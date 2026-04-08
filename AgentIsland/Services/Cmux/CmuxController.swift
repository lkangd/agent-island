import Foundation

actor CmuxController {
    static let shared = CmuxController()

    private init() {}

    func findTarget(forTTY tty: String, agentPid: Int? = nil) async -> CmuxTarget? {
        await CmuxTargetFinder.shared.findTarget(forTTY: tty, agentPid: agentPid)
    }

    func findTarget(forAgentPid pid: Int) async -> CmuxTarget? {
        await CmuxTargetFinder.shared.findTarget(forAgentPid: pid)
    }

    func findTarget(forWorkingDirectory dir: String) async -> CmuxTarget? {
        await CmuxTargetFinder.shared.findTarget(forWorkingDirectory: dir)
    }

    func sendMessage(_ message: String, to target: CmuxTarget) async -> Bool {
        await CmuxRPCClient.shared.sendText(message, surfaceId: target.surfaceId)
    }

    func sendSpecialKey(_ key: TmuxSpecialKey, to target: CmuxTarget) async -> Bool {
        let mapped: String
        switch key {
        case .escape:
            mapped = "escape"
        }
        return await CmuxRPCClient.shared.sendKey(mapped, surfaceId: target.surfaceId)
    }

    func switchToTarget(_ target: CmuxTarget) async -> Bool {
        let switched = await CmuxRPCClient.shared.selectWorkspace(target.workspaceId)
        guard switched else { return false }
        return await CmuxRPCClient.shared.focusSurface(target.surfaceId)
    }

    func isSessionTargetActive(agentPid: Int) async -> Bool {
        await CmuxTargetFinder.shared.isSessionTargetActive(agentPid: agentPid)
    }
}
