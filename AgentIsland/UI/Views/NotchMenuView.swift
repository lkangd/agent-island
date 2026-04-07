//
//  NotchMenuView.swift
//  Agent Island
//
//  Minimal menu matching Dynamic Island aesthetic
//

import ApplicationServices
import Combine
import SwiftUI
import ServiceManagement
import Sparkle

// MARK: - NotchMenuView

struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var soundSelector = SoundSelector.shared
    @State private var launchAtLogin: Bool = false
    @State private var pluginSummaries: [AgentHookPluginSummary] = []
    @State private var approvalRules: [ApprovalRule] = []
    @State private var hookActionMessage: String? = nil
    @State private var hookActionIsError = false

    var body: some View {
        VStack(spacing: 4) {
            // Back button
            MenuRow(
                icon: "chevron.left",
                label: "Back"
            ) {
                viewModel.toggleMenu()
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            if let message = hookActionMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(hookActionIsError ? TerminalColors.amber : TerminalColors.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }

            // Appearance settings
            ScreenPickerRow(screenSelector: screenSelector)
            SoundPickerRow(soundSelector: soundSelector)

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // System settings
            MenuToggleRow(
                icon: "power",
                label: "Launch at Login",
                isOn: launchAtLogin
            ) {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.unregister()
                        launchAtLogin = false
                    } else {
                        try SMAppService.mainApp.register()
                        launchAtLogin = true
                    }
                } catch {
                    print("Failed to toggle launch at login: \(error)")
                }
            }

            if !pluginSummaries.isEmpty {
                AgentPluginsSection(
                    summaries: pluginSummaries,
                    onToggle: { summary in
                        togglePlugin(summary)
                    },
                    onRepair: { summary in
                        repairPlugin(summary)
                    }
                )
            }

            if !approvalRules.isEmpty {
                ApprovalRulesSection(
                    rules: approvalRules,
                    onDelete: { rule in
                        deleteApprovalRule(rule)
                    }
                )
            }

            AccessibilityRow(isEnabled: AXIsProcessTrusted())

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // About
            UpdateRow(updateManager: updateManager)

            MenuRow(
                icon: "star",
                label: "Star on GitHub"
            ) {
                if let url = URL(string: "https://github.com/javen-yan/agent-island") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            MenuRow(
                icon: "xmark.circle",
                label: "Quit",
                isDestructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            refreshStates()
        }
        .onChange(of: viewModel.contentType) { _, newValue in
            if newValue == .menu {
                refreshStates()
            }
        }
    }

    private func refreshStates() {
        pluginSummaries = AgentHookPluginManager.shared.pluginSummaries()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        screenSelector.refreshScreens()
        Task {
            let rules = await ApprovalPolicyStore.shared.allRules()
            await MainActor.run {
                approvalRules = rules
            }
        }
    }

    private func togglePlugin(_ summary: AgentHookPluginSummary) {
        guard summary.isAvailable else { return }

        if summary.isEnabled {
            AgentHookPluginManager.shared.uninstall(agentType: summary.agentType)
            showHookAction("Disabled \(summary.agentType.displayName)")
        } else {
            if let err = AgentHookPluginManager.shared.install(agentType: summary.agentType) {
                showHookAction("Failed to install \(summary.agentType.displayName): \(err.localizedDescription)", isError: true)
            } else {
                showHookAction("Installed \(summary.agentType.displayName)")
            }
        }

        refreshStates()
    }

    private func repairPlugin(_ summary: AgentHookPluginSummary) {
        guard summary.isAvailable else { return }

        if let err = AgentHookPluginManager.shared.repair(agentType: summary.agentType) {
            showHookAction("Repair failed for \(summary.agentType.displayName): \(err.localizedDescription)", isError: true)
        } else {
            showHookAction("Repaired \(summary.agentType.displayName)")
        }

        refreshStates()
    }

    private func showHookAction(_ message: String, isError: Bool = false) {
        hookActionMessage = message
        hookActionIsError = isError
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if hookActionMessage == message {
                    hookActionMessage = nil
                }
            }
        }
    }

    private func deleteApprovalRule(_ rule: ApprovalRule) {
        Task {
            await ApprovalPolicyStore.shared.removeRule(id: rule.id)
            let rules = await ApprovalPolicyStore.shared.allRules()
            await MainActor.run {
                approvalRules = rules
            }
        }
    }
}

// MARK: - Update Row

