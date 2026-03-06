#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/lib.sh"
runner_dir="$script_dir/runner"

# --- Parse args ---
raw=false
for arg in "$@"; do
  case "$arg" in
    --raw) raw=true ;;
  esac
done

# --- Set up logging ---
log_file="$RALPH_LOG_DIR/run-$(date +%Y%m%d-%H%M%S).jsonl"
echo "Log file: $log_file"

# --- Preflight: clean working tree ---
if ! git -C "$RALPH_HARNESS_DIR" diff --quiet || ! git -C "$RALPH_HARNESS_DIR" diff --cached --quiet; then
  echo "ERROR: Working tree has uncommitted changes. Commit or stash first."
  exit 1
fi

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
  -f "$runner_dir/Dockerfile" "$RALPH_HARNESS_DIR"

container_name="run-$(date +%Y%m%d-%H%M%S)"
echo "Running agent on branch $RALPH_BRANCH..."
echo "Container name: $container_name"

# Remove stale container with same name
docker rm "$container_name" 2>/dev/null || true

# Persistent volume for Claude Code memory across runs
docker volume create "$RALPH_VOLUME" 2>/dev/null || true
docker run --rm -v "$RALPH_VOLUME:/data" alpine chown "$(id -u):$(id -g)" /data

# Build docker run args
docker_args=()
docker_args+=(--name "$container_name")
docker_args+=(--env-file "$RALPH_ENV_FILE")
docker_args+=(-e REPO_URL="$RALPH_REPO_URL")
docker_args+=(-e BRANCH="$RALPH_BRANCH")
docker_args+=(-v "${SSH_AUTH_SOCK}:/ssh-agent")
docker_args+=(-e SSH_AUTH_SOCK=/ssh-agent)
docker_args+=(-v "$runner_dir/run.sh:/run.sh:ro")
docker_args+=(-v "$RALPH_VOLUME:/home/runner/.claude")

if [ "$raw" = true ]; then
  docker run "${docker_args[@]}" agent-runner /run.sh 2>&1 | tee "$log_file"
else
  docker run "${docker_args[@]}" agent-runner /run.sh 2>&1 | tee "$log_file" | bun run "$script_dir/stream-fmt.ts"
fi

echo ""
echo "Container $container_name finished."
ln -sf "$(basename "$log_file")" "$RALPH_LOG_DIR/latest.jsonl"

echo "Cleaning up..."
docker rm "$container_name"

# --- Pull any code changes the agent pushed ---
echo "Pulling code changes from remote..."
git -C "$RALPH_HARNESS_DIR" pull --ff-only || echo "No new commits to pull."

echo "Done. Log saved: $log_file"
