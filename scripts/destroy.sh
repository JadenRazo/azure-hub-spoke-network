#!/usr/bin/env bash
# destroy.sh — Tear down all resources managed by this Terraform configuration.
# Requires two separate confirmations to prevent accidental destruction.

set -euo pipefail

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prerequisites() {
  info "Checking prerequisites..."

  if ! command -v terraform &>/dev/null; then
    die "terraform is not installed or not on PATH."
  fi

  if ! command -v az &>/dev/null; then
    die "Azure CLI (az) is not installed."
  fi

  if ! az account show &>/dev/null; then
    die "Not logged in to Azure. Run 'az login' first."
  fi

  ACCOUNT_NAME="$(az account show --query 'name' -o tsv)"
  SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
  success "Authenticated — subscription: ${ACCOUNT_NAME} (${SUBSCRIPTION_ID})"

  if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    die "Terraform directory not found at ${TERRAFORM_DIR}"
  fi

  if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
    die "terraform.tfvars not found in ${TERRAFORM_DIR}"
  fi
}

# ---------------------------------------------------------------------------
# Double confirmation
# ---------------------------------------------------------------------------
confirm_destroy() {
  echo ""
  echo -e "${RED}${BOLD}========================================${RESET}"
  echo -e "${RED}${BOLD}  WARNING: DESTRUCTIVE OPERATION${RESET}"
  echo -e "${RED}${BOLD}========================================${RESET}"
  echo ""
  echo -e "${YELLOW}This will permanently destroy ALL resources managed by this Terraform"
  echo -e "configuration in subscription: $(az account show --query 'name' -o tsv)${RESET}"
  echo ""
  echo "Resources that will be deleted include:"
  echo "  - Hub VNet, subnets, NSGs, route tables"
  echo "  - Workload and DMZ spoke VNets, subnets, NSGs, route tables"
  echo "  - Azure Firewall and public IP"
  echo "  - Azure Bastion and public IP"
  echo "  - Log Analytics workspace and all ingested data"
  echo "  - Network Watcher and flow logs"
  echo "  - All test virtual machines and OS disks"
  echo "  - Private DNS zone and all records"
  echo "  - Storage account for flow logs"
  echo ""

  # First confirmation
  read -rp "First confirmation — type 'destroy' to continue: " ANSWER_1
  if [[ "${ANSWER_1}" != "destroy" ]]; then
    warn "Destruction cancelled."
    exit 0
  fi

  echo ""
  warn "Last chance. This cannot be undone."
  echo ""

  # Second confirmation — must type the subscription ID
  read -rp "Second confirmation — type the subscription ID to confirm: " ANSWER_2
  EXPECTED_SUB="$(az account show --query 'id' -o tsv)"
  if [[ "${ANSWER_2}" != "${EXPECTED_SUB}" ]]; then
    warn "Subscription ID did not match. Destruction cancelled."
    exit 0
  fi

  echo ""
  warn "Both confirmations accepted. Proceeding with destroy..."
  echo ""
}

# ---------------------------------------------------------------------------
# Terraform init (needed if .terraform directory is missing)
# ---------------------------------------------------------------------------
run_init() {
  if [[ ! -d "${TERRAFORM_DIR}/.terraform" ]]; then
    info "Running terraform init before destroy..."
    terraform -chdir="${TERRAFORM_DIR}" init -upgrade || die "terraform init failed"
  fi
}

# ---------------------------------------------------------------------------
# Terraform destroy
# ---------------------------------------------------------------------------
run_destroy() {
  info "Running terraform destroy..."
  if terraform -chdir="${TERRAFORM_DIR}" destroy \
      -var-file="terraform.tfvars" \
      -auto-approve; then
    success "Terraform destroy complete — all resources have been removed."
  else
    die "terraform destroy failed. Some resources may still exist. Check the Azure portal."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}========================================${RESET}"
echo -e "${BOLD}  Hub-Spoke Network — Destroy${RESET}"
echo -e "${BOLD}========================================${RESET}"
echo ""

check_prerequisites
confirm_destroy
run_init
run_destroy

echo ""
success "All resources destroyed."
