import Foundation
import ServiceManagement

public enum NotchSizePreset: String, CaseIterable, Identifiable, Codable {
    case compact = "compact"
    case standard = "standard"
    case wide = "wide"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: return "Compact (Auto Menu Bar Height)"
        case .standard: return "Standard (Auto Menu Bar Height)"
        case .wide: return "Wide (Auto Menu Bar Height)"
        case .custom: return "Custom"
        }
    }

    public var defaultBodyWidth: CGFloat {
        switch self {
        case .compact: return 168
        case .standard: return 194
        case .wide: return 224
        case .custom: return 194
        }
    }

    public var defaultHeight: CGFloat {
        switch self {
        case .compact: return 25
        case .standard: return 31
        case .wide: return 33
        case .custom: return 31
        }
    }
}

public enum NotchTriggerMode: String, CaseIterable, Identifiable, Codable {
    case expandOnHover = "hover"
    case clickOnly = "click"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .expandOnHover: return "Expand on Hover"
        case .clickOnly: return "Click Only"
        }
    }
}

public enum NotchAnimationStyle: String, CaseIterable, Identifiable, Codable {
    case snappy = "snappy"
    case smooth = "smooth"
    case bouncy = "bouncy"
    case instant = "instant"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .snappy: return "Snappy"
        case .smooth: return "Smooth (Default)"
        case .bouncy: return "Bouncy"
        case .instant: return "Instant (Off)"
        }
    }

    public var springResponse: Double {
        switch self {
        case .snappy: return 0.22
        case .smooth: return 0.34
        case .bouncy: return 0.36
        case .instant: return 0.0
        }
    }

    public var springDamping: Double {
        switch self {
        case .snappy: return 0.88
        case .smooth: return 0.84
        case .bouncy: return 0.70
        case .instant: return 1.0
        }
    }

    /// Time to wait before shrinking the NSPanel bounds back to collapsed size
    /// so the collapse (Out) animation finishes completely and matches In symmetrically.
    public var windowShrinkDelay: Double {
        switch self {
        case .snappy: return 0.40
        case .smooth: return 0.56
        case .bouncy: return 0.65
        case .instant: return 0.04
        }
    }
}

public enum NotchIdleStyle: String, CaseIterable, Identifiable, Codable {
    case smartStatus = "smart"
    case custom = "custom"
    case pureBlack = "minimal"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .smartStatus: return "Smart Status"
        case .custom: return "Custom"
        case .pureBlack: return "Pure Black"
        }
    }
}

public final class NotchSettings: ObservableObject {
    private enum Keys {
        static let isNotchVisible = "ikinotch.isNotchVisible"
        static let sizePreset = "ikinotch.sizePreset"
        static let customWidth = "ikinotch.customWidth"
        static let customHeight = "ikinotch.customHeight"
        static let horizontalOffset = "ikinotch.horizontalOffset"
        static let triggerMode = "ikinotch.v2.triggerMode"
        static let hoverDelay = "ikinotch.v2.hoverDelay"
        static let animationStyle = "ikinotch.animationStyle"
        static let idleStyle = "ikinotch.idleStyle"
        static let customIdleText = "ikinotch.customIdleText"
        static let customIdleShowBattery = "ikinotch.customIdleShowBattery"
        static let showCapsLockIndicator = "ikinotch.showCapsLockIndicator"
        static let hideInFullscreen = "ikinotch.v2.hideInFullscreen"
        static let showNowPlaying = "ikinotch.showNowPlaying"
        static let showCalendar = "ikinotch.showCalendar"
        static let showBattery = "ikinotch.showBattery"
        static let showClock = "ikinotch.showClock"
        static let showFileShelf = "ikinotch.showFileShelf"
        static let preferredDisplayID = "ikinotch.preferredDisplayID"
    }

    private let defaults: UserDefaults

    @Published public var isNotchVisible: Bool {
        didSet { defaults.set(isNotchVisible, forKey: Keys.isNotchVisible) }
    }

    @Published public var sizePreset: NotchSizePreset {
        didSet { defaults.set(sizePreset.rawValue, forKey: Keys.sizePreset) }
    }

    @Published public var customWidth: CGFloat {
        didSet { defaults.set(Double(customWidth), forKey: Keys.customWidth) }
    }

    @Published public var customHeight: CGFloat {
        didSet { defaults.set(Double(customHeight), forKey: Keys.customHeight) }
    }

    @Published public var horizontalOffset: CGFloat {
        didSet { defaults.set(Double(horizontalOffset), forKey: Keys.horizontalOffset) }
    }

    @Published public var triggerMode: NotchTriggerMode {
        didSet { defaults.set(triggerMode.rawValue, forKey: Keys.triggerMode) }
    }

