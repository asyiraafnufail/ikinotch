import AppKit
import Combine
import Foundation

/// Central state coordinator for the virtual notch.
/// Designed for zero CPU usage when collapsed: no polling timers, monitors attached only while expanded.
public final class NotchController: ObservableObject {
    @Published public private(set) var displayState: NotchDisplayState = .collapsed
    @Published public private(set) var isLockedExpanded: Bool = false
    @Published public private(set) var useExpandedWindowBounds: Bool = false
    @Published public private(set) var isHovered: Bool = false
    @Published public var menuBarHeight: CGFloat = 25

    public let settings: NotchSettings
    public var onWindowGeometryUpdateNeeded: (() -> Void)?
    public var onOpenSettings: (() -> Void)?

    private var hoverWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var shrinkBoundsWorkItem: DispatchWorkItem?

    private var outsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?

    public init(settings: NotchSettings) {
        self.settings = settings
    }

    deinit {
        removeActiveMonitors()
    }

    // MARK: - Pointer & Click Events

    public func handleMouseEntered() {
        isHovered = true
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        shrinkBoundsWorkItem?.cancel()
        shrinkBoundsWorkItem = nil

        guard settings.triggerMode != .clickOnly else { return }
        guard displayState == .collapsed else { return }

        hoverWorkItem?.cancel()
        let delay = max(0.02, settings.hoverDelay)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isHovered, self.displayState == .collapsed else { return }
            self.transition(to: .expanded, locked: false)
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func handleMouseExited() {
        isHovered = false
        hoverWorkItem?.cancel()
        hoverWorkItem = nil

        guard !isLockedExpanded, displayState != .collapsed else { return }

        collapseWorkItem?.cancel()
        // Symmetrical delay for hover Out matching hover In
        let delay = max(0.02, settings.hoverDelay)
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovered, !self.isLockedExpanded else { return }
            self.transition(to: .collapsed, locked: false)
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func handleNotchTapped() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        switch displayState {
        case .collapsed:
            transition(to: .expanded, locked: true)
        case .expanded:
            transition(to: .collapsed, locked: false)
        }
    }

    public func expandLocked() {
        hoverWorkItem?.cancel()
        collapseWorkItem?.cancel()
        transition(to: .expanded, locked: true)
    }

    public func collapseImmediately() {
        hoverWorkItem?.cancel()
        collapseWorkItem?.cancel()
        transition(to: .collapsed, locked: false)
    }

    // MARK: - State Transitions

    public func transition(to newState: NotchDisplayState, locked: Bool) {
        shrinkBoundsWorkItem?.cancel()
        shrinkBoundsWorkItem = nil

        isLockedExpanded = (newState == .expanded) ? locked : false

        if newState != .collapsed {
            if !useExpandedWindowBounds {
                useExpandedWindowBounds = true
                onWindowGeometryUpdateNeeded?()
            }
            displayState = newState
            if newState == .expanded {
                installActiveMonitors()
            } else {
                removeActiveMonitors()
            }
        } else {
            removeActiveMonitors()
            displayState = .collapsed

            // Keep expanded panel frame until the Out animation settles completely (symmetrical with In),
            // then shrink back to tight collapsed bounds for zero background overhead.
            let shrink = DispatchWorkItem { [weak self] in
                guard let self, self.displayState == .collapsed else { return }
                self.useExpandedWindowBounds = false
                self.onWindowGeometryUpdateNeeded?()
            }
            shrinkBoundsWorkItem = shrink
            DispatchQueue.main.asyncAfter(
                deadline: .now() + settings.animationStyle.windowShrinkDelay,
                execute: shrink
            )
        }
    }

    // MARK: - Active Monitors (Only Installed While Expanded)

    private func installActiveMonitors() {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.collapseImmediately()
                }
            }
        }

        if escapeKeyMonitor == nil {
            escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    self?.collapseImmediately()
                    return nil
                }
                return event
            }
        }
    }

    private func removeActiveMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }
}
