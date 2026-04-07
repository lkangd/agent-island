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
    let status = dispatch_result
        .status
        .unwrap_or_else(|| adapter::HOOK_STATUS_PROCESSING.to_string());

    if status == adapter::HOOK_STATUS_WAITING_FOR_APPROVAL {
        let decision = socket_client::send_sync(&cli.socket, &payload)?;
        if let Some(response) = adapter.map_permission_response(
            decision.decision.as_deref(),
            decision.reason.as_deref(),
            &hook_event,
        ) {
            let response_text = serde_json::to_string(&response.body)?;
            println!("{}", response_text);

            if std::env::var("RUST_LOG_PERMISSION_RESPONSE").is_ok() {
                eprintln!("permission_response_json={}", response_text);
            }
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

#[cfg(test)]
mod tests {
    use crate::adapter::adapter_for;
    use crate::protocol::AgentSource;

    #[test]
    fn claude_permission_allow_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Claude);
        let response = adapter
            .map_permission_response(Some("allow"), None, "PermissionRequest")
            .expect("expected response");
        let body = response.body;

        assert_eq!(
            body["hookSpecificOutput"]["hookEventName"].as_str(),
            Some("PermissionRequest")
        );
        assert_eq!(
            body["hookSpecificOutput"]["decision"]["behavior"].as_str(),
            Some("allow")
        );
    }

    #[test]
    fn claude_permission_deny_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Claude);
        let response = adapter
            .map_permission_response(Some("deny"), Some("Nope"), "PermissionRequest")
            .expect("expected response");
        let body = response.body;

        assert_eq!(
            body["hookSpecificOutput"]["hookEventName"].as_str(),
            Some("PermissionRequest")
        );
        assert_eq!(
            body["hookSpecificOutput"]["decision"]["behavior"].as_str(),
            Some("deny")
        );
        assert_eq!(
            body["hookSpecificOutput"]["decision"]["message"].as_str(),
            Some("Nope")
        );
    }

    #[test]
    fn codex_permission_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Codex);
        let response = adapter
            .map_permission_response(Some("allow"), Some("Approved"), "PreToolUse")
            .expect("expected response");
        let body = response.body;

        assert_eq!(body["decision"].as_str(), Some("allow"));
        assert_eq!(
            body["hookSpecificOutput"]["hookEventName"].as_str(),
            Some("PreToolUse")
        );
        assert_eq!(
            body["hookSpecificOutput"]["permissionDecision"].as_str(),
            Some("allow")
        );
        assert_eq!(
            body["hookSpecificOutput"]["permissionDecisionReason"].as_str(),
            Some("Approved")
        );
    }

    #[test]
    fn gemini_deny_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Gemini);
        let response = adapter
            .map_permission_response(Some("deny"), Some("Denied"), "BeforeTool")
            .expect("expected response");
        let body = response.body;

        assert_eq!(body["decision"].as_str(), Some("deny"));
        assert_eq!(body["reason"].as_str(), Some("Denied"));
    }

    #[test]
    fn gemini_allow_has_no_response_body() {
        let adapter = adapter_for(AgentSource::Gemini);
        let response = adapter.map_permission_response(Some("allow"), None, "BeforeTool");
        assert!(response.is_none());
    }
}
