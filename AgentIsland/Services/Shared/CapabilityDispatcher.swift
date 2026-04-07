//
//  CapabilityDispatcher.swift
//  Agent Island
//
//  Dispatches normalized ingress events into the shared session engine.
//

import Foundation

actor DefaultCapabilityDispatcher {
    nonisolated static let shared = DefaultCapabilityDispatcher()

    func handle(_ event: AgentIngressEvent) async {
        await MainActor.run {
            AgentEventBus.shared.publishIngress(event)
        }

        switch event {
        case .hookReceived(let hookEvent):
            await SessionStore.shared.process(.hookReceived(hookEvent))
            _ = await ApprovalPolicyExecutor.shared.applyAutomaticPolicyIfNeeded(for: hookEvent)

            let hookPhase = await MainActor.run { hookEvent.sessionPhase }

            if hookPhase == .processing {
                await MainActor.run {
                    AgentInteractionRegistry.shared.startObservingIfSupported(
                        sessionId: hookEvent.sessionId,
                        agentType: hookEvent.agentType,
                        cwd: hookEvent.cwd,
                        transcriptPath: hookEvent.transcriptPath
                    )
                }
            }

            if hookEvent.isSessionEnded {
                await MainActor.run {
                    AgentInteractionRegistry.shared.stopObservingIfSupported(
                        sessionId: hookEvent.sessionId,
                        agentType: hookEvent.agentType
                    )
                }
            }

            if case .stop = hookEvent.domainEvent {
                await HookSocketServer.shared.cancelPendingPermissions(sessionId: hookEvent.sessionId)
            }

            if case .postToolUse = hookEvent.domainEvent,
               let toolUseId = hookEvent.toolUseId {
                await HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
            }

        case .permissionSocketFailed(let sessionId, let toolUseId):
            await SessionStore.shared.process(
                .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
            )

        case .historyLoadRequested(let sessionId, let cwd):
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))

        case .fileSyncReceived(let payload):
            await SessionStore.shared.process(.fileUpdated(payload))

        case .interruptDetected(let sessionId):
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }
    }
}
