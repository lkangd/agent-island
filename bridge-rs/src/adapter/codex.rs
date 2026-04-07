use serde_json::{json, Value};

use crate::protocol::BridgeProfile;

use super::{
    default_extra_payload, default_process_info, get_first_string_opt, matches_approval_tool,
    matches_command_patterns, normalize_event_name, normalize_input_with_options,
    BridgeCapabilities, NormalizedInput, NormalizedInputOptions, PermissionCapability,
    ProcessInfo, SourceAdapter,
    HOOK_EVENT_POST_TOOL_USE, HOOK_EVENT_PRE_TOOL_USE, HOOK_EVENT_SESSION_END,
    HOOK_EVENT_SESSION_START, HOOK_EVENT_STOP, HOOK_EVENT_SUBAGENT_STOP,
    HOOK_EVENT_USER_PROMPT_SUBMIT, HOOK_STATUS_ENDED, HOOK_STATUS_PROCESSING,
    HOOK_STATUS_RUNNING_TOOL, HOOK_STATUS_WAITING_FOR_APPROVAL,
    HOOK_STATUS_WAITING_FOR_INPUT, INTERNAL_EVENT_PERMISSION_REQUESTED,
    INTERNAL_EVENT_SESSION_ENDED, INTERNAL_EVENT_SESSION_STARTED,
    INTERNAL_EVENT_STOPPED, INTERNAL_EVENT_SUBAGENT_STOPPED, INTERNAL_EVENT_TOOL_DID_RUN,
    INTERNAL_EVENT_TOOL_WILL_RUN, INTERNAL_EVENT_UNKNOWN,
    INTERNAL_EVENT_USER_PROMPT_SUBMITTED, PERMISSION_MODE_NATIVE_APP,
};

pub struct CodexAdapter;

const CODEX_TOOL_NAME_PATHS: &[&[&str]] = &[
    &["tool_name"],
    &["toolName"],
    &["tool"],
    &["payload", "name"],
    &["payload", "command"],
    &["params", "name"],
    &["params", "tool"],
    &["params", "tool_name"],
    &["params", "toolName"],
    &["params", "command"],
    &["name"],
];

const CODEX_TOOL_USE_ID_PATHS: &[&[&str]] = &[
    &["call_id"],
    &["callId"],
    &["tool_use_id"],
    &["toolUseId"],
    &["request_id"],
    &["requestId"],
    &["payload", "call_id"],
    &["payload", "callId"],
    &["params", "tool_use_id"],
    &["params", "toolUseId"],
    &["params", "call_id"],
    &["params", "callId"],
    &["params", "itemId"],
    &["params", "item_id"],
];

const CODEX_APPROVAL_EVENTS: &[&str] = &[HOOK_EVENT_PRE_TOOL_USE];

const CODEX_OPTIONS: NormalizedInputOptions<'static> = NormalizedInputOptions {
    tool_name_paths: CODEX_TOOL_NAME_PATHS,
    tool_use_id_paths: CODEX_TOOL_USE_ID_PATHS,
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
        "assistant_message",
        "last_assistant_message",
        "lastAssistantMessage",
    ],
};

impl SourceAdapter for CodexAdapter {
    fn capabilities(&self) -> BridgeCapabilities {
        BridgeCapabilities {
            permission: PermissionCapability {
                approval_request_events: CODEX_APPROVAL_EVENTS,
            },
        }
    }

    fn normalize_input(&self, input: &Value) -> NormalizedInput {
        let mut normalized = normalize_input_with_options(input, &CODEX_OPTIONS);
        if let Some(method) = get_first_string_opt(input, &["method"]) {
            let normalized_method = normalize_event_name(&method);
            if is_approval_request_event(&normalized_method) {
                normalized.hook_event = normalized_method;
            }
        }
        normalized
    }

    fn should_emit_event(&self, _normalized: &NormalizedInput) -> bool {
        true
    }

    fn status_for_event(&self, normalized: &NormalizedInput) -> String {
        match normalized.hook_event.as_str() {
            HOOK_EVENT_SESSION_START => HOOK_STATUS_WAITING_FOR_INPUT.to_string(),
            HOOK_EVENT_SESSION_END => HOOK_STATUS_ENDED.to_string(),
            HOOK_EVENT_STOP | HOOK_EVENT_SUBAGENT_STOP => HOOK_STATUS_WAITING_FOR_INPUT.to_string(),
            HOOK_EVENT_PRE_TOOL_USE => HOOK_STATUS_RUNNING_TOOL.to_string(),
            HOOK_EVENT_POST_TOOL_USE | HOOK_EVENT_USER_PROMPT_SUBMIT => {
                HOOK_STATUS_PROCESSING.to_string()
            }
            _ => HOOK_STATUS_PROCESSING.to_string(),
        }
    }

