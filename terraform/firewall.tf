# ---------------------------------------------------------------------------
# Azure Firewall — conditional on var.enable_azure_firewall
#
# Standard SKU with a Firewall Policy (preferred over classic rules).
# Threat intelligence is set to Alert mode by default; change to Deny for
# production environments once you have validated your rule set.
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "firewall" {
  count = var.enable_azure_firewall ? 1 : 0

  name                = "pip-firewall-hub-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Firewall policy
# ---------------------------------------------------------------------------

resource "azurerm_firewall_policy" "hub" {
  count = var.enable_azure_firewall ? 1 : 0

  name                = "afwp-hub-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "Standard"

  threat_intelligence_mode = "Alert"

  dns {
    # Use Azure-provided DNS for FQDN-based rules
    proxy_enabled = true
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Network rule collection — spoke-to-spoke and spoke-to-hub
# ---------------------------------------------------------------------------

resource "azurerm_firewall_policy_rule_collection_group" "hub_network" {
  count = var.enable_azure_firewall ? 1 : 0

  name               = "rcg-network-hub-${var.environment}"
  firewall_policy_id = azurerm_firewall_policy.hub[0].id
  priority           = 100

  network_rule_collection {
    name     = "nrc-spoke-to-spoke"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "Allow-Workload-To-DMZ"
      protocols             = ["Any"]
      source_addresses      = [var.workload_vnet_address_space[0]]
      destination_addresses = [var.dmz_vnet_address_space[0]]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "Allow-DMZ-To-Workload"
      protocols             = ["Any"]
      source_addresses      = [var.dmz_vnet_address_space[0]]
      destination_addresses = [var.workload_vnet_address_space[0]]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "Allow-Spoke-To-Hub-SharedServices"
      protocols             = ["Any"]
      source_addresses      = ["10.1.0.0/8"]
      destination_addresses = [var.hub_subnet_shared_services]
      destination_ports     = ["*"]
    }
  }

  network_rule_collection {
    name     = "nrc-dns"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "Allow-DNS-Outbound"
      protocols             = ["UDP", "TCP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }
  }

  network_rule_collection {
    name     = "nrc-ntp"
    priority = 300
    action   = "Allow"

    rule {
      name                  = "Allow-NTP-Outbound"
      protocols             = ["UDP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }
  }
}

# ---------------------------------------------------------------------------
# Application rule collection — controlled internet egress
# ---------------------------------------------------------------------------

resource "azurerm_firewall_policy_rule_collection_group" "hub_application" {
  count = var.enable_azure_firewall ? 1 : 0

  name               = "rcg-application-hub-${var.environment}"
  firewall_policy_id = azurerm_firewall_policy.hub[0].id
  priority           = 200

  application_rule_collection {
    name     = "arc-allow-web-outbound"
    priority = 100
    action   = "Allow"

    rule {
      name = "Allow-HTTP-HTTPS-All"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = ["10.0.0.0/8"]
      destination_fqdns = ["*"]
    }
  }

  application_rule_collection {
    name     = "arc-allow-ubuntu-updates"
    priority = 110
    action   = "Allow"

    rule {
      name = "Allow-Ubuntu-Updates"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["10.0.0.0/8"]
      destination_fqdns = [
        "*.ubuntu.com",
        "security.ubuntu.com",
        "archive.ubuntu.com",
        "*.snapcraft.io",
        "*.launchpad.net",
      ]
    }
  }

  application_rule_collection {
    name     = "arc-allow-azure-services"
    priority = 120
    action   = "Allow"

    rule {
      name = "Allow-Azure-Monitor"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["10.0.0.0/8"]
      destination_fqdn_tags = [
        "AzureMonitor",
        "WindowsUpdate",
        "WindowsDiagnostics",
        "MicrosoftActiveProtectionService",
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Azure Firewall resource
# ---------------------------------------------------------------------------

resource "azurerm_firewall" "hub" {
  count = var.enable_azure_firewall ? 1 : 0

  name                = "afw-hub-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.hub[0].id
  tags                = local.common_tags

  ip_configuration {
    name                 = "ipconfig-firewall"
    subnet_id            = azurerm_subnet.hub_firewall.id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  depends_on = [
    azurerm_firewall_policy_rule_collection_group.hub_network,
    azurerm_firewall_policy_rule_collection_group.hub_application,
  ]
}
