#!/usr/bin/env bash
# Rung-1 measurements for ADR-0056 (mbeacom/adrkit#297). Creates real, billed
# Azure resources in a throwaway resource group, one measurement at a time,
# and destroys each one before the next starts. See measure/README.md.
#
#   measure/run.sh --resource-group RG --subscription SUB [options]
#
# Options:
#   --resource-group RG     existing, throwaway resource group (required)
#   --subscription SUB      subscription ID or name (required)
#   --location REGION       region (default: the resource group's)
#   --publisher-email ADDR  APIM publisher email (default: signed-in user)
#   --only LIST             comma-separated subset, in this order:
#                             public-network-access, outbound-integration,
#                             azure-files-swap, mcp-2026, hmac-policy
#                           outbound-integration runs inside
#                           public-network-access, so selecting it alone
#                           also runs that.
#   --allow-nonempty-rg     proceed although the group already has resources
#   --preflight-only        check tools, login, group, and providers; create
#                           nothing and ask nothing
#   -h, --help
#
# Exit: 0 all PASS/INFO; 3 at least one FAIL or ERROR (see the summary);
# 1 harness or usage error; 130 interrupted (teardown still runs).
set -euo pipefail

MEASURE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$MEASURE_DIR/lib.sh"

ALL_MEASUREMENTS=(public-network-access outbound-integration azure-files-swap mcp-2026 hmac-policy)
INSPECTOR_VERSION=${INSPECTOR_VERSION:-2.8.0}

RG="" SUB="" LOCATION="" PUBLISHER_EMAIL="" ONLY="" ALLOW_NONEMPTY=0 PREFLIGHT_ONLY=0
CONFIRMED=0

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
  --resource-group) RG=${2:?--resource-group needs a value}; shift 2 ;;
  --subscription) SUB=${2:?--subscription needs a value}; shift 2 ;;
  --location) LOCATION=${2:?--location needs a value}; shift 2 ;;
  --publisher-email) PUBLISHER_EMAIL=${2:?--publisher-email needs a value}; shift 2 ;;
  --only) ONLY=${2:?--only needs a value}; shift 2 ;;
  --allow-nonempty-rg) ALLOW_NONEMPTY=1; shift ;;
  --preflight-only) PREFLIGHT_ONLY=1; shift ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; die "unknown argument: $1" ;;
  esac
done

[ -n "$RG" ] || { usage >&2; die "--resource-group is required"; }
[ -n "$SUB" ] || { usage >&2; die "--subscription is required"; }

# Selection, normalised to run order.
SELECTED=()
if [ -z "$ONLY" ]; then
  SELECTED=("${ALL_MEASUREMENTS[@]}")
else
  IFS=',' read -r -a wanted <<<"$ONLY"
  for w in "${wanted[@]}"; do
    case " ${ALL_MEASUREMENTS[*]} " in
    *" $w "*) ;;
    *) die "unknown measurement in --only: $w" ;;
    esac
  done
  for m in "${ALL_MEASUREMENTS[@]}"; do
    for w in "${wanted[@]}"; do [ "$m" = "$w" ] && SELECTED+=("$m"); done
  done
fi
selected() { case " ${SELECTED[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
if selected outbound-integration && ! selected public-network-access; then
  log "outbound-integration plans against the public-network-access instance; adding it."
  SELECTED=(public-network-access "${SELECTED[@]}")
fi

# ---------------------------------------------------------------- preflight
need=(terraform az jq curl perl)
selected hmac-policy && need+=(openssl)
selected mcp-2026 && need+=(npx)
for c in "${need[@]}"; do
  command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
done
# dig_available is read by public-network-access/measure.sh.
# shellcheck disable=SC2034
if command -v dig >/dev/null 2>&1; then dig_available=1; else dig_available=0; fi

# The Azure CLI default subscription is never changed: every az call that is
# subscription-scoped goes through azs (lib.sh), which passes --subscription,
# and Terraform gets ARM_SUBSCRIPTION_ID. ORIG_DEFAULT_SUB is only checked
# (and restored if something else moved it) when the run ends.
ORIG_DEFAULT_SUB=$(az account show --query id -o tsv 2>/dev/null) ||
  die "not logged in: run 'az login' first"
SUB_ID=$(az account show --subscription "$SUB" --query id -o tsv) ||
  die "cannot find subscription $SUB"
SUB_NAME=$(azs account show --query name -o tsv)
TENANT_ID=$(azs account show --query tenantId -o tsv)
export ARM_SUBSCRIPTION_ID=$SUB_ID

if selected azure-files-swap; then
  az containerapp --help >/dev/null 2>&1 ||
    die "the az containerapp extension is missing: az extension add --name containerapp"
fi

azs group show --name "$RG" >/dev/null 2>&1 ||
  die "resource group $RG not found in $SUB_NAME. Create a throwaway one first (az group create)."
RG_LOCATION=$(azs group show --name "$RG" --query location -o tsv)
LOCATION=${LOCATION:-$RG_LOCATION}
RG_COUNT=$(azs resource list --resource-group "$RG" --query "length(@)" -o tsv)

if [ -z "$PUBLISHER_EMAIL" ]; then
  PUBLISHER_EMAIL=$(azs account show --query user.name -o tsv)
fi
case "$PUBLISHER_EMAIL" in
*@*.*) ;;
*) die "no usable publisher email ($PUBLISHER_EMAIL); pass --publisher-email" ;;
esac

