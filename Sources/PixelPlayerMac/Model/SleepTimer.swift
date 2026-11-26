import Foundation

/// The sleep timer, as Spotify's and as SpotCopy's on Android (Sleep.kt): after a number of minutes, or at the end of the
/// song, the music pauses, here, on the speakers or on the phone (whatever the player plays on).
@MainActor @Observable
final class SleepTimer {
    static let shared = SleepTimer()
    private(set) var until: Date?
    private(set) var atEnd = false
    var isOn: Bool { until != nil || atEnd }
    private var ticker: Timer?
    private var song: String?
    private var model: PlayerModel { PlayerModel.shared }

    /// The choices in the menu, as Spotify offers them.
    static let minutes = [5, 10, 15, 30, 45, 60]

    func start(minutes: Int) {
        off()
        until = .now.addingTimeInterval(Double(minutes) * 60)
        run()
    }

    func endOfTrack() {
        off()
        atEnd = true
        song = model.current.id
        run()
    }

    func off() {
        ticker?.invalidate()
        ticker = nil
        until = nil
        atEnd = false
    }

    private func run() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { SleepTimer.shared.check() }
        }
    }

    private func check() {
        if let until, Date.now >= until { fire(); return }
        guard atEnd else { return }
        // Pause just before the end, or right away when the next song has already begun.
        if model.current.id != song || (model.duration > 0 && model.duration - model.position < 0.35) { fire() }
    }

    private func fire() {
        off()
        if model.isPlaying { model.setPlaying(false) }
    }

    /// "12 min" left, "end of track", or nothing when it is off.
    var label: String? {
        if atEnd { return "end of track" }
        guard let until else { return nil }
        let left = max(1, Int(until.timeIntervalSinceNow / 60) + 1)
        return left >= 60 ? "1 hr" : "\(left) min"
    }
}
