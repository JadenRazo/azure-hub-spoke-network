# ---------------------------------------------------------------------------
# Hub VNet
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.location}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = var.hub_vnet_address_space

  # Azure-provided DNS is used; Private DNS zones override specific FQDNs
  dns_servers = []

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Hub subnets
# Note: AzureFirewallSubnet and AzureBastionSubnet must not have NSGs;
#       GatewaySubnet must not have NSGs either — these are Azure requirements.
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "hub_firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnet_firewall]
}

resource "azurerm_subnet" "hub_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnet_bastion]
}

resource "azurerm_subnet" "hub_gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnet_gateway]
}

resource "azurerm_subnet" "hub_shared_services" {
  name                 = "snet-shared-services"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnet_shared_services]
}

# ---------------------------------------------------------------------------
# NSG — shared services subnet
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "hub_shared_services" {
  name                = "nsg-hub-shared-services-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.common_tags
}

# Allow inbound from all RFC 1918 ranges (hub and both spokes)
resource "azurerm_network_security_rule" "hub_shared_allow_inbound_internal" {
  name                        = "Allow-Inbound-Internal"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = ["10.0.0.0/8"]
  destination_address_prefix  = var.hub_subnet_shared_services
  resource_group_name         = azurerm_resource_group.hub.name
  network_security_group_name = azurerm_network_security_group.hub_shared_services.name
}

# Allow Azure Load Balancer health probes
resource "azurerm_network_security_rule" "hub_shared_allow_alb" {
  name                        = "Allow-AzureLoadBalancer"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.hub.name
  network_security_group_name = azurerm_network_security_group.hub_shared_services.name
}

# Deny all other inbound traffic (explicit deny-all before default rule)
resource "azurerm_network_security_rule" "hub_shared_deny_inbound_all" {
  name                        = "Deny-Inbound-All"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.hub.name
  network_security_group_name = azurerm_network_security_group.hub_shared_services.name
}

# Allow outbound to internal RFC 1918 ranges
resource "azurerm_network_security_rule" "hub_shared_allow_outbound_internal" {
  name                        = "Allow-Outbound-Internal"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.hub_subnet_shared_services
  destination_address_prefixes = ["10.0.0.0/8"]
  resource_group_name         = azurerm_resource_group.hub.name
  network_security_group_name = azurerm_network_security_group.hub_shared_services.name
}

# Deny direct internet egress — all spoke traffic must route through the firewall
resource "azurerm_network_security_rule" "hub_shared_deny_outbound_internet" {
  name                        = "Deny-Outbound-Internet"
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.hub_subnet_shared_services
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.hub.name
  network_security_group_name = azurerm_network_security_group.hub_shared_services.name
}

# ---------------------------------------------------------------------------
# Associate NSG with shared services subnet
# ---------------------------------------------------------------------------

resource "azurerm_subnet_network_security_group_association" "hub_shared_services" {
  subnet_id                 = azurerm_subnet.hub_shared_services.id
  network_security_group_id = azurerm_network_security_group.hub_shared_services.id
}
