# ---------------------------------------------------------------------------
# DMZ spoke VNet
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "dmz" {
  name                = "vnet-dmz-${var.location}"
  location            = azurerm_resource_group.dmz.location
  resource_group_name = azurerm_resource_group.dmz.name
  address_space       = var.dmz_vnet_address_space
  dns_servers         = []
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# DMZ subnets
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "dmz_public" {
  name                 = "snet-public"
  resource_group_name  = azurerm_resource_group.dmz.name
  virtual_network_name = azurerm_virtual_network.dmz.name
  address_prefixes     = [var.dmz_subnet_public]
}

resource "azurerm_subnet" "dmz_waf" {
  name                 = "snet-waf"
  resource_group_name  = azurerm_resource_group.dmz.name
  virtual_network_name = azurerm_virtual_network.dmz.name
  address_prefixes     = [var.dmz_subnet_waf]
}

# ---------------------------------------------------------------------------
# NSG — public subnet
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "dmz_public" {
  name                = "nsg-dmz-public-${var.environment}"
  location            = azurerm_resource_group.dmz.location
  resource_group_name = azurerm_resource_group.dmz.name
  tags                = local.common_tags
}

# Allow HTTP/HTTPS inbound from internet
resource "azurerm_network_security_rule" "dmz_public_allow_http" {
  name                        = "Allow-Inbound-HTTP"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.dmz_subnet_public
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_public.name
}

resource "azurerm_network_security_rule" "dmz_public_allow_https" {
  name                        = "Allow-Inbound-HTTPS"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.dmz_subnet_public
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_public.name
}

# Allow inbound from hub (Bastion, monitoring)
resource "azurerm_network_security_rule" "dmz_public_allow_from_hub" {
  name                        = "Allow-Inbound-From-Hub"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.hub_vnet_address_space[0]
  destination_address_prefix  = var.dmz_subnet_public
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_public.name
}

resource "azurerm_network_security_rule" "dmz_public_deny_all_inbound" {
  name                        = "Deny-Inbound-All"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_public.name
}

# ---------------------------------------------------------------------------
# NSG — WAF subnet
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "dmz_waf" {
  name                = "nsg-dmz-waf-${var.environment}"
  location            = azurerm_resource_group.dmz.location
  resource_group_name = azurerm_resource_group.dmz.name
  tags                = local.common_tags
}

# Allow HTTP/HTTPS from public subnet (WAF receives forwarded traffic)
resource "azurerm_network_security_rule" "dmz_waf_allow_from_public" {
  name                        = "Allow-Inbound-From-Public"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443", "65200-65535"]
  source_address_prefix       = var.dmz_subnet_public
  destination_address_prefix  = var.dmz_subnet_waf
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_waf.name
}

# Allow Application Gateway management ports (required by Azure)
resource "azurerm_network_security_rule" "dmz_waf_allow_gateway_manager" {
  name                        = "Allow-GatewayManager"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "65200-65535"
  source_address_prefix       = "GatewayManager"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_waf.name
}

resource "azurerm_network_security_rule" "dmz_waf_allow_alb" {
  name                        = "Allow-AzureLoadBalancer"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_waf.name
}

resource "azurerm_network_security_rule" "dmz_waf_allow_from_hub" {
  name                        = "Allow-Inbound-From-Hub"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.hub_vnet_address_space[0]
  destination_address_prefix  = var.dmz_subnet_waf
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_waf.name
}

resource "azurerm_network_security_rule" "dmz_waf_deny_all_inbound" {
  name                        = "Deny-Inbound-All"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dmz.name
  network_security_group_name = azurerm_network_security_group.dmz_waf.name
}

# ---------------------------------------------------------------------------
# NSG associations
# ---------------------------------------------------------------------------

resource "azurerm_subnet_network_security_group_association" "dmz_public" {
  subnet_id                 = azurerm_subnet.dmz_public.id
  network_security_group_id = azurerm_network_security_group.dmz_public.id
}

resource "azurerm_subnet_network_security_group_association" "dmz_waf" {
  subnet_id                 = azurerm_subnet.dmz_waf.id
  network_security_group_id = azurerm_network_security_group.dmz_waf.id
}

# ---------------------------------------------------------------------------
# Route table — force all non-internet traffic through hub firewall
# ---------------------------------------------------------------------------

resource "azurerm_route_table" "dmz" {
  count = var.enable_azure_firewall ? 1 : 0

  name                          = "rt-dmz-${var.environment}"
  location                      = azurerm_resource_group.dmz.location
  resource_group_name           = azurerm_resource_group.dmz.name
  disable_bgp_route_propagation = true
  tags                          = local.common_tags
}

resource "azurerm_route" "dmz_default" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-default-to-firewall"
  resource_group_name    = azurerm_resource_group.dmz.name
  route_table_name       = azurerm_route_table.dmz[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

resource "azurerm_route" "dmz_rfc1918_10" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-rfc1918-10-to-firewall"
  resource_group_name    = azurerm_resource_group.dmz.name
  route_table_name       = azurerm_route_table.dmz[0].name
  address_prefix         = "10.0.0.0/8"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

resource "azurerm_route" "dmz_rfc1918_172" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-rfc1918-172-to-firewall"
  resource_group_name    = azurerm_resource_group.dmz.name
  route_table_name       = azurerm_route_table.dmz[0].name
  address_prefix         = "172.16.0.0/12"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

resource "azurerm_route" "dmz_rfc1918_192" {
  count = var.enable_azure_firewall ? 1 : 0

  name                   = "route-rfc1918-192-to-firewall"
  resource_group_name    = azurerm_resource_group.dmz.name
  route_table_name       = azurerm_route_table.dmz[0].name
  address_prefix         = "192.168.0.0/16"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
}

# Route table associations
resource "azurerm_subnet_route_table_association" "dmz_public" {
  count = var.enable_azure_firewall ? 1 : 0

  subnet_id      = azurerm_subnet.dmz_public.id
  route_table_id = azurerm_route_table.dmz[0].id
}

resource "azurerm_subnet_route_table_association" "dmz_waf" {
  count = var.enable_azure_firewall ? 1 : 0

  subnet_id      = azurerm_subnet.dmz_waf.id
  route_table_id = azurerm_route_table.dmz[0].id
}

# ---------------------------------------------------------------------------
# Test VM — DMZ public subnet
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "dmz_vm" {
  name                = "nic-dmz-vm-${var.environment}"
  location            = azurerm_resource_group.dmz.location
  resource_group_name = azurerm_resource_group.dmz.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig-dmz-vm"
    subnet_id                     = azurerm_subnet.dmz_public.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "dmz_vm" {
  name                            = "vm-dmz-public-${var.environment}"
  location                        = azurerm_resource_group.dmz.location
  resource_group_name             = azurerm_resource_group.dmz.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  tags                            = local.common_tags

  network_interface_ids = [
    azurerm_network_interface.dmz_vm.id,
  ]

  os_disk {
    name                 = "osdisk-dmz-vm-${var.environment}"
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
    echo "<h1>DMZ VM - Public Subnet</h1>" > /var/www/html/index.html
  EOF
  )
}
