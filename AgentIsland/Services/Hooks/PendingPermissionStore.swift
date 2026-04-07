//
//  PendingPermissionStore.swift
//  Agent Island
//
//  Thread-safe storage for pending hook permission requests.
//

import Foundation
import os.log

private let pendingPermissionLogger = Logger(subsystem: "com.agentisland", category: "Hooks")

/// Pending permission request waiting for user decision
struct PendingPermission: Sendable {
    let sessionId: String
    let toolUseId: String
    let clientSocket: Int32
    let event: HookEvent
    let receivedAt: Date
}

final class PendingPermissionStore {
    private var pendingPermissions: [String: PendingPermission] = [:]
    private let lock = NSLock()

    func insert(_ pending: PendingPermission) -> PendingPermission? {
        lock.lock()
        let replaced = pendingPermissions.updateValue(pending, forKey: pending.toolUseId)
        lock.unlock()
        return replaced
    }

    func remove(toolUseId: String) -> PendingPermission? {
        lock.lock()
        let pending = pendingPermissions.removeValue(forKey: toolUseId)
        lock.unlock()
        return pending
    }

    func removeMostRecent(sessionId: String) -> PendingPermission? {
        lock.lock()
        let pending = pendingPermissions.values
            .filter { $0.sessionId == sessionId }
            .sorted { $0.receivedAt > $1.receivedAt }
            .first
        if let pending {
            pendingPermissions.removeValue(forKey: pending.toolUseId)
        }
        lock.unlock()
        return pending
    }

    func contains(sessionId: String) -> Bool {
        lock.lock()
        let hasPending = pendingPermissions.values.contains { $0.sessionId == sessionId }
        lock.unlock()
        return hasPending
    }

    func details(sessionId: String) -> (toolName: String?, toolId: String?, toolInput: [String: AnyCodable]?)? {
        lock.lock()
        let pending = pendingPermissions.values.first(where: { $0.sessionId == sessionId })
        lock.unlock()
        guard let pending else { return nil }
        return (pending.event.tool, pending.toolUseId, pending.event.toolInput)
    }

    func removeAll(sessionId: String) -> [PendingPermission] {
        lock.lock()
        let matching = pendingPermissions.filter { $0.value.sessionId == sessionId }
        for toolUseId in matching.keys {
            pendingPermissions.removeValue(forKey: toolUseId)
        }
        lock.unlock()
        return Array(matching.values)
    }

    func removeAll() -> [PendingPermission] {
        lock.lock()
        let allPending = Array(pendingPermissions.values)
        pendingPermissions.removeAll()
        lock.unlock()
        return allPending
    }
}
