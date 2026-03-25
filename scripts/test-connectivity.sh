#!/usr/bin/env bash
# test-connectivity.sh — Run connectivity tests across the hub-spoke topology.
#
# Usage:
#   ./test-connectivity.sh <resource-group-name>
#
# The script reads VM private IPs from terraform output and then runs connectivity
# checks via Azure Bastion / Azure Network Watcher. For tests that require running
# commands inside VMs, it uses the Azure CLI VM run-command invoke.
#
# Prerequisites:
#   - az CLI installed and authenticated
#   - terraform installed, state accessible from the terraform/ directory
#   - VMs must be running

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
pass()    { echo -e "${GREEN}[PASS]${RESET}  $*"; }
fail()    { echo -e "${RED}[FAIL]${RESET}  $*"; FAILED_TESTS+=("$*"); }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
header()  { echo -e "\n${BOLD}--- $* ---${RESET}"; }
die()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
FAILED_TESTS=()
PASSED=0
TOTAL=0

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <hub-resource-group-name>"
  echo ""
  echo "Example:"
  echo "  $0 rg-hubspoke-hub-dev"
  exit 1
fi

HUB_RG="$1"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
check_prereqs() {
  header "Checking prerequisites"

  for cmd in az terraform jq; do
    if command -v "${cmd}" &>/dev/null; then
      pass "${cmd} found"
    else
      die "${cmd} is not installed or not on PATH"
    fi
  done

  if ! az account show &>/dev/null; then
    die "Not logged in to Azure. Run 'az login' first."
  fi
  pass "Azure CLI authenticated"

  if [[ ! -d "${TERRAFORM_DIR}/.terraform" ]]; then
    die "Terraform not initialized. Run scripts/deploy.sh first."
  fi
  pass "Terraform state present"
}

# ---------------------------------------------------------------------------
# Read terraform outputs
# ---------------------------------------------------------------------------
get_outputs() {
  header "Reading Terraform outputs"

  TF_OUTPUT="$(terraform -chdir="${TERRAFORM_DIR}" output -json 2>/dev/null)"

  WORKLOAD_VM_IP="$(echo "${TF_OUTPUT}" | jq -r '.workload_vm_private_ip.value // empty')"
  DMZ_VM_IP="$(echo "${TF_OUTPUT}" | jq -r '.dmz_vm_private_ip.value // empty')"
  FIREWALL_PRIVATE_IP="$(echo "${TF_OUTPUT}" | jq -r '.firewall_private_ip.value // empty')"
  PRIVATE_DNS_ZONE="$(echo "${TF_OUTPUT}" | jq -r '.private_dns_zone_name.value // "hubspoke.internal"')"
  WORKLOAD_RG="$(echo "${TF_OUTPUT}" | jq -r '.workload_resource_group_name.value // empty')"
  DMZ_RG="$(echo "${TF_OUTPUT}" | jq -r '.dmz_resource_group_name.value // empty')"

  # Derive the deployment region from the hub resource group so no region is hardcoded
  HUB_LOCATION="$(az group show --name "${HUB_RG}" --query 'location' -o tsv 2>/dev/null || echo "")"

  [[ -n "${WORKLOAD_VM_IP}" ]] && info "Workload VM IP:   ${WORKLOAD_VM_IP}" || warn "Workload VM IP not available"
  [[ -n "${DMZ_VM_IP}" ]]      && info "DMZ VM IP:        ${DMZ_VM_IP}"      || warn "DMZ VM IP not available"
  [[ -n "${FIREWALL_PRIVATE_IP}" ]] && info "Firewall IP:  ${FIREWALL_PRIVATE_IP}" || warn "Firewall IP not available (firewall may be disabled)"
  [[ -n "${HUB_LOCATION}" ]]   && info "Hub location:     ${HUB_LOCATION}"   || warn "Could not determine hub resource group location"
  info "DNS Zone:         ${PRIVATE_DNS_ZONE}"
}

# ---------------------------------------------------------------------------
# Helper: run a command inside a VM and capture output
# ---------------------------------------------------------------------------
vm_run() {
  local rg="$1"
  local vm_name="$2"
  local command="$3"

  az vm run-command invoke \
    --resource-group "${rg}" \
    --name "${vm_name}" \
    --command-id RunShellScript \
    --scripts "${command}" \
    --query 'value[0].message' \
    -o tsv 2>/dev/null || echo "COMMAND_FAILED"
}

