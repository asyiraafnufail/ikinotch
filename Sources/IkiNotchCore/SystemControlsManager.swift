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
    @Published public private(set) var outputVolume: Float = 0.5

    private typealias SetBTPowerFn = @convention(c) (Int32) -> Void
    private let setBTPowerFn: SetBTPowerFn?
    private var bluetoothTransitionLockUntil: Date?
    private var bluetoothRefreshWorkItem: DispatchWorkItem?

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
        refreshAudioVolume()
    }

    // MARK: - Bluetooth

    public func refreshBluetooth(force: Bool = false) {
        if !force, let lockUntil = bluetoothTransitionLockUntil, Date() < lockUntil {
            return
        }
        bluetoothTransitionLockUntil = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let isOn: Bool
            if let controller = IOBluetoothHostController.default() {
                isOn = (controller.powerState == kBluetoothHCIPowerStateON)
            } else {
                isOn = false
            }

            let deviceName: String?
            if isOn, let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
                deviceName = devices.first(where: { $0.isConnected() })?.name
            } else {
                deviceName = nil
            }

            DispatchQueue.main.async {
                guard let self else { return }
                if let lockUntil = self.bluetoothTransitionLockUntil, Date() < lockUntil {
                    return
                }
                if self.isBluetoothOn != isOn {
                    self.isBluetoothOn = isOn
                }
                if self.connectedBluetoothDevice != deviceName {
                    self.connectedBluetoothDevice = deviceName
                }
            }
        }
    }

    public func toggleBluetooth() {
        let target: Int32 = isBluetoothOn ? 0 : 1
        if let fn = setBTPowerFn {
            bluetoothRefreshWorkItem?.cancel()
            fn(target)
            isBluetoothOn = (target == 1)
            if !isBluetoothOn {
                connectedBluetoothDevice = nil
            }
            // Hardware Bluetooth radio takes ~1.5-2.0s to finish powering up;
            // hold optimistic UI state until hardware settles so it never bounces back to "BT Off".
            bluetoothTransitionLockUntil = Date().addingTimeInterval(2.2)
            let work = DispatchWorkItem { [weak self] in
                self?.refreshBluetooth(force: true)
            }
            bluetoothRefreshWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
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

    public func refreshAudioVolume() {
        guard let deviceID = defaultOutputDeviceID() else { return }
        if let vol = readVolumeScalar(deviceID: deviceID) {
            outputVolume = vol
        }
    }

    public func setOutputVolume(_ volume: Float) {
        let clamped = min(1.0, max(0.0, volume))
        outputVolume = clamped
        guard let deviceID = defaultOutputDeviceID() else { return }
        _ = writeVolumeScalar(deviceID: deviceID, volume: clamped)
        if clamped > 0.01 && isMuted {
            if writeMuteState(deviceID: deviceID, muted: false) {
                isMuted = false
            }
        }
    }

    private func readVolumeScalar(deviceID: AudioDeviceID) -> Float? {
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
                if status == noErr {
                    return min(1.0, max(0.0, volume))
                }
            }
        }
        return nil
    }

    private func writeVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool {
        var value: Float32 = min(1.0, max(0.0, volume))
        let size = UInt32(MemoryLayout<Float32>.size)
        var succeeded = false

        // Try main element first; if not settable, set left & right channels (1 and 2)
        var mainAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &mainAddr) {
            var settable: DarwinBoolean = false
            if AudioObjectIsPropertySettable(deviceID, &mainAddr, &settable) == noErr, settable.boolValue {
                if AudioObjectSetPropertyData(deviceID, &mainAddr, 0, nil, size, &value) == noErr {
                    return true
                }
            }
        }

        for channel: UInt32 in [1, 2] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            if AudioObjectHasProperty(deviceID, &addr) {
                var settable: DarwinBoolean = false
                if AudioObjectIsPropertySettable(deviceID, &addr, &settable) == noErr, settable.boolValue {
                    if AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &value) == noErr {
                        succeeded = true
                    }
                }
            }
        }
        return succeeded
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
