# shellcheck shell=bash
# shellcheck disable=SC2154 # RG, RESULTS_DIR, etc. are set by run.sh
# Measurement 4: APIM "REST API as MCP server" against both MCP protocol eras.
# Sourced by measure/run.sh; do not execute directly.
#
# Applies the root, checks the stub answers as plain REST, records the names
# APIM gave the imported operations, finds the MCP endpoint, then drives it
# with the official MCP Inspector CLI (pinned, ADR-0018's run used 2.8.0):
#   --protocol-era legacy  (2025 era: initialize)
#   --protocol-era modern  (2026-07-28: server/discover, stateless)
#   --protocol-era auto
# For each era: tools/list must list getHello, and tools/call getHello must
# return the stub's body. A raw initialize POST is saved as HTTP evidence.
# Then the explicit destroy.
#
# PASS/FAIL here are per era; neither outcome is a harness error. ADR-0056
# needs the modern result either way (its Revisit-if names this run).

M4=mcp-2026
MCP_READY_TIMEOUT=${MCP_READY_TIMEOUT:-900}

mcp_inspector() { # OUTFILE ERA METHOD [EXTRA...]
  local out=$1 era=$2 method=$3 rc=0
  shift 3
  with_timeout 180 npx -y "@modelcontextprotocol/inspector@${INSPECTOR_VERSION}" --cli "$MCP_URL" \
    --transport http --protocol-era "$era" --stored-auth-only --connect-timeout 30000 \
    --header "Ocp-Apim-Subscription-Key: ${MCP_KEY}" \
    --method "$method" --format json "$@" >"$out" 2>"$out.stderr" || rc=$?
  return "$rc"
}

mcp_stub_ready() {
  local body
  body=$(curl -sS --max-time 20 -H "Ocp-Apim-Subscription-Key: ${MCP_KEY}" "$MCP_STUB_URL" 2>/dev/null) || return 1
  case "$body" in *adrkit-measure*) return 0 ;; *) return 1 ;; esac
}

measure_mcp_2026() {
  local rc apim_id base ops url era out found_by
  log "=== $M4 (ADR-0056 fact 5 / clause 6; ADR-0055 clause 15)"
  tf_write_vars "$M4" "$(base_vars | jq --arg e "$PUBLISHER_EMAIL" '. + {publisher_email: $e}')"
  tf_init "$M4"

  rc=0
  tf_apply "$M4" || rc=$?
  if [ "$rc" -ne 0 ]; then
    if tf_error_attributed_to "$LAST_APPLY_LOG" azapi_resource.mcp_tool; then
      record "$M4" "MCP tool referencing operation getHello" FAIL \
        "tool create failed; APIM may not name imported operations by operationId (TODO(openapi)); see $(basename "$LAST_APPLY_LOG")"
    else
      record "$M4" "apply" ERROR \
        "terraform apply exited $rc, errors on: $(tf_error_summary "$LAST_APPLY_LOG"); inconclusive. See $(basename "$LAST_APPLY_LOG")"
    fi
    tf_destroy "$M4"
    return 0
  fi
  record "$M4" "MCP tool referencing operation getHello" PASS "apply created the tool against .../operations/getHello"

  apim_id=$(tf "$M4" output -raw apim_id)
  base=$(tf "$M4" output -raw mcp_base_url)
  MCP_STUB_URL=$(tf "$M4" output -raw stub_url)
  MCP_KEY=$(tf "$M4" output -raw subscription_key)

  ops=$(arm_get "${apim_id}/apis/stub/operations" 2024-05-01 2>/dev/null |
    jq -r '.value[].name' 2>/dev/null | tr '\n' ' ')
  record "$M4" "names APIM gave the imported operations" INFO "$ops"

  if wait_until "$MCP_READY_TIMEOUT" 20 mcp_stub_ready; then
    record "$M4" "stub answers as plain REST" PASS "after ${WAIT_ELAPSED}s"
  else
    record "$M4" "stub answers as plain REST" ERROR "no stub body after ${WAIT_ELAPSED}s; MCP results below may reflect that"
  fi

  # Endpoint: the documented <api-path>/mcp first, then the API base, each in
  # both eras, so an endpoint that serves only one era is still found.
  MCP_URL="" found_by=""
  for url in "$base/mcp" "$base"; do
    for era in legacy modern; do
      MCP_URL=$url
      if mcp_inspector "$RESULTS_DIR/$M4.endpoint-probe.json" "$era" tools/list; then
        found_by=$era
        break 2
      fi
    done
    MCP_URL=""
  done
  if [ -z "$MCP_URL" ]; then
    MCP_URL="$base/mcp"
    record "$M4" "MCP endpoint" INFO "neither $base/mcp nor $base answered tools/list in either era; using $MCP_URL"
  else
    record "$M4" "MCP endpoint" INFO "$MCP_URL (first answered on $found_by)"
  fi

  for era in legacy modern auto; do
    out="$RESULTS_DIR/$M4.$era.tools-list.json"
    rc=0
    mcp_inspector "$out" "$era" tools/list || rc=$?
    if [ "$rc" -eq 0 ] && jq -e '[.. | objects | select(.name? == "getHello")] | length > 0' "$out" >/dev/null 2>&1; then
      record "$M4" "$era tools/list" PASS "getHello listed"
    else
      record "$M4" "$era tools/list" FAIL "exit $rc; see $(basename "$out") and .stderr"
    fi

    out="$RESULTS_DIR/$M4.$era.tools-call.json"
    rc=0
    mcp_inspector "$out" "$era" tools/call --tool-name getHello || rc=$?
    if [ "$rc" -eq 0 ] && grep -q 'adrkit-measure' "$out"; then
      record "$M4" "$era tools/call getHello" PASS "stub body returned"
    else
      record "$M4" "$era tools/call getHello" FAIL "exit $rc; see $(basename "$out") and .stderr"
    fi
  done

  # Raw HTTP evidence for the 2025 era: status, headers (Mcp-Session-Id means
  # APIM kept a session), and body of one initialize.
  curl -sS -D "$RESULTS_DIR/$M4.raw-initialize.headers" -o "$RESULTS_DIR/$M4.raw-initialize.body" \
    --max-time 30 -X POST "$MCP_URL" \
    -H "Ocp-Apim-Subscription-Key: ${MCP_KEY}" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"adrkit-measure","version":"0"}}}' \
    2>/dev/null || true
  record "$M4" "raw initialize response" INFO \
    "$(head -n 1 "$RESULTS_DIR/$M4.raw-initialize.headers" 2>/dev/null | tr -d '\r'); session header: $(grep -i '^mcp-session-id' "$RESULTS_DIR/$M4.raw-initialize.headers" >/dev/null 2>&1 && echo present || echo absent)"

  MCP_KEY=""
  tf_destroy "$M4"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Sourced by measure/run.sh. Run: measure/run.sh --only $M4 --resource-group RG --subscription SUB" >&2
  exit 2
fi
