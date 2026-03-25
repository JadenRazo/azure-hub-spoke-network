# ---------------------------------------------------------------------------
# Log Analytics workspace — centralized logging for all hub-spoke resources
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "hub" {
  name                = "law-hubspoke-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Network Watcher — required for NSG flow logs
# Azure auto-creates a Network Watcher per region per subscription, but
# Terraform must manage it to attach flow log resources to it.
# ---------------------------------------------------------------------------

resource "azurerm_network_watcher" "hub" {
  name                = "nw-hubspoke-${var.location}-${var.environment}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# NSG flow logs — hub shared services
# ---------------------------------------------------------------------------

resource "azurerm_network_watcher_flow_log" "hub_shared_services" {
  network_watcher_name = azurerm_network_watcher.hub.name
  resource_group_name  = azurerm_resource_group.hub.name
  name                 = "fl-nsg-hub-shared-${var.environment}"

  network_security_group_id = azurerm_network_security_group.hub_shared_services.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.log_analytics_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

# ---------------------------------------------------------------------------
# NSG flow logs — workload web
# ---------------------------------------------------------------------------

resource "azurerm_network_watcher_flow_log" "workload_web" {
  network_watcher_name = azurerm_network_watcher.hub.name
  resource_group_name  = azurerm_resource_group.hub.name
  name                 = "fl-nsg-workload-web-${var.environment}"

  network_security_group_id = azurerm_network_security_group.workload_web.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.log_analytics_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

# ---------------------------------------------------------------------------
# NSG flow logs — workload app
# ---------------------------------------------------------------------------

resource "azurerm_network_watcher_flow_log" "workload_app" {
  network_watcher_name = azurerm_network_watcher.hub.name
  resource_group_name  = azurerm_resource_group.hub.name
  name                 = "fl-nsg-workload-app-${var.environment}"

  network_security_group_id = azurerm_network_security_group.workload_app.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.log_analytics_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

# ---------------------------------------------------------------------------
# NSG flow logs — workload data
# ---------------------------------------------------------------------------

resource "azurerm_network_watcher_flow_log" "workload_data" {
  network_watcher_name = azurerm_network_watcher.hub.name
  resource_group_name  = azurerm_resource_group.hub.name
  name                 = "fl-nsg-workload-data-${var.environment}"

  network_security_group_id = azurerm_network_security_group.workload_data.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.log_analytics_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

# ---------------------------------------------------------------------------
# NSG flow logs — DMZ public
# ---------------------------------------------------------------------------

resource "azurerm_network_watcher_flow_log" "dmz_public" {
  network_watcher_name = azurerm_network_watcher.hub.name
  resource_group_name  = azurerm_resource_group.hub.name
  name                 = "fl-nsg-dmz-public-${var.environment}"

  network_security_group_id = azurerm_network_security_group.dmz_public.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.log_analytics_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

# ---------------------------------------------------------------------------
# NSG flow logs — DMZ WAF
# ---------------------------------------------------------------------------

resource "azurerm_network_watcher_flow_log" "dmz_waf" {
  network_watcher_name = azurerm_network_watcher.hub.name
  resource_group_name  = azurerm_resource_group.hub.name
  name                 = "fl-nsg-dmz-waf-${var.environment}"

  network_security_group_id = azurerm_network_security_group.dmz_waf.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.log_analytics_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

# ---------------------------------------------------------------------------
# Storage account for NSG flow logs
# Storage account names must be globally unique, 3–24 chars, lowercase alnum.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "flow_logs" {
  # Generate a deterministic short name from the environment label
  name                     = "stflowlogs${substr(md5("${var.environment}${var.location}"), 0, 8)}"
  resource_group_name      = azurerm_resource_group.hub.name
  location                 = azurerm_resource_group.hub.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # Disable public blob access — flow logs are written by the Azure platform
  allow_nested_items_to_be_public = false

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Diagnostic settings — Azure Firewall
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count = var.enable_azure_firewall ? 1 : 0

  name                       = "diag-afw-hub-${var.environment}"
  target_resource_id         = azurerm_firewall.hub[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }

  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  enabled_log {
    category = "AzureFirewallDnsProxy"
  }

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_log {
    category = "AZFWNatRule"
  }

  enabled_log {
    category = "AZFWThreatIntel"
  }

  enabled_log {
    category = "AZFWIdpsSignature"
  }

  enabled_log {
    category = "AZFWDnsQuery"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------------------------------------------------------------------------
# Diagnostic settings — Azure Bastion
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name                       = "diag-bastion-hub-${var.environment}"
  target_resource_id         = azurerm_bastion_host.hub[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log {
    category = "BastionAuditLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------------------------------------------------------------------------
# Diagnostic settings — Hub VNet
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "hub_vnet" {
  name                       = "diag-vnet-hub-${var.environment}"
  target_resource_id         = azurerm_virtual_network.hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
