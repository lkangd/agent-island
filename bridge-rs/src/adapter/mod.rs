mod claude;
mod codex;
mod gemini;
mod unknown;

use std::process;

use regex::Regex;
use serde_json::Value;

use crate::protocol::{AgentSource, BridgeProfile, HookPayload};

pub use claude::ClaudeAdapter;
pub use codex::CodexAdapter;
pub use gemini::GeminiAdapter;
pub use unknown::UnknownAdapter;

pub struct BridgeCapabilities {
    pub permission: PermissionCapability,
}

pub struct PermissionCapability {
    pub approval_request_events: &'static [&'static str],
}

pub trait SourceAdapter {
    fn capabilities(&self) -> BridgeCapabilities;
    fn normalize_input(&self, input: &Value) -> NormalizedInput;
    fn should_emit_event(&self, normalized: &NormalizedInput) -> bool;
    fn status_for_event(&self, normalized: &NormalizedInput) -> String;
    fn process_info(&self, input: &Value) -> ProcessInfo;
    fn resolve_status(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> String {
        let base_status = self.status_for_event(normalized);
        if self
            .capabilities()
            .permission
            .approval_request_events
            .contains(&normalized.hook_event.as_str())
            && self.requires_approval(profile, normalized)
        {
            return "waiting_for_approval".to_string();
        }
        base_status
    }
    fn requires_approval(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> bool {
        default_requires_approval(profile, normalized)
    }
    fn permission_response(
        &self,
        decision: Option<&str>,
        reason: Option<&str>,
        hook_event: &str,
    ) -> Option<Value>;
}

#[derive(Debug, Clone)]
pub struct NormalizedInput {
    pub hook_event: String,
    pub notification_type: Option<String>,
    pub tool_name: Option<String>,
    pub tool_input: Value,
    pub tool_use_id: Option<String>,
    pub session_id: Option<String>,
    pub cwd: Option<String>,
    pub transcript_path: Option<String>,
    pub message: Option<String>,
    pub command_text: Option<String>,
    pub escalation_requested: bool,
}

pub struct NormalizedInputOptions<'a> {
    pub tool_name_paths: &'a [&'a [&'a str]],
    pub tool_use_id_paths: &'a [&'a [&'a str]],
    pub session_id_keys: &'a [&'a str],
    pub cwd_keys: &'a [&'a str],
    pub transcript_path_keys: &'a [&'a str],
    pub notification_type_keys: &'a [&'a str],
    pub message_keys: &'a [&'a str],
}

impl Default for NormalizedInputOptions<'_> {
    fn default() -> Self {
        Self {
            tool_name_paths: &[&["tool_name"], &["toolName"], &["tool"], &["payload", "name"], &["name"]],
            tool_use_id_paths: &[
                &["tool_use_id"],
                &["toolUseId"],
                &["request_id"],
                &["requestId"],
                &["call_id"],
                &["callId"],
                &["payload", "call_id"],
                &["payload", "callId"],
            ],
            session_id_keys: &["session_id", "sessionId"],
            cwd_keys: &["cwd", "working_directory"],
            transcript_path_keys: &["transcript_path", "transcriptPath"],
            notification_type_keys: &["notification_type", "notificationType"],
            message_keys: &[
                "prompt",
                "user_prompt",
                "userPrompt",
                "text",
                "message",
                "last_assistant_message",
                "lastAssistantMessage",
                "assistant_message",
            ],
        }
    }
}

pub fn normalize_event_name(value: &str) -> String {
    match value {
        "BeforeTool" => "PreToolUse".to_string(),
        "AfterTool" => "PostToolUse".to_string(),
        "SessionStart" | "session_start" => "SessionStart".to_string(),
        "SessionEnd" | "session_end" => "SessionEnd".to_string(),
        "Notification" | "notification" => "Notification".to_string(),
        "Stop" | "stop" => "Stop".to_string(),
        "PreToolUse" | "PostToolUse" => value.to_string(),
        _ => value.to_string(),
    }
}

pub fn default_requires_approval(profile: &BridgeProfile, normalized: &NormalizedInput) -> bool {
    if normalized.escalation_requested {
        return true;
    }

    if matches_command_patterns(profile, normalized.command_text.as_deref()) {
        return true;
    }

    matches_approval_tool(profile, normalized.tool_name.as_deref())
}

pub fn matches_approval_tool(profile: &BridgeProfile, tool_name: Option<&str>) -> bool {
    tool_name
        .map(|name| profile.approval_tools.iter().any(|tool| tool == name))
        .unwrap_or(false)
}

pub fn matches_command_patterns(profile: &BridgeProfile, command_text: Option<&str>) -> bool {
    command_text
        .map(|command| {
            profile
                .approval_command_patterns
                .iter()
                .any(|pattern| Regex::new(pattern).map(|regex| regex.is_match(command)).unwrap_or(false))
        })
        .unwrap_or(false)
}

