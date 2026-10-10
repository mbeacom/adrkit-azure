# shellcheck shell=bash
# Shared helpers for measure/run.sh. Sourced, never executed.
#
# Globals set by run.sh before anything here runs:
#   MEASURE_DIR RESULTS_DIR SUMMARY RG SUB LOCATION PUBLISHER_EMAIL
#   RUN_ID NAME_PREFIX
# Globals owned here:
#   ACTIVE_ROOTS  roots that may hold resources (destroyed by cleanup)
#   FAILS ERRORS  counts of FAIL and ERROR records

ACTIVE_ROOTS=()
FAILS=0
ERRORS=0

export TF_IN_AUTOMATION=1
export TF_INPUT=0

# azs ARGS...: az pinned to the measured subscription, so the operator's
# Azure CLI default is never changed or relied on. (az rest needs no flag: its
# URLs carry the subscription ID. Data-plane calls with an account key need
# none either.)
azs() { az "$@" --subscription "$SUB_ID"; }

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
  exit 1
}

# record MEASUREMENT CHECK STATUS DETAIL
#   PASS  the observation matches what ADR-0056 assumes
#   FAIL  the observation contradicts it (a measurement result, not a bug)
#   ERROR the harness could not observe (inconclusive; rerun or investigate)
#   INFO  recorded for the maintainer, no expectation attached
record() {
  local m=$1 c=$2 s=$3 d=${4:-}
  case "$s" in
  FAIL) FAILS=$((FAILS + 1)) ;;
  ERROR) ERRORS=$((ERRORS + 1)) ;;
  PASS | INFO) ;;
  *) die "record: unknown status $s" ;;
  esac
  printf '%s | %s | %s | %s\n' "$m" "$c" "$s" "$d" >>"$SUMMARY"
  log "$s  $m: $c${d:+ ($d)}"
}

# Run a command with a wall-clock limit (macOS has no coreutils timeout).
with_timeout() {
  local secs=$1
  shift
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"
}

# shellcheck disable=SC2034 # WAIT_ELAPSED is read by the measure scripts
# wait_until TIMEOUT_SECONDS INTERVAL_SECONDS COMMAND...
# Polls COMMAND until it succeeds. Sets WAIT_ELAPSED (seconds). Returns 1 on
# timeout. COMMAND runs in a conditional context, so set -e does not apply
# inside it.
wait_until() {
  local timeout=$1 interval=$2 start now
  shift 2
  start=$(date +%s)
  while true; do
    if "$@"; then
      WAIT_ELAPSED=$(($(date +%s) - start))
      return 0
    fi
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      WAIT_ELAPSED=$((now - start))
      return 1
    fi
    sleep "$interval"
  done
}

root_dir() { printf '%s/%s' "$MEASURE_DIR" "$1"; }

tf() {
  local root=$1
  shift
  terraform -chdir="$(root_dir "$root")" "$@"
}

# tf_write_vars ROOT JSON: the root's inputs, so a later destroy (including
# the one in the EXIT trap) needs no arguments. Gitignored (*.tfvars.json).
# Marks the root active, so the file (which may hold a secret) is removed by
# the trap even if the run dies before anything is applied.
tf_write_vars() {
  local root=$1 json=$2
  mark_active "$root"
  (
    umask 077
    printf '%s\n' "$json" | jq . >"$(root_dir "$root")/terraform.tfvars.json"
  )
}

tf_init() {
  local root=$1
  tf "$root" init -input=false -no-color -lockfile=readonly >>"$RESULTS_DIR/$root.terraform.log" 2>&1 ||
    die "terraform init failed in $root; see $RESULTS_DIR/$root.terraform.log"
}

mark_active() {
  local root=$1 r
  for r in "${ACTIVE_ROOTS[@]+"${ACTIVE_ROOTS[@]}"}"; do
    [ "$r" = "$root" ] && return 0
  done
  ACTIVE_ROOTS+=("$root")
}

unmark_active() {
  local root=$1 r keep=()
  for r in "${ACTIVE_ROOTS[@]+"${ACTIVE_ROOTS[@]}"}"; do
    [ "$r" = "$root" ] || keep+=("$r")
  done
  ACTIVE_ROOTS=("${keep[@]+"${keep[@]}"}")
}

# tf_apply ROOT [ARGS...]: returns terraform's exit code; never exits. The
# root is marked active BEFORE the apply, so a partial apply is torn down.
tf_apply() {
  local root=$1 rc=0
  shift
  mark_active "$root"
  log "terraform apply in $root $*"
  tf "$root" apply -auto-approve -input=false -no-color "$@" \
    >>"$RESULTS_DIR/$root.terraform.log" 2>&1 || rc=$?
  return "$rc"
}

