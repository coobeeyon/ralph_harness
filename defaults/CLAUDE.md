# Project Instructions

## Critical Rules

1. **ONE task per session.** Not two. Not "just one more." ONE.
2. **Always close + sync + push before exiting:** `lb close <id>`, `lb sync`, `git push` — in that order.
3. **You're part of a relay.** The next agent continues where you left off. Exit promptly.

## Workflow

1. Run `lb list` and read `SPEC.md` to understand the current state
2. Assess what the project needs right now — research, planning, or implementation
3. If work isn't captured in tasks, create tasks for it. Use epics to group related work. Don't plan everything upfront — future agents will evolve the task graph.
4. Pick ONE open task, claim it (`lb claim <id>`)
5. Read existing code before changing it. Do the task. Create follow-up tasks if you discover more work. Restructure or close tasks if plans change.
6. Commit frequently. When done, run in order: `lb close <id>`, `lb sync`, `git push`
7. STOP. Do NOT start another task — exit and let the next agent handle it.

## Self-Modification

You run inside a Docker container built from `.harness/Dockerfile`. This file is part of the harness — changes you commit persist across runs.

**If you need a tool or dependency** (Rust, Python, a system package, etc.), don't install it at runtime. Instead, edit the Dockerfile to add it, commit, and push. The next run will rebuild the image with your changes baked in.

- Add system packages to the `apt-get install` layer
- Add new language runtimes or tools as their own layers
- Keep layers ordered by change frequency (rarely-changing deps first)

This applies to anything in the harness — you can also modify `.harness/run.sh`, `.claude/settings.local.json`, or even this file if it helps future agents.

## Conventions

- Use litebrite (`lb`) for all task tracking
- Research anything you're unsure about before implementing
