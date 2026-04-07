//
//  AgentHookPlugin.swift
//  Agent Island
//
//  Plugin-style abstraction for agent hook installation.
//

import Foundation

protocol AgentHookPlugin {
    var agentType: AgentPlatform { get }
    var capabilities: AgentHookCapabilities { get }
    func isAvailable(in context: HookPluginContext) -> Bool
    func install(in context: HookPluginContext) throws
    func uninstall(in context: HookPluginContext) throws
    func isInstalled(in context: HookPluginContext) -> Bool
    func diagnose(in context: HookPluginContext) -> AgentHookDiagnostic
}

enum AgentPermissionRequestSource: String, Sendable {
    case nativeRequest
    case preToolUse
}

enum AgentBridgeDistributionError: LocalizedError {
    case missingSource
    case invalidSource(String)
    case cannotCreateDirectory(String)
    case copyFailed(String)
    case notExecutable(String)

    var errorDescription: String? {
        switch self {
        case .missingSource:
            return "Rust bridge binary not found. Build bridge-rs first."
        case .invalidSource(let path):
            return "Invalid bridge source path: \(path)"
        case .cannotCreateDirectory(let path):
            return "Cannot create required bridge directory: \(path)"
        case .copyFailed(let path):
            return "Failed to copy bridge binary to: \(path)"
        case .notExecutable(let path):
            return "Bridge binary is not executable: \(path)"
        }
    }
}

struct AgentHookCapabilities: Sendable {
    let supportedEvents: [String]
    let approvalTools: [String]
    let approvalCommandPatterns: [String]
    let responseMode: String?
    let permissionRequestSource: AgentPermissionRequestSource?
    let supportsPermissionDecisions: Bool
    let supportsConversationHistory: Bool

    var bridgeProfile: AgentBridgeProfile? {
        guard let responseMode else { return nil }
        return AgentBridgeProfile(
            agentType: "",
            responseMode: responseMode,
            approvalTools: approvalTools,
            approvalCommandPatterns: approvalCommandPatterns
        )
    }
}

struct AgentBridgeProfile: Codable {
    let agentType: String
    let responseMode: String
    let approvalTools: [String]
    let approvalCommandPatterns: [String]
}

