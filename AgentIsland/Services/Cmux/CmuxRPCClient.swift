import Foundation
import os.log

actor CmuxRPCClient {
    nonisolated static let logger = Logger(subsystem: "com.agentisland", category: "CmuxRPC")
    static let shared = CmuxRPCClient()

    private init() {}

    private let defaultSocketPath = "/tmp/cmux.sock"

    private func socketPath() -> String {
        if let env = Foundation.ProcessInfo.processInfo.environment["CMUX_SOCKET_PATH"], !env.isEmpty {
            return env
        }
        return defaultSocketPath
    }

    private func rpc(_ method: String, params: [String: Any] = [:]) async -> [String: Any]? {
        let request: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              let payload = String(data: requestData, encoding: .utf8) else {
            return nil
        }

        let socket = socketPath()
        let cmd = "cat <<'EOF' | nc -U \"\(socket)\"\n\(payload)\nEOF"

        let result = await ProcessExecutor.shared.runWithResult("/bin/sh", arguments: ["-lc", cmd])
        guard case .success(let processResult) = result else {
            Self.logger.error("cmux rpc failed method=\(method, privacy: .public) socket=\(socket, privacy: .public)")
            return nil
        }

        let line = processResult.output
            .components(separatedBy: CharacterSet.newlines)
            .first { !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }

        guard let line,
              let data = line.data(using: String.Encoding.utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = response["ok"] as? Bool,
              ok == true else {
            Self.logger.error("cmux rpc bad response method=\(method, privacy: .public) raw=\(processResult.output, privacy: .public)")
            return nil
        }

        if let rpcResult = response["result"] as? [String: Any] {
            return rpcResult
        }

        return [:]
    }

    func identify() async -> [String: Any]? {
        await rpc("system.identify")
    }

    func currentWorkspace() async -> [String: Any]? {
        await rpc("workspace.current")
    }

    func listSurfaces() async -> [String: Any]? {
        await rpc("surface.list")
    }

    func sendText(_ text: String, surfaceId: String) async -> Bool {
        await rpc("surface.send_text", params: ["surface_id": surfaceId, "text": text + "\n"]) != nil
    }

    func sendKey(_ key: String, surfaceId: String) async -> Bool {
        await rpc("surface.send_key", params: ["surface_id": surfaceId, "key": key]) != nil
    }

    func focusSurface(_ surfaceId: String) async -> Bool {
        await rpc("surface.focus", params: ["surface_id": surfaceId]) != nil
    }

    func selectWorkspace(_ workspaceId: String) async -> Bool {
        await rpc("workspace.select", params: ["workspace_id": workspaceId]) != nil
    }
}
