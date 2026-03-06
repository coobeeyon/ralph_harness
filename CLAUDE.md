# Project Instructions

## Critical Rules

1. **Work until context fills up.** Do as many tasks as your context allows, but stop before you run out.
2. **Always close + sync + push per task:** `lb close <id>`, `lb sync`, `git push` — in that order, after each task.
3. **You're part of a relay.** The next agent continues where you left off. Exit promptly when context is filling up.

## Workflow

1. Run `lb list` and read `SPEC.md` to understand the current state
2. Assess what the project needs right now — research, planning, or implementation
3. If work isn't captured in tasks, create tasks for it. Use epics to group related work. Don't plan everything upfront — future agents will evolve the task graph.
4. Pick an open task, claim it (`lb claim <id>`)
5. Read existing code before changing it. Do the task. Create follow-up tasks if you discover more work. Restructure or close tasks if plans change.
6. Commit frequently. When done, run in order: `lb close <id>`, `lb sync`, `git push`
7. Assess remaining context budget. If you still have capacity, go back to step 4. If context is getting full (~70%), STOP and exit.

## Context Budget

- **Early** (first ~30%): take larger implementation tasks.
- **Mid-session** (~30-60%): medium tasks — bug fixes, small features.
- **Late** (>60%): only small, quick tasks.
- **Stop at ~70%.** Compaction kicks in around 80% — you need headroom to finish cleanly.
- Estimate usage from: turn count, code volume read, tool calls. 3+ substantial tasks or 20+ turns likely means >60%.

## Self-Modification

You run inside a Docker container built from `scripts/runner/Dockerfile`. This file is part of the repo — changes you commit persist across runs.

**If you need a tool or dependency** (Rust, Python, a system package, etc.), don't install it at runtime. Instead, edit the Dockerfile to add it, commit, and push. The next run will rebuild the image with your changes baked in.

- Add system packages to the `apt-get install` layer
- Add new language runtimes or tools as their own layers
- Keep layers ordered by change frequency (rarely-changing deps first)

This applies to anything in the repo — you can also modify `scripts/runner/run.sh`, `.claude/settings.local.json`, or even this file if it helps future agents.

## Conventions

- Use litebrite (`lb`) for all task tracking
- Research anything you're unsure about before implementing
