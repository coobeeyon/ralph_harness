#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
runner_dir="$script_dir/runner"

# --- Parse flags ---
raw=false
for arg in "$@"; do
  case "$arg" in
    --raw) raw=true ;;
  esac
done

# --- Set up logging ---
log_dir="$project_dir/logs"
mkdir -p "$log_dir"
log_file="$log_dir/run-$(date +%Y%m%d-%H%M%S).jsonl"

echo "Log file: $log_file"

# --- Preflight: clean working tree ---
if ! git -C "$project_dir" diff --quiet || ! git -C "$project_dir" diff --cached --quiet; then
  echo "ERROR: Working tree has uncommitted changes. Commit or stash first."
  exit 1
fi

repo_url="$(git -C "$project_dir" remote get-url origin)"
branch="$(git -C "$project_dir" branch --show-current)"

# --- Litebrite setup + sync ---
if command -v lb >/dev/null 2>&1; then
  lb init 2>/dev/null || true
  lb setup claude 2>/dev/null || true
  lb sync 2>/dev/null || true
fi

# --- Build container image ---
echo "Building runner container..."
docker build -q -t agent-runner \
  --build-arg HOST_UID="$(id -u)" \
  --build-arg HOST_GID="$(id -g)" \
  -f "$runner_dir/Dockerfile" "$project_dir"

container_name="run-$(date +%Y%m%d-%H%M%S)"

echo "Running agent on branch $branch..."
echo "Container name: $container_name"

# Remove stale container with same name if it exists
docker rm "$container_name" 2>/dev/null || true

# Persistent volume for Claude Code memory across runs
docker volume create agent-claude-home 2>/dev/null || true
docker run --rm -v agent-claude-home:/data alpine chown "$(id -u):$(id -g)" /data

if [ "$raw" = true ]; then
  docker run --name "$container_name" \
    --env-file "$project_dir/.env" \
    -e REPO_URL="$repo_url" \
    -e BRANCH="$branch" \
    -v "${SSH_AUTH_SOCK}:/ssh-agent" \
    -e SSH_AUTH_SOCK=/ssh-agent \
    -v "$runner_dir/run.sh:/run.sh:ro" \
    -v "agent-claude-home:/home/runner/.claude" \
    agent-runner /run.sh 2>&1 | tee "$log_file"
else
  docker run --name "$container_name" \
    --env-file "$project_dir/.env" \
    -e REPO_URL="$repo_url" \
    -e BRANCH="$branch" \
    -v "${SSH_AUTH_SOCK}:/ssh-agent" \
    -e SSH_AUTH_SOCK=/ssh-agent \
    -v "$runner_dir/run.sh:/run.sh:ro" \
    -v "agent-claude-home:/home/runner/.claude" \
    agent-runner /run.sh 2>&1 | tee "$log_file" | bun run "$script_dir/stream-fmt.ts"
fi

echo ""
echo "Container $container_name finished."
ln -sf "$(basename "$log_file")" "$log_dir/latest.jsonl"

echo "Cleaning up..."
docker rm "$container_name"

# --- Pull any code changes the agent pushed ---
echo "Pulling code changes from remote..."
git -C "$project_dir" pull --ff-only || echo "No new commits to pull."

echo "Done. Log saved: $log_file"
