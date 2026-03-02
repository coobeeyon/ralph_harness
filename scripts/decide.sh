#!/usr/bin/env bash
# Decide whether the agent loop should continue.
# Focuses on task closure: open tasks remain → continue, all closed → stop.
#
# Exit code 0 = continue, 1 = done
set -euo pipefail
unset CLAUDECODE

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/lib.sh"

# Accept optional project name
resolve_project "${1:-}"

# cd to the appropriate directory so lb and SPEC.md access work
if [ "$RALPH_MODE" = "external" ] && [ -n "$RALPH_LOCAL_PATH" ]; then
  cd "$RALPH_LOCAL_PATH"
else
  cd "$RALPH_HARNESS_DIR"
fi

# Ensure lb hooks are installed so claude gets task context automatically
lb setup claude 2>/dev/null || true

schema='{"type":"object","properties":{"continue":{"type":"boolean","description":"true if the loop should continue, false if done"},"reason":{"type":"string","description":"Brief explanation of the decision"}},"required":["continue","reason"]}'

output=$(cat <<EOF | claude -p \
  --model sonnet \
  --allowedTools 'Read, Bash(git *)' \
  --output-format json --json-schema "$schema"
You are deciding whether an AI agent loop should continue or stop. The project is specified in SPEC.md. You can see in the lites what has been done and what remains to do, and you can compare this to the SPEC.md (which may have changed) in order to make your decision. Use the return field "continue" to communicate your decision

EOF
)

structured=$(echo "$output" | jq '.structured_output')
reason=$(echo "$structured" | jq -r '.reason')
should_continue=$(echo "$structured" | jq -r '.continue')

echo "Decider: $reason"

if [ "$should_continue" = "false" ]; then
  exit 1
fi
