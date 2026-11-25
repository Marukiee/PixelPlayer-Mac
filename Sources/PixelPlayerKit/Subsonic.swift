import Foundation
import CryptoKit

/// The Subsonic API that Navidrome speaks, as far as PixelPlayer needs it.
/// Token authentication (md5 of password plus salt), JSON responses.
public struct SubsonicConfig: Sendable, Equatable {
    public var server: URL
    public var user: String
    public var password: String
    public var client: String
    public var version: String

    public init(server: URL, user: String, password: String, client: String = "PixelPlayerMac", version: String = "1.16.1") {
        self.server = server
        self.user = user
        self.password = password
        self.client = client
        self.version = version
    }
}

public enum SubsonicError: Error, Equatable, LocalizedError {
    case badResponse
    case server(code: Int, message: String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .badResponse: "The server sent something that is not a Subsonic answer."
        case .server(_, let message): message
        case .http(let status): "The server answered with HTTP \(status)."
        }
    }
}

// MARK: Models, named after the Subsonic fields

public struct SubsonicSong: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var album: String?
    public var artist: String?
    public var albumId: String?
    public var artistId: String?
    public var track: Int?
    public var discNumber: Int?
    public var year: Int?
    public var genre: String?
    public var duration: Int?
    public var path: String?
    public var suffix: String?
    public var bitRate: Int?
    public var size: Int?
    public var coverArt: String?
    public var created: String?
    public var starred: String?
    public var playCount: Int?

    public init(id: String, title: String, album: String? = nil, artist: String? = nil, albumId: String? = nil, artistId: String? = nil,
                track: Int? = nil, discNumber: Int? = nil, year: Int? = nil, genre: String? = nil, duration: Int? = nil, path: String? = nil,
                suffix: String? = nil, bitRate: Int? = nil, size: Int? = nil, coverArt: String? = nil, created: String? = nil,
                starred: String? = nil, playCount: Int? = nil) {
        self.id = id; self.title = title; self.album = album; self.artist = artist; self.albumId = albumId; self.artistId = artistId
        self.track = track; self.discNumber = discNumber; self.year = year; self.genre = genre; self.duration = duration; self.path = path
        self.suffix = suffix; self.bitRate = bitRate; self.size = size; self.coverArt = coverArt; self.created = created
        self.starred = starred; self.playCount = playCount
    }
}

public struct SubsonicAlbum: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var artist: String?
    public var artistId: String?
    public var coverArt: String?
    public var songCount: Int?
    public var duration: Int?
    public var year: Int?
    public var genre: String?
    public var created: String?
    public var starred: String?
    public var song: [SubsonicSong]?
}

public struct SubsonicArtist: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var albumCount: Int?
    public var coverArt: String?
    public var starred: String?
}

public struct SubsonicPlaylist: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var songCount: Int?
    public var duration: Int?
    public var coverArt: String?
    public var owner: String?
    public var changed: String?
    public var entry: [SubsonicSong]?
}

public struct SubsonicStarred: Codable, Sendable, Hashable {
    public var song: [SubsonicSong]?
    public var album: [SubsonicAlbum]?
    public var artist: [SubsonicArtist]?
}

public struct SubsonicSearch: Codable, Sendable, Hashable {
    public var song: [SubsonicSong]?
    public var album: [SubsonicAlbum]?
    public var artist: [SubsonicArtist]?
}

/// OpenSubsonic getLyricsBySongId: lyrics with a start in milliseconds per line when synced.
public struct SubsonicStructuredLyrics: Codable, Sendable, Hashable {
    public struct Line: Codable, Sendable, Hashable {
        public var start: Int?
        public var value: String
    }
    public var displayArtist: String?
    public var displayTitle: String?
    public var lang: String?
    public var offset: Int?
    public var synced: Bool
    public var line: [Line]?
}

/// The older getLyrics: one block of text found by artist and title.
public struct SubsonicLyrics: Codable, Sendable, Hashable {
    public var artist: String?
    public var title: String?
    public var value: String?
}

// MARK: Client

public struct SubsonicClient: Sendable {
    public let config: SubsonicConfig
    private let session: URLSession

    public init(config: SubsonicConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// The salt is new for every request, so a captured URL cannot be replayed with another one.
    public static func token(password: String, salt: String) -> String {
        Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func authItems(salt: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()) -> [URLQueryItem] {
        [
            URLQueryItem(name: "u", value: config.user),
            URLQueryItem(name: "t", value: Self.token(password: config.password, salt: salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: config.version),
            URLQueryItem(name: "c", value: config.client),
            URLQueryItem(name: "f", value: "json"),
        ]
    }

    public func url(_ endpoint: String, _ params: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: config.server.appendingPathComponent("rest/\(endpoint)"), resolvingAgainstBaseURL: false)!
        components.queryItems = authItems() + params
        return components.url!
    }

    /// Calls an endpoint and decodes the part of the answer under `key` (for example `albumList2`).
    func get<T: Decodable>(_ endpoint: String, _ params: [URLQueryItem] = [], key: String?, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: url(endpoint, params))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw SubsonicError.http(http.statusCode) }
        return try Self.decode(data, key: key, as: type)
    }

    static func decode<T: Decodable>(_ data: Data, key: String?, as type: T.Type) throws -> T {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["subsonic-response"] as? [String: Any] else { throw SubsonicError.badResponse }
        if (body["status"] as? String) != "ok" {
            let error = body["error"] as? [String: Any]
            throw SubsonicError.server(code: error?["code"] as? Int ?? 0, message: error?["message"] as? String ?? "Unknown error")
        }
        guard let key else {
            return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
        }
        let part = body[key] ?? [String: Any]()
        let partData = try JSONSerialization.data(withJSONObject: part)
        return try JSONDecoder().decode(T.self, from: partData)
    }

