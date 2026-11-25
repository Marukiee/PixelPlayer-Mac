import Foundation

/// The text rules the Android app uses to see that a local file and a server song are the same recording.
/// The rules differ on purpose (spec section 2); they are kept apart instead of merged into one.
public enum TextMatch {
    private static let replacements: [Character: String] = [
        "ø": "o", "æ": "ae", "œ": "oe", "ß": "ss", "ł": "l", "đ": "d", "ð": "d", "þ": "th", "ı": "i", "ħ": "h", "ŧ": "t",
    ]
    private static let apostrophes: Set<Character> = ["'", "`", "´", "‘", "’", "ʼ"]

    /// Lowercase without accents, so "Björk" and "bjork" meet.
    static func stripMarks(_ text: String) -> String {
        let decomposed = text.lowercased().decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            out.append(scalar)
        }
        var result = ""
        for character in String(out) { result += replacements[character] ?? String(character) }
        return result
    }

    /// `fold`: lowercase, no accents, no apostrophes, every run of other signs one space.
    public static func fold(_ text: String) -> String {
        let stripped = stripMarks(text).filter { !apostrophes.contains($0) }
        var result = ""
        var pendingSpace = false
        for character in stripped {
            if character.isLetter || character.isNumber {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    /// `loose`: like fold, but without anything in brackets and without "feat." and what follows.
    public static func loose(_ text: String) -> String {
        var value = stripMarks(text)
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}")] {
            while let start = value.firstIndex(of: Character(open)), let end = value[start...].firstIndex(of: Character(close)) {
                value.removeSubrange(start...end)
            }
        }
        let words = value.split(whereSeparator: { $0 == " " })
        if let cut = words.firstIndex(where: { ["feat", "feat.", "ft", "ft.", "featuring"].contains($0) }) {
            value = words[..<cut].joined(separator: " ")
        }
        let cleaned = value.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == " " ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Both filled in, and equal or one inside the other.
    public static func contains(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }
}

/// What the matching rules need to know of a song.
public struct TrackKey: Sendable, Hashable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int
    /// The server song id: its own id for a server song, nil for a local file.
    public var serverID: String?

    public init(id: String, title: String, artist: String, album: String, durationMs: Int, serverID: String? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.durationMs = durationMs; self.serverID = serverID
    }
}

public enum LocalFirst {
    /// The library rule (SQL hide): a server song is hidden when a local copy has exactly the same title, an artist that is
    /// the same or starts with the other (ignoring case), and a length within 3 seconds.
    public static func hiddenServerIDs(locals: [TrackKey], server: [TrackKey]) -> Set<String> {
        let localsByTitle = Dictionary(grouping: locals, by: \.title)
        var hidden = Set<String>()
        for song in server {
            guard let id = song.serverID, let candidates = localsByTitle[song.title] else { continue }
            let artist = song.artist.lowercased()
            if candidates.contains(where: { local in
                let localArtist = local.artist.lowercased()
                let artistOK = artist == localArtist
                    || (!artist.isEmpty && !localArtist.isEmpty && (artist.hasPrefix(localArtist) || localArtist.hasPrefix(artist)))
                return artistOK && abs(local.durationMs - song.durationMs) <= 3000
            }) {
                hidden.insert(id)
            }
        }
        return hidden
    }

    /// `SongDuplicates`: one row per recording in search results.
    public static func isDuplicate(_ a: TrackKey, _ b: TrackKey) -> Bool {
        TextMatch.fold(a.title) == TextMatch.fold(b.title)
            && TextMatch.contains(TextMatch.fold(a.artist), TextMatch.fold(b.artist))
            && abs(a.durationMs - b.durationMs) <= 3000
    }
}

/// `FavoriteSongIndex`: finds the server id for a local song, and the local songs for a server star.
public struct FavoriteIndex: Sendable {
    private let byFold: [String: [TrackKey]]
    private let byLoose: [String: [TrackKey]]

    public init(server: [TrackKey]) {
        let songs = server.filter { $0.serverID != nil }
        byFold = Dictionary(grouping: songs, by: { TextMatch.fold($0.title) })
        byLoose = Dictionary(grouping: songs, by: { TextMatch.loose($0.title) })
    }

    /// Folded title first, loose title second; the artist must match; the nearest length wins, with no limit;
    /// the same album is preferred. A server song uses its own id.
    public func serverID(for song: TrackKey) -> String? {
        if let own = song.serverID { return own }
        // Folded title group first: the artist may match folded, else loose.
        if let group = byFold[TextMatch.fold(song.title)], !group.isEmpty {
            let folded = TextMatch.fold(song.artist), loose = TextMatch.loose(song.artist)
            var matches = group.filter { TextMatch.contains(TextMatch.fold($0.artist), folded) }
            if matches.isEmpty { matches = group.filter { TextMatch.contains(TextMatch.loose($0.artist), loose) } }
            if let id = nearest(in: matches, to: song) { return id }
        }
        // Then the loose title group.
        if let group = byLoose[TextMatch.loose(song.title)], !group.isEmpty {
            let loose = TextMatch.loose(song.artist)
            if let id = nearest(in: group.filter { TextMatch.contains(TextMatch.loose($0.artist), loose) }, to: song) { return id }
        }
        return nil
    }

    /// The same album first, then the nearest length.
    private func nearest(in matches: [TrackKey], to song: TrackKey) -> String? {
        guard !matches.isEmpty else { return nil }
        let album = TextMatch.fold(song.album)
        let sameAlbum = matches.filter { TextMatch.fold($0.album) == album }
        let pool = sameAlbum.isEmpty ? matches : sameAlbum
        return pool.min { abs($0.durationMs - song.durationMs) < abs($1.durationMs - song.durationMs) }?.serverID
    }

    /// The local songs a server star lights up: local files with the same folded title and a matching artist,
    /// preferring the same album, plus any row that is that server song itself.
    public static func locals(for star: TrackKey, in locals: [TrackKey]) -> Set<String> {
        let title = TextMatch.fold(star.title)
        let artist = TextMatch.fold(star.artist)
        let files = locals.filter { $0.serverID == nil && TextMatch.fold($0.title) == title && TextMatch.contains(TextMatch.fold($0.artist), artist) }
        let album = TextMatch.fold(star.album)
        let sameAlbum = files.filter { TextMatch.fold($0.album) == album }
        var result = Set((sameAlbum.isEmpty ? files : sameAlbum).map(\.id))
        for row in locals where row.serverID == star.serverID && star.serverID != nil { result.insert(row.id) }
        return result
    }
}
