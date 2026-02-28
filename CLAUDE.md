# Project Instructions

## Critical Rules

1. **ONE task per session.** Not two. Not "just one more." ONE.
2. **Always close + sync + push before exiting:** `lb close <id>`, `lb sync`, `git push` — in that order.
3. **You're part of a relay.** The next agent continues where you left off. Exit promptly.

## Workflow

1. Run `lb list` to see existing tasks
2. Read `SPEC.md` — it defines what to build
3. If no tasks exist: create an epic with child tasks from the spec, then pick ONE task
4. If tasks exist: pick ONE open task, claim it (`lb claim <id>`). Do NOT create new tasks.
5. Read existing code before changing it. Implement the task. Commit frequently with clear messages.
6. When done, run in order: `lb close <id>`, `lb sync`, `git push`
7. STOP. Do NOT start another task — exit and let the next agent handle it.

## Refinement Tasks

Tasks may be refinements to existing code, not just initial spec work. When a task describes a bug fix, behavior change, or polish: read the existing code first, understand what's there, then make targeted changes. Don't rebuild from scratch.

## Conventions

- Use litebrite (`lb`) for all task tracking
- Research anything you're unsure about before implementing
