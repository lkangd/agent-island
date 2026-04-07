//
//  AgentPermissionAdapter.swift
//  Agent Island
//
//  Normalizes each agent's official permission hook protocol into one runtime model.
//

import Foundation

protocol AgentPermissionAdapter {
    nonisolated var agentType: AgentPlatform { get }
    nonisolated func shouldCacheToolUseId(for event: HookEvent) -> Bool
    nonisolated func shouldAwaitPermissionResponse(for event: HookEvent) -> Bool
    nonisolated func resolveToolUseId(
        for event: HookEvent,
        popCachedToolUseId: (HookEvent) -> String?
    ) -> String?
}

struct AgentPermissionAdapterRegistry {
    nonisolated static let shared = AgentPermissionAdapterRegistry()

    nonisolated func adapter(for agentType: AgentPlatform) -> (any AgentPermissionAdapter) {
        switch agentType {
        case .claude:
            return ClaudePermissionAdapter()
        case .codex:
            return CodexPermissionAdapter()
        case .gemini:
            return GeminiPermissionAdapter()
        }
    }
}

private struct ClaudePermissionAdapter: AgentPermissionAdapter {
    nonisolated init() {}
    let agentType: AgentPlatform = .claude

    func shouldCacheToolUseId(for event: HookEvent) -> Bool {
        if event.internalEventValue == .toolWillRun {
            return true
        }
        if !event.hasInternalProtocol, case .preToolUse = event.domainEvent {
            return true
        }
        return false
    }

    func shouldAwaitPermissionResponse(for event: HookEvent) -> Bool {
        event.internalEventValue == .permissionRequested
            || (!event.hasInternalProtocol && event.shouldAwaitPermissionResponse)
    }

    func resolveToolUseId(
        for event: HookEvent,
        popCachedToolUseId: (HookEvent) -> String?
    ) -> String? {
        event.toolUseId ?? popCachedToolUseId(event)
    }
}

private struct CodexPermissionAdapter: AgentPermissionAdapter {
    nonisolated init() {}
    let agentType: AgentPlatform = .codex

    func shouldCacheToolUseId(for event: HookEvent) -> Bool {
        false
    }

    func shouldAwaitPermissionResponse(for event: HookEvent) -> Bool {
        event.internalEventValue == .permissionRequested
            || (!event.hasInternalProtocol && event.shouldAwaitPermissionResponse)
    }

    func resolveToolUseId(
        for event: HookEvent,
        popCachedToolUseId: (HookEvent) -> String?
    ) -> String? {
        event.toolUseId ?? popCachedToolUseId(event)
    }
}

private struct GeminiPermissionAdapter: AgentPermissionAdapter {
    nonisolated init() {}
    let agentType: AgentPlatform = .gemini

    func shouldCacheToolUseId(for event: HookEvent) -> Bool {
        false
    }

    func shouldAwaitPermissionResponse(for event: HookEvent) -> Bool {
        event.internalEventValue == .permissionRequested
            || (!event.hasInternalProtocol && event.shouldAwaitPermissionResponse)
    }

    func resolveToolUseId(
        for event: HookEvent,
        popCachedToolUseId: (HookEvent) -> String?
    ) -> String? {
        event.toolUseId ?? popCachedToolUseId(event)
    }
}