struct UpdateRow: View {
    @ObservedObject var updateManager: UpdateManager
    @State private var isHovered = false
    @State private var isSpinning = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    if case .installing = updateManager.state {
                        Image(agentIcon: "gear")
                            .font(.system(size: 12))
                            .foregroundColor(TerminalColors.blue)
                            .rotationEffect(.degrees(isSpinning ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                            .onAppear { isSpinning = true }
                    } else {
                        Image(agentIcon: icon)
                            .font(.system(size: 12))
                            .foregroundColor(iconColor)
                    }
                }
                .frame(width: 16)

                // Label
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(labelColor)

                Spacer()

                // Right side: progress or status
                rightContent
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered && isInteractive ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: updateManager.state)
    }

    // MARK: - Right Content

    @ViewBuilder
    private var rightContent: some View {
        switch updateManager.state {
        case .idle:
            Text(appVersion)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))

        case .upToDate:
            HStack(spacing: 6) {
                Image(agentIcon: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(TerminalColors.green)
                Text("Up to date")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .checking, .installing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)

        case .found(let version, _):
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("v\(version)")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(TerminalColors.blue)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.blue)
                    .frame(width: 32, alignment: .trailing)
            }

        case .extracting(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(TerminalColors.amber)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.amber)
                    .frame(width: 32, alignment: .trailing)
            }

        case .readyToInstall(let version):
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("v\(version)")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .error:
            Text("Retry")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Computed Properties

    private var icon: String {
        switch updateManager.state {
        case .idle:
            return "arrow.down.circle"
        case .checking:
            return "arrow.down.circle"
        case .upToDate:
            return "checkmark.circle.fill"
        case .found:
            return "arrow.down.circle.fill"
        case .downloading:
            return "arrow.down.circle"
        case .extracting:
            return "doc.zipper"
        case .readyToInstall:
            return "checkmark.circle.fill"
        case .installing:
            return "gear"
        case .error:
            return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        switch updateManager.state {
        case .idle:
            return .white.opacity(isHovered ? 1.0 : 0.7)
        case .checking:
            return .white.opacity(0.7)
        case .upToDate:
            return TerminalColors.green
        case .found, .readyToInstall:
            return TerminalColors.green
        case .downloading:
            return TerminalColors.blue
        case .extracting:
            return TerminalColors.amber
        case .installing:
            return TerminalColors.blue
        case .error:
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private var label: String {
        switch updateManager.state {
        case .idle:
            return "Check for Updates"
        case .checking:
            return "Checking..."
        case .upToDate:
            return "Check for Updates"
        case .found:
            return "Download Update"
        case .downloading:
            return "Downloading..."
        case .extracting:
            return "Extracting..."
        case .readyToInstall:
            return "Install & Relaunch"
        case .installing:
            return "Installing..."
        case .error:
            return "Update failed"
        }
    }

    private var labelColor: Color {
        switch updateManager.state {
        case .idle, .upToDate:
            return .white.opacity(isHovered ? 1.0 : 0.7)
        case .checking, .downloading, .extracting, .installing:
            return .white.opacity(0.9)
        case .found, .readyToInstall:
            return TerminalColors.green
        case .error:
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private var isInteractive: Bool {
        switch updateManager.state {
        case .idle, .upToDate, .found, .readyToInstall, .error:
            return true
        case .checking, .downloading, .extracting, .installing:
            return false
        }
    }

    // MARK: - Actions

    private func handleTap() {
        switch updateManager.state {
        case .idle, .upToDate, .error:
            updateManager.checkForUpdates()
        case .found:
            updateManager.downloadAndInstall()
        case .readyToInstall:
            updateManager.installAndRelaunch()
        default:
            break
        }
    }
}

// MARK: - Accessibility Permission Row

struct AccessibilityRow: View {
    let isEnabled: Bool

    @State private var isHovered = false
    @State private var refreshTrigger = false

    private var currentlyEnabled: Bool {
        // Re-check on each render when refreshTrigger changes
        _ = refreshTrigger
        return isEnabled
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(agentIcon: "hand.raised")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text("Accessibility")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            if isEnabled {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)

                Text("On")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Button(action: openAccessibilitySettings) {
                    Text("Enable")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTrigger.toggle()
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AgentPluginsSection: View {
    let summaries: [AgentHookPluginSummary]
    let onToggle: (AgentHookPluginSummary) -> Void
    let onRepair: (AgentHookPluginSummary) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Detected Agents")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(summaries, id: \.agentType.rawValue) { summary in
                AgentPluginRow(
                    summary: summary,
                    onToggle: { onToggle(summary) },
                    onRepair: { onRepair(summary) }
                )
            }
        }
    }
}

struct AgentPluginRow: View {
    let summary: AgentHookPluginSummary
    let onToggle: () -> Void
    let onRepair: () -> Void

    @State private var isHovered = false

    private var statusText: String {
        switch summary.diagnostic.health {
        case .installed:
            return "Installed"
        case .disabled:
            return "Disabled"
        case .needsRepair:
            return "Needs Repair"
        case .unavailable:
            return "Not found"
        }
    }

    private var statusColor: Color {
        switch summary.diagnostic.health {
        case .installed:
            return TerminalColors.green
        case .disabled:
            return .white.opacity(0.5)
        case .needsRepair:
            return TerminalColors.amber
        case .unavailable:
            return .white.opacity(0.35)
        }
    }

    private var detailText: String {
        if let detail = summary.diagnostic.detail {
            return detail
        }

        var parts: [String] = []
        if summary.capabilities.supportsPermissionDecisions {
            parts.append("approval")
        }
        if summary.capabilities.supportsConversationHistory {
            parts.append("history")
        }
        if let responseMode = summary.capabilities.responseMode {
            parts.append(responseMode)
        }
        if parts.isEmpty {
            return "monitoring"
        }
        return parts.joined(separator: " · ")
    }

    private var locationText: String? {
        guard summary.diagnostic.health == .needsRepair || summary.diagnostic.health == .disabled else {
            return nil
        }
        return summary.diagnostic.expectedLocation
    }

    private var toggleIsOn: Bool {
        summary.isEnabled
    }

    private var toggleEnabled: Bool {
        summary.diagnostic.health != .unavailable
    }

    private var showsRepair: Bool {
        summary.diagnostic.health == .needsRepair
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(agentIcon: summary.agentType.iconSymbol)
                    .font(.system(size: 12))
                    .foregroundColor(summary.agentType.accentColor.opacity(0.95))
                    .frame(width: 16)

                if summary.diagnostic.showsWarning {
                    Image(agentIcon: "exclamationmark.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(TerminalColors.amber)
                        .background(Color.black.clipShape(Circle()))
                        .offset(x: 5, y: -3)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(summary.agentType.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))

                    Text(statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.14))
                        .clipShape(Capsule())
                }

                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)

                if let locationText {
                    Text(locationText)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.24))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if showsRepair {
                    Button(action: onRepair) {
                        Text("Repair")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(TerminalColors.amber)
                            )
                    }
                    .buttonStyle(.plain)
                }

                SwitchControl(
                    isOn: toggleIsOn,
                    isEnabled: toggleEnabled,
                    action: onToggle
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .onHover { isHovered = $0 }
    }
}

struct SwitchControl: View {
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            if isEnabled {
                action()
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(isEnabled ? (isOn ? TerminalColors.green : Color.white.opacity(0.16)) : Color.white.opacity(0.08))
                    .frame(width: 34, height: 20)

                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.5))
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct ApprovalRulesSection: View {
    let rules: [ApprovalRule]
    let onDelete: (ApprovalRule) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Approval Rules")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(rules) { rule in
                ApprovalRuleRow(rule: rule, onDelete: { onDelete(rule) })
            }
        }
    }
}

struct ApprovalRuleRow: View {
    let rule: ApprovalRule
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(agentIcon: rule.agentType.iconSymbol)
                .font(.system(size: 12))
                .foregroundColor(rule.agentType.accentColor.opacity(0.95))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.toolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))

                    Text(rule.policy.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(policyColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(policyColor.opacity(0.14))
                        .clipShape(Capsule())
                }

                Text("\(rule.agentType.displayName) · \(rule.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onDelete) {
                Image(agentIcon: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 28, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .onHover { isHovered = $0 }
    }

    private var policyColor: Color {
        switch rule.policy {
        case .deny:
            return .white.opacity(0.65)
        case .allowOnce:
            return TerminalColors.green
        case .allowAlways:
            return TerminalColors.amber
        case .autoExecute:
            return Color(red: 0.84, green: 0.30, blue: 0.24)
        }
    }
}

struct MenuRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(agentIcon: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        if isDestructive {
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
        return .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

struct MenuToggleRow: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(agentIcon: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                Circle()
                    .fill(isOn ? TerminalColors.green : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)

                Text(isOn ? "On" : "Off")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}
