# shellcheck shell=bash
# shellcheck disable=SC2154 # RG, RESULTS_DIR, etc. are set by run.sh
# Measurement 1: publicNetworkAccess flip on APIM Standard v2. Sourced by
# measure/run.sh; do not execute directly.
#
# Steps: apply public_access=false, then true, then false. After each:
#   1. read properties.publicNetworkAccess from ARM at the flip's own API
#      version (az rest), polling until it equals the expected value;
#   2. read az apim show's view of the same property (secondary);
#   3. probe the gateway's status endpoint from this machine (outside the
#      VNet), polling until it matches: Enabled -> any HTTP answer other than
#      403; Disabled -> no answer or 403;
#   4. terraform plan -detailed-exitcode must be 0 (no plan reverts the flip).
# After the first apply it also reads the outbound integration azapi set, and
# runs measurement 2 (outbound-integration) against this instance if selected.
# Then the explicit destroy.

M1=public-network-access
PNA_ARM_TIMEOUT=${PNA_ARM_TIMEOUT:-1800}
PNA_PROBE_TIMEOUT=${PNA_PROBE_TIMEOUT:-1800}

pna_arm_value() {
  az rest --method get \
    --url "https://management.azure.com${PNA_APIM_ID}?api-version=${PNA_API_VERSION}" \
    --query properties.publicNetworkAccess -o tsv 2>/dev/null
}

pna_arm_is() { [ "$(pna_arm_value)" = "$1" ]; }

# Sets PROBE_RC (curl exit), PROBE_HTTP (status or 000), PROBE_BODY (head).
pna_probe() {
  local tmp
  tmp=$(mktemp)
  PROBE_RC=0
  PROBE_HTTP=$(curl -sS -o "$tmp" -w '%{http_code}' --connect-timeout 10 --max-time 20 \
    "https://${PNA_HOST}/status-0123456789abcdef" 2>>"$RESULTS_DIR/$M1.probe.stderr") || PROBE_RC=$?
  PROBE_BODY=$(head -c 300 "$tmp" | tr '\n\r' '  ')
  rm -f "$tmp"
  printf '%s step=%s rc=%s http=%s body=%s\n' "$(date -u +%FT%TZ)" "$PNA_STEP" "$PROBE_RC" "$PROBE_HTTP" "$PROBE_BODY" \
    >>"$RESULTS_DIR/$M1.probes.log"
}

pna_probe_matches() { # Enabled|Disabled
  pna_probe
  if [ "$1" = Enabled ]; then
    [ "$PROBE_RC" -eq 0 ] && [ "$PROBE_HTTP" != 000 ] && [ "$PROBE_HTTP" != 403 ]
  else
    [ "$PROBE_RC" -ne 0 ] || [ "$PROBE_HTTP" = 000 ] || [ "$PROBE_HTTP" = 403 ]
  fi
}

pna_observe() { # STEP PUBLIC_ACCESS EXPECTED
  local step=$1 pa=$2 expected=$3 cli dns rc
  PNA_STEP=$step

  if wait_until "$PNA_ARM_TIMEOUT" 20 pna_arm_is "$expected"; then
    record "$M1" "step $step ARM publicNetworkAccess" PASS "$expected after ${WAIT_ELAPSED}s"
  else
    record "$M1" "step $step ARM publicNetworkAccess" FAIL \
      "expected $expected, still '$(pna_arm_value)' after ${WAIT_ELAPSED}s"
  fi

  cli=$(azs apim show --name "$PNA_APIM_NAME" --resource-group "$RG" --query publicNetworkAccess -o tsv 2>&1 || true)
  record "$M1" "step $step az apim show publicNetworkAccess" INFO "$cli"

  if [ "$dig_available" -eq 1 ]; then
    dns=$(dig +short "$PNA_HOST" | tr '\n' ' ')
    record "$M1" "step $step public DNS for gateway" INFO "$dns"
  fi

  if wait_until "$PNA_PROBE_TIMEOUT" 30 pna_probe_matches "$expected"; then
    record "$M1" "step $step gateway probe from outside" PASS \
      "$expected: curl rc=$PROBE_RC http=$PROBE_HTTP after ${WAIT_ELAPSED}s"
  else
    record "$M1" "step $step gateway probe from outside" FAIL \
      "$expected expected; last curl rc=$PROBE_RC http=$PROBE_HTTP body=$PROBE_BODY after ${WAIT_ELAPSED}s"
  fi

  rc=0
  tf "$M1" plan -detailed-exitcode -input=false -no-color -var "public_access=$pa" \
    >"$RESULTS_DIR/$M1.step$step.plan.txt" 2>&1 || rc=$?
  case "$rc" in
  0) record "$M1" "step $step plan after apply" PASS "no changes (ignore_changes holds)" ;;
  2)
    # Name the resources: a diff on azurerm_api_management.this means
    # ignore_changes is wrong; a diff on an azapi_update_resource means ARM
    # normalised the body (a perpetual azapi diff), which is a different fix.
    record "$M1" "step $step plan after apply" FAIL \
      "plan proposes changes to: $(grep -E '^ *# .* (will be|must be)' "$RESULTS_DIR/$M1.step$step.plan.txt" | sed -E 's/^ *# ([^ ]+).*/\1/' | tr '\n' ' ')(see $M1.step$step.plan.txt)"
    ;;
  *) record "$M1" "step $step plan after apply" ERROR "plan exited $rc; see $M1.step$step.plan.txt" ;;
  esac
}

