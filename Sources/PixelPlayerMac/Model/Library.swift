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

    private static var today: Int { Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 1 }
    static let mixName = "Your Mix"
    private static var mixTag: String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.locale = Locale(identifier: "en_US_POSIX")
        return "PixelPlayer daily mix \(format.string(from: .now))"
    }

    /// Makes today's mix from the library: likes, plays and dates. Again only on a new day or a new library.
    func refreshDailyMix() {
        let candidates = songs.map { song in
            MixCandidate(id: song.id, artist: song.artist, liked: likedIDs.contains(song.id), playCount: song.playCount,
                         lastPlayed: song.lastPlayed, added: song.addedAt)
        }
        mixIDs = DailyMix.pick(candidates, day: Self.today, now: Date.now.timeIntervalSince1970)
        mixDay = Self.today
    }

    /// A new day while the app was open: a new mix, and the shared one of today.
    func checkNewDay() async {
        guard !isSample, !songs.isEmpty, mixDay != Self.today else { return }
        refreshDailyMix()
        sharedMixIDs = nil
        await syncYourMix()
    }

    /// The same mix on every device: the first one of the day puts it on Navidrome as the playlist Your Mix, the others
    /// take that one. A playlist called Your Mix that PixelPlayer did not make is never touched.
    func syncYourMix() async {
        guard let client, !isSample else { return }
        let tag = Self.mixTag
        let existing = serverPlaylists.first { $0.name == Self.mixName }
        if let existing, existing.comment == tag, let entries = existing.entry, !entries.isEmpty {
            sharedMixIDs = entries.map { localByServerID[$0.id] ?? $0.id }
            return
        }
        if let existing, !(existing.comment ?? "").hasPrefix("PixelPlayer daily mix") { return }
        let ids = yourMix.compactMap(\.source.serverID)
        guard ids.count >= 5 else { return }
        do {
            if let existing {
                try await client.replacePlaylist(id: existing.id, songIDs: ids)
                try await client.setPlaylistComment(id: existing.id, comment: tag)
            } else {
                try await client.createPlaylist(name: Self.mixName, songIDs: ids)
                if let made = try await client.playlists().first(where: { $0.name == Self.mixName }) {
                    try await client.setPlaylistComment(id: made.id, comment: tag)
                }
            }
            var lists: [SubsonicPlaylist] = []
            for list in try await client.playlists() { lists.append((try? await client.playlist(id: list.id)) ?? list) }
            serverPlaylists = lists
            sharedMixIDs = nil
            rebuild()
        } catch {
            SonosLog.write("your mix sync failed: \(error.localizedDescription)")
        }
    }

    var yourMixSummary: String {
        if isSample { return "Blue Hour, Night Signal, Orbit and 18 more" }
        let mix = yourMix
        guard !mix.isEmpty else { return "Play something to get your mix going" }
        let names = mix.prefix(3).map(\.title).joined(separator: ", ")
        return mix.count > 3 ? "\(names) and \(mix.count - 3) more" : names
    }

    /// "12 songs · 1 h 4 m"
    static func summary(_ songs: [Song]) -> String {
        let seconds = songs.reduce(0) { $0 + $1.seconds }
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        let time = hours > 0 ? "\(hours) h \(minutes) m" : "\(minutes) m"
        return "\(songCount(songs.count)) · \(time)"
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

    func song(id: String) -> Song? { songs.first { $0.id == id } }

    init() {
        let env = ProcessInfo.processInfo.environment
        if Debug.active, let server = env["PP_LIVE_SERVER"], let url = URL(string: server) {
            // A scripted run against a fake server: the login comes from the run, not the keychain.
            client = SubsonicClient(config: SubsonicConfig(server: url, user: env["PP_LIVE_USER"] ?? "test", password: env["PP_LIVE_PASSWORD"] ?? "test"))
            FavoritesSync.shared.use(account: "\(server)|test")
            Task { await scanLocal(); await reload() }
        } else if Debug.active, env["PP_MUSIC_FOLDER"] != nil {
            // A scripted run against a music folder and no server: the live app as it is with only local files.
            Task { await scanLocal() }
        } else if Debug.active {
            loadSample()
        } else if let settings = ServerSettings.saved, let config = settings.config {
            client = SubsonicClient(config: config)
            FavoritesSync.shared.use(account: "\(settings.server)|\(settings.user)")
            Task { await scanLocal(); await reload() }
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
        status = .sample
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
        status = .loading("Loading your library")
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
            await FavoritesSync.shared.sync()
            refreshDailyMix()
            await syncYourMix()
            await ScrobbleQueue.shared.send()
        } catch {
            status = .failed(error.localizedDescription)
        }
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
        playlists = serverPlaylists.map { list in
            Playlist(id: list.id, title: list.name, songs: (list.entry ?? []).map { preferLocal(serverByID[$0.id] ?? makeSong($0)) })
        }
        likedIDs = FavoritesSync.shared.storedLikes
        recentAlbums = serverRecent.map { albumByID[$0.id] ?? makeAlbum($0) }
        if recentAlbums.isEmpty { recentAlbums = Array(albums.prefix(12)) }
        // Genre mixes from the genres with the most songs, local copies first.
        let genres = Dictionary(grouping: songs.filter { !$0.album.genre.isEmpty }, by: { $0.album.genre })
            .sorted { $0.value.count > $1.value.count }.prefix(5)
        let tones: [Tone] = [.pink, .blue, .green, .amber, .teal]
        mixes = genres.enumerated().map { index, entry in
            let covers = Array(Set(entry.value.map(\.album))).prefix(4)
            return Mix(id: "genre-\(entry.key)", title: entry.key, subtitle: "Genre mix", symbol: "music.note", tone: tones[index % tones.count],
                       covers: Array(covers))
        }
        week = []
        if mixIDs.isEmpty || mixDay != Self.today { refreshDailyMix() }
        playlistSongIDs = Set(playlists.flatMap { $0.songs.map(\.id) })
        collectionItems = LibraryItem.collections(of: self)
        PlayerModel.shared.restoreIfEmpty()
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
