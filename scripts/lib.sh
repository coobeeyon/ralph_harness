#!/usr/bin/env bash
# scripts/lib.sh -- shared paths and env vars for ralph harness
# Source this file from host scripts: source "$(dirname "$0")/lib.sh"

# Locate harness root (parent of scripts/)
RALPH_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RALPH_REPO_URL="$(git -C "$RALPH_HARNESS_DIR" remote get-url origin)"
RALPH_BRANCH="$(git -C "$RALPH_HARNESS_DIR" branch --show-current)"
RALPH_LOG_DIR="$RALPH_HARNESS_DIR/logs"
RALPH_ENV_FILE="$RALPH_HARNESS_DIR/.env"
RALPH_VOLUME="agent-claude-home"

mkdir -p "$RALPH_LOG_DIR"

export RALPH_REPO_URL RALPH_BRANCH
export RALPH_LOG_DIR RALPH_ENV_FILE RALPH_VOLUME
export RALPH_HARNESS_DIR
