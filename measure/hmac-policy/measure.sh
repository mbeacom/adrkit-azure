# shellcheck shell=bash
# shellcheck disable=SC2154 # RG, RESULTS_DIR, etc. are set by run.sh
# Measurement 5: GitHub X-Hub-Signature-256 HMAC verified in APIM policy.
# Sourced by measure/run.sh; do not execute directly.
#
# Generates a random hex secret, applies the root (the secret becomes a
# secret named value), waits until the policy is live, then posts bodies
# signed exactly as GitHub signs them ("sha256=" + lowercase hex
# HMAC-SHA256 over the raw bytes, computed here with openssl) and asserts
# the status of each:
#   correct signature                     200
#   signature made with another secret    401
#   no signature header                   401
#   body changed after signing            401
#   sha1= prefix (GitHub's old header)    401
#   correct, non-ASCII UTF-8 body         200  (hashing raw bytes, not text)
#   correct, empty body                   200
#   correct, ~1 MiB body                  200  (body size APIM will buffer)
# If APIM refuses to save the policy, that is recorded as the result
# (clause 9 is dropped), not as a harness error. Then the explicit destroy.

M5=hmac-policy
HMAC_READY_TIMEOUT=${HMAC_READY_TIMEOUT:-900}

hmac_sign() { # SECRET FILE -> sha256=<hex>
  printf 'sha256=%s' "$(openssl dgst -sha256 -hmac "$1" <"$2" | awk '{print $NF}')"
}

# hmac_send FILE SIGNATURE|"" -> prints the HTTP status (000 on no answer)
hmac_send() {
  local file=$1 sig=$2 args
  args=(-sS -o /dev/null -w '%{http_code}' --max-time 60 -X POST
    -H 'Content-Type: application/json' -H 'X-GitHub-Event: ping'
    -H "X-GitHub-Delivery: adrkit-measure-$RUN_ID")
  [ -n "$sig" ] && args+=(-H "X-Hub-Signature-256: $sig")
  curl "${args[@]}" --data-binary "@$file" "$HMAC_URL" 2>/dev/null || true
}

hmac_policy_live() { [ "$(hmac_send "$HMAC_DIR/ping.json" "")" = 401 ]; }

hmac_case() { # NAME FILE SIGNATURE EXPECTED
  local code
  code=$(hmac_send "$2" "$3")
  [ -n "$code" ] || code=000
  if [ "$code" = "$4" ]; then
    record "$M5" "$1" PASS "HTTP $code"
  else
    record "$M5" "$1" FAIL "HTTP $code, expected $4"
  fi
}

measure_hmac_policy() {
  local rc secret other
  log "=== $M5 (ADR-0056 action item 5, clause 9)"
  secret=$(openssl rand -hex 32)
  other=$(openssl rand -hex 32)
  tf_write_vars "$M5" "$(base_vars | jq --arg e "$PUBLISHER_EMAIL" --arg s "$secret" \
    '. + {publisher_email: $e, webhook_secret: $s}')"
  tf_init "$M5"

  rc=0
  tf_apply "$M5" || rc=$?
  if [ "$rc" -ne 0 ]; then
    if grep -q 'azurerm_api_management_api_policy.webhook' "$RESULTS_DIR/$M5.terraform.log"; then
      record "$M5" "APIM accepts the HMAC policy" FAIL \
        "APIM rejected the policy document; ADR-0056 clause 9's drop condition. See $M5.terraform.log"
    else
      record "$M5" "apply" ERROR "terraform apply exited $rc; see $M5.terraform.log"
    fi
    tf_destroy "$M5"
    return 0
  fi
  record "$M5" "APIM accepts the HMAC policy" PASS "policy saved"

  HMAC_URL=$(tf "$M5" output -raw webhook_url)
  HMAC_DIR=$(mktemp -d)
  printf '%s' '{"zen":"Design for failure.","hook_id":1,"hook":{"type":"Repository"}}' >"$HMAC_DIR/ping.json"
  printf '%s' '{"zen":"Design for failure.","hook_id":2,"hook":{"type":"Repository"}}' >"$HMAC_DIR/tampered.json"
  printf '%s' '{"msg":"Grüße – décision ✓ 決定"}' >"$HMAC_DIR/utf8.json"
  : >"$HMAC_DIR/empty.json"
  {
    printf '{"pad":"'
    head -c 1048576 /dev/zero | tr '\0' 'a'
    printf '"}'
  } >"$HMAC_DIR/large.json"

  if wait_until "$HMAC_READY_TIMEOUT" 20 hmac_policy_live; then
    record "$M5" "policy live (unsigned request answered 401)" INFO "after ${WAIT_ELAPSED}s"
  else
    record "$M5" "policy live (unsigned request answered 401)" ERROR \
      "last status $(hmac_send "$HMAC_DIR/ping.json" "") after ${WAIT_ELAPSED}s; cases below may be inconclusive"
  fi

  hmac_case "correct signature" "$HMAC_DIR/ping.json" "$(hmac_sign "$secret" "$HMAC_DIR/ping.json")" 200
  hmac_case "signature from another secret" "$HMAC_DIR/ping.json" "$(hmac_sign "$other" "$HMAC_DIR/ping.json")" 401
  hmac_case "no signature header" "$HMAC_DIR/ping.json" "" 401
  hmac_case "body changed after signing" "$HMAC_DIR/tampered.json" "$(hmac_sign "$secret" "$HMAC_DIR/ping.json")" 401
  hmac_case "sha1= prefix" "$HMAC_DIR/ping.json" "sha1=$(openssl dgst -sha1 -hmac "$secret" <"$HMAC_DIR/ping.json" | awk '{print $NF}')" 401
  hmac_case "correct signature, non-ASCII UTF-8 body" "$HMAC_DIR/utf8.json" "$(hmac_sign "$secret" "$HMAC_DIR/utf8.json")" 200
  hmac_case "correct signature, empty body" "$HMAC_DIR/empty.json" "$(hmac_sign "$secret" "$HMAC_DIR/empty.json")" 200
  hmac_case "correct signature, ~1 MiB body" "$HMAC_DIR/large.json" "$(hmac_sign "$secret" "$HMAC_DIR/large.json")" 200

  rm -rf "$HMAC_DIR"
  secret="" other=""
  tf_destroy "$M5"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Sourced by measure/run.sh. Run: measure/run.sh --only $M5 --resource-group RG --subscription SUB" >&2
  exit 2
fi
