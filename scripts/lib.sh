#!/usr/bin/env bash
# scripts/lib.sh -- shared project resolution for ralph harness
# Source this file from host scripts: source "$(dirname "$0")/lib.sh"

# Locate harness root (parent of scripts/)
RALPH_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# resolve_project [project-name]
#
# Sets RALPH_MODE and project-level variables.
# - If a project name is given and projects/<name>/project.conf exists,
#   loads config from it (external mode).
# - Otherwise, falls back to template mode (repo is the harness itself).
resolve_project() {
  local project_name="${1:-}"

  if [ -n "$project_name" ] && [ -f "$RALPH_HARNESS_DIR/projects/$project_name/project.conf" ]; then
    RALPH_MODE=external
    RALPH_PROJECT_DIR="$RALPH_HARNESS_DIR/projects/$project_name"

    # Load project config (REPO_URL, BRANCH, LOCAL_PATH)
    # shellcheck source=/dev/null
    source "$RALPH_PROJECT_DIR/project.conf"

    RALPH_REPO_URL="${REPO_URL:?project.conf must set REPO_URL}"
    RALPH_BRANCH="${BRANCH:-main}"
    RALPH_LOCAL_PATH="${LOCAL_PATH:-}"
  else
    RALPH_MODE=template
    RALPH_PROJECT_DIR="$RALPH_HARNESS_DIR"
    RALPH_REPO_URL="$(git -C "$RALPH_HARNESS_DIR" remote get-url origin)"
    RALPH_BRANCH="$(git -C "$RALPH_HARNESS_DIR" branch --show-current)"
    RALPH_LOCAL_PATH=""
  fi

  RALPH_LOG_DIR="$RALPH_HARNESS_DIR/logs"
  RALPH_ENV_FILE="$RALPH_HARNESS_DIR/.env"
  RALPH_VOLUME="agent-claude-home"

  mkdir -p "$RALPH_LOG_DIR"

  export RALPH_MODE RALPH_REPO_URL RALPH_BRANCH RALPH_LOCAL_PATH
  export RALPH_LOG_DIR RALPH_ENV_FILE RALPH_VOLUME
  export RALPH_HARNESS_DIR RALPH_PROJECT_DIR
}

# resolve_overlay <filename>
#
# Prints the path to the highest-priority copy of <filename>.
# Priority: projects/<name>/ > defaults/ > repo root
# Returns 1 if the file is not found anywhere.
resolve_overlay() {
  local filename="$1"

  # Project-specific override (external mode only)
  if [ "$RALPH_MODE" = "external" ] && [ -f "$RALPH_PROJECT_DIR/$filename" ]; then
    echo "$RALPH_PROJECT_DIR/$filename"
    return 0
  fi

  # Harness defaults
  if [ -f "$RALPH_HARNESS_DIR/defaults/$filename" ]; then
    echo "$RALPH_HARNESS_DIR/defaults/$filename"
    return 0
  fi

  # Repo root fallback (template mode)
  if [ -f "$RALPH_HARNESS_DIR/$filename" ]; then
    echo "$RALPH_HARNESS_DIR/$filename"
    return 0
  fi

  return 1
}

# build_overlay_dir
#
# Assembles resolved overlay files into a temp directory suitable for
# Docker bind-mounting into the container. The caller is responsible
# for cleaning up the temp dir (or relying on container teardown).
#
# Layout inside the overlay dir:
#   CLAUDE.md
#   AGENTS.md
#   settings.local.json
#
# Prints the path to the overlay directory.
build_overlay_dir() {
  local overlay_dir
  overlay_dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-overlay.XXXXXX")"

  local claude_md agents_md settings_json

  claude_md="$(resolve_overlay CLAUDE.md)" || true
  agents_md="$(resolve_overlay AGENTS.md)" || true
  settings_json="$(resolve_overlay claude-settings.json)" || true

  if [ -n "$claude_md" ]; then
    cp "$claude_md" "$overlay_dir/CLAUDE.md"
  fi

  if [ -n "$agents_md" ]; then
    cp "$agents_md" "$overlay_dir/AGENTS.md"
  fi

  if [ -n "$settings_json" ]; then
    cp "$settings_json" "$overlay_dir/settings.local.json"
  fi

  echo "$overlay_dir"
}
