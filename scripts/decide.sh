#!/usr/bin/env bash
# Decide whether the agent loop should continue.
# Focuses on task closure: open tasks remain → continue, all closed → stop.
#
# Exit code 0 = continue, 1 = done
set -euo pipefail
unset CLAUDECODE

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

# Gather state upfront so the decider doesn't need tool access
task_state=$(cd "$project_dir" && lb list --all 2>/dev/null || echo "NO TASKS FOUND")
spec_contents=$(cat "$project_dir/SPEC.md" 2>/dev/null || echo "NO SPEC FOUND")

schema='{"type":"object","properties":{"continue":{"type":"boolean","description":"true if open tasks remain, false if all tasks are closed"},"reason":{"type":"string","description":"Brief explanation of the decision"}},"required":["continue","reason"]}'

output=$(cat <<EOF | claude -p \
  --model sonnet \
  --output-format json --json-schema "$schema"
You are deciding whether an AI agent loop should continue or stop.

## Current task state (from lb list --all):
$task_state

## Project spec (SPEC.md):
$spec_contents

## Decision rules:
- If there are NO tasks at all yet, continue=true (the first agent needs to create them).
- If ANY tasks have status other than "closed", continue=true.
- If ALL tasks are closed BUT the spec contains requirements not covered by any task, continue=true (the spec may have been updated after the initial tasks were created).
- If ALL tasks are closed AND the spec is fully covered, continue=false.
EOF
)

structured=$(echo "$output" | jq '.structured_output')
reason=$(echo "$structured" | jq -r '.reason')
should_continue=$(echo "$structured" | jq -r '.continue')

echo "Decider: $reason"

if [ "$should_continue" = "false" ]; then
  exit 1
fi
