import CoreWLAN
import Foundation

/// Event-driven Wi-Fi SSID monitor backed by CoreWLAN CWEventDelegate (zero polling).
public final class WiFiMonitor: NSObject, ObservableObject, CWEventDelegate {
    @Published public private(set) var currentSSID: String?
    @Published public private(set) var isPoweredOn: Bool = false

    private let client = CWWiFiClient.shared()
    private var isListening = false

    public init(startListening: Bool = true) {
        super.init()
        let state = Self.readState(client: client)
        self.isPoweredOn = state.isPoweredOn
        self.currentSSID = state.ssid
        if startListening {
            start()
        }
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isListening else { return }
        isListening = true
        client.delegate = self
        try? client.startMonitoringEvent(with: .ssidDidChange)
        try? client.startMonitoringEvent(with: .linkDidChange)
        try? client.startMonitoringEvent(with: .powerDidChange)
        refresh()
    }

    public func stop() {
        guard isListening else { return }
        isListening = false
        try? client.stopMonitoringAllEvents()
        if client.delegate === self {
            client.delegate = nil
        }
    }

    public func refresh() {
        let state = Self.readState(client: client)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isPoweredOn != state.isPoweredOn {
                self.isPoweredOn = state.isPoweredOn
            }
            if self.currentSSID != state.ssid {
                self.currentSSID = state.ssid
            }
        }
    }

    public func togglePower() {
        let target = !isPoweredOn
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            try? self.client.interface()?.setPower(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.refresh()
            }
        }
    }

    // MARK: - CWEventDelegate

    public func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        refresh()
    }

    public func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        refresh()
    }

    public func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        refresh()
    }

    private static func readState(client: CWWiFiClient) -> (isPoweredOn: Bool, ssid: String?) {
        guard let iface = client.interface() else {
            return (false, nil)
        }
        let powered = iface.powerOn()
        guard powered, let raw = iface.ssid() else {
            return (powered, nil)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (true, trimmed.isEmpty ? nil : trimmed)
    }
}
