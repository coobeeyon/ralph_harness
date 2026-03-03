#!/usr/bin/env bash
set -euo pipefail

# tests/test-init.sh — end-to-end test for scripts/init.sh
# Creates a temporary git repo, runs init.sh, and verifies results.

harness_dir="$(cd "$(dirname "$0")/.." && pwd)"
init_script="$harness_dir/scripts/init.sh"
pass=0
fail=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }

assert() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    green "  PASS: $desc"
    pass=$((pass + 1))
  else
    red "  FAIL: $desc"
    fail=$((fail + 1))
  fi
}

assert_not() {
  local desc="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    green "  PASS: $desc"
    pass=$((pass + 1))
  else
    red "  FAIL: $desc"
    fail=$((fail + 1))
  fi
}

# --- Set up temp repo ---
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init "$tmp/target" --quiet
cd "$tmp/target"
git commit --allow-empty -m "initial" --quiet

# Pre-populate files that init.sh should merge into (not overwrite)
cat > CLAUDE.md << 'EOF'
# My Project

Some existing instructions.
EOF

cat > .gitignore << 'EOF'
node_modules/
.env
EOF

mkdir -p .claude
cat > .claude/settings.local.json << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(npm *)"
    ]
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "echo hello"
          }
        ]
      }
    ]
  }
}
SETTINGS

cat > SPEC.md << 'EOF'
# My Spec
EOF

echo ""
echo "=== Test 1: First run of init.sh ==="
"$init_script" "$tmp/target"

echo ""
echo "--- Verifying first run ---"

# CLAUDE.md checks
assert "CLAUDE.md exists" test -f CLAUDE.md
assert "CLAUDE.md has original content" grep -q "My Project" CLAUDE.md
assert "CLAUDE.md has harness start marker" grep -qF "<!-- ralph-harness-start -->" CLAUDE.md
assert "CLAUDE.md has harness end marker" grep -qF "<!-- ralph-harness-end -->" CLAUDE.md
assert "CLAUDE.md references .harness/Dockerfile (not scripts/runner/Dockerfile)" grep -q '\.harness/Dockerfile' CLAUDE.md
assert_not "CLAUDE.md does NOT reference scripts/runner/Dockerfile" grep -q 'scripts/runner/Dockerfile' CLAUDE.md

# .gitignore checks
assert ".gitignore has logs/" grep -qxF "logs/" .gitignore
assert ".gitignore has *.log" grep -qxF "*.log" .gitignore
assert ".gitignore has *.jsonl" grep -qxF "*.jsonl" .gitignore
assert ".gitignore has .env (no duplicate)" test "$(grep -cxF '.env' .gitignore)" -eq 1
assert ".gitignore has node_modules/ (preserved)" grep -qxF "node_modules/" .gitignore

# SPEC.md should NOT be overwritten (it already existed)
assert "SPEC.md preserved (not overwritten)" grep -q "My Spec" SPEC.md

# settings.local.json checks
assert "settings.local.json exists" test -f .claude/settings.local.json
assert "settings has original permission (npm)" node -e '
  var s = JSON.parse(require("fs").readFileSync(".claude/settings.local.json","utf8"));
  process.exit(s.permissions.allow.includes("Bash(npm *)") ? 0 : 1);
'
assert "settings has harness permission (git)" node -e '
  var s = JSON.parse(require("fs").readFileSync(".claude/settings.local.json","utf8"));
  process.exit(s.permissions.allow.includes("Bash(git *)") ? 0 : 1);
'
assert "settings has original hook (echo hello)" node -e '
  var s = JSON.parse(require("fs").readFileSync(".claude/settings.local.json","utf8"));
  var hooks = s.hooks.SessionStart;
  var found = hooks.some(function(h) {
    return h.hooks.some(function(e) { return e.command === "echo hello"; });
  });
  process.exit(found ? 0 : 1);
'
assert "settings has harness hook (lb prime)" node -e '
  var s = JSON.parse(require("fs").readFileSync(".claude/settings.local.json","utf8"));
  var hooks = s.hooks.SessionStart;
  var found = hooks.some(function(h) {
    return h.hooks.some(function(e) { return e.command === "lb prime"; });
  });
  process.exit(found ? 0 : 1);
'

# Copied files
assert "scripts/ directory copied" test -d scripts
assert "AGENTS.md copied" test -f AGENTS.md
assert ".env.example copied" test -f .env.example

echo ""
echo "=== Test 2: Idempotency (second run) ==="

# Count markers before second run
markers_before=$(grep -cF "<!-- ralph-harness-start -->" CLAUDE.md)
gitignore_lines_before=$(wc -l < .gitignore)

"$init_script" "$tmp/target"

echo ""
echo "--- Verifying idempotency ---"

markers_after=$(grep -cF "<!-- ralph-harness-start -->" CLAUDE.md)
gitignore_lines_after=$(wc -l < .gitignore)

assert "CLAUDE.md harness marker not duplicated" test "$markers_before" -eq "$markers_after"
assert ".gitignore line count unchanged" test "$gitignore_lines_before" -eq "$gitignore_lines_after"

assert "settings permissions not duplicated" node -e '
  var s = JSON.parse(require("fs").readFileSync(".claude/settings.local.json","utf8"));
  var count = s.permissions.allow.filter(function(p) { return p === "Bash(git *)"; }).length;
  process.exit(count === 1 ? 0 : 1);
'

# --- Summary ---
echo ""
echo "=========================="
total=$((pass + fail))
if [ "$fail" -eq 0 ]; then
  green "All $total tests passed."
else
  red "$fail of $total tests FAILED."
  exit 1
fi
