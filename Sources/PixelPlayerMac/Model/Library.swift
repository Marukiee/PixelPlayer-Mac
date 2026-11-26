import SwiftUI
import Observation
import PixelPlayerKit

enum LibraryStatus: Equatable {
    /// The made-up music of the design shots.
    case sample
    /// No server set up yet.
    case notConnected
    case loading(String)
    case ready
    case failed(String)
}

/// Where the Navidrome server is, and the token that logs in. The password itself is not kept: only a salt and the md5
/// token Navidrome checks. Earlier versions kept the password in the keychain, which asked for the login password after
/// every update (the app is signed with a certificate of its own, so each version looks new to the keychain).
struct ServerSettings: Equatable {
    var server: String
    var user: String

    static var saved: ServerSettings? {
        let defaults = UserDefaults.standard
        guard let server = defaults.string(forKey: "navidrome.server"), !server.isEmpty,
              let user = defaults.string(forKey: "navidrome.user"), !user.isEmpty else { return nil }
        return ServerSettings(server: server, user: user)
    }

    func save(password: String?) {
        UserDefaults.standard.set(server, forKey: "navidrome.server")
        UserDefaults.standard.set(user, forKey: "navidrome.user")
        if let password, !password.isEmpty { Self.store(.make(password: password)) }
    }

    private static func store(_ auth: SubsonicConfig.SavedAuth) {
        UserDefaults.standard.set(auth.salt, forKey: "navidrome.salt")
        UserDefaults.standard.set(auth.token, forKey: "navidrome.token")
    }

    static var savedAuth: SubsonicConfig.SavedAuth? {
        guard let salt = UserDefaults.standard.string(forKey: "navidrome.salt"), let token = UserDefaults.standard.string(forKey: "navidrome.token"),
              !salt.isEmpty, !token.isEmpty else { return nil }
        return SubsonicConfig.SavedAuth(salt: salt, token: token)
    }

    var config: SubsonicConfig? {
        guard let url = URL(string: server.hasPrefix("http") ? server : "http://\(server)") else { return nil }
        if let auth = Self.savedAuth {
            var config = SubsonicConfig(server: url, user: user, password: "")
            config.savedAuth = auth
            return config
        }
        // Once, from an earlier version: the password from the keychain becomes a token, and the keychain is not asked again.
        guard let password = Keychain.password(for: user) else { return nil }
        let auth = SubsonicConfig.SavedAuth.make(password: password)
        Self.store(auth)
        var config = SubsonicConfig(server: url, user: user, password: "")
        config.savedAuth = auth
        return config
    }
}

/// All music the app knows: the sample music for the design shots, or the Navidrome library.
@MainActor @Observable
final class Library {
    static let shared = Library()

    var status: LibraryStatus = .notConnected
    /// True while the music folder is being read; the first read of a large folder takes a while.
    var scanning = false
    var albums: [Album] = []
    var songs: [Song] = []
    var playlists: [Playlist] = []
    var likedIDs: Set<String> = []
    var mixes: [Mix] = []
    var week: [Int] = []
    var recentSearches: [String] = []
    var recentAlbums: [Album] = []
    /// Playlists, albums and artists for Your Library, made once per rebuild rather than on every draw of the sidebar.
    var collectionItems: [LibraryItem] = []
    /// Pinned items of Your Library, by route key, in the order they were pinned.
    var pinned: [String] = Store.defaults.stringArray(forKey: "library.pinned") ?? [] {
        didSet { Store.defaults.set(pinned, forKey: "library.pinned") }
    }

    func isPinned(_ route: Route) -> Bool { pinned.contains(route.key) }

    /// Songs in any playlist, for the green check in song rows.
    private(set) var playlistSongIDs: Set<String> = []

    func inPlaylist(_ song: Song) -> Bool { playlistSongIDs.contains(song.id) }

