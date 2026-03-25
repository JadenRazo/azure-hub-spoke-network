# Walkthrough: Building the Enterprise Hub-and-Spoke Network

This walkthrough guides you through deploying the full architecture step by step. Each phase explains not just the commands to run but why the decisions were made — the reasoning behind subnet sizing, routing choices, and policy design. By the end, you will have a production-pattern Azure network running and will understand every component in it.

---

## Table of Contents

- [Phase 1: IP Address Planning](#phase-1-ip-address-planning)
- [Phase 2: Deploy Hub Network](#phase-2-deploy-hub-network)
- [Phase 3: Deploy Spoke Networks](#phase-3-deploy-spoke-networks)
- [Phase 4: Establish VNet Peering](#phase-4-establish-vnet-peering)
- [Phase 5: Configure Routing](#phase-5-configure-routing)
- [Phase 6: Deploy Test VMs and Validate](#phase-6-deploy-test-vms-and-validate)
- [Phase 7: DNS Configuration](#phase-7-dns-configuration)
- [Phase 8: Logging and Monitoring](#phase-8-logging-and-monitoring)
- [Phase 9: Governance with Azure Policy](#phase-9-governance-with-azure-policy)
- [Phase 10: Cleanup](#phase-10-cleanup)

---

## Phase 1: IP Address Planning

**Estimated time: 15 minutes**

Before a single resource gets created, the IP address plan needs to be locked down. This is not a step you want to revisit after deployment — re-addressing a production VNet means downtime and redeployment of every NIC, load balancer, and private endpoint inside it.

### Why Non-Overlapping Ranges Matter

Azure VNet peering has one hard requirement: the address spaces of any two peered VNets cannot overlap. If the hub is `10.0.0.0/16` and you peer it to a spoke that also uses `10.0.0.0/16`, Azure will reject the peering outright. The same rule applies to on-premises networks connected via VPN or ExpressRoute — if your datacenter uses `10.1.0.0/16` and you later try to peer a spoke using that range, you will have a conflict that requires VM redeployment to resolve.

The plan I used for this project:

| VNet | Address Space | Purpose |
|------|--------------|---------|
| Hub | 10.0.0.0/16 | Shared network services |
| Spoke 1 (Workload) | 10.1.0.0/16 | Application workloads |
| Spoke 2 (DMZ) | 10.2.0.0/16 | Public-facing and WAF tier |
| Reserved (future Spoke 3) | 10.3.0.0/16 | Unallocated, reserved |
| On-premises (simulated) | 192.168.0.0/16 | Would connect via GW subnet |

Each VNet gets a `/16`, which gives 65,536 addresses. That is far more than any single spoke needs today, but the size is intentional — it leaves room to add subnets later without running out of space or having to expand the address space (which, while possible, requires careful coordination with peered VNets).

### Hub Subnet Plan

The hub subnets use specific names that Azure requires for its managed services:

| Subnet | CIDR | Required Name | Reason for Size |
|--------|------|---------------|-----------------|
| Azure Firewall | 10.0.1.0/26 | `AzureFirewallSubnet` | `/26` minimum required by Azure |
| Azure Bastion | 10.0.2.0/26 | `AzureBastionSubnet` | `/26` minimum required by Azure |
| VPN/ER Gateway | 10.0.3.0/27 | `GatewaySubnet` | `/27` minimum recommended by Azure |
| Shared Services | 10.0.4.0/24 | `SharedServicesSubnet` | 251 usable hosts for DNS/monitoring VMs |

The `/26` requirement for AzureFirewallSubnet and AzureBastionSubnet is enforced by the Azure control plane. If you try to deploy with a smaller prefix, the deployment fails. I used `/26` (64 addresses) rather than the minimum to leave breathing room for internal Azure management addresses.

### Spoke 1 Subnet Plan

| Subnet | CIDR | Tier |
|--------|------|------|
| web-subnet | 10.1.1.0/24 | Web tier (load balancers, web VMs) |
| app-subnet | 10.1.2.0/24 | Application tier (app servers) |
| data-subnet | 10.1.3.0/24 | Data tier (DB VMs, private endpoints) |

Three-tier segmentation is a classic pattern. Even if your workload does not strictly separate these layers today, having dedicated subnets means you can apply different NSG rules per tier. The web tier might allow inbound 443 from the internet (via the WAF in Spoke 2), while the data tier blocks all inbound except from the app-subnet range.

### Spoke 2 Subnet Plan

| Subnet | CIDR | Tier |
|--------|------|------|
| public-subnet | 10.2.1.0/24 | Public-facing services (Application Gateway) |
| waf-subnet | 10.2.2.0/24 | WAF / Application Gateway backend subnet |

The DMZ spoke exists specifically for components that accept traffic originating from the internet. Keeping these in a separate VNet (rather than a separate subnet in the workload VNet) enforces a hard boundary — traffic from the internet can never reach the workload VNet directly, even by misconfigured NSG.

### Verify Your Plan Before Continuing

Before running any Terraform, open `terraform/terraform.tfvars` and confirm the CIDR values match your environment. If you have an existing on-premises network or Azure environment that already uses part of the `10.x.x.x` space, update the spoke ranges to something in `172.16.0.0/12` or `192.168.0.0/16` instead.

```bash
# Quick sanity check — verify no range overlaps using ipcalc
# Install if needed: sudo apt-get install -y ipcalc
ipcalc 10.0.0.0/16
ipcalc 10.1.0.0/16
ipcalc 10.2.0.0/16
```

![IP address plan spreadsheet view](docs/screenshots/01-ip-plan.png)

---

## Phase 2: Deploy Hub Network

**Estimated time: 30 minutes**

The hub is deployed first because the spokes depend on it — specifically, the firewall private IP needs to exist before you can configure spoke UDRs to point at it.

### Step 1: Authenticate to Azure

```bash
az login
az account show --query "{subscription:name, id:id}" -o table
```

Make sure the correct subscription is active. If you have multiple subscriptions:

```bash
az account set --subscription "<subscription-id-or-name>"
```

### Step 2: Create the Resource Group

```bash
az group create \
  --name rg-hub-spoke-network \
  --location eastus2 \
  --tags "managed-by=terraform" "project=hub-spoke-network" "environment=lab"
```

I use `eastus2` throughout this project. It is one of the lower-cost regions for Azure Firewall and has good availability of B-series VMs for lab testing.

### Step 3: Bootstrap Terraform Remote State

Terraform state should never live on your local machine for any project that could be used by more than one person or machine. The bootstrap script creates an Azure Storage account and container for the state backend:

```bash
bash scripts/bootstrap-state.sh
```

This script does the following:
1. Creates a storage account with a generated unique name
2. Creates a blob container named `tfstate`
3. Outputs the storage account name and access key
4. Writes a `backend.tf` file in the `terraform/` directory with the correct backend configuration

After the script runs, open `terraform/backend.tf` and confirm it looks correct:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "<generated-name>"
    container_name       = "tfstate"
    key                  = "hub-spoke-network.tfstate"
  }
}
```

### Step 4: Initialize Terraform

```bash
cd terraform
terraform init
```

On the first run, `terraform init` downloads the AzureRM provider and configures the remote backend. You should see output confirming both actions:

```
Initializing the backend...
Successfully configured the backend "azurerm"!

Initializing provider plugins...
- Finding hashicorp/azurerm versions matching "~> 3.90"...
- Installing hashicorp/azurerm v3.90.0...
```

### Step 5: Plan and Deploy the Hub

```bash
terraform plan -target=module.hub -out=hub.tfplan
terraform apply hub.tfplan
```

Targeting the hub module specifically ensures the hub resources exist before the spokes try to reference them. The hub module provisions:

- **Hub VNet** with the address space `10.0.0.0/16`
- **Four subnets** (Firewall, Bastion, Gateway, Shared Services)
- **Azure Firewall Standard** with a public IP and threat intelligence enabled in Alert mode
- **Azure Bastion Standard** with a dedicated public IP
- **Log Analytics Workspace** with 30-day retention (sufficient for a lab, use 90+ days in production)
- **NSG for SharedServicesSubnet** (Firewall and Bastion subnets do not support NSGs)

Azure Firewall takes approximately 8–10 minutes to provision. The Bastion takes 3–5 minutes. The overall hub deployment runs 12–18 minutes.

While waiting, examine the firewall output in the console. You will need the **firewall private IP** in Phase 5. Terraform stores it as an output:

```bash
terraform output hub_firewall_private_ip
```

It should be `10.0.1.4` — Azure assigns the fourth IP in any subnet (the first three are reserved for Azure's infrastructure).

### Step 6: Review What Was Created

```bash
az network vnet show \
  --resource-group rg-hub-spoke-network \
  --name vnet-hub \
  --query "{name:name, addressSpace:addressSpace.addressPrefixes, subnets:subnets[].{name:name,prefix:addressPrefix}}" \
  -o json
```

```bash
az network firewall show \
  --resource-group rg-hub-spoke-network \
  --name fw-hub \
  --query "{name:name, provisioningState:provisioningState, privateIp:ipConfigurations[0].privateIpAddress}" \
  -o table
```

![Hub VNet and subnets in Azure Portal](docs/screenshots/02-hub-vnet-portal.png)

![Azure Firewall provisioned in hub](docs/screenshots/03-firewall-deployed.png)

---

## Phase 3: Deploy Spoke Networks

**Estimated time: 20 minutes**

With the hub in place, both spokes can be deployed. Each spoke gets its own VNet, subnets, and NSGs. At this stage, the spokes are isolated — no peering exists yet, so there is no connectivity between them or to the hub.

### Step 1: Deploy Spoke 1 (Workload VNet)

```bash
terraform plan -target=module.spoke_workload -out=spoke1.tfplan
terraform apply spoke1.tfplan
```

The workload spoke creates:

- **Spoke 1 VNet**: `10.1.0.0/16`
- **web-subnet**: `10.1.1.0/24` with NSG `nsg-web`
- **app-subnet**: `10.1.2.0/24` with NSG `nsg-app`
- **data-subnet**: `10.1.3.0/24` with NSG `nsg-data`

### Step 2: Review the NSG Rules for the Workload Spoke

The NSG for the web tier allows:
- **Inbound 443** from `10.2.0.0/16` (the DMZ spoke, specifically the WAF subnet) — this is where production HTTPS traffic arrives after being inspected by the WAF
- **Inbound 22/3389** from the Bastion subnet `10.0.2.0/26` — allows SSH/RDP from Bastion only, no public access
- **Outbound to app-subnet** on application ports
- **Deny all other inbound** (the implicit NSG default)

The NSG for the data tier is more restrictive:
- **Inbound on database ports** (1433 for SQL, 5432 for PostgreSQL, etc.) only from `10.1.2.0/24` (the app subnet)
- **Inbound 22/3389** from the Bastion subnet only
- **No inbound from the web tier at all**

This separation is important. Even if someone compromises a web server, the NSG prevents that VM from connecting directly to the database subnet. The attacker would have to pivot through the app tier first, which creates additional detection opportunities.

```bash
az network nsg rule list \
  --resource-group rg-hub-spoke-network \
  --nsg-name nsg-data \
  --query "[].{name:name, priority:priority, direction:direction, access:access, sourceAddr:sourceAddressPrefix, destAddr:destinationAddressPrefix, destPort:destinationPortRange}" \
  -o table
```

### Step 3: Deploy Spoke 2 (DMZ VNet)

```bash
terraform plan -target=module.spoke_dmz -out=spoke2.tfplan
terraform apply spoke2.tfplan
```

The DMZ spoke creates:

- **Spoke 2 VNet**: `10.2.0.0/16`
- **public-subnet**: `10.2.1.0/24` with NSG `nsg-public`
- **waf-subnet**: `10.2.2.0/24` with NSG `nsg-waf`

The `nsg-public` NSG allows inbound 80 and 443 from `Internet` (the Azure service tag that encompasses all public IP space). This is intentional — the DMZ exists to accept public traffic. The WAF/Application Gateway in this subnet inspects that traffic before it ever touches the workload VNet.

### Step 4: Verify Spoke Isolation

At this point, the spokes have no route to each other or to the hub. This is easy to verify conceptually — no peering has been created yet. You can confirm:

```bash
az network vnet peering list \
  --resource-group rg-hub-spoke-network \
  --vnet-name vnet-spoke-workload \
  -o table
# Expected: empty output (no peerings)
```

![Both spoke VNets deployed](docs/screenshots/04-spoke-vnets-portal.png)

---

## Phase 4: Establish VNet Peering

**Estimated time: 15 minutes**

VNet peering is the connectivity fabric of the hub-and-spoke model. Peerings connect the hub to each spoke in both directions — each peering is directional, so creating `hub → spoke1` also requires creating `spoke1 → hub`.

### Why Not Peer Spokes Directly to Each Other?

The whole value of hub-and-spoke is that the hub is the choke point. If you peer Spoke 1 directly to Spoke 2, traffic between them bypasses the firewall entirely. You lose centralized inspection, logging, and policy enforcement for that traffic. In large organizations with dozens of spokes, maintaining direct peerings between all of them also creates an O(n²) management problem — every new spoke needs a peering to every existing spoke. The hub model keeps it O(n): every new spoke just needs one peering to the hub.

### Step 1: Deploy the Peerings

```bash
terraform plan -target=module.peering -out=peering.tfplan
terraform apply peering.tfplan
```

The peering module creates four peering resources (two per spoke, one in each direction):

| Peering Resource | Allow Forwarded Traffic | Allow Gateway Transit | Use Remote Gateways |
|------------------|------------------------|----------------------|---------------------|
| hub → spoke1 | true | true | false |
| spoke1 → hub | true | false | true |
| hub → spoke2 | true | true | false |
| spoke2 → hub | true | false | true |

These settings deserve explanation:

- **Allow Forwarded Traffic**: Allows traffic that was *not* originated from the peered VNet to pass through the peering. This is required for the firewall scenario — traffic from `10.1.0.0/16` (Spoke 1) that is forwarded through the hub firewall needs to exit via the `hub → spoke2` peering. Without this setting, that forwarded traffic is dropped.

- **Allow Gateway Transit** (hub side): Allows the hub's VPN/ExpressRoute gateway to be used by peered VNets. This means when Spoke 1 VMs need to reach on-premises resources, their traffic can traverse the peering to the hub and then exit via the gateway — without each spoke needing its own gateway.

- **Use Remote Gateways** (spoke side): The complement to gateway transit. This tells the spoke VNet to use the hub's gateway for on-premises connectivity. Note: this setting requires that the hub actually has a gateway deployed (or you must set it to false and leave on-premises connectivity out of scope for this lab).

### Step 2: Verify Peering Status

```bash
az network vnet peering list \
  --resource-group rg-hub-spoke-network \
  --vnet-name vnet-hub \
  --query "[].{name:name, peeringState:peeringState, remoteVnet:remoteVirtualNetwork.id}" \
  -o table
```

Both peerings should show `Connected`. If you see `Initiated`, the return peering from the spoke side has not been created yet (or is still provisioning). A peering in `Initiated` state carries no traffic.

```bash
az network vnet peering list \
  --resource-group rg-hub-spoke-network \
  --vnet-name vnet-spoke-workload \
  --query "[].{name:name, peeringState:peeringState, remoteVnet:remoteVirtualNetwork.id}" \
  -o table
```

![VNet peerings showing Connected status](docs/screenshots/05-vnet-peering-connected.png)

### What Peering Does NOT Do

Peering establishes connectivity at the network layer, but it does not automatically route traffic correctly for the hub-and-spoke pattern. At this point, VMs in Spoke 1 can reach the hub's address space directly via the peering — but traffic destined for Spoke 2 would be dropped because the Spoke 1 VNet has no route for `10.2.0.0/16`. That routing is what Phase 5 sets up.

---

## Phase 5: Configure Routing

**Estimated time: 20 minutes**

Routing is where the hub-and-spoke model goes from "VNets that are peered" to "a centrally enforced network topology." Without UDRs, each VNet uses Azure's system routes, which would send traffic directly to the destination via the most direct peering — bypassing the firewall.

### How Azure System Routes Work (and Why We Override Them)

When you peer two VNets, Azure automatically creates system routes in each VNet for the other's address space. After peering Hub to Spoke 1, Spoke 1 gets a system route: `10.0.0.0/16 → VNet peering`. That is correct — traffic from Spoke 1 to the hub should go directly through the peering.

But Spoke 1 does *not* automatically get a route for `10.2.0.0/16` (Spoke 2's range). And even if it did (because some advanced routing propagation was configured), the default behavior would be to route directly — no firewall inspection.

UDRs override system routes. By creating a route table with:
- `0.0.0.0/0` → Next hop: Azure Firewall private IP (`10.0.1.4`)
- `10.1.0.0/16` → Next hop: Azure Firewall private IP (for Spoke 2 to reach Spoke 1)
- `10.2.0.0/16` → Next hop: Azure Firewall private IP (for Spoke 1 to reach Spoke 2)

...and associating that route table with every spoke subnet, all traffic (internet-bound and inter-spoke) flows through the firewall before reaching its destination.

### Step 1: Deploy the Route Tables

```bash
terraform plan -target=module.routing -out=routing.tfplan
terraform apply routing.tfplan
```

The routing module creates two route tables:

**rt-spoke-workload** (associated with all subnets in Spoke 1):
```
Destination         Next Hop Type           Next Hop IP
0.0.0.0/0           VirtualAppliance        10.0.1.4
10.2.0.0/16         VirtualAppliance        10.0.1.4
```

**rt-spoke-dmz** (associated with all subnets in Spoke 2):
```
Destination         Next Hop Type           Next Hop IP
0.0.0.0/0           VirtualAppliance        10.0.1.4
10.1.0.0/16         VirtualAppliance        10.0.1.4
```

Note that the route to `10.0.0.0/16` (the hub itself) is intentionally absent. Traffic from the spokes to the hub (e.g., to the Bastion, DNS server, or Shared Services subnet) routes directly through the peering. Only inter-spoke and internet traffic needs to pass through the firewall.

### Step 2: Configure Azure Firewall Rules

The firewall needs explicit allow rules or it drops everything by default. The Terraform configuration deploys three rule collections:

**Network Rule Collection — inter-spoke:**
```
Name: allow-spoke-to-spoke
Priority: 200
Rules:
  - Spoke1-to-Spoke2: src 10.1.0.0/16, dst 10.2.0.0/16, protocol TCP, ports 80,443,8080
  - Spoke2-to-Spoke1: src 10.2.0.0/16, dst 10.1.0.0/16, protocol TCP, ports 80,443,8080
```

**Network Rule Collection — internet egress:**
```
Name: allow-internet-egress
Priority: 300
Rules:
  - Allow-HTTPS-Out: src 10.1.0.0/8, dst *, protocol TCP, port 443
```

**Application Rule Collection — FQDN-based egress:**
```
Name: allow-update-endpoints
Priority: 400
Rules:
  - Allow-Ubuntu-Updates: src 10.1.0.0/8, FQDNs: *.ubuntu.com, *.launchpad.net
  - Allow-Azure-Services: src 10.1.0.0/8, FQDNs: *.azure.com, *.microsoft.com
```

Application rules use FQDN inspection (TLS inspection requires Azure Firewall Premium). For a lab, the network rules are sufficient to test connectivity.

### Step 3: Verify Route Table Associations

```bash
az network route-table show \
  --resource-group rg-hub-spoke-network \
  --name rt-spoke-workload \
  --query "{routes:routes[].{name:name,prefix:addressPrefix,nextHopType:nextHopType,nextHopIp:nextHopIpAddress}, subnets:subnets[].id}" \
  -o json
```

Confirm that all three spoke subnets (web, app, data) appear in the `subnets` list.

![Route table with UDRs pointing to firewall](docs/screenshots/06-route-table-udrs.png)

### Step 4: Verify Effective Routes on a NIC

Once test VMs are deployed (Phase 6), you can check effective routes on a NIC to confirm the UDR overrides are working:

```bash
az network nic show-effective-route-table \
  --resource-group rg-hub-spoke-network \
  --name <nic-name> \
  -o table
```

Look for the `0.0.0.0/0` entry — its `nextHopType` should be `VirtualAppliance` and the next hop IP should be `10.0.1.4`. If it shows `Internet`, the route table is not correctly associated.

---

## Phase 6: Deploy Test VMs and Validate

**Estimated time: 20 minutes**

With the network fully configured, I deploy two small VMs — one in the workload spoke and one in the DMZ spoke — to validate that routing, NSGs, and the firewall are working correctly.

### Step 1: Deploy the Test VMs

```bash
cd terraform/test-vms
terraform init
terraform plan -out=vms.tfplan
terraform apply vms.tfplan
```

Each VM is a `Standard_B1s` (1 vCPU, 1 GiB RAM) running Ubuntu 22.04 LTS. They have **no public IP addresses**. The only way to access them is through Azure Bastion. This is intentional — it validates that Bastion works and demonstrates that production VMs in this architecture do not need public IPs.

The VMs are placed in:
- `vm-spoke1-web`: Spoke 1, web-subnet (`10.1.1.x`)
- `vm-spoke2-pub`: Spoke 2, public-subnet (`10.2.1.x`)

### Step 2: Connect via Azure Bastion

In the Azure Portal, navigate to the VM `vm-spoke1-web` and click **Connect → Bastion**. Enter the username and password set in `terraform.tfvars`. Bastion establishes an RDP or SSH session directly in the browser over HTTPS 443 — no VPN client, no public IP on the VM.

This works because Azure Bastion in the hub VNet can reach VMs in the peered spokes. The `Allow Forwarded Traffic` setting on the peering ensures Bastion's traffic (sourced from `10.0.2.x`) can traverse the peering and reach `10.1.1.x`.

![Azure Bastion connection to spoke VM](docs/screenshots/07-bastion-connection.png)

### Step 3: Run the Connectivity Test Script

Once connected to `vm-spoke1-web`, download and run the test script:

```bash
curl -O https://raw.githubusercontent.com/<your-username>/azure-hub-spoke-network/main/scripts/test-connectivity.sh
chmod +x test-connectivity.sh
sudo ./test-connectivity.sh
```

Or, if you are running the script from within the repo on your local machine, copy it via Bastion's file transfer feature.

The script tests:

```bash
#!/bin/bash
# test-connectivity.sh — Run from a spoke VM to validate connectivity

echo "=== Testing internet connectivity (should succeed via Firewall SNAT) ==="
curl -s --max-time 5 https://ifconfig.me && echo " [PASS]" || echo " [FAIL]"

echo "=== Testing DNS resolution ==="
nslookup vm-spoke2-pub.internal.contoso.com && echo " [PASS]" || echo " [FAIL]"

echo "=== Testing spoke-to-spoke connectivity (should succeed if Firewall rule allows) ==="
nc -zv 10.2.1.4 80 2>&1 && echo " [PASS]" || echo " [FAIL]"

echo "=== Testing blocked port (should fail — no Firewall rule for 8443) ==="
nc -zv 10.2.1.4 8443 2>&1 && echo " [UNEXPECTED PASS]" || echo " [EXPECTED FAIL]"

echo "=== Testing hub shared services connectivity ==="
nc -zv 10.0.4.4 53 2>&1 && echo " [PASS]" || echo " [FAIL]"
```

Expected results:
- Internet connectivity: PASS (Firewall SNAT translates the private IP to the firewall's public IP)
- DNS resolution: PASS (after Phase 7 is complete)
- Spoke-to-spoke TCP 80: PASS (Firewall network rule allows it)
- TCP 8443: EXPECTED FAIL (no Firewall rule exists for this port — demonstrates default-deny)

![Connectivity test output from spoke VM](docs/screenshots/08-connectivity-test.png)

### Step 4: Verify Traffic Is Flowing Through the Firewall

In the Azure Portal, navigate to the Azure Firewall resource and open **Logs**. Run this KQL query to see traffic that was processed by the firewall:

```kql
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| where TimeGenerated > ago(15m)
| project TimeGenerated, msg_s
| order by TimeGenerated desc
| take 50
```

You should see entries for the connections made by the test script — confirming that spoke-to-spoke traffic is actually transiting the firewall rather than bypassing it.

---

## Phase 7: DNS Configuration

**Estimated time: 10 minutes**

Without private DNS, VMs in this network can only reach each other by IP address. Private DNS zones provide human-readable names within the virtual network environment and are essential for any workload that uses service discovery, certificates, or connection strings that reference hostnames.

### Why Private DNS Zones vs. Custom DNS Servers

I chose Azure Private DNS zones rather than deploying a DNS server VM in the shared services subnet. Private DNS zones are:
- **Serverless** — no VM to patch or monitor
- **Highly available** — backed by Azure's infrastructure, 99.99% SLA
- **Integrated** — VMs auto-register their records when joined to a zone-linked VNet

For a more complex enterprise environment (on-premises DNS forwarding, AD domain, split-horizon DNS), a DNS server in the shared services subnet with conditional forwarders would be the right approach. For this project, managed Private DNS zones are sufficient.

### Step 1: Deploy the Private DNS Zone

```bash
terraform plan -target=module.dns -out=dns.tfplan
terraform apply dns.tfplan
```

This creates:

- **Private DNS Zone**: `internal.contoso.com`
- **VNet link for Hub**: Links the zone to `vnet-hub` with auto-registration disabled (the hub does not have application VMs)
- **VNet link for Spoke 1**: Links to `vnet-spoke-workload` with auto-registration **enabled** (VMs register automatically)
- **VNet link for Spoke 2**: Links to `vnet-spoke-dmz` with auto-registration **enabled**

Auto-registration creates `<vm-name>.internal.contoso.com` A records for every VM in the linked VNet. When a VM is deleted, the record is removed automatically.

### Step 2: Verify DNS Resolution

Connect to `vm-spoke1-web` via Bastion and test:

```bash
# Should resolve to 10.2.1.4 (or whatever IP vm-spoke2-pub received)
nslookup vm-spoke2-pub.internal.contoso.com

# Reverse lookup
nslookup 10.2.1.4
```

```bash
# List all auto-registered records
az network private-dns record-set list \
  --resource-group rg-hub-spoke-network \
  --zone-name internal.contoso.com \
  --query "[].{name:name, type:type, records:aRecords[].ipv4Address}" \
  -o table
```

![Private DNS zone records showing auto-registered VMs](docs/screenshots/09-private-dns-records.png)

### Step 3: How the Resolution Works

When `vm-spoke1-web` issues a DNS query for `vm-spoke2-pub.internal.contoso.com`:
1. The VM sends the query to `168.63.129.16` (Azure's magic DNS resolver — it is in every VNet automatically)
2. Azure DNS checks if the queried zone (`internal.contoso.com`) is linked to the VM's VNet
3. It finds the link between `internal.contoso.com` and `vnet-spoke-workload`
4. It returns the A record for `vm-spoke2-pub` from the auto-registered records

No DNS server is involved — Azure handles it entirely within its fabric. This is why the IP `168.63.129.16` must be reachable from all subnets. It is a platform-level IP, not an actual VM, so NSG rules should allow UDP/TCP 53 to that address (or allow DNS via the `AzurePlatformDNS` service tag).

---

## Phase 8: Logging and Monitoring

**Estimated time: 15 minutes**

A network without observability is a network you cannot operate. Every component in this architecture sends its logs to the central Log Analytics workspace deployed with the hub.

### Step 1: Enable NSG Flow Logs

NSG flow logs capture every accepted and denied connection at the NSG level, including source/destination IP, port, protocol, and whether the packet was allowed or denied. This is invaluable for security investigations and for fine-tuning NSG rules.

```bash
# Get the storage account ID for flow log storage
STORAGE_ID=$(az storage account show \
  --resource-group rg-hub-spoke-network \
  --name <your-storage-account> \
  --query id -o tsv)

# Enable flow logs on the web tier NSG
az network watcher flow-log create \
  --location eastus2 \
  --name flowlog-nsg-web \
  --nsg nsg-web \
  --resource-group rg-hub-spoke-network \
  --storage-account $STORAGE_ID \
  --workspace $(az monitor log-analytics workspace show \
    --resource-group rg-hub-spoke-network \
    --workspace-name law-hub-spoke \
    --query id -o tsv) \
  --retention 30 \
  --traffic-analytics true \
  --traffic-analytics-interval 10
```

Terraform handles this in the `module.logging` module — the commands above are shown for context. The `--traffic-analytics true` flag enables Traffic Analytics, which aggregates flow log data and provides a topology view and anomaly detection on top of raw flow logs.

### Step 2: Verify Diagnostic Settings

Confirm that the firewall and Bastion are sending diagnostics to Log Analytics:

```bash
az monitor diagnostic-settings list \
  --resource $(az network firewall show \
    --resource-group rg-hub-spoke-network \
    --name fw-hub --query id -o tsv) \
  --query "[].{name:name, workspaceId:workspaceId}" \
  -o table
```

### Step 3: Run KQL Queries

Connect to the Log Analytics workspace in the Azure Portal (**Monitor → Log Analytics workspaces → law-hub-spoke → Logs**) and run the following queries.

**All denied connections in the last hour:**
```kql
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| where msg_s has "Deny"
| where TimeGenerated > ago(1h)
| parse msg_s with * "from " SourceIP ":" SourcePort " to " DestinationIP ":" DestinationPort "." *
| project TimeGenerated, SourceIP, SourcePort, DestinationIP, DestinationPort
| order by TimeGenerated desc
```

**Top talkers by source IP in the last 24 hours:**
```kql
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| where TimeGenerated > ago(24h)
| parse msg_s with * "from " SourceIP ":" * " to " *
| summarize ConnectionCount=count() by SourceIP
| order by ConnectionCount desc
| take 20
```

**NSG flow log summary — allowed vs denied by subnet:**
```kql
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| summarize AllowedFlows=countif(FlowStatus_s == "A"), DeniedFlows=countif(FlowStatus_s == "D") by Subnet=SubNet_s
| order by DeniedFlows desc
```

**Bastion session audit log:**
```kql
AzureDiagnostics
| where ResourceType == "BASTIONHOSTS"
| where Category == "BastionAuditLogs"
| project TimeGenerated, UserName_s, UserIPAddress_s, Protocol_s, TargetResourceId_s, SessionDurationInMins_d
| order by TimeGenerated desc
```

![Log Analytics KQL query results showing firewall denies](docs/screenshots/10-log-analytics-kql.png)

### Step 4: Create an Alert

Create an alert that fires when more than 50 denied connections occur within 5 minutes — this could indicate a port scan or misconfigured application:

```bash
az monitor scheduled-query create \
  --resource-group rg-hub-spoke-network \
  --name "alert-excessive-firewall-denies" \
  --scopes $(az monitor log-analytics workspace show \
    --resource-group rg-hub-spoke-network \
    --workspace-name law-hub-spoke \
    --query id -o tsv) \
  --condition "count > 50" \
  --condition-query "AzureDiagnostics | where Category == 'AzureFirewallNetworkRule' | where msg_s has 'Deny'" \
  --evaluation-frequency 5m \
  --window-size 5m \
  --severity 2 \
  --description "Fires when more than 50 firewall deny events occur in 5 minutes"
```

---

## Phase 9: Governance with Azure Policy

**Estimated time: 15 minutes**

Azure Policy provides guardrails at the control plane level — it can prevent non-compliant resources from being created, audit existing resources, and automatically remediate certain types of drift. For a network architecture like this, policy enforces the rules that keep the design intact over time.

### What We Are Enforcing

The policies deployed in this phase enforce:

1. **NSGs must be attached to all subnets** — Prevents subnets from existing without network-level access control
2. **Resources must be in approved regions** — Restricts all new resources to `eastus2` and `eastus` to prevent accidental deployment to expensive regions
3. **Required tags on all resources** — Enforces `environment`, `managed-by`, and `project` tags on every resource
4. **Azure Bastion must exist in the hub VNet** — Audits to ensure the Bastion resource exists; alerts if it is deleted
5. **VMs must not have public IP addresses** — Prevents operators from assigning public IPs to VMs in spoke VNets (they should always use Bastion)

### Step 1: Deploy Policy Definitions and Assignments

```bash
terraform plan -target=module.policy -out=policy.tfplan
terraform apply policy.tfplan
```

The custom policy definitions live in `policies/azure-policy-definitions/`. The Terraform module deploys them as `azurerm_policy_definition` resources and then creates `azurerm_resource_group_policy_assignment` resources to assign them to the project resource group.

### Step 2: Review the No-Public-IP Policy Definition

Open `policies/azure-policy-definitions/deny-public-ip-on-vm.json`. The `policyRule` evaluates the `ipConfigurations` on network interfaces and denies creation if any configuration has a non-null `publicIPAddress` reference:

```json
{
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Network/networkInterfaces"
        },
        {
          "count": {
            "field": "Microsoft.Network/networkInterfaces/ipConfigurations[*].publicIPAddress.id"
          },
          "greater": 0
        }
      ]
    },
    "then": {
      "effect": "Deny"
    }
  }
}
```

This policy operates in `Deny` mode, which means attempting to create a VM NIC with a public IP will fail at the ARM API level — before the resource is ever created. This is stronger than an audit policy, which only reports after the fact.

### Step 3: Test the Policy

Try to create a VM with a public IP (it should be denied):

```bash
az vm create \
  --resource-group rg-hub-spoke-network \
  --name vm-policy-test \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --vnet-name vnet-spoke-workload \
  --subnet web-subnet \
  --public-ip-address test-pip \
  --admin-username azureuser \
  --admin-password "TestPassword123!" \
  --no-wait
```

Expected output:

```
(RequestDisallowedByPolicy) Resource 'test-pip' was disallowed by policy. Policy identifiers: ...
```

![Azure Policy compliance dashboard](docs/screenshots/11-policy-compliance.png)

### Step 4: View Compliance State

```bash
az policy state list \
  --resource-group rg-hub-spoke-network \
  --query "[].{resource:resourceId, policy:policyDefinitionName, compliance:complianceState}" \
  -o table
```

Resources that were deployed before the policy assignment may show as `NonCompliant`. For example, if any subnet was created without an NSG, the NSG-required policy will flag it. Use the remediation task feature to bring those resources into compliance:

```bash
az policy remediation create \
  --resource-group rg-hub-spoke-network \
  --name remediate-nsg-requirement \
  --policy-assignment <assignment-id>
```

Note: Remediation only works for policies with `deployIfNotExists` or `modify` effects. The `deny` and `audit` effects cannot be auto-remediated because they do not define a deployment template.

---

## Phase 10: Cleanup

When you are done with the lab environment, tear everything down to avoid ongoing charges. Azure Firewall and Bastion are the most expensive resources in this architecture — leaving them running overnight adds roughly $40–50 USD to your bill.

### Step 1: Destroy Test VMs First

```bash
cd /root/azure-hub-spoke-network/terraform/test-vms
terraform destroy
```

Confirm with `yes`. VM deletion takes 1–2 minutes.

### Step 2: Destroy the Core Infrastructure

```bash
cd /root/azure-hub-spoke-network/terraform
terraform destroy
```

Terraform will present the full list of resources to be destroyed. Review it, then confirm with `yes`.

Azure Firewall deprovisions in approximately 8–10 minutes. The total destroy operation takes 15–20 minutes. Do not interrupt the process — a partially destroyed environment can leave orphaned resources that continue to accrue charges and cannot be re-created without manual cleanup.

### Step 3: Verify No Resources Remain

```bash
az resource list \
  --resource-group rg-hub-spoke-network \
  --query "[].{name:name, type:type}" \
  -o table
```

The output should be empty. If any resources remain, they were likely created outside of Terraform (e.g., via the Portal during testing) and must be deleted manually:

```bash
az group delete \
  --name rg-hub-spoke-network \
  --yes \
  --no-wait
```

The `--no-wait` flag lets the deletion run in the background. The resource group and everything in it will be gone within a few minutes.

### Step 4: Clean Up Remote State (Optional)

If you are done with the project entirely, remove the Terraform state storage account:

```bash
bash /root/azure-hub-spoke-network/scripts/cleanup-state.sh
```

Or manually:

```bash
az group delete --name rg-tfstate --yes --no-wait
```

After cleanup, your Azure subscription will have no remaining resources from this project and no ongoing charges.

---

## Summary

This walkthrough covered the full lifecycle of an enterprise hub-and-spoke network in Azure — from IP address planning through cleanup. The architecture demonstrates patterns that appear in production Azure environments at organizations of all sizes: centralized firewall inspection, Bastion-only VM access, private DNS for internal resolution, NSG micro-segmentation, and Policy-enforced guardrails.

The key design decisions to carry forward from this project:

- **Lock down your IP plan before you deploy.** Re-addressing VNets is painful and disruptive.
- **All inter-spoke traffic should transit the hub firewall.** UDRs enforce this; verify with effective route checks.
- **No VM should have a public IP.** Bastion in the hub covers all spoke VMs with a single managed service.
- **Centralize your logs.** A single Log Analytics workspace for all network diagnostics makes investigation and alerting significantly simpler than per-resource log buckets.
- **Use Policy to protect the architecture over time.** Guardrails prevent configuration drift that would undermine the security model.