# tf_destroy ROOT: the explicit teardown step of every measurement, and what
# the EXIT trap calls for anything still active. On success the root's
# tfvars (which may hold a secret) and local state are deleted.
tf_destroy() {
  local root=$1 dir rc=0 attempt
  dir=$(root_dir "$root")
  if [ -s "$dir/terraform.tfstate" ] && [ -n "$(tf "$root" state list 2>/dev/null)" ]; then
    for attempt in 1 2; do
      rc=0
      log "terraform destroy in $root (attempt $attempt)"
      tf "$root" destroy -auto-approve -input=false -no-color \
        >>"$RESULTS_DIR/$root.terraform.log" 2>&1 || rc=$?
      [ "$rc" -eq 0 ] && break
    done
    if [ "$rc" -ne 0 ]; then
      warn "destroy FAILED in $root. State kept at $dir/terraform.tfstate."
      warn "Retry: terraform -chdir=$dir destroy   (tfvars kept beside it)"
      warn "Then check for a soft-deleted APIM: az apim deletedservice list -o table"
      ERRORS=$((ERRORS + 1))
      printf '%s | %s | %s | %s\n' "$root" "destroy" "ERROR" "destroy failed; state kept" >>"$SUMMARY"
      return 0
    fi
  fi
  rm -f "$dir/terraform.tfvars.json" "$dir/terraform.tfstate" "$dir/terraform.tfstate.backup" "$dir/plan.bin"
  unmark_active "$root"
  return 0
}

# EXIT trap: destroy every root that may still hold resources, newest first.
# Must never abort part-way, so errexit is off inside it.
cleanup() {
  local rc=$? i
  set +e
  trap - EXIT INT TERM
  if [ "${#ACTIVE_ROOTS[@]}" -gt 0 ]; then
    warn "Tearing down: ${ACTIVE_ROOTS[*]}"
    for ((i = ${#ACTIVE_ROOTS[@]} - 1; i >= 0; i--)); do
      tf_destroy "${ACTIVE_ROOTS[$i]}"
    done
  fi
  if [ -n "${RG:-}" ] && [ -n "${RUN_ID:-}" ] && [ "${CONFIRMED:-0}" = 1 ]; then
    report_leftovers
  fi
  restore_default_subscription
  if [ -n "${SUMMARY:-}" ] && [ -f "$SUMMARY" ]; then
    log "Summary ($SUMMARY):"
    cat "$SUMMARY"
    log "FAIL=$FAILS ERROR=$ERRORS. Transcribe into measure/RESULTS.md."
  fi
  if [ "$rc" -eq 0 ] && [ $((FAILS + ERRORS)) -gt 0 ]; then rc=3; fi
  exit "$rc"
}

# The harness never runs az account set, but verify the operator's default
# subscription is what it was at start, and put it back if anything moved it.
restore_default_subscription() {
  local now
  [ -n "${ORIG_DEFAULT_SUB:-}" ] || return 0
  now=$(az account show --query id -o tsv 2>/dev/null)
  if [ "$now" != "$ORIG_DEFAULT_SUB" ]; then
    warn "Azure CLI default subscription changed during the run ($now); restoring $ORIG_DEFAULT_SUB"
    az account set --subscription "$ORIG_DEFAULT_SUB" ||
      warn "could not restore it: az account set --subscription $ORIG_DEFAULT_SUB"
  fi
}

report_leftovers() {
  local left deleted
  left=$(azs resource list --resource-group "$RG" --tag "adrkit-measure=$RUN_ID" \
    --query "[].[type, name]" -o tsv 2>/dev/null)
  if [ -n "$left" ]; then
    warn "Resources tagged adrkit-measure=$RUN_ID remain in $RG:"
    printf '%s\n' "$left" >&2
    printf '%s | %s | %s | %s\n' "teardown" "leftovers" "ERROR" "tagged resources remain in $RG" >>"$SUMMARY"
    ERRORS=$((ERRORS + 1))
  else
    log "No resources tagged adrkit-measure=$RUN_ID remain in $RG."
  fi
  deleted=$(azs apim deletedservice list --query "[?starts_with(name, '$NAME_PREFIX-')].name" -o tsv 2>/dev/null)
  if [ -n "$deleted" ]; then
    warn "Soft-deleted APIM instances from this run (purge them):"
    printf '%s\n' "$deleted" | while read -r name; do
      printf '  az apim deletedservice purge --service-name %s --location <region>\n' "$name" >&2
    done
  fi
}

# kv FILE KEY: value of KEY=value from a summary file, or empty.
kv() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

# lower STRING (bash 3.2 has no ${x,,}).
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
