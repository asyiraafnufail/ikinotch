import AppKit
import Darwin
import Foundation
import ImageIO

public struct NowPlayingInfo: Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let sourceName: String
    public let isPlaying: Bool
    public let artworkData: Data?
    public let accentHue: Double
    public let duration: Double
    public let elapsedTime: Double
    public let playbackRate: Double
    public let elapsedTimestamp: Date

    public init(
        title: String,
        artist: String,
        album: String,
        sourceName: String,
        isPlaying: Bool,
        artworkData: Data? = nil,
        duration: Double = 0,
        elapsedTime: Double = 0,
        playbackRate: Double = 1.0,
        elapsedTimestamp: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.sourceName = sourceName
        self.isPlaying = isPlaying
        self.artworkData = artworkData
        self.accentHue = Self.stableHue(from: "\(title)|\(artist)")
        self.duration = max(0, duration)
        self.elapsedTime = max(0, elapsedTime)
        self.playbackRate = playbackRate
        self.elapsedTimestamp = elapsedTimestamp
    }

    public func estimatedElapsed(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let delta = isPlaying ? max(0, date.timeIntervalSince(elapsedTimestamp)) * max(0, playbackRate) : 0
        return min(duration, max(0, elapsedTime + delta))
    }

    public static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    private static func stableHue(from seed: String) -> Double {
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Double(hash % 360) / 360.0
    }
}

/// System-wide, event-driven Now Playing monitor backed by macOS MediaRemote
/// (supports Brave, Chrome, Safari, YouTube, Spotify, Apple Music, VLC, etc.) with zero polling.
public final class NowPlayingMonitor: ObservableObject {
    public static let musicNotification = Notification.Name("com.apple.Music.playerInfo")
    public static let spotifyNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    private static let mrInfoChanged = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    private static let mrIsPlayingChanged = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    private static let mrAppChanged = Notification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification")

    @Published public private(set) var currentTrack: NowPlayingInfo?
    @Published public private(set) var artworkImage: NSImage?

    private let bridge = MediaRemoteBridge()
    private var localObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var lastKnownIsPlaying: Bool = false
    private var lastArtworkHash: Int?

    public init(startListening: Bool = true) {
        if startListening {
            start()
        }
    }

    deinit {
        stop()
    }

    public func start() {
        if bridge.isAvailable && localObservers.isEmpty {
            bridge.registerForNotifications(on: .main)

            let nc = NotificationCenter.default
            let o1 = nc.addObserver(forName: Self.mrInfoChanged, object: nil, queue: .main) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
            let o2 = nc.addObserver(forName: Self.mrIsPlayingChanged, object: nil, queue: .main) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
            let o3 = nc.addObserver(forName: Self.mrAppChanged, object: nil, queue: .main) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
            localObservers = [o1, o2, o3]
            refreshFromMediaRemote()
        }

        // Also keep DistributedNotificationCenter fallback for Spotify / Music
        if distributedObservers.isEmpty {
            let dnc = DistributedNotificationCenter.default()
            let musicObs = dnc.addObserver(forName: Self.musicNotification, object: nil, queue: .main) { [weak self] notif in
                self?.handleDistributedFallback(notif)
            }
            let spotifyObs = dnc.addObserver(forName: Self.spotifyNotification, object: nil, queue: .main) { [weak self] notif in
                self?.handleDistributedFallback(notif)
            }
            distributedObservers = [musicObs, spotifyObs]
        }
    }

    public func stop() {
        if !localObservers.isEmpty {
            let nc = NotificationCenter.default
            for obs in localObservers {
                nc.removeObserver(obs)
            }
            localObservers.removeAll()
            bridge.unregisterForNotifications()
        }

        if !distributedObservers.isEmpty {
            let dnc = DistributedNotificationCenter.default()
            for obs in distributedObservers {
                dnc.removeObserver(obs)
            }
            distributedObservers.removeAll()
        }
    }

