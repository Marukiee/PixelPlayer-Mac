import AppKit
import IOBluetooth
import Observation
import PixelPlayerKit

/// A phone the music can play on: paired over Bluetooth, or reached over the network (a test hook of the Android app).
struct RemotePhone: Identifiable, Hashable {
    enum Kind: Hashable {
        case bluetooth(address: String)
        case tcp(host: String, port: UInt16)
    }
    let kind: Kind
    let name: String

    var id: String {
        switch kind {
        case .bluetooth(let address): "bt:\(address)"
        case .tcp(let host, let port): "tcp:\(host):\(port)"
        }
    }

    /// Lines of `host:port name`, as the phones' remote_hosts.txt; `#` starts a comment.
    static func parse(hosts: String) -> [RemotePhone] {
        hosts.split(whereSeparator: { $0 == "\n" || $0 == ";" }).compactMap { raw in
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { return nil }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let address = parts[0]
            guard let colon = address.lastIndex(of: ":"), let port = UInt16(address[address.index(after: colon)...]) else { return nil }
            let host = String(address[..<colon])
            return RemotePhone(kind: .tcp(host: host, port: port), name: parts.count > 1 ? parts[1] : host)
        }
    }
}

/// Plays on a phone with PixelPlayer, the way one phone controls another (spec section 6). The Mac keeps the queue;
/// the phone plays its own copy of each song, leads on timing and reports back. While a phone plays, the Mac plays
/// nothing itself and counts no listens: the phone that plays counts them.
@MainActor @Observable
final class RemoteController {
    static let shared = RemoteController()

    enum Phase: Equatable { case connecting, connected, reconnecting }

    /// The phones Connect lists. Listing never opens a connection: any connection takes a phone away from whatever
    /// controls it, so the Mac connects only when asked.
    private(set) var phones: [RemotePhone] = []
    private(set) var active: RemotePhone?
    private(set) var phase: Phase = .connecting
    /// A short line under a phone in Connect, about what just happened with it.
    private(set) var notes: [String: String] = [:]

    var isActive: Bool { active != nil }
    /// Whether play, pause, seek and volume go to the phone. While it connects, the Mac keeps playing itself,
    /// so a phone that does not answer costs nothing.
    var controlsPlayback: Bool { active != nil && phase != .connecting }

    @ObservationIgnored private var link: RemoteLink?
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var lastReceived = Date.distantPast
    @ObservationIgnored private var lastQid: Int64 = 0
    @ObservationIgnored private var sentIDs: [String] = []
    @ObservationIgnored private var acked = false
    @ObservationIgnored private var syncInFlight = false
    @ObservationIgnored private var lastRemoteIndex = 0
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var forceSync = false
    @ObservationIgnored private var lastTrackCommand = Date.distantPast
    @ObservationIgnored private var lastPlayCommand = Date.distantPast
    @ObservationIgnored private var lastSeek = Date.distantPast
    @ObservationIgnored private var lastVolumeMove = Date.distantPast
    @ObservationIgnored private var changedWhileAway = false
    @ObservationIgnored private var firstStateAfterConnect = false
    @ObservationIgnored private var reconnectAttempts = 0
    @ObservationIgnored private var nextReconnect = Date.distantPast
    @ObservationIgnored private var applyingState = false
    @ObservationIgnored private var missingStreak = 0
    @ObservationIgnored private var anchor: (ms: Int, at: Date)?

