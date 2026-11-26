import Foundation

/// Lyrics from LRCLIB (lrclib.net), looked up first as PixelPlayer on Android does: by title and artist, the entry whose
/// length matches the song, synced before plain. Lyrics in a file or on the server are often timed to another release of
/// the song (Mark, 2026-11-26: the Mac lit the second half of a sentence while the first was sung; Android had it right).
/// Only reads: the title, artist and length go out, nothing else.
public enum LRCLib {
    public struct Entry: Decodable, Sendable, Equatable {
        public var id: Int
        public var trackName: String?
        public var artistName: String?
        public var duration: Double?
        public var instrumental: Bool?
        public var plainLyrics: String?
        public var syncedLyrics: String?

        public init(id: Int, trackName: String?, artistName: String?, duration: Double?, instrumental: Bool? = false,
                    plainLyrics: String? = nil, syncedLyrics: String? = nil) {
            self.id = id
            self.trackName = trackName
            self.artistName = artistName
            self.duration = duration
            self.instrumental = instrumental
            self.plainLyrics = plainLyrics
            self.syncedLyrics = syncedLyrics
        }

        var synced: Bool { !(syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var plain: Bool { !(plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// How far an entry's length may be from the song's, as on Android: 2% of it (5 to 8 s) for synced lyrics, 4% (8 to 15 s)
    /// for plain ones.
    public static func tolerance(_ seconds: Double, synced: Bool) -> Double {
        synced ? min(max(seconds * 0.02, 5), 8) : min(max(seconds * 0.04, 8), 15)
    }

    /// A title or artist without what is in brackets ("(Remastered 2011)", "[Live]"), trimmed.
    public static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*[\(\[\{（［【「『〔〈《][^\)\]\}）］】」』〕〉》]*[\)\]\}）］】」』〕〉》]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// For comparing names: lower case, letters and digits only (accents kept, so "Hjälp" is not "Hjalp").
    static func key(_ text: String) -> String {
        String(clean(text).lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The entry to use: the same title, the artist named, its length close to the song's; synced before plain, then the
    /// closest length.
    public static func best(_ entries: [Entry], title: String, artist: String, seconds: Double) -> Entry? {
        let wantedTitle = key(title)
        let wantedArtist = key(artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? artist)
        let fitting = entries.filter { entry in
            guard entry.instrumental != true, entry.synced || entry.plain else { return false }
            guard key(entry.trackName ?? "") == wantedTitle else { return false }
            let entryArtist = key(entry.artistName ?? "")
            guard wantedArtist.isEmpty || entryArtist.contains(wantedArtist) || wantedArtist.contains(entryArtist) && !entryArtist.isEmpty else { return false }
            guard seconds > 0, let length = entry.duration else { return seconds <= 0 }
            return abs(length - seconds) <= tolerance(seconds, synced: entry.synced)
        }
        return fitting.min { a, b in
            if a.synced != b.synced { return a.synced }
            return abs((a.duration ?? 0) - seconds) < abs((b.duration ?? 0) - seconds)
        }
    }

    /// Looks the song up; nil when LRCLIB has nothing that fits or can't be reached.
    public static func lookup(title: String, artist: String, seconds: Double, session: URLSession = .shared) async -> Entry? {
        let cleanTitle = clean(title), cleanArtist = clean(artist)
        guard !cleanTitle.isEmpty else { return nil }
        // As on Android: by title and artist, then as one search.
        let searches: [[URLQueryItem]] = [
            [URLQueryItem(name: "track_name", value: cleanTitle), URLQueryItem(name: "artist_name", value: cleanArtist)],
            [URLQueryItem(name: "q", value: "\(cleanArtist) \(cleanTitle)")],
        ]
        for query in searches {
            var parts = URLComponents(string: "https://lrclib.net/api/search")!
            parts.queryItems = query
            guard let url = parts.url else { continue }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("PixelPlayer Mac (https://github.com/Marukiee/PixelPlayer-Mac)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let entries = try? JSONDecoder().decode([Entry].self, from: data) else { continue }
            if let entry = best(entries, title: title, artist: artist, seconds: seconds) { return entry }
        }
        return nil
    }
}

extension Lyrics {
    /// The lines of an LRCLIB entry: its synced lyrics when it has them, otherwise the plain ones.
    public init?(lrclib entry: LRCLib.Entry) {
        let lyrics = LRC.parse((entry.synced ? entry.syncedLyrics : entry.plainLyrics) ?? "")
        guard !lyrics.isEmpty else { return nil }
        self = lyrics
    }
}
