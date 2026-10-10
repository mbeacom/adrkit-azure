#!/bin/bash
# Runs inside both Container Apps jobs of the azure-files-swap measurement.
# ROLE=writer performs the swaps (and runs a same-client reader in the
# background); ROLE=reader is the cross-client reader. Everything is written
# under $MOUNT/$RUN_ID on the share, and measure.sh downloads the summaries.
#
# Torn means: a load that ADR-0055 clause 5 would have KEPT (sidecar commit
# identical before and after the load) but whose files are not all from that
# commit's generation. That is the failure ADR-0056 clause 4 lists as "a sync
# that a load observes half-written". Everything else is counted and kept.
set -uo pipefail

: "${ROLE:?}" "${RUN_ID:?}" "${MOUNT:?}" "${SWAPS:?}" "${FILES_PER_TREE:?}" "${READER_TIMEOUT_SECONDS:?}"

base="$MOUNT/$RUN_ID"
corpus="$base/corpus"
key="$corpus/demo"
res="$base/results"
mkdir -p "$res" "$corpus"

now_ms() { date +%s%3N; }
log() { printf '%s %s %s\n' "$(now_ms)" "$1" "$2" >>"$res/$1.log"; }
commit_for() { printf '%040x' "$1"; }

# Parse a sidecar line into SC_COMMIT / SC_GEN; return 1 if it is not valid
# under ADR-0055 clause 4 (commit ^[0-9a-f]{40}$) or not this harness's shape.
parse_sidecar() {
  SC_COMMIT="" SC_GEN=""
  [[ $1 =~ \"commit\":\"([0-9a-f]{40})\",\"gen\":([0-9]+) ]] || return 1
  SC_COMMIT=${BASH_REMATCH[1]}
  SC_GEN=${BASH_REMATCH[2]}
  [ "$SC_COMMIT" = "$(commit_for "$SC_GEN")" ]
}

# write_tree DIR GEN: files first, sidecar LAST (ADR-0055 clause 4).
write_tree() {
  local d=$1 g=$2 i
  mkdir "$d" || return 1
  for ((i = 1; i <= FILES_PER_TREE; i++)); do
    printf 'gen=%d file=%d\n' "$g" "$i" >"$d/f$i.txt" || return 1
  done
  printf '{"commit":"%s","gen":%d}\n' "$(commit_for "$g")" "$g" >"$d/.adrkit-corpus.json" || return 1
}

# read_loop NAME STOPFILE: one load per iteration, modelled on ADR-0055
# clause 5. Uses bash builtins only (no fork per file) so loads are fast
# enough to land inside the swap window.
read_loop() {
  local name=$1 stop=$2
  local deadline=$(($(date +%s) + READER_TIMEOUT_SECONDS))
  local loads=0 accepted=0 rejected_moved=0 failed_absent=0 failed_midload=0
  local sidecar_invalid=0 sidecar_missing_in_tree=0 torn=0
  local s1 s2 g1 g2 line i ok bad
  while [ ! -e "$stop" ] && [ "$(date +%s)" -lt "$deadline" ]; do
    loads=$((loads + 1))
    if ! IFS= read -r s1 2>/dev/null <"$key/.adrkit-corpus.json"; then
      # Absent directory is the expected window between the two moves.
      # A present tree with files but no sidecar would break "sidecar last".
      if [ -e "$key/f1.txt" ] && [ ! -e "$key/.adrkit-corpus.json" ]; then
        sidecar_missing_in_tree=$((sidecar_missing_in_tree + 1))
        log "$name" "SIDECAR_MISSING_IN_TREE load=$loads"
      else
        failed_absent=$((failed_absent + 1))
      fi
      continue
    fi
    if ! parse_sidecar "$s1"; then
      sidecar_invalid=$((sidecar_invalid + 1))
      log "$name" "SIDECAR_INVALID load=$loads content=$s1"
      continue
    fi
    g1=$SC_GEN
    ok=1 bad=""
    for ((i = 1; i <= FILES_PER_TREE; i++)); do
      if ! IFS= read -r line 2>/dev/null <"$key/f$i.txt"; then
        ok=0
        break
      fi
      line=${line#gen=}
      line=${line%% *}
      if [ "$line" != "$g1" ]; then
        bad="$bad f$i=$line"
      fi
    done
    if [ "$ok" -eq 0 ]; then
      # A read failed mid-load: the server keeps its old handle (clause 5).
      failed_midload=$((failed_midload + 1))
      continue
    fi
    if ! IFS= read -r s2 2>/dev/null <"$key/.adrkit-corpus.json" || ! parse_sidecar "$s2"; then
      failed_midload=$((failed_midload + 1))
      continue
    fi
    g2=$SC_GEN
    if [ "$g1" != "$g2" ]; then
      rejected_moved=$((rejected_moved + 1))
    elif [ -n "$bad" ]; then
      torn=$((torn + 1))
      log "$name" "TORN load=$loads sidecar_gen=$g1 mismatched:$bad"
    else
      accepted=$((accepted + 1))
    fi
  done
  {
    echo "role=$name"
    echo "host=${HOSTNAME:-unknown}"
    echo "loads=$loads"
    echo "accepted=$accepted"
    echo "rejected_commit_moved=$rejected_moved"
    echo "failed_absent=$failed_absent"
    echo "failed_midload=$failed_midload"
    echo "sidecar_invalid=$sidecar_invalid"
    echo "sidecar_missing_in_tree=$sidecar_missing_in_tree"
    echo "torn=$torn"
    if [ -e "$stop" ]; then echo "stopped_by=writer_done"; else echo "stopped_by=timeout"; fi
  } >"$res/$name.summary"
}

wait_for() { # FILE SECONDS
  local f=$1 until=$(($(date +%s) + $2))
  while [ ! -e "$f" ]; do
    [ "$(date +%s)" -ge "$until" ] && return 1
    sleep 1
  done
}

case "$ROLE" in
reader)
  if ! wait_for "$base/seeded" 900; then
    echo "role=reader-cross" >"$res/reader-cross.summary"
    echo "error=writer_never_seeded" >>"$res/reader-cross.summary"
    exit 0
  fi
  touch "$base/reader.ready"
  read_loop reader-cross "$base/writer.done"
  ;;

writer)
  rm -rf "$corpus/demo" "$corpus"/demo.* 2>/dev/null
  write_tree "$key" 0 || {
    echo "error=seed_failed" >"$res/writer.summary"
    exit 1
  }
  touch "$base/seeded"
  reader_ready=1
  wait_for "$base/reader.ready" 900 || reader_ready=0

  read_loop reader-same "$base/writer.done" &
  same_pid=$!

  write_fail=0 next_cleanup_fail=0 move1_fail=0 move2_fail=0 restore_fail=0 rm_old_fail=0 completed=0
  window_max=0 window_total=0
  err="$res/writer.stderr"
  for ((g = 1; g <= SWAPS; g++)); do
    next="$key.next"
    old="$key.old.$g"
    if [ -e "$next" ] && ! rm -rf "$next" 2>>"$err"; then
      next_cleanup_fail=$((next_cleanup_fail + 1))
      log writer "NEXT_CLEANUP_FAIL gen=$g"
      continue
    fi
    if ! write_tree "$next" "$g" 2>>"$err"; then
      write_fail=$((write_fail + 1))
      log writer "WRITE_FAIL gen=$g"
      continue
    fi
    if ! mv "$key" "$old" 2>>"$err"; then
      move1_fail=$((move1_fail + 1))
      log writer "MOVE1_FAIL gen=$g (mv $key -> $old)"
      continue
    fi
    t1=$(now_ms)
    if ! mv "$next" "$key" 2>>"$err"; then
      move2_fail=$((move2_fail + 1))
      log writer "MOVE2_FAIL gen=$g (mv $next -> $key); restoring"
      mv "$old" "$key" 2>>"$err" || {
        restore_fail=$((restore_fail + 1))
        log writer "RESTORE_FAIL gen=$g"
      }
      continue
    fi
    t2=$(now_ms)
    w=$((t2 - t1))
    window_total=$((window_total + w))
    [ "$w" -gt "$window_max" ] && window_max=$w
    if ! rm -rf "$old" 2>>"$err"; then
      rm_old_fail=$((rm_old_fail + 1))
      log writer "RM_OLD_FAIL gen=$g"
    fi
    completed=$((completed + 1))
  done
  touch "$base/writer.done"
  wait "$same_pid"
  {
    echo "role=writer"
    echo "host=${HOSTNAME:-unknown}"
    echo "reader_ready=$reader_ready"
    echo "swaps_requested=$SWAPS"
    echo "swaps_completed=$completed"
    echo "write_fail=$write_fail"
    echo "next_cleanup_fail=$next_cleanup_fail"
    echo "move1_fail=$move1_fail"
    echo "move2_fail=$move2_fail"
    echo "restore_fail=$restore_fail"
    echo "rm_old_fail=$rm_old_fail"
    echo "absence_window_ms_max=$window_max"
    if [ "$completed" -gt 0 ]; then
      echo "absence_window_ms_mean=$((window_total / completed))"
    else
      echo "absence_window_ms_mean=n/a"
    fi
    echo "leftover_old_dirs=$(find "$corpus" -maxdepth 1 -name 'demo.old.*' | wc -l)"
  } >"$res/writer.summary"
  ;;

*)
  echo "unknown ROLE=$ROLE" >&2
  exit 2
  ;;
esac
