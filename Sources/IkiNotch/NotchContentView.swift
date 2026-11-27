import AppKit
import IkiNotchCore
import SwiftUI
import UniformTypeIdentifiers

private enum ExpandedTab: Equatable {
    case home
    case media
    case tray
    case notes
    case timer
    case stats
    case tools
}

struct NotchContentView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var settings: NotchSettings
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var calendar: CalendarMonitor
    @ObservedObject var capsLock: CapsLockMonitor
    @ObservedObject var privacy: PrivacyIndicatorMonitor
    @ObservedObject var wifi: WiFiMonitor
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var fileShelf: FileShelfStore
    @ObservedObject var systemControls: SystemControlsManager
    @ObservedObject var quickTimer: QuickTimerManager
    @ObservedObject var scratchpad: ScratchpadStore
    @ObservedObject var systemStats: SystemStatsProvider
    var onSetKeyFocusAllowed: ((Bool) -> Void)?

    @State private var selectedTab: ExpandedTab = .home
    @State private var isDropTargeted: Bool = false
    @State private var copiedNoteFeedback: Bool = false
    @State private var copiedIPFeedback: Bool = false
    @State private var pickedHexFeedback: String?

    private var hasCards: Bool {
        true
    }

    private var currentMetrics: NotchMetrics {
        NotchGeometry.metrics(
            for: controller.displayState,
            preset: settings.sizePreset,
            customWidth: settings.customWidth,
            customHeight: settings.customHeight,
            menuBarHeight: controller.menuBarHeight,
            shapeStyle: settings.shapeStyle,
            hasContentCards: hasCards
        )
    }

    private var transitionAnimation: Animation? {
        switch settings.animationStyle {
        case .instant:
            return nil
        case .snappy, .smooth, .bouncy:
            return .spring(
                response: settings.animationStyle.springResponse,
                dampingFraction: settings.animationStyle.springDamping
            )
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchBody
                .frame(width: currentMetrics.totalWidth, height: currentMetrics.height)
                .padding(.top, currentMetrics.topMargin)
                .animation(transitionAnimation, value: controller.displayState)
                .animation(.easeOut(duration: 0.18), value: settings.shapeStyle)
                .animation(.easeOut(duration: 0.18), value: settings.sizePreset)
                .animation(.easeOut(duration: 0.12), value: settings.customWidth)
                .animation(.easeOut(duration: 0.12), value: settings.customHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var notchBody: some View {
        let isPill = settings.shapeStyle == .pill
        let pillShape = RoundedRectangle(
            cornerRadius: currentMetrics.bottomCornerRadius,
            style: .continuous
        )
        let notchShape = NotchShape(
            topEarRadius: currentMetrics.topEarRadius,
            bottomCornerRadius: currentMetrics.bottomCornerRadius
        )
        let notchOutline = NotchShape(
            topEarRadius: currentMetrics.topEarRadius,
            bottomCornerRadius: currentMetrics.bottomCornerRadius,
            closeTopEdge: false
        )

        ZStack {
            if isPill {
                pillShape
                    .fill(Color.black)
                    .overlay(
                        pillShape
                            .stroke(
                                Color.white.opacity(controller.displayState == .collapsed ? 0.14 : 0.18),
                                lineWidth: 0.7
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(controller.displayState == .collapsed ? 0.25 : 0.45),
                        radius: controller.displayState == .expanded ? 16 : 5,
                        x: 0,
                        y: controller.displayState == .expanded ? 7 : 2
                    )
            } else {
                notchShape
                    .fill(Color.black)
                    .overlay(
                        notchOutline
                            .stroke(
                                Color.white.opacity(controller.displayState == .collapsed ? 0.06 : 0.14),
                                lineWidth: 0.6
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(controller.displayState == .collapsed ? 0.0 : 0.42),
                        radius: controller.displayState == .expanded ? 14 : 7,
                        x: 0,
                        y: controller.displayState == .expanded ? 6 : 3
                    )
            }

            Group {
                if controller.displayState == .collapsed {
                    collapsedView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            controller.handleNotchTapped()
                        }
                        .contextMenu {
                            Button("Expand Notch (⌃⌥N)") {
                                controller.expandLocked()
                            }
                            Button(settings.shapeStyle == .notch ? "Switch to Pill Style" : "Switch to Notch Style") {
                                settings.shapeStyle = (settings.shapeStyle == .notch) ? .pill : .notch
                            }
                            Button("Settings...") {
                                controller.onOpenSettings?()
                            }
                            Divider()
                            Button("Quit IkiNotch") {
                                NSApp.terminate(nil)
                            }
                        }
                } else {
                    expandedView
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, isPill ? (controller.displayState == .collapsed ? 10 : 14) : (currentMetrics.topEarRadius + (controller.displayState == .collapsed ? 4 : 10)))
        }
        .clipShape(AnyShape(isPill ? AnyShape(pillShape) : AnyShape(notchShape)))
        .contentShape(AnyShape(isPill ? AnyShape(pillShape) : AnyShape(notchShape)))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers)
        }
        .onChange(of: isDropTargeted) { targeted in
            if targeted && settings.showFileShelf {
                selectedTab = .tray
                if controller.displayState != .expanded {
                    controller.expandLocked()
                }
            }
        }
    }

    // MARK: - Collapsed State (Idle Display + Caps Lock & Keep Awake Icons, 0 Timers)

    private var hasActiveIdleIcons: Bool {
        (settings.showCapsLockIndicator && capsLock.isCapsLockOn)
            || keepAwake.isActive
            || (settings.showPrivacyIndicators && (privacy.isCameraActive || privacy.isMicActive))
    }

    @ViewBuilder
    private var activeStatusIcons: some View {
        if settings.showPrivacyIndicators && privacy.isCameraActive {
            cameraActiveIcon
        }
        if settings.showPrivacyIndicators && privacy.isMicActive {
            micActiveIcon
        }
        if keepAwake.isActive {
            keepAwakeIcon
        }
        if settings.showCapsLockIndicator && capsLock.isCapsLockOn {
            capsLockIcon
        }
    }

    @ViewBuilder
    private var collapsedView: some View {
        switch settings.idleStyle {
        case .pureBlack:
            if hasActiveIdleIcons {
                HStack(spacing: 6) {
                    activeStatusIcons
                }
            } else {
                Color.clear
            }

        case .custom:
            let label = settings.customIdleText.trimmingCharacters(in: .whitespacesAndNewlines)
            HStack(spacing: 8) {
                Text(label.isEmpty ? "IkiNotch" : label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                activeStatusIcons
                if settings.customIdleShowBattery {
                    idleBatteryBadge
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 2)

        case .smartStatus:
            HStack(spacing: 8) {
                if quickTimer.isRunning {
                    HStack(spacing: 4) {
                        Image(systemName: quickTimer.mode == .stopwatch ? "stopwatch" : "timer")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(idleTimerAccent)
                        Text(quickTimer.formattedDisplay)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(idleTimerAccent)
                            .lineLimit(1)
                    }
                } else if let track = nowPlaying.currentTrack, track.isPlaying {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hue: track.accentHue, saturation: 0.78, brightness: 0.92))
                            .frame(width: 6, height: 6)
                        Text(track.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                } else if let event = calendar.nextEvent {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: event.colorHex))
                            .frame(width: 6, height: 6)
                        Text(event.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                } else if let ssid = wifi.currentSSID {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                        if settings.showWiFiName {
                            Text(ssid)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.84))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else {
                    Text("Offline")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }

                activeStatusIcons
                if settings.showBattery {
                    idleBatteryBadge
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 2)
        }
    }

    private var cameraActiveIcon: some View {
        Image(systemName: "video.fill")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Color(red: 0.24, green: 0.85, blue: 0.42))
            .help("Camera in use")
    }

    private var micActiveIcon: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.16))
            .help("Microphone in use")
    }

    private var keepAwakeIcon: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.25))
            .help("Keep Awake On")
    }

    private var capsLockIcon: some View {
        Image(systemName: "capslock.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.25))
            .help("Caps Lock On")
    }

    @ViewBuilder
    private var idleBatteryBadge: some View {
        if battery.status.hasBattery {
            HStack(spacing: 4) {
                if settings.batteryDisplayStyle != .percentOnly {
                    BatteryIconView(
                        percentage: battery.status.percentage,
                        isCharging: battery.status.isCharging
                    )
                }
                if settings.batteryDisplayStyle != .iconOnly {
                    HStack(spacing: 2) {
                        if settings.batteryDisplayStyle == .percentOnly && battery.status.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color(red: 0.24, green: 0.85, blue: 0.42))
                        }
                        Text("\(battery.status.percentage)%")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(
                                settings.batteryDisplayStyle == .percentOnly
                                    ? batteryTint
                                    : .white.opacity(0.84)
                            )
                            .lineLimit(1)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: - Expanded State (Full Info Panel)

    private var expandedView: some View {
        VStack(spacing: 10) {
            // Top bar: all elements centered cleanly with fixed-width icon tabs (0px shift across tabs)
            HStack(spacing: 10) {
                if settings.showClock {
                    TimelineView(.everyMinute) { context in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(Self.timeFormatter.string(from: context.date))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                            Text(Self.shortDateFormatter.string(from: context.date))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                // Fixed-width icon tab bar (never changes width when switching tabs)
                HStack(spacing: 2) {
                    tabPill(icon: "house.fill", title: "Home", tab: .home)
                    if settings.showNowPlaying {
                        tabPill(icon: "music.note", title: "Media", tab: .media)
                    }
                    if settings.showFileShelf {
                        tabPill(
                            icon: "tray.fill",
                            title: fileShelf.items.isEmpty ? "Tray" : "Tray (\(fileShelf.items.count))",
                            tab: .tray,
                            hasBadge: !fileShelf.items.isEmpty
                        )
                    }
                    tabPill(icon: "note.text", title: "Notes", tab: .notes)
                    tabPill(
                        icon: "timer",
                        title: quickTimer.isRunning ? "Timer (\(quickTimer.formattedRemaining))" : "Timer",
                        tab: .timer,
                        hasBadge: quickTimer.isRunning
                    )
                    tabPill(icon: "chart.bar.fill", title: "Stats", tab: .stats)
                    tabPill(icon: "wrench.and.screwdriver.fill", title: "Tools", tab: .tools)
                }
                .padding(2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())

                if settings.showPrivacyIndicators && privacy.isCameraActive {
                    cameraActiveIcon
                }
                if settings.showPrivacyIndicators && privacy.isMicActive {
                    micActiveIcon
                }
                if settings.showCapsLockIndicator && capsLock.isCapsLockOn {
                    capsLockIcon
                }

                if settings.showBattery && battery.status.hasBattery {
                    HStack(spacing: 4) {
                        if settings.batteryDisplayStyle != .percentOnly {
                            BatteryIconView(
                                percentage: battery.status.percentage,
                                isCharging: battery.status.isCharging
                            )
                        }
                        if settings.batteryDisplayStyle != .iconOnly {
                            HStack(spacing: 2) {
                                if settings.batteryDisplayStyle == .percentOnly && battery.status.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(Color(red: 0.24, green: 0.85, blue: 0.42))
                                }
                                Text("\(battery.status.percentage)%")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(
                                        settings.batteryDisplayStyle == .percentOnly
                                            ? batteryTint
                                            : .white.opacity(0.92)
                                    )
                            }
                        }
                        if let timeStr = battery.status.formattedTimeRemaining {
                            Text("· \(timeStr)")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.09))
                    .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    Button {
                        keepAwake.toggle()
                    } label: {
                        Image(systemName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .font(.system(size: 11))
                            .foregroundColor(
                                keepAwake.isActive
                                    ? Color(red: 1.0, green: 0.78, blue: 0.25)
                                    : .white.opacity(0.78)
                            )
                            .frame(width: 24, height: 24)
                            .background(
                                keepAwake.isActive
                                    ? Color(red: 1.0, green: 0.75, blue: 0.20).opacity(0.22)
                                    : Color.white.opacity(0.10)
                            )
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(NotchPressButtonStyle())
                    .help(keepAwake.isActive ? "Keep Awake: ON (Click to turn off)" : "Keep Awake: OFF")

                    Button {
                        controller.collapseImmediately()
                        controller.onOpenSettings?()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.78))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(NotchPressButtonStyle())
                    .help("Settings")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 28)

            Group {
                switch selectedTab {
                case .home:
                    homeDashboardView
                case .media:
                    nowPlayingCard
                case .tray:
                    fileShelfCard
                case .notes:
                    notesCard
                case .timer:
                    timerCard
                case .stats:
                    statsCard
                case .tools:
                    toolsCard
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .padding(.horizontal, 4)
        .onAppear {
            battery.refresh()
            nowPlaying.refreshFromMediaRemote()
            wifi.refresh()
            systemControls.refresh()
            privacy.refresh()
            if selectedTab == .stats {
                systemStats.startLiveUpdates()
            }
            if selectedTab == .notes {
                onSetKeyFocusAllowed?(true)
            }
            if calendar.authState == .authorized {
                calendar.refreshNextEvent()
            }
            if !settings.showFileShelf && selectedTab == .tray {
                selectedTab = .home
            }
            if !settings.showNowPlaying && selectedTab == .media {
                selectedTab = .home
            }
        }
        .onDisappear {
            onSetKeyFocusAllowed?(false)
            systemStats.stopLiveUpdates()
        }
        .onChange(of: selectedTab) { tab in
            onSetKeyFocusAllowed?(tab == .notes)
            if tab == .stats {
                systemStats.startLiveUpdates()
            } else {
                systemStats.stopLiveUpdates()
            }
        }
    }

    // MARK: - Home Dashboard (Combined Summary + Quick Controls)

    private var homeDashboardView: some View {
        VStack(spacing: 8) {
            // Row 1: Compact Mini Media + Calendar & Tray Summary
            HStack(spacing: 8) {
                if settings.showNowPlaying {
                    miniMediaStrip
                }
                summaryStatusCard
            }

            // Row 2: Quick System Controls (Wi-Fi, Bluetooth, Theme, Mute)
            HStack(spacing: 8) {
                quickControlButton(
                    icon: wifi.isPoweredOn ? "wifi" : "wifi.slash",
                    title: (settings.showWiFiName ? wifi.currentSSID : nil) ?? (wifi.isPoweredOn ? "Wi-Fi" : "Wi-Fi Off"),
                    isActive: wifi.isPoweredOn,
                    activeColor: Color(red: 0.04, green: 0.52, blue: 1.0)
                ) {
                    wifi.togglePower()
                }

                quickControlButton(
                    icon: "dot.radiowaves.left.and.right",
                    title: systemControls.connectedBluetoothDevice ?? (systemControls.isBluetoothOn ? "Bluetooth" : "BT Off"),
                    isActive: systemControls.isBluetoothOn,
                    activeColor: Color(red: 0.04, green: 0.52, blue: 1.0)
                ) {
                    systemControls.toggleBluetooth()
                }

                quickControlButton(
                    icon: systemControls.isDarkMode ? "moon.fill" : "sun.max.fill",
                    title: systemControls.isDarkMode ? "Dark" : "Light",
                    isActive: systemControls.isDarkMode,
                    activeColor: Color(red: 0.45, green: 0.36, blue: 0.96)
                ) {
                    systemControls.toggleDarkMode()
                }

                quickControlButton(
                    icon: systemControls.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    title: systemControls.isMuted ? "Muted" : "Sound",
                    isActive: systemControls.isMuted,
                    activeColor: Color(red: 0.95, green: 0.32, blue: 0.28)
                ) {
                    systemControls.toggleAudioMute()
                }
            }
        }
    }

    private var miniMediaStrip: some View {
        HStack(spacing: 8) {
            Button {
                selectedTab = .media
            } label: {
                HStack(spacing: 8) {
                    if let track = nowPlaying.currentTrack {
                        ZStack {
                            if let nsImage = nowPlaying.artworkImage {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(hue: track.accentHue, saturation: 0.72, brightness: 0.75))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "music.note")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("No Media")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressButtonStyle())

            if let track = nowPlaying.currentTrack {
                HStack(spacing: 6) {
                    Button { nowPlaying.togglePlayPause() } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(NotchPressButtonStyle())

                    Button { nowPlaying.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .buttonStyle(NotchPressButtonStyle())
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var summaryStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.showCalendar {
                if calendar.authState == .authorized {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(calendar.nextEvent.map { Color(hex: $0.colorHex) } ?? Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Text(calendar.nextEvent?.title ?? "No upcoming events")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(calendar.nextEvent != nil ? 0.9 : 0.48))
                            .lineLimit(1)
                    }
                } else if calendar.authState == .notDetermined {
                    Button {
                        calendar.requestAccess()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 10))
                            Text("Connect Calendar")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchPressButtonStyle())
                }
            }

            if settings.showFileShelf {
                Button {
                    selectedTab = .tray
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                        Text(fileShelf.items.isEmpty ? "Tray: Empty" : "Tray: \(fileShelf.items.count) item\(fileShelf.items.count == 1 ? "" : "s")")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(NotchPressButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func quickControlButton(
        icon: String,
        title: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.7))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(isActive ? activeColor.opacity(0.85) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(NotchPressButtonStyle())
    }

    private func tabPill(icon: String, title: String, tab: ExpandedTab, hasBadge: Bool = false) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .foregroundColor(isSelected ? .black : .white.opacity(0.72))
                    .background(isSelected ? Color.white : Color.clear)
                    .clipShape(Capsule())

                if hasBadge && !isSelected {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.72, blue: 0.22))
                        .frame(width: 5, height: 5)
                        .offset(x: -3, y: 2)
                }
            }
            .frame(width: 26, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(NotchPressButtonStyle())
        .help(title)
    }

    // MARK: - Notes Card (Quick Scratchpad)

    private var notesCard: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Quick Notes", systemImage: "note.text")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                Spacer()
                Button {
                    scratchpad.copyToClipboard()
                    copiedNoteFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copiedNoteFeedback = false
                    }
                } label: {
                    Text(copiedNoteFeedback ? "Copied!" : "Copy")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(copiedNoteFeedback ? Color(red: 0.24, green: 0.85, blue: 0.42) : .white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(NotchPressButtonStyle())

                Button {
                    scratchpad.clear()
                } label: {
                    Text("Clear")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(NotchPressButtonStyle())
            }

            ZStack(alignment: .topLeading) {
                if scratchpad.text.isEmpty {
                    Text("Type quick notes, links, or to-dos here (auto-saved)...")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.top, 5)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $scratchpad.text)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Timer Card (Countdown, Pomodoro, Stopwatch)

    private var idleTimerAccent: Color {
        if quickTimer.mode == .stopwatch {
            return Color(red: 0.30, green: 0.74, blue: 1.0)
        }
        if quickTimer.isBreakPhase {
            return Color(red: 0.24, green: 0.85, blue: 0.42)
        }
        return Color(red: 1.0, green: 0.72, blue: 0.25)
    }

    private var timerCard: some View {
        HStack(spacing: 14) {
            // Left: Live digits + status + progress bar
            VStack(alignment: .center, spacing: 5) {
                if quickTimer.mode == .pomodoro {
                    Text("\(quickTimer.pomodoroPhase.rawValue) · #\(quickTimer.completedFocusSessions + 1)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(idleTimerAccent)
                } else if quickTimer.mode == .stopwatch, let lap = quickTimer.formattedLastLap {
                    Text("Lap \(lap)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.62))
                } else {
                    Text(quickTimer.mode.rawValue)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }

                Text(quickTimer.formattedDisplay)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(
                        quickTimer.didFinishRecently
                            ? Color(red: 0.24, green: 0.85, blue: 0.42)
                            : .white
                    )

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(quickTimer.isRunning ? idleTimerAccent : Color.white.opacity(0.5))
                            .frame(width: max(4, geo.size.width * quickTimer.progress))
                    }
                }
                .frame(width: 148, height: 5)
            }
            .frame(maxWidth: .infinity)

            // Right: Mode switcher + mode-specific presets + action buttons
            VStack(spacing: 7) {
                HStack(spacing: 2) {
                    ForEach(QuickTimerMode.allCases) { m in
                        let selected = quickTimer.mode == m
                        Button {
                            quickTimer.setMode(m)
                        } label: {
                            Text(m.rawValue)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(selected ? .black : .white.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(selected ? Color.white : Color.clear)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(NotchPressButtonStyle())
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())

                // Mode-specific secondary row
                switch quickTimer.mode {
                case .countdown:
                    HStack(spacing: 5) {
                        ForEach([1, 5, 10, 25, 45], id: \.self) { mins in
                            let isCurrent = quickTimer.totalSeconds == mins * 60
                            Button {
                                quickTimer.selectPreset(minutes: mins)
                            } label: {
                                Text("\(mins)m")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(isCurrent ? .black : .white.opacity(0.8))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(isCurrent ? Color.white : Color.white.opacity(0.10))
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(NotchPressButtonStyle())
                        }
                    }

                case .pomodoro:
                    HStack(spacing: 5) {
                        ForEach([PomodoroPhase.focus, .shortBreak, .longBreak], id: \.rawValue) { phase in
                            let isCurrent = quickTimer.pomodoroPhase == phase
                            Button {
                                quickTimer.selectPomodoroPhase(phase)
                            } label: {
                                Text(phase.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(isCurrent ? .black : .white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(isCurrent ? Color.white : Color.white.opacity(0.10))
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(NotchPressButtonStyle())
                        }
                    }

                case .stopwatch:
                    HStack(spacing: 6) {
                        Button {
                            quickTimer.recordLap()
                        } label: {
                            Label("Mark Lap", systemImage: "flag.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.88))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3.5)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(NotchPressButtonStyle())
                    }
                }

                // Controls row
                HStack(spacing: 6) {
                    if quickTimer.mode == .countdown {
                        Button {
                            quickTimer.adjustMinutes(-1)
                        } label: {
                            Text("-1m")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                                .padding(.horizontal, 7)
                                .frame(height: 26)
                                .background(Color.white.opacity(0.10))
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(NotchPressButtonStyle())
                    }

                    Button {
                        quickTimer.toggleStartPause()
                    } label: {
                        Label(
                            quickTimer.isRunning ? "Pause" : "Start",
                            systemImage: quickTimer.isRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 82, height: 26)
                        .background(
                            quickTimer.isRunning
                                ? Color(red: 1.0, green: 0.58, blue: 0.16)
                                : Color(red: 0.04, green: 0.52, blue: 1.0)
                        )
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(NotchPressButtonStyle())

                    if quickTimer.mode == .countdown {
                        Button {
                            quickTimer.adjustMinutes(1)
                        } label: {
                            Text("+1m")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                                .padding(.horizontal, 7)
                                .frame(height: 26)
                                .background(Color.white.opacity(0.10))
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(NotchPressButtonStyle())
                    }

                    Button {
                        quickTimer.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(NotchPressButtonStyle())
                    .help("Reset")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Stats Card (Live While Visible, 0% CPU When Closed)

    private var statsCard: some View {
        let s = systemStats.snapshot
        return VStack(spacing: 8) {
            // Row 1: CPU, Memory, Disk Free meters
            HStack(spacing: 8) {
                statMeterTile(
                    title: "CPU",
                    value: String(format: "%.0f%%", s.cpuUsagePercent),
                    ratio: s.cpuRatio,
                    tint: s.cpuRatio > 0.80 ? Color(red: 0.95, green: 0.32, blue: 0.28) : Color(red: 1.0, green: 0.68, blue: 0.20)
                )
                statMeterTile(
                    title: "RAM",
                    value: String(format: "%.1f/%.0fG", s.usedMemoryGB, s.totalMemoryGB),
                    ratio: s.memoryRatio,
                    tint: s.memoryRatio > 0.85 ? Color(red: 0.95, green: 0.32, blue: 0.28) : Color(red: 0.04, green: 0.52, blue: 1.0)
                )
                statMeterTile(
                    title: "Disk Free",
                    value: String(format: "%.0f/%.0fG", s.freeDiskGB, s.totalDiskGB),
                    ratio: s.diskUsedRatio,
                    tint: s.diskUsedRatio > 0.88 ? Color(red: 1.0, green: 0.62, blue: 0.18) : Color(red: 0.24, green: 0.85, blue: 0.42)
                )
            }

            // Row 2: Network Speed (Down/Up), Thermal State, Local IP (click to copy), Uptime
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color(red: 0.24, green: 0.85, blue: 0.42))
                        Text(SystemStatsProvider.formatSpeed(s.downloadBytesPerSec))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.9))
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color(red: 0.30, green: 0.68, blue: 1.0))
                        Text(SystemStatsProvider.formatSpeed(s.uploadBytesPerSec))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(thermalColor(s.thermal))
                    Text(s.thermal.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("Thermal State")

                Button {
                    guard s.localIPAddress != "—" && s.localIPAddress != "Offline" else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(s.localIPAddress, forType: .string)
                    copiedIPFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copiedIPFeedback = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "network")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.6))
                        Text(copiedIPFeedback ? "Copied!" : s.localIPAddress)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(copiedIPFeedback ? Color(red: 0.24, green: 0.85, blue: 0.42) : .white.opacity(0.88))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(NotchPressButtonStyle())
                .help("Click to copy Local IP")

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.6))
                    Text(s.uptimeFormatted)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("System Uptime")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func thermalColor(_ level: ThermalLevel) -> Color {
        switch level {
        case .cool: return Color(red: 0.24, green: 0.85, blue: 0.42)
        case .fair: return Color(red: 1.0, green: 0.78, blue: 0.25)
        case .warm: return Color(red: 1.0, green: 0.52, blue: 0.16)
        case .hot: return Color(red: 0.95, green: 0.30, blue: 0.26)
        }
    }

    private func statMeterTile(title: String, value: String, ratio: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                Spacer()
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.92))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: - Tools Card (1-Click macOS Utilities)

    private var toolsCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                toolActionButton(icon: "camera.viewfinder", title: "Screenshot") {
                    controller.collapseImmediately()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        task.arguments = ["-i", "-c"]
                        try? task.run()
                    }
                }

                toolActionButton(
                    icon: "eyedropper.halffull",
                    title: pickedHexFeedback ?? "Color Picker"
                ) {
                    NSColorSampler().show { selectedColor in
                        guard let color = selectedColor?.usingColorSpace(.sRGB) else { return }
                        let r = Int((color.redComponent * 255).rounded())
                        let g = Int((color.greenComponent * 255).rounded())
                        let b = Int((color.blueComponent * 255).rounded())
                        let hex = String(format: "#%02X%02X%02X", r, g, b)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(hex, forType: .string)
                        pickedHexFeedback = hex
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            pickedHexFeedback = nil
                        }
                    }
                }

                toolActionButton(icon: "terminal.fill", title: "Terminal") {
                    controller.collapseImmediately()
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
            }

            HStack(spacing: 8) {
                toolActionButton(icon: "folder.fill", title: "Downloads") {
                    controller.collapseImmediately()
                    let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    NSWorkspace.shared.open(downloads)
                }

                toolActionButton(icon: "waveform.path.ecg", title: "Activity") {
                    controller.collapseImmediately()
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }

                toolActionButton(icon: "lock.fill", title: "Sleep Screen") {
                    controller.collapseImmediately()
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                    task.arguments = ["displaysleepnow"]
                    try? task.run()
                }
            }

            // Compact Volume Slider (CoreAudio, zero idle polling)
            HStack(spacing: 8) {
                Button {
                    systemControls.toggleAudioMute()
                } label: {
                    Image(systemName: systemControls.isMuted || systemControls.outputVolume <= 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(systemControls.isMuted ? Color(red: 0.95, green: 0.32, blue: 0.28) : .white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(NotchPressButtonStyle())
                .help(systemControls.isMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { Double(systemControls.outputVolume) },
                        set: { systemControls.setOutputVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
                .tint(.white)

                Text("\(Int((systemControls.isMuted ? 0 : systemControls.outputVolume * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.68))
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toolActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchPressButtonStyle())
    }

    // MARK: - File Drop Shelf (Tray)

    private var fileShelfCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fileShelf.items.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isDropTargeted ? .accentColor : .white.opacity(0.65))
                    Text(isDropTargeted ? "Release to drop into Tray" : "Drag & drop files here to hold")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Drag out anytime to Finder, Browser, or AirDrop")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.white.opacity(0.16),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
            } else {
                HStack {
                    Text("\(fileShelf.items.count) item\(fileShelf.items.count == 1 ? "" : "s") in Tray")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                    Spacer()
                    Button {
                        shareViaAirDrop(urls: fileShelf.items.map(\.url))
                    } label: {
                        Label("AirDrop", systemImage: "airplayaudio")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(NotchPressButtonStyle())

                    Button {
                        showSharePicker(urls: fileShelf.items.map(\.url))
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(NotchPressButtonStyle())

                    Button {
                        fileShelf.clear()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(NotchPressButtonStyle())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fileShelf.items) { item in
                            shelfItemChip(item)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(isDropTargeted ? 0.12 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shelfItemChip(_ item: ShelfFileItem) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .onTapGesture {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }

                Button {
                    fileShelf.remove(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                        .background(Color.black.clipShape(Circle()))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -3)
            }

            Text(item.fileName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
        }
        .help("\(item.fileName) — Drag out or click to reveal in Finder")
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard settings.showFileShelf else { return false }
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let directURL = item as? URL {
                    url = directURL
                } else {
                    url = nil
                }
                if let url {
                    DispatchQueue.main.async {
                        self.fileShelf.add(urls: [url])
                        self.selectedTab = .tray
                    }
                }
            }
        }
        return handled
    }

    private func shareViaAirDrop(urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    private func showSharePicker(urls: [URL]) {
        guard !urls.isEmpty, let contentView = NSApp.windows.first(where: { $0 is NotchPanel })?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        let anchorRect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: anchorRect, of: contentView, preferredEdge: .minY)
    }

    // MARK: - Now Playing Card (Full Media Tab, Centered Text)

    private var nowPlayingCard: some View {
        Group {
            if let track = nowPlaying.currentTrack {
                HStack(spacing: 16) {
                    ZStack {
                        if let nsImage = nowPlaying.artworkImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hue: track.accentHue, saturation: 0.78, brightness: 0.85),
                                            Color(hue: (track.accentHue + 0.14).truncatingRemainder(dividingBy: 1.0), saturation: 0.72, brightness: 0.45)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 72, height: 72)
                            Image(systemName: track.isPlaying ? "music.note" : "pause.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .center, spacing: 6) {
                        VStack(alignment: .center, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                        }

                        if track.duration > 0 {
                            TimelineView(.periodic(from: .now, by: track.isPlaying ? 1.0 : 60.0)) { context in
                                let elapsed = track.estimatedElapsed(at: context.date)
                                let ratio = min(1.0, max(0.0, elapsed / track.duration))
                                HStack(spacing: 6) {
                                    Text(NowPlayingInfo.formatDuration(elapsed))
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(.white.opacity(0.5))

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.14))
                                            Capsule()
                                                .fill(Color.white.opacity(0.85))
                                                .frame(width: max(3, geo.size.width * ratio))
                                        }
                                    }
                                    .frame(height: 3.5)

                                    Text(NowPlayingInfo.formatDuration(track.duration))
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .frame(maxWidth: 220)
                            }
                        }

                        HStack(spacing: 22) {
                            Button { nowPlaying.previousTrack() } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(NotchPressButtonStyle())

                            Button { nowPlaying.togglePlayPause() } label: {
                                Image(systemName: track.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(NotchPressButtonStyle())

                            Button { nowPlaying.nextTrack() } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(NotchPressButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 14)
            } else {
                VStack(alignment: .center, spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                    Text("Now Playing")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Text("Play audio or video in Browser, Spotify, or Music.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Calendar Card

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                Text("Up Next")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }

            switch calendar.authState {
            case .authorized:
                if let event = calendar.nextEvent {
                    HStack(alignment: .top, spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: event.colorHex))
                            .frame(width: 3, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Text(event.formattedTimeRange())
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(event.calendarTitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                        .lineLimit(1)
                } else {
                    Text("No upcoming events.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                    Spacer(minLength: 0)
                }

            case .notDetermined:
                Text("See your next meeting right in the notch.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    calendar.requestAccess()
                } label: {
                    Text("Connect Calendar")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.85))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

            case .denied:
                Text("Calendar access disabled in System Settings.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Open Privacy Settings")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private var batteryTint: Color {
        if battery.status.isCharging {
            return .green
        }
        if battery.status.percentage <= 20 {
            return .orange
        }
        return .white.opacity(0.9)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f
    }()
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

private struct NotchPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct BatteryIconView: View {
    let percentage: Int
    let isCharging: Bool

    private var fillFraction: CGFloat {
        CGFloat(min(100, max(0, percentage))) / 100.0
    }

    private var fillColor: Color {
        if isCharging {
            return Color(red: 0.24, green: 0.85, blue: 0.42)
        }
        if percentage <= 15 {
            return Color(red: 0.98, green: 0.30, blue: 0.26)
        }
        if percentage <= 25 {
            return Color(red: 1.0, green: 0.72, blue: 0.22)
        }
        return Color.white.opacity(0.92)
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    .frame(width: 20, height: 10.5)

                RoundedRectangle(cornerRadius: 1.3, style: .continuous)
                    .fill(fillColor)
                    .frame(width: max(1.5, 16.0 * fillFraction), height: 6.5)
                    .padding(.leading, 2)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.75), radius: 0.8, x: 0, y: 0)
                        .frame(width: 20, height: 10.5)
                }
            }

            RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .frame(width: 1.5, height: 4)
        }
    }
}
