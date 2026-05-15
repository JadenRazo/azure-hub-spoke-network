terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.73"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------

locals {
  common_tags = merge(var.tags, {
    environment = var.environment
    project     = "hub-spoke-network"
    managed_by  = "terraform"
  })
}

# ---------------------------------------------------------------------------
# Resource groups
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "hub" {
  name     = "rg-hubspoke-hub-${var.environment}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "workload" {
  name     = "rg-hubspoke-workload-${var.environment}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "dmz" {
  name     = "rg-hubspoke-dmz-${var.environment}"
  location = var.location
  tags     = local.common_tags
}