struct HookPluginContext {
    let fileManager: FileManager
    let homeDirectory: URL
    let installRoot: URL
    let sharedHooksDir: URL
    let bridgeProfilesDir: URL
    let sharedBridgeName: String

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.homeDirectory = fileManager.homeDirectoryForCurrentUser
        self.installRoot = homeDirectory.appendingPathComponent(".agent-island")
        self.sharedHooksDir = installRoot.appendingPathComponent("hooks")
        self.bridgeProfilesDir = installRoot.appendingPathComponent("bridge-profiles")
        self.sharedBridgeName = "agent-island-bridge"
    }

    func bridgeCommand(for agent: AgentPlatform) -> String {
        "\"\(sharedHooksDir.appendingPathComponent(sharedBridgeName).path)\" --source \(agent.rawValue)"
    }

    private func preferredResourceBridgeURL() -> URL? {
        let bundlePath = Bundle.main.resourcePath
        if let bundlePath {
            let resourceCandidates = [
                "\(bundlePath)/\(sharedBridgeName)",
                "\(bundlePath)/Contents/Resources/\(sharedBridgeName)"
            ]
            for path in resourceCandidates where fileManager.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent(sharedBridgeName)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let bundleBundlePath = Bundle.main.bundlePath
        let fallbackBundlePaths = [
            "\(bundleBundlePath)/Contents/Resources/\(sharedBridgeName)",
            "\(bundleBundlePath)/Contents/Helpers/\(sharedBridgeName)",
            "\(bundleBundlePath)/Contents/SharedSupport/\(sharedBridgeName)"
        ]
        for path in fallbackBundlePaths where fileManager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    func preferredRustBridgeSourceURL() -> URL? {
        let environment = Foundation.ProcessInfo.processInfo.environment

        if let override = environment["AGENT_ISLAND_BRIDGE_BINARY"] {
            let expandedOverride = NSString(string: override).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedOverride) {
                return URL(fileURLWithPath: expandedOverride)
            }
        }

        if let resourceBridge = preferredResourceBridgeURL() {
            return resourceBridge
        }

        let installedBridge = sharedHooksDir.appendingPathComponent(sharedBridgeName)
        if fileManager.fileExists(atPath: installedBridge.path) {
            return installedBridge
        }

        let legacyInstalledBridge = homeDirectory
            .appendingPathComponent(".agent-island/hooks")
            .appendingPathComponent("agent-island-bridge")
        if fileManager.fileExists(atPath: legacyInstalledBridge.path) {
            return legacyInstalledBridge
        }

        let appInstallPaths = [
            "/Applications/Agent Island.app/Contents/Resources/\(sharedBridgeName)",
            "/Applications/AgentIsland.app/Contents/Resources/\(sharedBridgeName)"
        ]
        for path in appInstallPaths where fileManager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let cwd = fileManager.currentDirectoryPath
        let candidates = [
            "\(cwd)/bridge-rs/target/release/\(sharedBridgeName)",
            "\(cwd)/target/release/\(sharedBridgeName)",
            "\(cwd)/bridge-rs/target/release/agent-island-bridge",
            "\(cwd)/target/release/agent-island-bridge"
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return nil
    }

    func requiredRustBridgeSourceURL() throws -> URL {
        guard let url = preferredRustBridgeSourceURL() else {
            throw AgentBridgeDistributionError.missingSource
        }
        if !fileManager.isReadableFile(atPath: url.path) {
            throw AgentBridgeDistributionError.invalidSource(url.path)
        }
        return url
    }

    func ensureSharedBridgeInstalled() throws {
        do {
            try ensureDirectory(at: installRoot, label: "install root")
            try ensureDirectory(at: sharedHooksDir, label: "hooks directory")
            try ensureDirectory(at: bridgeProfilesDir, label: "bridge profiles directory")
        } catch {
            throw AgentBridgeDistributionError.cannotCreateDirectory(installRoot.path)
        }

        let bridgeURL = sharedHooksDir.appendingPathComponent(sharedBridgeName)
        let rustBridge = try requiredRustBridgeSourceURL()
        let sourcePath = rustBridge.standardizedFileURL.path
        let targetPath = bridgeURL.standardizedFileURL.path
        print("Agent bridge source: \(sourcePath)")
        print("Agent bridge target: \(targetPath)")

        if sourcePath == targetPath {
            print("Bridge source already points to shared hooks path, skipping copy")
        } else {
            if fileManager.fileExists(atPath: targetPath) {
                try? fileManager.removeItem(at: bridgeURL)
            }
            do {
                try fileManager.copyItem(at: rustBridge, to: bridgeURL)
            } catch {
                print("Failed copying bridge binary: \(error)")
                throw AgentBridgeDistributionError.copyFailed(targetPath)
            }
        }

        do {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetPath)
        } catch {
            print("Failed to set executable bit for bridge: \(error)")
            throw AgentBridgeDistributionError.copyFailed(targetPath)
        }

        guard fileManager.fileExists(atPath: targetPath) else {
            throw AgentBridgeDistributionError.copyFailed(targetPath)
        }
        guard fileManager.isExecutableFile(atPath: targetPath) else {
            throw AgentBridgeDistributionError.notExecutable(targetPath)
        }

        removeLegacyBridgeArtifacts()
    }

    func ensureDirectory(at directoryURL: URL, label: String) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
            try fileManager.removeItem(at: directoryURL)
        }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            print("Failed creating \(label) at: \(directoryURL.path), error: \(error)")
            throw error
        }
    }

    func removeLegacyBridgeArtifacts() {
        let legacyArtifacts = [
            "multi-agent-bridge.sh",
            "bridge-common.sh",
            "bridge-adapter-codex.sh",
            "bridge-adapter-gemini.sh"
        ]

        for artifact in legacyArtifacts {
            try? fileManager.removeItem(at: sharedHooksDir.appendingPathComponent(artifact))
        }
    }

    func bridgeProfilePath(for agent: AgentPlatform) -> URL {
        bridgeProfilesDir.appendingPathComponent("\(agent.rawValue).json")
    }

    func writeBridgeProfile(_ profile: AgentBridgeProfile, for agent: AgentPlatform) throws {
        try fileManager.createDirectory(at: bridgeProfilesDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profile)
        try data.write(to: bridgeProfilePath(for: agent))
    }

    func removeBridgeProfile(for agent: AgentPlatform) {
        try? fileManager.removeItem(at: bridgeProfilePath(for: agent))
    }

    func readJSON(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return existing
    }

    func writeJSON(_ json: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    func fileContains(_ url: URL, needle: String) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return content.contains(needle)
    }

    func binaryExists(_ name: String) -> Bool {
        let candidatePaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(homeDirectory.path)/.local/bin/\(name)",
            "\(homeDirectory.path)/.cargo/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        return candidatePaths.contains { fileManager.fileExists(atPath: $0) }
    }

    var installedBridgeURL: URL {
        sharedHooksDir.appendingPathComponent(sharedBridgeName)
    }

    func commandHook(
        command: String,
        name: String? = nil,
        timeout: Int? = nil
    ) -> [String: Any] {
        var hook: [String: Any] = [
            "type": "command",
            "command": command
        ]

        if let name {
            hook["name"] = name
        }

        if let timeout {
            hook["timeout"] = timeout
        }

        return hook
    }

    func hookGroup(
        matcher: String? = nil,
        hooks: [[String: Any]]
    ) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": hooks
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    func writeDerivedBridgeProfile(for plugin: any AgentHookPlugin) throws {
        guard let baseProfile = plugin.capabilities.bridgeProfile else { return }
        try writeBridgeProfile(
            AgentBridgeProfile(
                agentType: plugin.agentType.rawValue,
                responseMode: baseProfile.responseMode,
                approvalTools: baseProfile.approvalTools,
                approvalCommandPatterns: baseProfile.approvalCommandPatterns
            ),
            for: plugin.agentType
        )
    }
}

