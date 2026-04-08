import Foundation

protocol TerminalMultiplexerAdapter {
    var backend: TerminalBackend { get }

    func hasTarget(forTTY tty: String) async -> Bool
    func sendMessage(_ message: String, tty: String, agentPid: Int?) async -> Bool
    func sendSpecialKey(_ key: TmuxSpecialKey, tty: String, agentPid: Int?) async -> Bool
    func isSessionTargetActive(agentPid: Int) async -> Bool
}