    @Published public var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) }
    }

    @Published public var animationStyle: NotchAnimationStyle {
        didSet { defaults.set(animationStyle.rawValue, forKey: Keys.animationStyle) }
    }

    @Published public var idleStyle: NotchIdleStyle {
        didSet { defaults.set(idleStyle.rawValue, forKey: Keys.idleStyle) }
    }

    @Published public var customIdleText: String {
        didSet { defaults.set(customIdleText, forKey: Keys.customIdleText) }
    }

    @Published public var customIdleShowBattery: Bool {
        didSet { defaults.set(customIdleShowBattery, forKey: Keys.customIdleShowBattery) }
    }

    @Published public var showCapsLockIndicator: Bool {
        didSet { defaults.set(showCapsLockIndicator, forKey: Keys.showCapsLockIndicator) }
    }

    @Published public var hideInFullscreen: Bool {
        didSet { defaults.set(hideInFullscreen, forKey: Keys.hideInFullscreen) }
    }

    @Published public var showNowPlaying: Bool {
        didSet { defaults.set(showNowPlaying, forKey: Keys.showNowPlaying) }
    }

    @Published public var showCalendar: Bool {
        didSet { defaults.set(showCalendar, forKey: Keys.showCalendar) }
    }

    @Published public var showBattery: Bool {
        didSet { defaults.set(showBattery, forKey: Keys.showBattery) }
    }

    @Published public var showClock: Bool {
        didSet { defaults.set(showClock, forKey: Keys.showClock) }
    }

    @Published public var showFileShelf: Bool {
        didSet { defaults.set(showFileShelf, forKey: Keys.showFileShelf) }
    }

    /// 0 means primary / main screen.
    @Published public var preferredDisplayID: UInt32 {
        didSet { defaults.set(Int(preferredDisplayID), forKey: Keys.preferredDisplayID) }
    }

    @Published public var launchAtLoginError: String?

    public var launchAtLoginEnabled: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.isNotchVisible = defaults.object(forKey: Keys.isNotchVisible) as? Bool ?? true

        if let rawPreset = defaults.string(forKey: Keys.sizePreset),
           let preset = NotchSizePreset(rawValue: rawPreset) {
            self.sizePreset = preset
        } else {
            self.sizePreset = .standard
        }

        let storedWidth = defaults.double(forKey: Keys.customWidth)
        self.customWidth = storedWidth > 0 ? CGFloat(storedWidth) : 194

        let storedHeight = defaults.double(forKey: Keys.customHeight)
        self.customHeight = storedHeight > 0 ? CGFloat(storedHeight) : 31

        self.horizontalOffset = CGFloat(defaults.double(forKey: Keys.horizontalOffset))

        if let rawTrigger = defaults.string(forKey: Keys.triggerMode),
           let trigger = NotchTriggerMode(rawValue: rawTrigger) {
            self.triggerMode = trigger
        } else {
            self.triggerMode = .expandOnHover
        }

        let rawDelay = defaults.object(forKey: Keys.hoverDelay) as? Double ?? 0.15
        let allowedDelays: [Double] = [0.05, 0.10, 0.15, 0.20]
        self.hoverDelay = allowedDelays.min(by: { abs($0 - rawDelay) < abs($1 - rawDelay) }) ?? 0.15
        if let rawAnim = defaults.string(forKey: Keys.animationStyle),
           let anim = NotchAnimationStyle(rawValue: rawAnim) {
            self.animationStyle = anim
        } else {
            self.animationStyle = .smooth
        }
        if let rawIdle = defaults.string(forKey: Keys.idleStyle),
           let idle = NotchIdleStyle(rawValue: rawIdle) {
            self.idleStyle = idle
        } else {
            self.idleStyle = .smartStatus
        }
        self.customIdleText = defaults.string(forKey: Keys.customIdleText) ?? "Focus"
        self.customIdleText = defaults.string(forKey: Keys.customIdleText) ?? "Focus"
        self.customIdleShowBattery = defaults.object(forKey: Keys.customIdleShowBattery) as? Bool ?? true
        self.showCapsLockIndicator = defaults.object(forKey: Keys.showCapsLockIndicator) as? Bool ?? true
        self.hideInFullscreen = defaults.object(forKey: Keys.hideInFullscreen) as? Bool ?? true
        self.showNowPlaying = defaults.object(forKey: Keys.showNowPlaying) as? Bool ?? true
        self.showCalendar = defaults.object(forKey: Keys.showCalendar) as? Bool ?? true
        self.showBattery = defaults.object(forKey: Keys.showBattery) as? Bool ?? true
        self.showClock = defaults.object(forKey: Keys.showClock) as? Bool ?? true
        self.showFileShelf = defaults.object(forKey: Keys.showFileShelf) as? Bool ?? true
        self.preferredDisplayID = UInt32(max(0, defaults.integer(forKey: Keys.preferredDisplayID)))
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            launchAtLoginError = "Launch at Login requires running from IkiNotch.app bundle."
            return
        }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            objectWillChange.send()
        } catch {
            launchAtLoginError = error.localizedDescription
            objectWillChange.send()
        }
    }

    public func resetPosition() {
        horizontalOffset = 0
    }
}
