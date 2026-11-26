import AppKit
import CoreGraphics
import Foundation

/// Event-driven Caps Lock monitor (zero polling).
/// Uses flagsChanged monitors plus hidSystemState refresh on app switch (handles Secure Input fields).
public final class CapsLockMonitor: ObservableObject {
    @Published public private(set) var isCapsLockOn: Bool

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init(startListening: Bool = true) {
        self.isCapsLockOn = Self.readSystemCapsLockState()
        if startListening {
            start()
        }
    }

    deinit {
        stop()
    }

    public func start() {
        refresh()
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let isOn = event.modifierFlags.contains(.capsLock)
                DispatchQueue.main.async {
                    self?.update(isOn)
                }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let isOn = event.modifierFlags.contains(.capsLock)
                DispatchQueue.main.async {
                    self?.update(isOn)
                }
                return event
            }
        }
    }

    public func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    public func refresh() {
        update(Self.readSystemCapsLockState())
    }

    private func update(_ newValue: Bool) {
        if isCapsLockOn != newValue {
            isCapsLockOn = newValue
        }
    }

    public static func readSystemCapsLockState() -> Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }
}
