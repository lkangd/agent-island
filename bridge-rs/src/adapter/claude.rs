use std::ffi::CStr;
use std::process::Command;

use serde_json::{json, Value};

use super::{first_string, normalize_input_with_options, BridgeCapabilities, NormalizedInput, NormalizedInputOptions, PermissionCapability, ProcessInfo, SourceAdapter};

pub struct ClaudeAdapter;

const CLAUDE_OPTIONS: NormalizedInputOptions<'static> = NormalizedInputOptions {
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

impl SourceAdapter for ClaudeAdapter {
    fn capabilities(&self) -> BridgeCapabilities {
        BridgeCapabilities {
            permission: PermissionCapability {
                approval_request_events: &[],
            },
        }
    }

    fn normalize_input(&self, input: &Value) -> NormalizedInput {
        normalize_input_with_options(input, &CLAUDE_OPTIONS)
    }

    fn should_emit_event(&self, normalized: &NormalizedInput) -> bool {
        !(normalized.hook_event == "Notification" && normalized.notification_type.as_deref() == Some("permission_prompt"))
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
            "PreCompact" => "compacting".to_string(),
            "PermissionRequest" => "waiting_for_approval".to_string(),
            _ => "unknown".to_string(),
        }
    }

    fn process_info(&self, input: &Value) -> ProcessInfo {
        ProcessInfo {
            pid: Some(parent_pid() as i64),
            tty: resolve_claude_tty().or_else(|| first_string(input, &["tty"])),
        }
    }

    fn permission_response(
        &self,
        decision: Option<&str>,
        reason: Option<&str>,
        _hook_event: &str,
    ) -> Option<Value> {
        match decision {
            Some("allow") => Some(json!({
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": { "behavior": "allow" }
                }
            })),
            Some("deny") => Some(json!({
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {
                        "behavior": "deny",
                        "message": reason.unwrap_or("Denied by user via Agent Island")
                    }
                }
            })),
            _ => None,
        }
    }
}

fn parent_pid() -> u32 {
    unsafe { libc::getppid() as u32 }
}

fn resolve_claude_tty() -> Option<String> {
    let tty_from_parent = Command::new("ps")
        .args(["-p", &parent_pid().to_string(), "-o", "tty="])
        .output()
        .ok()
        .and_then(|output| {
            if !output.status.success() {
                return None;
            }

            let tty = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if tty.is_empty() || tty == "??" || tty == "-" {
                None
            } else if tty.starts_with("/dev/") {
                Some(tty)
            } else {
                Some(format!("/dev/{tty}"))
            }
        });

    tty_from_parent
        .or_else(|| tty_name_for_fd(libc::STDIN_FILENO))
        .or_else(|| tty_name_for_fd(libc::STDOUT_FILENO))
}

fn tty_name_for_fd(fd: i32) -> Option<String> {
    unsafe {
        let ptr = libc::ttyname(fd);
        if ptr.is_null() {
            return None;
        }

        CStr::from_ptr(ptr).to_str().ok().map(str::to_owned)
    }
}
