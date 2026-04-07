//
//  NotchGeometry.swift
//  Agent Island
//
//  Geometry calculations for the notch
//

import CoreGraphics
import Foundation

/// Pure geometry calculations for the notch
struct NotchGeometry: Sendable {
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat

    private var openedPanelHorizontalPadding: CGFloat { 31 }
    private var openedPanelBottomPadding: CGFloat { 12 }
    private var openedPanelHitSlop: CGFloat { 8 }

    /// The notch rect in screen coordinates (for hit testing with global mouse position)
    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    /// The opened panel rect in screen coordinates for a given size
    func openedScreenRect(for size: CGSize) -> CGRect {
        // Match the actual rendered panel bounds in NotchView:
        // the opened container adds horizontal padding and a small bottom inset.
        let width = size.width + (openedPanelHorizontalPadding * 2)
        let height = size.height + openedPanelBottomPadding
        return CGRect(
            x: screenRect.midX - width / 2,
            y: screenRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// Check if a point is in the notch area (with padding for easier interaction)
    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }

    /// Check if a point is in the opened panel area
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size)
            .insetBy(dx: -openedPanelHitSlop, dy: -openedPanelHitSlop)
            .contains(point)
    }

    /// Check if a point is outside the opened panel (for closing)
    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !isPointInOpenedPanel(point, size: size)
    }
}
