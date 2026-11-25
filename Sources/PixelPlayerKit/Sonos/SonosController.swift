import Foundation

/// What the controller needs from the Mac's own player, which keeps running silently while the speakers play (spec 5.11).
///
/// The local player stays in charge of the queue, like the phone. Changes made through these methods come from the
/// controller following the speaker, so the player must not report them back through the `local...` event methods.
public protocol SonosLocalPlayer: AnyObject, Sendable {
    /// The current item, the upcoming ones in play order (shuffle aware, repeat off), position and play state.
    func sonosSnapshot() async -> SonosLocalSnapshot?
    func sonosSetPlaying(_ playing: Bool) async
    func sonosSeek(toMs positionMs: Int) async
    /// Moves to the item with this id nearest to the current one, at the given position.
    func sonosMove(toItemID id: String, positionMs: Int) async
    /// False when there is no next item.
    func sonosSkipToNext() async -> Bool
    /// True when it moved to another item, false when it restarted the current one.
    func sonosSkipToPrevious() async -> Bool
    func sonosReplaceQueue(_ tracks: [SonosTrackInput], startAt index: Int, positionMs: Int, playing: Bool) async
}

public struct SonosLocalSnapshot: Sendable, Equatable {
    public var current: SonosTrackInput
    /// At most `SonosTiming.maxUpcoming` are used.
    public var upcoming: [SonosTrackInput]
    public var positionMs: Int
    /// The user wants it to play.
    public var playWhenReady: Bool
    /// It really plays at this moment.
    public var isPlaying: Bool

    public init(current: SonosTrackInput, upcoming: [SonosTrackInput], positionMs: Int, playWhenReady: Bool, isPlaying: Bool) {
        self.current = current
        self.upcoming = upcoming
        self.positionMs = positionMs
        self.playWhenReady = playWhenReady
        self.isPlaying = isPlaying
    }
}

public struct SonosSessionState: Sendable, Equatable {
    public var group: SonosGroup
    public var isConnecting = true
    /// PLAYING or TRANSITIONING.
    public var isPlaying = false
    public var transportState = ""
    /// 1-based track on the speaker's queue, 0 when unknown.
    public var track = 0
    /// The speaker's time in the song at the last poll.
    public var positionMs = 0
    public var groupVolume: Int?
    /// Per room, only filled when the group has more than one room.
    public var speakerVolumes: [String: Int] = [:]
    public var isMuted = false

    public init(group: SonosGroup) { self.group = group }
}

/// What the app shows as a short note (a toast on the phone).
public enum SonosMessage: Sendable, Equatable {
    case problem(SonosSourceProblem)
    case takenOver(room: String)
    case lost(room: String)
    case skipped(title: String)
    case stopped(title: String)
    case serverUnreachable
    case stalled
    case favoriteGone
    /// "UPnP 701" or the error text.
    case failed(String)
}

public enum SonosEvent: Sendable, Equatable {
    case groups([SonosGroup])
    /// Nil when the session ended. The app mutes its own player while a session exists and unmutes when it ends;
    /// when it ended with a pause, unmute `SonosTiming.unmuteAfterPause` later so the pause reaches the sink.
    case session(SonosSessionState?)
    case message(SonosMessage)
}

/// How far the speaker is ahead of the local player. The speaker only reports whole seconds, so one reading puts the
/// true difference in a window of a second; readings at different moments overlap in an ever smaller window.
public struct SonosSpeakerOffsetEstimate: Sendable {
    private var low = Int.min
    private var high = Int.max
    static let windowMs = 999
    static let maxWidthMs = 400

    public init() {}

    /// Takes one reading; returns the difference once it is known well enough.
    public mutating func add(speakerWholeSecondsMs: Int, localMs: Int) -> Int? {
        let sample = speakerWholeSecondsMs - localMs
        let newLow = max(low, sample)
        let newHigh = min(high, sample + Self.windowMs)
        // No overlap: one of the two clocks jumped, so what we had says nothing any more.
        if newLow > newHigh {
            low = sample
            high = sample + Self.windowMs
        } else {
            low = newLow
            high = newHigh
        }
        return high - low <= Self.maxWidthMs ? (low + high) / 2 : nil
    }

    public mutating func reset() {
        low = Int.min
        high = Int.max
    }
}