    public func refreshFromMediaRemote() {
        guard bridge.isAvailable else { return }

        bridge.getIsPlaying(on: .main) { [weak self] isPlaying in
            guard let self else { return }
            self.lastKnownIsPlaying = isPlaying

            self.bridge.getNowPlayingInfo(on: .main) { [weak self] dict in
                guard let self else { return }
                guard let dict, !dict.isEmpty else {
                    self.currentTrack = nil
                    self.updateCachedArtwork(from: nil)
                    return
                }
                let parsed = Self.parseMediaRemoteDictionary(dict, fallbackIsPlaying: self.lastKnownIsPlaying)
                self.currentTrack = parsed
                self.updateCachedArtwork(from: parsed?.artworkData)
            }
        }
    }

    private func updateCachedArtwork(from data: Data?) {
        guard let data, !data.isEmpty else {
            lastArtworkHash = nil
            if artworkImage != nil {
                artworkImage = nil
            }
            return
        }
        let hash = data.hashValue
        guard hash != lastArtworkHash else { return }
        lastArtworkHash = hash

        // Decode & downsample once off the main thread (max 128px) to keep memory & CPU minimal
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = Self.downsampledImage(from: data, maxDimension: 128)
            DispatchQueue.main.async {
                guard let self, self.lastArtworkHash == hash else { return }
                self.artworkImage = image
            }
        }
    }

    private static func downsampledImage(from data: Data, maxDimension: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return NSImage(data: data)
    }

    // MARK: - Playback Controls (System-Wide: Browser, Music, Spotify, VLC, etc.)

    public func togglePlayPause() {
        if bridge.isAvailable {
            _ = bridge.sendCommand(.togglePlayPause)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.refreshFromMediaRemote()
            }
        }
    }

    public func nextTrack() {
        if bridge.isAvailable {
            _ = bridge.sendCommand(.nextTrack)
        }
    }

    public func previousTrack() {
        if bridge.isAvailable {
            _ = bridge.sendCommand(.previousTrack)
        }
    }

    public func seek(to seconds: Double) {
        guard bridge.isAvailable, let track = currentTrack, track.duration > 0 else { return }
        let clamped = min(track.duration, max(0, seconds))
        bridge.setElapsedTime(clamped)
        currentTrack = NowPlayingInfo(
            title: track.title,
            artist: track.artist,
            album: track.album,
            sourceName: track.sourceName,
            isPlaying: track.isPlaying,
            artworkData: track.artworkData,
            duration: track.duration,
            elapsedTime: clamped,
            playbackRate: track.playbackRate,
            elapsedTimestamp: Date()
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.refreshFromMediaRemote()
        }
    }

    // MARK: - Parsers (Pure & Unit-Testable)

    public static func parseMediaRemoteDictionary(
        _ dict: [String: Any],
        fallbackIsPlaying: Bool
    ) -> NowPlayingInfo? {
        let title = (dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }

        let artist = (dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = (dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artworkData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

        let playbackRate: Double
        let isPlaying: Bool
        if let rate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue {
            playbackRate = rate
            isPlaying = rate > 0.0
        } else {
            playbackRate = fallbackIsPlaying ? 1.0 : 0.0
            isPlaying = fallbackIsPlaying
        }

        let duration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
        let elapsed = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let timestamp = (dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date) ?? Date()

        return NowPlayingInfo(
            title: title,
            artist: artist.isEmpty ? "Now Playing" : artist,
            album: album,
            sourceName: album.isEmpty ? "Media" : album,
            isPlaying: isPlaying,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: elapsed,
            playbackRate: playbackRate,
            elapsedTimestamp: timestamp
        )
    }

    private func handleDistributedFallback(_ notification: Notification) {
        if bridge.isAvailable {
            refreshFromMediaRemote()
            return
        }
        guard let parsed = Self.parseNotification(name: notification.name, userInfo: notification.userInfo) else {
            if let state = Self.extractPlayerState(from: notification.userInfo),
               state.lowercased() == "stopped" {
                currentTrack = nil
            }
            return
        }
        currentTrack = parsed
    }

    public static func extractPlayerState(from userInfo: [AnyHashable: Any]?) -> String? {
        guard let userInfo else { return nil }
        return (userInfo["Player State"] as? String) ?? (userInfo["Playback State"] as? String)
    }

    public static func parseNotification(
        name: Notification.Name,
        userInfo: [AnyHashable: Any]?
    ) -> NowPlayingInfo? {
        let sourceName: String
        switch name {
        case musicNotification: sourceName = "Music"
        case spotifyNotification: sourceName = "Spotify"
        default: return nil
        }

        guard let userInfo else { return nil }
        let stateString = (extractPlayerState(from: userInfo) ?? "").lowercased()
        if stateString == "stopped" {
            return nil
        }

        let title = (userInfo["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }

        let artist = (userInfo["Artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = (userInfo["Album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return NowPlayingInfo(
            title: title,
            artist: artist.isEmpty ? sourceName : artist,
            album: album,
            sourceName: sourceName,
            isPlaying: stateString == "playing"
        )
    }
}

// MARK: - Dynamic MediaRemote.framework Bridge

private final class MediaRemoteBridge {
    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias UnregisterFn = @convention(c) () -> Void
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias SetElapsedTimeFn = @convention(c) (Double) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let registerFn: RegisterFn?
    private let unregisterFn: UnregisterFn?
    private let getInfoFn: GetInfoFn?
    private let getIsPlayingFn: GetIsPlayingFn?
    private let sendCommandFn: SendCommandFn?
    private let setElapsedTimeFn: SetElapsedTimeFn?

    var isAvailable: Bool {
        registerFn != nil && getInfoFn != nil
    }

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let h = dlopen(path, RTLD_LAZY)
        self.handle = h

        if let h {
            self.registerFn = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications")
                .map { unsafeBitCast($0, to: RegisterFn.self) }
            self.unregisterFn = dlsym(h, "MRMediaRemoteUnregisterForNowPlayingNotifications")
                .map { unsafeBitCast($0, to: UnregisterFn.self) }
            self.getInfoFn = dlsym(h, "MRMediaRemoteGetNowPlayingInfo")
                .map { unsafeBitCast($0, to: GetInfoFn.self) }
            self.getIsPlayingFn = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
                .map { unsafeBitCast($0, to: GetIsPlayingFn.self) }
            self.sendCommandFn = dlsym(h, "MRMediaRemoteSendCommand")
                .map { unsafeBitCast($0, to: SendCommandFn.self) }
            self.setElapsedTimeFn = dlsym(h, "MRMediaRemoteSetElapsedTime")
                .map { unsafeBitCast($0, to: SetElapsedTimeFn.self) }
        } else {
            self.registerFn = nil
            self.unregisterFn = nil
            self.getInfoFn = nil
            self.getIsPlayingFn = nil
            self.sendCommandFn = nil
            self.setElapsedTimeFn = nil
        }
    }

    func registerForNotifications(on queue: DispatchQueue) {
        registerFn?(queue)
    }

    func unregisterForNotifications() {
        unregisterFn?()
    }

    func getNowPlayingInfo(on queue: DispatchQueue, completion: @escaping ([String: Any]?) -> Void) {
        guard let getInfoFn else {
            completion(nil)
            return
        }
        getInfoFn(queue) { nsDict in
            completion(nsDict as? [String: Any])
        }
    }

    func getIsPlaying(on queue: DispatchQueue, completion: @escaping (Bool) -> Void) {
        guard let getIsPlayingFn else {
            completion(false)
            return
        }
        getIsPlayingFn(queue) { playing in
            completion(playing)
        }
    }

    func sendCommand(_ command: Command) -> Bool {
        sendCommandFn?(command.rawValue, nil) ?? false
    }

    func setElapsedTime(_ seconds: Double) {
        setElapsedTimeFn?(seconds)
    }
}
