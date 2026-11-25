import Foundation

/// One song as the daily mix weighs it. Plays and dates come from Navidrome, so every device sees the same history.
public struct MixCandidate: Sendable, Hashable {
    public var id: String
    public var artist: String
    public var liked: Bool
    public var playCount: Int
    /// Seconds since 1970 of the last play, when known.
    public var lastPlayed: Double?
    /// Seconds since 1970 the song came into the library, when known.
    public var added: Double?

    public init(id: String, artist: String, liked: Bool, playCount: Int, lastPlayed: Double? = nil, added: Double? = nil) {
        self.id = id
        self.artist = artist
        self.liked = liked
        self.playCount = playCount
        self.lastPlayed = lastPlayed
        self.added = added
    }
}

/// Your Mix: a new mix every day that stays the same all day and is the same on every device with the same library.
///
/// Five parts, mixed through each other:
/// - favourites: liked songs, the more played the likelier;
/// - heavy rotation: songs played a lot that are not liked;
/// - discoveries: songs never played by the artists you like or play most;
/// - rediscoveries: liked songs not played for a month;
/// - new: songs added in the last month that were not played yet.
/// Songs played in the last two days stay out (when enough are left), at most three songs per artist, and never the same
/// artist twice in a row.
public enum DailyMix {
    public static func pick(_ candidates: [MixCandidate], day: Int, now: Double, count: Int = 25) -> [String] {
        guard !candidates.isEmpty else { return [] }
        var random = SplitMix(seed: UInt64(truncatingIfNeeded: day) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491)
        let day: Double = 86_400
        let rested = candidates.filter { ($0.lastPlayed ?? 0) < now - 2 * day }
        let pool = rested.count >= count * 2 ? rested : candidates

        // How much each artist means to you: likes count three times as much as plays.
        var artistWeight: [String: Double] = [:]
        for song in candidates { artistWeight[song.artist, default: 0] += (song.liked ? 3 : 0) + Double(min(song.playCount, 50)) }
        let topArtists = Set(artistWeight.sorted { $0.value > $1.value }.prefix(20).filter { $0.value > 0 }.map(\.key))
        let plays = pool.map(\.playCount).filter { $0 > 0 }.sorted()
        let median = plays.isEmpty ? 1 : plays[plays.count / 2]

        let favourites = pool.filter(\.liked)
        let heavy = pool.filter { !$0.liked && $0.playCount >= max(median, 2) }
        let discoveries = pool.filter { !$0.liked && $0.playCount == 0 && topArtists.contains($0.artist) }
        let rediscoveries = pool.filter { $0.liked && ($0.lastPlayed.map { $0 < now - 30 * day } ?? false) }
        let fresh = pool.filter { ($0.added.map { $0 > now - 30 * day } ?? false) && $0.playCount == 0 }

        let share = Double(count) / 25
        let parts: [([MixCandidate], Int, (MixCandidate) -> Double)] = [
            (favourites, Int((8 * share).rounded()), { 1 + log(1 + Double($0.playCount)) }),
            (heavy, Int((5 * share).rounded()), { log(1 + Double($0.playCount)) }),
            (discoveries, Int((6 * share).rounded()), { 1 + (artistWeight[$0.artist] ?? 0) / 10 }),
            (rediscoveries, Int((3 * share).rounded()), { _ in 1 }),
            (fresh, Int((3 * share).rounded()), { _ in 1 }),
        ]
        var chosen: [MixCandidate] = []
        var taken = Set<String>()
        var perArtist: [String: Int] = [:]
        func take(from list: [MixCandidate], upTo limit: Int, capped: Bool = true, weight: (MixCandidate) -> Double) {
            var rest = list.filter { !taken.contains($0.id) }
            var added = 0
            while added < limit, !rest.isEmpty {
                // A weighted draw: a heavier song is likelier, but any can come up.
                let weights = rest.map { max(0.05, weight($0)) }
                var target = Double.random(in: 0..<weights.reduce(0, +), using: &random)
                var index = 0
                while index < weights.count - 1, target >= weights[index] { target -= weights[index]; index += 1 }
                let song = rest.remove(at: index)
                if capped, perArtist[song.artist, default: 0] >= 3 { continue }
                perArtist[song.artist, default: 0] += 1
                taken.insert(song.id)
                chosen.append(song)
                added += 1
            }
        }
        for part in parts { take(from: part.0, upTo: part.1, weight: part.2) }
        // Short of songs in some part: top up from favourites and plays, then from anything.
        take(from: favourites + heavy, upTo: count - chosen.count, weight: { 1 + log(1 + Double($0.playCount)) })
        take(from: pool, upTo: count - chosen.count, weight: { _ in 1 })
        // A small library with few artists: then more than three of one artist rather than a short mix.
        take(from: pool, upTo: count - chosen.count, capped: false, weight: { _ in 1 })

        chosen.shuffle(using: &random)
        return spread(chosen).map(\.id)
    }

    /// Reorders so the same artist never plays twice in a row, where the songs allow it.
    static func spread(_ songs: [MixCandidate]) -> [MixCandidate] {
        var rest = songs
        var result: [MixCandidate] = []
        while !rest.isEmpty {
            let index = rest.firstIndex { $0.artist != result.last?.artist } ?? 0
            result.append(rest.remove(at: index))
        }
        return result
    }
}

/// A small fixed random generator: the same seed gives the same numbers on every device.
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
