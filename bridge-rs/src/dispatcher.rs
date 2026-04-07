use serde_json::Value;

use crate::adapter::{adapter_for, build_payload};
use crate::protocol::{AgentSource, BridgeProfile};

pub struct DispatchResult {
    pub payload: Option<crate::protocol::HookPayload>,
    pub hook_event: Option<String>,
    pub status: Option<String>,
}

pub fn dispatch(
    source: AgentSource,
    input: &Value,
    profile: &BridgeProfile,
) -> DispatchResult {
    let adapter = adapter_for(source);
    let normalized = adapter.normalize_input(input);

    if !adapter.should_emit_event(&normalized) {
        return DispatchResult {
            payload: None,
            hook_event: None,
            status: None,
        };
    }

    let status = adapter.resolve_status(profile, &normalized);

    let session_id = non_empty_or(
        normalized.session_id.clone(),
        || format!("unknown-{}", std::process::id()),
    );
    let cwd = non_empty_or(
        normalized.cwd.clone(),
        || std::env::current_dir().ok().map(|path| path.display().to_string()).unwrap_or_default(),
    );
    let process_info = adapter.process_info(input);

    let payload = build_payload(
        source,
        session_id,
        cwd,
        normalized.hook_event.clone(),
        status.clone(),
        normalized.transcript_path.clone(),
        process_info.pid,
        process_info.tty,
        normalized.tool_name.clone(),
        normalized.tool_input.clone(),
        normalized.tool_use_id.clone(),
        normalized.notification_type.clone(),
        normalized.message.clone(),
    );

    DispatchResult {
        payload: Some(payload),
        hook_event: Some(normalized.hook_event),
        status: Some(status),
    }
}

fn non_empty_or<F>(value: Option<String>, fallback: F) -> String
where
    F: FnOnce() -> String,
{
    match value {
        Some(value) if !value.is_empty() => value,
        _ => fallback(),
    }
}
