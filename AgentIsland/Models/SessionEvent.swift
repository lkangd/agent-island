//
//  SessionEvent.swift
//  Agent Island
//
//  Unified event types for the session state machine.
//  All state changes flow through SessionStore.process(event).
//

import Foundation

enum AgentHookDomainEvent: Sendable {
    case notification(HookEvent.NotificationType?)
    case preCompact
    case sessionStart
    case sessionEnd
    case stop
    case subagentStop
    case preToolUse
    case postToolUse
    case userPromptSubmit
    case permissionRequest
    case unknown(String)
}

/// All events that can affect session state
/// This is the single entry point for state mutations
enum SessionEvent: Sendable {
    // MARK: - Hook Events (from HookSocketServer)

    /// A hook event was received from a supported agent
    case hookReceived(HookEvent)

    // MARK: - Permission Events (user actions)

    /// User approved a permission request
    case permissionApproved(sessionId: String, toolUseId: String)

    /// User denied a permission request
    case permissionDenied(sessionId: String, toolUseId: String, reason: String?)

    /// Permission socket failed (connection died before response)
    case permissionSocketFailed(sessionId: String, toolUseId: String)

    // MARK: - File Events (from ConversationParser)

    /// JSONL file was updated with new content
    case fileUpdated(FileUpdatePayload)

    // MARK: - Tool Completion Events (from JSONL parsing)

    /// A tool was detected as completed via JSONL result
    /// This is the authoritative signal that a tool has finished
    case toolCompleted(sessionId: String, toolUseId: String, result: ToolCompletionResult)

    // MARK: - Interrupt Events (from JSONLInterruptWatcher)

    /// User interrupted Claude (detected via JSONL)
    case interruptDetected(sessionId: String)

    // MARK: - Subagent Events (Task tool tracking)

    /// A Task (subagent) tool has started
    case subagentStarted(sessionId: String, taskToolId: String)

    /// A tool was executed within an active subagent
    case subagentToolExecuted(sessionId: String, tool: SubagentToolCall)

    /// A subagent tool completed (status update)
    case subagentToolCompleted(sessionId: String, toolId: String, status: ToolStatus)

    /// A Task (subagent) tool has stopped
    case subagentStopped(sessionId: String, taskToolId: String)

    /// Agent file was updated with new subagent tools (from AgentFileWatcher)
    case agentFileUpdated(sessionId: String, taskToolId: String, tools: [SubagentToolInfo])

    // MARK: - Clear Events (from JSONL detection)

    /// User issued /clear command - reset UI state while keeping session alive
    case clearDetected(sessionId: String)

    // MARK: - Session Lifecycle

    /// Session has ended
    case sessionEnded(sessionId: String)

    /// Request to load initial history from file
    case loadHistory(sessionId: String, cwd: String)

    /// History load completed
    case historyLoaded(sessionId: String, messages: [ChatMessage], completedTools: Set<String>, toolResults: [String: SessionToolResult], structuredResults: [String: ToolResultData], conversationInfo: ConversationInfo, phaseHint: SessionPhase?)
}

/// Payload for file update events
struct FileUpdatePayload: Sendable {
    let sessionId: String
    let cwd: String
    /// Messages to process - either only new messages (if isIncremental) or all messages
    let messages: [ChatMessage]
    /// When true, messages contains only NEW messages since last update
    /// When false, messages contains ALL messages (used for initial load or after /clear)
    let isIncremental: Bool
    let completedToolIds: Set<String>
    let toolResults: [String: SessionToolResult]
    let structuredResults: [String: ToolResultData]
    let conversationInfo: ConversationInfo
    let phaseHint: SessionPhase?
}

/// Result of a tool completion detected from JSONL
struct ToolCompletionResult: Sendable {
    let status: ToolStatus
    let result: String?
    let structuredResult: ToolResultData?

    nonisolated static func from(parserResult: SessionToolResult?, structuredResult: ToolResultData?) -> ToolCompletionResult {
        let status: ToolStatus
        if parserResult?.isInterrupted == true {
            status = .interrupted
        } else if parserResult?.isError == true {
            status = .error
        } else {
            status = .success
        }

        var resultText: String? = nil
        if let r = parserResult {
            if !r.isInterrupted {
                if let stdout = r.stdout, !stdout.isEmpty {
                    resultText = stdout
                } else if let stderr = r.stderr, !stderr.isEmpty {
                    resultText = stderr
                } else if let content = r.content, !content.isEmpty {
                    resultText = content
                }
            }
        }

        return ToolCompletionResult(status: status, result: resultText, structuredResult: structuredResult)
    }
}

