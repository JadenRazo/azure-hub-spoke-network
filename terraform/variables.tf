# ---------------------------------------------------------------------------
# Core configuration
# ---------------------------------------------------------------------------

variable "location" {
  description = "Azure region where all resources will be deployed."
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Deployment environment label used in resource names and tags (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# VM credentials
# ---------------------------------------------------------------------------

variable "admin_username" {
  description = "Local administrator username for test virtual machines."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Local administrator password for test virtual machines. Must meet Azure complexity requirements."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters long."
  }
}

variable "vm_size" {
  description = "Azure VM size for test virtual machines."
  type        = string
  default     = "Standard_B1s"
}

# ---------------------------------------------------------------------------
# Hub VNet address spaces
# ---------------------------------------------------------------------------

variable "hub_vnet_address_space" {
  description = "Address space for the hub VNet."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "hub_subnet_firewall" {
  description = "Address prefix for AzureFirewallSubnet. Must be at least /26."
  type        = string
  default     = "10.0.1.0/26"
}

variable "hub_subnet_bastion" {
  description = "Address prefix for AzureBastionSubnet. Must be at least /26."
  type        = string
  default     = "10.0.2.0/26"
}

variable "hub_subnet_gateway" {
  description = "Address prefix for GatewaySubnet. Must be at least /27."
  type        = string
  default     = "10.0.3.0/27"
}

variable "hub_subnet_shared_services" {
  description = "Address prefix for the shared services subnet in the hub."
  type        = string
  default     = "10.0.4.0/24"
}

# ---------------------------------------------------------------------------
# Workload spoke VNet address spaces
# ---------------------------------------------------------------------------

variable "workload_vnet_address_space" {
  description = "Address space for the workload spoke VNet."
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "workload_subnet_web" {
  description = "Address prefix for the web tier subnet in the workload spoke."
  type        = string
  default     = "10.1.1.0/24"
}

variable "workload_subnet_app" {
  description = "Address prefix for the application tier subnet in the workload spoke."
  type        = string
  default     = "10.1.2.0/24"
}

variable "workload_subnet_data" {
  description = "Address prefix for the data tier subnet in the workload spoke."
  type        = string
  default     = "10.1.3.0/24"
}

# ---------------------------------------------------------------------------
# DMZ spoke VNet address spaces
# ---------------------------------------------------------------------------

variable "dmz_vnet_address_space" {
  description = "Address space for the DMZ spoke VNet."
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

variable "dmz_subnet_public" {
  description = "Address prefix for the public-facing services subnet in the DMZ spoke."
  type        = string
  default     = "10.2.1.0/24"
}

variable "dmz_subnet_waf" {
  description = "Address prefix for the WAF subnet in the DMZ spoke."
  type        = string
  default     = "10.2.2.0/24"
}

# ---------------------------------------------------------------------------
# Feature flags
# ---------------------------------------------------------------------------

variable "enable_azure_firewall" {
  description = "Deploy Azure Firewall in the hub. Set to false to skip (reduces cost for lab use)."
  type        = bool
  default     = true
}

variable "enable_bastion" {
  description = "Deploy Azure Bastion in the hub. Set to false to skip."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to merge with the default tag set applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Log Analytics
# ---------------------------------------------------------------------------

variable "log_analytics_retention_days" {
  description = "Number of days to retain data in the Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days must be between 30 and 730."
  }
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

variable "private_dns_zone_name" {
  description = "Name of the Azure Private DNS zone used for internal name resolution."
  type        = string
  default     = "hubspoke.internal"
}
