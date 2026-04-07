//
//  SessionListState.swift
//  Agent Island
//
//  Lightweight projection for session list and notch-level UI.
//

import Foundation

struct SessionListState: Equatable, Identifiable, Sendable {
    let sessionId: String
    let agentType: AgentPlatform
    let cwd: String
    let transcriptPath: String?
    let projectName: String
    let pid: Int?
    let tty: String?
    let isInTmux: Bool
    let phase: SessionPhase
    let conversationInfo: ConversationInfo
    let lastActivity: Date
    let createdAt: Date

    var id: String { sessionId }

    var stableId: String {
        if let pid {
            return "\(pid)-\(sessionId)"
        }
        return sessionId
    }

    var needsAttention: Bool {
        phase.needsAttention
    }

    var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase {
            return ctx
        }
        return nil
    }

    var approvalMode: ApprovalMode? {
        phase.approvalMode
    }

    var usesTerminalApproval: Bool {
        approvalMode == .terminal
    }

    var displayTitle: String {
        cleanedDisplayTitle(conversationInfo.summary)
            ?? cleanedDisplayTitle(conversationInfo.firstUserMessage)
            ?? projectName
    }

    var pendingToolName: String? {
        activePermission?.toolName
    }

    var pendingToolInput: String? {
        activePermission?.formattedInput
    }

    var lastMessage: String? {
        conversationInfo.lastMessage
    }

    var lastMessageRole: String? {
        conversationInfo.lastMessageRole
    }

    var lastToolName: String? {
        conversationInfo.lastToolName
    }

    var summary: String? {
        conversationInfo.summary
    }

    var firstUserMessage: String? {
        conversationInfo.firstUserMessage
    }

    var lastUserMessageDate: Date? {
        conversationInfo.lastUserMessageDate
    }
}
