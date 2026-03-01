#!/usr/bin/env bash
set -euo pipefail

repo_url="${REPO_URL:?REPO_URL required}"
branch="${BRANCH:?BRANCH required}"
work_dir="$HOME/workspace"

# --- Clone repo ---
echo "Cloning $repo_url (branch: $branch)..."
git clone --branch "$branch" "$repo_url" "$work_dir"
cd "$work_dir"
git config --global --add safe.directory "$work_dir"

# --- Initialize litebrite ---
echo "Initializing litebrite..."
lb init
lb setup claude 2>/dev/null || true

# --- Restore .claude.json from persisted backup if missing ---
claude_config="$HOME/.claude.json"
if [ ! -f "$claude_config" ] && [ -d "$HOME/.claude/backups" ]; then
  latest_backup=$(ls -t "$HOME/.claude/backups/.claude.json.backup."* 2>/dev/null | head -1)
  if [ -n "$latest_backup" ]; then
    cp "$latest_backup" "$claude_config"
    echo "Restored .claude.json from backup: $(basename "$latest_backup")"
  fi
fi

# --- Run agent ---
echo "Starting agent run..."
claude -p --dangerously-skip-permissions --verbose --output-format stream-json --model opus "$(cat <<'PROMPT'
You are ONE agent in a relay. Do ONE task, then stop.

## Steps

1. Run `lb list` to see what exists. Read SPEC.md to understand the project.
2. Assess the current state: What tasks exist? What code is already written? What does the project need right now — research, planning, or implementation?
3. If the project needs work that isn't captured in tasks yet, create tasks for it. Use epics to group related work. You can create research tasks, implementation tasks, or whatever fits. You don't need to plan everything upfront — future agents will add more tasks as the project evolves.
4. Pick ONE open task. Claim it: `lb claim <id>`
5. Read existing code before changing it. Do the task.
6. If you discover follow-up work, create tasks for it. If a plan turns out wrong, close or restructure tasks as needed.
7. Commit your code frequently with clear messages.
8. When done, run these commands IN ORDER:
   ```
   lb close <id>
   lb sync
   git push
   ```
9. STOP. Do NOT start another task. Exit immediately.

## Rules
- ONE task per session. Not two. Not "just one more." ONE.
- Every session ends with: lb close, lb sync, git push — in that order.
- The next agent will continue where you left off.
- The task graph is a living document. Create, restructure, and close tasks as understanding grows.
PROMPT
)"

echo "Agent run complete."

# --- Belt-and-suspenders: force sync/push even if agent forgot ---
echo "Post-agent cleanup: forcing lb sync and git push..."
lb sync 2>/dev/null || true
git push 2>/dev/null || true