    fn process_info(&self, input: &Value) -> ProcessInfo {
        default_process_info(input)
    }

    fn requires_approval(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> bool {
        if normalized.hook_event != HOOK_EVENT_PRE_TOOL_USE {
            return false;
        }

        if normalized.escalation_requested {
            return true;
        }

        if matches_command_patterns(profile, normalized.command_text.as_deref()) {
            return true;
        }

        matches_approval_tool(profile, normalized.tool_name.as_deref())
    }

    fn internal_event(
        &self,
        _profile: &BridgeProfile,
        normalized: &NormalizedInput,
        status: &str,
    ) -> String {
        if status == HOOK_STATUS_WAITING_FOR_APPROVAL {
            return INTERNAL_EVENT_PERMISSION_REQUESTED.to_string();
        }

        match normalized.hook_event.as_str() {
            HOOK_EVENT_SESSION_START => INTERNAL_EVENT_SESSION_STARTED.to_string(),
            HOOK_EVENT_SESSION_END => INTERNAL_EVENT_SESSION_ENDED.to_string(),
            HOOK_EVENT_STOP => INTERNAL_EVENT_STOPPED.to_string(),
            HOOK_EVENT_SUBAGENT_STOP => INTERNAL_EVENT_SUBAGENT_STOPPED.to_string(),
            HOOK_EVENT_PRE_TOOL_USE => INTERNAL_EVENT_TOOL_WILL_RUN.to_string(),
            HOOK_EVENT_POST_TOOL_USE => INTERNAL_EVENT_TOOL_DID_RUN.to_string(),
            HOOK_EVENT_USER_PROMPT_SUBMIT => INTERNAL_EVENT_USER_PROMPT_SUBMITTED.to_string(),
            _ => INTERNAL_EVENT_UNKNOWN.to_string(),
        }
    }

    fn permission_mode(
        &self,
        _profile: &BridgeProfile,
        normalized: &NormalizedInput,
        status: &str,
    ) -> Option<String> {
        if status == HOOK_STATUS_WAITING_FOR_APPROVAL
            || normalized.hook_event == HOOK_EVENT_PRE_TOOL_USE
        {
            return Some(PERMISSION_MODE_NATIVE_APP.to_string());
        }

        None
    }

    fn extra_payload(&self, _profile: &BridgeProfile, normalized: &NormalizedInput) -> Value {
        let mut extra = default_extra_payload(normalized);
        if let Value::Object(ref mut object) = extra {
            object.insert(
                "officialPermissionEvent".to_string(),
                Value::String(HOOK_EVENT_PRE_TOOL_USE.to_string()),
            );
            object.insert("toolMatcher".to_string(), Value::String("Bash".to_string()));
        }
        extra
    }

    fn permission_response(
        &self,
        decision: Option<&str>,
        reason: Option<&str>,
        hook_event: &str,
    ) -> Option<Value> {
        let mapped = map_codex_decision(decision)?;
        if std::env::var("RUST_LOG_PERMISSION_RESPONSE").is_ok() {
            eprintln!(
                "codex permission map: raw_decision={:?} mapped={:?} hook_event={}",
                decision, mapped, hook_event
            );
        }
        let permission_reason = match mapped {
            "deny" => reason.or(Some("Denied from Agent Island")),
            "ask" => reason.or(Some("Need user confirmation")),
            _ => reason.or(Some("Approved from Agent Island")),
        };

        Some(json!({
            "decision": mapped,
            "reason": reason.unwrap_or(""),
            "hookSpecificOutput": {
                "hookEventName": HOOK_EVENT_PRE_TOOL_USE,
                "permissionDecision": mapped,
                "permissionDecisionReason": permission_reason.unwrap_or(""),
            },
        }))
    }
}

fn map_codex_decision(decision: Option<&str>) -> Option<&'static str> {
    let decision = decision?;

    match decision {
        "allow" | "accept" | "acceptForSession" => Some("allow"),
        "deny" | "decline" | "cancel" => Some("deny"),
        "ask" => Some("ask"),
        _ => None,
    }
}

fn is_approval_request_event(event: &str) -> bool {
    CODEX_APPROVAL_EVENTS.contains(&event)
}
