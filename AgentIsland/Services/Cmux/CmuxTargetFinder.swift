import Foundation
import os.log

actor CmuxTargetFinder {
    static let shared = CmuxTargetFinder()

    private init() {}

    func findTarget(forTTY tty: String, agentPid: Int? = nil) async -> CmuxTarget? {
        guard let workspaceId = await currentWorkspaceId() else {
            CmuxRPCClient.logger.error("cmux target resolve failed: missing workspace for tty=\(tty)")
            return nil
        }

        if let surfaceId = await findSurfaceIdByTTY(tty) {
            return CmuxTarget(workspaceId: workspaceId, surfaceId: surfaceId)
        }

        if let agentPid,
           let targetFromEnv = findTargetFromProcessEnvironment(agentPid: agentPid, fallbackWorkspaceId: workspaceId) {
            return targetFromEnv
        }

        if let identified = await CmuxRPCClient.shared.identify() {
            let focused = identified["focused"] as? [String: Any]
            if let surfaceId = focused?["surface_id"] as? String,
               let focusedWorkspaceId = focused?["workspace_id"] as? String {
                return CmuxTarget(workspaceId: focusedWorkspaceId, surfaceId: surfaceId)
            }
            if let surfaceId = identified["surface_id"] as? String,
               let identifiedWorkspaceId = identified["workspace_id"] as? String {
                return CmuxTarget(workspaceId: identifiedWorkspaceId, surfaceId: surfaceId)
            }
        }

        CmuxRPCClient.logger.error("cmux target resolve failed: no surface matched tty=\(tty)")
        return nil
    }

    func findTarget(forAgentPid agentPid: Int) async -> CmuxTarget? {
        let tree = ProcessTreeBuilder.shared.buildTree()
        guard let tty = tree[agentPid]?.tty else {
            return nil
        }
        return await findTarget(forTTY: tty)
    }

    func findTarget(forWorkingDirectory workingDirectory: String) async -> CmuxTarget? {
        guard let workspaceId = await currentWorkspaceId() else {
            return nil
        }

        guard let response = await CmuxRPCClient.shared.listSurfaces(),
              let surfaces = response["surfaces"] as? [[String: Any]] else {
            return nil
        }

        for surface in surfaces {
            guard let surfaceId = surface["surface_id"] as? String else { continue }
            if let cwd = surface["cwd"] as? String, cwd == workingDirectory {
                return CmuxTarget(workspaceId: workspaceId, surfaceId: surfaceId)
            }
        }

        return nil
    }

    func isSessionTargetActive(agentPid: Int) async -> Bool {
        guard let target = await findTarget(forAgentPid: agentPid),
              let identified = await CmuxRPCClient.shared.identify(),
              let activeSurfaceId = identified["surface_id"] as? String else {
            return false
        }

        return target.surfaceId == activeSurfaceId
    }

    private func currentWorkspaceId() async -> String? {
        if let response = await CmuxRPCClient.shared.currentWorkspace(),
           let id = response["workspace_id"] as? String {
            return id
        }

        if let identify = await CmuxRPCClient.shared.identify() {
            let focused = identify["focused"] as? [String: Any]
            if let id = focused?["workspace_id"] as? String {
                return id
            }
            if let id = identify["workspace_id"] as? String {
                return id
            }
        }

        return nil
    }

    private func findTargetFromProcessEnvironment(agentPid: Int, fallbackWorkspaceId: String) -> CmuxTarget? {
        guard let envOutput = ProcessExecutor.shared.runSyncOrNil("/bin/ps", arguments: ["eww", "-p", String(agentPid)]) else {
            return nil
        }

        if let surfaceId = extractEnvValue("CMUX_SURFACE_ID", from: envOutput) {
            let workspaceId = extractEnvValue("CMUX_WORKSPACE_ID", from: envOutput) ?? fallbackWorkspaceId
            return CmuxTarget(workspaceId: workspaceId, surfaceId: surfaceId)
        }

        return nil
    }

    private func extractEnvValue(_ key: String, from text: String) -> String? {
        guard let range = text.range(of: "\(key)=") else {
            return nil
        }
        let substring = text[range.upperBound...]
        let value = substring.prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : String(value)
    }

    private func findSurfaceIdByTTY(_ tty: String) async -> String? {
        guard let response = await CmuxRPCClient.shared.listSurfaces(),
              let surfaces = response["surfaces"] as? [[String: Any]] else {
            return nil
        }

        for surface in surfaces {
            guard let surfaceId = surface["surface_id"] as? String else { continue }
            if let surfaceTTY = surface["tty"] as? String {
                let normalized = surfaceTTY.replacingOccurrences(of: "/dev/", with: "")
                if normalized == tty {
                    return surfaceId
                }
            }
        }

        return nil
    }
}
