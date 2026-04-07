//
//  ToolUseIdCache.swift
//  Agent Island
//
//  Tracks official tool_use_id values for agents whose permission events omit them.
//

import Foundation
import os.log

private let toolUseIdCacheLogger = Logger(subsystem: "com.agentisland", category: "Hooks")

final class ToolUseIdCache {
    /// Encoder with sorted keys for deterministic cache keys.
    private static let sortedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Key: "sessionId:toolName:serializedInput" -> Queue of tool_use_ids (FIFO)
    private var storage: [String: [String]] = [:]
    private let lock = NSLock()

    func store(for event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }

        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        lock.lock()
        if storage[key] == nil {
            storage[key] = []
        }
        storage[key]?.append(toolUseId)
        lock.unlock()

        toolUseIdCacheLogger.debug("Cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
    }

    func pop(for event: HookEvent) -> String? {
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        lock.lock()
        defer { lock.unlock() }

        guard var queue = storage[key], !queue.isEmpty else {
            return nil
        }

        let toolUseId = queue.removeFirst()
        if queue.isEmpty {
            storage.removeValue(forKey: key)
        } else {
            storage[key] = queue
        }

        toolUseIdCacheLogger.debug("Retrieved cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
        return toolUseId
    }

    func removeAll(sessionId: String) {
        lock.lock()
        let keysToRemove = storage.keys.filter { $0.hasPrefix("\(sessionId):") }
        for key in keysToRemove {
            storage.removeValue(forKey: key)
        }
        lock.unlock()

        if !keysToRemove.isEmpty {
            toolUseIdCacheLogger.debug("Cleaned up \(keysToRemove.count) cache entries for session \(sessionId.prefix(8), privacy: .public)")
        }
    }

    func removeAll() {
        lock.lock()
        let removedCount = storage.count
        storage.removeAll()
        lock.unlock()

        if removedCount > 0 {
            toolUseIdCacheLogger.debug("Cleared \(removedCount) tool_use_id cache entries")
        }
    }

    private func cacheKey(sessionId: String, toolName: String?, toolInput: [String: AnyCodable]?) -> String {
        let inputStr: String
        if let toolInput,
           let data = try? Self.sortedEncoder.encode(toolInput),
           let str = String(data: data, encoding: .utf8) {
            inputStr = str
        } else {
            inputStr = "{}"
        }

        return "\(sessionId):\(toolName ?? "unknown"):\(inputStr)"
    }
}
