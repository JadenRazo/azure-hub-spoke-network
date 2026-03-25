#!/usr/bin/env bash
# generate-traffic-report.sh — Query Log Analytics for network traffic data and
# output a formatted report.
#
# Usage:
#   ./generate-traffic-report.sh [--workspace-id <id>] [--hours <n>] [--output <file>]
#
# Options:
#   --workspace-id  Log Analytics workspace resource ID (reads from terraform output if omitted)
#   --hours         Lookback window in hours (default: 24)
#   --output        Write report to file instead of stdout
#
# Prerequisites:
#   - az CLI authenticated
#   - terraform output accessible from terraform/ directory
#   - Log Analytics workspace with Traffic Analytics data

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

info()    { echo -e "${CYAN}[INFO]${RESET}  $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
section() { printf "\n%s\n%s\n" "${BOLD}$*${RESET}" "$(printf '=%.0s' {1..60})"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
WORKSPACE_ID=""
HOURS=24
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-id)
      WORKSPACE_ID="$2"
      shift 2
      ;;
    --hours)
      HOURS="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,20p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      die "Unknown argument: $1. Use --help for usage."
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Get workspace ID from terraform if not provided
# ---------------------------------------------------------------------------
get_workspace_id() {
  if [[ -n "${WORKSPACE_ID}" ]]; then
    return
  fi

  if [[ ! -d "${TERRAFORM_DIR}/.terraform" ]]; then
    die "Terraform not initialized and --workspace-id not provided."
  fi

  info "Reading workspace ID from terraform output..."
  WORKSPACE_ID="$(terraform -chdir="${TERRAFORM_DIR}" output -raw log_analytics_workspace_id 2>/dev/null || echo "")"

  if [[ -z "${WORKSPACE_ID}" ]]; then
    die "Could not retrieve Log Analytics workspace ID. Pass --workspace-id explicitly."
  fi

  info "Using workspace: ${WORKSPACE_ID}"
}

# ---------------------------------------------------------------------------
# Run a KQL query and return tab-separated results
# ---------------------------------------------------------------------------
run_query() {
  local description="$1"
  local query="$2"

  info "Querying: ${description}..."

  az monitor log-analytics query \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${query}" \
    --timespan "PT${HOURS}H" \
    --output table 2>/dev/null || {
      warn "Query failed or no data available for: ${description}"
      echo "(no data)"
    }
}

