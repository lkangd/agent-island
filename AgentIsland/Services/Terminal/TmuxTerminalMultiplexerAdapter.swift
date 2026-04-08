import Foundation

final actor TmuxTerminalMultiplexerAdapter: TerminalMultiplexerAdapter {
    static let shared = TmuxTerminalMultiplexerAdapter()

    let backend: TerminalBackend = .tmux

    private init() {}

    func hasTarget(forTTY tty: String) async -> Bool {
        await TmuxController.shared.findTmuxTarget(forTTY: tty) != nil
    }

    func sendMessage(_ message: String, tty: String, agentPid _: Int?) async -> Bool {
        guard let target = await TmuxController.shared.findTmuxTarget(forTTY: tty) else {
            return false
        }
        return await TmuxController.shared.sendMessage(message, to: target)
    }

    func sendSpecialKey(_ key: TmuxSpecialKey, tty: String, agentPid _: Int?) async -> Bool {
        guard let target = await TmuxController.shared.findTmuxTarget(forTTY: tty) else {
            return false
        }
        return await TmuxController.shared.sendSpecialKey(key, to: target)
    }

    func isSessionTargetActive(agentPid: Int) async -> Bool {
        await TmuxTargetFinder.shared.isSessionPaneActive(agentPid: agentPid)
    }
}
