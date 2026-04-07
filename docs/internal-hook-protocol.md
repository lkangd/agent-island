# Internal Hook Protocol

Agent Island uses a two-layer hook model:

1. Official agent hook protocols
2. Agent Island's internal hook protocol

Claude, Codex, Gemini, and future agents should keep their official behavior inside agent-specific adapters. UI and session logic should consume the internal protocol instead of raw official event names.

Related docs:

- [Docs Index](./README.md)
- [Multi-Agent Architecture Draft](./multi-agent-architecture.md)
- [Agent Extension Guide](./agent-extension-guide.md)

## Goals

- Keep UI and session state logic stable
- Allow each agent to follow its official hook protocol
- Make new agent integrations predictable
- Preserve agent-specific details through `extra` without expanding the core contract

## Stable Fields

The Rust bridge emits these stable fields to the Swift runtime in `HookPayload`.

- `session_id`
- `cwd`
- `agent_type`
- `transcript_path`
- `event`
  Raw official hook event. Keep for diagnostics and fallback only.
- `internal_event`
  Agent Island's normalized event. This is the primary business field.
- `status`
  Shared runtime status used for session phase decisions.
- `permission_mode`
  Normalized permission mode.
- `pid`
- `tty`
- `tool`
- `tool_input`
- `tool_use_id`
- `notification_type`
- `message`
- `extra`
  Agent-specific passthrough payload. This is the extension point for non-core details.

## Internal Events

`internal_event` currently uses these values:

- `notification`
- `idle_prompt`
- `pre_compact`
- `session_started`
- `session_ended`
- `stopped`
- `subagent_stopped`
- `tool_will_run`
- `tool_did_run`
- `user_prompt_submitted`
- `permission_requested`
- `unknown`

UI and state logic should prefer `internal_event` over raw `event`.

## Permission Modes

`permission_mode` currently uses:

- `native_app`
- `terminal`

If an agent does not provide a permission mode, Swift may still fall back to older status-based logic. New integrations should emit `permission_mode` explicitly whenever a permission decision is involved.

## Official Agent Mappings

These are the current official-to-internal mappings.

### Claude

Official hook protocol:

- `SessionStart`
- `SessionEnd`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `Notification`
- `Stop`
- `SubagentStop`
- `PreCompact`
- `UserPromptSubmit`

Internal mapping highlights:

- `PermissionRequest` -> `permission_requested`
- `PreToolUse` -> `tool_will_run`
- `PostToolUse` -> `tool_did_run`
- `Notification(idle_prompt)` -> `idle_prompt`

Permission mode:

- `PermissionRequest` -> `native_app`

### Codex

Official hook protocol:

- `SessionStart`
- `PreToolUse`
- `PostToolUse`
- `UserPromptSubmit`
- `Stop`

Current official behavior we depend on:

- approvals are driven from `PreToolUse`
- current stable matcher is `Bash`

Internal mapping highlights:

- `PreToolUse` -> `tool_will_run`
- approval-triggering `PreToolUse` -> `permission_requested`
- `PostToolUse` -> `tool_did_run`

Permission mode:

- approval-triggering `PreToolUse` -> `native_app`

### Gemini

Official hook protocol currently handled by Agent Island:

- `BeforeTool`
- `AfterTool`
- `SessionStart`
- `SessionEnd`
- `Notification`

Internal mapping highlights:

- `BeforeTool` -> `tool_will_run`
- approval-triggering `BeforeTool` -> `permission_requested`
- `AfterTool` -> `tool_did_run`
- `Notification(idle_prompt)` -> `idle_prompt`

Permission mode:

- approval-triggering `BeforeTool` -> `native_app`

## `extra` Guidelines

`extra` exists for agent-specific details that should not become part of the stable core contract.

Good uses:

- official event metadata
- matcher names
- command text
- escalation flags
- agent-specific debug context

Avoid putting these into `extra`:

- session identity
- canonical permission state
- normalized business event names
- fields already represented by stable core properties

Current examples:

- `officialEvent`
- `officialPermissionEvent`
- `toolMatcher`
- `commandText`
- `escalationRequested`

## Adapter Responsibilities

Each agent adapter is responsible for:

1. Parsing official payloads
2. Deciding whether an event should be emitted
3. Computing shared `status`
4. Computing `internal_event`
5. Computing `permission_mode`
6. Populating `extra`
7. Building official permission response JSON

The adapter layer is the only place that should know official hook event names in detail.

## Swift Responsibilities

Swift runtime responsibilities:

- decode bridge payloads
- prefer `internalEvent` and `permissionMode`
- use raw `event` only as fallback compatibility
- keep UI logic independent from agent-specific official names

Important files:

- `AgentIsland/Services/Hooks/HookSocketServer.swift`
- `AgentIsland/Models/SessionEvent.swift`
- `AgentIsland/Services/State/SessionStore.swift`

## Adding a New Agent

When adding a new hook-capable agent:

1. Create a new official adapter in `bridge-rs/src/adapter/`
2. Keep official event handling inside that adapter
3. Map official events to `internal_event`
4. Emit `permission_mode` for any approval flow
5. Put non-core details into `extra`
6. Add install/repair logic in `AgentHookPlugin.swift`
7. Add dispatch tests for event mapping
8. Add permission response tests for official response JSON

Do not make the UI understand the new agent's raw official event names unless there is no viable internal mapping.

For the implementation checklist and rollout order, continue with the [Agent Extension Guide](./agent-extension-guide.md).
