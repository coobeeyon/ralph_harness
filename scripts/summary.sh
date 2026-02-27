#!/usr/bin/env bash
# Print a summary of a run from its JSONL log file.
# Usage: summary.sh <log-file>
set -euo pipefail

log_file="${1:?Usage: summary.sh <log-file>}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Done. Log saved: $log_file"
  exit 0
fi

echo "=== Run Summary ==="
echo "Log: $log_file"

# Extract the final result message (last assistant text)
result=$(grep '"result"' "$log_file" 2>/dev/null | tail -1 | jq -r '.result // empty' 2>/dev/null || true)
if [ -n "$result" ]; then
  echo ""
  echo "$result"
fi

# Token usage from the last stats line
stats=$(grep '"usage"' "$log_file" 2>/dev/null | tail -1 || true)
if [ -n "$stats" ]; then
  input=$(echo "$stats" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo 0)
  output=$(echo "$stats" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo 0)
  echo ""
  echo "Tokens: ${input} in / ${output} out"
fi

echo "=================="
