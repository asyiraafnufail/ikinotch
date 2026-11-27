import AppKit
import Foundation

/// Lightweight countdown / Pomodoro timer.
/// Runs a 1-second DispatchSourceTimer ONLY while `isRunning == true` (0% CPU when idle or paused).
public final class QuickTimerManager: ObservableObject {
    @Published public private(set) var totalSeconds: Int = 25 * 60
    @Published public private(set) var remainingSeconds: Int = 25 * 60
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var didFinishRecently: Bool = false

    private var timer: DispatchSourceTimer?

    public init() {}

    deinit {
        stopTimer()
    }

    public var isActiveOrPaused: Bool {
        isRunning || (remainingSeconds > 0 && remainingSeconds < totalSeconds)
    }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    public var formattedRemaining: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public func selectPreset(minutes: Int) {
        stopTimer()
        let seconds = max(60, minutes * 60)
        totalSeconds = seconds
        remainingSeconds = seconds
        didFinishRecently = false
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
        if remainingSeconds <= 0 {
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
        remainingSeconds = totalSeconds
        didFinishRecently = false
    }

    private func tick() {
        guard remainingSeconds > 1 else {
            remainingSeconds = 0
            stopTimer()
            didFinishRecently = true
            NSSound(named: NSSound.Name("Glass"))?.play()
            return
        }
        remainingSeconds -= 1
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }
}
