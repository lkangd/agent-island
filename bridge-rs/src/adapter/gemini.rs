use serde_json::{json, Value};

use super::{default_process_info, normalize_input_with_options, BridgeCapabilities, NormalizedInput, NormalizedInputOptions, PermissionCapability, ProcessInfo, SourceAdapter};

pub struct GeminiAdapter;

const GEMINI_OPTIONS: NormalizedInputOptions<'static> = NormalizedInputOptions {
    tool_name_paths: &[
        &["tool_name"],
        &["toolName"],
        &["tool"],
        &["payload", "tool_name"],
        &["payload", "toolName"],
        &["payload", "name"],
        &["name"],
    ],
    tool_use_id_paths: &[
        &["tool_use_id"],
        &["toolUseId"],
        &["request_id"],
        &["requestId"],
        &["call_id"],
        &["callId"],
        &["payload", "tool_use_id"],
        &["payload", "toolUseId"],
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
};

impl SourceAdapter for GeminiAdapter {
    fn capabilities(&self) -> BridgeCapabilities {
        BridgeCapabilities {
            permission: PermissionCapability {
                approval_request_events: &["PreToolUse", "BeforeTool"],
            },
        }
    }

    fn normalize_input(&self, input: &Value) -> NormalizedInput {
        normalize_input_with_options(input, &GEMINI_OPTIONS)
    }

    fn should_emit_event(&self, _normalized: &NormalizedInput) -> bool {
        true
    }

    fn status_for_event(&self, normalized: &NormalizedInput) -> String {
        match normalized.hook_event.as_str() {
            "SessionStart" => "waiting_for_input".to_string(),
            "SessionEnd" => "ended".to_string(),
            "Notification" => {
                if normalized.notification_type.as_deref() == Some("idle_prompt") {
                    "waiting_for_input".to_string()
                } else {
                    "notification".to_string()
                }
            }
            "Stop" | "SubagentStop" => "waiting_for_input".to_string(),
            "PreToolUse" => "running_tool".to_string(),
            "PostToolUse" | "UserPromptSubmit" => "processing".to_string(),
            _ => "processing".to_string(),
        }
    }

    fn process_info(&self, input: &Value) -> ProcessInfo {
        default_process_info(input)
    }

    fn permission_response(
        &self,
        decision: Option<&str>,
        reason: Option<&str>,
        _hook_event: &str,
    ) -> Option<Value> {
        if decision == Some("deny") {
            Some(json!({
                "decision": "deny",
                "reason": reason.unwrap_or("Denied from Agent Island")
            }))
        } else {
            None
        }
    }
}
