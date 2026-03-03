#!/usr/bin/env bash
set -euo pipefail

# tests/test-external-mode.sh — end-to-end test for external/stealth mode
# Tests project resolution, overlay building, and container setup.

harness_dir="$(cd "$(dirname "$0")/.." && pwd)"

# Use files for counters so they work across subshells
_count_dir="$(mktemp -d)"
echo 0 > "$_count_dir/pass"
echo 0 > "$_count_dir/fail"

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }

_inc_pass() { echo $(( $(cat "$_count_dir/pass") + 1 )) > "$_count_dir/pass"; }
_inc_fail() { echo $(( $(cat "$_count_dir/fail") + 1 )) > "$_count_dir/fail"; }

assert() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    green "  PASS: $desc"
    _inc_pass
  else
    red "  FAIL: $desc"
    _inc_fail
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    green "  PASS: $desc"
    _inc_pass
  else
    red "  FAIL: $desc (expected='$expected', actual='$actual')"
    _inc_fail
  fi
}

assert_not() {
  local desc="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    green "  PASS: $desc"
    _inc_pass
  else
    red "  FAIL: $desc"
    _inc_fail
  fi
}

# --- Set up temp project config ---
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" "$_count_dir"; rm -rf "$harness_dir/projects/test-e2e"' EXIT

# Create a bare git repo to serve as our "remote"
git init --bare "$tmp/remote.git" --quiet
# Create a local clone to populate it
git clone "$tmp/remote.git" "$tmp/local-repo" --quiet 2>/dev/null
cd "$tmp/local-repo"
echo "# Test repo" > README.md
git add README.md
git commit -m "initial" --quiet
git push origin main --quiet 2>/dev/null

# Create project config in the harness
project_dir="$harness_dir/projects/test-e2e"
mkdir -p "$project_dir"
cat > "$project_dir/project.conf" << EOF
REPO_URL=$tmp/remote.git
BRANCH=main
LOCAL_PATH=$tmp/local-repo
EOF

# Create project-specific SPEC.md overlay
cat > "$project_dir/SPEC.md" << 'EOF'
# Test E2E Project
This is a test SPEC.md for the e2e test.
EOF

# Create project-specific CLAUDE.md override
cat > "$project_dir/CLAUDE.md" << 'EOF'
# Project-Specific Instructions
This overrides the defaults/CLAUDE.md for this project.
EOF

echo ""
echo "=== Test 1: resolve_project() — external mode ==="

# Source lib.sh and test resolve_project
(
  source "$harness_dir/scripts/lib.sh"
  resolve_project "test-e2e"

  assert_eq "RALPH_MODE is external" "external" "$RALPH_MODE"
  assert_eq "RALPH_REPO_URL matches" "$tmp/remote.git" "$RALPH_REPO_URL"
  assert_eq "RALPH_BRANCH is main" "main" "$RALPH_BRANCH"
  assert_eq "RALPH_LOCAL_PATH matches" "$tmp/local-repo" "$RALPH_LOCAL_PATH"
  assert_eq "RALPH_PROJECT_DIR is correct" "$project_dir" "$RALPH_PROJECT_DIR"
  assert "RALPH_LOG_DIR created" test -d "$RALPH_LOG_DIR"
)

echo ""
echo "=== Test 2: resolve_project() — template mode ==="

(
  cd "$harness_dir"
  source "$harness_dir/scripts/lib.sh"
  resolve_project ""

  assert_eq "RALPH_MODE is template" "template" "$RALPH_MODE"
  assert_eq "RALPH_PROJECT_DIR is harness root" "$harness_dir" "$RALPH_PROJECT_DIR"
  assert "RALPH_LOCAL_PATH is empty" test -z "$RALPH_LOCAL_PATH"
)

echo ""
echo "=== Test 3: resolve_overlay() — priority ordering ==="

(
  source "$harness_dir/scripts/lib.sh"
  resolve_project "test-e2e"

  # Project-specific CLAUDE.md should win over defaults/
  result="$(resolve_overlay CLAUDE.md)"
  assert_eq "CLAUDE.md resolves to project dir" "$project_dir/CLAUDE.md" "$result"

  # SPEC.md is in project dir too
  result="$(resolve_overlay SPEC.md)"
  assert_eq "SPEC.md resolves to project dir" "$project_dir/SPEC.md" "$result"

  # AGENTS.md not in project dir, should fall back to defaults/
  result="$(resolve_overlay AGENTS.md)"
  assert_eq "AGENTS.md resolves to defaults/" "$harness_dir/defaults/AGENTS.md" "$result"

  # claude-settings.json should come from defaults/
  result="$(resolve_overlay claude-settings.json)"
  assert_eq "claude-settings.json resolves to defaults/" "$harness_dir/defaults/claude-settings.json" "$result"

  # Nonexistent file should fail
  assert_not "nonexistent.txt returns error" resolve_overlay nonexistent.txt
)

echo ""
echo "=== Test 4: resolve_overlay() — template mode fallback ==="

(
  cd "$harness_dir"
  source "$harness_dir/scripts/lib.sh"
  resolve_project ""

  # In template mode, CLAUDE.md should resolve to defaults/ then harness root
  result="$(resolve_overlay CLAUDE.md)"
  assert_eq "Template CLAUDE.md resolves to defaults/" "$harness_dir/defaults/CLAUDE.md" "$result"
)

echo ""
echo "=== Test 5: build_overlay_dir() — external mode ==="