    private var model: PlayerModel { .shared }
    private var name: String { active?.name ?? "the phone" }

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { RemoteController.shared.link?.send(RemoteMessage.simple("bye")) }
        }
    }

    // MARK: Finding phones

    /// Network phones from Settings (or, in a scripted run, PP_REMOTE_TCP) and the phones paired with this Mac.
    func refreshPhones() {
        if Library.shared.isSample {
            phones = Sample.phones.map { RemotePhone(kind: .tcp(host: $0.id, port: 0), name: $0.name) }
            return
        }
        var found: [RemotePhone] = []
        if Debug.active {
            // Scripted runs never touch Bluetooth: no permission prompt, no real phone.
            found = RemotePhone.parse(hosts: ProcessInfo.processInfo.environment["PP_REMOTE_TCP"] ?? "")
        } else {
            found = RemotePhone.parse(hosts: UserDefaults.standard.string(forKey: "remote.hosts") ?? "")
            for device in BluetoothRemoteLink.pairedPhones() {
                guard let address = device.addressString else { continue }
                found.append(RemotePhone(kind: .bluetooth(address: address), name: device.name ?? address))
            }
        }
        // The last used phone first, as on the phones.
        let last = UserDefaults.standard.string(forKey: "remote.last")
        phones = found.sorted { ($0.id == last ? 0 : 1) < ($1.id == last ? 0 : 1) }
        if let active, !phones.contains(active) { phones.insert(active, at: 0) }
    }

    func note(for phone: RemotePhone) -> String? {
        if phone == active {
            switch phase {
            case .connecting: return "Connecting…"
            case .reconnecting: return "Reconnecting…"
            case .connected: return notes[phone.id] ?? "Playing here"
            }
        }
        return notes[phone.id]
    }

    // MARK: Connecting

    func connect(_ phone: RemotePhone) {
        guard phone != active, !Library.shared.isSample else { return }
        // One place at a time: speakers that played stop first.
        SonosOutput.shared.stopForOtherOutput()
        // From one phone to another the music carries on.
        let wasPlaying = model.isPlaying
        if active != nil { disconnect() }
        model.isPlaying = wasPlaying
        model.group = []
        notes[phone.id] = nil
        active = phone
        phase = .connecting
        lastQid = 0
        sentIDs = []
        acked = false
        syncInFlight = false
        changedWhileAway = false
        missingStreak = 0
        UserDefaults.standard.set(phone.id, forKey: "remote.last")
        // Without audio of its own the app would nap, and a late ping makes the phone drop the Mac after 12 seconds.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Playing on \(phone.name)")
        startTimer()
        Task { await open(first: true) }
    }

    /// Back to this Mac: the phone pauses and lets go. The song and the place in it stay, ready to play here.
    func disconnect() {
        guard active != nil else { return }
        let wasControlling = controlsPlayback
        if let link {
            link.send(RemoteMessage.simple("pause"))
            link.send(RemoteMessage.simple("bye"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { link.close() }
        }
        finish(note: nil)
        if wasControlling { model.isPlaying = false }
    }

    private func finish(note: String?) {
        if let active { notes[active.id] = note }
        link = nil
        active = nil
        pendingSync?.cancel()
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func makeLink(_ phone: RemotePhone) -> RemoteLink? {
        switch phone.kind {
        case .tcp(let host, let port):
            return port == 0 ? nil : TCPRemoteLink(host: host, port: port)
        case .bluetooth(let address):
            guard !Debug.active, let device = IOBluetoothDevice(addressString: address) else { return nil }
            return BluetoothRemoteLink(device: device)
        }
    }

    private func open(first: Bool) async {
        guard let phone = active, !opening else { return }
        opening = true
        defer { opening = false }
        guard let newLink = makeLink(phone) else {
            finish(note: "Can't reach this phone.")
            return
        }
        newLink.onLine = { [weak self] line in MainActor.assumeIsolated { self?.receive(line) } }
        newLink.onClose = { [weak self, weak newLink] in MainActor.assumeIsolated { self?.closed(newLink) } }
        let ok = await newLink.open(timeout: first ? 8 : 6)
        guard active == phone else { newLink.close(); return }
        guard ok else {
            if first {
                finish(note: "No answer. On the phone, turn on PixelPlayer › Settings › Play from › Use this phone as remote player.")
                if !Playback.shared.isPlayingHere { model.isPlaying = false }
            } else {
                scheduleReconnect()
            }
            return
        }
        link = newLink
        lastReceived = .now
        if first { Playback.shared.handOff() }
        phase = .connected
        reconnectAttempts = 0
        newLink.send(RemoteMessage.hello(name: Host.current().localizedName ?? "Mac", session: true))
        if first {
            sendQueue()
        } else {
            firstStateAfterConnect = true
        }
    }

    private func closed(_ closedLink: RemoteLink?) {
        guard let closedLink, closedLink === link else { return }
        linkLost()
    }

    private func linkLost() {
        let old = link
        link = nil
        old?.close()
        guard active != nil else { return }
        phase = .reconnecting
        reconnectAttempts = 0
        scheduleReconnect()
    }

    /// The first 20 tries every 3 seconds, then every 10, until the listener goes back to the Mac.
    private func scheduleReconnect() {
        phase = .reconnecting
        reconnectAttempts += 1
        nextReconnect = .now + (reconnectAttempts <= 20 ? 3 : 10)
    }

    // MARK: The clock: keepalive, silence, reconnect, and the position between two reports

    private func startTimer() {
        timer?.invalidate()
        ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { RemoteController.shared.tick() }
        }
    }

    private func tick() {
        guard active != nil else { return }
        ticks += 1
        let now = Date.now
        switch phase {
        case .connected:
            if ticks % 4 == 0 { link?.send(RemoteMessage.simple("ping")) }
            if now.timeIntervalSince(lastReceived) > RemoteProtocol.silenceLimit { linkLost(); return }
            if model.isPlaying, let anchor, now.timeIntervalSince(lastSeek) > 1.5 {
                model.position = min(model.duration, Double(anchor.ms) / 1000 + now.timeIntervalSince(anchor.at))
            }
        case .reconnecting:
            if now >= nextReconnect, !opening { Task { await open(first: false) } }
        case .connecting:
            break
        }
    }

    // MARK: What the Mac sends

    private static func track(_ song: Song) -> RemoteTrack {
        // A local song's id holds its path inside the music folder, which is what the phone's matcher looks for first.
        let path = song.id.hasPrefix("local:") ? String(song.id.dropFirst(6)) : song.source.serverPath
        return RemoteTrack(id: song.id, path: path, title: song.title, artist: song.artist, album: song.album.title,
                           durationMs: song.seconds * 1000)
    }

    /// Up to 20 played songs, the current one and up to 300 ahead, in play order.
    private func window() -> (songs: [Song], index: Int) {
        let before = Array(Playback.shared.history.suffix(RemoteProtocol.windowBefore))
        let ahead = Array((model.userQueue + model.upNext).prefix(RemoteProtocol.windowAhead))
        return (before + [model.current] + ahead, before.count)
    }

    private func sendQueue() {
        guard let link, phase == .connected else { changedWhileAway = true; return }
        guard !model.current.id.isEmpty else { return }
        let (songs, index) = window()
        let qid = max(lastQid + 1, Int64(Date.now.timeIntervalSince1970 * 1000))
        lastQid = qid
        sentIDs = songs.map(\.id)
        lastRemoteIndex = index
        acked = false
        syncInFlight = true
        // Repeat all only when the whole queue fits, or the phone would loop a part of it.
        let fits = Playback.shared.history.count <= RemoteProtocol.windowBefore && model.userQueue.count + model.upNext.count <= RemoteProtocol.windowAhead
        anchor = (Int(model.position * 1000), .now)
        link.send(RemoteMessage.queue(qid: qid, items: songs.map(Self.track), index: index, positionMs: Int(model.position * 1000),
                                      play: model.isPlaying, repeatMode: model.repeatAll && fits ? 2 : 0))
    }

    /// Sends a new queue a moment later, so a burst of changes becomes one message.
    private func scheduleSync(force: Bool) {
        forceSync = forceSync || force
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let forced = forceSync
            forceSync = false
            if forced || !matchesPhone() { sendQueue() }
        }
    }

    /// Whether the phone already has what follows the current song, so an edit or a followed song needs no message.
    private func matchesPhone() -> Bool {
        guard acked || syncInFlight else { return false }
        let indexes = sentIDs.indices.filter { sentIDs[$0] == model.current.id }
        guard let at = indexes.min(by: { abs($0 - lastRemoteIndex) < abs($1 - lastRemoteIndex) }) else { return false }
        let local = window()
        let localAhead = local.songs[(local.index + 1)...].map(\.id)
        let remoteAhead = Array(sentIDs[(at + 1)...])
        guard zip(localAhead, remoteAhead).allSatisfy({ $0 == $1 }) else { return false }
        return localAhead.count < RemoteProtocol.windowAhead ? remoteAhead.count == localAhead.count : remoteAhead.count >= 100
    }

    /// The listener picked another song here (a click, next, previous): the phone gets it.
    func userChangedTrack() {
        lastTrackCommand = .now
        model.isPlaying = true
        anchor = (0, .now)
        scheduleSync(force: true)
    }

    /// The queue changed here (play next, add, reorder, or the queue following the phone).
    func queueChanged() {
        guard isActive, !applyingState else { return }
        scheduleSync(force: false)
    }

    /// Repeat changed: the phone gets the queue again with the new mode.
    func modesChanged() {
        guard isActive else { return }
        scheduleSync(force: true)
    }

    func setPlaying(_ playing: Bool) {
        lastPlayCommand = .now
        anchor = (Int(model.position * 1000), .now)
        guard let link, phase == .connected else { changedWhileAway = true; return }
        // A queue on its way carries the play itself.
        if playing && syncInFlight { return }
        link.send(RemoteMessage.simple(playing ? "play" : "pause"))
    }

    func seek(to seconds: Double) {
        lastSeek = .now
        anchor = (Int(seconds * 1000), .now)
        guard let link, phase == .connected else { changedWhileAway = true; return }
        link.send(RemoteMessage.seek(Int(seconds * 1000)))
    }

    func setVolume(_ value: Double) {
        guard !applyingState else { return }
        lastVolumeMove = .now
        link?.send(RemoteMessage.volume(Int(value.rounded())))
    }

    // MARK: What the phone sends

    private func receive(_ line: String) {
        lastReceived = .now
        guard let message = RemoteMessage.parse(line) else { return }
        switch message {
        case .state(let state): follow(state)
        case .queued(let qid, let missing, let found): queued(qid: qid, missing: missing, found: found)
        case .volumeHeld:
            if let active { notes[active.id] = "The phone kept its volume lower. Confirm its volume warning to go higher." }
        case .bye:
            let lost = link
            finish(note: "\(name) took over again.")
            lost?.close()
            model.isPlaying = false
        case .hello, .other:
            break
        }
    }

    private func queued(qid: Int64, missing: [String], found: Int) {
        guard qid == lastQid else { return }
        acked = true
        syncInFlight = false
        guard let active else { return }
        if found == 0 {
            notes[active.id] = "None of these songs are on \(name)."
            model.isPlaying = false
            link?.send(RemoteMessage.simple("pause"))
            return
        }
        guard missing.contains(model.current.id) else { missingStreak = 0; return }
        missingStreak += 1
        let hasNext = !model.userQueue.isEmpty || !model.upNext.isEmpty
        if missingStreak < 25, hasNext {
            notes[active.id] = "\(model.current.title) is not on \(name), so it was skipped."
            Playback.shared.next()
        } else {
            notes[active.id] = "\(model.current.title) is not on \(name)."
            model.isPlaying = false
            link?.send(RemoteMessage.simple("pause"))
        }
    }

    /// The Mac follows the phone: its song, its place in it, play or pause, and its volume. Following never sends
    /// anything back, or the Mac would pull the phone back to where it was.
    private func follow(_ state: RemoteState) {
        let now = Date.now
        applyingState = true
        defer { applyingState = false }
        if now.timeIntervalSince(lastVolumeMove) > 1.5, Double(state.volume) != model.volume { model.volume = Double(state.volume) }
        if firstStateAfterConnect {
            firstStateAfterConnect = false
            if changedWhileAway || state.qid != lastQid {
                changedWhileAway = false
                applyingState = false
                sendQueue()
                return
            }
        }
        // Only once the phone has the Mac's queue: right after connecting it still reports what it played before.
        if state.foreign, state.qid == lastQid, acked {
            let lost = link
            lost?.send(RemoteMessage.simple("bye"))
            finish(note: "\(name) is playing something else.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { lost?.close() }
            model.isPlaying = false
            return
        }
        guard state.qid == lastQid, let id = state.id else { return }
        let busy = syncInFlight || now.timeIntervalSince(lastTrackCommand) < 2.5
        if id != model.current.id {
            guard !busy else { return }
            Playback.shared.follow(to: id)
            guard model.current.id == id else { return }
            if let index = sentIDs.firstIndex(of: id) { lastRemoteIndex = index }
            anchor = (state.positionMs, now)
            model.position = Double(state.positionMs) / 1000
            model.isPlaying = state.playWhenReady
            // Near the end of what the phone has: send the next part, from the song it plays now.
            let sentAhead = sentIDs.count - lastRemoteIndex - 1
            if sentAhead < 50, model.userQueue.count + model.upNext.count > sentAhead {
                applyingState = false
                sendQueue()
            }
            return
        }
        if now.timeIntervalSince(lastPlayCommand) > 2, model.isPlaying != state.playWhenReady { model.isPlaying = state.playWhenReady }
        if !busy, now.timeIntervalSince(lastSeek) > 1.5 {
            // Half a Bluetooth round trip later, the phone is a little further.
            let target = state.positionMs + (state.playing ? 40 : 0)
            anchor = (target, now)
            model.position = Double(target) / 1000
        }
    }
}
