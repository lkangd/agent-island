use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentSource {
    Claude,
    Codex,
    Gemini,
    Unknown,
}

impl AgentSource {
    pub fn from_str(value: &str) -> Self {
        match value {
            "claude" => Self::Claude,
            "codex" => Self::Codex,
            "gemini" => Self::Gemini,
            _ => Self::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::Gemini => "gemini",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone)]
pub struct BridgeProfile {
    #[allow(dead_code)]
    pub response_mode: Option<String>,
    pub approval_tools: Vec<String>,
    pub approval_command_patterns: Vec<String>,
    pub auto_approve_tools: Vec<String>,
    pub auto_approve_command_patterns: Vec<String>,
}

impl BridgeProfile {
    pub fn from_json(value: &Value) -> Self {
        Self {
            response_mode: value
                .get("responseMode")
                .and_then(Value::as_str)
                .map(str::to_owned),
            approval_tools: value
                .get("approvalTools")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
            approval_command_patterns: value
                .get("approvalCommandPatterns")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
            auto_approve_tools: value
                .get("autoApproveTools")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
            auto_approve_command_patterns: value
                .get("autoApproveCommandPatterns")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct HookPayload {
    pub session_id: String,
    pub cwd: String,
    pub agent_type: String,
    pub transcript_path: Option<String>,
    pub event: String,
    pub internal_event: String,
    pub status: String,
    pub permission_mode: Option<String>,
    pub pid: Option<i64>,
    pub tty: Option<String>,
    pub tool: Option<String>,
    pub tool_input: Value,
    pub tool_use_id: Option<String>,
    pub notification_type: Option<String>,
    pub message: Option<String>,
    pub extra: Value,
}

#[derive(Debug, Clone)]
pub struct PermissionDecision {
    pub decision: Option<String>,
    pub reason: Option<String>,
}
