import AppKit
import IkiNotchCore
import SwiftUI

/// Non-activating borderless panel floating cleanly above the menu bar.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }

    func setAllowInFullscreen(_ allow: Bool) {
        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]
        if allow {
            behavior.insert(.fullScreenAuxiliary)
        }
        if collectionBehavior != behavior {
            collectionBehavior = behavior
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Custom NSHostingView that uses a system-managed NSTrackingArea (0% idle CPU)
/// restricted strictly to the visible notch rect and lets clicks on transparent margins pass through.
final class NotchHostView<Content: View>: NSHostingView<Content> {
    var onMouseEnteredNotch: (() -> Void)?
    var onMouseExitedNotch: (() -> Void)?
    var activeNotchSize: CGSize = CGSize(width: 210, height: 31) {
        didSet {
            if oldValue != activeNotchSize {
                updateTrackingAreas()
            }
        }
    }

    private var notchTrackingArea: NSTrackingArea?

    private var activeNotchRect: NSRect {
        let width = min(activeNotchSize.width, bounds.width)
        let height = min(activeNotchSize.height, bounds.height)
        let originX = ((bounds.width - width) / 2.0).rounded()
        // In AppKit's default (non-flipped) coordinates, top edge is bounds.maxY
        let originY = isFlipped ? 0 : (bounds.height - height)
        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private var isMouseCurrentlyInsideActiveNotch: Bool {
        guard let window else { return false }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = convert(windowPoint, from: nil)
        return activeNotchRect.contains(localPoint)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = notchTrackingArea {
            removeTrackingArea(existing)
        }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if isMouseCurrentlyInsideActiveNotch {
            options.insert(.assumeInside)
        }
        let area = NSTrackingArea(
            rect: activeNotchRect,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        notchTrackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeNotchRect.contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEnteredNotch?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Ignore synthetic exit events fired while resizing the panel/tracking area if cursor is still inside
        if isMouseCurrentlyInsideActiveNotch {
            return
        }
        onMouseExitedNotch?()
    }
}
