# AI Agent Harness

Docker-isolated harness for running Claude Code as an autonomous coding agent. Uses task tracking via litebrite and iterative implementation from a spec.

This is a template repo — create a repo from it, write your spec, and let agents work on it.

## Prerequisites

- **Docker** — container runtime for agent isolation
- **SSH agent** — running with keys that have access to your repo (`ssh-add`)
- **bun** — used to run the stream formatter (`stream-fmt.ts`)
- **lb** (litebrite) — task tracking CLI ([coobeeyon/litebrite](https://github.com/coobeeyon/litebrite))
- **Anthropic API key** or Claude Code OAuth token

## Setup

1. Create a repo from this template (or clone it directly)
2. Write your project spec in `SPEC.md`
3. Set up credentials:
   ```bash
   cp .env.example .env
   # Add your ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN
   ```

## Running the Agent

### Single run (`scripts/run.sh`)

Runs one agent session. The agent picks up existing tasks or creates new ones from `SPEC.md`.

```bash
scripts/run.sh [--raw]
```

- `--raw` — output raw JSONL instead of formatted stream

### Loop (`scripts/run-loop.sh`)

Runs the agent repeatedly. After each run, an AI summarizer writes a log summary, then an AI decider checks whether open work remains. The loop stops when the decider says the project is complete.

```bash
scripts/run-loop.sh [--delay=N]
```

- `--delay=N` — wait N seconds between runs (default: 0)

### Epic (`scripts/run-epic.sh`)

Runs a task loop for a specific litebrite epic. Creates a feature branch and works through each child task sequentially. Aborts after 3 consecutive failures.

```bash
scripts/run-epic.sh <epic-id> [timeout-minutes] [--raw]
```

- `timeout-minutes` — per-task timeout (default: 15)

## How It Works

**Relay pattern:** Each run is a fresh agent session. The agent reads task state (via litebrite) and the spec, picks ONE task, does it, commits, pushes, and exits. The next run picks up where the last one left off. This gives each agent a full context window and avoids degradation from long sessions.

**Container lifecycle:**
1. Host script builds a Docker image from `scripts/runner/Dockerfile`
2. Container clones the repo fresh
3. Claude Code runs with `--dangerously-skip-permissions` and a structured prompt
4. Agent reads spec, checks tasks, claims one, implements, commits, pushes
5. Container exits; host pulls changes and syncs litebrite

**Self-modification:** The agent can edit `scripts/runner/Dockerfile` to add tools and dependencies. Changes are committed and rebuilt on the next run.

**Persistent state:** A Docker volume (`agent-claude-home`) persists Claude Code's memory across runs, so the agent retains context about the project.

## Logging

All logs are written to `logs/`.

- **Run logs:** `logs/run-YYYYMMDD-HHMMSS.jsonl` — full JSONL stream from Claude
- **Epic logs:** `logs/epic-<id>-YYYYMMDD-HHMMSS.jsonl`
- **Latest symlink:** `logs/latest.jsonl` always points to the most recent log
- **Summaries:** `logs/summaries/<log-name>.md` — AI-generated markdown summaries (created automatically in loop mode)

The stream formatter (`scripts/stream-fmt.ts`) colorizes output, collapses long code blocks, and suppresses noisy tool results for a cleaner terminal experience. Use `--raw` to bypass it.

## Files

| File | Purpose |
|------|---------|
| `SPEC.md` | Project specification — describe what you want built |
| `CLAUDE.md` | Agent instructions for the harness itself |
| `AGENTS.md` | Agent quick-reference card (lb commands, exit checklist) |
| `scripts/run.sh` | Host: single agent run |
| `scripts/run-loop.sh` | Host: repeated runs with AI decider |
| `scripts/run-epic.sh` | Host: epic task runner |
| `scripts/lib.sh` | Host: shared env vars and paths |
| `scripts/summary.sh` | Generate AI summary of a run log |
| `scripts/decide.sh` | AI decider for loop continuation |
| `scripts/stream-fmt.ts` | JSONL stream formatter for terminal output |
| `scripts/runner/Dockerfile` | Docker image definition |
| `scripts/runner/run.sh` | Container entrypoint (single run) |
| `scripts/runner/run-epic.sh` | Container entrypoint (epic mode) |
| `.claude/settings.local.json` | Claude Code permissions for the harness |
| `.env.example` | Credential template |

## Mr Mouth (v2)

Mr Mouth is a Rust CLI that will replace the bash scripts above with a single binary. See `SPEC.md` and `mrmouth/` for details. It's under active development.
