#!/usr/bin/env bash
# deploy.sh — Initialize, plan, and apply the hub-spoke Terraform configuration.
# Run from the repo root or any directory; the script navigates to terraform/ itself.

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

# ---------------------------------------------------------------------------
# Locate terraform directory relative to this script
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prerequisites() {
  info "Checking prerequisites..."

  if ! command -v terraform &>/dev/null; then
    die "terraform is not installed or not on PATH. Install it from https://developer.hashicorp.com/terraform/downloads"
  fi

  TF_VERSION="$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || terraform version | head -1 | awk '{print $2}' | tr -d 'v')"
  success "terraform ${TF_VERSION} found"

  if ! command -v az &>/dev/null; then
    die "Azure CLI (az) is not installed. Install it from https://docs.microsoft.com/cli/azure/install-azure-cli"
  fi

  AZ_VERSION="$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo 'unknown')"
  success "Azure CLI ${AZ_VERSION} found"

  # Verify the user is authenticated
  if ! az account show &>/dev/null; then
    die "Not logged in to Azure. Run 'az login' and try again."
  fi

  ACCOUNT_NAME="$(az account show --query 'name' -o tsv)"
  SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
  success "Authenticated — subscription: ${ACCOUNT_NAME} (${SUBSCRIPTION_ID})"

  if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    die "Terraform directory not found at ${TERRAFORM_DIR}"
  fi

  # Check for a tfvars file
  if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
    warn "terraform.tfvars not found. Copy terraform.tfvars.example and fill in values:"
    warn "  cp ${TERRAFORM_DIR}/terraform.tfvars.example ${TERRAFORM_DIR}/terraform.tfvars"
    die "Missing terraform.tfvars — cannot proceed."
  fi

  success "All prerequisites satisfied"
}

# ---------------------------------------------------------------------------
# Terraform init
# ---------------------------------------------------------------------------
run_init() {
  info "Initializing Terraform..."
  if terraform -chdir="${TERRAFORM_DIR}" init -upgrade; then
    success "Terraform initialized"
  else
    die "terraform init failed"
  fi
}

# ---------------------------------------------------------------------------
# Terraform plan
# ---------------------------------------------------------------------------
run_plan() {
  info "Running Terraform plan..."
  PLAN_FILE="${TERRAFORM_DIR}/tfplan"

  if terraform -chdir="${TERRAFORM_DIR}" plan \
      -var-file="terraform.tfvars" \
      -out="${PLAN_FILE}" \
      -detailed-exitcode; then
    success "Plan complete — no changes detected"
    return 0
  fi

  PLAN_EXIT=$?
  if [[ ${PLAN_EXIT} -eq 2 ]]; then
    success "Plan complete — changes are pending (exit 2 = changes present)"
    return 0
  fi

  die "terraform plan failed (exit ${PLAN_EXIT})"
}

# ---------------------------------------------------------------------------
# Confirmation prompt
# ---------------------------------------------------------------------------
confirm_apply() {
  echo ""
  echo -e "${BOLD}Review the plan output above before continuing.${RESET}"
  echo -e "${YELLOW}This will create or modify Azure resources in your subscription.${RESET}"
  echo ""
  read -rp "Type 'yes' to apply, anything else to abort: " ANSWER
  if [[ "${ANSWER}" != "yes" ]]; then
    warn "Apply cancelled by user."
    exit 0
  fi
}

# ---------------------------------------------------------------------------
# Terraform apply
# ---------------------------------------------------------------------------
run_apply() {
  info "Applying Terraform plan..."
  PLAN_FILE="${TERRAFORM_DIR}/tfplan"

  if terraform -chdir="${TERRAFORM_DIR}" apply "${PLAN_FILE}"; then
    success "Terraform apply complete"
    rm -f "${PLAN_FILE}"
  else
    die "terraform apply failed"
  fi
}

# ---------------------------------------------------------------------------
# Print outputs
# ---------------------------------------------------------------------------
print_outputs() {
  info "Deployment outputs:"
  terraform -chdir="${TERRAFORM_DIR}" output 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}========================================${RESET}"
echo -e "${BOLD}  Hub-Spoke Network — Deploy${RESET}"
echo -e "${BOLD}========================================${RESET}"
echo ""

check_prerequisites
run_init
run_plan
confirm_apply
run_apply
print_outputs

echo ""
success "Deployment complete."