// MARK: - Hook Event Extensions

extension HookEvent {
    /// AgentIsland's stable event projection.
    /// Prefer this over `event` in UI and state logic; raw official events are fallback-only.
    nonisolated var sessionPhase: SessionPhase {
        if case .preCompact = domainEvent {
            return .compacting
        }

        switch status {
        case HookEvent.Status.waitingForApproval.rawValue, HookEvent.Status.terminalApprovalRequired.rawValue:
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool ?? "unknown",
                toolInput: toolInput,
                mode: {
                    switch approvalRequestType {
                    case .terminal:
                        return .terminal
                    case .none, .app:
                        return .nativeApp
                    }
                }(),
                receivedAt: Date()
            ))
        case HookEvent.Status.waitingForInput.rawValue:
            return .waitingForInput
        case HookEvent.Status.runningTool.rawValue, HookEvent.Status.processing.rawValue, HookEvent.Status.starting.rawValue:
            return .processing
        case HookEvent.Status.compacting.rawValue:
            return .compacting
        default:
            return .idle
        }
    }

    nonisolated var approvalRequestType: HookEvent.ApprovalRequestType {
        if permissionModeValue == .terminal || status == HookEvent.Status.terminalApprovalRequired.rawValue {
            return .terminal
        }
        if permissionModeValue == .nativeApp || status == HookEvent.Status.waitingForApproval.rawValue {
            return .app
        }
        return .none
    }

    nonisolated var shouldAwaitPermissionResponse: Bool {
        switch approvalRequestType {
        case .none:
            return false
        case .app, .terminal:
            return true
        }
    }

    nonisolated var isSessionEnded: Bool {
        status == HookEvent.Status.ended.rawValue
    }

    nonisolated var isPermissionPromptNotification: Bool {
        switch domainEvent {
        case .notification(.permissionPrompt):
            return true
        default:
            return false
        }
    }

    nonisolated var isIdlePromptNotification: Bool {
        switch domainEvent {
        case .notification(.idlePrompt):
            return true
        default:
            return false
        }
    }

    nonisolated var statusValue: HookEvent.Status {
        HookEvent.Status(rawValue: status) ?? .unknown
    }

    nonisolated var internalEventValue: HookEvent.InternalEventName {
        HookEvent.InternalEventName(rawValue: internalEvent ?? "") ?? .unknown
    }

    nonisolated var permissionModeValue: HookEvent.PermissionMode? {
        guard let permissionMode else { return nil }
        return HookEvent.PermissionMode(rawValue: permissionMode)
    }

    nonisolated var legacyDomainEvent: AgentHookDomainEvent {
        switch event {
        case HookEvent.EventName.notification.rawValue:
            return .notification(NotificationType(rawValue: notificationType ?? "") ?? .unknown)
        case HookEvent.EventName.preCompact.rawValue:
            return .preCompact
        case HookEvent.EventName.sessionStart.rawValue:
            return .sessionStart
        case HookEvent.EventName.sessionEnd.rawValue:
            return .sessionEnd
        case HookEvent.EventName.stop.rawValue:
            return .stop
        case HookEvent.EventName.subagentStop.rawValue:
            return .subagentStop
        case HookEvent.EventName.beforeTool.rawValue, HookEvent.EventName.preToolUse.rawValue:
            return .preToolUse
        case HookEvent.EventName.afterTool.rawValue, HookEvent.EventName.postToolUse.rawValue:
            return .postToolUse
        case HookEvent.EventName.userPromptSubmit.rawValue:
            return .userPromptSubmit
        case HookEvent.EventName.permissionRequest.rawValue:
            return .permissionRequest
        default:
            return .unknown(event)
        }
    }

    nonisolated var usesLegacyEventFallback: Bool {
        internalEventValue == .unknown
    }

    nonisolated var domainEvent: AgentHookDomainEvent {
        // Internal protocol wins. Raw official event names are only fallback compatibility.
        switch internalEventValue {
        case .notification:
            return .notification(NotificationType(rawValue: notificationType ?? "") ?? .unknown)
        case .idlePrompt:
            return .notification(.idlePrompt)
        case .preCompact:
            return .preCompact
        case .sessionStarted:
            return .sessionStart
        case .sessionEnded:
            return .sessionEnd
        case .stopped:
            return .stop
        case .subagentStopped:
            return .subagentStop
        case .toolWillRun:
            return .preToolUse
        case .toolDidRun:
            return .postToolUse
        case .userPromptSubmitted:
            return .userPromptSubmit
        case .permissionRequested:
            return .permissionRequest
        case .unknown:
            return legacyDomainEvent
        }
    }

    nonisolated var protocolDebugSummary: String {
        let internalName = internalEvent ?? "nil"
        let officialName = event.isEmpty ? "nil" : event
        let permission = permissionMode ?? "nil"
        return "internal=\(internalName) official=\(officialName) permission=\(permission)"
    }

    /// Determine the target session phase based on this hook event
    nonisolated func determinePhase() -> SessionPhase {
        // PreCompact takes priority
        if case .preCompact = domainEvent {
            return .compacting
        }

        // Permission request creates waitingForApproval state
        if shouldAwaitPermissionResponse, let tool = tool {
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool,
                toolInput: toolInput,
                mode: {
                    switch approvalRequestType {
                    case .terminal:
                        return .terminal
                    case .none, .app:
                        return .nativeApp
                    }
                }(),
                receivedAt: Date()
            ))
        }

        if case .notification(.idlePrompt) = domainEvent {
            return .idle
        }

        switch status {
        case HookEvent.Status.waitingForInput.rawValue:
            return .waitingForInput
        case HookEvent.Status.runningTool.rawValue, HookEvent.Status.processing.rawValue, HookEvent.Status.starting.rawValue:
            return .processing
        case HookEvent.Status.compacting.rawValue:
            return .compacting
        case HookEvent.Status.ended.rawValue:
            return .ended
        default:
            return .idle
        }
    }

    /// Whether this is a tool-related event
    nonisolated var isToolEvent: Bool {
        switch domainEvent {
        case .preToolUse, .postToolUse, .permissionRequest:
            return true
        default:
            return false
        }
    }

    /// Whether this event should trigger a file sync
    nonisolated var shouldSyncFile: Bool {
        guard AgentInteractionRegistry.shared.supportsConversationHistory(for: agentType) else {
            return false
        }

        switch domainEvent {
        case .userPromptSubmit, .preToolUse, .postToolUse, .stop:
            return true
        default:
            return false
        }
    }
}