(
  source "$harness_dir/scripts/lib.sh"
  resolve_project "test-e2e"

  overlay="$(build_overlay_dir)"
  assert "Overlay dir exists" test -d "$overlay"
  assert "Overlay has CLAUDE.md" test -f "$overlay/CLAUDE.md"
  assert "Overlay has AGENTS.md" test -f "$overlay/AGENTS.md"
  assert "Overlay has settings.local.json" test -f "$overlay/settings.local.json"

  # Verify CLAUDE.md came from project (not defaults)
  assert "Overlay CLAUDE.md is project-specific" grep -q "Project-Specific Instructions" "$overlay/CLAUDE.md"
  assert_not "Overlay CLAUDE.md is NOT from defaults" grep -q ".harness/Dockerfile" "$overlay/CLAUDE.md"

  # Verify settings is valid JSON
  assert "settings.local.json is valid JSON" node -e "JSON.parse(require('fs').readFileSync('$overlay/settings.local.json','utf8'))"

  rm -rf "$overlay"
)

echo ""
echo "=== Test 6: Container overlay injection (mock) ==="

# Simulate what scripts/runner/run.sh does with overlay files
(
  source "$harness_dir/scripts/lib.sh"
  resolve_project "test-e2e"
  overlay="$(build_overlay_dir)"

  # Create a mock workspace (simulating what the container does)
  mock_workspace="$tmp/mock-workspace"
  mkdir -p "$mock_workspace"

  # Simulate the overlay logic from runner/run.sh lines 15-28
  if [ -d "$overlay" ]; then
    [ -f "$overlay/CLAUDE.md" ] && [ ! -f "$mock_workspace/CLAUDE.md" ] && cp "$overlay/CLAUDE.md" "$mock_workspace/CLAUDE.md"
    [ -f "$overlay/AGENTS.md" ] && [ ! -f "$mock_workspace/AGENTS.md" ] && cp "$overlay/AGENTS.md" "$mock_workspace/AGENTS.md"
    [ -f "$overlay/SPEC.md" ] && [ ! -f "$mock_workspace/SPEC.md" ] && cp "$overlay/SPEC.md" "$mock_workspace/SPEC.md"
    if [ -f "$overlay/claude-settings.json" ] && [ ! -f "$mock_workspace/.claude/settings.local.json" ]; then
      mkdir -p "$mock_workspace/.claude"
      cp "$overlay/claude-settings.json" "$mock_workspace/.claude/settings.local.json"
    fi
  fi

  assert "Workspace has CLAUDE.md after overlay" test -f "$mock_workspace/CLAUDE.md"
  assert "Workspace has AGENTS.md after overlay" test -f "$mock_workspace/AGENTS.md"
  assert "Workspace CLAUDE.md is project-specific" grep -q "Project-Specific Instructions" "$mock_workspace/CLAUDE.md"

  # Verify overlay doesn't clobber existing files
  echo "# Original" > "$mock_workspace/CLAUDE.md"
  if [ -f "$overlay/CLAUDE.md" ] && [ ! -f "$mock_workspace/CLAUDE.md" ]; then
    cp "$overlay/CLAUDE.md" "$mock_workspace/CLAUDE.md"
  fi
  assert "Existing CLAUDE.md not overwritten" grep -q "Original" "$mock_workspace/CLAUDE.md"

  rm -rf "$overlay"
)

echo ""
echo "=== Test 7: Docker build and mounts (if docker available) ==="

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # Test that the Dockerfile builds successfully
  if docker build -q -t agent-runner-test \
    --build-arg HOST_UID="$(id -u)" \
    --build-arg HOST_GID="$(id -g)" \
    -f "$harness_dir/scripts/runner/Dockerfile" "$harness_dir" >/dev/null 2>&1; then

    green "  PASS: Docker image builds successfully"
    _inc_pass

    # Verify container user is correct
    container_user=$(docker run --rm agent-runner-test -c "whoami" 2>/dev/null || echo "unknown")
    assert_eq "Container user is runner" "runner" "$container_user"

    container_home=$(docker run --rm agent-runner-test -c 'echo $HOME' 2>/dev/null || echo "unknown")
    assert_eq "Container HOME is /home/runner" "/home/runner" "$container_home"

    # Verify overlay mount point works
    overlay_test="$tmp/overlay-test"
    mkdir -p "$overlay_test"
    echo "test-claude" > "$overlay_test/CLAUDE.md"
    overlay_check=$(docker run --rm -v "$overlay_test:/overlay:ro" agent-runner-test -c "cat /overlay/CLAUDE.md" 2>/dev/null || echo "failed")
    assert_eq "Overlay mount readable in container" "test-claude" "$overlay_check"

    # Verify workspace mount point works
    workspace_check=$(docker run --rm -v "$tmp/local-repo:/home/runner/workspace" agent-runner-test -c "cat /home/runner/workspace/README.md" 2>/dev/null || echo "failed")
    assert_eq "Workspace mount at \$HOME/workspace works" "# Test repo" "$workspace_check"

    docker rmi agent-runner-test >/dev/null 2>&1 || true
  else
    red "  FAIL: Docker image failed to build"
    _inc_fail
  fi
else
  echo "  SKIP: Docker not available or not running"
fi

# --- Summary ---
echo ""
echo "=========================="
pass=$(cat "$_count_dir/pass")
fail=$(cat "$_count_dir/fail")
total=$((pass + fail))
if [ "$fail" -eq 0 ]; then
  green "All $total tests passed."
else
  red "$fail of $total tests FAILED."
  exit 1
fi
