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

# --- Initialize beads (embedded mode, no server needed) ---
echo "Initializing beads..."
rm -f .beads/metadata.json
bd init --from-jsonl

# --- Install pre-commit hook (beads) ---
git config core.hooksPath scripts/git-hooks

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
claude -p --dangerously-skip-permissions --output-format json --model opus "$(cat <<'PROMPT'
Read SPEC.md to understand the project requirements.
Run `bd list` to check for existing tasks.

If tasks exist: pick one open task, implement it, commit your changes, and close the bead.
If no tasks exist: read SPEC.md carefully, create an epic with child tasks, then start implementing.

Research anything you need. Follow AGENTS.md for the Landing the Plane protocol.
Push all changes before finishing.
PROMPT
)" > /tmp/agent-run.json

echo "Agent run complete."