pna_read_outbound() {
  local vnt subnet expected_subnet
  expected_subnet=$(tf "$M1" output -raw integration_subnet_id)
  vnt=$(az rest --method get \
    --url "https://management.azure.com${PNA_APIM_ID}?api-version=${PNA_API_VERSION}" \
    --query properties.virtualNetworkType -o tsv 2>/dev/null || true)
  subnet=$(az rest --method get \
    --url "https://management.azure.com${PNA_APIM_ID}?api-version=${PNA_API_VERSION}" \
    --query properties.virtualNetworkConfiguration.subnetResourceId -o tsv 2>/dev/null || true)
  # ARM IDs compare case-insensitively (no ${x,,}: macOS ships bash 3.2).
  if [ "$vnt" = External ] && [ "$(lower "$subnet")" = "$(lower "$expected_subnet")" ]; then
    record "$M1" "azapi outbound integration body took effect" PASS "virtualNetworkType=External, subnet matches"
  else
    record "$M1" "azapi outbound integration body took effect" FAIL \
      "virtualNetworkType='$vnt' subnetResourceId='$subnet' (expected External, $expected_subnet)"
  fi
}

measure_public_network_access() {
  local step pa expected rc
  log "=== $M1 (ADR-0056 action item 2, clause 7)"
  tf_write_vars "$M1" "$(base_vars | jq --arg e "$PUBLISHER_EMAIL" '. + {publisher_email: $e, public_access: false}')"
  tf_init "$M1"

  for step in 1 2 3; do
    case "$step" in
    2) pa=true expected=Enabled ;;
    *) pa=false expected=Disabled ;;
    esac
    rc=0
    tf_apply "$M1" -var "public_access=$pa" || rc=$?
    if [ "$rc" -ne 0 ]; then
      record "$M1" "step $step apply public_access=$pa" FAIL \
        "terraform apply exited $rc; see $M1.terraform.log (an error on azapi_update_resource is the clause 7 failure)"
      break
    fi
    record "$M1" "step $step apply public_access=$pa" PASS "apply succeeded"

    PNA_APIM_ID=$(tf "$M1" output -raw apim_id)
    PNA_APIM_NAME=$(tf "$M1" output -raw apim_name)
    PNA_HOST=$(tf "$M1" output -raw gateway_hostname)
    PNA_API_VERSION=$(tf "$M1" output -raw service_api_version)

    pna_observe "$step" "$pa" "$expected"

    if [ "$step" = 1 ]; then
      pna_read_outbound
      if selected outbound-integration; then
        measure_outbound_integration \
          "$PNA_APIM_ID" "$PNA_APIM_NAME" "$(tf "$M1" output -raw location)" \
          "$(tf "$M1" output -raw publisher_name)" "$(tf "$M1" output -raw publisher_email)" \
          "$(tf "$M1" output -raw integration_subnet_id)"
      fi
    fi
  done

  tf_destroy "$M1"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Sourced by measure/run.sh. Run: measure/run.sh --only $M1 --resource-group RG --subscription SUB" >&2
  exit 2
fi
