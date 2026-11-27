import AppKit
import Foundation

public enum QuickTimerMode: String, CaseIterable, Identifiable {
    case countdown = "Timer"
    case pomodoro = "Pomodoro"
    case stopwatch = "Stopwatch"

    public var id: String { rawValue }
}

public enum PomodoroPhase: String, Equatable {
    case focus = "Focus"
    case shortBreak = "Break"
    case longBreak = "Long Break"

    public var durationSeconds: Int {
        switch self {
        case .focus: return 25 * 60
        case .shortBreak: return 5 * 60
        case .longBreak: return 15 * 60
        }
    }
}

/// Multi-mode timer (Countdown with +/-1m, Pomodoro Focus/Break cycles, and Stopwatch with Lap).
/// Runs a 1-second DispatchSourceTimer ONLY while `isRunning == true` (0% CPU when idle or paused).
public final class QuickTimerManager: ObservableObject {
    @Published public private(set) var mode: QuickTimerMode = .countdown
    @Published public private(set) var totalSeconds: Int = 25 * 60
    @Published public private(set) var remainingSeconds: Int = 25 * 60
    @Published public private(set) var elapsedSeconds: Int = 0
    @Published public private(set) var lastLapSeconds: Int?
    @Published public private(set) var pomodoroPhase: PomodoroPhase = .focus
    @Published public private(set) var completedFocusSessions: Int = 0
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var didFinishRecently: Bool = false

    private var timer: DispatchSourceTimer?

    public init() {}

    deinit {
        stopTimer()
    }

    public var progress: Double {
        switch mode {
        case .countdown, .pomodoro:
            guard totalSeconds > 0 else { return 0 }
            return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
        case .stopwatch:
            return Double(elapsedSeconds % 60) / 60.0
        }
    }

    public var formattedDisplay: String {
        let secs = (mode == .stopwatch) ? elapsedSeconds : remainingSeconds
        return Self.formatSeconds(secs)
    }

    public var formattedRemaining: String {
        formattedDisplay
    }

    public var formattedLastLap: String? {
        lastLapSeconds.map(Self.formatSeconds)
    }

    public var isBreakPhase: Bool {
        mode == .pomodoro && pomodoroPhase != .focus
    }

    public static func formatSeconds(_ total: Int) -> String {
        let clamped = max(0, total)
        let hours = clamped / 3600
        let mins = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    public func setMode(_ newMode: QuickTimerMode) {
        guard mode != newMode else { return }
        stopTimer()
        mode = newMode
        didFinishRecently = false
        switch newMode {
        case .countdown:
            if totalSeconds <= 0 { totalSeconds = 25 * 60 }
            remainingSeconds = totalSeconds
        case .pomodoro:
            pomodoroPhase = .focus
            totalSeconds = pomodoroPhase.durationSeconds
            remainingSeconds = totalSeconds
        case .stopwatch:
            elapsedSeconds = 0
            lastLapSeconds = nil
        }
    }

    public func selectPreset(minutes: Int) {
        stopTimer()
        mode = .countdown
        let seconds = max(60, minutes * 60)
        totalSeconds = seconds
        remainingSeconds = seconds
        didFinishRecently = false
    }

    public func adjustMinutes(_ deltaMinutes: Int) {
        guard mode == .countdown else { return }
        let delta = deltaMinutes * 60
        let newRemaining = min(180 * 60, max(60, remainingSeconds + delta))
        remainingSeconds = newRemaining
        if newRemaining > totalSeconds || !isRunning {
            totalSeconds = max(60, newRemaining)
        }
        didFinishRecently = false
    }

    public func selectPomodoroPhase(_ phase: PomodoroPhase) {
        stopTimer()
        mode = .pomodoro
        pomodoroPhase = phase
        totalSeconds = phase.durationSeconds
        remainingSeconds = totalSeconds
        didFinishRecently = false
    }

    public func recordLap() {
        guard mode == .stopwatch, elapsedSeconds > 0 else { return }
        lastLapSeconds = elapsedSeconds
    }

    public func toggleStartPause() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    public func start() {
        guard !isRunning else { return }
        if mode != .stopwatch && remainingSeconds <= 0 {
            remainingSeconds = totalSeconds
        }
        didFinishRecently = false
        isRunning = true

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.resume()
    }

    public func pause() {
        stopTimer()
    }

    public func reset() {
        stopTimer()
        didFinishRecently = false
        switch mode {
        case .countdown:
            remainingSeconds = totalSeconds
        case .pomodoro:
            totalSeconds = pomodoroPhase.durationSeconds
            remainingSeconds = totalSeconds
        case .stopwatch:
            elapsedSeconds = 0
            lastLapSeconds = nil
        }
    }

    private func tick() {
        if mode == .stopwatch {
            elapsedSeconds += 1
            return
        }

        guard remainingSeconds > 1 else {
            remainingSeconds = 0
            stopTimer()
            didFinishRecently = true
            NSSound(named: NSSound.Name("Glass"))?.play()

            if mode == .pomodoro {
                advancePomodoroPhase()
            }
            return
        }
        remainingSeconds -= 1
    }

    private func advancePomodoroPhase() {
        if pomodoroPhase == .focus {
            completedFocusSessions += 1
            pomodoroPhase = (completedFocusSessions % 4 == 0) ? .longBreak : .shortBreak
        } else {
            pomodoroPhase = .focus
        }
        totalSeconds = pomodoroPhase.durationSeconds
        remainingSeconds = totalSeconds
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }
}
