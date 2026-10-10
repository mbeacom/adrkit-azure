# shellcheck shell=bash
# shellcheck disable=SC2154 # RG, RESULTS_DIR, etc. are set by run.sh
# Measurement 2: can azurerm express APIM v2 outbound VNet integration?
# Sourced by measure/run.sh and called from inside measurement 1, while that
# instance exists; do not execute directly.
#
# Plan only: imports measurement 1's instance into an azurerm resource that
# declares virtual_network_type = "External" plus the subnet, and reads the
# plan as JSON. Nothing is applied, so there is nothing to destroy beyond the
# local tfvars and plan file.
#
#   no-op (import only)        -> PASS: azurerm reads the azapi-set integration
#                                 as External + subnet
#   update to virtual_network_* -> FAIL: azurerm does not represent it; azapi
#                                 stays required (clause 12 already says so)
#   plan error                 -> FAIL if it names the attributes, else ERROR

M2=outbound-integration

measure_outbound_integration() {
  local apim_id=$1 apim_name=$2 location=$3 pub_name=$4 pub_email=$5 subnet=$6
  local rc changes actions attrs
  log "=== $M2 (ADR-0056 action item 2, clause 12) against $apim_name"

  tf_write_vars "$M2" "$(jq -n \
    --arg id "$apim_id" --arg n "$apim_name" --arg rg "$RG" --arg l "$location" \
    --arg pn "$pub_name" --arg pe "$pub_email" --arg s "$subnet" \
    '{apim_id: $id, apim_name: $n, resource_group_name: $rg, location: $l,
      publisher_name: $pn, publisher_email: $pe, integration_subnet_id: $s}')"
  tf_init "$M2"

  rc=0
  tf "$M2" plan -input=false -no-color -out=plan.bin \
    >"$RESULTS_DIR/$M2.plan.txt" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    if grep -qi 'virtual_network' "$RESULTS_DIR/$M2.plan.txt"; then
      record "$M2" "azurerm plan with v2 outbound integration" FAIL \
        "plan refused the virtual_network attributes; see $M2.plan.txt"
    else
      record "$M2" "azurerm plan with v2 outbound integration" ERROR \
        "plan exited $rc for another reason; see $M2.plan.txt"
    fi
    tf_destroy "$M2"
    return 0
  fi

  tf "$M2" show -json plan.bin >"$RESULTS_DIR/$M2.plan.json"
  changes=$(jq -c '.resource_changes[] | select(.address == "azurerm_api_management.probe") | {
      actions: .change.actions,
      importing: (.change.importing != null),
      before_type: .change.before.virtual_network_type,
      after_type: .change.after.virtual_network_type,
      before_config: .change.before.virtual_network_configuration,
      after_config: .change.after.virtual_network_configuration,
      changed: ([.change.before as $b | (.change.after // {}) | to_entries[]
                 | select(.value != $b[.key]) | .key])
    }' "$RESULTS_DIR/$M2.plan.json")
  record "$M2" "plan change for the imported instance" INFO "$changes"

  actions=$(printf '%s' "$changes" | jq -r '.actions | join(",")')
  attrs=$(printf '%s' "$changes" | jq -r '.changed | join(",")')
  if [ "$actions" = "no-op" ]; then
    record "$M2" "azurerm represents v2 outbound integration" PASS \
      "import with no update: azurerm reads virtual_network_type External + this subnet"
  elif printf '%s' "$attrs" | grep -q 'virtual_network'; then
    record "$M2" "azurerm represents v2 outbound integration" FAIL \
      "plan would change: $attrs (azurerm does not read the azapi-set integration back)"
  else
    record "$M2" "azurerm represents v2 outbound integration" ERROR \
      "plan action $actions on unrelated attributes ($attrs); adjust ignore_changes and rerun"
  fi

  tf_destroy "$M2"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Sourced by measure/run.sh (runs inside public-network-access). Run: measure/run.sh --only $M2 ..." >&2
  exit 2
fi
