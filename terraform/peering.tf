# ---------------------------------------------------------------------------
# VNet peering — Hub <-> Workload spoke
#
# Hub side: allow_gateway_transit = true enables the spoke to use any VPN/ER
#           gateway deployed in the hub.
# Spoke side: use_remote_gateways = false (set to true once a gateway exists
#             in the hub and you want on-premises connectivity through it).
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network_peering" "hub_to_workload" {
  name                         = "peer-hub-to-workload"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.workload.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "workload_to_hub" {
  name                         = "peer-workload-to-hub"
  resource_group_name          = azurerm_resource_group.workload.name
  virtual_network_name         = azurerm_virtual_network.workload.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  # Peerings must be created after both sides of the hub peering exist
  depends_on = [
    azurerm_virtual_network_peering.hub_to_workload,
  ]
}

# ---------------------------------------------------------------------------
# VNet peering — Hub <-> DMZ spoke
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network_peering" "hub_to_dmz" {
  name                         = "peer-hub-to-dmz"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.dmz.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "dmz_to_hub" {
  name                         = "peer-dmz-to-hub"
  resource_group_name          = azurerm_resource_group.dmz.name
  virtual_network_name         = azurerm_virtual_network.dmz.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [
    azurerm_virtual_network_peering.hub_to_dmz,
  ]
}
