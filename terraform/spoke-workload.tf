# ---------------------------------------------------------------------------
# Workload spoke VNet
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "workload" {
  name                = "vnet-workload-${var.location}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  address_space       = var.workload_vnet_address_space
  dns_servers         = []
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Workload subnets
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "workload_web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = [var.workload_subnet_web]
}

resource "azurerm_subnet" "workload_app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = [var.workload_subnet_app]
}

resource "azurerm_subnet" "workload_data" {
  name                 = "snet-data"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = [var.workload_subnet_data]
}

# ---------------------------------------------------------------------------
# NSG — web tier
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "workload_web" {
  name                = "nsg-workload-web-${var.environment}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.common_tags
}

# Allow HTTP from internet (WAF / load balancer fronts this in production)
resource "azurerm_network_security_rule" "workload_web_allow_http" {
  name                        = "Allow-Inbound-HTTP"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.workload_subnet_web
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_web.name
}

resource "azurerm_network_security_rule" "workload_web_allow_https" {
  name                        = "Allow-Inbound-HTTPS"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.workload_subnet_web
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_web.name
}

# Allow inbound from internal RFC 1918 (hub management traffic, Bastion)
resource "azurerm_network_security_rule" "workload_web_allow_inbound_internal" {
  name                        = "Allow-Inbound-Internal"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = ["10.0.0.0/8"]
  destination_address_prefix  = var.workload_subnet_web
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_web.name
}

resource "azurerm_network_security_rule" "workload_web_deny_all_inbound" {
  name                        = "Deny-Inbound-All"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_web.name
}

# ---------------------------------------------------------------------------
# NSG — app tier
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "workload_app" {
  name                = "nsg-workload-app-${var.environment}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.common_tags
}

# Allow inbound from web tier only
resource "azurerm_network_security_rule" "workload_app_allow_from_web" {
  name                        = "Allow-Inbound-From-Web"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["8080", "8443"]
  source_address_prefix       = var.workload_subnet_web
  destination_address_prefix  = var.workload_subnet_app
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_app.name
}

# Allow inbound from hub (Bastion access, monitoring)
resource "azurerm_network_security_rule" "workload_app_allow_from_hub" {
  name                        = "Allow-Inbound-From-Hub"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.hub_vnet_address_space[0]
  destination_address_prefix  = var.workload_subnet_app
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_app.name
}

resource "azurerm_network_security_rule" "workload_app_deny_all_inbound" {
  name                        = "Deny-Inbound-All"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_app.name
}

# ---------------------------------------------------------------------------
# NSG — data tier
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "workload_data" {
  name                = "nsg-workload-data-${var.environment}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.common_tags
}

# Allow inbound from app tier only (SQL, PostgreSQL, etc.)
resource "azurerm_network_security_rule" "workload_data_allow_from_app" {
  name                        = "Allow-Inbound-From-App"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["1433", "5432", "3306", "6379"]
  source_address_prefix       = var.workload_subnet_app
  destination_address_prefix  = var.workload_subnet_data
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_data.name
}

# Allow inbound from hub (Bastion access, monitoring)
resource "azurerm_network_security_rule" "workload_data_allow_from_hub" {
  name                        = "Allow-Inbound-From-Hub"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.hub_vnet_address_space[0]
  destination_address_prefix  = var.workload_subnet_data
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_data.name
}

resource "azurerm_network_security_rule" "workload_data_deny_all_inbound" {
  name                        = "Deny-Inbound-All"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.workload_data.name
}

# ---------------------------------------------------------------------------
# NSG associations
# ---------------------------------------------------------------------------

resource "azurerm_subnet_network_security_group_association" "workload_web" {
  subnet_id                 = azurerm_subnet.workload_web.id
  network_security_group_id = azurerm_network_security_group.workload_web.id
}

resource "azurerm_subnet_network_security_group_association" "workload_app" {
  subnet_id                 = azurerm_subnet.workload_app.id
  network_security_group_id = azurerm_network_security_group.workload_app.id
}

resource "azurerm_subnet_network_security_group_association" "workload_data" {
  subnet_id                 = azurerm_subnet.workload_data.id
  network_security_group_id = azurerm_network_security_group.workload_data.id
}

# ---------------------------------------------------------------------------
# Route table — force all traffic through the hub firewall
# The firewall private IP is only available when enable_azure_firewall = true.
# When the firewall is disabled, no UDR is attached (traffic flows normally).
# ---------------------------------------------------------------------------

resource "azurerm_route_table" "workload" {
  count = var.enable_azure_firewall ? 1 : 0

  name                          = "rt-workload-${var.environment}"
  location                      = azurerm_resource_group.workload.location
  resource_group_name           = azurerm_resource_group.workload.name
  disable_bgp_route_propagation = true
  tags                          = local.common_tags
}

# Default route: all internet traffic → hub firewall
resource "azurerm_route" "workload_default" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-default-to-firewall"
  resource_group_name    = azurerm_resource_group.workload.name
  route_table_name       = azurerm_route_table.workload[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

# RFC 1918 inter-spoke route: all 10.x traffic (including DMZ) → hub firewall
resource "azurerm_route" "workload_rfc1918_10" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-rfc1918-10-to-firewall"
  resource_group_name    = azurerm_resource_group.workload.name
  route_table_name       = azurerm_route_table.workload[0].name
  address_prefix         = "10.0.0.0/8"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

resource "azurerm_route" "workload_rfc1918_172" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-rfc1918-172-to-firewall"
  resource_group_name    = azurerm_resource_group.workload.name
  route_table_name       = azurerm_route_table.workload[0].name
  address_prefix         = "172.16.0.0/12"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

resource "azurerm_route" "workload_rfc1918_192" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-rfc1918-192-to-firewall"
  resource_group_name    = azurerm_resource_group.workload.name
  route_table_name       = azurerm_route_table.workload[0].name
  address_prefix         = "192.168.0.0/16"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

# Route table associations
resource "azurerm_subnet_route_table_association" "workload_web" {
  count = var.enable_azure_firewall ? 1 : 0

  subnet_id      = azurerm_subnet.workload_web.id
  route_table_id = azurerm_route_table.workload[0].id
}

resource "azurerm_subnet_route_table_association" "workload_app" {
  count = var.enable_azure_firewall ? 1 : 0

  subnet_id      = azurerm_subnet.workload_app.id
  route_table_id = azurerm_route_table.workload[0].id
}

resource "azurerm_subnet_route_table_association" "workload_data" {
  count = var.enable_azure_firewall ? 1 : 0

  subnet_id      = azurerm_subnet.workload_data.id
  route_table_id = azurerm_route_table.workload[0].id
}

# ---------------------------------------------------------------------------
# Test VM — web tier
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "workload_vm" {
  name                = "nic-workload-vm-${var.environment}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig-workload-vm"
    subnet_id                     = azurerm_subnet.workload_web.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "workload_vm" {
  name                            = "vm-workload-web-${var.environment}"
  location                        = azurerm_resource_group.workload.location
  resource_group_name             = azurerm_resource_group.workload.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  tags                            = local.common_tags

  network_interface_ids = [
    azurerm_network_interface.workload_vm.id,
  ]

  os_disk {
    name                 = "osdisk-workload-vm-${var.environment}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Cloud-init: install nginx for basic connectivity tests
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx curl netcat-openbsd
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>Workload VM - Web Tier</h1>" > /var/www/html/index.html
  EOF
  )
}
