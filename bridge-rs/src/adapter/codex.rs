use serde_json::{json, Value};

use crate::protocol::BridgeProfile;

use super::{
    default_process_info,
    matches_approval_tool,
    matches_command_patterns,
    normalize_input_with_options,
    BridgeCapabilities,
    NormalizedInput,
    NormalizedInputOptions,
    PermissionCapability,
    ProcessInfo,
    SourceAdapter,
};

pub struct CodexAdapter;

const CODEX_TOOL_NAME_PATHS: &[&[&str]] = &[
    &["tool_name"],
    &["toolName"],
    &["tool"],
    &["payload", "name"],
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
];

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
                approval_request_events: &["PreToolUse", "BeforeTool"],
            },
        }
    }

    fn normalize_input(&self, input: &Value) -> NormalizedInput {
        normalize_input_with_options(input, &CODEX_OPTIONS)
    }

    fn should_emit_event(&self, _normalized: &NormalizedInput) -> bool {
        true
    }

    fn status_for_event(&self, normalized: &NormalizedInput) -> String {
        match normalized.hook_event.as_str() {
            "SessionStart" => "waiting_for_input".to_string(),
            "SessionEnd" => "ended".to_string(),
            "Stop" | "SubagentStop" => "waiting_for_input".to_string(),
            "PreToolUse" => "running_tool".to_string(),
            "PostToolUse" | "UserPromptSubmit" => "processing".to_string(),
            _ => "processing".to_string(),
        }
    }

    fn process_info(&self, input: &Value) -> ProcessInfo {
        default_process_info(input)
    }

    fn resolve_status(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> String {
        if normalized.hook_event == "PreToolUse" && self.requires_approval(profile, normalized) {
            return "terminal_approval_required".to_string();
        }

        self.status_for_event(normalized)
    }

    fn requires_approval(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> bool {
        if normalized.hook_event != "PreToolUse" {
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

    fn permission_response(
        &self,
        decision: Option<&str>,
        reason: Option<&str>,
        _hook_event: &str,
    ) -> Option<Value> {
        if decision == Some("deny") {
            Some(json!({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason.unwrap_or("Denied from Agent Island")
                }
            }))
        } else {
            None
        }
    }
}