enum AgentHookHealth: Sendable {
    case installed
    case disabled
    case needsRepair
    case unavailable
}

enum AgentHookInstallError: LocalizedError {
    case pluginUnavailable
    case pluginNotFound

    var errorDescription: String? {
        switch self {
        case .pluginUnavailable:
            return "Plugin is not available in current environment"
        case .pluginNotFound:
            return "Plugin is not registered"
        }
    }
}

struct AgentHookDiagnostic: Sendable {
    let health: AgentHookHealth
    let detail: String?
    let expectedLocation: String?

    var showsWarning: Bool {
        health == .needsRepair
    }
}

private enum AgentHookIssue: String {
    case missingBridge = "Missing bridge binary"
    case missingConfig = "Hooks config missing"
    case incompleteConfig = "Hooks config incomplete"
    case featureFlagDisabled = "Hooks feature disabled"
}

extension AgentHookPlugin {
    func diagnose(in context: HookPluginContext) -> AgentHookDiagnostic {
        let available = isAvailable(in: context)
        let installed = isInstalled(in: context)

        if !available {
            return AgentHookDiagnostic(
                health: .unavailable,
                detail: nil,
                expectedLocation: nil
            )
        }

        if installed {
            return AgentHookDiagnostic(
                health: .installed,
                detail: nil,
                expectedLocation: nil
            )
        }

        return AgentHookDiagnostic(
            health: .disabled,
            detail: nil,
            expectedLocation: nil
        )
    }
}

final class AgentHookPluginManager {
    static let shared = AgentHookPluginManager()

    private let context = HookPluginContext()
    private let defaults = UserDefaults.standard
    private let enabledPreferencePrefix = "agent_hooks_enabled_"
    private let plugins: [any AgentHookPlugin] = [
        ClaudeHookPlugin(),
        CodexHookPlugin(),
        GeminiHookPlugin()
    ]

    private init() {}

    @discardableResult
    func ensureBridgeBinaryAvailable() -> Error? {
        do {
            try context.ensureSharedBridgeInstalled()
            return nil
        } catch {
            print("Failed to preinstall bridge binary: \(error)")
            return error
        }
    }

