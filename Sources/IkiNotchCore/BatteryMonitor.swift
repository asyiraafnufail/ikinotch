import Foundation
import IOKit.ps

public struct BatteryStatus: Equatable {
    public let hasBattery: Bool
    public let percentage: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let timeRemainingMinutes: Int?

    public init(
        hasBattery: Bool,
        percentage: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        timeRemainingMinutes: Int?
    ) {
        self.hasBattery = hasBattery
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.timeRemainingMinutes = timeRemainingMinutes
    }

    public var formattedTimeRemaining: String? {
        guard let minutes = timeRemainingMinutes, minutes > 0, minutes < 1440 else {
            return nil
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    public var symbolName: String {
        if !hasBattery {
            return "powerplug.fill"
        }
        if isCharging {
            return "battery.100.bolt"
        }
        switch percentage {
        case 88...100: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    public static let desktopFallback = BatteryStatus(
        hasBattery: false,
        percentage: 100,
        isCharging: false,
        isPluggedIn: true,
        timeRemainingMinutes: nil
    )
}

/// Event-driven battery monitor backed by IOKit power source notifications (zero polling).
public final class BatteryMonitor: ObservableObject {
    @Published public private(set) var status: BatteryStatus

    private var runLoopSource: CFRunLoopSource?

    public init(startListening: Bool = true) {
        self.status = Self.readCurrentStatus()
        if startListening {
            start()
        }
    }

    deinit {
        stop()
    }

    public func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanagedSource = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.refresh()
        }, context) else {
            return
        }
        let source = unmanagedSource.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }
    }

    public func refresh() {
        let updated = Self.readCurrentStatus()
        if updated != status {
            status = updated
        }
    }

    public static func readCurrentStatus() -> BatteryStatus {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .desktopFallback
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let parsed = parsePowerSourceDictionary(description) else {
                continue
            }
            return parsed
        }
        return .desktopFallback
    }

    public static func parsePowerSourceDictionary(_ dict: [String: Any]) -> BatteryStatus? {
        let type = dict[kIOPSTypeKey as String] as? String ?? dict["Type"] as? String
        if let type, type != kIOPSInternalBatteryType && type != "InternalBattery" {
            return nil
        }

        guard let current = dict[kIOPSCurrentCapacityKey as String] as? Int ?? dict["Current Capacity"] as? Int else {
            return nil
        }
        let maxCap = max(1, dict[kIOPSMaxCapacityKey as String] as? Int ?? dict["Max Capacity"] as? Int ?? 100)
        let percentage = min(100, max(0, Int((Double(current) / Double(maxCap) * 100.0).rounded())))

        let isCharging = (dict[kIOPSIsChargingKey as String] as? Bool)
            ?? (dict["Is Charging"] as? Bool)
            ?? false

        let powerState = (dict[kIOPSPowerSourceStateKey as String] as? String)
            ?? (dict["Power Source State"] as? String)
            ?? ""
        let isPluggedIn = powerState == kIOPSACPowerValue || powerState == "AC Power" || isCharging

        let rawTime: Int?
        if isCharging {
            rawTime = dict[kIOPSTimeToFullChargeKey as String] as? Int ?? dict["Time to Full Charge"] as? Int
        } else {
            rawTime = dict[kIOPSTimeToEmptyKey as String] as? Int ?? dict["Time to Empty"] as? Int
        }
        let validTime = (rawTime ?? -1) > 0 ? rawTime : nil

        return BatteryStatus(
            hasBattery: true,
            percentage: percentage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            timeRemainingMinutes: validTime
        )
    }
}
