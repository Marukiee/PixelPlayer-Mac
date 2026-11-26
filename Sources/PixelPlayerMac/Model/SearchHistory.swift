import Foundation

/// What was opened from a search, newest first, as Spotify keeps it (and as SpotCopy on Android does, Store.searches):
/// an artist, an album or a song, at most thirty, each to remove on its own or all at once. Remembered.
@MainActor @Observable
final class SearchHistory {
    static let shared = SearchHistory()
    private(set) var codes: [String] = UserDefaults.standard.stringArray(forKey: "search.recents") ?? []

    func remember(_ code: String) {
        codes.removeAll { $0 == code }
        codes.insert(code, at: 0)
        if codes.count > 30 { codes.removeLast(codes.count - 30) }
        save()
    }

    func forget(_ code: String) {
        codes.removeAll { $0 == code }
        save()
    }

    func clear() {
        codes = []
        save()
    }

    private func save() { UserDefaults.standard.set(codes, forKey: "search.recents") }

    nonisolated static func code(album: Album) -> String { "album:" + album.id }
    nonisolated static func code(song: Song) -> String { "song:" + song.id }
    nonisolated static func code(artist: String) -> String { "artist:" + artist }
}

/// A recent search, found again in the library; one that is no longer there is left out.
enum RecentSearch: Identifiable {
    case album(Album), song(Song), artist(String, Album)

    var id: String {
        switch self {
        case .album(let album): SearchHistory.code(album: album)
        case .song(let song): SearchHistory.code(song: song)
        case .artist(let name, _): SearchHistory.code(artist: name)
        }
    }

    @MainActor init?(code: String) {
        let library = Library.shared
        guard let colon = code.firstIndex(of: ":") else { return nil }
        let value = String(code[code.index(after: colon)...])
        switch code[..<colon] {
        case "album": guard let album = library.albums.first(where: { $0.id == value }) else { return nil }; self = .album(album)
        case "song": guard let song = library.song(id: value) else { return nil }; self = .song(song)
        case "artist": guard let album = library.albums.first(where: { $0.artist == value }) else { return nil }; self = .artist(value, album)
        default: return nil
        }
    }
}
