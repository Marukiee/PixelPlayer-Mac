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
    private var history: [Song] = []
    private var scrobbled = false
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

    private func start(_ song: Song) {
        if model.current.id != "" && model.current.id != song.id { history.append(model.current) }
        model.current = song
        model.position = 0
        scrobbled = false
        guard !Library.shared.isSample, let url = url(for: song) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.volume = Float(model.volume / 100)
        player.play()
        model.isPlaying = true
        updateNowPlaying()
        scrobble(song, submission: false)
    }

    func setPlaying(_ playing: Bool) {
        guard !Library.shared.isSample else { return }
        if player.currentItem == nil, playing, model.current.id != "" { start(model.current); return }
        playing ? player.play() : player.pause()
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        guard !Library.shared.isSample else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func setVolume(_ value: Double) {
        player.volume = Float(value / 100)
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
            model.isPlaying = false
        }
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
        // A play counts once half of the song has played, as on the phone.
        if !scrobbled, model.duration > 0, seconds >= model.duration / 2 {
            scrobbled = true
            scrobble(model.current, submission: true)
        }
    }

    private func scrobble(_ song: Song, submission: Bool) {
        guard let id = song.source.serverID, let client = Library.shared.client else { return }
        Task.detached { try? await client.scrobble(id: id, time: .now, submission: submission) }
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
