import Darwin
import Foundation

public enum ThermalLevel: String, Equatable {
    case cool = "Cool"
    case fair = "Fair"
    case warm = "Warm"
    case hot = "Hot"

    public init(state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .cool
        case .fair: self = .fair
        case .serious: self = .warm
        case .critical: self = .hot
        @unknown default: self = .cool
        }
    }
}

public struct SystemStatsSnapshot: Equatable {
    public let cpuUsagePercent: Double
    public let usedMemoryGB: Double
    public let totalMemoryGB: Double
    public let freeDiskGB: Double
    public let totalDiskGB: Double
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let thermal: ThermalLevel
    public let localIPAddress: String
    public let uptimeFormatted: String

    public var cpuRatio: Double {
        min(1.0, max(0.0, cpuUsagePercent / 100.0))
    }

    public var memoryRatio: Double {
        guard totalMemoryGB > 0 else { return 0 }
        return min(1.0, max(0.0, usedMemoryGB / totalMemoryGB))
    }

    public var diskUsedRatio: Double {
        guard totalDiskGB > 0 else { return 0 }
        return min(1.0, max(0.0, (totalDiskGB - freeDiskGB) / totalDiskGB))
    }

    public static let empty = SystemStatsSnapshot(
        cpuUsagePercent: 0,
        usedMemoryGB: 0,
        totalMemoryGB: 0,
        freeDiskGB: 0,
        totalDiskGB: 0,
        downloadBytesPerSec: 0,
        uploadBytesPerSec: 0,
        thermal: .cool,
        localIPAddress: "—",
        uptimeFormatted: "—"
    )
}

/// Pure native Mach/Darwin system stats reader.
/// Runs live sampling ONLY while the Stats tab is visible (`startLiveUpdates()` / `stopLiveUpdates()`).
/// Consumes 0% CPU when collapsed or when viewing any other tab.
public final class SystemStatsProvider: ObservableObject {
    @Published public private(set) var snapshot: SystemStatsSnapshot = .empty

    private let queue = DispatchQueue(label: "com.ikinotch.stats", qos: .utility)
    private var timer: DispatchSourceTimer?

    private var prevCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevNetSample: (rxBytes: UInt64, txBytes: UInt64, timestamp: CFAbsoluteTime)?

    public init() {}

    deinit {
        stopLiveUpdates()
    }

    public func startLiveUpdates(interval: TimeInterval = 2.0) {
        stopLiveUpdates()
        refresh()

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(300)
        )
        source.setEventHandler { [weak self] in
            self?.sampleOnQueue()
        }
        timer = source
        source.resume()
    }

    public func stopLiveUpdates() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.prevCPUTicks = nil
            self?.prevNetSample = nil
        }
    }

    public func refresh() {
        queue.async { [weak self] in
            self?.sampleOnQueue()
        }
    }

    private func sampleOnQueue() {
        let cpu = readCPUUsagePercent()
        let mem = Self.readMemoryGB()
        let disk = Self.readDiskGB()
        let net = readNetworkSpeeds()
        let ip = Self.readLocalIPv4() ?? "Offline"
        let uptime = Self.formatUptime(ProcessInfo.processInfo.systemUptime)
        let thermal = ThermalLevel(state: ProcessInfo.processInfo.thermalState)

        let updated = SystemStatsSnapshot(
            cpuUsagePercent: cpu,
            usedMemoryGB: mem.used,
            totalMemoryGB: mem.total,
            freeDiskGB: disk.free,
            totalDiskGB: disk.total,
            downloadBytesPerSec: net.down,
            uploadBytesPerSec: net.up,
            thermal: thermal,
            localIPAddress: ip,
            uptimeFormatted: uptime
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.snapshot != updated {
                self.snapshot = updated
            }
        }
    }

    // MARK: - Native Mach / Darwin Readers (Zero Subprocess Spawns)

    private func readCPUUsagePercent() -> Double {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let current = (
            user: UInt64(cpuInfo.cpu_ticks.0),
            system: UInt64(cpuInfo.cpu_ticks.1),
            idle: UInt64(cpuInfo.cpu_ticks.2),
            nice: UInt64(cpuInfo.cpu_ticks.3)
        )
        defer { prevCPUTicks = current }

        guard let prev = prevCPUTicks else {
            // On very first sample before a delta exists, approximate via load average / core count
            var loadAvg = [Double](repeating: 0, count: 3)
            if getloadavg(&loadAvg, 1) == 1 {
                let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
                return min(100, max(0, (loadAvg[0] / cores) * 100.0))
            }
            return 0
        }

        let dUser = current.user >= prev.user ? current.user - prev.user : 0
        let dSystem = current.system >= prev.system ? current.system - prev.system : 0
        let dIdle = current.idle >= prev.idle ? current.idle - prev.idle : 0
        let dNice = current.nice >= prev.nice ? current.nice - prev.nice : 0
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(dUser + dSystem + dNice) / Double(total) * 100.0))
    }

    private func readNetworkSpeeds() -> (down: Double, up: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }

            if let dataPtr = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totalRx &+= UInt64(dataPtr.pointee.ifi_ibytes)
                totalTx &+= UInt64(dataPtr.pointee.ifi_obytes)
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        defer { prevNetSample = (totalRx, totalTx, now) }

        guard let prev = prevNetSample else { return (0, 0) }
        let dt = now - prev.timestamp
        guard dt > 0.1 else { return (0, 0) }

        let dRx = totalRx >= prev.rxBytes ? Double(totalRx - prev.rxBytes) : 0
        let dTx = totalTx >= prev.txBytes ? Double(totalTx - prev.txBytes) : 0
        return (dRx / dt, dTx / dt)
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

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        }
        if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        }
        return String(format: "%.0f B/s", max(0, bytesPerSec))
    }
}
