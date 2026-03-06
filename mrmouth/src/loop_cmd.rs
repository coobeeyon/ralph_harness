use std::path::Path;
use std::process::Command;

use crate::config::Config;
use crate::run::{self, RunOptions};

pub struct LoopOptions {
    pub delay: u32,
    pub max_runs: u32,
    pub no_summary: bool,
    pub model: String,
}

pub fn execute(config: &Config, repo_root: &Path, opts: LoopOptions) -> Result<(), LoopError> {
    let max_label = if opts.max_runs == 0 {
        "unlimited".to_string()
    } else {
        opts.max_runs.to_string()
    };
    eprintln!("=== Agent loop ({}s between runs, max={}, Ctrl-C to stop) ===", opts.delay, max_label);

    let mut run_number: u32 = 0;

    loop {
        run_number += 1;

        if opts.max_runs > 0 && run_number > opts.max_runs {
            eprintln!();
            eprintln!("=== Loop complete: reached max runs ({}) ===", opts.max_runs);
            break;
        }

        eprintln!();
        eprintln!("--- Run {run_number} starting at {} ---", chrono::Local::now().format("%Y-%m-%d %H:%M:%S"));

        let run_opts = RunOptions {
            raw: false,
            model: opts.model.clone(),
            timeout: None,
            local: false,
        };

        let run_result = run::execute(config, repo_root, run_opts);
        if let Err(e) = &run_result {
            eprintln!("Run {run_number} failed: {e}");
        }

        // Sync litebrite so decider sees fresh task state
        sync_litebrite(repo_root);

        // Generate summary (best-effort, non-blocking)
        if !opts.no_summary {
            generate_summary(config, repo_root);
        }

        // Ask decider whether to continue
        match should_continue(repo_root, &config.loop_config.decider_model) {
            Ok(Decision::Continue(reason)) => {
                eprintln!("Decider: {reason}");
            }
            Ok(Decision::Stop(reason)) => {
                eprintln!("Decider: {reason}");
                eprintln!();
                eprintln!("=== Loop complete after {run_number} runs ===");
                break;
            }
            Err(e) => {
                eprintln!("Decider error (continuing anyway): {e}");
            }
        }

        if opts.delay > 0 {
            eprintln!();
            eprintln!("--- Waiting {}s until next run ---", opts.delay);
            std::thread::sleep(std::time::Duration::from_secs(opts.delay as u64));
        }
    }

    Ok(())
}

enum Decision {
    Continue(String),
    Stop(String),
}

fn should_continue(repo_root: &Path, decider_model: &str) -> Result<Decision, LoopError> {
    let schema = r#"{"type":"object","properties":{"continue":{"type":"boolean","description":"true if the loop should continue, false if done"},"reason":{"type":"string","description":"Brief explanation of the decision"}},"required":["continue","reason"]}"#;

    let prompt = "You are deciding whether an AI agent loop should continue or stop. \
        The project is specified in SPEC.md. You can see in the lites what has been done \
        and what remains to do, and you can compare this to the SPEC.md (which may have changed) \
        in order to make your decision. Use the return field \"continue\" to communicate your decision.";

    let output = Command::new("claude")
        .args([
            "-p",
            "--model", decider_model,
            "--allowedTools", "Read, Bash(git *)",
            "--output-format", "json",
            "--json-schema", schema,
        ])
        .arg(prompt)
        .current_dir(repo_root)
        .stderr(std::process::Stdio::inherit())
        .output()
        .map_err(|e| LoopError::Decider(format!("failed to run claude CLI: {e}")))?;

    if !output.status.success() {
        return Err(LoopError::Decider(format!(
            "claude CLI exited with code {}",
            output.status.code().unwrap_or(-1)
        )));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Parse the JSON output to extract structured_output
    let parsed: serde_json::Value = serde_json::from_str(stdout.trim())
        .map_err(|e| LoopError::Decider(format!("failed to parse decider output: {e}")))?;

    let structured = &parsed["structured_output"];
    let should_continue = structured["continue"].as_bool().unwrap_or(false);
    let reason = structured["reason"].as_str().unwrap_or("no reason given").to_string();

    if should_continue {
        Ok(Decision::Continue(reason))
    } else {
        Ok(Decision::Stop(reason))
    }
}

fn generate_summary(config: &Config, repo_root: &Path) {
    let log_dir = repo_root.join(&config.log_dir);
    let latest = log_dir.join("latest.jsonl");

    if !latest.exists() {
        return;
    }

    // Resolve the symlink to get the real log filename
    let log_file = match std::fs::read_link(&latest) {
        Ok(target) => log_dir.join(target),
        Err(_) => latest,
    };

    let log_name = log_file
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".into());

    let summary_dir = log_dir.join("summaries");
    let _ = std::fs::create_dir_all(&summary_dir);
    let summary_file = summary_dir.join(format!("{log_name}.md"));

    let prompt = format!(
        "Read the log file at {}. Write a concise markdown summary to {} covering:\n\
        - What tasks were worked on\n\
        - What was accomplished (files created/modified, commits)\n\
        - Whether the run succeeded or failed (and why)\n\
        - Any errors or notable events\n\
        \n\
        Also print the summary to stdout.",
        log_file.display(),
        summary_file.display()
    );

    eprintln!("Generating summary...");
    let result = Command::new("claude")
        .args([
            "-p",
            "--model", &config.loop_config.summary_model,
            "--dangerously-skip-permissions",
        ])
        .arg(&prompt)
        .current_dir(repo_root)
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit())
        .status();

    match result {
        Ok(s) if s.success() => eprintln!("Summary saved: {}", summary_file.display()),
        Ok(s) => eprintln!("Summary generation failed (exit code {})", s.code().unwrap_or(-1)),
        Err(e) => eprintln!("Summary generation failed: {e}"),
    }
}

fn sync_litebrite(repo_root: &Path) {
    if Command::new("which")
        .arg("lb")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map_or(false, |s| s.success())
    {
        let _ = Command::new("lb")
            .arg("sync")
            .current_dir(repo_root)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
    }
}

#[derive(Debug)]
pub enum LoopError {
    Decider(String),
}

impl std::fmt::Display for LoopError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Decider(msg) => write!(f, "decider error: {msg}"),
        }
    }
}

impl std::error::Error for LoopError {}
