//
//  AgentPlatform.swift
//  Agent Island
//
//  Supported top-level agent runtimes for session tracking and hook setup.
//

import SwiftUI

enum AgentExitCommand: Sendable {
    case quit
    case exit

    var text: String {
        switch self {
        case .quit: return "/quit"
        case .exit: return "/exit"
        }
    }

    var buttonLabel: String {
        switch self {
        case .quit: return "Quit"
        case .exit: return "Exit"
        }
    }
}

struct AgentTerminalControlProfile: Sendable {
    let supportsInterrupt: Bool
    let exitCommand: AgentExitCommand?
}

enum ApprovalPolicy: String, Codable, CaseIterable, Sendable {
    case deny
    case allowOnce
    case allowAlways
    case autoExecute

    var displayName: String {
        switch self {
        case .deny: return "Deny"
        case .allowOnce: return "Allow Once"
        case .allowAlways: return "Allow Always"
        case .autoExecute: return "Auto Execute"
        }
    }
}

enum ApprovalAction: String, CaseIterable, Sendable {
    case deny
    case allowOnce
    case allowAlways
    case autoExecute
    case terminal

    var label: String {
        switch self {
        case .deny: return "Deny"
        case .allowOnce: return "Allow Once"
        case .allowAlways: return "Allow Always"
        case .autoExecute: return "Auto Execute"
        case .terminal: return "Jump to Terminal"
        }
    }
}

enum ApprovalCapabilityKind: String, Codable, Sendable {
    case nativeInteractive
    case terminalOnly
    case unsupported
}

struct ApprovalCapability: Sendable {
    let kind: ApprovalCapabilityKind
    let supportedPolicies: [ApprovalPolicy]
    let supportedActions: [ApprovalAction]
}

enum AgentPlatform: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude:
            return TerminalColors.claude
        case .codex:
            return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .gemini:
            return Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }

    var iconSymbol: String {
        switch self {
        case .claude: return "brain.head.profile.fill"
        case .codex: return "terminal"
        case .gemini: return "sparkles"
        }
    }

    nonisolated var approvalCapability: ApprovalCapability {
        switch self {
        case .claude:
            return ApprovalCapability(
                kind: .nativeInteractive,
                supportedPolicies: [.deny, .allowOnce, .allowAlways, .autoExecute],
                supportedActions: [.deny, .allowOnce, .allowAlways, .autoExecute]
            )
        case .codex:
            return ApprovalCapability(
                kind: .nativeInteractive,
                supportedPolicies: [.deny, .allowOnce],
                supportedActions: [.deny, .allowOnce]
            )
        case .gemini:
            return ApprovalCapability(
                kind: .terminalOnly,
                supportedPolicies: [.deny, .allowOnce],
                supportedActions: [.terminal]
            )
        }
    }

    nonisolated var terminalControlProfile: AgentTerminalControlProfile {
        switch self {
        case .claude:
            return AgentTerminalControlProfile(
                supportsInterrupt: true,
                exitCommand: .exit
            )
        case .codex:
            return AgentTerminalControlProfile(
                supportsInterrupt: true,
                exitCommand: .quit
            )
        case .gemini:
            return AgentTerminalControlProfile(
                supportsInterrupt: true,
                exitCommand: .quit
            )
        }
    }

    static func from(rawValue: String?) -> AgentPlatform {
        guard let rawValue else { return .claude }

        switch rawValue.lowercased() {
        case "claude", "claudecode", "claude_code":
            return .claude
        case "codex":
            return .codex
        case "gemini", "geminicli", "gemini_cli":
            return .gemini
        default:
            return .claude
        }
    }

    nonisolated static func detect(fromCommand command: String) -> AgentPlatform? {
        let normalized = command.lowercased()

        if normalized.contains("claude") {
            return .claude
        }
        if normalized.contains("codex") {
            return .codex
        }
        if normalized.contains("gemini") {
            return .gemini
        }

        return nil
    }
}
