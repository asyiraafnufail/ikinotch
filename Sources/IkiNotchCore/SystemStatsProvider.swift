import Darwin
import Foundation

public struct SystemStatsSnapshot: Equatable {
    public let usedMemoryGB: Double
    public let totalMemoryGB: Double
    public let freeDiskGB: Double
    public let totalDiskGB: Double
    public let localIPAddress: String
    public let uptimeFormatted: String

    public var memoryRatio: Double {
        guard totalMemoryGB > 0 else { return 0 }
        return min(1.0, max(0.0, usedMemoryGB / totalMemoryGB))
    }

    public var diskUsedRatio: Double {
        guard totalDiskGB > 0 else { return 0 }
        return min(1.0, max(0.0, (totalDiskGB - freeDiskGB) / totalDiskGB))
    }

    public static let empty = SystemStatsSnapshot(
        usedMemoryGB: 0,
        totalMemoryGB: 0,
        freeDiskGB: 0,
        totalDiskGB: 0,
        localIPAddress: "—",
        uptimeFormatted: "—"
    )
}

/// On-demand system stats reader. Runs ONLY when `refresh()` is called (0% idle CPU).
public final class SystemStatsProvider: ObservableObject {
    @Published public private(set) var snapshot: SystemStatsSnapshot = .empty

    public init() {}

    public func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mem = Self.readMemoryGB()
            let disk = Self.readDiskGB()
            let ip = Self.readLocalIPv4() ?? "Offline"
            let uptime = Self.formatUptime(ProcessInfo.processInfo.systemUptime)

            let updated = SystemStatsSnapshot(
                usedMemoryGB: mem.used,
                totalMemoryGB: mem.total,
                freeDiskGB: disk.free,
                totalDiskGB: disk.total,
                localIPAddress: ip,
                uptimeFormatted: uptime
            )
            DispatchQueue.main.async {
                self?.snapshot = updated
            }
        }
    }

    private static func readMemoryGB() -> (used: Double, total: Double) {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / 1_073_741_824.0

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (0, totalGB)
        }

        let active = Double(stats.active_count)
        let wired = Double(stats.wire_count)
        let compressed = Double(stats.compressor_page_count)
        let usedBytes = (active + wired + compressed) * Double(pageSize)
        return (usedBytes / 1_073_741_824.0, totalGB)
    }

    private static func readDiskGB() -> (free: Double, total: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]) else {
            return (0, 0)
        }
        let freeBytes = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let totalBytes = Double(values.volumeTotalCapacity ?? 0)
        return (freeBytes / 1_000_000_000.0, totalBytes / 1_000_000_000.0)
    }

    private static func readLocalIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var fallbackIP: String?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: current.pointee.ifa_name)
            if name == "lo0" { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if name == "en0" {
                    return ip
                }
                if fallbackIP == nil {
                    fallbackIP = ip
                }
            }
        }
        return fallbackIP
    }

    public static func formatUptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let mins = totalMinutes % 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}