    func installAll() {
        for plugin in plugins where plugin.isAvailable(in: context) && isEnabled(agentType: plugin.agentType) {
            do {
                try plugin.install(in: context)
            } catch {
                print("Failed to install \(plugin.agentType.displayName) hooks: \(error)")
            }
        }
    }

    @discardableResult
    func install(agentType: AgentPlatform) -> Error? {
        guard let plugin = plugin(for: agentType) else { return AgentHookInstallError.pluginNotFound }
        guard plugin.isAvailable(in: context) else { return AgentHookInstallError.pluginUnavailable }
        setEnabled(true, for: agentType)
        do {
            try plugin.install(in: context)
            return nil
        } catch {
            print("Failed to install \(plugin.agentType.displayName) hooks: \(error)")
            return error
        }
        return nil
    }

    func uninstallAll() {
        for plugin in plugins {
            do {
                try plugin.uninstall(in: context)
            } catch {
                print("Failed to uninstall \(plugin.agentType.displayName) hooks: \(error)")
            }
        }

        try? context.fileManager.removeItem(at: context.sharedHooksDir)
    }

    func uninstall(agentType: AgentPlatform) {
        guard let plugin = plugin(for: agentType) else { return }
        setEnabled(false, for: agentType)
        do {
            try plugin.uninstall(in: context)
        } catch {
            print("Failed to uninstall \(plugin.agentType.displayName) hooks: \(error)")
        }
    }

    func isEnabled(agentType: AgentPlatform) -> Bool {
        let key = enabledPreferenceKey(for: agentType)
        if defaults.object(forKey: key) == nil {
            return true
        }
        return defaults.bool(forKey: key)
    }

    func isAnyInstalled() -> Bool {
        plugins.contains { $0.isInstalled(in: context) }
    }

    func pluginSummaries() -> [AgentHookPluginSummary] {
        plugins.map { plugin in
            AgentHookPluginSummary(
                agentType: plugin.agentType,
                isAvailable: plugin.isAvailable(in: context),
                isInstalled: plugin.isInstalled(in: context),
                isEnabled: isEnabled(agentType: plugin.agentType),
                capabilities: plugin.capabilities,
                diagnostic: plugin.diagnose(in: context)
            )
        }
    }

    private func plugin(for agentType: AgentPlatform) -> (any AgentHookPlugin)? {
        plugins.first { $0.agentType == agentType }
    }

    private func setEnabled(_ enabled: Bool, for agentType: AgentPlatform) {
        defaults.set(enabled, forKey: enabledPreferenceKey(for: agentType))
    }

    private func enabledPreferenceKey(for agentType: AgentPlatform) -> String {
        enabledPreferencePrefix + agentType.rawValue
    }
}

struct AgentHookPluginSummary: Sendable {
    let agentType: AgentPlatform
    let isAvailable: Bool
    let isInstalled: Bool
    let isEnabled: Bool
    let capabilities: AgentHookCapabilities
    let diagnostic: AgentHookDiagnostic
}

private struct ClaudeHookPlugin: AgentHookPlugin {
    let agentType: AgentPlatform = .claude
    let capabilities = AgentHookCapabilities(
        supportedEvents: [
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PermissionRequest",
            "Notification",
            "Stop",
            "SubagentStop",
            "SessionStart",
            "SessionEnd",
            "PreCompact"
        ],
        approvalTools: [],
        approvalCommandPatterns: [],
        responseMode: nil,
        permissionRequestSource: .nativeRequest,
        supportsPermissionDecisions: true,
        supportsConversationHistory: true
    )

    func isAvailable(in context: HookPluginContext) -> Bool {
        context.fileManager.fileExists(atPath: context.homeDirectory.appendingPathComponent(".claude").path)
            || context.binaryExists("claude")
    }

