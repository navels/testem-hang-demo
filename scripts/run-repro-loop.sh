#!/usr/bin/env bash

set -u
set +m
set +b

RUNS=100
SLOW_AFTER_END_MARKER_SECONDS=$((2 * 60))
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_ROOT="$ROOT_DIR/tmp/repro-loop"
RUN_LABEL="$(date '+%Y%m%dT%H%M%S')"
LOG_DIR="$LOG_ROOT/$RUN_LABEL"
SUMMARY_FILE="$LOG_DIR/summary.txt"
END_MARKER='^ok 500 '
REPRO_CMD='npm run repro'
TESTEM_PORT=7357

mkdir -p "$LOG_DIR"

if ! command -v perl >/dev/null 2>&1; then
  echo "perl is required for process-group management" >&2
  exit 1
fi

cleanup_stale_testem_port() {
  local run_dir="$1"
  local port_pids
  local stale_file
  local stale_pid

  port_pids="$(lsof -tiTCP:"$TESTEM_PORT" -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' | xargs)"

  if [ -z "$port_pids" ]; then
    return
  fi

  stale_file="$run_dir/pre-run-stale-port-$TESTEM_PORT.txt"
  {
    date '+timestamp=%Y-%m-%dT%H:%M:%S%z'
    echo "port=$TESTEM_PORT"
    echo "stale_pids=$port_pids"
    echo
    lsof -iTCP:"$TESTEM_PORT" -n -P 2>&1 || true
    echo
    ps -o pid,ppid,pgid,stat,etime,command -p "$(echo "$port_pids" | tr ' ' ',')" 2>&1 || true
  } >"$stale_file"

  echo "Run $run found stale listener on port $TESTEM_PORT: $port_pids; terminating"
  echo "Run $run found stale listener on port $TESTEM_PORT: $port_pids; terminating" >>"$SUMMARY_FILE"

  for stale_pid in $port_pids; do
    kill -TERM "$stale_pid" >/dev/null 2>&1 || true
  done
  sleep 2
  for stale_pid in $port_pids; do
    kill -KILL "$stale_pid" >/dev/null 2>&1 || true
  done
}

echo "Root: $ROOT_DIR"
echo "Runs: $RUNS"
echo "Stop after first run slower than: ${SLOW_AFTER_END_MARKER_SECONDS}s after end marker"
echo "Logs: $LOG_DIR"
echo "Repro command: $REPRO_CMD"
echo

{
  echo "Root: $ROOT_DIR"
  echo "Runs: $RUNS"
  echo "Stop after first run slower than: ${SLOW_AFTER_END_MARKER_SECONDS}s after end marker"
  echo "Logs: $LOG_DIR"
  echo "Repro command: $REPRO_CMD"
  echo
} >"$SUMMARY_FILE"

cd "$ROOT_DIR" || exit 1

success_count=0

for run in $(seq 1 "$RUNS"); do
  run_dir="$LOG_DIR/run-$run"
  log_file="$run_dir/output.log"
  start_time=$(date +%s)

  mkdir -p "$run_dir"
  cleanup_stale_testem_port "$run_dir"

  echo "Run $run/$RUNS started at $(date '+%Y-%m-%dT%H:%M:%S')"
  echo "Run $run/$RUNS started at $(date '+%Y-%m-%dT%H:%M:%S')" >>"$SUMMARY_FILE"

  perl -e 'setpgrp(0, 0); exec @ARGV' \
    /bin/zsh -lc "$REPRO_CMD" >"$log_file" 2>&1 &
  pid=$!

  marker_seen=0
  marker_time=0
  marker_seen_in_final_scan=0
  should_stop_after_run=0

  while kill -0 "$pid" >/dev/null 2>&1; do
    now=$(date +%s)

    if [ "$marker_seen" -eq 0 ] && grep -q "$END_MARKER" "$log_file" 2>/dev/null; then
      marker_seen=1
      marker_time=$now
      echo "Run $run reached end marker at $(date '+%Y-%m-%dT%H:%M:%S')"
      echo "Run $run reached end marker at $(date '+%Y-%m-%dT%H:%M:%S')" >>"$SUMMARY_FILE"
    fi

    sleep 1
  done

  wait "$pid"
  rc=$?
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  if [ "$marker_seen" -eq 0 ] && grep -q "$END_MARKER" "$log_file" 2>/dev/null; then
    marker_seen=1
    marker_seen_in_final_scan=1
  fi

  success_count=$((success_count + 1))
  if [ "$marker_seen" -eq 1 ] && [ "$marker_time" -gt 0 ]; then
    post_marker_elapsed=$((end_time - marker_time))
    echo "Run $run result: COMPLETED (${elapsed}s total, ${post_marker_elapsed}s after end marker) rc=$rc"
    echo "Run $run result: COMPLETED (${elapsed}s total, ${post_marker_elapsed}s after end marker) rc=$rc" >>"$SUMMARY_FILE"

    if [ "$post_marker_elapsed" -gt "$SLOW_AFTER_END_MARKER_SECONDS" ]; then
      should_stop_after_run=1
      echo "Run $run exceeded slow-run threshold (${post_marker_elapsed}s > ${SLOW_AFTER_END_MARKER_SECONDS}s after end marker); stopping loop"
      echo "Run $run exceeded slow-run threshold (${post_marker_elapsed}s > ${SLOW_AFTER_END_MARKER_SECONDS}s after end marker); stopping loop" >>"$SUMMARY_FILE"
    fi
  elif [ "$marker_seen_in_final_scan" -eq 1 ]; then
    echo "Run $run result: COMPLETED (${elapsed}s total, end marker seen in final log scan) rc=$rc"
    echo "Run $run result: COMPLETED (${elapsed}s total, end marker seen in final log scan) rc=$rc" >>"$SUMMARY_FILE"
  else
    echo "Run $run result: COMPLETED (${elapsed}s total, end marker not seen) rc=$rc"
    echo "Run $run result: COMPLETED (${elapsed}s total, end marker not seen) rc=$rc" >>"$SUMMARY_FILE"
  fi

  echo "Log: $log_file"
  echo "Log: $log_file" >>"$SUMMARY_FILE"
  echo
  echo >>"$SUMMARY_FILE"

  if [ "$should_stop_after_run" -eq 1 ]; then
    break
  fi
done

echo "Summary"
echo "Completed: $success_count/$run"
{
  echo "Summary"
  echo "Completed: $success_count/$run"
} >>"$SUMMARY_FILE"