pub fn adapter_for(source: AgentSource) -> Box<dyn SourceAdapter + Send + Sync> {
    match source {
        AgentSource::Claude => Box::new(ClaudeAdapter),
        AgentSource::Codex => Box::new(CodexAdapter),
        AgentSource::Gemini => Box::new(GeminiAdapter),
        AgentSource::Unknown => Box::new(UnknownAdapter),
    }
}

pub fn default_status_for_event(hook_event: &str, notification_type: Option<&str>) -> String {
    match hook_event {
        "Notification" => {
            if notification_type == Some("idle_prompt") {
                "waiting_for_input".to_string()
            } else {
                "notification".to_string()
            }
        }
        "SessionStart" | "Stop" | "SubagentStop" => "waiting_for_input".to_string(),
        "SessionEnd" => "ended".to_string(),
        _ => "processing".to_string(),
    }
}

pub fn build_payload(
    source: AgentSource,
    session_id: String,
    cwd: String,
    hook_event: String,
    status: String,
    transcript_path: Option<String>,
    pid: Option<i64>,
    tty: Option<String>,
    tool: Option<String>,
    tool_input: Value,
    tool_use_id: Option<String>,
    notification_type: Option<String>,
    message: Option<String>,
) -> HookPayload {
    HookPayload {
        session_id,
        cwd,
        agent_type: source.as_str().to_string(),
        transcript_path,
        event: hook_event,
        status,
        pid,
        tty,
        tool,
        tool_input,
        tool_use_id,
        notification_type,
        message,
    }
}

pub struct ProcessInfo {
    pub pid: Option<i64>,
    pub tty: Option<String>,
}

pub fn normalize_input_with_options(input: &Value, options: &NormalizedInputOptions<'_>) -> NormalizedInput {
    let tool_input = resolve_tool_input(input);
    let hook_event = normalize_event_name(&get_first_string(
        input,
        &["hook_event_name", "hookEventName", "event_name", "eventName", "event", "type"],
    ));
    let notification_type = get_first_string_opt(input, options.notification_type_keys);
    let tool_name = value_string_opt(input, options.tool_name_paths);
    let command_text = value_string_opt(&tool_input, &[&["command"], &["cmd"]]);
    let escalation_requested = value_string_opt(
        &tool_input,
        &[&["sandbox_permissions"], &["sandboxPermissions"]],
    )
    .map(|value| value == "require_escalated")
    .unwrap_or(false);

    NormalizedInput {
        hook_event,
        notification_type,
        tool_name,
        tool_input,
        tool_use_id: value_string_opt(input, options.tool_use_id_paths),
        session_id: get_first_string_opt(input, options.session_id_keys),
        cwd: get_first_string_opt(input, options.cwd_keys),
        transcript_path: get_first_string_opt(input, options.transcript_path_keys),
        message: get_first_string_opt(input, options.message_keys),
        command_text,
        escalation_requested,
    }
}

pub fn default_process_info(input: &Value) -> ProcessInfo {
    ProcessInfo {
        pid: first_i64(input, &["pid"]).or_else(|| Some(process::id() as i64)),
        tty: first_string(input, &["tty"]),
    }
}

pub fn first_string(input: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| input.get(*key).and_then(Value::as_str))
        .map(str::to_owned)
        .filter(|value| !value.is_empty())
}

fn first_i64(input: &Value, keys: &[&str]) -> Option<i64> {
    keys.iter().find_map(|key| input.get(*key).and_then(Value::as_i64))
}

pub fn get_first_string(input: &Value, keys: &[&str]) -> String {
    get_first_string_opt(input, keys).unwrap_or_default()
}

pub fn get_first_string_opt(input: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| input.get(*key).and_then(Value::as_str))
        .map(str::to_owned)
        .filter(|value| !value.is_empty())
}

pub fn get_first_value(input: &Value, keys: &[&str]) -> Option<Value> {
    keys.iter().find_map(|key| input.get(*key).cloned())
}

pub fn value_string_opt(input: &Value, paths: &[&[&str]]) -> Option<String> {
    paths.iter().find_map(|path| {
        let mut current = input;
        for segment in *path {
            current = current.get(*segment)?;
        }
        current.as_str().map(str::to_owned)
    })
}

pub fn resolve_tool_input(input: &Value) -> Value {
    if let Some(value) = get_first_value(input, &["tool_input", "toolInput"]) {
        if let Some(resolved) = expand_arguments_object(&value) {
            return resolved;
        }
        return value;
    }

    if let Some(value) = get_first_value(input, &["arguments"]) {
        if let Some(parsed) = parse_json_string_value(&value) {
            return parsed;
        }
    }

    if let Some(value) = get_first_value(input, &["payload"]) {
        if let Some(resolved) = expand_arguments_object(&value) {
            return resolved;
        }
    }

    Value::Object(Default::default())
}

fn expand_arguments_object(value: &Value) -> Option<Value> {
    if let Some(parsed) = parse_json_string_value(value.get("arguments")?) {
        return Some(parsed);
    }
    Some(value.clone())
}

fn parse_json_string_value(value: &Value) -> Option<Value> {
    let raw = value.as_str()?;
    serde_json::from_str(raw).ok()
}
