import AppKit
import Combine
import IkiNotchCore
import SwiftUI

@main
final class IkiNotchAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var notchPanel: NotchPanel?
    private var hostView: NotchHostView<NotchContentView>?
    private var settingsWindow: NSWindow?

    private let settings = NotchSettings()
    private lazy var controller = NotchController(settings: settings)
    private let batteryMonitor = BatteryMonitor(startListening: true)
    private let nowPlayingMonitor = NowPlayingMonitor(startListening: true)
    private let calendarMonitor = CalendarMonitor(startListening: true)
    private let capsLockMonitor = CapsLockMonitor(startListening: true)
    private let privacyMonitor = PrivacyIndicatorMonitor(startListening: true)
    private let wifiMonitor = WiFiMonitor(startListening: true)
    private let keepAwakeManager = KeepAwakeManager()
    private let fileShelfStore = FileShelfStore()
    private let systemControls = SystemControlsManager()
    private let quickTimer = QuickTimerManager()
    private let scratchpad = ScratchpadStore()
    private let systemStats = SystemStatsProvider()
    private let hotKeyManager = GlobalHotKeyManager()

    private var cancellables = Set<AnyCancellable>()
    private var toggleVisibilityMenuItem: NSMenuItem?
    private var transitionWorkItems: [DispatchWorkItem] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = IkiNotchAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupNotchPanel()
        setupGlobalHotKeyAndTimerCallbacks()
        bindObservers()
        updatePanelVisibilityAndFrame()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.stop()
        batteryMonitor.stop()
        nowPlayingMonitor.stop()
        capsLockMonitor.stop()
        privacyMonitor.stop()
        wifiMonitor.stop()
        keepAwakeManager.deactivate()
    }

    private func setupGlobalHotKeyAndTimerCallbacks() {
        hotKeyManager.onHotKeyPressed = { [weak self] in
            guard let self else { return }
            if !self.settings.isNotchVisible {
                self.settings.isNotchVisible = true
            }
            if self.controller.displayState == .collapsed {
                self.updatePanelVisibilityAndFrame()
                self.controller.expandLocked()
            } else {
                self.controller.collapseImmediately()
            }
        }

        quickTimer.onTimerFinished = { mode, finishedPhase in
            let title: String
            let message: String
            if mode == .pomodoro {
                title = "IkiNotch Pomodoro"
                message = finishedPhase == .focus
                    ? "Focus session complete! Time for a break."
                    : "Break finished! Ready for your next focus session."
            } else {
                title = "IkiNotch Timer"
                message = "Countdown finished."
            }
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", "display notification \"\(message)\" with title \"\(title)\""]
                try? task.run()
            }
        }
    }

    // MARK: - Menu Bar Status Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "IkiNotch") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "IN"
            }
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: settings.isNotchVisible ? "Hide Notch" : "Show Notch",
            action: #selector(toggleNotchVisibility),
            keyEquivalent: "h"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        self.toggleVisibilityMenuItem = toggleItem

        let expandItem = NSMenuItem(
            title: "Expand Notch",
            action: #selector(expandNotchAction),
            keyEquivalent: "e"
        )
        expandItem.target = self
        menu.addItem(expandItem)

        let centerItem = NSMenuItem(
            title: "Center Notch",
            action: #selector(centerNotchAction),
            keyEquivalent: ""
        )
        centerItem.target = self
        menu.addItem(centerItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit IkiNotch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    // MARK: - Notch Panel Setup

    private func setupNotchPanel() {
        let targetScreen = resolveTargetScreen()
        let initialFrame = computePanelFrame(for: targetScreen)
        let panel = NotchPanel(contentRect: initialFrame)

        let rootView = NotchContentView(
            controller: controller,
            settings: settings,
            battery: batteryMonitor,
            nowPlaying: nowPlayingMonitor,
            calendar: calendarMonitor,
            capsLock: capsLockMonitor,
            privacy: privacyMonitor,
            wifi: wifiMonitor,
            keepAwake: keepAwakeManager,
            fileShelf: fileShelfStore,
            systemControls: systemControls,
            quickTimer: quickTimer,
            scratchpad: scratchpad,
            systemStats: systemStats,
            onSetKeyFocusAllowed: { [weak self] allowed in
                guard let panel = self?.notchPanel else { return }
                panel.allowKeyFocus = allowed
                if allowed {
                    panel.makeKey()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        )

        let host = NotchHostView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: initialFrame.size)
        host.autoresizingMask = [.width, .height]
        host.onMouseEnteredNotch = { [weak self] in
            guard let self else { return }
            if self.settings.hideInFullscreen && self.isFullscreenActive(on: self.resolveTargetScreen()) {
                self.updatePanelVisibilityAndFrame()
                return
            }
            self.controller.handleMouseEntered()
        }
        host.onMouseExitedNotch = { [weak self] in
            self?.controller.handleMouseExited()
        }

        panel.contentView = host
        self.hostView = host
        self.notchPanel = panel

        controller.onWindowGeometryUpdateNeeded = { [weak self] in
            self?.updatePanelVisibilityAndFrame()
        }
        controller.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
    }

    // MARK: - Event-Driven Observers

    private func bindObservers() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.syncOptionalMonitors()
                    self?.toggleVisibilityMenuItem?.title = (self?.settings.isNotchVisible == true) ? "Hide Notch" : "Show Notch"
                    self?.updatePanelVisibilityAndFrame()
                }
            }
            .store(in: &cancellables)
        syncOptionalMonitors()

        controller.$displayState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncActiveTrackingSize()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelVisibilityAndFrame()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSpaceOrAppTransition()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.capsLockMonitor.refresh()
                self?.privacyMonitor.refresh()
                self?.handleSpaceOrAppTransition()
            }
            .store(in: &cancellables)
    }

    private func syncOptionalMonitors() {
        if settings.showCapsLockIndicator {
            capsLockMonitor.start()
        } else {
            capsLockMonitor.stop()
        }
        if settings.showPrivacyIndicators {
            privacyMonitor.start()
        } else {
            privacyMonitor.stop()
        }
        if settings.showNowPlaying || settings.idleStyle == .smartStatus {
            nowPlayingMonitor.start()
        } else {
            nowPlayingMonitor.stop()
        }
        if settings.enableGlobalShortcut {
            hotKeyManager.start(
                keyCode: settings.globalShortcutPreset.keyCode,
                modifiers: settings.globalShortcutPreset.modifiers
            )
        } else {
            hotKeyManager.stop()
        }
        quickTimer.soundEnabled = settings.timerSoundEnabled
        statusItem?.isVisible = settings.showMenuBarIcon
    }

    private func handleSpaceOrAppTransition() {
        for item in transitionWorkItems {
            item.cancel()
        }
        transitionWorkItems.removeAll()

        updatePanelVisibilityAndFrame()

        // One-shot settle checks covering macOS fullscreen animation duration (~1.2s on Intel Macs)
        for delay in [0.35, 0.90, 1.60] {
            let item = DispatchWorkItem { [weak self] in
                self?.updatePanelVisibilityAndFrame()
            }
            transitionWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func resolveTargetScreen() -> NSScreen {
        if settings.displayTarget == .activeScreen {
            let mouseLoc = NSEvent.mouseLocation
            if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
                return mouseScreen
            }
            return NSScreen.main ?? NSScreen.screens.first!
        }

        if settings.preferredDisplayID != 0 {
            for screen in NSScreen.screens {
                if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                   num.uint32Value == settings.preferredDisplayID {
                    return screen
                }
            }
        }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    private func isFullscreenActive(on screen: NSScreen) -> Bool {
        // 1. Check if macOS hid the menu bar on this screen via visibleFrame
        if abs(screen.frame.maxY - screen.visibleFrame.maxY) < 1.0 {
            return true
        }

        // 2. Inspect on-screen windows via CoreGraphics (zero permissions, zero polling)
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenQuartz = NotchGeometry.quartzRect(for: screen.frame, primaryScreenHeight: primaryHeight)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ignoredOwners: Set<String> = [
            "Finder", "Dock", "Window Server", "Control Center",
            "Notification Center", "Screenshot", "SystemUIServer", "Wallpaper"
        ]

        var foundVisibleMenuBarOnScreen = false

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            // Check whether Window Server's Menubar (layer 24) is currently visible at the top of this screen
            if layer == 24 {
                let onThisScreenX = bounds.midX >= screenQuartz.minX && bounds.midX <= screenQuartz.maxX
                let atTopEdge = bounds.minY >= screenQuartz.minY - 2 && bounds.minY <= screenQuartz.minY + 2
                if onThisScreenX && atTopEdge && bounds.height >= 16 {
                    foundVisibleMenuBarOnScreen = true
                }
                continue
            }

            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else {
                continue
            }
            // Only normal app windows (layer 0) should count as fullscreen; ignore system overlays (e.g. Screenshot at layer 21)
            guard layer == 0 else { continue }
            if let owner = info[kCGWindowOwnerName as String] as? String, ignoredOwners.contains(owner) {
                continue
            }

            if NotchGeometry.isWindowBoundsFullscreen(bounds, onScreenQuartzRect: screenQuartz) {
                return true
            }
        }

        // If macOS has hidden the Menubar (layer 24) on this screen, we are in a fullscreen space
        return !foundVisibleMenuBarOnScreen
    }

    private func detectedMenuBarHeight(for screen: NSScreen) -> CGFloat {
        let visibleDelta = screen.frame.maxY - screen.visibleFrame.maxY
        if visibleDelta >= 18 {
            return visibleDelta
        }
        return max(22, NSStatusBar.system.thickness)
    }

    private func computePanelFrame(for screen: NSScreen) -> CGRect {
        let barHeight = detectedMenuBarHeight(for: screen)
        if abs(controller.menuBarHeight - barHeight) > 0.5 {
            controller.menuBarHeight = barHeight
        }
        return NotchGeometry.panelFrame(
            for: controller.displayState,
            screenFrame: screen.frame,
            preset: settings.sizePreset,
            customWidth: settings.customWidth,
            customHeight: settings.customHeight,
            menuBarHeight: barHeight,
            shapeStyle: settings.shapeStyle,
            horizontalOffset: settings.horizontalOffset,
            useExpandedWindowBounds: controller.useExpandedWindowBounds,
            hasContentCards: settings.showNowPlaying || settings.showCalendar || settings.showFileShelf
        )
    }

    private func syncActiveTrackingSize() {
        let metrics = NotchGeometry.metrics(
            for: controller.displayState,
            preset: settings.sizePreset,
            customWidth: settings.customWidth,
            customHeight: settings.customHeight,
            menuBarHeight: controller.menuBarHeight,
            shapeStyle: settings.shapeStyle,
            hasContentCards: settings.showNowPlaying || settings.showCalendar || settings.showFileShelf
        )
        hostView?.activeNotchSize = metrics.size
    }

    private func updatePanelVisibilityAndFrame() {
        guard let panel = notchPanel else { return }
        let screen = resolveTargetScreen()

        panel.setAllowInFullscreen(!settings.hideInFullscreen)

        let shouldHide = !settings.isNotchVisible || (settings.hideInFullscreen && isFullscreenActive(on: screen))
        if shouldHide {
            if controller.displayState != .collapsed {
                controller.collapseImmediately()
            }
            panel.orderOut(nil)
            return
        }

        let newFrame = computePanelFrame(for: screen)
        if panel.frame != newFrame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.setFrame(newFrame, display: false)
            CATransaction.commit()
        }
        syncActiveTrackingSize()

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Actions

    @objc private func toggleNotchVisibility() {
        settings.isNotchVisible.toggle()
        if !settings.isNotchVisible {
            controller.collapseImmediately()
        }
    }

    @objc private func expandNotchAction() {
        if !settings.isNotchVisible {
            settings.isNotchVisible = true
        }
        controller.expandLocked()
    }

    @objc private func centerNotchAction() {
        settings.resetPosition()
    }

    @objc private func openSettingsWindow() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(settings: settings, calendar: calendarMonitor)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "IkiNotch Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        if let closed = notification.object as? NSWindow, closed == settingsWindow {
            // Release settings window when closed to keep idle memory footprint minimal
            settingsWindow = nil
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