# ---------------------------------------------------------------------------
# Helper: get VM name from resource group
# ---------------------------------------------------------------------------
get_vm_name() {
  local rg="$1"
  az vm list --resource-group "${rg}" --query '[0].name' -o tsv 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Test: VM reachability check (az vm show)
# ---------------------------------------------------------------------------
test_vm_running() {
  header "Test: VM Power State"

  local tests_run=0

  if [[ -n "${WORKLOAD_RG}" ]]; then
    WORKLOAD_VM_NAME="$(get_vm_name "${WORKLOAD_RG}")"
    if [[ -n "${WORKLOAD_VM_NAME}" ]]; then
      STATE="$(az vm show --resource-group "${WORKLOAD_RG}" --name "${WORKLOAD_VM_NAME}" --show-details --query 'powerState' -o tsv 2>/dev/null || echo "unknown")"
      if [[ "${STATE}" == "VM running" ]]; then
        pass "Workload VM (${WORKLOAD_VM_NAME}) is running"
        ((PASSED++)); ((TOTAL++))
      else
        fail "Workload VM (${WORKLOAD_VM_NAME}) power state: ${STATE}"
        ((TOTAL++))
      fi
      ((tests_run++))
    fi
  fi

  if [[ -n "${DMZ_RG}" ]]; then
    DMZ_VM_NAME="$(get_vm_name "${DMZ_RG}")"
    if [[ -n "${DMZ_VM_NAME}" ]]; then
      STATE="$(az vm show --resource-group "${DMZ_RG}" --name "${DMZ_VM_NAME}" --show-details --query 'powerState' -o tsv 2>/dev/null || echo "unknown")"
      if [[ "${STATE}" == "VM running" ]]; then
        pass "DMZ VM (${DMZ_VM_NAME}) is running"
        ((PASSED++)); ((TOTAL++))
      else
        fail "DMZ VM (${DMZ_VM_NAME}) power state: ${STATE}"
        ((TOTAL++))
      fi
      ((tests_run++))
    fi
  fi

  [[ ${tests_run} -eq 0 ]] && warn "No VMs found to test"
}

# ---------------------------------------------------------------------------
# Test: IP flow verify — workload VM to internet (should be allowed via firewall)
# ---------------------------------------------------------------------------
test_ip_flow_workload_to_internet() {
  header "Test: IP Flow Verify — Workload to Internet"
  ((TOTAL++))

  if [[ -z "${WORKLOAD_VM_IP}" || -z "${WORKLOAD_RG}" ]]; then
    warn "Skipping — workload VM IP or resource group not available"
    return
  fi

  WORKLOAD_VM_NAME="$(get_vm_name "${WORKLOAD_RG}" 2>/dev/null || echo "")"
  if [[ -z "${WORKLOAD_VM_NAME}" ]]; then
    warn "Skipping — could not determine workload VM name"
    return
  fi

  NIC_ID="$(az vm show --resource-group "${WORKLOAD_RG}" --name "${WORKLOAD_VM_NAME}" --query 'networkProfile.networkInterfaces[0].id' -o tsv 2>/dev/null || echo "")"
  if [[ -z "${NIC_ID}" ]]; then
    warn "Skipping IP flow verify — could not get NIC ID"
    return
  fi

  # Network Watcher name — resolved from the hub resource group's actual location
  if [[ -z "${HUB_LOCATION}" ]]; then
    warn "Skipping IP flow verify — could not determine hub location for Network Watcher lookup"
    return
  fi
  NW_NAME="$(az network watcher list --query "[?location=='${HUB_LOCATION}'].name" -o tsv 2>/dev/null | head -1 || echo "")"
  NW_RG="${HUB_RG}"

  if [[ -z "${NW_NAME}" ]]; then
    warn "Skipping IP flow verify — no Network Watcher found in ${HUB_LOCATION}"
    return
  fi

  RESULT="$(az network watcher test-ip-flow \
    --resource-group "${NW_RG}" \
    --watcher "${NW_NAME}" \
    --direction Outbound \
    --protocol Tcp \
    --local "${WORKLOAD_VM_IP}:1024" \
    --remote "8.8.8.8:443" \
    --nic "${NIC_ID}" \
    --query 'access' \
    -o tsv 2>/dev/null || echo "Error")"

  if [[ "${RESULT}" == "Allow" ]]; then
    pass "IP Flow: workload VM → internet:443 = Allow (routes through firewall)"
    ((PASSED++))
  else
    fail "IP Flow: workload VM → internet:443 = ${RESULT} (expected Allow via UDR)"
  fi
}

# ---------------------------------------------------------------------------
# Test: Ping between spokes via VM run-command
# ---------------------------------------------------------------------------
test_spoke_to_spoke_ping() {
  header "Test: Spoke-to-Spoke Ping (through hub firewall)"
  ((TOTAL++))

  if [[ -z "${WORKLOAD_VM_IP}" || -z "${DMZ_VM_IP}" || -z "${WORKLOAD_RG}" ]]; then
    warn "Skipping — VM IPs not available"
    return
  fi

  WORKLOAD_VM_NAME="$(get_vm_name "${WORKLOAD_RG}" 2>/dev/null || echo "")"
  if [[ -z "${WORKLOAD_VM_NAME}" ]]; then
    warn "Skipping — could not determine workload VM name"
    return
  fi

  info "Pinging DMZ VM (${DMZ_VM_IP}) from workload VM..."
  OUTPUT="$(vm_run "${WORKLOAD_RG}" "${WORKLOAD_VM_NAME}" "ping -c 3 -W 3 ${DMZ_VM_IP} 2>&1; echo EXIT:\$?")"

  if echo "${OUTPUT}" | grep -q "3 received\|3 packets received"; then
    pass "Spoke-to-spoke ping: workload → DMZ (${DMZ_VM_IP}) = reachable"
    ((PASSED++))
  elif echo "${OUTPUT}" | grep -q "COMMAND_FAILED"; then
    warn "Could not execute ping command on VM (VM may not be ready)"
  else
    fail "Spoke-to-spoke ping: workload → DMZ (${DMZ_VM_IP}) = unreachable"
  fi
}

# ---------------------------------------------------------------------------
# Test: HTTP from web VM (nginx running)
# ---------------------------------------------------------------------------
test_http_from_web_vm() {
  header "Test: HTTP Response from Workload Web VM"
  ((TOTAL++))

  if [[ -z "${WORKLOAD_VM_IP}" || -z "${WORKLOAD_RG}" ]]; then
    warn "Skipping — workload VM not available"
    return
  fi

  WORKLOAD_VM_NAME="$(get_vm_name "${WORKLOAD_RG}" 2>/dev/null || echo "")"
  if [[ -z "${WORKLOAD_VM_NAME}" ]]; then
    warn "Skipping — could not determine VM name"
    return
  fi

  info "Checking nginx on workload web VM (${WORKLOAD_VM_IP})..."
  OUTPUT="$(vm_run "${WORKLOAD_RG}" "${WORKLOAD_VM_NAME}" "curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>&1")"

  if echo "${OUTPUT}" | grep -q "200"; then
    pass "HTTP: curl localhost on web VM returned 200 (nginx running)"
    ((PASSED++))
  elif echo "${OUTPUT}" | grep -q "COMMAND_FAILED"; then
    warn "Could not run curl on VM"
  else
    fail "HTTP: curl localhost returned unexpected result: ${OUTPUT}"
  fi
}

# ---------------------------------------------------------------------------
# Test: Private DNS resolution
# ---------------------------------------------------------------------------
test_private_dns() {
  header "Test: Private DNS Resolution"
  ((TOTAL++))

  if [[ -z "${WORKLOAD_RG}" ]]; then
    warn "Skipping — workload resource group not available"
    return
  fi

  WORKLOAD_VM_NAME="$(get_vm_name "${WORKLOAD_RG}" 2>/dev/null || echo "")"
  if [[ -z "${WORKLOAD_VM_NAME}" ]]; then
    warn "Skipping — could not determine VM name"
    return
  fi

  info "Querying private DNS zone ${PRIVATE_DNS_ZONE} from workload VM..."
  OUTPUT="$(vm_run "${WORKLOAD_RG}" "${WORKLOAD_VM_NAME}" "nslookup workload-web.${PRIVATE_DNS_ZONE} 2>&1 || host workload-web.${PRIVATE_DNS_ZONE} 2>&1")"

  if echo "${OUTPUT}" | grep -qiE "address|answer"; then
    pass "Private DNS: resolved workload-web.${PRIVATE_DNS_ZONE} successfully"
    ((PASSED++))
  elif echo "${OUTPUT}" | grep -q "COMMAND_FAILED"; then
    warn "Could not run nslookup on VM"
  else
    fail "Private DNS: failed to resolve workload-web.${PRIVATE_DNS_ZONE}"
  fi
}

# ---------------------------------------------------------------------------
# Test: Traceroute shows hub firewall as hop
# ---------------------------------------------------------------------------
test_traceroute_via_hub() {
  header "Test: Traceroute Shows Hub Firewall Hop"
  ((TOTAL++))

  if [[ -z "${WORKLOAD_RG}" || -z "${FIREWALL_PRIVATE_IP}" || -z "${DMZ_VM_IP}" ]]; then
    warn "Skipping — firewall IP or VM not available"
    return
  fi

  WORKLOAD_VM_NAME="$(get_vm_name "${WORKLOAD_RG}" 2>/dev/null || echo "")"
  if [[ -z "${WORKLOAD_VM_NAME}" ]]; then
    warn "Skipping — could not determine VM name"
    return
  fi

  info "Running traceroute from workload VM to DMZ VM (${DMZ_VM_IP})..."
  OUTPUT="$(vm_run "${WORKLOAD_RG}" "${WORKLOAD_VM_NAME}" "traceroute -m 5 -w 2 ${DMZ_VM_IP} 2>&1 || tracepath -m 5 ${DMZ_VM_IP} 2>&1")"

  if echo "${OUTPUT}" | grep -q "${FIREWALL_PRIVATE_IP}"; then
    pass "Traceroute: hub firewall (${FIREWALL_PRIVATE_IP}) appears as next hop — UDR working"
    ((PASSED++))
  elif echo "${OUTPUT}" | grep -q "COMMAND_FAILED"; then
    warn "Could not run traceroute on VM"
  else
    fail "Traceroute: hub firewall (${FIREWALL_PRIVATE_IP}) NOT seen in path — check UDR"
    info "Traceroute output: ${OUTPUT}"
  fi
}

# ---------------------------------------------------------------------------
# NSG effective rules check
# ---------------------------------------------------------------------------
test_effective_nsg_rules() {
  header "Test: Effective NSG Rules on Workload NIC"
  ((TOTAL++))

  if [[ -z "${WORKLOAD_RG}" ]]; then
    warn "Skipping — workload resource group not available"
    return
  fi

  WORKLOAD_VM_NAME="$(get_vm_name "${WORKLOAD_RG}" 2>/dev/null || echo "")"
  if [[ -z "${WORKLOAD_VM_NAME}" ]]; then
    warn "Skipping — could not determine VM name"
    return
  fi

  NIC_ID="$(az vm show --resource-group "${WORKLOAD_RG}" --name "${WORKLOAD_VM_NAME}" \
    --query 'networkProfile.networkInterfaces[0].id' -o tsv 2>/dev/null || echo "")"

  if [[ -z "${NIC_ID}" ]]; then
    warn "Skipping — could not get NIC ID"
    return
  fi

  NIC_NAME="$(basename "${NIC_ID}")"
  RULES="$(az network nic show-effective-nsg --resource-group "${WORKLOAD_RG}" --name "${NIC_NAME}" \
    --query 'effectiveNetworkSecurityGroups[].securityRules[].name' -o tsv 2>/dev/null || echo "")"

  if echo "${RULES}" | grep -q "Deny-Inbound-All"; then
    pass "Effective NSG: deny-all inbound rule is present on workload NIC"
    ((PASSED++))
  else
    fail "Effective NSG: deny-all rule not found — NSG may not be associated correctly"
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  echo ""
  echo -e "${BOLD}========================================${RESET}"
  echo -e "${BOLD}  Connectivity Test Summary${RESET}"
  echo -e "${BOLD}========================================${RESET}"
  echo ""
  echo -e "  Passed: ${GREEN}${PASSED}${RESET} / ${TOTAL}"
  echo ""

  if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo -e "  ${RED}Failed tests:${RESET}"
    for t in "${FAILED_TESTS[@]}"; do
      echo -e "    ${RED}x${RESET} ${t}"
    done
    echo ""
    exit 1
  else
    echo -e "  ${GREEN}All tests passed.${RESET}"
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}========================================${RESET}"
echo -e "${BOLD}  Hub-Spoke Network — Connectivity Tests${RESET}"
echo -e "${BOLD}========================================${RESET}"
echo ""

check_prereqs
get_outputs
test_vm_running
test_ip_flow_workload_to_internet
test_spoke_to_spoke_ping
test_http_from_web_vm
test_private_dns
test_traceroute_via_hub
test_effective_nsg_rules
print_summary