    /// Puts a song in a playlist on Navidrome or takes it out, then reads that playlist back. The listener's own action.
    func setInPlaylist(_ song: Song, playlistID: String, on: Bool) async {
        guard let client, let serverID = song.source.serverID,
              let index = serverPlaylists.firstIndex(where: { $0.id == playlistID }) else { return }
        do {
            if on {
                try await client.updatePlaylist(id: playlistID, adding: [serverID])
            } else {
                let positions = (serverPlaylists[index].entry ?? []).enumerated().filter { $0.element.id == serverID }.map(\.offset)
                guard !positions.isEmpty else { return }
                try await client.updatePlaylist(id: playlistID, removingIndexes: positions)
            }
            if let fresh = try? await client.playlist(id: playlistID) { serverPlaylists[index] = fresh }
            rebuild()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// A new, empty playlist on Navidrome, from the plus beside Your Library.
    func createPlaylist(named name: String) async {
        guard let client else { return }
        do {
            try await client.createPlaylist(name: name, songIDs: [])
            var lists: [SubsonicPlaylist] = []
            for list in try await client.playlists() { lists.append((try? await client.playlist(id: list.id)) ?? list) }
            serverPlaylists = lists
            rebuild()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// A new playlist on Navidrome with this song in it.
    func createPlaylist(named name: String, with song: Song) async {
        guard let client, let serverID = song.source.serverID else { return }
        do {
            try await client.createPlaylist(name: name, songIDs: [serverID])
            var lists: [SubsonicPlaylist] = []
            for list in try await client.playlists() { lists.append((try? await client.playlist(id: list.id)) ?? list) }
            serverPlaylists = lists
            rebuild()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func togglePin(_ route: Route) {
        if let index = pinned.firstIndex(of: route.key) { pinned.remove(at: index) } else { pinned.append(route.key) }
    }
    private(set) var client: SubsonicClient?
    /// What the server and the music folder gave, kept so the merged library can be rebuilt when either changes.
    private var serverAlbums: [SubsonicAlbum] = []
    private var serverSongs: [SubsonicSong] = []
    private var serverPlaylists: [SubsonicPlaylist] = []
    private var serverRecent: [SubsonicAlbum] = []
    private var localTracks: [LocalTrack] = []
    private var hiddenServer: [String: Song] = [:]
    /// Every server song, hidden copies included, as the matching rules see it.
    private(set) var serverKeys: [TrackKey] = []
    /// The merged library as the matching rules see it: local files without a server id, server rows with their own.
    private(set) var songKeys: [TrackKey] = []

    func hiddenServerSong(id: String) -> Song? { hiddenServer[id] }

    static func key(for song: SubsonicSong) -> TrackKey {
        TrackKey(id: song.id, title: song.title, artist: song.artist ?? "", album: song.album ?? "", durationMs: (song.duration ?? 0) * 1000,
                 serverID: song.id)
    }

    var liked: [Song] { songs.filter { likedIDs.contains($0.id) } }

    /// Your Mix of today: the one on Navidrome when another device made it today already, else our own (DailyMix).
    var yourMix: [Song] {
        if isSample { return Sample.songs }
        return (sharedMixIDs ?? mixIDs).compactMap(song(id:))
    }

    /// Today's mix made here, by song id.
    private(set) var mixIDs: [String] = []
    private var mixDay = 0
    /// Today's mix as it is on Navidrome, when it was made today (by this Mac or another device).
    private(set) var sharedMixIDs: [String]?
    /// A server song's local copy, for playlists that should play from this Mac.
    private var localByServerID: [String: String] = [:]
    /// Every song by its id, rebuilt with the library.
    private var songByID: [String: Song] = [:]

    private static var today: Int { Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 1 }
    static let mixName = MixTag.yourMixName

    // MARK: Mixes on Navidrome

    /// Whether Your Mix goes to Navidrome as a playlist, so every app shows the same one (MIXEN-NAVIDROME.md). Asked once,
    /// in the welcome; until then nothing is written. Off: nothing is written, but today's mix another app wrote is used.
    var saveMixes: Bool = Library.savedMixChoice.save {
        didSet { Store.defaults.set(saveMixes, forKey: "mixes.save") }
    }
    /// Whether the question was answered (Yes or Not now).
    var mixQuestionAsked: Bool = Library.savedMixChoice.asked {
        didSet { Store.defaults.set(mixQuestionAsked, forKey: "mixes.asked") }
    }

    /// The answer in the welcome or the switch in Settings. Yes writes today's mix at once.
    func answerMixQuestion(save: Bool) {
        mixQuestionAsked = true
        saveMixes = save
        guard save, !isSample else { return }
        // Picked again from the songs on Navidrome only, so the list here and on the server are the same.
        refreshDailyMix()
        rebuild()
        Task { await syncYourMix() }
    }

    /// A scripted run starts without an answer, unless it gives one: `PP_SAVE_MIXES=1` (Yes) or `0` (Not now).
    private static var savedMixChoice: (asked: Bool, save: Bool) {
        if Debug.active, let value = ProcessInfo.processInfo.environment["PP_SAVE_MIXES"] { return (true, value == "1") }
        return (Store.defaults.bool(forKey: "mixes.asked"), Store.defaults.bool(forKey: "mixes.save"))
    }

    /// What the last sync of the mixes did, for Settings › Developer.
    struct MixSyncReport: Codable, Equatable {
        var date: Date
        var text: String
        var failed = false
    }

    var lastMixSync: MixSyncReport? = Store.defaults.data(forKey: "mixes.lastSync").flatMap { try? JSONDecoder().decode(MixSyncReport.self, from: $0) } {
        didSet { Store.defaults.set(lastMixSync.flatMap { try? JSONEncoder().encode($0) }, forKey: "mixes.lastSync") }
    }

    private func report(_ text: String, failed: Bool = false) {
        lastMixSync = MixSyncReport(date: .now, text: text, failed: failed)
        SonosLog.write("mix sync: \(text)")
    }

    /// Today's Daily Mixes on Navidrome, made by PixelPlayer (one, `daily`) and SpotCopy (`daily:1` and on). Only read.
    private var serverMixSongs: [String: [Song]] = [:]

    /// Makes today's mix from the library: likes, plays and dates. Again only on a new day or a new library. While the mix
    /// goes to Navidrome only songs with a copy there are picked, so the list here and the one on the server are the same.
    func refreshDailyMix() {
        let pool = client != nil && saveMixes && songs.contains(where: { $0.source.serverID != nil })
            ? songs.filter { $0.source.serverID != nil } : songs
        let candidates = pool.map { song in
            MixCandidate(id: song.id, artist: song.artist, liked: likedIDs.contains(song.id), playCount: song.playCount,
                         lastPlayed: song.lastPlayed, added: song.addedAt)
        }
        mixIDs = DailyMix.pick(candidates, day: Self.today, now: Date.now.timeIntervalSince1970)
        mixDay = Self.today
    }

    /// A new day while the app was open: a new mix, the playlists read again (for today's Daily Mixes), and the shared one.
    func checkNewDay() async {
        guard !isSample, !songs.isEmpty, mixDay != Self.today else { return }
        refreshDailyMix()
        sharedMixIDs = nil
        if let client, let lists = try? await Self.playlistsWithSongs(client) {
            serverPlaylists = lists
            rebuild()
        }
        await syncYourMix()
    }

    /// Settings › Developer: today's mix made again here, and written over today's on Navidrome when saving is on.
    func remakeMixes() async {
        guard !isSample else { return }
        refreshDailyMix()
        sharedMixIDs = nil
        rebuild()
        if client == nil { report("Made Your Mix again on this Mac"); return }
        if let client, let lists = try? await Self.playlistsWithSongs(client) {
            serverPlaylists = lists
            rebuild()
        }
        await syncYourMix(force: true)
    }

    /// Every playlist with its songs.
    private static func playlistsWithSongs(_ client: SubsonicClient) async throws -> [SubsonicPlaylist] {
        var lists: [SubsonicPlaylist] = []
        for list in try await client.playlists() { lists.append((try? await client.playlist(id: list.id)) ?? list) }
        return lists
    }

    /// The same Your Mix on every device. The first app of the day writes it to Navidrome, the others take that one over.
    /// Only a playlist with the mark of Your Mix (or the old comment of this Mac) is ever changed or removed, and only one
    /// of this account. With saving off nothing on the server changes. `force` writes again over today's.
    func syncYourMix(force: Bool = false) async {
        guard let client, !isSample else { return }
        let user = client.config.user
        let today = MixTag(kind: "your", date: MixTag.day())
        // Another app (or this Mac) made it today already: that one it is.
        if !force, let kept = MixCopies.plan(for: today, in: serverPlaylists.map(\.mixInfo), user: user).keep, kept.tag == today,
           let entries = serverPlaylists.first(where: { $0.id == kept.id })?.entry, !entries.isEmpty {
            sharedMixIDs = entries.map { localByServerID[$0.id] ?? $0.id }
            if !saveMixes { report("Took today's Your Mix from Navidrome (\(entries.count) songs)"); return }
        } else if !saveMixes {
            report(mixQuestionAsked ? "Saving is off, so Your Mix stays on this Mac" : "Not asked yet, so Your Mix stays on this Mac")
            return
        }
        var seen = Set<String>()
        let ids = mixIDs.compactMap { song(id: $0)?.source.serverID }.filter { seen.insert($0).inserted }
        do {
            // Read again right before writing: another app may have written it a moment ago.
            let fresh = try await client.playlists()
            let plan = MixCopies.plan(for: today, in: fresh.map(\.mixInfo), user: user)
            // Two with the same mark: the oldest stays.
            for extra in plan.remove { try await client.deletePlaylist(id: extra.id) }
            var outcome: String
            if !force, let kept = plan.keep, kept.tag == today {
                if plan.remove.isEmpty {
                    // Nothing changed on the server: only this list is read again.
                    let list = try await client.playlist(id: kept.id)
                    if let index = serverPlaylists.firstIndex(where: { $0.id == kept.id }) { serverPlaylists[index] = list } else { serverPlaylists.append(list) }
                    sharedMixIDs = (list.entry ?? []).map { localByServerID[$0.id] ?? $0.id }
                    rebuild()
                    report("Took today's Your Mix from Navidrome (\(list.entry?.count ?? 0) songs)")
                    return
                }
                outcome = "Took today's Your Mix from Navidrome"
            } else if ids.count < 5 {
                report("Too few songs on Navidrome for Your Mix (\(ids.count))")
                return
            } else if let kept = plan.keep {
                try await client.replacePlaylist(id: kept.id, songIDs: ids)
                try await client.updatePlaylist(id: kept.id, comment: today.comment, isPublic: false)
                outcome = "Wrote Your Mix to Navidrome (\(ids.count) songs)"
            } else {
                let made = try await client.createPlaylist(name: Self.mixName, songIDs: ids)
                guard let id = made?.id else { throw SubsonicError.badResponse }
                try await client.updatePlaylist(id: id, comment: today.comment, isPublic: false)
                outcome = "Made Your Mix on Navidrome (\(ids.count) songs)"
            }
            if !plan.remove.isEmpty { outcome += ", removed \(plan.remove.count) twin" + (plan.remove.count == 1 ? "" : "s") }
            var lists = try await Self.playlistsWithSongs(client)
            // Another app made one at the same moment: again the oldest stays, and its songs are the mix.
            let after = MixCopies.plan(for: today, in: lists.map(\.mixInfo), user: user)
            for extra in after.remove {
                try await client.deletePlaylist(id: extra.id)
                lists.removeAll { $0.id == extra.id }
            }
            serverPlaylists = lists
            if let kept = after.keep, let entries = lists.first(where: { $0.id == kept.id })?.entry {
                sharedMixIDs = entries.map { localByServerID[$0.id] ?? $0.id }
            }
            rebuild()
            saveServerCache(account: client.config.server.absoluteString + "|" + client.config.user)
            report(outcome)
        } catch {
            report("Your Mix: \(error.localizedDescription)", failed: true)
        }
    }

    var yourMixSummary: String {
        if isSample { return "Blue Hour, Night Signal, Orbit and 18 more" }
        let mix = yourMix
        guard !mix.isEmpty else { return "Play something to get your mix going" }
        let names = mix.prefix(3).map(\.title).joined(separator: ", ")
        return mix.count > 3 ? "\(names) and \(mix.count - 3) more" : names
    }

    /// "12 songs, 1 hr 4 min", as Spotify writes it.
    static func summary(_ songs: [Song]) -> String {
        songs.isEmpty ? songCount(0) : "\(songCount(songs.count)), \(duration(songs.reduce(0) { $0 + $1.seconds }))"
    }

    /// "1 hr 4 min", or "38 min 12 sec" under an hour, as on Spotify's list pages.
    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min \(seconds % 60) sec"
    }
    var isSample: Bool { status == .sample }
    /// True once there is music to show.
    var hasMusic: Bool { !songs.isEmpty }
    /// How many songs the server gave, for the status line in Settings.
    var serverSongCount: Int { serverSongs.count }

    /// An album by position that is always there, for places that show a few covers.
    func album(at index: Int) -> Album {
        albums.isEmpty ? Sample.albums[index % Sample.albums.count] : albums[index % albums.count]
    }

    func song(id: String) -> Song? { songByID[id] ?? songs.first { $0.id == id } }

    /// The library's own, newest copy of a song: a song kept from before the server's list came in (the queue restored at
    /// launch) then knows its server copy. A server song that now plays from a local copy becomes that copy.
    func fresh(_ song: Song) -> Song {
        songByID[song.id] ?? localByServerID[song.id].flatMap { songByID[$0] } ?? song
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        if Debug.active, let server = env["PP_LIVE_SERVER"], let url = URL(string: server) {
            // A scripted run against a fake server: the login comes from the run, not the keychain.
            client = SubsonicClient(config: SubsonicConfig(server: url, user: env["PP_LIVE_USER"] ?? "test", password: env["PP_LIVE_PASSWORD"] ?? "test"))
            FavoritesSync.shared.use(account: "\(server)|test")
            Task { await loadServerCache(account: "\(server)|test"); await scanLocal(); await reload() }
        } else if Debug.active, env["PP_MUSIC_FOLDER"] != nil {
            // A scripted run against a music folder and no server: the live app as it is with only local files.
            Task { await scanLocal() }
        } else if Debug.active {
            loadSample()
        } else if let settings = ServerSettings.saved, let config = settings.config {
            client = SubsonicClient(config: config)
            FavoritesSync.shared.use(account: "\(settings.server)|\(settings.user)")
            Task { await loadServerCache(account: "\(settings.server)|\(settings.user)"); await scanLocal(); await reload() }
        } else if !Debug.active {
            Task { await scanLocal() }
        }
    }

    /// Reads the music folder on this Mac and merges it with the server library.
    func scanLocal() async {
        guard !isSample, let folder = MusicFolder.path else { return }
        // A scripted run keeps its own cache, so it never replaces the one of the real app.
        let cache = Debug.directory?.appendingPathComponent("local-library.json")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PixelPlayer/local-library.json")
        scanning = true
        defer { scanning = false }
        localTracks = await LocalScanner(cacheURL: cache).scan(root: URL(fileURLWithPath: folder))
        rebuild()
        if status == .notConnected, hasMusic { status = .ready }
    }

    func loadSample() {
        albums = Sample.albums
        songs = Sample.songs
        playlists = Sample.playlists
        likedIDs = Set(Sample.liked.map(\.id))
        mixes = Sample.mixes
        week = Sample.week
        recentSearches = Sample.recentSearches
        collectionItems = LibraryItem.collections(of: self)
        recentAlbums = Sample.albums
        // A scripted run can show an account: PP_ACCOUNT=<user name>.
        account = ProcessInfo.processInfo.environment["PP_ACCOUNT"].map { SubsonicUser(username: $0) }
        status = .sample
    }

    /// The account signed in on the server, and its photo when it has a real one. Likes, playlists and plays belong to it,
    /// so everyone with their own account keeps their own.
    var account: SubsonicUser?
    var avatar: NSImage?

    func loadAccount() async {
        guard let client else { account = nil; avatar = nil; return }
        account = (try? await client.account()) ?? SubsonicUser(username: client.config.user)
        avatar = await Self.photo(from: client.avatarURL())
    }

    /// Only a real photo. Navidrome sends a stand-in of its own unless its admin turned on Gravatar; then it sends the
    /// Gravatar of the account's email, asked again here with d=404 so an email without one gives no picture rather than
    /// Gravatar's logo.
    nonisolated static func photo(from url: URL) async -> NSImage? {
        guard let (_, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
              let final = response.url, final.host?.contains("gravatar") == true,
              var parts = URLComponents(url: final, resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "d" } + [URLQueryItem(name: "d", value: "404")]
        guard let gravatar = parts.url, let (data, answer) = try? await URLSession.shared.data(from: gravatar),
              (answer as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }

    /// Tries the server and, when it answers, keeps the settings and loads the library.
    func connect(_ settings: ServerSettings, password: String) async {
        guard let url = URL(string: settings.server.hasPrefix("http") ? settings.server : "http://\(settings.server)") else {
            status = .failed("That is not a server address.")
            return
        }
        // An empty password with a saved token reconnects with the token.
        var config = SubsonicConfig(server: url, user: settings.user, password: password)
        if password.isEmpty, let auth = ServerSettings.savedAuth { config.savedAuth = auth }
        let candidate = SubsonicClient(config: config)
        status = .loading("Connecting")
        do {
            try await candidate.ping()
            settings.save(password: password)
            FavoritesSync.shared.use(account: "\(settings.server)|\(settings.user)")
            client = candidate
            await reload()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Reads the whole library from the server. Only reads: nothing on the server changes here.
    func reload() async {
        guard let client else { status = .notConnected; return }
        Task { await loadAccount() }
        status = .loading("Loading your library")
        let started = Date()
        do {
            var serverAlbums: [SubsonicAlbum] = []
            while true {
                let page = try await client.albums(size: 500, offset: serverAlbums.count)
                serverAlbums += page
                if page.count < 500 { break }
            }
            // Album by album, as the Android app does: that works on every Navidrome, where a search with an empty query
            // returns nothing on some versions. Six at a time.
            var serverSongs: [SubsonicSong] = []
            var failedAlbums = 0
            await withTaskGroup(of: [SubsonicSong]?.self) { group in
                var albums = serverAlbums.makeIterator()
                for _ in 0..<6 {
                    guard let album = albums.next() else { break }
                    group.addTask { try? await client.album(id: album.id).song ?? [] }
                }
                for await songs in group {
                    if let songs { serverSongs += songs } else { failedAlbums += 1 }
                    if let album = albums.next() { group.addTask { try? await client.album(id: album.id).song ?? [] } }
                }
            }
            // A server that answered for too few albums gives a partial library; the one we have stays.
            if failedAlbums * 10 > serverAlbums.count { status = .failed("The server did not answer for every album."); return }
            if serverSongs.isEmpty {
                // No albums: the old way, page by page, stopping when a page repeats.
                var seen = Set<String>()
                while true {
                    let page = try await client.search("", songCount: 500, songOffset: serverSongs.count).song ?? []
                    let fresh = page.filter { seen.insert($0.id).inserted }
                    serverSongs += fresh
                    if page.count < 500 || fresh.isEmpty { break }
                }
            }
            let starred = try await client.starred()
            var lists: [SubsonicPlaylist] = []
            for list in try await client.playlists() {
                lists.append((try? await client.playlist(id: list.id)) ?? list)
            }
            let recent = (try? await client.albums(type: "recent", size: 20)) ?? []
            // Never replace a library with a partial or empty answer.
            guard !serverSongs.isEmpty else { status = hasMusic ? .ready : .failed("The server has no songs."); return }
            self.serverAlbums = serverAlbums
            self.serverSongs = serverSongs
            self.serverPlaylists = lists
            self.serverRecent = recent
            _ = starred
            rebuild()
            status = .ready
            SonosLog.write(String(format: "library ready: %d server songs in %.1f s", serverSongs.count, Date().timeIntervalSince(started)))
            reloadRetries = 0
            saveServerCache(account: client.config.server.absoluteString + "|" + client.config.user)
            await FavoritesSync.shared.sync()
            refreshDailyMix()
            await syncYourMix()
            await ScrobbleQueue.shared.send()
        } catch {
            status = .failed(error.localizedDescription)
            SonosLog.write("library failed: \(error.localizedDescription)")
            // Right after a launch or an update macOS can report the network as offline for a moment (Mark's Mac,
            // 2026-11-26): the library then stayed without the server all session. Try again a few times.
            if Self.isTransient(error), reloadRetries < Self.retryDelays.count {
                let delay = Self.retryDelays[reloadRetries]
                reloadRetries += 1
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    if case .failed = status { await reload() }
                }
            }
        }
    }

    private var reloadRetries = 0
    private static let retryDelays: [Double] = [2, 5, 15, 30, 60]

    /// A network that is away for a moment, not a wrong password or a server that says no.
    private static func isTransient(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed].contains(error.code)
    }

    // MARK: The server's list on disk

    /// The server's albums, songs and playlists from the last load, as the Android app keeps them in its database: read at
    /// launch, before the local files, so every song knows its server copy from the first second instead of after the
    /// whole library has been fetched again (Mark, 2026-11-26: the Sonos skipped through the queue right after a launch).
    private struct ServerCache: Codable {
        var account: String
        var albums: [SubsonicAlbum]
        var songs: [SubsonicSong]
        var playlists: [SubsonicPlaylist]
        var recent: [SubsonicAlbum]
    }

    private static var serverCacheURL: URL {
        Debug.directory?.appendingPathComponent("server-library.json")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PixelPlayer/server-library.json")
    }

    /// Settings › Developer: whether the server's list is on disk, and taking it away. The library in use stays; the next
    /// launch reads everything from Navidrome again.
    var serverCacheExists: Bool { FileManager.default.fileExists(atPath: Self.serverCacheURL.path) }

    func clearServerCache() {
        try? FileManager.default.removeItem(at: Self.serverCacheURL)
    }

    /// Only for the same server and account; read off the main thread.
    private func loadServerCache(account: String) async {
        guard serverSongs.isEmpty else { return }
        let url = Self.serverCacheURL
        let cache = await Task.detached { () -> ServerCache? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(ServerCache.self, from: data)
        }.value
        guard let cache, Self.sameAccount(cache.account, account), serverSongs.isEmpty else { return }
        serverAlbums = cache.albums
        serverSongs = cache.songs
        serverPlaylists = cache.playlists
        serverRecent = cache.recent
        SonosLog.write("library from disk: \(cache.songs.count) server songs")
    }

    private func saveServerCache(account: String) {
        let cache = ServerCache(account: account, albums: serverAlbums, songs: serverSongs, playlists: serverPlaylists, recent: serverRecent)
        let url = Self.serverCacheURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(cache) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The saved login and the one in use name the same account, with or without http:// and a trailing slash.
    private static func sameAccount(_ a: String, _ b: String) -> Bool {
        func plain(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "/|", with: "|")
        }
        return plain(a) == plain(b)
    }

    /// Builds the one library: local files first, each knowing its server twin, and the server songs that have no local copy.
    private func rebuild() {
        let tints: [UInt32] = [0x23408F, 0x5B2A86, 0x14594F, 0x8C3A1E, 0x2B5C8F, 0x0F7C80, 0x4A2C7A]
        func tint(_ id: String) -> UInt32 { tints[abs(id.hashValue) % tints.count] }
        func makeAlbum(_ album: SubsonicAlbum) -> Album {
            Album(id: album.id, title: album.name, artist: album.artist ?? "Unknown artist", year: album.year ?? 0, genre: album.genre ?? "",
                  coverArtID: album.coverArt ?? album.id, tint: tint(album.id))
        }
        let albumByID = Dictionary(serverAlbums.map { ($0.id, makeAlbum($0)) }, uniquingKeysWith: { first, _ in first })
        let relative = RelativeDateTimeFormatter()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func makeSong(_ song: SubsonicSong) -> Song {
            let album = song.albumId.flatMap { albumByID[$0] }
                ?? Album(id: song.albumId ?? "none", title: song.album ?? "", artist: song.artist ?? "", year: song.year ?? 0,
                         genre: song.genre ?? "", coverArtID: song.coverArt)
            let created = song.created.flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return Song(id: song.id, title: song.title, album: album, seconds: song.duration ?? 0, artistName: song.artist, track: song.track,
                        source: SongSource(serverID: song.id, serverPath: song.path, suffix: song.suffix, bitRate: song.bitRate,
                                           sampleRate: song.samplingRate),
                        addedText: created.map { relative.localizedString(for: $0, relativeTo: .now) } ?? "", addedAt: created?.timeIntervalSince1970,
                        playCount: song.playCount ?? 0,
                        lastPlayed: song.played.flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }?.timeIntervalSince1970)
        }
        let server = serverSongs.map(makeSong)
        serverKeys = serverSongs.map(Library.key(for:))
        let index = FavoriteIndex(server: serverKeys)
        let serverByID = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Local files: albums by album name and artist, borrowing the server's album (and cover) when it is the same one.
        var localAlbums: [String: Album] = [:]
        var locals: [Song] = []
        for track in localTracks {
            let key = TrackKey(id: "local:" + track.relativePath, title: track.title, artist: track.artist, album: track.album,
                               durationMs: track.durationMs)
            let twin = index.serverID(for: key)
            let albumKey = TextMatch.fold((track.albumArtist ?? track.artist) + "|" + track.album)
            let album = localAlbums[albumKey] ?? twin.flatMap { serverByID[$0]?.album }
                ?? Album(id: "local-album:" + albumKey, title: track.album.isEmpty ? "Unknown album" : track.album,
                         artist: track.albumArtist ?? track.artist, year: track.year ?? 0, genre: track.genre ?? "",
                         localCover: URL(fileURLWithPath: track.path), tint: tint(albumKey))
            localAlbums[albumKey] = album
            locals.append(Song(id: key.id, title: track.title, album: album, seconds: track.durationMs / 1000,
                               artistName: track.artist.isEmpty ? nil : track.artist, track: track.track,
                               source: SongSource(localURL: URL(fileURLWithPath: track.path), serverID: twin,
                                                  serverPath: twin.flatMap { serverByID[$0]?.source.serverPath }, suffix: track.suffix,
                                                  sampleRate: twin.flatMap { serverByID[$0]?.source.sampleRate }),
                               // When the file came onto this Mac, as far as the file tells.
                               addedText: track.modified > 0 ? relative.localizedString(for: Date(timeIntervalSince1970: track.modified), relativeTo: .now) : "",
                               addedAt: track.modified > 0 ? track.modified : nil,
                               playCount: twin.flatMap { serverByID[$0]?.playCount } ?? 0,
                               lastPlayed: twin.flatMap { serverByID[$0]?.lastPlayed }))
        }
        let localKeys = locals.map { TrackKey(id: $0.id, title: $0.title, artist: $0.artist, album: $0.album.title, durationMs: $0.seconds * 1000) }
        let hidden = LocalFirst.hiddenServerIDs(locals: localKeys, server: serverKeys)
        hiddenServer = Dictionary(server.filter { hidden.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let visibleServer = server.filter { !hidden.contains($0.id) }
        songs = locals + visibleServer
        songByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        songKeys = localKeys + visibleServer.map { TrackKey(id: $0.id, title: $0.title, artist: $0.artist, album: $0.album.title,
                                                            durationMs: $0.seconds * 1000, serverID: $0.id) }
        // A server song with a local copy plays from the copy, also inside a playlist.
        let localForServer = Dictionary(locals.compactMap { song in song.source.serverID.map { ($0, song) } }, uniquingKeysWith: { first, _ in first })
        localByServerID = localForServer.mapValues(\.id)
        func preferLocal(_ song: Song) -> Song { localForServer[song.id] ?? song }
        // The server's albums and the local ones, plus any album a song points at that neither list has, so an album page
        // always finds its album instead of falling back to another one.
        var known = serverAlbums.map(makeAlbum) + localAlbums.values.filter { $0.id.hasPrefix("local-album:") }.sorted { $0.title < $1.title }
        var ids = Set(known.map(\.id))
        for song in songs where ids.insert(song.album.id).inserted { known.append(song.album) }
        albums = known
        // Mixes are no playlists of the listener's: not in Your Library, not in Add to playlist. Today's Daily Mixes of
        // this account go to Mixes for you on Home, the oldest of each when there are two.
        playlists = serverPlaylists.filter { !MixTag.isMix(comment: $0.comment, name: $0.name) }.map { list in
            Playlist(id: list.id, title: list.name, songs: (list.entry ?? []).map { preferLocal(serverByID[$0.id] ?? makeSong($0)) })
        }
        let day = MixTag.day()
        let infos = serverPlaylists.map(\.mixInfo)
        let dailyTags = Set(infos.compactMap(\.tag).filter { $0.kind == "daily" && $0.date == day })
        let dailies = dailyTags.compactMap { MixCopies.copies(of: $0, in: infos, user: client?.config.user ?? "").first { $0.tag?.date == day } }
            // PixelPlayer's Daily Mix first, then Daily Mix 1, 2, ...
            .sorted { (Int($0.tag?.key ?? "") ?? 0, $0.name) < (Int($1.tag?.key ?? "") ?? 0, $1.name) }
        serverMixSongs = [:]
        let dailyMixes: [Mix] = dailies.compactMap { info in
            guard let list = serverPlaylists.first(where: { $0.id == info.id }), let entries = list.entry, !entries.isEmpty else { return nil }
            let songs = entries.map { preferLocal(serverByID[$0.id] ?? makeSong($0)) }
            // No colon in the id: script steps and stored routes split on it.
            let id = "server-mix-\(list.id)"
            serverMixSongs[id] = songs
            var artists: [String] = []
            for song in songs where !artists.contains(song.artist) && artists.count < 3 { artists.append(song.artist) }
            // Colours as SpotCopy's covers: Daily Mix N gets pair N, PixelPlayer's one Daily Mix pair 6.
            let number = Int(info.tag?.key ?? "") ?? 6
            return Mix(id: id, title: list.name, subtitle: artists.joined(separator: ", ") + (Set(songs.map(\.artist)).count > 3 ? " and more" : ""),
                       symbol: "music.note", tone: .blue, covers: Array(songs.map(\.album).prefix(4)), pair: (number - 1) % 6 + 1)
        }
        likedIDs = FavoritesSync.shared.storedLikes
        recentAlbums = serverRecent.map { albumByID[$0.id] ?? makeAlbum($0) }
        if recentAlbums.isEmpty { recentAlbums = Array(albums.prefix(12)) }
        // Genre mixes from the genres with the most songs, local copies first.
        let genres = Dictionary(grouping: songs.filter { !$0.album.genre.isEmpty }, by: { $0.album.genre })
            .sorted { $0.value.count > $1.value.count }.prefix(5)
        let tones: [Tone] = [.pink, .blue, .green, .amber, .teal]
        mixes = dailyMixes + genres.enumerated().map { index, entry in
            let covers = Array(Set(entry.value.map(\.album))).prefix(4)
            return Mix(id: "genre-\(entry.key)", title: entry.key, subtitle: "Genre mix", symbol: "music.note", tone: tones[index % tones.count],
                       covers: Array(covers))
        }
        week = []
        if mixIDs.isEmpty || mixDay != Self.today { refreshDailyMix() }
        playlistSongIDs = Set(playlists.flatMap { $0.songs.map(\.id) })
        collectionItems = LibraryItem.collections(of: self)
        PlayerModel.shared.restoreIfEmpty()
        PlayerModel.shared.refreshFromLibrary()
    }

    /// The songs behind a place in the library, in the order its page shows them first.
    func songs(for route: Route) -> [Song] {
        switch route {
        case .songs: return TrackOrder.title.sorted(songs, fields: \.orderFields)
        case .liked: return liked
        case .playlist(let id): return playlists.first { $0.id == id }?.songs ?? []
        case .album(let id): return songs.filter { $0.album.id == id }.sorted { ($0.track ?? 0) < ($1.track ?? 0) }
        case .artist(let name): return TrackOrder.album.sorted(songs.filter { $0.artist == name || $0.album.artist == name }, fields: \.orderFields)
        case .genre(let name): return TrackOrder.artist.sorted(songs.filter { $0.album.genre == name }, fields: \.orderFields)
        case .mix(let id): return mixes.first { $0.id == id }.map { songs(for: $0) } ?? []
        case .home, .search, .shelf: return []
        }
    }

    /// The songs of a mix: a genre mix plays that genre, a sample mix the albums on its cover.
    func songs(for mix: Mix) -> [Song] {
        if let songs = serverMixSongs[mix.id] { return songs }
        if mix.id.hasPrefix("genre-") { return songs.filter { "genre-" + $0.album.genre == mix.id } }
        let albums = Set(mix.covers.map(\.id))
        return songs.filter { albums.contains($0.album.id) }
    }

    /// The cover image address for an album from the server.
    func coverURL(for album: Album, size: Int = 600) -> URL? {
        guard let client, let id = album.coverArtID else { return nil }
        return client.coverArtURL(id: id, size: size)
    }
}

/// Shuffles the same way all day, so Your Mix does not change every time the page is opened.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
