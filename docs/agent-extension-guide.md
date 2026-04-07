# Agent Extension Guide

This guide explains how to add a new hook-capable agent to AgentIsland without forcing the UI to learn a new raw protocol.

Related docs:

- [Docs Index](./README.md)
- [Internal Hook Protocol](./internal-hook-protocol.md)
- [Multi-Agent Architecture Draft](./multi-agent-architecture.md)

## Design Rule

New agents must integrate through the same layered model:

1. Official agent hooks
2. Agent-specific adapter
3. AgentIsland internal hook protocol
4. Shared Swift runtime and UI

Do not wire a new agent directly into UI logic through raw official event names unless there is no viable internal mapping.

## What Must Stay Stable

The UI and session engine should continue to rely on the internal protocol, especially:

- `internal_event`
- `permission_mode`
- `extra`

The new agent should map its official hooks into those fields instead of adding new UI-only branches first.

If you are unsure whether a field belongs in the stable contract, prefer updating the adapter and keeping the field inside `extra` until there is a stronger cross-agent need.

## Integration Checklist

### 1. Add a Rust adapter

Create a new file under:

```text
bridge-rs/src/adapter/
```

Typical shape:

- parse official payload
- decide which events should emit
- compute shared `status`
- compute `internal_event`
- compute `permission_mode`
- build `extra`
- build official permission response JSON

Then register it in:

- `bridge-rs/src/adapter/mod.rs`
- `bridge-rs/src/protocol.rs`

## 2. Map official events to internal events

Your adapter should emit one of the stable internal events:

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

If the new agent exposes a permission flow, it should also emit `permission_mode`.

## 3. Define permission behavior

Decide:

- what official event starts approval
- whether approval is `native_app` or `terminal`
- how to generate the official response JSON

The response format must remain official-agent-specific. Only the internal event model is shared.

## 4. Add installer support

Update:

```text
AgentIsland/Services/Hooks/AgentHookPlugin.swift
```

Tasks:

- add the new plugin
- define official hook event registration
- define install / repair / uninstall behavior
- define capability metadata

## 5. Add Swift runtime support

Update the agent enum and capability surfaces where needed, but keep Swift business logic aligned to internal protocol.

Important files:

- `AgentIsland/Models/AgentPlatform.swift`
- `AgentIsland/Services/Hooks/AgentPermissionAdapter.swift`
- `AgentIsland/Services/Hooks/HookSocketServer.swift`
- `AgentIsland/Models/SessionEvent.swift`

## 6. Use `extra` carefully

`extra` is the escape hatch for agent-specific metadata.

Good examples:

- official event metadata
- matcher names
- command text
- escalation hints
- agent-specific debug fields

Bad examples:

- normalized business meaning
- canonical approval state
- fields already represented in the stable protocol

## 7. Add tests

At minimum, add:

### Event mapping tests

In `bridge-rs`, add dispatch tests that verify:

- official event name is preserved
- internal event is correct
- permission mode is correct
- important `extra` fields are present

### Permission response tests

Also verify:

- allow response shape
- deny response shape
- no-response cases if the agent expects them

## 8. Update docs

When a new agent is added, update:

- `README.md`
- `README.zh.md`
- `docs/internal-hook-protocol.md`

At minimum, document:

- official hook entry points
- approval entry point
- internal event mapping
- validation status

## Recommended Implementation Order

1. Add Rust adapter
2. Add dispatch tests
3. Add permission response tests
4. Add installer support
5. Connect Swift runtime
6. Validate build
7. Update docs

## Current Reference Integrations

Use these as concrete examples:

- Claude
  - official approval entry: `PermissionRequest`
- Codex
  - official approval entry: `PreToolUse`
- Gemini
  - official approval entry: `BeforeTool`

All three end up in the same internal approval event:

- `permission_requested`

That is the pattern future integrations should follow whenever possible.
