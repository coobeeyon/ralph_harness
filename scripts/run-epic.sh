#!/usr/bin/env bash
set -euo pipefail

epic="${1:?Usage: run-epic.sh <epic-id> [timeout-minutes]}"
timeout_mins="${2:-15}"
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
log_file="$log_dir/epic-${epic}-$(date +%Y%m%d-%H%M%S).jsonl"

repo_url="$(git -C "$project_dir" remote get-url origin)"
branch="$(git -C "$project_dir" branch --show-current)"

# Litebrite setup + sync
lb init 2>/dev/null || true
lb setup claude 2>/dev/null || true
lb sync 2>/dev/null || true

# Build the container image (all layers cached unless versions change)
echo "Building runner container..."
docker build -q -t agent-runner \
  --build-arg HOST_UID="$(id -u)" \
  --build-arg HOST_GID="$(id -g)" \
  -f "$runner_dir/Dockerfile" "$project_dir"

container_name="epic-${epic}"

echo "Running epic $epic on branch $branch (${timeout_mins}m timeout per task)..."
echo "Container name: $container_name"
echo "Log file: $log_file"

# Remove stale container with same name if it exists
docker rm "$container_name" 2>/dev/null || true

if [ "$raw" = true ]; then
  docker run --name "$container_name" \
    --env-file "$project_dir/.env" \
    -e ANTHROPIC_API_KEY \
    -e REPO_URL="$repo_url" \
    -e BRANCH="$branch" \
    -v "${SSH_AUTH_SOCK}:/ssh-agent" \
    -e SSH_AUTH_SOCK=/ssh-agent \
    -v "$runner_dir/run-epic.sh:/run-epic.sh:ro" \
    agent-runner /run-epic.sh "$epic" "$timeout_mins" 2>&1 | tee "$log_file"
else
  docker run --name "$container_name" \
    --env-file "$project_dir/.env" \
    -e ANTHROPIC_API_KEY \
    -e REPO_URL="$repo_url" \
    -e BRANCH="$branch" \
    -v "${SSH_AUTH_SOCK}:/ssh-agent" \
    -e SSH_AUTH_SOCK=/ssh-agent \
    -v "$runner_dir/run-epic.sh:/run-epic.sh:ro" \
    agent-runner /run-epic.sh "$epic" "$timeout_mins" 2>&1 | tee "$log_file" | bun run "$script_dir/stream-fmt.ts"
fi

echo ""
echo "Container $container_name finished."
ln -sf "$(basename "$log_file")" "$log_dir/latest.jsonl"

echo "Cleaning up..."
docker rm "$container_name"

# Pull changes and sync litebrite
echo "Fetching results from remote..."
git -C "$project_dir" fetch origin
lb sync 2>/dev/null || true
echo "Done. Log saved: $log_file"
