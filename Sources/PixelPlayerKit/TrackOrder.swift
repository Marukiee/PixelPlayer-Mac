import Foundation

/// The orders a list of songs can be shown in, as the sort menu above a list offers them.
public enum TrackOrder: String, CaseIterable, Sendable {
    /// The list's own order, such as a playlist as it was made.
    case custom
    /// Newest first.
    case added
    case title, artist, album
    /// Shortest first.
    case duration

    /// What a song is sorted by.
    public struct Fields: Sendable {
        public var title: String
        public var artist: String
        public var album: String
        public var track: Int?
        /// Seconds since 1970, nil when unknown.
        public var added: Double?
        /// Length in seconds, nil when unknown.
        public var seconds: Int?

        public init(title: String, artist: String, album: String, track: Int? = nil, added: Double? = nil, seconds: Int? = nil) {
            self.title = title
            self.artist = artist
            self.album = album
            self.track = track
            self.added = added
            self.seconds = seconds
        }
    }

    /// The items in this order, or the other way round when `reversed` (as a second click on a column title does). Text
    /// compares as the Finder does (no case, numbers by value); empty text and unknown dates stay last either way, and items
    /// that are equal keep their place.
    public func sorted<T>(_ items: [T], reversed: Bool = false, fields: (T) -> Fields) -> [T] {
        guard self != .custom else { return reversed ? items.reversed() : items }
        let keyed = items.enumerated().map { (index: $0.offset, item: $0.element, fields: fields($0.element)) }
        func text(_ a: String, _ b: String) -> ComparisonResult {
            switch (a.isEmpty, b.isEmpty) {
            case (true, true): return .orderedSame
            case (true, false): return .orderedDescending
            case (false, true): return .orderedAscending
            default: return a.localizedStandardCompare(b)
            }
        }
        func number(_ a: Int?, _ b: Int?) -> ComparisonResult {
            switch (a, b) {
            case let (a?, b?): return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            }
        }
        func newest(_ a: Double?, _ b: Double?) -> ComparisonResult {
            switch (a, b) {
            case let (a?, b?): return a == b ? .orderedSame : a > b ? .orderedAscending : .orderedDescending
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            }
        }
        func flip(_ result: ComparisonResult, known: Bool) -> ComparisonResult {
            guard reversed, known else { return result }
            return result == .orderedAscending ? .orderedDescending : result == .orderedDescending ? .orderedAscending : result
        }
        let order = self
        return keyed.sorted { x, y in
            let a = x.fields, b = y.fields
            let steps: [ComparisonResult]
            switch order {
            case .custom: steps = []
            case .added: steps = [flip(newest(a.added, b.added), known: a.added != nil && b.added != nil)]
            case .title: steps = [flip(text(a.title, b.title), known: !a.title.isEmpty && !b.title.isEmpty), text(a.artist, b.artist), text(a.album, b.album)]
            case .artist: steps = [flip(text(a.artist, b.artist), known: !a.artist.isEmpty && !b.artist.isEmpty), text(a.album, b.album),
                                   number(a.track, b.track), text(a.title, b.title)]
            case .album: steps = [flip(text(a.album, b.album), known: !a.album.isEmpty && !b.album.isEmpty), number(a.track, b.track), text(a.title, b.title)]
            case .duration: steps = [flip(number(a.seconds, b.seconds), known: a.seconds != nil && b.seconds != nil), text(a.title, b.title)]
            }
            for step in steps where step != .orderedSame { return step == .orderedAscending }
            return x.index < y.index
        }.map(\.item)
    }
}
