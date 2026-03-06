#!/usr/bin/env bash
set -euo pipefail
unset CLAUDECODE

script_dir="$(cd "$(dirname "$0")" && pwd)"

# --- Parse args ---
delay=0
project_name=""
for arg in "$@"; do
  case "$arg" in
    --delay) shift; delay="${1:-0}" ;;
    --delay=*) delay="${arg#*--delay=}" ;;
    *) [ -z "$project_name" ] && project_name="$arg" ;;
  esac
done

# Build args to pass through
run_args=()
decide_args=()
if [ -n "$project_name" ]; then
  run_args+=("$project_name")
  decide_args+=("$project_name")
fi

echo "=== Agent loop (${delay}s between runs, Ctrl-C to stop) ==="
if [ -n "$project_name" ]; then
  echo "Project: $project_name"
fi

run=0
while true; do
  run=$((run + 1))
  echo ""
  echo "--- Run $run starting at $(date) ---"
  "$script_dir/run.sh" "${run_args[@]}" || echo "Run $run exited with status $?"

  # Sync litebrite so decider sees fresh task state
  if command -v lb >/dev/null 2>&1; then
    lb sync 2>/dev/null || true
  fi

  # Summarize and decide in parallel
  "$script_dir/summary.sh" &
  summary_pid=$!

  if ! "$script_dir/decide.sh" "${decide_args[@]}"; then
    wait "$summary_pid" 2>/dev/null || true
    echo ""
    echo "=== Loop complete after $run runs ==="
    break
  fi

  wait "$summary_pid" 2>/dev/null || true

  if [ "$delay" -gt 0 ]; then
    echo ""
    echo "--- Waiting ${delay}s until next run ---"
    sleep "$delay"
  fi
done
