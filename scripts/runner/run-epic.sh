#!/usr/bin/env bash
set -euo pipefail

epic="${1:?Usage: run-epic.sh <epic-id> [timeout-minutes]}"
timeout_mins="${2:-15}"
repo_url="${REPO_URL:?REPO_URL required}"
branch="${BRANCH:?BRANCH required}"

# --- Clone and set up ---
echo "Cloning $repo_url (branch: $branch)..."
git clone --branch "$branch" "$repo_url" /workspace
cd /workspace
git config --global --add safe.directory /workspace

logdir="/workspace/logs/epic-runs"
mkdir -p "$logdir"

# --- Initialize beads (JSONL-only, no Dolt server needed in container) ---
echo "Initializing beads..."
bd init --no-db --from-jsonl

# Verify the epic exists before starting
if ! bd show "$epic" > /dev/null 2>&1; then
  echo "ERROR: Epic $epic not found in beads database"
  echo "Available issues:"
  bd list --pretty
  exit 1
fi

# --- Create feature branch from bead title ---
bead_id="$(bd show "$epic" --json 2>/dev/null | grep '"id"' | head -1 | sed 's/.*"id": *"//; s/".*//')"
bead_title="$(bd show "$epic" --json 2>/dev/null | grep '"title"' | head -1 | sed 's/.*"title": *"//; s/".*//')"
slug="$(echo "$bead_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-50)"
feature_branch="${bead_id}-${slug}"

echo "Creating feature branch: $feature_branch"
git checkout -b "$feature_branch"

# --- Task loop ---
remaining() {
  bd show --children "$epic" | grep -c '○' || true
}

sync_and_push() {
  bd export
  git add .beads/issues.jsonl 2>/dev/null || true
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "bd sync: $epic task $task_num"
  fi
  git push -u origin "$feature_branch"
}

task_num=0
failures=0
max_failures=3
while [ "$(remaining)" -gt 0 ]; do
  task_num=$((task_num + 1))
  logfile="$logdir/${epic}-task-${task_num}-$(date +%H%M%S).log"

  echo "=== Task $task_num | $(remaining) remaining | log: $logfile ==="

  set +e
  timeout "${timeout_mins}m" claude \
    "Run 'bd show --children $epic' to see tasks. Pick ONE open child task (marked ○) and complete it. Do NOT work on tasks outside this epic. Commit your changes and close the bead when done. Do NOT push — the runner handles pushing." \
    --dangerously-skip-permissions \
    -p --verbose 2>&1 | tee "$logfile"
  exit_code=${PIPESTATUS[0]}
  set -e

  if [ "$exit_code" -eq 124 ]; then
    echo "--- Task $task_num timed out after ${timeout_mins}m — skipping"
    failures=$((failures + 1))
  elif [ "$exit_code" -ne 0 ]; then
    echo "--- Task $task_num exited with code $exit_code"
    failures=$((failures + 1))
  else
    failures=0
    echo "--- Task $task_num succeeded, pushing to remote..."
    sync_and_push
  fi

  if [ "$failures" -ge "$max_failures" ]; then
    echo "ERROR: $max_failures consecutive failures — aborting"
    break
  fi

  echo ""
  bd list --pretty
  echo ""
done

echo ""
echo "All tasks in $epic complete."
echo "Final push to remote..."
sync_and_push
echo "Done. Merge branch '$feature_branch' into '$branch' when ready."