    private struct Empty: Decodable {}
    private struct AlbumList: Decodable { var album: [SubsonicAlbum]? }
    private struct ArtistIndex: Decodable {
        struct Index: Decodable { var artist: [SubsonicArtist]? }
        var index: [Index]?
    }
    private struct PlaylistList: Decodable { var playlist: [SubsonicPlaylist]? }
    struct LyricsList: Decodable { var structuredLyrics: [SubsonicStructuredLyrics]? }

    public func ping() async throws {
        _ = try await get("ping", key: nil, as: Empty.self)
    }

    /// One page of albums. Navidrome allows up to 500 per page.
    public func albums(type: String = "alphabeticalByName", size: Int = 500, offset: Int = 0) async throws -> [SubsonicAlbum] {
        try await get("getAlbumList2", [.init(name: "type", value: type), .init(name: "size", value: "\(size)"), .init(name: "offset", value: "\(offset)")],
                      key: "albumList2", as: AlbumList.self).album ?? []
    }

    public func album(id: String) async throws -> SubsonicAlbum {
        try await get("getAlbum", [.init(name: "id", value: id)], key: "album", as: SubsonicAlbum.self)
    }

    public func artists() async throws -> [SubsonicArtist] {
        (try await get("getArtists", key: "artists", as: ArtistIndex.self).index ?? []).flatMap { $0.artist ?? [] }
    }

    /// Songs page by page. An empty query returns the whole library on Navidrome.
    public func search(_ query: String, songCount: Int = 500, songOffset: Int = 0, albumCount: Int = 0, artistCount: Int = 0) async throws -> SubsonicSearch {
        try await get("search3", [.init(name: "query", value: query), .init(name: "songCount", value: "\(songCount)"),
                                  .init(name: "songOffset", value: "\(songOffset)"), .init(name: "albumCount", value: "\(albumCount)"),
                                  .init(name: "artistCount", value: "\(artistCount)")],
                      key: "searchResult3", as: SubsonicSearch.self)
    }

    public func playlists() async throws -> [SubsonicPlaylist] {
        try await get("getPlaylists", key: "playlists", as: PlaylistList.self).playlist ?? []
    }

    public func playlist(id: String) async throws -> SubsonicPlaylist {
        try await get("getPlaylist", [.init(name: "id", value: id)], key: "playlist", as: SubsonicPlaylist.self)
    }

    public func starred() async throws -> SubsonicStarred {
        try await get("getStarred2", key: "starred2", as: SubsonicStarred.self)
    }

    public func star(songIDs: [String]) async throws {
        guard !songIDs.isEmpty else { return }
        _ = try await get("star", songIDs.map { .init(name: "id", value: $0) }, key: nil, as: Empty.self)
    }

    public func unstar(songIDs: [String]) async throws {
        guard !songIDs.isEmpty else { return }
        _ = try await get("unstar", songIDs.map { .init(name: "id", value: $0) }, key: nil, as: Empty.self)
    }

    public func createPlaylist(name: String, songIDs: [String]) async throws {
        _ = try await get("createPlaylist", [.init(name: "name", value: name)] + songIDs.map { .init(name: "songId", value: $0) },
                          key: nil, as: Empty.self)
    }

    public func updatePlaylist(id: String, adding: [String] = [], removingIndexes: [Int] = []) async throws {
        _ = try await get("updatePlaylist", [.init(name: "playlistId", value: id)]
                          + adding.map { .init(name: "songIdToAdd", value: $0) }
                          + removingIndexes.map { .init(name: "songIndexToRemove", value: "\($0)") },
                          key: nil, as: Empty.self)
    }

    /// `submission: false` is "now playing", `true` counts a play.
    public func scrobble(id: String, time: Date, submission: Bool) async throws {
        _ = try await get("scrobble", [.init(name: "id", value: id), .init(name: "time", value: "\(Int(time.timeIntervalSince1970 * 1000))"),
                                       .init(name: "submission", value: submission ? "true" : "false")],
                          key: nil, as: Empty.self)
    }

    /// OpenSubsonic playback report: shows what plays now on the server without counting a listen (ignoreScrobble).
    public func reportPlayback(id: String, positionMs: Int, state: String) async throws {
        _ = try await get("reportPlayback", [.init(name: "mediaId", value: id), .init(name: "mediaType", value: "song"),
                                             .init(name: "positionMs", value: "\(positionMs)"), .init(name: "state", value: state),
                                             .init(name: "playbackRate", value: "1.0"), .init(name: "ignoreScrobble", value: "true")],
                          key: nil, as: Empty.self)
    }

    /// Lyrics of a song by its id (OpenSubsonic). Only reads.
    public func lyrics(songID: String) async throws -> [SubsonicStructuredLyrics] {
        try await get("getLyricsBySongId", [.init(name: "id", value: songID)], key: "lyricsList", as: LyricsList.self).structuredLyrics ?? []
    }

    /// Lyrics found by artist and title, for servers without the call above. Only reads.
    public func lyrics(artist: String, title: String) async throws -> SubsonicLyrics {
        try await get("getLyrics", [.init(name: "artist", value: artist), .init(name: "title", value: title)], key: "lyrics", as: SubsonicLyrics.self)
    }

    public func streamURL(id: String) -> URL { url("stream", [.init(name: "id", value: id)]) }

    public func coverArtURL(id: String, size: Int? = nil) -> URL {
        url("getCoverArt", [.init(name: "id", value: id)] + (size.map { [.init(name: "size", value: "\($0)")] } ?? []))
    }
}
