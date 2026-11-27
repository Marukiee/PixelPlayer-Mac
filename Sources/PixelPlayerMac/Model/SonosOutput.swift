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
    /// The place in the song at a moment, and whether the clock ran from there. The clock keeps its own running flag:
    /// the player's play state can change a moment before the anchor is moved, and must not change the time already counted.
    @ObservationIgnored private var anchor: (ms: Int, at: Date, running: Bool) = (0, .now, false)
    /// A small correction from the speaker still to be eased in, so the bar and the lyrics glide instead of jump.
    @ObservationIgnored private var slewMs = 0
    @ObservationIgnored private var clock: Timer?
    @ObservationIgnored private var tracks: [String: SonosTrackInput] = [:]
    @ObservationIgnored private var tracksClient: SubsonicClient?
    /// Tickets from Navidrome for songs a speaker can't play as they are (FLAC above 48 kHz and the like): with one the
    /// speaker gets them converted to FLAC 48 kHz, so they stay lossless. Never MP3. A ticket runs out after two days.
    @ObservationIgnored private var conversions: [String: (ticket: String, until: Date)] = [:]
    /// Whether the server can convert like that (OpenSubsonic `transcoding`); nil until asked.
    @ObservationIgnored private var serverConverts: Bool?
    @ObservationIgnored private var lastLoggedSession = ""

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
    /// No room is locked: the room that leads can be unticked too, and another room of the group takes over.
    func isLocked(_ room: Room) -> Bool { false }

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
                // The last room goes back to the Mac; a leading room hands the music to another room of the group.
                if group.members.count == 1 { backToMac() } else { Task { await controller.removeCoordinator(groupID: group.id) } }
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
        model.refreshFromLibrary()
        // The speaker fetches the music from Navidrome. Without the server's copy of the song that plays it would skip
        // song after song (as it did through 25 songs on 2026-11-26), so it does not take over: the Mac plays on.
        if Library.shared.fresh(model.current).source.serverID == nil || Library.shared.client == nil {
            if case .loading = Library.shared.status {
                waitForLibrary(groupID: groupID, controller: controller)
            } else {
                SonosLog.write("connect refused: \(model.current.title) has no server copy, library=\(Library.shared.status)")
                note = Library.shared.client == nil ? "Sign in to Navidrome first: the speaker plays from your server."
                    : "\(model.current.title) is only on this Mac, so the speaker can't play it. Pick a song from your server."
            }
            return
        }
        // One place at a time: a phone that played lets go first, and the music carries on here.
        let wasPlaying = model.isPlaying
        RemoteController.shared.disconnect()
        model.isPlaying = wasPlaying
        note = nil
        connecting = true
        setAnchor(Int(model.position * 1000), running: model.isPlaying)
        Playback.shared.handOff()
        startClock()
        let withoutServer = ([model.current] + model.userQueue + model.upNext).prefix(50).filter { Library.shared.fresh($0).source.serverID == nil }.count
        let first = Library.shared.fresh(model.current)
        SonosLog.write("connect \(groupID) current=\(model.current.title) server=\(first.source.serverID ?? "none") notOnServerInNext50=\(withoutServer) login=\(Library.shared.client != nil) library=\(Library.shared.status) at=\(Int(model.position))s playing=\(model.isPlaying) format=\(first.source.suffix ?? "?")/\(first.source.sampleRate ?? 0) converts=\(Self.needsConverting(first))")
        Task {
            await prepareConversions()
            await controller.setSettings(addressSettings)
            let ok = await controller.connect(groupID: groupID)
            SonosLog.write("connect result \(ok)")
            connecting = false
            // The speakers did not take it: the Mac plays on from the same spot.
            if !ok, session == nil {
                ended()
                if model.isPlaying { Playback.shared.setPlaying(true) }
            }
        }
    }

    /// Right after a launch the server's list may still be coming: wait for it (at most half a minute), then connect.
    private func waitForLibrary(groupID: String, controller: SonosController) {
        connecting = true
        note = "Loading your library…"
        SonosLog.write("connect waits for the library")
        Task {
            for _ in 0..<60 {
                guard case .loading = Library.shared.status else { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            connecting = false
            note = nil
            if case .loading = Library.shared.status {
                note = "Your library is still loading. Try again in a moment."
                return
            }
            start(groupID: groupID, controller: controller)
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

    /// The search and the speaker list in Settings changed: the next look for rooms uses them.
    func settingsChanged() {
        guard !controlsPlayback else { return }
        if let controller { Task { await controller.watchGroups(false) } }
        controller = nil
        discovery = nil
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
        case .session(let state):
            // Only when something changes, not every poll.
            let key = state.map { "\($0.group.id)|\($0.isConnecting)|\($0.transportState)|\($0.track)" } ?? "none"
            if key != lastLoggedSession {
                lastLoggedSession = key
                SonosLog.write(state.map { "session \($0.group.displayName) connecting=\($0.isConnecting) state=\($0.transportState) track=\($0.track) pos=\($0.positionMs)" } ?? "session ended")
            }
        case .message(let message):
            SonosLog.write("message \(message)")
        case .groups(let found):
            SonosLog.write("groups \(found.count)")
        }
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
        SonosLog.write("user picked \(model.current.title) server=\(model.current.source.serverID ?? "none") rate=\(model.current.source.sampleRate.map(String.init) ?? "?")")
        model.isPlaying = true
        setAnchor(0, running: true)
        guard let controller else { return }
        Task {
            await prepareConversions()
            await controller.localItemChanged(automatic: false)
        }
    }

    func setPlaying(_ playing: Bool) {
        // The time so far is counted with the clock as it was, before it stops or starts.
        setAnchor(currentMs, running: playing)
        model.isPlaying = playing
        guard let controller else { return }
        Task { await controller.localPlayStateChanged(playing: playing) }
    }

    func seek(toMs ms: Int) {
        setAnchor(ms, running: model.isPlaying)
        guard let controller else { return }
        Task { await controller.localSeeked(toMs: ms) }
    }

    func queueChanged() {
        guard controlsPlayback, !applying, let controller else { return }
        Task {
            await prepareConversions()
            await controller.localQueueChanged()
        }
    }

    func setMacVolume(_ value: Double) {
        groupVolume = value
    }

    // MARK: The clock

    private var currentMs: Int {
        var ms = anchor.ms
        if anchor.running { ms += max(0, Int(Date.now.timeIntervalSince(anchor.at) * 1000)) }
        return min(ms, max(model.current.seconds * 1000, 0))
    }

    private func setAnchor(_ ms: Int, running: Bool) {
        anchor = (ms, .now, running)
        slewMs = 0
    }

    private func startClock() {
        clock?.invalidate()
        // Ten times a second, so lyrics change on the beat rather than up to half a second late.
        clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let output = SonosOutput.shared
                guard output.controlsPlayback else { return }
                // A correction is eased in at most 50 ms per tick: the clock runs a little faster or slower for a moment,
                // and never backwards.
                if output.slewMs != 0, output.anchor.running {
                    let step = max(-50, min(50, output.slewMs))
                    output.anchor.ms += step
                    output.slewMs -= step
                }
                output.model.position = Double(output.currentMs) / 1000
            }
        }
    }

    // MARK: The Mac's queue as the controller sees it (SonosLocalPlayer, through SonosBridge)

    private func track(_ queued: Song) -> SonosTrackInput {
        if tracksClient?.config != Library.shared.client?.config { tracks = [:]; tracksClient = Library.shared.client }
        // Always the library's newest copy: one kept in the queue from before the server's list came in has no server id.
        let song = Library.shared.fresh(queued)
        // A song without a stream is looked up again next time, once the server's list may be in.
        if let known = tracks[song.id], known.streamURL != nil { return known }
        // Built once per song: the stream URL has a fresh salt each time, and the speaker compares it.
        let client = Library.shared.client
        let converts = Self.needsConverting(song)
        let ticket = song.source.serverID.flatMap { conversions[$0]?.ticket }
        let stream: URL? = song.source.serverID.flatMap { id in
            if converts, let ticket { return client?.transcodeStreamURL(id: id, ticket: ticket) }
            return client?.streamURL(id: id)
        }
        let input = SonosTrackInput(id: song.id, title: song.title, artist: song.artist, album: song.album.title, durationMs: song.seconds * 1000,
                                    streamURL: stream, coverURL: Library.shared.coverURL(for: song.album, size: 500),
                                    mimeType: converts && ticket != nil ? "audio/flac" : song.source.suffix.map { SonosTracks.mimeType(suffix: $0) })
        // Without its ticket a song is built again next time, once the ticket may be there.
        if !converts || ticket != nil { tracks[song.id] = input }
        return input
    }

    /// Gets the tickets for the songs in the queue that a speaker can't play as they are, before the speaker sees them.
    /// Only those songs (31 of 970 in a library with some 96 kHz albums), a few at a time; a ticket is kept until it nearly runs out.
    private func prepareConversions() async {
        guard let client = Library.shared.client else { return }
        let soon = Date().addingTimeInterval(3600)
        var seen = Set<String>()
        let wanted = ([model.current] + model.userQueue + model.upNext).map(Library.shared.fresh).filter(Self.needsConverting)
            .compactMap(\.source.serverID).filter { (conversions[$0]?.until ?? .distantPast) < soon && seen.insert($0).inserted }
        guard !wanted.isEmpty else { return }
        if serverConverts == nil {
            serverConverts = (try? await client.openSubsonicExtensions())?.contains("transcoding")
        }
        guard serverConverts == true else {
            SonosLog.write("server can't convert: \(wanted.count) songs above 48 kHz go as they are and may be skipped (Navidrome too old for transcoding)")
            return
        }
        let profile = SonosTracks.speakerProfile
        let found = await withTaskGroup(of: (String, String?).self) { group in
            var results: [(String, String?)] = []
            for (index, id) in wanted.enumerated() {
                if index >= 4, let done = await group.next() { results.append(done) }
                group.addTask { (id, try? await client.transcodeDecision(id: id, clientInfo: profile).transcodeParams) }
            }
            for await done in group { results.append(done) }
            return results
        }
        for case let (id, ticket?) in found {
            conversions[id] = (ticket, SubsonicTranscodeDecision.expiry(ofTicket: ticket) ?? Date().addingTimeInterval(86_400))
        }
        SonosLog.write("converted to FLAC 48 kHz: \(found.filter { $0.1 != nil }.count) of \(wanted.count) songs")
    }

    /// Whether a song needs converting before a speaker can play it: FLAC above 48 kHz, Opus, DSD and the like.
    private static func needsConverting(_ song: Song) -> Bool {
        SonosTracks.needsTranscode(suffix: song.source.suffix, sampleRate: song.source.sampleRate)
    }

    fileprivate func snapshot() -> SonosLocalSnapshot? {
        guard !model.current.id.isEmpty else { return nil }
        let upcoming = (model.userQueue + model.upNext).prefix(SonosTiming.maxUpcoming).map(track)
        let ms = currentMs
        return SonosLocalSnapshot(current: track(model.current), upcoming: Array(upcoming), positionMs: ms, playWhenReady: model.isPlaying,
                                  isPlaying: model.isPlaying && ms < model.current.seconds * 1000)
    }

    fileprivate func applyPlaying(_ playing: Bool) {
        SonosLog.write("speaker says play=\(playing)")
        setAnchor(currentMs, running: playing)
        model.isPlaying = playing
    }

    fileprivate func applySeek(_ ms: Int) {
        setAnchor(ms, running: model.isPlaying)
        model.position = Double(ms) / 1000
    }

    /// The speaker's time, from the controller keeping the clock in step: a small difference is eased in, a large one jumps.
    fileprivate func applySync(_ ms: Int) {
        let delta = ms - currentMs
        if anchor.running && abs(delta) <= 1500 {
            slewMs = delta
        } else {
            applySeek(ms)
        }
    }

    fileprivate func applyMove(to id: String, positionMs: Int) {
        SonosLog.write("speaker moved to \(Library.shared.song(id: id)?.title ?? id) at \(positionMs)")
        applying = true
        defer { applying = false }
        Playback.shared.follow(to: id)
        applySeek(positionMs)
    }

    fileprivate func applyNext() -> Bool {
        SonosLog.write("skip to next (from \(model.current.title), server=\(model.current.source.serverID ?? "none"))")
        guard let next = model.userQueue.first ?? model.upNext.first else { return false }
        applyMove(to: next.id, positionMs: 0)
        return true
    }

    fileprivate func applyPrevious() -> Bool {
        SonosLog.write("back to previous")
        guard currentMs <= 3000, let last = Playback.shared.history.last else { applySeek(0); return false }
        applyMove(to: last.id, positionMs: 0)
        return true
    }

    fileprivate func applyReplace(_ inputs: [SonosTrackInput], startAt index: Int, positionMs: Int, playing: Bool) {
        SonosLog.write("queue replaced, \(inputs.count) songs, start \(index)")
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
    func sonosSeek(toMs positionMs: Int) async { await MainActor.run { SonosOutput.shared.applySync(positionMs) } }
    func sonosMove(toItemID id: String, positionMs: Int) async { await MainActor.run { SonosOutput.shared.applyMove(to: id, positionMs: positionMs) } }
    func sonosSkipToNext() async -> Bool { await MainActor.run { SonosOutput.shared.applyNext() } }
    func sonosSkipToPrevious() async -> Bool { await MainActor.run { SonosOutput.shared.applyPrevious() } }
    func sonosReplaceQueue(_ tracks: [SonosTrackInput], startAt index: Int, positionMs: Int, playing: Bool) async {
        await MainActor.run { SonosOutput.shared.applyReplace(tracks, startAt: index, positionMs: positionMs, playing: playing) }
    }
}

/// What happens with the speakers, for finding out why something went wrong: ~/Library/Logs/PixelPlayer/sonos.log
/// (in a scripted run, sonos.log in its folder). No passwords: song titles, ids and what the speaker reports.
@MainActor
enum SonosLog {
    /// Where the log is, for Settings › Developer.
    static var fileURL: URL { url }

    private static let url: URL = {
        if let dir = Debug.directory { return dir.appendingPathComponent("sonos.log") }
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/PixelPlayer")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("sonos.log")
    }()

    static func write(_ line: String) {
        let text = "\(Date.now.formatted(.iso8601)) \(line)\n"
        // Kept small: past half a megabyte the older half goes.
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512_000,
           let data = try? Data(contentsOf: url) {
            try? data.suffix(256_000).write(to: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
