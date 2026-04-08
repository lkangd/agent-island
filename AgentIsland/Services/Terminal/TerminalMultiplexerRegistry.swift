import Foundation

struct TerminalMultiplexerRegistry {
    nonisolated static let shared = TerminalMultiplexerRegistry()

    private init() {}

    func adapter(for backend: TerminalBackend) -> any TerminalMultiplexerAdapter {
        switch backend {
        case .tmux:
            return TmuxTerminalMultiplexerAdapter.shared
        case .cmux:
            return CmuxTerminalMultiplexerAdapter.shared
        }
    }
}