/// Plays the local queue on a Sonos group, the way the Android `SonosController` does (spec 5.5 to 5.13).
///
/// The local player stays in charge and runs muted; every user action goes to the speakers, which stream from Navidrome.
/// The speaker leads on timing: the local player is moved to the speaker's position and follows changes made in the
/// Sonos app. The Sonos queue holds the upcoming songs, so the music keeps going when the Mac sleeps.
public actor SonosController {
    public nonisolated let discovery: SonosDiscovery
    private let soap: SonosSoapClient
    private let local: any SonosLocalPlayer
    private var settings: SonosAddressSettings
    private var skipUnavailableSongs = true
    private var handler: (@Sendable (SonosEvent) -> Void)?

    public private(set) var groups: [SonosGroup] {
        didSet { if groups != oldValue { handler?(.groups(groups)) } }
    }
    public private(set) var session: SonosSessionState? {
        didSet { if session != oldValue { handler?(.session(session)) } }
    }
    public private(set) var isScanning = false

    private var lastRefreshAt = 0
    private var active: ActiveSession?
    private var groupWatch: Task<Void, Never>?

    // One command at a time, in arrival order, across awaits (an actor alone is reentrant).
    private var lockHeld = false
    private var lockWaiters: [CheckedContinuation<Void, Never>] = []

    private var pendingVolume: (@Sendable () async throws -> Void)?
    private var volumeSending = false
    private var lastVolumeChangeAt = 0
    /// Each room's volume at the start of the current group volume change.
    private var volumeShares: [String: Int]?

    private final class ActiveSession {
        var group: SonosGroup
        /// Mirror of the Sonos queue: track number = index + 1.
        var queue: [SonosQueuedTrack] = []
        var lastTrackCommandAt = 0
        var lastPlayPauseCommandAt = 0
        var lastResetAt = 0
        var lastLocalAutoTransitionAt = 0
        /// Bumped by every sync request, so a sync that waited its turn can see a newer one behind it.
        var syncGeneration = 0
        /// A sync is waiting or running.
        var syncBusy = false
        var lastSkipAt = 0
        /// The speaker went quiet during a run of skips and starts again on the song they end on.
        var quietForSkips = false
        var skipStreak = 0
        /// The speaker could not seek while paused; put it on the local spot when it starts playing.
        var alignOnPlay = false
        var pendingJump = false
        var speakerOffset = SonosSpeakerOffsetEstimate()
        /// A speaker that says it plays but stands still has a problem.
        var lastSpeakerMs = -1
        var speakerMovedAt = 0
        var stallHandled = false
        var pollTask: Task<Void, Never>?
        var syncTask: Task<Void, Never>?
        var appendTask: Task<Void, Never>?

        init(group: SonosGroup) { self.group = group }
    }

    public init(local: any SonosLocalPlayer, discovery: SonosDiscovery, settings: SonosAddressSettings = SonosAddressSettings(),
                soap: SonosSoapClient = SonosSoapClient(), cachedGroups: [SonosGroup] = []) {
        self.local = local
        self.discovery = discovery
        self.settings = settings
        self.soap = soap
        self.groups = cachedGroups
    }

    public func setEventHandler(_ handler: (@Sendable (SonosEvent) -> Void)?) { self.handler = handler }
    /// Read on each track build, so a change applies to the next sync.
    public func setSettings(_ settings: SonosAddressSettings) { self.settings = settings }
    /// "Skip songs not on Navidrome" (default on).
    public func setSkipUnavailableSongs(_ on: Bool) { skipUnavailableSongs = on }

    // MARK: Discovery and groups

    /// Searches when the last search is older than a minute, so Connect opens with rooms.
    public func warmUp() async {
        if now() - lastRefreshAt < SonosTiming.warmUpInterval { return }
        await refresh()
    }

    @discardableResult
    public func refresh() async -> [SonosGroup] {
        if isScanning { return groups }
        lastRefreshAt = now()
        isScanning = true
        let found = await discovery.discoverGroups()
        // An empty answer on a flaky network should not wipe the rooms we know.
        if !found.isEmpty || groups.isEmpty { await applyGroups(found) }
        isScanning = false
        return groups
    }

    /// While Connect is open and nothing plays, reads the groups every 3 s from a known speaker (no network search).
    public func watchGroups(_ on: Bool) {
        groupWatch?.cancel()
        groupWatch = nil
        guard on else { return }
        groupWatch = Task {
            while !Task.isCancelled {
                guard (try? await sleep(SonosTiming.groupWatch)) != nil else { return }
                // During a session the poll already reads them.
                if active != nil { continue }
                guard let host = groups.first?.coordinator.host else { continue }
                if let fresh = try? await discovery.readGroups(host: host), !fresh.isEmpty { await applyGroups(fresh) }
            }
        }
    }

    private func applyGroups(_ fresh: [SonosGroup]) async {
        groups = fresh
        guard let s = active else { return }
        if let updated = fresh.first(where: { $0.coordinatorUUID == s.group.coordinatorUUID }) {
            s.group = updated
            session?.group = updated
        } else if !fresh.isEmpty {
            // Our speaker joined another group in the Sonos app.
            await endSession(.takenOver(room: s.group.coordinator.name), pauseLocal: true)
        }
    }

    /// Puts exactly `memberUUIDs` (plus the coordinator) in the group, like the Sonos app's Group screen.
    public func setGroupMembers(groupID: String, memberUUIDs: Set<String>) async {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        let everyone = groups.flatMap(\.members)
        let coordinator = group.coordinator
        await withLock {
            do {
                for speaker in everyone where speaker.uuid != coordinator.uuid {
                    let inGroup = group.members.contains { $0.uuid == speaker.uuid }
                    let wanted = memberUUIDs.contains(speaker.uuid)
                    if wanted && !inGroup {
                        try await join(speaker, to: coordinator.uuid)
                    } else if !wanted && inGroup {
                        try await makeStandalone(speaker)
                    }
                }
            } catch {
                report(error)
            }
        }
        try? await sleep(SonosTiming.groupSettle)
        if let fresh = try? await discovery.readGroups(host: coordinator.host) { await applyGroups(fresh) }
        if let s = active { await refreshVolumes(s) }
    }

    /// Every room of the group plays on its own again.
    public func ungroup(groupID: String) async { await setGroupMembers(groupID: groupID, memberUUIDs: []) }

    /// Adds the rooms of `groupID` to the group that is playing now.
    public func addToActiveGroup(groupID: String) async {
        guard let s = active,
              let playing = groups.first(where: { $0.coordinatorUUID == s.group.coordinatorUUID }),
              let extra = groups.first(where: { $0.id == groupID }) else { return }
        await setGroupMembers(groupID: playing.id, memberUUIDs: Set((playing.members + extra.members).map(\.uuid)))
    }

    /// Plays on a favorite set of rooms: an existing group with exactly those rooms just connects; otherwise they are
    /// grouped first around a room that already leads a group, so the fewest speakers change.
    @discardableResult
    public func playFavorite(memberUUIDs: Set<String>) async -> Bool {
        if let existing = groups.first(where: { Set($0.members.map(\.uuid)) == memberUUIDs }) {
            return await connect(groupID: existing.id)
        }
        var everyone: [String: SonosSpeaker] = [:]
        for speaker in groups.flatMap(\.members) where everyone[speaker.uuid] == nil { everyone[speaker.uuid] = speaker }
        // A Set has no order, so pick by name to keep "the first" stable.
        let wanted = memberUUIDs.compactMap { everyone[$0] }.sorted { $0.name < $1.name }.map(\.uuid)
        guard let first = wanted.first else {
            emit(.message(.favoriteGone))
            return false
        }
        let coordinatorUUID = wanted.first { uuid in groups.contains { $0.coordinatorUUID == uuid } } ?? first
        guard let coordinator = everyone[coordinatorUUID] else { return false }
        let ownGroup = groups.first { $0.coordinatorUUID == coordinatorUUID }
        await withLock {
            do {
                // In someone else's group now: on its own first, so it can lead.
                if ownGroup == nil { try await makeStandalone(coordinator) }
                // Rooms of its group that are not in the favorite go on their own.
                for speaker in ownGroup?.members ?? [] where speaker.uuid != coordinatorUUID && !memberUUIDs.contains(speaker.uuid) {
                    try await makeStandalone(speaker)
                }
                for uuid in wanted where uuid != coordinatorUUID && !(ownGroup?.members.contains { $0.uuid == uuid } ?? false) {
                    if let speaker = everyone[uuid] { try await join(speaker, to: coordinatorUUID) }
                }
            } catch {
                report(error)
            }
        }
        try? await sleep(SonosTiming.groupSettle)
        guard let fresh = try? await discovery.readGroups(host: coordinator.host) else { return false }
        await applyGroups(fresh)
        guard let group = fresh.first(where: { $0.coordinatorUUID == coordinatorUUID }) else { return false }
        return await connect(groupID: group.id)
    }

    private func join(_ speaker: SonosSpeaker, to coordinatorUUID: String) async throws {
        try await soap.call(speaker.host, .avTransport, "SetAVTransportURI",
                            [("InstanceID", "0"), ("CurrentURI", "x-rincon:\(coordinatorUUID)"), ("CurrentURIMetaData", "")])
    }

    private func makeStandalone(_ speaker: SonosSpeaker) async throws {
        try await soap.call(speaker.host, .avTransport, "BecomeCoordinatorOfStandaloneGroup", [("InstanceID", "0")])
    }

    // MARK: Session

    /// Connects to a group and makes it play the local queue (full reset). True when the session runs.
    @discardableResult
    public func connect(groupID: String) async -> Bool {
        guard let group = groups.first(where: { $0.id == groupID }) else { return false }
        let previous = active
        if previous?.group.coordinatorUUID == group.coordinatorUUID { return true }
        // Not cancellable by the caller, like the NonCancellable block on the phone: a half reset leaves a mess.
        return await Task { await self.runConnect(group, previous: previous) }.value
    }

    private func runConnect(_ group: SonosGroup, previous: ActiveSession?) async -> Bool {
        if let previous {
            stopJobs(previous)
            active = nil
            await withLock { _ = try? await avt(previous, "Pause") }
        }
        session = SonosSessionState(group: group)
        if let problem = SonosAddresses.sourceProblem(settings) {
            if previous != nil { await local.sonosSetPlaying(false) }
            session = nil
            emit(.message(.problem(problem)))
            return false
        }
        let s = ActiveSession(group: group)
        active = s
        let ok = await withLock { () -> Bool in
            do {
                try await avt(s, "SetPlayMode", [("NewPlayMode", "NORMAL")])
                try await syncNow(s, jump: true, forceReset: true)
                return true
            } catch {
                report(error)
                return false
            }
        }
        guard ok, active === s else {
            if active === s { await endSession(nil, pauseLocal: false) }
            return false
        }
        session?.isConnecting = false
        await refreshVolumes(s)
        startPolling(s)
        return true
    }

    /// Back to the Mac: the speakers pause and the local player plays on from the same spot.
    public func switchToLocal() async {
        guard let s = active else { return }
        stopJobs(s)
        await withLock { _ = try? await avt(s, "Pause") }
        await endSession(nil, pauseLocal: false)
    }

    private func endSession(_ message: SonosMessage?, pauseLocal: Bool) async {
        guard let s = active else { return }
        stopJobs(s)
        active = nil
        // Pause before the session goes, so the app does not unmute a player that still runs.
        if pauseLocal { await local.sonosSetPlaying(false) }
        session = nil
        if let message { emit(.message(message)) }
    }

    private func stopJobs(_ s: ActiveSession) {
        s.pollTask?.cancel()
        s.syncTask?.cancel()
        s.appendTask?.cancel()
    }

    // MARK: Transport, for an app that drives the local player through the controller

    /// Replaces the local queue and plays it on the speakers (a new queue counts as a user skip, as on the phone).
    public func playTracks(_ tracks: [SonosTrackInput], startAt index: Int = 0, positionMs: Int = 0, playing: Bool = true) async {
        await local.sonosReplaceQueue(tracks, startAt: index, positionMs: positionMs, playing: playing)
        await localItemChanged(automatic: false)
    }

    public func play() async { await setLocalPlaying(true) }
    public func pause() async { await setLocalPlaying(false) }

    public func togglePlayPause() async {
        let playing = await local.sonosSnapshot()?.playWhenReady ?? false
        await setLocalPlaying(!playing)
    }

    public func next() async {
        if await local.sonosSkipToNext() { await localItemChanged(automatic: false) }
    }

    public func previous() async {
        if await local.sonosSkipToPrevious() {
            await localItemChanged(automatic: false)
        } else {
            localSeeked(toMs: 0)
        }
    }

    public func seek(toMs positionMs: Int) async {
        await local.sonosSeek(toMs: positionMs)
        localSeeked(toMs: positionMs)
    }

    private func setLocalPlaying(_ playing: Bool) async {
        guard let snapshot = await local.sonosSnapshot(), snapshot.playWhenReady != playing else { return }
        await local.sonosSetPlaying(playing)
        localPlayStateChanged(playing: playing)
    }

    // MARK: Events from the local player (spec 5.7)

    /// The local player moved to another item. `automatic`: the song ended by itself (or repeat); else a user skip.
    public func localItemChanged(automatic: Bool) async {
        guard let s = active else { return }
        if automatic {
            s.lastLocalAutoTransitionAt = now()
            return
        }
        let inRun = now() - s.lastSkipAt < SonosTiming.skipRunWindow
        s.lastSkipAt = now()
        if inRun && !s.quietForSkips, await local.sonosSnapshot()?.playWhenReady == true, active === s {
            // The speaker should not start every song that is being skipped past.
            s.quietForSkips = true
            s.lastPlayPauseCommandAt = now()
            command(s) { try await self.pauseSonos(s) }
        }
        guard active === s else { return }
        if inRun { s.lastPlayPauseCommandAt = now() }
        scheduleSync(s, jump: true, waitMs: inRun ? SonosTiming.skipRunDebounce : SonosTiming.syncDebounce)
    }

    /// Songs were added, removed or moved in the local queue.
    public func localQueueChanged() {
        guard let s = active else { return }
        scheduleSync(s, jump: false)
    }

    /// The user pressed play or pause on the local player.
    public func localPlayStateChanged(playing: Bool) {
        guard let s = active else { return }
        s.lastPlayPauseCommandAt = now()
        // Starting waits for the queue to be right, or the old song plays for a moment. A sync that is already running
        // may have passed the play state, so this asks for one more after it.
        if playing && s.syncBusy {
            scheduleSync(s, jump: false)
            return
        }
        // A pause goes out right away, also in the middle of a sync: the order of the lock keeps it last.
        command(s) { try await self.applyPlayState(s) }
    }

    /// The user moved within the same song.
    public func localSeeked(toMs positionMs: Int) {
        guard let s = active else { return }
        s.lastTrackCommandAt = now()
        command(s) { try await self.seekSonos(s, positionMs) }
    }

    // MARK: Volume (spec 5.13), outside the command lock

    /// Sets the group volume like the Sonos app: every room keeps its share, so a loud room moves faster than a quiet
    /// one. Shares are taken at the start of a drag or run of key presses, so down and back up ends where it started.
    public func setGroupVolume(_ volume: Int) {
        guard let s = active, let state = session else { return }
        let v = min(max(volume, 0), 100)
        if state.isMuted { setGroupMuted(false) }
        let members = s.group.members
        let soap = self.soap
        if members.count < 2 || members.contains(where: { state.speakerVolumes[$0.uuid] == nil }) {
            let host = s.group.coordinator.host
            session?.groupVolume = v
            sendVolume {
                try await soap.call(host, .groupRenderingControl, "SetGroupVolume", [("InstanceID", "0"), ("DesiredVolume", "\(v)")])
            }
            return
        }
        let ids = Set(members.map(\.uuid))
        let base: [String: Int]
        if let shares = volumeShares, now() - lastVolumeChangeAt < SonosTiming.volumeGesture, Set(shares.keys) == ids {
            base = shares
        } else {
            base = Dictionary(uniqueKeysWithValues: members.map { ($0.uuid, state.speakerVolumes[$0.uuid] ?? 0) })
        }
        volumeShares = base
        let targets = Self.groupVolumeTargets(base, groupVolume: v)
        session?.groupVolume = v
        session?.speakerVolumes.merge(targets) { $1 }
        let rooms = members.map { ($0.host, targets[$0.uuid] ?? v) }
        sendVolume {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (host, value) in rooms {
                    group.addTask {
                        try await soap.call(host, .renderingControl, "SetVolume",
                                            [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(value)")])
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    public func setGroupMuted(_ muted: Bool) {
        guard let s = active else { return }
        lastVolumeChangeAt = now()
        session?.isMuted = muted
        let host = s.group.coordinator.host
        Task {
            do {
                try await soap.call(host, .groupRenderingControl, "SetGroupMute", [("InstanceID", "0"), ("DesiredMute", muted ? "1" : "0")])
            } catch {
                report(error)
            }
        }
    }

    public func setSpeakerVolume(uuid: String, _ volume: Int) {
        guard let s = active, let speaker = s.group.members.first(where: { $0.uuid == uuid }) else { return }
        let v = min(max(volume, 0), 100)
        // A room set by hand gets a new share for the next group change.
        volumeShares = nil
        if var state = session {
            state.speakerVolumes[uuid] = v
            state.groupVolume = Int((Double(state.speakerVolumes.values.reduce(0, +)) / Double(state.speakerVolumes.count)).rounded())
            session = state
        }
        let soap = self.soap
        sendVolume {
            try await soap.call(speaker.host, .renderingControl, "SetVolume", [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(v)")])
        }
    }

    /// For volume keys (step `SonosTiming.volumeKeyStep`). False when no session runs.
    @discardableResult
    public func adjustGroupVolume(by delta: Int) -> Bool {
        guard let state = session else { return false }
        if state.isConnecting { return true }
        setGroupVolume((state.groupVolume ?? 20) + delta)
        return true
    }

    /// Sends only the newest volume, one at a time: a call on its way cannot be taken back, so sending the next one
    /// alongside it could let the older value win.
    private func sendVolume(_ block: @escaping @Sendable () async throws -> Void) {
        lastVolumeChangeAt = now()
        pendingVolume = block
        if volumeSending { return }
        volumeSending = true
        Task {
            try? await sleep(SonosTiming.volumeSendDelay)
            while let next = pendingVolume {
                pendingVolume = nil
                do { try await next() } catch { report(error) }
            }
            volumeSending = false
        }
    }

    private func refreshVolumes(_ s: ActiveSession) async {
        if now() - lastVolumeChangeAt < SonosTiming.volumeRefreshQuiet { return }
        let host = s.group.coordinator.host
        do {
            let group = Int(try await soap.call(host, .groupRenderingControl, "GetGroupVolume", [("InstanceID", "0")])["CurrentVolume"] ?? "")
            let muted = (try? await soap.call(host, .groupRenderingControl, "GetGroupMute", [("InstanceID", "0")]))?["CurrentMute"] == "1"
            var speakers: [String: Int] = [:]
            if s.group.members.count > 1 {
                for speaker in s.group.members {
                    let answer = try await soap.call(speaker.host, .renderingControl, "GetVolume", [("InstanceID", "0"), ("Channel", "Master")])
                    speakers[speaker.uuid] = Int(answer["CurrentVolume"] ?? "") ?? 0
                }
            }
            // Drop the answer if the user moved a volume while it was on its way.
            let stale = now() - lastVolumeChangeAt < SonosTiming.volumeRefreshQuiet
            if active === s && !stale, var state = session {
                state.groupVolume = group
                state.speakerVolumes = speakers
                state.isMuted = muted
                session = state
            }
        } catch {}
    }

    // MARK: Keeping the speaker in step with the local player (spec 5.5, 5.6)

    private func command(_ s: ActiveSession, _ block: @escaping () async throws -> Void) {
        Task {
            await withLock {
                guard active === s else { return }
                do { try await block() } catch { report(error) }
            }
        }
    }

    private func scheduleSync(_ s: ActiveSession, jump: Bool, waitMs: Int = SonosTiming.syncDebounce) {
        s.pendingJump = s.pendingJump || jump
        s.syncTask?.cancel()
        s.syncGeneration += 1
        let generation = s.syncGeneration
        s.syncBusy = true
        s.syncTask = Task {
            if (try? await sleep(waitMs)) != nil {
                // From here on not cancellable, like the NonCancellable block on the phone.
                await Task { await self.runScheduledSync(s, generation: generation) }.value
            }
            if s.syncGeneration == generation { s.syncBusy = false }
        }
    }

    private func runScheduledSync(_ s: ActiveSession, generation: Int) async {
        await withLock {
            // A newer request behind this one reads the local player when it is its turn.
            guard active === s, generation == s.syncGeneration else { return }
            let jump = s.pendingJump
            s.pendingJump = false
            do { try await syncNow(s, jump: jump, forceReset: false) } catch { report(error) }
        }
    }

    private func queued(_ input: SonosTrackInput) -> SonosQueuedTrack? { SonosTracks.queued(input, settings: settings) }

    /// Makes the speaker play what the local player plays. Reuses what is on the Sonos queue where possible, so editing
    /// the upcoming songs never interrupts the current one.
    private func syncNow(_ s: ActiveSession, jump: Bool, forceReset: Bool) async throws {
        s.appendTask?.cancel()
        let generation = s.syncGeneration
        guard let localState = await local.sonosSnapshot() else { return }
        // The local player moved on meanwhile; the sync that caused is next in line.
        if generation != s.syncGeneration || active !== s { return }
        guard let current = queued(localState.current) else {
            try await handleUnplayable(s, localState)
            return
        }
        s.skipStreak = 0
        let upcoming = localState.upcoming.prefix(SonosTiming.maxUpcoming).compactMap(queued)

        if !forceReset && !s.queue.isEmpty {
            let media = try await avt(s, "GetMediaInfo")["CurrentURI"] ?? ""
            let position = try await avt(s, "GetPositionInfo")
            var index = (Int(position["Track"] ?? "") ?? 0) - 1
            if media == s.group.queueURI && s.queue.indices.contains(index) {
                if s.queue[index].mediaID != current.mediaID {
                    let found = Self.nearestIndex(of: current.mediaID, in: s.queue.map(\.mediaID), around: index)
                    if found >= 0 {
                        s.lastTrackCommandAt = now()
                        try await avt(s, "Seek", [("Unit", "TRACK_NR"), ("Target", "\(found + 1)")])
                        index = found
                        if localState.positionMs > SonosTiming.seekMinimum { try await seekSonos(s, localState.positionMs) }
                    } else {
                        index = -1
                    }
                } else if jump && abs(SonosSoapClient.hmsToMs(position["RelTime"]) - localState.positionMs) > SonosTiming.driftLimit {
                    s.lastTrackCommandAt = now()
                    try await seekSonos(s, localState.positionMs)
                }
                if index >= 0 {
                    try await applyPlayState(s)
                    try await replaceUpcoming(s, index: index, wanted: upcoming)
                    return
                }
            }
        }
        try await fullReset(s, current: current, upcoming: upcoming, localState: localState)
    }

    private func fullReset(_ s: ActiveSession, current: SonosQueuedTrack, upcoming: [SonosQueuedTrack], localState: SonosLocalSnapshot) async throws {
        s.lastResetAt = now()
        s.lastTrackCommandAt = now()
        let hadOtherSource = try await releaseOtherSource(s)
        try await avt(s, "RemoveAllTracksFromQueue")
        s.queue.removeAll()
        try await addToQueue(s, current)
        // A fresh queue starts at its first track, so no TRACK_NR seek is needed.
        try await avt(s, "SetAVTransportURI", [("CurrentURI", s.group.queueURI), ("CurrentURIMetaData", "")])
        if hadOtherSource { try await holdSpeaker(s) }
        // Jump ahead by the time the speaker needs to start; the exact alignment follows once it plays.
        let fresh = await local.sonosSnapshot()
        let localAt = fresh?.positionMs ?? localState.positionMs
        var preSeeked = false
        if localAt > SonosTiming.seekMinimum {
            // A quick call: if the speaker is slow to answer, alignWithLocal fixes the spot once it plays.
            let target = SonosSoapClient.msToHms(localAt + (localState.playWhenReady ? SonosTiming.startLead : 0))
            preSeeked = (try? await soap.callQuick(s.group.coordinator.host, .avTransport, "Seek",
                                                    [("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", target)])) != nil
        }
        s.quietForSkips = false
        if fresh?.playWhenReady ?? localState.playWhenReady {
            s.lastPlayPauseCommandAt = now()
            try await avt(s, "Play", [("Speed", "1")])
            try await alignWithLocal(s)
        } else {
            // Some speakers refuse a time seek before playing; align on the next play then.
            s.alignOnPlay = localAt > SonosTiming.seekMinimum && !preSeeked
        }
        try await appendTracks(s, upcoming)
    }

    /// Spotify Connect grabs a speaker back half a second after losing it, also when it was on pause, unless it got a
    /// Pause first (measured on real speakers). Returns whether something else was on the speaker.
    private func releaseOtherSource(_ s: ActiveSession) async throws -> Bool {
        let media = try await avt(s, "GetMediaInfo")["CurrentURI"] ?? ""
        if media.isEmpty || media == s.group.queueURI { return false }
        _ = try? await avt(s, "Pause")
        try await sleep(SonosTiming.releaseSourceWait)
        return true
    }

    /// Makes sure the other source really let go: a Play or Seek that lands on it would resume Spotify or hang.
    private func holdSpeaker(_ s: ActiveSession) async throws {
        for _ in 0..<SonosTiming.holdAttempts {
            var retaken = false
            for _ in 0..<SonosTiming.holdChecks {
                try await sleep(SonosTiming.holdCheckInterval)
                if try await avt(s, "GetMediaInfo")["CurrentURI"] != s.group.queueURI {
                    retaken = true
                    break
                }
            }
            if !retaken { return }
            _ = try? await avt(s, "Pause")
            try await sleep(SonosTiming.releaseSourceWait)
            try await avt(s, "SetAVTransportURI", [("CurrentURI", s.group.queueURI), ("CurrentURIMetaData", "")])
        }
    }

    /// Waits until the speaker really plays, then puts it where the local player is now. The local player kept going
    /// (muted) while the speaker buffered, so the music continues from the same spot.
    private func alignWithLocal(_ s: ActiveSession) async throws {
        s.alignOnPlay = false
        let mediaID = await local.sonosSnapshot()?.current.id
        let deadline = now() + SonosTiming.playStartTimeout
        while now() < deadline {
            let snapshot = await local.sonosSnapshot()
            // Paused or skipped while the speaker was starting: do not hold up what comes next.
            if snapshot?.playWhenReady != true {
                s.alignOnPlay = true
                return
            }
            if snapshot?.current.id != mediaID { return }
            if try await avt(s, "GetTransportInfo")["CurrentTransportState"] == "PLAYING" { break }
            try await sleep(SonosTiming.playStartCheck)
        }
        guard let localAt = await local.sonosSnapshot()?.positionMs, localAt >= SonosTiming.seekMinimum else { return }
        let speakerAt = SonosSoapClient.hmsToMs(try await avt(s, "GetPositionInfo")["RelTime"])
        if abs(speakerAt - localAt) < SonosTiming.alignTolerance { return }
        _ = try? await seekSonos(s, localAt + SonosTiming.seekLead)
        s.lastTrackCommandAt = now()
    }

    private func replaceUpcoming(_ s: ActiveSession, index: Int, wanted: [SonosQueuedTrack]) async throws {
        let existing = s.queue[(index + 1)...].map(\.mediaID)
        var same = 0
        while same < existing.count && same < wanted.count && existing[same] == wanted[same].mediaID { same += 1 }
        if same == existing.count && same == wanted.count { return }
        if same < existing.count {
            try await avt(s, "RemoveTrackRangeFromQueue",
                          [("UpdateID", "0"), ("StartingIndex", "\(index + 2 + same)"), ("NumberOfTracks", "\(existing.count - same)")])
            s.queue.removeSubrange((index + 1 + same)...)
        }
        try await appendTracks(s, Array(wanted.dropFirst(same)))
    }

    /// Adds the next two songs right away and the rest in the background, one per turn of the lock.
    private func appendTracks(_ s: ActiveSession, _ tracks: [SonosQueuedTrack]) async throws {
        for track in tracks.prefix(2) { try await addToQueue(s, track) }
        let rest = Array(tracks.dropFirst(2))
        if rest.isEmpty { return }
        s.appendTask = Task {
            for track in rest {
                if Task.isCancelled || active !== s { break }
                let ok = await withLock { () -> Bool in
                    // A sync that ran meanwhile cancelled this; on the phone the lock wait itself would throw.
                    if Task.isCancelled || active !== s { return false }
                    do {
                        try await addToQueue(s, track)
                        return true
                    } catch {
                        report(error)
                        return false
                    }
                }
                if !ok { break }
            }
        }
    }

    private func addToQueue(_ s: ActiveSession, _ track: SonosQueuedTrack) async throws {
        try await avt(s, "AddURIToQueue", [("EnqueuedURI", track.uri), ("EnqueuedURIMetaData", track.metadata),
                                           ("DesiredFirstTrackNumberEnqueued", "0"), ("EnqueueAsNext", "0")])
        s.queue.append(track)
    }

    /// Puts the speaker in the play state the local player is in now, not the one it had when a sync started.
    private func applyPlayState(_ s: ActiveSession) async throws {
        let state = try await avt(s, "GetTransportInfo")["CurrentTransportState"] ?? ""
        s.lastPlayPauseCommandAt = now()
        s.quietForSkips = false
        let wantPlaying = await local.sonosSnapshot()?.playWhenReady ?? false
        switch Self.playStateCommand(wantPlaying: wantPlaying, transport: state) {
        case "Play"?:
            try await avt(s, "Play", [("Speed", "1")])
            if s.alignOnPlay { try await alignWithLocal(s) }
        case "Pause"?:
            try await pauseSonos(s)
        default:
            break
        }
    }

    /// Spec 5.8: skip a song that is not on Navidrome without restarting the speaker, or stop after too many.
    private func handleUnplayable(_ s: ActiveSession, _ localState: SonosLocalSnapshot) async throws {
        let title = localState.current.title
        if skipUnavailableSongs && s.skipStreak < SonosTiming.maxSkipStreak && !localState.upcoming.isEmpty {
            if s.skipStreak == 0 { emit(.message(.skipped(title: title))) }
            s.skipStreak += 1
            if await local.sonosSkipToNext() { scheduleSync(s, jump: false) }
        } else {
            s.skipStreak = 0
            await local.sonosSetPlaying(false)
            _ = try? await pauseSonos(s)
            emit(.message(.stopped(title: title)))
        }
    }

    private func pauseSonos(_ s: ActiveSession) async throws {
        // Pausing an already stopped speaker returns UPnP 701; that is fine.
        do { try await avt(s, "Pause") } catch let error as SonosError where error.upnpCode == 701 {}
    }

    private func seekSonos(_ s: ActiveSession, _ positionMs: Int) async throws {
        try await avt(s, "Seek", [("Unit", "REL_TIME"), ("Target", SonosSoapClient.msToHms(positionMs))])
    }

    // MARK: Following the speaker (spec 5.9, 5.10)

    private func startPolling(_ s: ActiveSession) {
        s.pollTask = Task {
            var tick = 0
            var failures = 0
            while !Task.isCancelled && active === s {
                let ok = await withLock { () -> Bool in
                    if active !== s || Task.isCancelled { return true }
                    do {
                        try await pollOnce(s, tick: tick)
                        return true
                    } catch {
                        return false
                    }
                }
                if Task.isCancelled { break }
                failures = ok ? 0 : failures + 1
                if failures >= SonosTiming.maxPollFailures {
                    await endSession(.lost(room: s.group.coordinator.name), pauseLocal: true)
                    break
                }
                tick += 1
                guard (try? await sleep(SonosTiming.pollInterval)) != nil else { break }
            }
        }
    }

    private func pollOnce(_ s: ActiveSession, tick: Int) async throws {
        let transport = try await avt(s, "GetTransportInfo")["CurrentTransportState"] ?? ""
        let position = try await avt(s, "GetPositionInfo")
        // Read right away: every further call to the speaker would make the comparison less exact.
        let localAtSample = await local.sonosSnapshot()?.positionMs ?? 0
        let index = (Int(position["Track"] ?? "") ?? 0) - 1
        let trackURI = position["TrackURI"] ?? ""
        let relMs = SonosSoapClient.hmsToMs(position["RelTime"])
        if var state = session {
            state.transportState = transport
            state.isPlaying = transport == "PLAYING" || transport == "TRANSITIONING"
            state.track = index + 1
            state.positionMs = relMs
            session = state
        }

        // Only once our queue is on the speaker can someone else take it over.
        let settled = s.lastResetAt > 0 && now() - s.lastResetAt > SonosTiming.takeoverGrace
        // A track outside our queue usually means the TV or another app took over: check right away.
        if settled && (tick % SonosTiming.takeoverPollTicks == 0 || !s.queue.indices.contains(index)) {
            let media = try await avt(s, "GetMediaInfo")["CurrentURI"] ?? ""
            if media != s.group.queueURI {
                await endSession(.takenOver(room: s.group.coordinator.name), pauseLocal: true)
                return
            }
        }
        if tick % SonosTiming.volumePollTicks == 0 { await refreshVolumes(s) }
        // Grouping or ungrouping in the Sonos app shows here within a few seconds.
        if tick % SonosTiming.groupPollTicks == SonosTiming.groupPollTicks - 1,
           let fresh = try? await discovery.readGroups(host: s.group.coordinator.host) {
            await applyGroups(fresh)
        }
        guard active === s else { return }
        let stallBusy = now() - s.lastTrackCommandAt < SonosTiming.trackCommandGrace || s.syncBusy
        if await handleStalledSpeaker(s, transport: transport, relMs: relMs, index: index, busy: stallBusy) { return }

        guard s.queue.indices.contains(index) else { return }
        let busy = now() - s.lastTrackCommandAt < SonosTiming.trackCommandGrace || s.syncBusy
        if settled && !busy && !SonosTracks.sameStream(s.queue[index].uri, trackURI) {
            // The queue was edited in the Sonos app (or by another controller), so our copy is off: rebuild it.
            s.queue.removeAll()
            scheduleSync(s, jump: false)
            return
        }
        guard let localState = await local.sonosSnapshot(), active === s else { return }
        let speakerID = s.queue[index].mediaID
        if localState.current.id != speakerID {
            if busy { return }
            let localIndex = s.queue.firstIndex { $0.mediaID == localState.current.id } ?? -1
            let autoAdvancedRecently = now() - s.lastLocalAutoTransitionAt < SonosTiming.autoAdvanceGrace
            if autoAdvancedRecently && localIndex == index + 1 && transport == "PLAYING" {
                // The local player finished the song a moment before the speakers did.
            } else if autoAdvancedRecently {
                // The local player moved on by itself (end of queue, repeat): bring the speaker along.
                scheduleSync(s, jump: true)
            } else {
                // Changed on the Sonos side (Sonos app, buttons on the speaker): follow it.
                await local.sonosMove(toItemID: speakerID, positionMs: relMs)
            }
            return
        }

        let playPauseRecent = now() - s.lastPlayPauseCommandAt < SonosTiming.playPauseGrace
        if !playPauseRecent {
            if transport == "PLAYING" && !localState.playWhenReady { await local.sonosSetPlaying(true) }
            if (transport == "PAUSED_PLAYBACK" || transport == "STOPPED") && localState.playWhenReady { await local.sonosSetPlaying(false) }
        }
        if transport != "PLAYING" || !localState.isPlaying || busy {
            s.speakerOffset.reset()
            return
        }
        // The local player keeps the speaker's time closely, because the lyrics and the progress bar run on it.
        let offset = s.speakerOffset.add(speakerWholeSecondsMs: relMs, localMs: localAtSample)
        if abs(relMs - localAtSample) > SonosTiming.driftLimit {
            await local.sonosSeek(toMs: relMs)
            s.speakerOffset.reset()
        } else if let offset, abs(offset) > SonosTiming.fineSyncLimit {
            let now = await local.sonosSnapshot()?.positionMs ?? localAtSample
            await local.sonosSeek(toMs: now + offset)
            s.speakerOffset.reset()
        }
    }

    /// The speaker says it plays, but its time stands still: it cannot fetch the song, mostly because Navidrome is out
    /// of reach. The local player then stops too and the app says why. True when it stopped.
    private func handleStalledSpeaker(_ s: ActiveSession, transport: String, relMs: Int, index: Int, busy: Bool) async -> Bool {
        let saysPlaying = transport == "PLAYING" || transport == "TRANSITIONING"
        if !saysPlaying || busy || relMs != s.lastSpeakerMs {
            if relMs != s.lastSpeakerMs || !saysPlaying { s.stallHandled = false }
            s.lastSpeakerMs = relMs
            s.speakerMovedAt = now()
            return false
        }
        if s.stallHandled || now() - s.speakerMovedAt < SonosTiming.stall { return false }
        guard let localState = await local.sonosSnapshot(), localState.playWhenReady else { return false }
        s.stallHandled = true
        let uri = s.queue.indices.contains(index) ? s.queue[index].uri : nil
        var serverDown = false
        if let uri, uri.hasPrefix("http") { serverDown = !(await soap.canReach(uri)) }
        s.lastPlayPauseCommandAt = now()
        await local.sonosSetPlaying(false)
        _ = try? await avt(s, "Pause")
        emit(.message(serverDown ? .serverUnreachable : .stalled))
        return true
    }

    // MARK: Helpers

    @discardableResult
    private func avt(_ s: ActiveSession, _ action: String, _ args: [(String, String)] = []) async throws -> [String: String] {
        try await soap.call(s.group.coordinator.host, .avTransport, action, [("InstanceID", "0")] + args)
    }

    private func withLock<T>(_ body: () async -> T) async -> T {
        if lockHeld {
            await withCheckedContinuation { lockWaiters.append($0) }
        } else {
            lockHeld = true
        }
        let result = await body()
        // Hands the lock straight to the next waiter, so the order of arrival holds.
        if lockWaiters.isEmpty { lockHeld = false } else { lockWaiters.removeFirst().resume() }
        return result
    }

    private func emit(_ event: SonosEvent) { handler?(event) }

    private func report(_ error: Error) {
        // A newer volume or sync request replaced this one; that is not a failure.
        if error is CancellationError { return }
        let detail = (error as? SonosError)?.upnpCode.map { "UPnP \($0)" } ?? error.localizedDescription
        emit(.message(.failed(detail)))
    }

    private func sleep(_ ms: Int) async throws { try await Task.sleep(for: .milliseconds(ms)) }

    /// Milliseconds on a clock that keeps running in sleep, like Android's elapsedRealtime; large from the start, so
    /// "last command at 0" never counts as recent.
    private func now() -> Int { Int(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }

    // MARK: Pure parts

    /// What the speaker needs to match the local player, or nil. A starting speaker reports TRANSITIONING: it counts as
    /// playing, and takes a Pause at once.
    public static func playStateCommand(wantPlaying: Bool, transport: String) -> String? {
        let going = transport == "PLAYING" || transport == "TRANSITIONING"
        if wantPlaying && !going { return "Play" }
        if !wantPlaying && going { return "Pause" }
        return nil
    }

    /// Spreads a group volume over the rooms in proportion to `base`, so the mean lands on `groupVolume`. A room that hits
    /// 100 stops there and the others keep rising; rooms that were all silent move together.
    public static func groupVolumeTargets(_ base: [String: Int], groupVolume: Int) -> [String: Int] {
        let target = Double(min(max(groupVolume, 0), 100))
        guard let quietest = base.values.filter({ $0 > 0 }).min() else { return base.mapValues { _ in Int(target.rounded()) } }
        func spread(_ factor: Double) -> [String: Double] { base.mapValues { min(max(Double($0) * factor, 0), 100) } }
        func mean(_ values: [String: Double]) -> Double { values.values.reduce(0, +) / Double(values.count) }
        var low = 0.0
        var high = 100.0 / Double(quietest)
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if mean(spread(mid)) < target { low = mid } else { high = mid }
        }
        return spread(high).mapValues { Int($0.rounded()) }
    }

    /// Index of `id` in `ids` closest to `around`, or -1.
    public static func nearestIndex(of id: String, in ids: [String], around: Int) -> Int {
        ids.indices.filter { ids[$0] == id }.min { abs($0 - around) < abs($1 - around) } ?? -1
    }
}