    func install(in context: HookPluginContext) throws {
        let claudeDir = context.homeDirectory.appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try context.fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        try context.ensureSharedBridgeInstalled()
        context.removeLegacyBridgeArtifacts()
        try? context.fileManager.removeItem(at: hooksDir.appendingPathComponent("agent-island-state.py"))

        var json = context.readJSON(at: settings)
        let command = context.bridgeCommand(for: .claude)

        let hookEntry = [context.commandHook(command: command)]
        let hookEntryWithTimeout = [context.commandHook(command: command, timeout: 86400)]
        let withMatcher = [context.hookGroup(matcher: "*", hooks: hookEntry)]
        let withMatcherAndTimeout = [context.hookGroup(matcher: "*", hooks: hookEntryWithTimeout)]
        let withoutMatcher = [context.hookGroup(hooks: hookEntry)]
        let preCompactConfig: [[String: Any]] = [
            context.hookGroup(matcher: "auto", hooks: hookEntry),
            context.hookGroup(matcher: "manual", hooks: hookEntry)
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig)
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                existingEvent.removeAll { entry in
                    guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                    return entryHooks.contains { hook in
                        let command = hook["command"] as? String ?? ""
                        return command.contains("agent-island-state.py") || command.contains(context.sharedBridgeName)
                    }
                }

                existingEvent.append(contentsOf: config)
                hooks[event] = existingEvent
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks
        try context.writeJSON(json, to: settings)
    }

    func uninstall(in context: HookPluginContext) throws {
        let claudeDir = context.homeDirectory.appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("agent-island-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? context.fileManager.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { hook in
                    let command = hook["command"] as? String ?? ""
                    return command.contains("agent-island-state.py") || command.contains(context.sharedBridgeName)
                }
            }

            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        try? context.writeJSON(json, to: settings)
    }

    func isInstalled(in context: HookPluginContext) -> Bool {
        let settings = context.homeDirectory.appendingPathComponent(".claude/settings.json")
        return context.fileContains(settings, needle: context.sharedBridgeName)
    }

    func diagnose(in context: HookPluginContext) -> AgentHookDiagnostic {
        let claudeDir = context.homeDirectory.appendingPathComponent(".claude")
        let settings = claudeDir.appendingPathComponent("settings.json")
        let bridgeExists = context.fileManager.fileExists(atPath: context.installedBridgeURL.path)
        let hasBridgeConfig = context.fileContains(settings, needle: context.sharedBridgeName)

        guard isAvailable(in: context) else {
            return AgentHookDiagnostic(health: .unavailable, detail: nil, expectedLocation: claudeDir.path)
        }

        if hasBridgeConfig && bridgeExists {
            return AgentHookDiagnostic(health: .installed, detail: nil, expectedLocation: settings.path)
        }

        if hasBridgeConfig && !bridgeExists {
            return AgentHookDiagnostic(
                health: .needsRepair,
                detail: AgentHookIssue.missingBridge.rawValue,
                expectedLocation: context.installedBridgeURL.path
            )
        }

        return AgentHookDiagnostic(health: .disabled, detail: nil, expectedLocation: settings.path)
    }
}

private struct CodexHookPlugin: AgentHookPlugin {
    let agentType: AgentPlatform = .codex
    let capabilities = AgentHookCapabilities(
        supportedEvents: [
            "SessionStart",
            "PreToolUse",
            "PostToolUse",
            "UserPromptSubmit",
            "Stop"
        ],
        approvalTools: [],
        approvalCommandPatterns: [
            #"(^|\s)(sudo|su)\b"#,
            #"(^|\s)(rm|mv|cp)\s+.*(/|~)"#,
            #"(^|\s)(chmod|chown|chgrp)\b"#,
            #"(^|\s)(kill|pkill|killall|launchctl)\b"#,
            #"(^|\s)(shutdown|reboot|halt)\b"#,
            #"(^|\s)(dd|mkfs|diskutil)\b"#
        ],
        responseMode: "codex",
        permissionRequestSource: .preToolUse,
        supportsPermissionDecisions: true,
        supportsConversationHistory: true
    )

    func isAvailable(in context: HookPluginContext) -> Bool {
        context.fileManager.fileExists(atPath: context.homeDirectory.appendingPathComponent(".codex").path)
            || context.binaryExists("codex")
    }

