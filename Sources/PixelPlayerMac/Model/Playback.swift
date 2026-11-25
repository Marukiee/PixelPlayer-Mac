import AVFoundation
import MediaPlayer
import PixelPlayerKit

/// Plays songs on this Mac: the local file when there is one, otherwise the stream from the server.
/// Songs the listener queued play first, then the rest of what was started. Media keys and Control Center
/// work through the system's now playing center.
@MainActor
final class Playback {
    static let shared = Playback()

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    /// Songs played before the current one, oldest first.
    private(set) var history: [Song] = []
    /// Real listening time of the song that plays, for counting the listen (spec section 4).
    private var listenedMs = 0
    private var lastTick: Double?
    private var lastReport = Date.distantPast
    private var model: PlayerModel { PlayerModel.shared }

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.next(automatic: true)
            }
        }
        setUpRemoteCommands()
    }

    /// Where a song plays from on the Mac: the local file wins over the server copy.
    func url(for song: Song) -> URL? {
        if let local = song.source.localURL, FileManager.default.fileExists(atPath: local.path) { return local }
        guard let id = song.source.serverID, let client = Library.shared.client else { return nil }
        return client.streamURL(id: id)
    }

    /// Starts a song, with the rest of the list it came from as what plays after it.
    func play(_ song: Song, in context: [Song] = []) {
        if let index = context.firstIndex(of: song) {
            model.upNext = Array(context[(index + 1)...])
        }
        start(song)
    }

    private func start(_ song: Song, at seconds: Double = 0) {
        endListen()
        if model.current.id != "" && model.current.id != song.id { history.append(model.current) }
        model.current = song
        model.position = seconds
        guard !Library.shared.isSample else { return }
        // On a phone the phone plays; the Mac only tells it what.
        if RemoteController.shared.controlsPlayback { RemoteController.shared.userChangedTrack(); return }
        if SonosOutput.shared.controlsPlayback { SonosOutput.shared.userChangedTrack(); return }
        guard let url = url(for: song) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.volume = Debug.active ? 0 : Float(model.volume / 100)
        if seconds > 0 { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
        player.play()
        model.isPlaying = true
        updateNowPlaying()
        report("starting")
        report("playing")
    }

    /// The listen of the song that played ends here: it goes into the queue when it was long enough.
    private func endListen() {
        if listenedMs > 0, !model.current.id.isEmpty { ScrobbleQueue.shared.record(song: model.current, listenedMs: listenedMs) }
        listenedMs = 0
        lastTick = nil
    }

    func setPlaying(_ playing: Bool) {
        guard !Library.shared.isSample else { return }
        if RemoteController.shared.controlsPlayback { RemoteController.shared.setPlaying(playing); return }
        if SonosOutput.shared.controlsPlayback { SonosOutput.shared.setPlaying(playing); return }
        if player.currentItem == nil, playing, model.current.id != "" { start(model.current, at: model.position); return }
        playing ? player.play() : player.pause()
        lastTick = nil
        updateNowPlaying()
        report(playing ? "playing" : "paused")
    }

    func seek(to seconds: Double) {
        guard !Library.shared.isSample else { return }
        if RemoteController.shared.controlsPlayback { RemoteController.shared.seek(to: seconds); return }
        if SonosOutput.shared.controlsPlayback { SonosOutput.shared.seek(toMs: Int(seconds * 1000)); return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func setVolume(_ value: Double) {
        if RemoteController.shared.controlsPlayback { RemoteController.shared.setVolume(value); return }
        if SonosOutput.shared.controlsPlayback { SonosOutput.shared.setMacVolume(value); return }
        // Scripted runs stay silent: they play real audio, and nobody at the Mac asked for it.
        player.volume = Debug.active ? 0 : Float(value / 100)
    }

    /// The next song: one the listener queued first, then the rest of the list.
    func next(automatic: Bool = false) {
        if !model.userQueue.isEmpty {
            start(model.userQueue.removeFirst())
        } else if !model.upNext.isEmpty {
            start(model.upNext.removeFirst())
        } else if automatic, model.repeatAll, let first = history.first {
            start(first)
        } else if automatic {
            report("stopped", positionMs: model.current.seconds * 1000)
            endListen()
            model.isPlaying = false
        }
    }

    /// Whether sound comes out of this Mac right now.
    var isPlayingHere: Bool { player.rate > 0 }

    /// A phone takes over: the Mac stops its own sound, and what it played so far counts as a listen.
    func handOff() {
        if player.rate > 0 { report("paused") }
        endListen()
        player.pause()
        player.replaceCurrentItem(with: nil)
        updateNowPlaying()
    }

    /// The phone moved to another song by itself (the song ended, or someone used the phone). The queue here follows,
    /// without starting anything: the phone plays, the Mac only shows it.
    func follow(to id: String) {
        if let i = model.userQueue.firstIndex(where: { $0.id == id }) {
            history.append(model.current)
            history += model.userQueue[..<i]
            model.current = model.userQueue[i]
            model.userQueue.removeFirst(i + 1)
        } else if let i = model.upNext.firstIndex(where: { $0.id == id }) {
            history.append(model.current)
            history += model.userQueue + model.upNext[..<i]
            model.userQueue = []
            model.current = model.upNext[i]
            model.upNext.removeFirst(i + 1)
        } else if let i = history.lastIndex(where: { $0.id == id }) {
            model.upNext.insert(contentsOf: Array(history[(i + 1)...]) + [model.current], at: 0)
            model.current = history[i]
            history.removeSubrange(i...)
        }
        updateNowPlaying()
    }

    /// Back to the start of the song, or to the one before when it has only just begun.
    func previous() {
        if model.position > 3 || history.isEmpty {
            seek(to: 0)
        } else {
            let last = history.removeLast()
            model.upNext.insert(model.current, at: 0)
            model.current = last
            start(last)
            history.removeLast()
        }
    }

    private func tick(_ seconds: Double) {
        guard !Library.shared.isSample, seconds.isFinite else { return }
        model.position = seconds
        // Only time that really played counts: a seek is not listening.
        if player.rate > 0 {
            if let last = lastTick { listenedMs += Int(max(0, min(1, seconds - last)) * 1000) }
            lastTick = seconds
            if Date.now.timeIntervalSince(lastReport) >= 30 { report("playing") }
        }
    }

    /// What plays now, for the server's now playing list. Never counts a listen; that is the queue's job.
    private func report(_ state: String, positionMs: Int? = nil) {
        guard let id = model.current.source.serverID, let client = Library.shared.client else { return }
        lastReport = .now
        let position = positionMs ?? Int(model.position * 1000)
        Task.detached {
            do {
                try await client.reportPlayback(id: id, positionMs: position, state: state)
            } catch {
                // Servers without the report fall back to the old now playing call.
                if "\(error)".contains("404") || (error as? SubsonicError) == .http(404), state == "playing" || state == "starting" {
                    try? await client.scrobble(id: id, time: .now, submission: false)
                }
            }
        }
    }

    // MARK: Media keys and Control Center

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in MainActor.assumeIsolated { PlayerModel.shared.setPlaying(true) }; return .success }
        center.pauseCommand.addTarget { _ in MainActor.assumeIsolated { PlayerModel.shared.setPlaying(false) }; return .success }
        center.togglePlayPauseCommand.addTarget { _ in
            MainActor.assumeIsolated { PlayerModel.shared.setPlaying(!PlayerModel.shared.isPlaying) }; return .success
        }
        center.nextTrackCommand.addTarget { _ in MainActor.assumeIsolated { Playback.shared.next() }; return .success }
        center.previousTrackCommand.addTarget { _ in MainActor.assumeIsolated { Playback.shared.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { Playback.shared.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        let song = model.current
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album.title,
            MPMediaItemPropertyPlaybackDuration: Double(song.seconds),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: model.position,
            MPNowPlayingInfoPropertyPlaybackRate: model.isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = model.isPlaying ? .playing : .paused
    }
}
