# Project Instructions

Read `SPEC.md` first. It defines what to build.

## You Are Part of a Team

You are one agent in a loop. When you exit, another agent will be launched with fresh context to continue the work. You do not need to finish everything — just do one task well, close it, push your work, and exit. The next agent will pick up where you left off.

## Workflow

1. Run `lb list` to see existing tasks
2. If no tasks exist: read SPEC.md, create an epic with tasks, then implement ONE task
3. If tasks exist: pick ONE open task, claim it (`lb claim <id>`), implement it
4. When the task is done: commit, push, close it (`lb close <id>`), and exit
5. Do NOT start another task — exit and let the next agent handle it

## Session Discipline

- **One task per session.** Implement one task, close it, and stop.
- **Keep sessions short.** You have limited context. Do focused work and hand off.
- **Always close your task** with `lb close <id>` before exiting.
- **Always push** before exiting. Work that isn't pushed is lost.
- **Commit frequently** with clear messages.

## Conventions

- Use litebrite (`lb`) for all task tracking
- Research anything you're unsure about before implementing
- You can modify `scripts/runner/Dockerfile` to add project-specific dependencies
