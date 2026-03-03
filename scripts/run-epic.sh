#!/usr/bin/env bash
set -euo pipefail

epic="${1:?Usage: run-epic.sh <epic-id> [timeout-minutes] [project-name] [--raw]}"
timeout_mins="${2:-15}"
project_name="${3:-}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/lib.sh"
runner_dir="$script_dir/runner"

# --- Parse flags ---
raw=false
for arg in "$@"; do
  case "$arg" in
    --raw) raw=true ;;
  esac
done

# --- Resolve project ---
resolve_project "$project_name"

# --- Set up logging ---
log_file="$RALPH_LOG_DIR/epic-${epic}-$(date +%Y%m%d-%H%M%S).jsonl"

# Litebrite setup + sync
lb init 2>/dev/null || true
lb setup claude 2>/dev/null || true
lb sync 2>/dev/null || true

# --- Build overlay (external mode) ---
overlay_dir=""
if [ "$RALPH_MODE" = "external" ]; then
  overlay_dir="$(build_overlay_dir)"
fi

# Build the container image
echo "Building runner container..."
docker build -q -t agent-runner \
  --build-arg HOST_UID="$(id -u)" \
  --build-arg HOST_GID="$(id -g)" \
  -f "$runner_dir/Dockerfile" "$RALPH_HARNESS_DIR"

container_name="epic-${epic}"

echo "Running epic $epic on branch $RALPH_BRANCH (${timeout_mins}m timeout per task)..."
echo "Container name: $container_name"
echo "Log file: $log_file"
echo "Mode: $RALPH_MODE"

# Remove stale container with same name
docker rm "$container_name" 2>/dev/null || true

# Build docker run args
docker_args=()
docker_args+=(--name "$container_name")
docker_args+=(--env-file "$RALPH_ENV_FILE")
docker_args+=(-e ANTHROPIC_API_KEY)
docker_args+=(-e REPO_URL="$RALPH_REPO_URL")
docker_args+=(-e BRANCH="$RALPH_BRANCH")
docker_args+=(-v "${SSH_AUTH_SOCK}:/ssh-agent")
docker_args+=(-e SSH_AUTH_SOCK=/ssh-agent)
docker_args+=(-v "$runner_dir/run-epic.sh:/run-epic.sh:ro")

if [ -n "$overlay_dir" ]; then
  docker_args+=(-v "$overlay_dir:/overlay:ro")
fi

if [ "$RALPH_MODE" = "external" ] && [ -n "$RALPH_LOCAL_PATH" ]; then
  docker_args+=(-v "$RALPH_LOCAL_PATH:/home/runner/workspace")
fi

if [ "$raw" = true ]; then
  docker run "${docker_args[@]}" agent-runner /run-epic.sh "$epic" "$timeout_mins" 2>&1 | tee "$log_file"
else
  docker run "${docker_args[@]}" agent-runner /run-epic.sh "$epic" "$timeout_mins" 2>&1 | tee "$log_file" | bun run "$script_dir/stream-fmt.ts"
fi

echo ""
echo "Container $container_name finished."
ln -sf "$(basename "$log_file")" "$RALPH_LOG_DIR/latest.jsonl"

# --- Extract updated Dockerfile from container (external mode) ---
if [ "$RALPH_MODE" = "external" ]; then
  echo "Checking for updated Dockerfile..."
  docker cp "$container_name:/home/runner/workspace/.harness/Dockerfile" "$RALPH_PROJECT_DIR/Dockerfile" 2>/dev/null || true
fi

echo "Cleaning up..."
docker rm "$container_name"

# Clean up overlay temp dir
if [ -n "$overlay_dir" ]; then
  rm -rf "$overlay_dir"
fi

# Pull changes and sync litebrite
echo "Fetching results from remote..."
if [ "$RALPH_MODE" = "template" ]; then
  git -C "$RALPH_HARNESS_DIR" fetch origin
elif [ -n "$RALPH_LOCAL_PATH" ]; then
  git -C "$RALPH_LOCAL_PATH" fetch origin
fi
lb sync 2>/dev/null || true
echo "Done. Log saved: $log_file"
