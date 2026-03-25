# ---------------------------------------------------------------------------
# Resource group names
# ---------------------------------------------------------------------------

output "hub_resource_group_name" {
  description = "Name of the hub resource group."
  value       = azurerm_resource_group.hub.name
}

output "workload_resource_group_name" {
  description = "Name of the workload spoke resource group."
  value       = azurerm_resource_group.workload.name
}

output "dmz_resource_group_name" {
  description = "Name of the DMZ spoke resource group."
  value       = azurerm_resource_group.dmz.name
}

# ---------------------------------------------------------------------------
# VNet IDs
# ---------------------------------------------------------------------------

output "hub_vnet_id" {
  description = "Resource ID of the hub virtual network."
  value       = azurerm_virtual_network.hub.id
}

output "spoke_workload_vnet_id" {
  description = "Resource ID of the workload spoke virtual network."
  value       = azurerm_virtual_network.workload.id
}

output "spoke_dmz_vnet_id" {
  description = "Resource ID of the DMZ spoke virtual network."
  value       = azurerm_virtual_network.dmz.id
}

# ---------------------------------------------------------------------------
# Subnet IDs
# ---------------------------------------------------------------------------

output "hub_subnet_shared_services_id" {
  description = "Resource ID of the hub shared services subnet."
  value       = azurerm_subnet.hub_shared_services.id
}

output "workload_subnet_web_id" {
  description = "Resource ID of the workload web tier subnet."
  value       = azurerm_subnet.workload_web.id
}

output "workload_subnet_app_id" {
  description = "Resource ID of the workload app tier subnet."
  value       = azurerm_subnet.workload_app.id
}

output "workload_subnet_data_id" {
  description = "Resource ID of the workload data tier subnet."
  value       = azurerm_subnet.workload_data.id
}

output "dmz_subnet_public_id" {
  description = "Resource ID of the DMZ public subnet."
  value       = azurerm_subnet.dmz_public.id
}

output "dmz_subnet_waf_id" {
  description = "Resource ID of the DMZ WAF subnet."
  value       = azurerm_subnet.dmz_waf.id
}

# ---------------------------------------------------------------------------
# Azure Bastion
# ---------------------------------------------------------------------------

output "bastion_public_ip" {
  description = "Public IP address of the Azure Bastion host. Null when enable_bastion is false."
  value       = var.enable_bastion ? azurerm_public_ip.bastion[0].ip_address : null
}

output "bastion_host_id" {
  description = "Resource ID of the Azure Bastion host. Null when enable_bastion is false."
  value       = var.enable_bastion ? azurerm_bastion_host.hub[0].id : null
}

# ---------------------------------------------------------------------------
# Azure Firewall
# ---------------------------------------------------------------------------

output "firewall_private_ip" {
  description = "Private IP address of the Azure Firewall. Null when enable_azure_firewall is false."
  value       = var.enable_azure_firewall ? azurerm_firewall.hub[0].ip_configuration[0].private_ip_address : null
}

output "firewall_public_ip" {
  description = "Public IP address of the Azure Firewall. Null when enable_azure_firewall is false."
  value       = var.enable_azure_firewall ? azurerm_public_ip.firewall[0].ip_address : null
}

output "firewall_id" {
  description = "Resource ID of the Azure Firewall. Null when enable_azure_firewall is false."
  value       = var.enable_azure_firewall ? azurerm_firewall.hub[0].id : null
}

# ---------------------------------------------------------------------------
# Log Analytics
# ---------------------------------------------------------------------------

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.hub.id
}

output "log_analytics_workspace_key" {
  description = "Primary shared key for the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.hub.primary_shared_key
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Private DNS
# ---------------------------------------------------------------------------

output "private_dns_zone_id" {
  description = "Resource ID of the private DNS zone."
  value       = azurerm_private_dns_zone.internal.id
}

output "private_dns_zone_name" {
  description = "Name of the private DNS zone."
  value       = azurerm_private_dns_zone.internal.name
}

# ---------------------------------------------------------------------------
# Test VM private IPs
# ---------------------------------------------------------------------------

output "workload_vm_private_ip" {
  description = "Private IP address of the workload spoke test VM."
  value       = azurerm_network_interface.workload_vm.private_ip_address
}

output "dmz_vm_private_ip" {
  description = "Private IP address of the DMZ spoke test VM."
  value       = azurerm_network_interface.dmz_vm.private_ip_address
}