providers_ok=1
for ns in Microsoft.ApiManagement Microsoft.Network Microsoft.App Microsoft.Storage Microsoft.OperationalInsights Microsoft.Web; do
  state=$(azs provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo unknown)
  if [ "$state" != "Registered" ]; then
    warn "resource provider $ns is $state (az provider register --namespace $ns)"
    providers_ok=0
  fi
done

cat <<EOF

adrkit rung-1 measurements (ADR-0056, mbeacom/adrkit#297)
  subscription     $SUB_NAME ($SUB_ID), tenant $TENANT_ID
  resource group   $RG ($RG_COUNT existing resources)
  region           $LOCATION
  publisher email  $PUBLISHER_EMAIL
  measurements     ${SELECTED[*]}
  terraform        $(terraform version | head -n 1)
  az               $(az version --query '"azure-cli"' -o tsv)
EOF
selected mcp-2026 && echo "  MCP Inspector    @modelcontextprotocol/inspector@$INSPECTOR_VERSION (via npx)"

if [ "$providers_ok" -ne 1 ]; then
  die "register the resource providers above, then rerun"
fi
if [ "$RG_COUNT" != "0" ] && [ "$ALLOW_NONEMPTY" -ne 1 ]; then
  die "$RG is not empty. Use a fresh throwaway group, or pass --allow-nonempty-rg."
fi
if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
  restore_default_subscription
  log "Preflight passed. Nothing was created."
  exit 0
fi

cat <<EOF

This creates BILLED resources in $RG, one measurement at a time:
$(selected public-network-access && echo "  - APIM Standard v2 + VNet + private endpoint (public-network-access; outbound-integration plans against it)")
$(selected azure-files-swap && echo "  - Storage account + Files share + Container Apps environment + 2 jobs (azure-files-swap)")
$(selected mcp-2026 && echo "  - APIM Standard v2 (public) with a stub API and an MCP API (mcp-2026)")
$(selected hmac-policy && echo "  - APIM Standard v2 (public) with a webhook API and a secret named value (hmac-policy)")
Each is destroyed before the next starts; anything left is destroyed on exit,
including Ctrl-C. Each APIM instance can take tens of minutes to create.

EOF
answer=""
if [ -r /dev/tty ]; then
  read -r -p "Type the resource group name ($RG) to proceed: " answer </dev/tty || true
fi
[ "$answer" = "$RG" ] || die "not confirmed; nothing was created"
CONFIRMED=1

# ---------------------------------------------------------------- run
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
NAME_PREFIX="am$(date -u +%m%d%H%M)"
RESULTS_DIR="$MEASURE_DIR/results/$RUN_ID"
SUMMARY="$RESULTS_DIR/summary.txt"
mkdir -p "$RESULTS_DIR"
: >"$SUMMARY"
exec > >(tee -a "$RESULTS_DIR/run.log") 2>&1

trap cleanup EXIT
trap 'exit 130' INT TERM

{
  echo "run_id=$RUN_ID"
  echo "name_prefix=$NAME_PREFIX"
  echo "subscription=$SUB_ID"
  echo "resource_group=$RG"
  echo "location=$LOCATION"
  echo "terraform=$(terraform version -json | jq -r .terraform_version)"
  echo "az=$(az version --query '"azure-cli"' -o tsv)"
  echo "inspector=$INSPECTOR_VERSION"
  echo "measurements=${SELECTED[*]}"
} >"$RESULTS_DIR/environment.txt"
log "Run $RUN_ID; results in $RESULTS_DIR"

# Inputs every root shares.
base_vars() {
  jq -n --arg rg "$RG" --arg loc "$LOCATION" --arg p "$NAME_PREFIX" --arg r "$RUN_ID" \
    '{resource_group_name: $rg, location: $loc, name_prefix: $p, run_id: $r}'
}

for m in public-network-access outbound-integration azure-files-swap mcp-2026 hmac-policy; do
  # shellcheck source=/dev/null
  . "$MEASURE_DIR/$m/measure.sh"
done

for m in "${SELECTED[@]}"; do
  case "$m" in
  public-network-access) measure_public_network_access ;;
  outbound-integration) ;; # runs inside public-network-access
  azure-files-swap) measure_azure_files_swap ;;
  mcp-2026) measure_mcp_2026 ;;
  hmac-policy) measure_hmac_policy ;;
  esac
done

log "All selected measurements finished."
# cleanup (EXIT trap) prints the summary and sets the exit code.
