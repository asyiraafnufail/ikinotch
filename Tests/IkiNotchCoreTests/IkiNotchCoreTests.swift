import XCTest
@testable import IkiNotchCore

final class IkiNotchCoreTests: XCTestCase {
    func testCollapsedGeometryStaysAnchoredToTopCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NotchGeometry.panelFrame(
            for: .collapsed,
            screenFrame: screen,
            preset: .standard,
            customWidth: 194,
            customHeight: 31,
            menuBarHeight: 24,
            horizontalOffset: 0,
            useExpandedWindowBounds: false
        )

        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.5)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.height, 24, accuracy: 0.5)
        XCTAssertLessThan(frame.width, 230)
    }

    func testHorizontalSnapToCenterAndClamping() {
        XCTAssertEqual(
            NotchGeometry.snappedHorizontalOffset(5, screenWidth: 1440, collapsedTotalWidth: 210),
            0
        )
        XCTAssertEqual(
            NotchGeometry.snappedHorizontalOffset(-7, screenWidth: 1440, collapsedTotalWidth: 210),
            0
        )
        let clamped = NotchGeometry.snappedHorizontalOffset(9999, screenWidth: 1440, collapsedTotalWidth: 210)
        XCTAssertLessThan(clamped, 720)
    }

    func testBatteryParsing() {
        let dict: [String: Any] = [
            "Type": "InternalBattery",
            "Current Capacity": 82,
            "Max Capacity": 100,
            "Is Charging": true,
            "Power Source State": "AC Power",
            "Time to Full Charge": 45
        ]
        let parsed = BatteryMonitor.parsePowerSourceDictionary(dict)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.percentage, 82)
        XCTAssertEqual(parsed?.isCharging, true)
        XCTAssertEqual(parsed?.isPluggedIn, true)
        XCTAssertEqual(parsed?.formattedTimeRemaining, "45m")
        XCTAssertEqual(parsed?.symbolName, "battery.100.bolt")
    }

    func testNowPlayingSpotifyAndMusicParsing() {
        let spotifyInfo: [AnyHashable: Any] = [
            "Name": "Bohemian Rhapsody",
            "Artist": "Queen",
            "Album": "A Night at the Opera",
            "Playback State": "Playing"
        ]
        let spotify = NowPlayingMonitor.parseNotification(
            name: NowPlayingMonitor.spotifyNotification,
            userInfo: spotifyInfo
        )
        XCTAssertEqual(spotify?.title, "Bohemian Rhapsody")
        XCTAssertEqual(spotify?.artist, "Queen")
        XCTAssertEqual(spotify?.sourceName, "Spotify")
        XCTAssertEqual(spotify?.isPlaying, true)

        let mrTrack = NowPlayingMonitor.parseMediaRemoteDictionary([
            "kMRMediaRemoteNowPlayingInfoTitle": "Lofi Hip Hop Radio",
            "kMRMediaRemoteNowPlayingInfoArtist": "Lofi Girl",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1.0)
        ], fallbackIsPlaying: false)
        XCTAssertEqual(mrTrack?.title, "Lofi Hip Hop Radio")
        XCTAssertEqual(mrTrack?.artist, "Lofi Girl")
        XCTAssertEqual(mrTrack?.isPlaying, true)

        let stopped = NowPlayingMonitor.parseNotification(
            name: NowPlayingMonitor.musicNotification,
            userInfo: ["Player State": "Stopped", "Name": "Old Song"]
        )
        XCTAssertNil(stopped)
    }

    func testControllerClickExpandAndCollapse() {
        let suiteName = "com.ikinotch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = NotchSettings(defaults: defaults)
        let controller = NotchController(settings: settings)

        XCTAssertEqual(controller.displayState, .collapsed)
        XCTAssertFalse(controller.useExpandedWindowBounds)

        controller.handleNotchTapped()
        XCTAssertEqual(controller.displayState, .expanded)
        XCTAssertTrue(controller.isLockedExpanded)
        XCTAssertTrue(controller.useExpandedWindowBounds)

        controller.handleNotchTapped()
        XCTAssertEqual(controller.displayState, .collapsed)
        XCTAssertFalse(controller.isLockedExpanded)
    }

    func testFullscreenWindowBoundsDetection() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let quartz = NotchGeometry.quartzRect(for: screen, primaryScreenHeight: 900)
        XCTAssertEqual(quartz, CGRect(x: 0, y: 0, width: 1440, height: 900))

        // True fullscreen covers full 1440x900 from (0,0)
        XCTAssertTrue(NotchGeometry.isWindowBoundsFullscreen(
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            onScreenQuartzRect: quartz
        ))

        // Normal maximized window starts below 25pt menu bar
        XCTAssertFalse(NotchGeometry.isWindowBoundsFullscreen(
            CGRect(x: 0, y: 25, width: 1440, height: 875),
            onScreenQuartzRect: quartz
        ))
    }

    func testFileShelfDeduplicationAndRemoval() {
        let shelf = FileShelfStore()
        let fileA = URL(fileURLWithPath: "/tmp/demo-a.txt")
        let fileB = URL(fileURLWithPath: "/tmp/demo-b.png")

        shelf.add(urls: [fileA, fileB, fileA])
        XCTAssertEqual(shelf.items.count, 2)
        XCTAssertEqual(shelf.items.first?.fileName, "demo-b.png")

        if let firstID = shelf.items.first?.id {
            shelf.remove(id: firstID)
        }
        XCTAssertEqual(shelf.items.count, 1)

        shelf.clear()
        XCTAssertTrue(shelf.items.isEmpty)
    }

    func testQuickTimerFormattingAndUptime() {
        let timer = QuickTimerManager()
        timer.selectPreset(minutes: 5)
        XCTAssertEqual(timer.formattedRemaining, "05:00")
        timer.adjustMinutes(1)
        XCTAssertEqual(timer.formattedRemaining, "06:00")
        timer.setMode(.pomodoro)
        XCTAssertEqual(timer.pomodoroPhase, .focus)
        XCTAssertEqual(timer.formattedDisplay, "25:00")
        timer.selectPomodoroPhase(.shortBreak)
        XCTAssertEqual(timer.formattedDisplay, "05:00")
        timer.setMode(.stopwatch)
        XCTAssertEqual(timer.formattedDisplay, "00:00")
        XCTAssertFalse(timer.isRunning)

        XCTAssertEqual(SystemStatsProvider.formatUptime(9000), "2h 30m")
        XCTAssertEqual(SystemStatsProvider.formatUptime(90000), "1d 1h")
        XCTAssertEqual(SystemStatsProvider.formatSpeed(512), "512 B/s")
        XCTAssertEqual(SystemStatsProvider.formatSpeed(204_800), "200 KB/s")
        XCTAssertEqual(SystemStatsProvider.formatSpeed(2_621_440), "2.5 MB/s")
    }
}
