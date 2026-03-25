# ---------------------------------------------------------------------------
# Azure Bastion — conditional on var.enable_bastion
#
# Standard SKU is used to enable session recording, file transfer, and
# native client support. Use Basic SKU by changing the sku attribute if
# you only need basic RDP/SSH tunnelling.
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name                = "pip-bastion-hub-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  # Azure Bastion requires Standard SKU with Static allocation
  allocation_method = "Static"
  sku               = "Standard"

  tags = local.common_tags
}

resource "azurerm_bastion_host" "hub" {
  count = var.enable_bastion ? 1 : 0

  name                = "bas-hub-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "Standard"

  # Standard SKU features
  tunneling_enabled     = true
  file_copy_enabled     = true
  copy_paste_enabled    = true
  shareable_link_enabled = true

  ip_configuration {
    name                 = "ipconfig-bastion"
    subnet_id            = azurerm_subnet.hub_bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = local.common_tags
}
