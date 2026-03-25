# ---------------------------------------------------------------------------
# Remote state backend — Azure Blob Storage
#
# Uncomment this block after running scripts/bootstrap-state.sh, which
# creates the storage account and container. Replace the placeholder values
# with the outputs from that script before running `terraform init`.
#
# See: https://developer.hashicorp.com/terraform/language/settings/backends/azurerm
# ---------------------------------------------------------------------------

# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-hubspoke-tfstate"
#     storage_account_name = "<your-storage-account-name>"
#     container_name       = "tfstate"
#     key                  = "hub-spoke-network.terraform.tfstate"
#   }
# }
