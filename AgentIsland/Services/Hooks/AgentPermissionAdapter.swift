//
//  AgentPermissionAdapter.swift
//  Agent Island
//
//  Normalizes agent-specific permission hook protocols into one runtime model.
//

import Foundation

protocol AgentPermissionAdapter {
    var agentType: AgentPlatform { get }
    func shouldCacheToolUseId(for event: HookEvent) -> Bool
    func shouldAwaitPermissionResponse(for event: HookEvent) -> Bool
    func resolveToolUseId(
        for event: HookEvent,
        popCachedToolUseId: (HookEvent) -> String?
    ) -> String?
}

struct AgentPermissionAdapterRegistry {
    nonisolated static let shared = AgentPermissionAdapterRegistry()

    private let adapters: [AgentPlatform: any AgentPermissionAdapter] = [
        .claude: ClaudePermissionAdapter(),
        .codex: BridgePermissionAdapter(agentType: .codex),
        .gemini: BridgePermissionAdapter(agentType: .gemini)
    ]

    nonisolated func adapter(for agentType: AgentPlatform) -> (any AgentPermissionAdapter) {
        adapters[agentType] ?? BridgePermissionAdapter(agentType: agentType)
    }
}

private struct ClaudePermissionAdapter: AgentPermissionAdapter {
    let agentType: AgentPlatform = .claude

    func shouldCacheToolUseId(for event: HookEvent) -> Bool {
        event.event == "PreToolUse"
    }

    func shouldAwaitPermissionResponse(for event: HookEvent) -> Bool {
        event.expectsResponse
    }

    func resolveToolUseId(
        for event: HookEvent,
        popCachedToolUseId: (HookEvent) -> String?
    ) -> String? {
        event.toolUseId ?? popCachedToolUseId(event)
    }
}

private struct BridgePermissionAdapter: AgentPermissionAdapter {
    let agentType: AgentPlatform

    func shouldCacheToolUseId(for event: HookEvent) -> Bool {
        false
    }

    func shouldAwaitPermissionResponse(for event: HookEvent) -> Bool {
        event.expectsResponse
    }

    func resolveToolUseId(
        for event: HookEvent,
        popCachedToolUseId: (HookEvent) -> String?
    ) -> String? {
        event.toolUseId ?? popCachedToolUseId(event)
    }
}
