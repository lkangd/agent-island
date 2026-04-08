import Foundation

final actor CmuxTerminalMultiplexerAdapter: TerminalMultiplexerAdapter {
    static let shared = CmuxTerminalMultiplexerAdapter()

    let backend: TerminalBackend = .cmux

    private init() {}

    func hasTarget(forTTY tty: String) async -> Bool {
        await CmuxController.shared.findTarget(forTTY: tty) != nil
    }

    func sendMessage(_ message: String, tty: String, agentPid: Int?) async -> Bool {
        guard let target = await CmuxController.shared.findTarget(forTTY: tty, agentPid: agentPid) else {
            return false
        }
        return await CmuxController.shared.sendMessage(message, to: target)
    }

    func sendSpecialKey(_ key: TmuxSpecialKey, tty: String, agentPid: Int?) async -> Bool {
        guard let target = await CmuxController.shared.findTarget(forTTY: tty, agentPid: agentPid) else {
            return false
        }
        return await CmuxController.shared.sendSpecialKey(key, to: target)
    }

    func isSessionTargetActive(agentPid: Int) async -> Bool {
        await CmuxController.shared.isSessionTargetActive(agentPid: agentPid)
    }
}
