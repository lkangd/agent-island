//
//  AgentRuntimeObserver.swift
//  Agent Island
//
//  Agent-specific runtime observers for live session signals such as interrupts.
//

import Foundation

protocol AgentRuntimeObserverDelegate: AnyObject {
    func didDetectInterrupt(sessionId: String)
}

protocol AgentInteractionAdapter: Sendable {
    var agentType: AgentPlatform { get }
    nonisolated var supportsMessaging: Bool { get }
    nonisolated func canSendMessages(in session: SessionState) -> Bool
    func sendMessage(_ message: String, in session: SessionState) async -> Bool
}

@MainActor
protocol AgentRuntimeObserver: AnyObject {
    var agentType: AgentPlatform { get }
    var delegate: AgentRuntimeObserverDelegate? { get set }
    func startObserving(sessionId: String, cwd: String)
    func stopObserving(sessionId: String)
    func stopAll()
}

@MainActor
final class AgentRuntimeObserverRegistry {
    static let shared = AgentRuntimeObserverRegistry()

    private let observers: [AgentPlatform: AgentRuntimeObserver]

    private init() {
        let claudeObserver = ClaudeRuntimeObserver()
        self.observers = [
            .claude: claudeObserver
        ]
    }

    func observer(for agentType: AgentPlatform) -> AgentRuntimeObserver? {
        observers[agentType]
    }

    nonisolated func supportsObservation(for agentType: AgentPlatform) -> Bool {
        switch agentType {
        case .claude:
            return true
        default:
            return false
        }
    }

    func setDelegate(_ delegate: AgentRuntimeObserverDelegate) {
        for observer in observers.values {
            observer.delegate = delegate
        }
    }
}

@MainActor
private final class ClaudeRuntimeObserver: NSObject, AgentRuntimeObserver {
    let agentType: AgentPlatform = .claude

    weak var delegate: AgentRuntimeObserverDelegate? {
        didSet {
            InterruptWatcherManager.shared.delegate = self
        }
    }

    func startObserving(sessionId: String, cwd: String) {
        InterruptWatcherManager.shared.startWatching(sessionId: sessionId, cwd: cwd)
    }

    func stopObserving(sessionId: String) {
        InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
    }

    func stopAll() {
        InterruptWatcherManager.shared.stopAll()
    }
}

extension ClaudeRuntimeObserver: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectInterrupt(sessionId: sessionId)
        }
    }
}

struct AgentInteractionRegistry {
    nonisolated static let shared = AgentInteractionRegistry()

    struct Capabilities: Sendable {
        let supportsConversationHistory: Bool
        let supportsRuntimeObservation: Bool
        let supportsMessaging: Bool
    }

    private let runtimeObservationAgents: Set<AgentPlatform> = [.claude]

    private let adapters: [AgentPlatform: any AgentInteractionAdapter] = [
        .claude: TmuxAgentInteractionAdapter(agentType: .claude),
        .codex: TmuxAgentInteractionAdapter(agentType: .codex),
        .gemini: UnsupportedAgentInteractionAdapter(agentType: .gemini)
    ]

    nonisolated func capabilities(for agentType: AgentPlatform) -> Capabilities {
        Capabilities(
            supportsConversationHistory: SessionTranscriptProviderRegistry.shared.supportsHistory(for: agentType),
            supportsRuntimeObservation: runtimeObservationAgents.contains(agentType),
            supportsMessaging: adapter(for: agentType)?.supportsMessaging ?? false
        )
    }

    nonisolated func supportsConversationHistory(for agentType: AgentPlatform) -> Bool {
        capabilities(for: agentType).supportsConversationHistory
    }

    @MainActor
    func startObservingIfSupported(sessionId: String, agentType: AgentPlatform, cwd: String) {
        guard capabilities(for: agentType).supportsRuntimeObservation else { return }

        AgentRuntimeObserverRegistry.shared
            .observer(for: agentType)?
            .startObserving(sessionId: sessionId, cwd: cwd)
    }

    @MainActor
    func stopObservingIfSupported(sessionId: String, agentType: AgentPlatform) {
        guard capabilities(for: agentType).supportsRuntimeObservation else { return }

        AgentRuntimeObserverRegistry.shared
            .observer(for: agentType)?
            .stopObserving(sessionId: sessionId)
    }

    nonisolated func canSendMessages(for session: SessionState) -> Bool {
        adapter(for: session.agentType)?.canSendMessages(in: session) ?? false
    }

    func sendMessage(_ message: String, for session: SessionState) async -> Bool {
        guard let adapter = adapter(for: session.agentType) else {
            return false
        }

        return await adapter.sendMessage(message, in: session)
    }

    private nonisolated func adapter(for agentType: AgentPlatform) -> (any AgentInteractionAdapter)? {
        adapters[agentType]
    }
}

private struct TmuxAgentInteractionAdapter: AgentInteractionAdapter {
    let agentType: AgentPlatform
    let supportsMessaging = true

    nonisolated func canSendMessages(in session: SessionState) -> Bool {
        session.isInTmux && session.tty != nil
    }

    func sendMessage(_ message: String, in session: SessionState) async -> Bool {
        guard let tty = session.tty,
              let target = await TmuxController.shared.findTmuxTarget(forTTY: tty) else {
            return false
        }

        return await TmuxController.shared.sendMessage(message, to: target)
    }
}

private struct UnsupportedAgentInteractionAdapter: AgentInteractionAdapter {
    let agentType: AgentPlatform
    let supportsMessaging = false

    nonisolated func canSendMessages(in session: SessionState) -> Bool {
        false
    }

    func sendMessage(_ message: String, in session: SessionState) async -> Bool {
        false
    }
}
