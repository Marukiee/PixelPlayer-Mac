import Foundation
@testable import PixelPlayerKit

/// Your Mix: the same every time for a day, different the next, artists spread, recently played left out.
func mixChecks() {
    let now = 1_800_000_000.0
    var songs: [MixCandidate] = []
    for artist in 0..<12 {
        for n in 0..<10 {
            let i = artist * 10 + n
            songs.append(MixCandidate(id: "s\(i)", artist: "Artist \(artist)", liked: i % 4 == 0, playCount: (i * 7) % 13,
                                      lastPlayed: i % 9 == 0 ? now - 3600 : now - Double(i) * 86_400, added: now - Double(i % 40) * 86_400))
        }
    }
    let a = DailyMix.pick(songs, day: 1000, now: now)
    let b = DailyMix.pick(songs, day: 1000, now: now)
    let c = DailyMix.pick(songs, day: 1001, now: now)
    check(a == b, "the mix is the same all day")
    check(a != c, "the next day has another mix")
    check(a.count == 25 && Set(a).count == 25, "the mix has 25 different songs")
    let byID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
    let artists = a.compactMap { byID[$0]?.artist }
    check(Dictionary(grouping: artists, by: { $0 }).values.allSatisfy { $0.count <= 3 }, "at most three songs per artist")
    check(zip(artists, artists.dropFirst()).allSatisfy { $0 != $1 }, "never the same artist twice in a row")
    check(a.compactMap { byID[$0] }.allSatisfy { ($0.lastPlayed ?? 0) < now - 2 * 86_400 }, "songs played in the last two days stay out")
    check(a.compactMap { byID[$0] }.contains(where: \.liked), "liked songs are in it")
    check(DailyMix.pick([], day: 1, now: now).isEmpty, "an empty library gives an empty mix")
    let few = Array(songs.prefix(6))
    check(DailyMix.pick(few, day: 1, now: now).count == 6, "a small library gives what it has")
}
