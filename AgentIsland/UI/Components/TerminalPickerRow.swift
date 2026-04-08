//
//  TerminalPickerRow.swift
//  Agent Island
//
//  Terminal backend selection picker for settings menu
//

import SwiftUI

struct TerminalPickerRow: View {
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var selectedBackend: TerminalBackend = AppSettings.terminalBackend

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(agentIcon: "terminal")
                        .font(.system(size: 12))
                        .foregroundStyle(textColor)
                        .frame(width: 16)

                    Text("Terminal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textColor)

                    Spacer()

                    Text(selectedBackend.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)

                    Image(agentIcon: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
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

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(TerminalBackend.allCases, id: \.self) { backend in
                        TerminalOptionRow(
                            label: backend.displayName,
                            isSelected: selectedBackend == backend
                        ) {
                            selectedBackend = backend
                            AppSettings.terminalBackend = backend
                            Task {
                                try? await Task.sleep(for: .seconds(0.3))
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isExpanded = false
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
        .onAppear {
            selectedBackend = AppSettings.terminalBackend
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}
