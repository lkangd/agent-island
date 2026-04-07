mod adapter;
mod dispatcher;
mod protocol;
mod socket_client;

use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::fs::OpenOptions;
use std::hash::{Hash, Hasher};
use std::io::{self, IsTerminal, Read};
use std::io::Write;
use std::path::PathBuf;
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

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
    let pid = process::id();
    log_process_event("start", pid, None);

    if let Err(error) = run() {
        let error_text = format!("{error:#}");
        log_process_event("error", pid, Some(&error_text));
        eprintln!("{error_text}");
        process::exit(1);
    }

    log_process_event("exit", pid, Some("ok"));
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
    log_bridge_event(
        source.as_str(),
        "received",
        input.get("hook_event_name").and_then(Value::as_str),
        input.get("tool_use_id").and_then(Value::as_str),
        input.get("turn_id").and_then(Value::as_str),
        Some(&stdin_json),
        None,
    );
    let Some(payload) = dispatch_result.payload else {
        return Ok(());
    };
    let hook_event = dispatch_result.hook_event.unwrap_or_default();
    let status = dispatch_result
        .status
        .unwrap_or_else(|| adapter::HOOK_STATUS_PROCESSING.to_string());

    if let Some(permission_decision) = dispatch_result.permission_decision.as_deref() {
        socket_client::send_async(&cli.socket, &payload)?;

        if let Some(response) = adapter.map_permission_response(
            Some(permission_decision),
            Some("Auto-approved from Agent Island"),
            &hook_event
        ) {
            let response_text = serde_json::to_string(&response.body)?;
            println!("{}", response_text);
            log_permission_response(
                source.as_str(),
                &hook_event,
                permission_decision,
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                &response_text,
            );

            if std::env::var("RUST_LOG_PERMISSION_RESPONSE").is_ok() {
                eprintln!("permission_response_json={}", response_text);
            }
        } else {
            log_permission_response(
                source.as_str(),
                &hook_event,
                permission_decision,
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                "<no-output>",
            );
        }
    } else if status == adapter::HOOK_STATUS_WAITING_FOR_APPROVAL {
        let decision = socket_client::send_sync(&cli.socket, &payload)?;
        if let Some(response) = adapter.map_permission_response(
            decision.decision.as_deref(),
            decision.reason.as_deref(),
            &hook_event
        ) {
            let response_text = serde_json::to_string(&response.body)?;
            println!("{}", response_text);
            log_permission_response(
                source.as_str(),
                &hook_event,
                decision.decision.as_deref().unwrap_or("none"),
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                &response_text,
            );

            if std::env::var("RUST_LOG_PERMISSION_RESPONSE").is_ok() {
                eprintln!("permission_response_json={}", response_text);
            }
        } else {
            log_permission_response(
                source.as_str(),
                &hook_event,
                decision.decision.as_deref().unwrap_or("none"),
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                "<no-output>",
            );
        }
    } else {
        socket_client::send_async(&cli.socket, &payload)?;
    }

    Ok(())
}

fn log_permission_response(
    source: &str,
    hook_event: &str,
    decision: &str,
    tool_use_id: Option<&str>,
    turn_id: Option<&str>,
    response_text: &str,
) {
    log_bridge_event(
        source,
        "responded",
        Some(hook_event),
        tool_use_id,
        turn_id,
        None,
        Some(&format!("decision={} response={}", decision, response_text)),
    );
}

fn log_bridge_event(
    source: &str,
    stage: &str,
    event: Option<&str>,
    tool_use_id: Option<&str>,
    turn_id: Option<&str>,
    stdin_body: Option<&str>,
    extra: Option<&str>,
) {
    let log_path = bridge_log_path();
    let mut file = match OpenOptions::new().create(true).append(true).open(&log_path) {
        Ok(file) => file,
        Err(_) => return,
    };

    let ts = timestamp_millis();
    let stdin_sha = stdin_body.map(short_hash);
    let extra_sha = extra.map(short_hash);

    let _ = writeln!(
        file,
        "ts={} source={} stage={} event={} tool_use_id={} turn_id={} stdin_sha={} extra_sha={} body={} extra={}",
        ts,
        source,
        stage,
        event.unwrap_or(""),
        tool_use_id.unwrap_or(""),
        turn_id.unwrap_or(""),
        stdin_sha.unwrap_or_default(),
        extra_sha.unwrap_or_default(),
        stdin_body.unwrap_or(""),
        extra.unwrap_or(""),
    );
}

fn log_process_event(stage: &str, pid: u32, extra: Option<&str>) {
    let log_path = bridge_log_path();
    let mut file = match OpenOptions::new().create(true).append(true).open(&log_path) {
        Ok(file) => file,
        Err(_) => return,
    };

    let ts = timestamp_millis();
    let extra_sha = extra.map(short_hash);

    let _ = writeln!(
        file,
        "ts={} source=bridge stage={} pid={} extra_sha={} extra={}",
        ts,
        stage,
        pid,
        extra_sha.unwrap_or_default(),
        extra.unwrap_or(""),
    );
}

fn timestamp_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default()
}

fn short_hash(value: &str) -> String {
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn bridge_log_path() -> String {
    if let Ok(path) = std::env::var("AGENT_ISLAND_BRIDGE_LOG") {
        return path;
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let directory = format!("{home}/.agent-island");
    let _ = fs::create_dir_all(&directory);
    format!("{directory}/bridge-debug.log")
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
            auto_approve_tools: vec![],
            auto_approve_command_patterns: vec![],
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
        let response = adapter.map_permission_response(Some("allow"), Some("Approved"), "PreToolUse");
        assert!(response.is_none());
    }

    #[test]
    fn codex_deny_response_matches_block_shape() {
        let adapter = adapter_for(AgentSource::Codex);
        let response = adapter
            .map_permission_response(Some("deny"), Some("Denied"), "PreToolUse")
            .expect("expected response");
        let body = response.body;

        assert_eq!(
            body["hookSpecificOutput"]["hookEventName"].as_str(),
            Some("PreToolUse")
        );
        assert_eq!(
            body["hookSpecificOutput"]["permissionDecision"].as_str(),
            Some("deny")
        );
        assert_eq!(
            body["hookSpecificOutput"]["permissionDecisionReason"].as_str(),
            Some("Denied")
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