# ---------------------------------------------------------------------------
# Build the report
# ---------------------------------------------------------------------------
build_report() {
  TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  LOOKBACK_START="$(date -u -d "${HOURS} hours ago" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -v-"${HOURS}"H '+%Y-%m-%d %H:%M:%S UTC')"

  # Redirect output to file if requested
  if [[ -n "${OUTPUT_FILE}" ]]; then
    exec > "${OUTPUT_FILE}"
    info "Writing report to ${OUTPUT_FILE}" >&2
  fi

  printf "%s\n" "Hub-Spoke Network — Traffic Report"
  printf "%s\n" "Generated:  ${TIMESTAMP}"
  printf "%s\n" "Lookback:   ${LOOKBACK_START} → now (${HOURS}h)"
  printf "%s\n" "Workspace:  ${WORKSPACE_ID}"
  printf "\n"

  # -------------------------------------------------------------------------
  # 1. Top Talkers (source IPs by bytes sent)
  # -------------------------------------------------------------------------
  section "1. Top Talkers — Source IPs by Bytes Sent"

  run_query "Top talkers" "
AzureNetworkAnalytics_CL
| where TimeGenerated >= ago(${HOURS}h)
| where SubType_s == 'FlowLog'
| where FlowType_s != 'MaliciousFlow'
| summarize TotalBytesSent = sum(BytesSent_d) by SrcIP_s
| top 20 by TotalBytesSent desc
| project SourceIP = SrcIP_s, BytesSent = TotalBytesSent, MBSent = round(TotalBytesSent / 1048576, 2)
| order by BytesSent desc
"

  # -------------------------------------------------------------------------
  # 2. Blocked Traffic (denied flows)
  # -------------------------------------------------------------------------
  section "2. Blocked Traffic — Top Denied Flows"

  run_query "Blocked traffic" "
AzureNetworkAnalytics_CL
| where TimeGenerated >= ago(${HOURS}h)
| where SubType_s == 'FlowLog'
| where FlowStatus_s == 'D'
| summarize DeniedCount = count() by SrcIP_s, DestIP_s, DestPort_d, L4Protocol_s
| top 20 by DeniedCount desc
| project SourceIP = SrcIP_s, DestIP = DestIP_s, DestPort = tostring(toint(DestPort_d)), Protocol = L4Protocol_s, DeniedFlows = DeniedCount
| order by DeniedFlows desc
"

  # -------------------------------------------------------------------------
  # 3. Allowed Traffic by Destination Port
  # -------------------------------------------------------------------------
  section "3. Allowed Traffic — By Destination Port"

  run_query "Allowed by port" "
AzureNetworkAnalytics_CL
| where TimeGenerated >= ago(${HOURS}h)
| where SubType_s == 'FlowLog'
| where FlowStatus_s == 'A'
| summarize FlowCount = count(), TotalBytes = sum(BytesSent_d) by DestPort_d, L4Protocol_s
| project DestPort = tostring(toint(DestPort_d)), Protocol = L4Protocol_s, FlowCount, TotalMB = round(TotalBytes / 1048576, 2)
| order by FlowCount desc
| top 25 by FlowCount desc
"

  # -------------------------------------------------------------------------
  # 4. Traffic Volume Over Time (hourly buckets)
  # -------------------------------------------------------------------------
  section "4. Traffic Volume Over Time (hourly)"

  run_query "Traffic volume over time" "
AzureNetworkAnalytics_CL
| where TimeGenerated >= ago(${HOURS}h)
| where SubType_s == 'FlowLog'
| summarize
    AllowedFlows = countif(FlowStatus_s == 'A'),
    DeniedFlows = countif(FlowStatus_s == 'D'),
    TotalMB = round(sum(BytesSent_d) / 1048576, 2)
  by bin(TimeGenerated, 1h)
| order by TimeGenerated asc
| project TimeWindow = TimeGenerated, AllowedFlows, DeniedFlows, TotalMB
"

  # -------------------------------------------------------------------------
  # 5. Azure Firewall — Top Application Rules Hit
  # -------------------------------------------------------------------------
  section "5. Azure Firewall — Application Rules"

  run_query "Firewall application rules" "
AzureDiagnostics
| where TimeGenerated >= ago(${HOURS}h)
| where Category == 'AzureFirewallApplicationRule'
| summarize HitCount = count() by FQDN = msg_s, Action = action_s
| top 20 by HitCount desc
| project FQDN, Action, HitCount
| order by HitCount desc
"

  # -------------------------------------------------------------------------
  # 6. Azure Firewall — Top Network Rules Hit
  # -------------------------------------------------------------------------
  section "6. Azure Firewall — Network Rules"

  run_query "Firewall network rules" "
AzureDiagnostics
| where TimeGenerated >= ago(${HOURS}h)
| where Category == 'AzureFirewallNetworkRule'
| extend RuleName = split(msg_s, '.')[0]
| summarize HitCount = count() by tostring(RuleName), Action = action_s, Protocol = proto_s
| top 20 by HitCount desc
| order by HitCount desc
"

  # -------------------------------------------------------------------------
  # 7. Threat Intelligence Hits
  # -------------------------------------------------------------------------
  section "7. Threat Intelligence Hits"

  run_query "Threat intel hits" "
AzureDiagnostics
| where TimeGenerated >= ago(${HOURS}h)
| where Category == 'AZFWThreatIntel'
| summarize HitCount = count() by SourceIP = msg_s, Action = action_s
| order by HitCount desc
| top 10 by HitCount desc
"

  # -------------------------------------------------------------------------
  # 8. Bastion Session Audit
  # -------------------------------------------------------------------------
  section "8. Bastion Session Audit"

  run_query "Bastion sessions" "
AzureDiagnostics
| where TimeGenerated >= ago(${HOURS}h)
| where Category == 'BastionAuditLogs'
| project TimeGenerated, UserAgent = UserAgent_s, TargetVMIPAddress = TargetVMIPAddress_s, SessionDuration = SessionDurationInMins_d
| order by TimeGenerated desc
"

  printf "\n%s\n" "--- End of Report ---"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if ! command -v az &>/dev/null; then
  die "Azure CLI not found."
fi

if ! az account show &>/dev/null; then
  die "Not logged in. Run 'az login' first."
fi

get_workspace_id
build_report

if [[ -n "${OUTPUT_FILE}" ]]; then
  echo -e "${GREEN}Report written to: ${OUTPUT_FILE}${RESET}" >&2
fi
