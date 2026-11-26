import Foundation
import IOKit.pwr_mgt

/// Prevents macOS display & idle sleep on demand via IOKit power assertions (zero polling, 0% CPU).
public final class KeepAwakeManager: ObservableObject {
    @Published public private(set) var isActive: Bool = false

    private var assertionID: IOPMAssertionID = 0

    public init() {}

    deinit {
        deactivate()
    }

    public func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    public func activate() {
        guard !isActive else { return }
        let reason = "IkiNotch Keep Awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
        }
    }

    public func deactivate() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}
