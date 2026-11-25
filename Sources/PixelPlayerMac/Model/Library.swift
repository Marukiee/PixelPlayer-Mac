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

/// Where the Navidrome server is. The password is kept in the keychain under the user name.
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
        if let password { Keychain.setPassword(password, for: user) }
    }

    var config: SubsonicConfig? {
        guard let url = URL(string: server.hasPrefix("http") ? server : "http://\(server)"),
              let password = Keychain.password(for: user) else { return nil }
        return SubsonicConfig(server: url, user: user, password: password)
    }
}

/// All music the app knows: the sample music for the design shots, or the Navidrome library.
@MainActor @Observable
final class Library {
    static let shared = Library()

    var status: LibraryStatus = .notConnected
    var albums: [Album] = []
    var songs: [Song] = []
    var playlists: [Playlist] = []
    var likedIDs: Set<String> = []
    var mixes: [Mix] = []
    var week: [Int] = []
    var recentSearches: [String] = []
    var recentAlbums: [Album] = []
    private(set) var client: SubsonicClient?

    var liked: [Song] { songs.filter { likedIDs.contains($0.id) } }

    /// Your Mix: liked songs first, topped up from the rest of the library, 21 in all, fresh every day.
    var yourMix: [Song] {
        if isSample { return Sample.songs }
        var generator = SeededGenerator(seed: UInt64(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 1))
        let likedPart = liked.shuffled(using: &generator)
        let rest = songs.filter { !likedIDs.contains($0.id) }.shuffled(using: &generator)
        return Array((likedPart + rest).prefix(21))
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
        return "\(songs.count.formatted()) songs · \(time)"
    }
    var isSample: Bool { status == .sample }
    /// True once there is music to show.
    var hasMusic: Bool { !songs.isEmpty }

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
            Task { await reload() }
        } else if Debug.active {
            loadSample()
        } else if let settings = ServerSettings.saved, let config = settings.config {
            client = SubsonicClient(config: config)
            Task { await reload() }
        }
    }

    func loadSample() {
        albums = Sample.albums
        songs = Sample.songs
        playlists = Sample.playlists
        likedIDs = Set(Sample.liked.map(\.id))
        mixes = Sample.mixes
        week = Sample.week
        recentSearches = Sample.recentSearches
        recentAlbums = Sample.albums
        status = .sample
    }

    /// Tries the server and, when it answers, keeps the settings and loads the library.
    func connect(_ settings: ServerSettings, password: String) async {
        guard let url = URL(string: settings.server.hasPrefix("http") ? settings.server : "http://\(settings.server)") else {
            status = .failed("That is not a server address.")
            return
        }
        let candidate = SubsonicClient(config: SubsonicConfig(server: url, user: settings.user, password: password))
        status = .loading("Connecting")
        do {
            try await candidate.ping()
            settings.save(password: password)
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
            var serverSongs: [SubsonicSong] = []
            while true {
                let page = try await client.search("", songCount: 500, songOffset: serverSongs.count).song ?? []
                serverSongs += page
                if page.count < 500 { break }
            }
            let starred = try await client.starred()
            var lists: [SubsonicPlaylist] = []
            for list in try await client.playlists() {
                lists.append((try? await client.playlist(id: list.id)) ?? list)
            }
            let recent = (try? await client.albums(type: "recent", size: 20)) ?? []
            apply(albums: serverAlbums, songs: serverSongs, starred: starred, playlists: lists, recent: recent)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func apply(albums serverAlbums: [SubsonicAlbum], songs serverSongs: [SubsonicSong], starred: SubsonicStarred,
                       playlists serverLists: [SubsonicPlaylist], recent: [SubsonicAlbum]) {
        let tints: [UInt32] = [0x23408F, 0x5B2A86, 0x14594F, 0x8C3A1E, 0x2B5C8F, 0x0F7C80, 0x4A2C7A]
        func makeAlbum(_ album: SubsonicAlbum) -> Album {
            Album(id: album.id, title: album.name, artist: album.artist ?? "Unknown artist", year: album.year ?? 0, genre: album.genre ?? "",
                  coverArtID: album.coverArt ?? album.id, tint: tints[abs(album.id.hashValue) % tints.count])
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
                        source: SongSource(serverID: song.id, serverPath: song.path, suffix: song.suffix, bitRate: song.bitRate),
                        addedText: created.map { relative.localizedString(for: $0, relativeTo: .now) } ?? "")
        }
        albums = serverAlbums.map(makeAlbum)
        songs = serverSongs.map(makeSong)
        let songByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        playlists = serverLists.map { list in
            Playlist(id: list.id, title: list.name, songs: (list.entry ?? []).map { songByID[$0.id] ?? makeSong($0) })
        }
        likedIDs = Set((starred.song ?? []).map(\.id))
        recentAlbums = recent.map { albumByID[$0.id] ?? makeAlbum($0) }
        // Genre mixes from the genres with the most songs.
        let genres = Dictionary(grouping: songs.filter { !$0.album.genre.isEmpty }, by: { $0.album.genre })
            .sorted { $0.value.count > $1.value.count }.prefix(5)
        let tones: [Tone] = [.pink, .blue, .green, .amber, .teal]
        mixes = genres.enumerated().map { index, entry in
            let covers = Array(Set(entry.value.map(\.album))).prefix(4)
            return Mix(id: "genre-\(entry.key)", title: entry.key, subtitle: "Genre mix", symbol: "music.note", tone: tones[index % tones.count],
                       covers: Array(covers))
        }
        week = []
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
