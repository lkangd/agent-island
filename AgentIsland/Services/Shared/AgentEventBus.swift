//
//  AgentEventBus.swift
//  Agent Island
//
//  Lightweight in-app event bus for normalized ingress and domain events.
//

import Combine
import Foundation

enum AgentIngressEvent: Sendable {
    case hookReceived(HookEvent)
    case permissionSocketFailed(sessionId: String, toolUseId: String)
    case historyLoadRequested(sessionId: String, cwd: String)
    case fileSyncReceived(FileUpdatePayload)
    case interruptDetected(sessionId: String)
}

enum AgentDomainEvent: Sendable {
    case sessionEventProcessed(SessionEvent)
    case sessionsUpdated([SessionListState])
}

@MainActor
final class AgentEventBus {
    static let shared = AgentEventBus()

    private let ingressSubject = PassthroughSubject<AgentIngressEvent, Never>()
    private let domainSubject = PassthroughSubject<AgentDomainEvent, Never>()

    var ingressPublisher: AnyPublisher<AgentIngressEvent, Never> {
        ingressSubject.eraseToAnyPublisher()
    }

    var domainPublisher: AnyPublisher<AgentDomainEvent, Never> {
        domainSubject.eraseToAnyPublisher()
    }

    func publishIngress(_ event: AgentIngressEvent) {
        ingressSubject.send(event)
    }

    func publishDomain(_ event: AgentDomainEvent) {
        domainSubject.send(event)
    }
}
