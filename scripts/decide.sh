#!/usr/bin/env bash
# Decide whether the agent loop should continue.
# Reads SPEC.md, beads state, and recent summaries.
#
# Exit code 0 = continue, 1 = done
set -euo pipefail
unset CLAUDECODE

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

schema='{"type":"object","properties":{"continue":{"type":"boolean","description":"true if more work remains, false if spec is fully implemented"},"reason":{"type":"string","description":"Brief explanation of the decision"}},"required":["continue","reason"]}'

output=$(claude -p \
  --model sonnet \
  --allowedTools 'Read' 'Bash(bd list*)' 'Bash(bd show*)' \
  --output-format json --json-schema "$schema" \
  "You are deciding whether an AI agent loop should continue or stop.

Read these inputs:
1. $project_dir/SPEC.md — the project specification
2. Run 'bd list --pretty' to see current task state
3. Read the latest summary from $project_dir/logs/summaries/ (if any exist)

Decide:
- continue=true if there are open tasks, unfinished spec requirements, or the agent appears stuck and should retry
- continue=false if the spec is fully implemented and all tasks are closed")

structured=$(echo "$output" | jq '.structured_output')
reason=$(echo "$structured" | jq -r '.reason')
should_continue=$(echo "$structured" | jq -r '.continue')

echo "Decider: $reason"

if [ "$should_continue" = "false" ]; then
  exit 1
fi
