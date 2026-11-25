import Foundation

/// A silent stand-in for the Mac's own player while the speakers play: it keeps the queue, the current item and a
/// running clock for the position, and the controller moves it to follow the speaker. For an app that would rather not
/// run its own player muted (spec 5.11), and for the checks. It does not advance by itself at the end of a song: it waits
/// at the end and the controller moves it once the speaker has moved on, since the speaker leads on timing.
public actor SonosVirtualPlayer: SonosLocalPlayer {
    public private(set) var tracks: [SonosTrackInput]
    public private(set) var currentIndex: Int
    public private(set) var playWhenReady: Bool
    private var baseMs: Int
    private var startedAt: ContinuousClock.Instant?

    /// Media3 restarts the song instead of going back when it is past this point.
    static let previousRestartsAfterMs = 3_000

    public init(tracks: [SonosTrackInput] = [], startAt index: Int = 0, positionMs: Int = 0, playing: Bool = false) {
        self.tracks = tracks
        self.currentIndex = index
        self.playWhenReady = playing
        self.baseMs = max(positionMs, 0)
        self.startedAt = playing ? .now : nil
    }

    public var current: SonosTrackInput? { tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil }

    public var positionMs: Int {
        var ms = baseMs
        if let startedAt {
            let elapsed = ContinuousClock.now - startedAt
            ms += Int(elapsed.components.seconds) * 1000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        }
        if let duration = current?.durationMs, duration > 0 { ms = min(ms, duration) }
        return ms
    }

    private var isPlaying: Bool {
        guard playWhenReady, let current else { return false }
        return current.durationMs <= 0 || positionMs < current.durationMs
    }

    private func setPosition(_ ms: Int) {
        baseMs = max(ms, 0)
        startedAt = playWhenReady ? .now : nil
    }

    // MARK: SonosLocalPlayer

    public func sonosSnapshot() -> SonosLocalSnapshot? {
        guard let current else { return nil }
        let upcoming = Array(tracks[(currentIndex + 1)...].prefix(SonosTiming.maxUpcoming))
        return SonosLocalSnapshot(current: current, upcoming: upcoming, positionMs: positionMs, playWhenReady: playWhenReady, isPlaying: isPlaying)
    }

    public func sonosSetPlaying(_ playing: Bool) {
        guard playing != playWhenReady else { return }
        let now = positionMs
        playWhenReady = playing
        setPosition(now)
    }

    public func sonosSeek(toMs positionMs: Int) { setPosition(positionMs) }

    public func sonosMove(toItemID id: String, positionMs: Int) {
        let target = tracks.indices.filter { tracks[$0].id == id }.min { abs($0 - currentIndex) < abs($1 - currentIndex) }
        guard let target else { return }
        currentIndex = target
        setPosition(positionMs)
    }

    public func sonosSkipToNext() -> Bool {
        guard currentIndex + 1 < tracks.count else { return false }
        currentIndex += 1
        setPosition(0)
        return true
    }

    public func sonosSkipToPrevious() -> Bool {
        if currentIndex == 0 || positionMs > Self.previousRestartsAfterMs {
            setPosition(0)
            return false
        }
        currentIndex -= 1
        setPosition(0)
        return true
    }

    public func sonosReplaceQueue(_ tracks: [SonosTrackInput], startAt index: Int, positionMs: Int, playing: Bool) {
        self.tracks = tracks
        currentIndex = min(max(index, 0), max(tracks.count - 1, 0))
        playWhenReady = playing
        setPosition(positionMs)
    }
}
