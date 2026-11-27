import Carbon.HIToolbox
import Foundation

/// Event-driven global hotkey manager using Carbon `RegisterEventHotKey`.
/// Zero polling, zero idle CPU, and requires no Accessibility permissions.
/// Default shortcut: Control + Option + N (⌃⌥N).
public final class GlobalHotKeyManager {
    private static let signature: OSType = 0x494B4E48 // 'IKNH'
    private static let hotKeyIDValue: UInt32 = 1

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    public var onHotKeyPressed: (() -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard hotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalHotKeyManager.signature,
                      hotKeyID.id == GlobalHotKeyManager.hotKeyIDValue else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onHotKeyPressed?()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            eventHandlerRef = nil
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyIDValue)
        let modifiers = UInt32(controlKey | optionKey)
        let keyCode = UInt32(kVK_ANSI_N)

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if regStatus != noErr {
            stop()
        }
    }

    public func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
