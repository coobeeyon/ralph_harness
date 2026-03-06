mod config;
mod docker;
mod prompt;
mod run;
pub mod stream_fmt;

use clap::{Parser, Subcommand};
use config::Config;

#[derive(Parser)]
#[command(name = "mrmouth", version, about = "Run Claude Code as an autonomous coding agent in Docker containers")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run one agent session
    Run {
        /// Output raw JSONL instead of formatted stream
        #[arg(long)]
        raw: bool,

        /// Override the Claude model (default: from config or opus)
        #[arg(long)]
        model: Option<String>,

        /// Kill container after N minutes
        #[arg(long)]
        timeout: Option<u32>,

        /// Bind-mount current directory instead of cloning
        #[arg(long)]
        local: bool,
    },

    /// Run the agent repeatedly until work is done
    Loop {
        /// Wait between runs in seconds
        #[arg(long, default_value_t = 0)]
        delay: u32,

        /// Stop after N runs regardless of decider
        #[arg(long)]
        max_runs: Option<u32>,

        /// Skip AI summary generation
        #[arg(long)]
        no_summary: bool,
    },

    /// Work through a litebrite epic's tasks sequentially
    Epic {
        /// The litebrite epic ID
        epic_id: String,

        /// Per-task timeout in minutes
        #[arg(long, default_value_t = 15)]
        timeout: u32,

        /// Consecutive failures before aborting
        #[arg(long, default_value_t = 3)]
        max_failures: u32,
    },

    /// Scaffold .mrmouth/ config in the current repo
    Init,

    /// Generate an AI summary of a run log
    Summary {
        /// Path to log file (default: logs/latest.jsonl)
        log_file: Option<String>,
    },
}

fn main() {
    let cli = Cli::parse();

    // Init doesn't need config (it creates it)
    if matches!(cli.command, Commands::Init) {
        eprintln!("mrmouth init: not implemented yet");
        return;
    }

    let repo_root = match Config::find_repo_root() {
        Ok(root) => root,
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    };

    let config = match Config::load(&repo_root) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    };

    match cli.command {
        Commands::Run { raw, model, timeout, local } => {
            let opts = run::RunOptions {
                raw,
                model: model.unwrap_or_else(|| config.model.clone()),
                timeout,
                local,
            };
            if let Err(e) = run::execute(&config, &repo_root, opts) {
                eprintln!("error: {e}");
                std::process::exit(1);
            }
        }
        Commands::Loop { delay, max_runs, no_summary } => {
            let delay = if delay > 0 { delay } else { config.loop_config.delay };
            let max_runs = max_runs.unwrap_or(config.loop_config.max_runs);
            eprintln!("mrmouth loop: not implemented yet");
            eprintln!("  delay={delay}, max_runs={max_runs}, no_summary={no_summary}");
        }
        Commands::Epic { epic_id, timeout, max_failures } => {
            eprintln!("mrmouth epic: not implemented yet");
            eprintln!("  epic_id={epic_id}, timeout={timeout}, max_failures={max_failures}");
        }
        Commands::Init => unreachable!(),
        Commands::Summary { log_file } => {
            let log_file = log_file.unwrap_or_else(|| {
                format!("{}/latest.jsonl", config.log_dir)
            });
            eprintln!("mrmouth summary: not implemented yet");
            eprintln!("  log_file={log_file}");
        }
    }
}
