import Foundation

/// The orders a list of songs can be shown in, as the sort menu above a list offers them.
public enum TrackOrder: String, CaseIterable, Sendable {
    /// The list's own order, such as a playlist as it was made.
    case custom
    /// Newest first.
    case added
    case title, artist, album

    /// What a song is sorted by.
    public struct Fields: Sendable {
        public var title: String
        public var artist: String
        public var album: String
        public var track: Int?
        /// Seconds since 1970, nil when unknown.
        public var added: Double?

        public init(title: String, artist: String, album: String, track: Int? = nil, added: Double? = nil) {
            self.title = title
            self.artist = artist
            self.album = album
            self.track = track
            self.added = added
        }
    }

    /// The items in this order. Text compares as the Finder does (no case, numbers by value), empty text and unknown dates last,
    /// and items that are equal keep their place.
    public func sorted<T>(_ items: [T], fields: (T) -> Fields) -> [T] {
        guard self != .custom else { return items }
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
        let order = self
        return keyed.sorted { x, y in
            let a = x.fields, b = y.fields
            let steps: [ComparisonResult]
            switch order {
            case .custom: steps = []
            case .added: steps = [newest(a.added, b.added)]
            case .title: steps = [text(a.title, b.title), text(a.artist, b.artist), text(a.album, b.album)]
            case .artist: steps = [text(a.artist, b.artist), text(a.album, b.album), number(a.track, b.track), text(a.title, b.title)]
            case .album: steps = [text(a.album, b.album), number(a.track, b.track), text(a.title, b.title)]
            }
            for step in steps where step != .orderedSame { return step == .orderedAscending }
            return x.index < y.index
        }.map(\.item)
    }
}
