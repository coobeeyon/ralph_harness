#!/usr/bin/env bash
set -euo pipefail

# scripts/init.sh -- adopt ralph harness into an existing repo
# Usage: init.sh <target-repo-path>

harness_dir="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:?Usage: init.sh <target-repo-path>}"
target="$(cd "$target" && pwd)"

# --- Validate target is a git repo ---
if [ ! -d "$target/.git" ]; then
  echo "ERROR: $target is not a git repository."
  exit 1
fi

summary_lines=""
add_summary() { summary_lines="${summary_lines}  - $1\n"; }

# --- (1) Copy scripts/ directory ---
echo "Copying scripts/..."
cp -r "$harness_dir/scripts" "$target/scripts"
add_summary "Copied scripts/ directory"

# --- (2) Copy AGENTS.md ---
echo "Copying AGENTS.md..."
cp "$harness_dir/AGENTS.md" "$target/AGENTS.md"
add_summary "Copied AGENTS.md"

# --- (3) Copy .env.example ---
echo "Copying .env.example..."
cp "$harness_dir/.env.example" "$target/.env.example"
add_summary "Copied .env.example"

# --- (4) Create SPEC-md from template if absent ---
if [ ! -f "$target/SPEC.md" ]; then
  echo "Creating SPEC.md from template..."
  cp "$harness_dir/SPEC.md" "$target/SPEC.md"
  add_summary "Created SPEC.md from template"
else
  echo "SPEC.md already exists, skipping."
  add_summary "SPEC.md already exists (skipped)"
fi

# --- (5) Merge .gitignore entries ---
echo "Merging .gitignore..."
touch "$target/.gitignore"
added_entries=0
for entry in "logs/" ".env" "*.log" "*.jsonl" "!tests/*.jsonl" ".claude/settings.local.json"; do
  if ! grep -qxF "$entry" "$target/.gitignore"; then
    echo "$entry" >> "$target/.gitignore"
    added_entries=$((added_entries + 1))
  fi
done
if [ "$added_entries" -gt 0 ]; then
  add_summary "Added $added_entries entries to .gitignore"
else
  add_summary ".gitignore already up to date"
fi

# --- (6) Merge CLAUDE.md ---
echo "Merging CLAUDE.md..."
harness_marker_start="<!-- ralph-harness-start -->"
harness_marker_end="<!-- ralph-harness-end -->"

if [ -f "$target/CLAUDE.md" ] && grep -qF "$harness_marker_start" "$target/CLAUDE.md"; then
  echo "CLAUDE.md already has harness sections, skipping."
  add_summary "CLAUDE.md harness sections already present (skipped)"
else
  {
    echo ""
    echo "$harness_marker_start"
    cat "$harness_dir/defaults/CLAUDE.md"
    echo "$harness_marker_end"
  } >> "$target/CLAUDE.md"
  add_summary "Appended harness sections to CLAUDE.md"
fi

# --- (7) Merge .claude/settings.local.json ---
echo "Merging .claude/settings.local.json..."
mkdir -p "$target/.claude"
harness_settings="$harness_dir/.claude/settings.local.json"
target_settings="$target/.claude/settings.local.json"

if [ ! -f "$harness_settings" ]; then
  echo "No harness settings to merge."
  add_summary "No harness settings found (skipped)"
elif [ ! -f "$target_settings" ]; then
  cp "$harness_settings" "$target_settings"
  add_summary "Copied .claude/settings.local.json"
else
  node -e '
    var fs = require("fs");
    var t = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    var h = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    if (h.permissions && h.permissions.allow) {
      if (!t.permissions) t.permissions = {};
      if (!t.permissions.allow) t.permissions.allow = [];
      var existing = new Set(t.permissions.allow);
      h.permissions.allow.forEach(function(perm) {
        if (!existing.has(perm)) t.permissions.allow.push(perm);
      });
    }
    if (h.hooks) {
      if (!t.hooks) t.hooks = {};
      Object.keys(h.hooks).forEach(function(ev) {
        if (!t.hooks[ev]) {
          t.hooks[ev] = h.hooks[ev];
        } else {
          var existingSet = new Set(t.hooks[ev].map(function(e) { return JSON.stringify(e); }));
          h.hooks[ev].forEach(function(entry) {
            if (!existingSet.has(JSON.stringify(entry))) {
              t.hooks[ev].push(entry);
            }
          });
        }
      });
    }
    fs.writeFileSync(process.argv[1], JSON.stringify(t, null, 2) + "\n");
  ' "$target_settings" "$harness_settings"
  add_summary "Merged .claude/settings.local.json"
fi

# --- Print summary ---
echo ""
echo "=== Init complete ==="
printf "%b" "$summary_lines"
echo ""
echo "Next steps:"
echo "  1. Review the changes: cd $target && git diff"
echo "  2. Set up your API key: cp .env.example .env && edit .env"
echo "  3. Fill in SPEC.md with your project details"
echo "  4. Commit: git add -A && git commit -m 'Add ralph harness'"
