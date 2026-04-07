//
//  NotchHeaderView.swift
//  Agent Island
//
//  Header bar for the dynamic island
//

import Combine
import SwiftUI

struct IslandMarkIcon: View {
    let size: CGFloat
    let color: Color
    let agentType: AgentPlatform
    var animateLegs: Bool = false

    @State private var legPhase: Int = 0

    // Timer for leg animation
    private let legTimer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    init(size: CGFloat = 18, color: Color? = nil, agentType: AgentPlatform = .claude, animateLegs: Bool = false) {
        self.size = size
        self.color = color ?? agentType.accentColor
        self.agentType = agentType
        self.animateLegs = animateLegs
    }

    var body: some View {
        Canvas { context, canvasSize in
            let iconViewport: CGFloat = 30
            let scale = size / iconViewport
            let xOffset = (canvasSize.width - iconViewport * scale) / 2
            let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0)

            let bodyRect = CGRect(x: 4, y: 8, width: 22, height: 20)
            let chestRect = CGRect(x: 10, y: 12, width: 10, height: 8)
            let faceRect = CGRect(x: 10, y: 14, width: 10, height: 7)
            let leftEye = CGRect(x: 12, y: 16, width: 2, height: 2)
            let rightEye = CGRect(x: 18, y: 16, width: 2, height: 2)
            let leftAntenna = CGRect(x: 5, y: 3, width: 2, height: 6)
            let rightAntenna = CGRect(x: 18, y: 3, width: 2, height: 6)
            let leftDot = CGRect(x: 5, y: 2, width: 2, height: 2)
            let rightDot = CGRect(x: 18, y: 2, width: 2, height: 2)
            let bootRects: [CGRect] = [
                CGRect(x: 7, y: 28, width: 2, height: 2),
                CGRect(x: 11, y: 28, width: 2, height: 2),
                CGRect(x: 16, y: 28, width: 2, height: 2),
                CGRect(x: 20, y: 28, width: 2, height: 2),
            ]
            let armRects: [CGRect] = [
                CGRect(x: 0, y: 14, width: 4, height: 2),
                CGRect(x: 26, y: 14, width: 4, height: 2),
                CGRect(x: 0, y: 19, width: 4, height: 2),
                CGRect(x: 26, y: 19, width: 4, height: 2),
            ]

            let walkCycle: [[CGFloat]] = [
                [-2, -1.5, 2, 1.5],
                [0, 0, 0, 0],
                [2, 1.5, -2, -1.5],
                [0, 0, 0, 0],
            ]
            let currentOffset = animateLegs ? walkCycle[legPhase % walkCycle.count] : [CGFloat](repeating: 0, count: 4)
            let bodyLift: CGFloat = animateLegs ? (legPhase % 2 == 0 ? -1 : 0) : 0

            // Base body
            var body = bodyRect
            body.origin.y += bodyLift
            context.fill(Path(body).applying(transform), with: .color(color))
            context.fill(Path(chestRect).applying(transform), with: .color(.black.opacity(0.22)))
            context.fill(Path(faceRect).applying(transform), with: .color(color.opacity(0.15)))

            // Face and eyes
            context.fill(Path(ellipseIn: CGRect(x: 6, y: 14, width: 6, height: 3).applying(transform)), with: .color(.black.opacity(0.24)))
            context.fill(Path(leftEye).applying(transform), with: .color(.black))
            context.fill(Path(rightEye).applying(transform), with: .color(.black))

            // Antennae + tips
            context.fill(Path(roundedRect: leftAntenna, cornerSize: CGSize(width: 0.5, height: 0.5)).applying(transform), with: .color(color))
            context.fill(Path(roundedRect: rightAntenna, cornerSize: CGSize(width: 0.5, height: 0.5)).applying(transform), with: .color(color))
            context.fill(Path(ellipseIn: leftDot).applying(transform), with: .color(activeColor(isAlert: hasAlertState())))
            context.fill(Path(ellipseIn: rightDot).applying(transform), with: .color(activeColor(isAlert: hasAlertState())))

            // Arms
            for (i, arm) in armRects.enumerated() {
                var movingArm = arm
                if animateLegs {
                    movingArm.origin.y += (i % 2 == 0 ? 1 : -1) * (legPhase % 2 == 0 ? 0.8 : 0)
                }
                context.fill(
                    Path(roundedRect: movingArm, cornerSize: CGSize(width: 0.8, height: 0.8)).applying(transform),
                    with: .color(color.opacity(0.85))
                )
            }

            // Feet / stance animated by processing flag
            for (i, boot) in bootRects.enumerated() {
                let offsetY = currentOffset[min(i, 3)] * 2.0
                var movingBoot = boot
                movingBoot.origin.y += offsetY
                context.fill(Path(roundedRect: movingBoot, cornerSize: CGSize(width: 0.6, height: 0.6)).applying(transform), with: .color(color.opacity(0.65)))
            }
        }
        .frame(width: size, height: size)
        .onReceive(legTimer) { _ in
            if animateLegs {
                legPhase = (legPhase + 1) % 4
            }
        }
    }

    private func hasAlertState() -> Bool {
        animateLegs || legPhase != 0
    }

    private func activeColor(isAlert: Bool) -> Color {
        isAlert ? .red : .yellow
    }
}

// Pixel art permission indicator icon
struct PermissionIndicatorIcon: View {
    let size: CGFloat
    let color: Color
    let agentType: AgentPlatform

    init(size: CGFloat = 14, color: Color? = nil, agentType: AgentPlatform = .claude) {
        self.size = size
        self.color = color ?? agentType.accentColor
        self.agentType = agentType
    }

    // Visible pixel positions from the SVG (at 30x30 scale)
    private let pixels: [(CGFloat, CGFloat)] = [
        (7, 7), (7, 11),           // Left column
        (11, 3),                    // Top left
        (15, 3), (15, 19), (15, 27), // Center column
        (19, 3), (19, 15),          // Right of center
        (23, 7), (23, 11)           // Right column
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale

            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}

// Pixel art "ready for input" indicator icon (checkmark/done shape)
struct ReadyForInputIndicatorIcon: View {
    let size: CGFloat
    let color: Color
    let agentType: AgentPlatform

    init(size: CGFloat = 14, color: Color? = nil, agentType: AgentPlatform = .claude) {
        self.size = size
        self.color = color ?? agentType.accentColor
        self.agentType = agentType
    }

    // Checkmark shape pixel positions (at 30x30 scale)
    private let pixels: [(CGFloat, CGFloat)] = [
        (5, 15),                    // Start of checkmark
        (9, 19),                    // Down stroke
        (13, 23),                   // Bottom of checkmark
        (17, 19),                   // Up stroke begins
        (21, 15),                   // Up stroke
        (25, 11),                   // Up stroke
        (29, 7)                     // End of checkmark
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale

            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}
