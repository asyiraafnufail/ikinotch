import AppKit
import CoreAudio
import Darwin
import Foundation
import IOBluetooth

/// On-demand system controls (Bluetooth, Dark Mode, Audio Mute) with zero idle polling.
/// Reads state only when `refresh()` is called (when the expanded notch opens) or after user clicks.
public final class SystemControlsManager: ObservableObject {
    @Published public private(set) var isBluetoothOn: Bool = false
    @Published public private(set) var connectedBluetoothDevice: String?
    @Published public private(set) var isDarkMode: Bool = false
    @Published public private(set) var isMuted: Bool = false

    private typealias SetBTPowerFn = @convention(c) (Int32) -> Void
    private let setBTPowerFn: SetBTPowerFn?

    public init() {
        let btPath = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
        if let handle = dlopen(btPath, RTLD_LAZY),
           let sym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") {
            self.setBTPowerFn = unsafeBitCast(sym, to: SetBTPowerFn.self)
        } else {
            self.setBTPowerFn = nil
        }
        refresh()
    }

    public func refresh() {
        refreshBluetooth()
        refreshDarkMode()
        refreshAudioMute()
    }

    // MARK: - Bluetooth

    public func refreshBluetooth() {
        if let controller = IOBluetoothHostController.default() {
            isBluetoothOn = (controller.powerState == kBluetoothHCIPowerStateON)
        } else {
            isBluetoothOn = false
        }

        if isBluetoothOn, let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            connectedBluetoothDevice = devices.first(where: { $0.isConnected() })?.name
        } else {
            connectedBluetoothDevice = nil
        }
    }

    public func toggleBluetooth() {
        let target: Int32 = isBluetoothOn ? 0 : 1
        if let fn = setBTPowerFn {
            fn(target)
            isBluetoothOn = (target == 1)
            if !isBluetoothOn {
                connectedBluetoothDevice = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.refreshBluetooth()
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Dark / Light Mode

    public func refreshDarkMode() {
        isDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    public func toggleDarkMode() {
        let next = !isDarkMode
        isDarkMode = next
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var errorInfo: NSDictionary?
            let script = NSAppleScript(
                source: "tell application \"System Events\" to tell appearance preferences to set dark mode to \(next ? "true" : "false")"
            )
            _ = script?.executeAndReturnError(&errorInfo)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.refreshDarkMode()
            }
        }
    }

    // MARK: - CoreAudio System Output Mute (Zero Permissions, Instant)

    public func refreshAudioMute() {
        guard let deviceID = defaultOutputDeviceID() else {
            isMuted = false
            return
        }
        isMuted = readMuteState(deviceID: deviceID)
    }

    public func toggleAudioMute() {
        guard let deviceID = defaultOutputDeviceID() else { return }
        let nextMute = !readMuteState(deviceID: deviceID)
        if writeMuteState(deviceID: deviceID, muted: nextMute) {
            isMuted = nextMute
        } else {
            refreshAudioMute()
        }
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func readMuteState(deviceID: AudioDeviceID) -> Bool {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
                if status == noErr {
                    return muted != 0
                }
            }
        }
        return false
    }

    private func writeMuteState(deviceID: AudioDeviceID, muted: Bool) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                var settable: DarwinBoolean = false
                if AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue {
                    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
                    if status == noErr {
                        return true
                    }
                }
            }
        }
        return false
    }
}
