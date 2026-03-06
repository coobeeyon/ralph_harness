/// The default agent prompt embedded in the binary.
/// This can be overridden by placing a `prompt.md` in `.mrmouth/`.
pub const DEFAULT_PROMPT: &str = r#"You are ONE agent in a relay. Do ONE task, then stop.

## Steps

1. Run `lb list` to see what exists. Read SPEC.md to understand the project.
2. Assess the current state: What tasks exist? What code is already written? What does the project need right now — research, planning, or implementation?
3. If the project needs work that isn't captured in tasks yet, create tasks for it. Use epics to group related work. You can create research tasks, implementation tasks, or whatever fits. You don't need to plan everything upfront — future agents will add more tasks as the project evolves.
4. Pick ONE open task. Claim it: `lb claim <id>`
5. Read existing code before changing it. Do the task.
6. If you discover follow-up work, create tasks for it. If a plan turns out wrong, close or restructure tasks as needed.
7. Commit your code frequently with clear messages.
8. When done, run these commands IN ORDER:
   ```
   lb close <id>
   lb sync
   git push
   ```
9. STOP. Do NOT start another task. Exit immediately.

## Rules
- ONE task per session. Not two. Not "just one more." ONE.
- Every session ends with: lb close, lb sync, git push — in that order.
- The next agent will continue where you left off.
- The task graph is a living document. Create, restructure, and close tasks as understanding grows.
- Need a tool or dependency? Edit `scripts/runner/Dockerfile` instead of installing at runtime — changes you commit are baked into the next run's image.
"#;

/// Load the agent prompt, checking for a custom override in `.mrmouth/prompt.md`.
pub fn load_prompt(repo_root: &std::path::Path) -> String {
    let custom_path = repo_root.join(".mrmouth").join("prompt.md");
    if custom_path.exists() {
        match std::fs::read_to_string(&custom_path) {
            Ok(content) => return content,
            Err(e) => {
                eprintln!("warning: failed to read {}: {e}", custom_path.display());
            }
        }
    }
    DEFAULT_PROMPT.to_string()
}
