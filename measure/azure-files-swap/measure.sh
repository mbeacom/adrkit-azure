# shellcheck shell=bash
# shellcheck disable=SC2154 # RG, RESULTS_DIR, etc. are set by run.sh
# Measurement 3: the two-move swap on Azure Files (SMB) under concurrent
# reads. Sourced by measure/run.sh; do not execute directly.
#
# Applies the root, starts the reader job and the writer job together, waits
# for both executions, downloads the summaries the jobs wrote to the share,
# asserts on them, and destroys the root.
#
# Assertions (each reader: reader-cross = separate replica and SMB mount,
# reader-same = background reader in the writer's replica):
#   torn == 0                     a load clause 5 would keep was never mixed
#   sidecar_invalid == 0          a sidecar was never read half-written
#   sidecar_missing_in_tree == 0  a visible tree never lacked its sidecar
#   accepted > 0                  the reader really loaded (else inconclusive)
# Writer:
#   swaps_completed == swaps_requested, move1_fail == move2_fail ==
#   restore_fail == 0             both moves work on SMB while reads run
#   rm_old_fail                   recorded (FAIL if > 0: old trees pile up)
# Recorded as INFO: failed_absent / failed_midload (the expected window that
# clause 4 says clause 5 survives), rejected_commit_moved, absence window ms.

M3=azure-files-swap
SWAP_JOB_TIMEOUT=${SWAP_JOB_TIMEOUT:-2400}

swap_exec_status() { # JOB EXECUTION
  azs containerapp job execution show --name "$1" --resource-group "$RG" \
    --job-execution-name "$2" --query properties.status -o tsv 2>/dev/null
}

swap_exec_done() { # JOB EXECUTION
  case "$(swap_exec_status "$1" "$2")" in
  Succeeded | Failed | Stopped | Degraded) return 0 ;;
  *) return 1 ;;
  esac
}

swap_check_zero() { # FILE ROLE KEY
  local v
  v=$(kv "$1" "$3")
  if [ -z "$v" ]; then
    record "$M3" "$2 $3 == 0" ERROR "missing from summary"
  elif [ "$v" = 0 ]; then
    record "$M3" "$2 $3 == 0" PASS "0"
  else
    record "$M3" "$2 $3 == 0" FAIL "$v (see $2.log)"
  fi
}

measure_azure_files_swap() {
  local rc writer reader acct share key ew er s f out v req done_
  log "=== $M3 (ADR-0056 action item 3, clause 4)"
  tf_write_vars "$M3" "$(base_vars)"
  tf_init "$M3"

  rc=0
  tf_apply "$M3" || rc=$?
  if [ "$rc" -ne 0 ]; then
    record "$M3" "apply" ERROR "terraform apply exited $rc; see $M3.terraform.log"
    tf_destroy "$M3"
    return 0
  fi

  writer=$(tf "$M3" output -raw writer_job_name)
  reader=$(tf "$M3" output -raw reader_job_name)
  acct=$(tf "$M3" output -raw storage_account_name)
  share=$(tf "$M3" output -raw share_name)

  # Reader first: it waits for the writer's seed, then the writer waits for it.
  er=$(azs containerapp job start --name "$reader" --resource-group "$RG" --query name -o tsv)
  ew=$(azs containerapp job start --name "$writer" --resource-group "$RG" --query name -o tsv)
  record "$M3" "job executions started" INFO "reader=$er writer=$ew"

  for pair in "$reader:$er" "$writer:$ew"; do
    if wait_until "$SWAP_JOB_TIMEOUT" 20 swap_exec_done "${pair%%:*}" "${pair#*:}"; then
      record "$M3" "execution ${pair#*:}" INFO "$(swap_exec_status "${pair%%:*}" "${pair#*:}") after ${WAIT_ELAPSED}s"
    else
      record "$M3" "execution ${pair#*:}" ERROR "not finished after ${WAIT_ELAPSED}s"
    fi
  done

  out="$RESULTS_DIR/$M3"
  mkdir -p "$out"
  key=$(azs storage account keys list --resource-group "$RG" --account-name "$acct" --query '[0].value' -o tsv)
  for f in writer.summary reader-same.summary reader-cross.summary writer.log reader-same.log reader-cross.log writer.stderr; do
    az storage file download --account-name "$acct" --account-key "$key" --share-name "$share" \
      --path "$RUN_ID/results/$f" --dest "$out/$f" --no-progress >/dev/null 2>&1 || true
  done
  key=""

  s="$out/writer.summary"
  if [ ! -s "$s" ]; then
    record "$M3" "writer summary" ERROR "not downloaded; check the job logs in Log Analytics"
  else
    [ "$(kv "$s" reader_ready)" = 1 ] ||
      record "$M3" "cross-client reader was running" ERROR "writer did not see reader.ready; cross-client result inconclusive"
    req=$(kv "$s" swaps_requested)
    done_=$(kv "$s" swaps_completed)
    if [ -n "$req" ] && [ "$req" = "$done_" ]; then
      record "$M3" "writer swaps completed" PASS "$done_/$req"
    else
      record "$M3" "writer swaps completed" FAIL "${done_:-?}/${req:-?}"
    fi
    for v in move1_fail move2_fail restore_fail write_fail next_cleanup_fail rm_old_fail; do
      swap_check_zero "$s" writer "$v"
    done
    record "$M3" "absence window between the two moves (writer's clock)" INFO \
      "max=$(kv "$s" absence_window_ms_max)ms mean=$(kv "$s" absence_window_ms_mean)ms leftover_old_dirs=$(kv "$s" leftover_old_dirs)"
  fi

  for f in reader-cross reader-same; do
    s="$out/$f.summary"
    if [ ! -s "$s" ]; then
      record "$M3" "$f summary" ERROR "not downloaded"
      continue
    fi
    if [ -n "$(kv "$s" error)" ]; then
      record "$M3" "$f ran" ERROR "$(kv "$s" error)"
      continue
    fi
    swap_check_zero "$s" "$f" torn
    swap_check_zero "$s" "$f" sidecar_invalid
    swap_check_zero "$s" "$f" sidecar_missing_in_tree
    v=$(kv "$s" accepted)
    if [ -n "$v" ] && [ "$v" -gt 0 ]; then
      record "$M3" "$f loads accepted > 0" PASS "$v of $(kv "$s" loads)"
    else
      record "$M3" "$f loads accepted > 0" ERROR "accepted=${v:-?}; the reader did not really load"
    fi
    record "$M3" "$f window and rejections" INFO \
      "failed_absent=$(kv "$s" failed_absent) failed_midload=$(kv "$s" failed_midload) rejected_commit_moved=$(kv "$s" rejected_commit_moved) stopped_by=$(kv "$s" stopped_by)"
  done

  tf_destroy "$M3"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Sourced by measure/run.sh. Run: measure/run.sh --only $M3 --resource-group RG --subscription SUB" >&2
  exit 2
fi
