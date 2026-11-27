import CoreAudio
import CoreMediaIO
import Foundation

/// Event-driven privacy indicator monitor for Camera (CoreMediaIO) and Microphone (CoreAudio).
/// Zero polling timers, zero permissions required (reads hardware running state only).
public final class PrivacyIndicatorMonitor: ObservableObject {
    @Published public private(set) var isCameraActive: Bool = false
    @Published public private(set) var isMicActive: Bool = false

    private let queue = DispatchQueue(label: "com.ikinotch.privacy", qos: .utility)
    private var isListening = false

    private var watchedCameraIDs: [CMIODeviceID] = []
    private var watchedMicIDs: [AudioDeviceID] = []

    private var cameraDevicesListenerBlock: CMIOObjectPropertyListenerBlock?
    private var cameraRunningListenerBlock: CMIOObjectPropertyListenerBlock?
    private var audioDevicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?
    private var micRunningListenerBlock: AudioObjectPropertyListenerBlock?
    private var settleWorkItem: DispatchWorkItem?

    public init(startListening: Bool = true) {
        if startListening {
            start()
        }
    }

    deinit {
        stop()
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !self.isListening else { return }
            self.isListening = true
            self.attachCameraListeners()
            self.attachMicListeners()
            self.refreshStatesOnQueue()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self, self.isListening else { return }
            self.isListening = false
            self.settleWorkItem?.cancel()
            self.settleWorkItem = nil
            self.detachCameraListeners()
            self.detachMicListeners()
            DispatchQueue.main.async {
                self.isCameraActive = false
                self.isMicActive = false
            }
        }
    }

    /// Event-driven on-demand refresh (zero polling).
    public func refresh() {
        queue.async { [weak self] in
            guard let self, self.isListening else { return }
            self.rewatchCameraDevices()
            self.rewatchMicDevices()
            self.refreshStatesOnQueue()
        }
    }

    /// One-shot settle check after hardware device list or camera transitions
    /// (covers macOS Voice Processing / WebRTC aggregate mic devices starting slightly after creation).
    private func scheduleOneShotSettleRefresh() {
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            self.rewatchMicDevices()
            self.refreshStatesOnQueue()
        }
        settleWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func refreshStatesOnQueue() {
        let camOn = watchedCameraIDs.contains { Self.isCameraRunning($0) }
        let micOn = watchedMicIDs.contains { Self.isAudioDeviceRunning($0) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isCameraActive != camOn {
                self.isCameraActive = camOn
            }
            if self.isMicActive != micOn {
                self.isMicActive = micOn
            }
        }
    }

    // MARK: - CoreMediaIO (Camera)

    private func attachCameraListeners() {
        let devicesBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isListening else { return }
            self.rewatchCameraDevices()
            self.refreshStatesOnQueue()
        }
        cameraDevicesListenerBlock = devicesBlock

        var devicesAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddr,
            queue,
            devicesBlock
        )

        cameraRunningListenerBlock = { [weak self] _, _ in
            guard let self, self.isListening else { return }
            self.refreshStatesOnQueue()
            self.scheduleOneShotSettleRefresh()
        }

        rewatchCameraDevices()
    }

    private func rewatchCameraDevices() {
        if let runningBlock = cameraRunningListenerBlock {
            var runAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            for id in watchedCameraIDs {
                CMIOObjectRemovePropertyListenerBlock(id, &runAddr, queue, runningBlock)
            }
        }

        watchedCameraIDs = Self.fetchCameraDeviceIDs()

        if let runningBlock = cameraRunningListenerBlock {
            var runAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            for id in watchedCameraIDs {
                CMIOObjectAddPropertyListenerBlock(id, &runAddr, queue, runningBlock)
            }
        }
    }

    private func detachCameraListeners() {
        if let devicesBlock = cameraDevicesListenerBlock {
            var devicesAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            CMIOObjectRemovePropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject),
                &devicesAddr,
                queue,
                devicesBlock
            )
            cameraDevicesListenerBlock = nil
        }

        if let runningBlock = cameraRunningListenerBlock {
            var runAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            for id in watchedCameraIDs {
                CMIOObjectRemovePropertyListenerBlock(id, &runAddr, queue, runningBlock)
            }
            cameraRunningListenerBlock = nil
        }
        watchedCameraIDs.removeAll()
    }

    private static func fetchCameraDeviceIDs() -> [CMIODeviceID] {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var ids = [CMIODeviceID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &addr,
            0,
            nil,
            dataSize,
            &dataUsed,
            &ids
        )
        guard status == noErr else { return [] }
        return ids
    }

    private static func isCameraRunning(_ deviceID: CMIODeviceID) -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var isRunning: UInt32 = 0
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            deviceID,
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &dataUsed,
            &isRunning
        )
        return status == noErr && isRunning != 0
    }

    // MARK: - CoreAudio (Microphone Input)

    private func attachMicListeners() {
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isListening else { return }
            self.rewatchMicDevices()
            self.refreshStatesOnQueue()
            self.scheduleOneShotSettleRefresh()
        }
        audioDevicesListenerBlock = devicesBlock

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            queue,
            devicesBlock
        )

        let defaultInputBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isListening else { return }
            self.rewatchMicDevices()
            self.refreshStatesOnQueue()
            self.scheduleOneShotSettleRefresh()
        }
        defaultInputListenerBlock = defaultInputBlock

        var defaultInputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddr,
            queue,
            defaultInputBlock
        )

        micRunningListenerBlock = { [weak self] _, _ in
            guard let self, self.isListening else { return }
            self.refreshStatesOnQueue()
        }

        rewatchMicDevices()
    }

    private func rewatchMicDevices() {
        if let runningBlock = micRunningListenerBlock {
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeWildcard,
                mElement: kAudioObjectPropertyElementWildcard
            )
            for id in watchedMicIDs {
                AudioObjectRemovePropertyListenerBlock(id, &runAddr, queue, runningBlock)
            }
        }

        watchedMicIDs = Self.fetchAudioInputDeviceIDs()

        if let runningBlock = micRunningListenerBlock {
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeWildcard,
                mElement: kAudioObjectPropertyElementWildcard
            )
            for id in watchedMicIDs {
                AudioObjectAddPropertyListenerBlock(id, &runAddr, queue, runningBlock)
            }
        }
    }

    private func detachMicListeners() {
        if let devicesBlock = audioDevicesListenerBlock {
            var devicesAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddr,
                queue,
                devicesBlock
            )
            audioDevicesListenerBlock = nil
        }

        if let defaultInputBlock = defaultInputListenerBlock {
            var defaultInputAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddr,
                queue,
                defaultInputBlock
            )
            defaultInputListenerBlock = nil
        }

        if let runningBlock = micRunningListenerBlock {
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeWildcard,
                mElement: kAudioObjectPropertyElementWildcard
            )
            for id in watchedMicIDs {
                AudioObjectRemovePropertyListenerBlock(id, &runAddr, queue, runningBlock)
            }
            micRunningListenerBlock = nil
        }
        watchedMicIDs.removeAll()
    }

    private static func fetchAudioInputDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }

        return ids.filter { hasInputStreams($0) }
    }

    private static func hasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return false
        }

        let bufferListPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPtr.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &dataSize, bufferListPtr) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        hasStreams(deviceID, scope: kAudioDevicePropertyScopeInput)
    }

    private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        hasStreams(deviceID, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func isAudioDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &inputAddr, 0, nil, &dataSize, &isRunning) == noErr,
           isRunning != 0 {
            return true
        }

        // For dedicated input-only microphones (e.g. Built-in Mic / USB Mic with no output streams),
        // CoreAudio reliably reports running state on kAudioObjectPropertyScopeGlobal.
        if !hasOutputStreams(deviceID) {
            var globalAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            isRunning = 0
            dataSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceID, &globalAddr, 0, nil, &dataSize, &isRunning) == noErr,
               isRunning != 0 {
                return true
            }
        }
        return false
    }
}