    func install(in context: HookPluginContext) throws {
        let codexDir = context.homeDirectory.appendingPathComponent(".codex")
        let hooksFile = codexDir.appendingPathComponent("hooks.json")
        let configFile = codexDir.appendingPathComponent("config.toml")

        try context.fileManager.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try context.ensureSharedBridgeInstalled()
        context.removeLegacyBridgeArtifacts()
        try enableCodexHooksFeature(configURL: configFile, context: context)
        try context.writeDerivedBridgeProfile(for: self)

        let standardHookCommand = context.commandHook(
            command: context.bridgeCommand(for: .codex),
            timeout: 5
        )
        let permissionHookCommand = context.commandHook(
            command: context.bridgeCommand(for: .codex),
            timeout: 300
        )

        let hooks: [String: Any] = [
            "hooks": [
                "SessionStart": [context.hookGroup(matcher: "startup|resume", hooks: [standardHookCommand])],
                "PreToolUse": [context.hookGroup(matcher: "Bash", hooks: [permissionHookCommand])],
                "PostToolUse": [context.hookGroup(matcher: "Bash", hooks: [standardHookCommand])],
                "UserPromptSubmit": [context.hookGroup(hooks: [standardHookCommand])],
                "Stop": [context.hookGroup(hooks: [standardHookCommand])]
            ]
        ]

        try context.writeJSON(hooks, to: hooksFile)
    }

    func uninstall(in context: HookPluginContext) throws {
        let hooksFile = context.homeDirectory.appendingPathComponent(".codex/hooks.json")
        try? context.fileManager.removeItem(at: hooksFile)
        context.removeBridgeProfile(for: agentType)
    }

    func isInstalled(in context: HookPluginContext) -> Bool {
        let hooksFile = context.homeDirectory.appendingPathComponent(".codex/hooks.json")
        return context.fileContains(hooksFile, needle: context.sharedBridgeName)
    }

    func diagnose(in context: HookPluginContext) -> AgentHookDiagnostic {
        let codexDir = context.homeDirectory.appendingPathComponent(".codex")
        let hooksFile = codexDir.appendingPathComponent("hooks.json")
        let configFile = codexDir.appendingPathComponent("config.toml")
        let bridgeExists = context.fileManager.fileExists(atPath: context.installedBridgeURL.path)
        let hasBridgeConfig = context.fileContains(hooksFile, needle: context.sharedBridgeName)
        let hooksFeatureEnabled = context.fileContains(configFile, needle: "codex_hooks = true")

        guard isAvailable(in: context) else {
            return AgentHookDiagnostic(health: .unavailable, detail: nil, expectedLocation: codexDir.path)
        }

        if hasBridgeConfig && hooksFeatureEnabled && bridgeExists {
            return AgentHookDiagnostic(health: .installed, detail: nil, expectedLocation: hooksFile.path)
        }

        if hasBridgeConfig || hooksFeatureEnabled {
            let detail: String
            if !bridgeExists {
                detail = AgentHookIssue.missingBridge.rawValue
            } else if !hooksFeatureEnabled {
                detail = AgentHookIssue.featureFlagDisabled.rawValue
            } else {
                detail = AgentHookIssue.incompleteConfig.rawValue
            }

            return AgentHookDiagnostic(
                health: .needsRepair,
                detail: detail,
                expectedLocation: hooksFile.path
            )
        }

        return AgentHookDiagnostic(health: .disabled, detail: nil, expectedLocation: hooksFile.path)
    }

    private func enableCodexHooksFeature(configURL: URL, context: HookPluginContext) throws {
        try context.fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var content = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if content.contains("codex_hooks = true") {
            return
        }

        if content.contains("codex_hooks = false") {
            content = content.replacingOccurrences(of: "codex_hooks = false", with: "codex_hooks = true")
        } else if content.contains("[features]") {
            content = content.replacingOccurrences(of: "[features]", with: "[features]\ncodex_hooks = true")
        } else {
            if !content.isEmpty && !content.hasSuffix("\n") {
                content.append("\n")
            }
            content.append("[features]\ncodex_hooks = true\n")
        }

        try content.write(to: configURL, atomically: true, encoding: .utf8)
    }
}

