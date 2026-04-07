//
//  HookInstaller.swift
//  Agent Island
//
//  Facade over the agent hook plugin registry.
//

import Foundation

struct HookInstaller {
    static func installIfNeeded() {
        _ = AgentHookPluginManager.shared.ensureBridgeBinaryAvailable()
        AgentHookPluginManager.shared.installAll()
    }

    static func isInstalled() -> Bool {
        AgentHookPluginManager.shared.isAnyInstalled()
    }

    static func uninstall() {
        AgentHookPluginManager.shared.uninstallAll()
    }
}
