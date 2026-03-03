# AI Agent Harness

Docker-isolated harness for running Claude Code as an autonomous coding agent. Supports task tracking via litebrite, iterative implementation from a spec, and three different usage modes depending on your project setup.

## Prerequisites

- **Docker** — container runtime for agent isolation
- **SSH agent** — running with keys that have access to your repo (`ssh-add`)
- **bun** — used to run the stream formatter (`stream-fmt.ts`)
- **lb** (litebrite) — task tracking CLI ([coobeeyon/litebrite](https://github.com/coobeeyon/litebrite))
- **Anthropic API key** or Claude Code OAuth token

## Three Ways to Use This Harness

| Mode | Use when... | Harness files in your repo? |
|------|-------------|----------------------------|
| **Template** | Starting a fresh project | Yes (your repo *is* the harness) |
| **External** | Driving an existing repo without modifying it | No (files are injected at runtime) |
| **Init** | Permanently adopting the harness into an existing repo | Yes (copied once, then yours) |

### 1. Template Mode (new project)

The harness repo itself is the project. Best for greenfield work.

**Setup:**

1. Create a repo from this template (or clone it directly)
2. Write your project spec in `SPEC.md`
3. Set up credentials:
   ```bash
   cp .env.example .env
   # Add your ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN
   ```

**Run:**

```bash
scripts/run.sh                  # Single run
scripts/run-loop.sh             # Repeated runs until done
scripts/run-epic.sh lb-XXXX     # Work through an epic's tasks
```

**Self-modification:** The agent can edit `scripts/runner/Dockerfile` to add tools and dependencies. Changes are committed and rebuilt on the next run.

### 2. External Mode (existing repo, no modifications)

The harness drives work on a separate target repo. No harness files are added to the target — they're injected into the container at runtime via an overlay. The agent only sees the target repo.

**Setup:**

1. Create a project config:
   ```bash
   mkdir -p projects/my-project
   cp defaults/project.conf.example projects/my-project/project.conf
   ```

2. Edit `projects/my-project/project.conf`:
   ```bash
   REPO_URL=git@github.com:org/my-repo.git
   BRANCH=main
   # LOCAL_PATH=/home/user/my-repo   # Optional: mount local checkout instead of cloning
   ```

3. Set up credentials in `.env` (same as template mode)

**Run:** Pass the project name as the first argument:

```bash
scripts/run.sh my-project
scripts/run-loop.sh my-project
scripts/run-epic.sh lb-XXXX 15 my-project
```

**Overlay system:** At container start, these files are copied into the workspace *only if they don't already exist* in the target repo:
- `CLAUDE.md`, `AGENTS.md`, `SPEC.md` — from `defaults/` (or project-specific overrides)
- `.claude/settings.local.json` — from `defaults/claude-settings.json`
- `.harness/Dockerfile` — the runner Dockerfile

To override defaults for a specific project, place files in `projects/<name>/`:
- `projects/my-project/CLAUDE.md` takes priority over `defaults/CLAUDE.md`
- Same for `AGENTS.md`, `claude-settings.json`

**LOCAL_PATH option:** When set in `project.conf`, the harness bind-mounts your local checkout into the container instead of cloning. Useful for large repos or when you want to see changes locally immediately. The harness checks for uncommitted changes before starting and runs `git pull --ff-only` after each run.

**Self-modification:** The agent edits `.harness/Dockerfile` inside the workspace. After the container exits, the updated Dockerfile is extracted back to `projects/<name>/Dockerfile` on the host, so changes persist across runs.

### 3. Init Mode (adopt harness into existing repo)

Copies the harness scripts and config into an existing repo permanently. After init, you use template mode commands (no project name argument needed).

**Usage:**

```bash
scripts/init.sh /path/to/your/repo
```

**What it does:**
- Copies `scripts/` directory, `AGENTS.md`, `.env.example`
- Creates `SPEC.md` from template (only if one doesn't exist)
- Merges entries into `.gitignore` (logs, .env, etc.)
- Appends harness instructions to `CLAUDE.md` (wrapped in HTML comment markers for idempotency)
- Merges `.claude/settings.local.json` (adds missing permissions and hooks)

Running `init.sh` again is safe — it skips files that are already present and won't duplicate merged content.

**After init:**

```bash
cd /path/to/your/repo
cp .env.example .env        # Add your API key
vim SPEC.md                 # Describe your project
git add -A && git commit -m "Add ralph harness"
scripts/run.sh              # Go
```

## Running the Agent

### Single run (`scripts/run.sh`)

Runs one agent session. The agent picks up existing tasks or creates new ones from `SPEC.md`.

```bash
scripts/run.sh [project-name] [--raw]
```

- `--raw` — output raw JSONL instead of formatted stream

### Loop (`scripts/run-loop.sh`)

Runs the agent repeatedly. After each run, an AI summarizer writes a log summary, then an AI decider checks whether open work remains. The loop stops when the decider says the project is complete.

```bash
scripts/run-loop.sh [project-name] [--delay=N]
```

- `--delay=N` — wait N seconds between runs (default: 0)

### Epic (`scripts/run-epic.sh`)

Runs a task loop for a specific litebrite epic. Creates a feature branch and works through each child task sequentially. Aborts after 3 consecutive failures.

```bash
scripts/run-epic.sh <epic-id> [timeout-minutes] [project-name] [--raw]
```

- `timeout-minutes` — per-task timeout (default: 15)

## How It Works

**Relay pattern:** Each run is a fresh agent session. The agent reads task state (via litebrite) and the spec, picks ONE task, does it, commits, pushes, and exits. The next run picks up where the last one left off. This gives each agent a full context window and avoids degradation from long sessions.

**Container lifecycle:**
1. Host script builds a Docker image from `scripts/runner/Dockerfile`
2. Container clones the repo fresh (or uses a bind-mounted local checkout)
3. In external mode, overlay files are injected into the workspace
4. Claude Code runs with `--dangerously-skip-permissions` and a structured prompt
5. Agent reads spec, checks tasks, claims one, implements, commits, pushes
6. Container exits; host pulls changes and syncs litebrite

**Persistent state:** A Docker volume (`agent-claude-home`) persists Claude Code's memory across runs, so the agent retains context about the project.

## Logging

All logs are written to `logs/` in the harness directory.

- **Run logs:** `logs/run-YYYYMMDD-HHMMSS.jsonl` — full JSONL stream from Claude
- **Epic logs:** `logs/epic-<id>-YYYYMMDD-HHMMSS.jsonl`
- **Latest symlink:** `logs/latest.jsonl` always points to the most recent log
- **Summaries:** `logs/summaries/<log-name>.md` — AI-generated markdown summaries (created automatically in loop mode)

The stream formatter (`scripts/stream-fmt.ts`) colorizes output, collapses long code blocks, and suppresses noisy tool results (file reads, task list operations) for a cleaner terminal experience. Use `--raw` to bypass it.

## Files

| File | Purpose |
|------|---------|
| `SPEC.md` | Project specification — describe what you want built |
| `CLAUDE.md` | Agent instructions for the harness itself |
| `AGENTS.md` | Agent quick-reference card (lb commands, exit checklist) |
| `scripts/run.sh` | Host: single agent run |
| `scripts/run-loop.sh` | Host: repeated runs with AI decider |
| `scripts/run-epic.sh` | Host: epic task runner |
| `scripts/lib.sh` | Host: shared functions (project resolution, overlay building) |
| `scripts/init.sh` | Adopt harness into an existing repo |
| `scripts/summary.sh` | Generate AI summary of a run log |
| `scripts/decide.sh` | AI decider for loop continuation |
| `scripts/stream-fmt.ts` | JSONL stream formatter for terminal output |
| `scripts/runner/Dockerfile` | Docker image definition |
| `scripts/runner/run.sh` | Container entrypoint (single run) |
| `scripts/runner/run-epic.sh` | Container entrypoint (epic mode) |
| `defaults/CLAUDE.md` | Default agent instructions for external-mode projects |
| `defaults/AGENTS.md` | Default agent reference card |
| `defaults/claude-settings.json` | Default Claude Code permissions and hooks |
| `defaults/project.conf.example` | Template for external-mode project config |
| `.claude/settings.local.json` | Claude Code permissions for the harness itself |
| `.env.example` | Credential template |