private struct GeminiHookPlugin: AgentHookPlugin {
    let agentType: AgentPlatform = .gemini
    let capabilities = AgentHookCapabilities(
        supportedEvents: [
            "BeforeTool",
            "AfterTool",
            "SessionStart",
            "SessionEnd",
            "Notification"
        ],
        approvalTools: [
            "run_shell_command",
            "write_file",
            "replace",
            "delete_file",
            "run_shell_script"
        ],
        approvalCommandPatterns: [],
        responseMode: "gemini",
        permissionRequestSource: .preToolUse,
        supportsPermissionDecisions: true,
        supportsConversationHistory: false
    )

    func isAvailable(in context: HookPluginContext) -> Bool {
        context.fileManager.fileExists(atPath: context.homeDirectory.appendingPathComponent(".gemini").path)
            || context.binaryExists("gemini")
    }

    func install(in context: HookPluginContext) throws {
        let geminiDir = context.homeDirectory.appendingPathComponent(".gemini")
        let settings = geminiDir.appendingPathComponent("settings.json")

        try context.fileManager.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try context.ensureSharedBridgeInstalled()
        context.removeLegacyBridgeArtifacts()
        try context.writeDerivedBridgeProfile(for: self)

        var json = context.readJSON(at: settings)
        let hook = context.commandHook(
            command: context.bridgeCommand(for: .gemini),
            name: "agent-island-gemini-bridge",
            timeout: 5000
        )

        let installedHooks: [String: Any] = [
            "BeforeTool": [context.hookGroup(matcher: "", hooks: [hook])],
            "AfterTool": [context.hookGroup(matcher: "", hooks: [hook])],
            "SessionStart": [context.hookGroup(hooks: [hook])],
            "SessionEnd": [context.hookGroup(hooks: [hook])],
            "Notification": [context.hookGroup(hooks: [hook])]
        ]
        json["hooks"] = installedHooks
        json["hooksConfig"] = [
            "enabled": true,
            "hooks": installedHooks
        ]

        try context.writeJSON(json, to: settings)
    }

    func uninstall(in context: HookPluginContext) throws {
        let settings = context.homeDirectory.appendingPathComponent(".gemini/settings.json")
        guard var json = try? JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] else {
            context.removeBridgeProfile(for: agentType)
            return
        }

        json.removeValue(forKey: "hooks")
        json.removeValue(forKey: "hooksConfig")
        try? context.writeJSON(json, to: settings)
        context.removeBridgeProfile(for: agentType)
    }

    func isInstalled(in context: HookPluginContext) -> Bool {
        let settings = context.homeDirectory.appendingPathComponent(".gemini/settings.json")
        return context.fileContains(settings, needle: context.sharedBridgeName)
    }

    func diagnose(in context: HookPluginContext) -> AgentHookDiagnostic {
        let geminiDir = context.homeDirectory.appendingPathComponent(".gemini")
        let settings = geminiDir.appendingPathComponent("settings.json")
        let bridgeExists = context.fileManager.fileExists(atPath: context.installedBridgeURL.path)
        let hasBridgeConfig = context.fileContains(settings, needle: context.sharedBridgeName)
        let hasTopLevelHooks = context.fileContains(settings, needle: "\"hooks\"")

        guard isAvailable(in: context) else {
            return AgentHookDiagnostic(health: .unavailable, detail: nil, expectedLocation: geminiDir.path)
        }

        if hasBridgeConfig && bridgeExists {
            return AgentHookDiagnostic(health: .installed, detail: nil, expectedLocation: settings.path)
        }

        if hasBridgeConfig || hasTopLevelHooks {
            let detail = bridgeExists
                ? AgentHookIssue.incompleteConfig.rawValue
                : AgentHookIssue.missingBridge.rawValue
            return AgentHookDiagnostic(
                health: .needsRepair,
                detail: detail,
                expectedLocation: settings.path
            )
        }

        return AgentHookDiagnostic(health: .disabled, detail: nil, expectedLocation: settings.path)
    }
}
