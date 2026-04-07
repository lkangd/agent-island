mod adapter;
mod dispatcher;
mod protocol;
mod socket_client;

use std::fs;
use std::io::{self, IsTerminal, Read};
use std::path::PathBuf;
use std::process;

use anyhow::{Context, Result};
use clap::Parser;
use dispatcher::dispatch;
use protocol::{AgentSource, BridgeProfile};
use serde_json::Value;

#[derive(Debug, Parser)]
#[command(name = "agent-island-bridge")]
#[command(about = "Unified multi-agent hook bridge for Agent Island")]
struct Cli {
    #[arg(long, alias = "agent", default_value = "unknown")]
    source: String,

    #[arg(long, default_value = "/tmp/agent-island.sock")]
    socket: String,

    #[arg(long)]
    profile: Option<PathBuf>,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        process::exit(1);
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let source = AgentSource::from_str(&cli.source);

    let stdin_json = read_stdin_json()?;
    if stdin_json.trim().is_empty() {
        return Ok(());
    }

    let input: Value = serde_json::from_str(&stdin_json).context("invalid stdin json")?;
    let profile = load_profile(cli.profile, source)?;
    let adapter = adapter::adapter_for(source);
    let dispatch_result = dispatch(source, &input, &profile);
    let Some(payload) = dispatch_result.payload else {
        return Ok(());
    };
    let hook_event = dispatch_result.hook_event.unwrap_or_default();
    let status = dispatch_result.status.unwrap_or_else(|| "processing".to_string());

    if status == "waiting_for_approval" {
        let decision = socket_client::send_sync(&cli.socket, &payload)?;
        if let Some(response) = adapter.permission_response(
            decision.decision.as_deref(),
            decision.reason.as_deref(),
            &hook_event,
        ) {
            println!("{}", serde_json::to_string(&response)?);
        }
    } else {
        socket_client::send_async(&cli.socket, &payload)?;
    }

    Ok(())
}

fn read_stdin_json() -> Result<String> {
    if io::stdin().is_terminal() {
        return Ok(String::new());
    }

    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer)?;
    Ok(buffer)
}

fn load_profile(path: Option<PathBuf>, source: AgentSource) -> Result<BridgeProfile> {
    let path = path.unwrap_or_else(|| {
        PathBuf::from(format!(
            "{}/.agent-island/bridge-profiles/{}.json",
            std::env::var("HOME").unwrap_or_default(),
            source.as_str()
        ))
    });

    if !path.exists() {
        return Ok(BridgeProfile {
            response_mode: None,
            approval_tools: vec![],
            approval_command_patterns: vec![],
        });
    }

    let contents = fs::read_to_string(&path)
        .with_context(|| format!("failed to read profile from {}", path.display()))?;
    let value: Value = serde_json::from_str(&contents)?;
    Ok(BridgeProfile::from_json(&value))
}
