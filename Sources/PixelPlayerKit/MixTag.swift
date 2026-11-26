import Foundation

/// The mark that makes a Navidrome playlist a mix, agreed between SpotCopy, PixelPlayer and this Mac app
/// (MIXEN-NAVIDROME.md): a readable sentence in the comment with `[mix:<kind>:<key>:<yyyy-mm-dd>]` at the end.
/// `[mix:your::2026-11-27]` is Your Mix, `[mix:daily::...]` PixelPlayer's one Daily Mix, `[mix:daily:1:...]` SpotCopy's
/// Daily Mix 1. Apps know a mix by this mark only, never by its name: a playlist of your own called Daily Mix 1 stays yours.
public struct MixTag: Hashable, Sendable {
    public var kind: String
    public var key: String
    /// The local day it was made, as `yyyy-MM-dd`.
    public var date: String

    public init(kind: String, key: String = "", date: String) {
        self.kind = kind
        self.key = key
        self.date = date
    }

    public static let yourMixName = "Your Mix"
    /// What this Mac wrote before the mark existed (0.2.x): the playlist Your Mix with this and the date.
    public static let legacyPrefix = "PixelPlayer daily mix "

    /// `[mix:your::2026-11-27]`.
    public var mark: String { "[mix:\(kind):\(key):\(date)]" }

    /// The comment to write: the sentence PixelPlayer writes too, then the mark.
    public var comment: String { "Made for you, refreshed every day. \(mark)" }

    /// Same mix, whatever the day.
    public func sameMix(as other: MixTag) -> Bool { kind == other.kind && key == other.key }

    /// The mark in a playlist's comment, wherever it stands, or the old comment of this Mac's Your Mix. Nil for anything else.
    public static func read(comment: String?, name: String? = nil) -> MixTag? {
        guard let comment else { return nil }
        if let start = comment.range(of: "[mix:", options: .backwards),
           let end = comment[start.upperBound...].firstIndex(of: "]") {
            // Kind first, day last, the key is all in between (empty for Your Mix and PixelPlayer's Daily Mix).
            let parts = comment[start.upperBound..<end].components(separatedBy: ":")
            guard parts.count >= 3, let kind = parts.first, !kind.isEmpty, let date = parts.last, isDay(date) else { return nil }
            return MixTag(kind: kind, key: parts.dropFirst().dropLast().joined(separator: ":"), date: date)
        }
        // The old comment counts only on the playlist it was written on.
        if name == yourMixName, comment.hasPrefix(legacyPrefix) {
            let date = comment.dropFirst(legacyPrefix.count).trimmingCharacters(in: .whitespaces)
            return isDay(date) ? MixTag(kind: "your", date: date) : nil
        }
        return nil
    }

    /// True for a playlist that is a mix and not one of the listener's own: any `[mix:` (also one this app can't read) or
    /// the old comment of Your Mix.
    public static func isMix(comment: String?, name: String?) -> Bool {
        guard let comment else { return false }
        return comment.contains("[mix:") || read(comment: comment, name: name) != nil
    }

    /// A real day written as `yyyy-MM-dd`.
    public static func isDay(_ text: String) -> Bool {
        guard text.count == 10, text.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
        // Read and written back the same: 2026-02-30 is not a day.
        let format = dayFormatter(TimeZone(identifier: "UTC")!)
        return format.date(from: text).map { format.string(from: $0) == text } ?? false
    }

    /// The local day of a moment, as the mark writes it.
    public static func day(_ date: Date = .now, timeZone: TimeZone = .current) -> String {
        dayFormatter(timeZone).string(from: date)
    }

    private static func dayFormatter(_ zone: TimeZone) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = zone
        format.dateFormat = "yyyy-MM-dd"
        return format
    }
}

/// One playlist as the mix rules see it, from getPlaylists.
public struct MixPlaylist: Hashable, Sendable {
    public var id: String
    public var name: String
    public var comment: String?
    public var owner: String?
    public var created: String?
    public var readonly: Bool

    public init(id: String, name: String, comment: String?, owner: String?, created: String?, readonly: Bool = false) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.created = created
        self.readonly = readonly
    }

    public var tag: MixTag? { MixTag.read(comment: comment, name: name) }
}

/// Which playlist of a mix to keep, and which to take away. Only playlists with a mark, of this account, are ever touched.
public enum MixCopies {
    /// The copies of this mix (same kind and key, any day) that belong to `user`, oldest first.
    public static func copies(of tag: MixTag, in lists: [MixPlaylist], user: String) -> [MixPlaylist] {
        lists.filter { list in
            !list.readonly && (list.owner.map { $0.caseInsensitiveCompare(user) == .orderedSame } ?? false)
                && (list.tag.map { $0.sameMix(as: tag) } ?? false)
        }
        .sorted { a, b in
            let x = created(a.created), y = created(b.created)
            return x != y ? x < y : a.id < b.id
        }
    }

    /// The oldest copy stays, the others go.
    public static func plan(for tag: MixTag, in lists: [MixPlaylist], user: String) -> (keep: MixPlaylist?, remove: [MixPlaylist]) {
        let all = copies(of: tag, in: lists, user: user)
        return (all.first, Array(all.dropFirst()))
    }

    /// Seconds since 1970 of a Navidrome time such as `2026-11-26T19:08:47.21337357Z`, whatever the number of digits after
    /// the second (Navidrome sends 8 or 9, which compare wrongly as text). Unknown counts as newest.
    public static func created(_ text: String?) -> Double {
        guard let text, text.count >= 19 else { return .infinity }
        let whole = String(text.prefix(19))
        let parse = ISO8601DateFormatter()
        parse.formatOptions = [.withInternetDateTime]
        guard let base = parse.date(from: whole + "Z") else { return .infinity }
        var rest = text.dropFirst(19)
        var fraction = 0.0
        if rest.first == "." {
            let digits = rest.dropFirst().prefix { $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            rest = rest.dropFirst(1 + digits.count)
        }
        // A zone other than Z: +hh:mm or -hh:mm.
        var offset = 0.0
        if let sign = rest.first, sign == "+" || sign == "-" {
            let parts = rest.dropFirst().split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { offset = (parts[0] * 3600 + parts[1] * 60) * (sign == "+" ? 1 : -1) }
        }
        return base.timeIntervalSince1970 + fraction - offset
    }
}
