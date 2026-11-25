import AppKit
import Observation
import PixelPlayerKit

/// Plays on Sonos speakers through the kit's controller (spec section 5). The Mac's own queue stays the one that counts:
/// the controller reads it and moves it to follow the speaker. While the speakers play, the Mac plays nothing itself;
/// a clock moves the position, and it waits at the end of a song until the speaker has moved on.
@MainActor @Observable
final class SonosOutput {
    static let shared = SonosOutput()

    struct Room: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private(set) var groups: [SonosGroup] = []
    private(set) var session: SonosSessionState?
    /// A short line in Connect about what just happened (a takeover, a skipped song, an unreachable server).
    private(set) var note: String?
    private(set) var connecting = false

    var controlsPlayback: Bool { connecting || session != nil }

    @ObservationIgnored private var controller: SonosController?
    @ObservationIgnored private var discovery: SonosDiscovery?
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var anchor: (ms: Int, at: Date) = (0, .now)
    @ObservationIgnored private var clock: Timer?
    @ObservationIgnored private var tracks: [String: SonosTrackInput] = [:]
    @ObservationIgnored private var tracksClient: SubsonicClient?

    private var model: PlayerModel { .shared }
    private var sample: Bool { Library.shared.isSample }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "sonos.groups"), let saved = try? JSONDecoder().decode([SonosGroup].self, from: data) {
            groups = saved
        }
    }

    // MARK: Settings

    static var manualHosts: [String] {
        if Debug.active { return (ProcessInfo.processInfo.environment["PP_SONOS_HOSTS"] ?? "").split(separator: ",").map(String.init) }
        return (UserDefaults.standard.string(forKey: "sonos.hosts") ?? "").split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " }).map(String.init)
    }

    private var addressSettings: SonosAddressSettings {
        let login = Library.shared.client?.config.server.absoluteString
        if Debug.active { return SonosAddressSettings(loginAddress: login) }
        return SonosAddressSettings(loginAddress: login, homeAddress: UserDefaults.standard.string(forKey: "sonos.home") ?? "",
                                    coverAddress: UserDefaults.standard.string(forKey: "sonos.cover") ?? "")
    }

    /// The controller, made the first time Connect opens: no network traffic before anyone asks for speakers.
    private func ensureController() -> SonosController? {
        if let controller { return controller }
        guard !sample else { return nil }
        // Scripted runs never search the network: only the hosts they were given.
        let ssdp = !Debug.active && UserDefaults.standard.object(forKey: "sonos.search") as? Bool ?? true
        let known = Debug.active ? [] : UserDefaults.standard.stringArray(forKey: "sonos.known") ?? []
        let discovery = SonosDiscovery(manualHosts: Self.manualHosts, knownHosts: known, allowSSDP: ssdp)
        let controller = SonosController(local: SonosBridge(), discovery: discovery, settings: addressSettings, cachedGroups: groups)
        self.discovery = discovery
        self.controller = controller
        Task {
            await controller.setEventHandler { event in Task { @MainActor in SonosOutput.shared.handle(event) } }
        }
        return controller
    }

    // MARK: Rooms

    var rooms: [Room] {
        if sample { return Sample.rooms.map { Room(id: $0.id, name: $0.name) } }
        var seen = Set<String>()
        return groups.flatMap(\.members).filter { seen.insert($0.uuid).inserted }.sorted { $0.name < $1.name }
            .map { Room(id: $0.uuid, name: $0.name) }
    }

    func isOn(_ room: Room) -> Bool {
        if sample { return model.group.contains(room.id) }
        return session?.group.members.contains { $0.uuid == room.id } ?? false
    }

    /// The room that leads the playing group cannot leave it while other rooms play along.
    func isLocked(_ room: Room) -> Bool {
        guard !sample, let group = session?.group else { return false }
        return group.coordinatorUUID == room.id && group.members.count > 1
    }

    var groupName: String? {
        if sample { return nil }
        return session?.group.displayName
    }

    /// Connect opened or closed: rooms are looked up while it is open.
    func connectShown(_ shown: Bool) {
        guard let controller = ensureController() else { return }
        Task {
            if shown {
                await controller.setSettings(addressSettings)
                await controller.warmUp()
                _ = await controller.refresh()
            }
            await controller.watchGroups(shown)
        }
    }

    func setRoom(_ room: Room, on: Bool) {
        if sample {
            if on { model.group.insert(room.id) } else { model.group.remove(room.id) }
            return
        }
        guard let controller = ensureController() else { return }
        if let group = session?.group {
            var others = Set(group.members.map(\.uuid)).subtracting([group.coordinatorUUID])
            if on {
                others.insert(room.id)
            } else if room.id == group.coordinatorUUID {
                if group.members.count == 1 { backToMac() }
                return
            } else {
                others.remove(room.id)
            }
            Task { await controller.setGroupMembers(groupID: group.id, memberUUIDs: others) }
        } else if on, let group = groups.first(where: { $0.members.contains { $0.uuid == room.id } }) {
            start(groupID: group.id, controller: controller)
        }
    }

    private func start(groupID: String, controller: SonosController) {
        guard !model.current.id.isEmpty else { note = "Play a song first."; return }
        // One place at a time: a phone that played lets go first, and the music carries on here.
        let wasPlaying = model.isPlaying
        RemoteController.shared.disconnect()
        model.isPlaying = wasPlaying
        note = nil
        connecting = true
        anchor = (Int(model.position * 1000), .now)
        Playback.shared.handOff()
        startClock()
        Task {
            await controller.setSettings(addressSettings)
            let ok = await controller.connect(groupID: groupID)
            connecting = false
            if !ok, session == nil { ended() }
        }
    }

    /// Back to this Mac: the speakers pause and the Mac plays on from the same spot.
    func backToMac() {
        guard let controller, controlsPlayback else { return }
        let playing = model.isPlaying
        Task {
            await controller.switchToLocal()
            session = nil
            connecting = false
            ended()
            if playing { Playback.shared.setPlaying(true) }
        }
    }

    /// Another output takes over (a phone): the speakers pause, the Mac stays quiet.
    func stopForOtherOutput() {
        guard let controller, controlsPlayback else { return }
        Task { await controller.switchToLocal() }
        session = nil
        connecting = false
        ended()
    }

    private func ended() {
        clock?.invalidate()
        clock = nil
        tracks = [:]
    }

    // MARK: Volume

    var groupVolume: Double {
        get { Double(session?.groupVolume ?? 0) }
        set {
            session?.groupVolume = Int(newValue.rounded())
            guard let controller else { return }
            Task { await controller.setGroupVolume(Int(newValue.rounded())) }
        }
    }

    func volume(of room: Room) -> Double { Double(session?.speakerVolumes[room.id] ?? 0) }

    func setVolume(of room: Room, _ value: Double) {
        session?.speakerVolumes[room.id] = Int(value.rounded())
        guard let controller else { return }
        Task { await controller.setSpeakerVolume(uuid: room.id, Int(value.rounded())) }
    }

    // MARK: Events from the controller

    private func handle(_ event: SonosEvent) {
        switch event {
        case .groups(let found):
            groups = found
            if let data = try? JSONEncoder().encode(found), !Debug.active { UserDefaults.standard.set(data, forKey: "sonos.groups") }
            if let discovery, !Debug.active {
                Task { UserDefaults.standard.set(await discovery.knownHosts, forKey: "sonos.known") }
            }
        case .session(let state):
            let had = session != nil
            session = state
            if state != nil { connecting = false }
            if state == nil, had { ended() }
        case .message(let message):
            note = Self.text(message)
        }
    }

    private static func text(_ message: SonosMessage) -> String {
        switch message {
        case .problem(.notLoggedIn): "Connect to Navidrome first: the speakers play from the server."
        case .problem(.tailscaleAddress): "The speakers can't reach a Tailscale address. Set a home address in Settings › Sources."
        case .problem(.noSongs): "The server has no songs yet."
        case .takenOver(let room): "\(room) is playing something else now."
        case .lost(let room): "Lost the connection to \(room)."
        case .skipped(let title): "\(title) is not on the server, so it was skipped."
        case .stopped(let title): "\(title) is not on the server."
        case .serverUnreachable: "The speakers can't reach the server."
        case .stalled: "The speakers stopped: they can't load the song."
        case .favoriteGone: "Some of these rooms are gone."
        case .failed(let reason): "The speakers said no (\(reason))."
        }
    }

    // MARK: What the listener does here

    func userChangedTrack() {
        model.isPlaying = true
        anchor = (0, .now)
        guard let controller else { return }
        Task { await controller.localItemChanged(automatic: false) }
    }

    func setPlaying(_ playing: Bool) {
        anchor = (currentMs, .now)
        model.isPlaying = playing
        guard let controller else { return }
        Task { await controller.localPlayStateChanged(playing: playing) }
    }

    func seek(toMs ms: Int) {
        anchor = (ms, .now)
        guard let controller else { return }
        Task { await controller.localSeeked(toMs: ms) }
    }

    func queueChanged() {
        guard controlsPlayback, !applying, let controller else { return }
        Task { await controller.localQueueChanged() }
    }

    func setMacVolume(_ value: Double) {
        groupVolume = value
    }

    // MARK: The clock

    private var currentMs: Int {
        var ms = anchor.ms
        if model.isPlaying { ms += Int(Date.now.timeIntervalSince(anchor.at) * 1000) }
        return min(ms, max(model.current.seconds * 1000, 0))
    }

    private func startClock() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let output = SonosOutput.shared
                guard output.controlsPlayback else { return }
                output.model.position = Double(output.currentMs) / 1000
            }
        }
    }

    // MARK: The Mac's queue as the controller sees it (SonosLocalPlayer, through SonosBridge)

    private func track(_ song: Song) -> SonosTrackInput {
        if tracksClient?.config != Library.shared.client?.config { tracks = [:]; tracksClient = Library.shared.client }
        if let known = tracks[song.id] { return known }
        // Built once per song: the stream URL has a fresh salt each time, and the speaker compares it.
        let client = Library.shared.client
        let input = SonosTrackInput(id: song.id, title: song.title, artist: song.artist, album: song.album.title, durationMs: song.seconds * 1000,
                                    streamURL: song.source.serverID.flatMap { id in client?.streamURL(id: id) },
                                    coverURL: Library.shared.coverURL(for: song.album, size: 500),
                                    mimeType: song.source.suffix.map { SonosTracks.mimeType(suffix: $0) })
        tracks[song.id] = input
        return input
    }

    fileprivate func snapshot() -> SonosLocalSnapshot? {
        guard !model.current.id.isEmpty else { return nil }
        let upcoming = (model.userQueue + model.upNext).prefix(SonosTiming.maxUpcoming).map(track)
        let ms = currentMs
        return SonosLocalSnapshot(current: track(model.current), upcoming: Array(upcoming), positionMs: ms, playWhenReady: model.isPlaying,
                                  isPlaying: model.isPlaying && ms < model.current.seconds * 1000)
    }

    fileprivate func applyPlaying(_ playing: Bool) {
        anchor = (currentMs, .now)
        model.isPlaying = playing
    }

    fileprivate func applySeek(_ ms: Int) {
        anchor = (ms, .now)
        model.position = Double(ms) / 1000
    }

    fileprivate func applyMove(to id: String, positionMs: Int) {
        applying = true
        defer { applying = false }
        Playback.shared.follow(to: id)
        applySeek(positionMs)
    }

    fileprivate func applyNext() -> Bool {
        guard let next = model.userQueue.first ?? model.upNext.first else { return false }
        applyMove(to: next.id, positionMs: 0)
        return true
    }

    fileprivate func applyPrevious() -> Bool {
        guard currentMs <= 3000, let last = Playback.shared.history.last else { applySeek(0); return false }
        applyMove(to: last.id, positionMs: 0)
        return true
    }

    fileprivate func applyReplace(_ inputs: [SonosTrackInput], startAt index: Int, positionMs: Int, playing: Bool) {
        let songs = inputs.compactMap { Library.shared.song(id: $0.id) }
        guard songs.indices.contains(index) else { return }
        applying = true
        defer { applying = false }
        model.current = songs[index]
        model.userQueue = []
        model.upNext = Array(songs[(index + 1)...])
        model.isPlaying = playing
        applySeek(positionMs)
    }
}

/// The controller's view of the Mac's player. Every call hops to the main actor, where the queue lives.
final class SonosBridge: SonosLocalPlayer, @unchecked Sendable {
    func sonosSnapshot() async -> SonosLocalSnapshot? { await MainActor.run { SonosOutput.shared.snapshot() } }
    func sonosSetPlaying(_ playing: Bool) async { await MainActor.run { SonosOutput.shared.applyPlaying(playing) } }
    func sonosSeek(toMs positionMs: Int) async { await MainActor.run { SonosOutput.shared.applySeek(positionMs) } }
    func sonosMove(toItemID id: String, positionMs: Int) async { await MainActor.run { SonosOutput.shared.applyMove(to: id, positionMs: positionMs) } }
    func sonosSkipToNext() async -> Bool { await MainActor.run { SonosOutput.shared.applyNext() } }
    func sonosSkipToPrevious() async -> Bool { await MainActor.run { SonosOutput.shared.applyPrevious() } }
    func sonosReplaceQueue(_ tracks: [SonosTrackInput], startAt index: Int, positionMs: Int, playing: Bool) async {
        await MainActor.run { SonosOutput.shared.applyReplace(tracks, startAt: index, positionMs: positionMs, playing: playing) }
    }
}