// MARK: - Debug Description

extension SessionEvent: CustomStringConvertible {
    nonisolated var description: String {
        switch self {
        case .hookReceived(let event):
            return "hookReceived(\(event.agentType.rawValue):\(event.event), session: \(event.sessionId.prefix(8)))"
        case .permissionApproved(let sessionId, let toolUseId):
            return "permissionApproved(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)))"
        case .permissionDenied(let sessionId, let toolUseId, _):
            return "permissionDenied(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)))"
        case .permissionSocketFailed(let sessionId, let toolUseId):
            return "permissionSocketFailed(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)))"
        case .fileUpdated(let payload):
            return "fileUpdated(session: \(payload.sessionId.prefix(8)), messages: \(payload.messages.count))"
        case .interruptDetected(let sessionId):
            return "interruptDetected(session: \(sessionId.prefix(8)))"
        case .clearDetected(let sessionId):
            return "clearDetected(session: \(sessionId.prefix(8)))"
        case .sessionEnded(let sessionId):
            return "sessionEnded(session: \(sessionId.prefix(8)))"
        case .loadHistory(let sessionId, _):
            return "loadHistory(session: \(sessionId.prefix(8)))"
        case .historyLoaded(let sessionId, let messages, _, _, _, _, _):
            return "historyLoaded(session: \(sessionId.prefix(8)), messages: \(messages.count))"
        case .toolCompleted(let sessionId, let toolUseId, let result):
            return "toolCompleted(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)), status: \(result.status))"
        case .subagentStarted(let sessionId, let taskToolId):
            return "subagentStarted(session: \(sessionId.prefix(8)), task: \(taskToolId.prefix(12)))"
        case .subagentToolExecuted(let sessionId, let tool):
            return "subagentToolExecuted(session: \(sessionId.prefix(8)), tool: \(tool.name))"
        case .subagentToolCompleted(let sessionId, let toolId, let status):
            return "subagentToolCompleted(session: \(sessionId.prefix(8)), tool: \(toolId.prefix(12)), status: \(status))"
        case .subagentStopped(let sessionId, let taskToolId):
            return "subagentStopped(session: \(sessionId.prefix(8)), task: \(taskToolId.prefix(12)))"
        case .agentFileUpdated(let sessionId, let taskToolId, let tools):
            return "agentFileUpdated(session: \(sessionId.prefix(8)), task: \(taskToolId.prefix(12)), tools: \(tools.count))"
        }
    }
}
