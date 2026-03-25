# ---------------------------------------------------------------------------
# Azure Private DNS zone
#
# All three VNets are linked so that VMs across the hub and both spokes
# can resolve each other by FQDN within the hubspoke.internal domain.
# Auto-registration is enabled on the spoke VNets so that VM NICs
# automatically register their private IPs as A records.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "internal" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# VNet links
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  name                  = "vnetlink-hub-${var.environment}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.hub.id

  # The hub does not host workload VMs, so auto-registration is disabled.
  registration_enabled = false

  tags = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "workload" {
  name                  = "vnetlink-workload-${var.environment}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.workload.id

  # Auto-registration creates DNS A records for each VM NIC in this VNet.
  registration_enabled = true

  tags = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dmz" {
  name                  = "vnetlink-dmz-${var.environment}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.dmz.id

  registration_enabled = true

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Static A records for test VMs
#
# Auto-registration covers the dynamic IPs, but static records are also
# created here with human-readable names for use in scripts and tests.
# These records follow the pattern: <vm-role>.<dns-zone>
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_a_record" "workload_vm" {
  name                = "vm-workload-web"
  zone_name           = azurerm_private_dns_zone.internal.name
  resource_group_name = azurerm_resource_group.hub.name
  ttl                 = 300
  records             = [azurerm_network_interface.workload_vm.private_ip_address]
  tags                = local.common_tags
}

resource "azurerm_private_dns_a_record" "dmz_vm" {
  name                = "vm-dmz-public"
  zone_name           = azurerm_private_dns_zone.internal.name
  resource_group_name = azurerm_resource_group.hub.name
  ttl                 = 300
  records             = [azurerm_network_interface.dmz_vm.private_ip_address]
  tags                = local.common_tags
}
