# Code Review Walkthrough

This archived repository used to include a deployment narrative that described modules, screenshots, policies, and infrastructure that are not present in the tree. That narrative was removed so the public record matches the code.

Use this shorter walkthrough to review the design without creating Azure resources.

## 1. Establish the boundary

Start with `terraform/main.tf` and `terraform/variables.tf`. The root configuration creates three resource groups and uses one flat Terraform root. Feature flags control only Azure Firewall and Bastion.

The `policies/` directory contains examples. Nothing in `terraform/` creates or assigns those policies.

## 2. Trace the address plan

The defaults reserve:

| Network | Default range | Implemented contents |
| --- | --- | --- |
| Hub | `10.0.0.0/16` | Firewall, Bastion, gateway-reserved, and shared-services subnets |
| Workload spoke | `10.1.0.0/16` | Web, application, and data subnets; one VM in web |
| DMZ spoke | `10.2.0.0/16` | Public and WAF-reserved subnets; one VM in public |

Check that any replacement ranges do not overlap with each other or with connected networks.

## 3. Review segmentation before routing

`spoke-workload.tf` and `spoke-dmz.tf` define subnet NSGs. Treat the existing rules as examples, not safe defaults. In particular, review internet-sourced HTTP/HTTPS, broad hub access, database ports, and explicit deny priorities.

No Application Gateway or WAF is created, despite the reserved subnet and WAF-oriented rule names.

## 4. Follow the traffic path

`peering.tf` creates hub-to-spoke peerings in both directions. It does not create spoke-to-spoke peerings.

When `enable_azure_firewall` is true, each spoke receives routes for the default route and RFC 1918 ranges with Azure Firewall as the virtual-appliance next hop. `firewall.tf` then defines the firewall policy. Its broad application rule permits outbound HTTP and HTTPS to any FQDN; this needs narrowing for real use.

When the flag is false, the route tables and associations are absent. Review the resulting Azure system routes separately rather than assuming equivalent inspection.

## 5. Identify reserved versus active services

- `GatewaySubnet` is reserved, but there is no VPN or ExpressRoute gateway.
- `snet-waf` is reserved, but there is no Application Gateway or WAF.
- Bastion and Firewall are optional but default to enabled.
- The two VMs always exist and use password authentication.

## 6. Inspect telemetry and data handling

`logging.tf` configures Log Analytics, a flow-log storage account, NSG flow logs, and selected diagnostic settings. Verify current Azure support, data residency, retention, access controls, and storage-network restrictions before reuse.

## 7. Run static checks

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

These checks do not prove that an apply will succeed or that the network behaves as intended. A maintained version would add plan review, policy-as-code tests, connectivity tests, and post-destroy verification in a disposable subscription.

## 8. Treat deployment as a new project

There is no current deployment evidence to reproduce. If you choose to adapt this code, fork it, update the provider and deprecated resources, replace password authentication, narrow the rules, design state storage, estimate costs, and validate the result in a dedicated lab subscription.
