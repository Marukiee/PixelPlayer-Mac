import Foundation
@testable import PixelPlayerKit

/// Checks of matching local files to server songs, of the favorites plan and of the listen rule.
func matchingChecks() {
    check(TextMatch.fold("Björk – It’s Oh So Quiet!") == "bjork its oh so quiet", "fold drops accents, apostrophes and signs")
    check(TextMatch.loose("Blue Hour (Live) [2023] feat. Someone") == "blue hour", "loose drops brackets and feat")
    check(TextMatch.contains("odile brandt", "odile brandt trio"), "an artist inside another matches")
    check(!TextMatch.contains("", "odile"), "an empty artist never matches")

    let local = TrackKey(id: "local:Odile/Blue Hour.flac", title: "Blue Hour", artist: "Odile Brandt Trio", album: "Blue Hour Sessions", durationMs: 288_000)
    let server = TrackKey(id: "so7", title: "Blue Hour", artist: "Odile Brandt", album: "Blue Hour Sessions", durationMs: 289_500, serverID: "so7")
    let other = TrackKey(id: "so8", title: "Blue Hour", artist: "Someone Else", album: "Other", durationMs: 288_000, serverID: "so8")
    check(LocalFirst.hiddenServerIDs(locals: [local], server: [server, other]) == ["so7"], "the server copy hides behind the local file")
    let farOff = TrackKey(id: "so9", title: "Blue Hour", artist: "Odile Brandt", album: "x", durationMs: 300_000, serverID: "so9")
    check(LocalFirst.hiddenServerIDs(locals: [local], server: [farOff]).isEmpty, "more than 3 seconds apart is another recording")
    let index = FavoriteIndex(server: [server, other])
    check(index.serverID(for: local) == "so7", "a local song finds its server id")
    check(FavoriteIndex.locals(for: server, in: [local]) == [local.id], "a star lights up the local copy")

    // A first sync: the server has stars, the Mac has none yet. Only additions, never a removal.
    let starred: Set<String> = ["so1", "so2", "so3"]
    let first = FavoritesMerge.plan(liked: [:], base: [], starred: starred, likeTargets: ["so1": ["l1"], "so2": ["l2"], "so3": []])
    check(first.toStar.isEmpty && first.toUnlike.isEmpty && first.removed.isEmpty, "a first sync never removes anything")
    check(first.toLike == ["l1", "l2"], "a first sync brings the stars over")
    // A like on the Mac that the server does not have yet is starred, not undone.
    let second = FavoritesMerge.plan(liked: ["l9": "so9"], base: [], starred: starred, likeTargets: [:])
    check(second.toStar == ["so9"] && second.toUnlike.isEmpty, "a new local like is starred")
    // An agreed like unstarred on the server is unliked here.
    let third = FavoritesMerge.plan(liked: ["l1": "so1", "l2": "so2"], base: ["so1", "so2"], starred: ["so2"], likeTargets: ["so2": ["l2"]])
    check(third.toUnlike == ["l1"] && third.toStar.isEmpty, "a server unstar of an agreed like removes it here")
    // Many stars gone at once: the library moved, nothing is removed.
    let base = Set((1...30).map { "s\($0)" })
    let liked = Dictionary(uniqueKeysWithValues: (1...30).map { ("l\($0)", "s\($0)") })
    let lost = FavoritesMerge.plan(liked: liked, base: base, starred: ["s1"], likeTargets: [:])
    check(lost.serverLost && lost.toUnlike.isEmpty, "a vanished server library removes nothing")

    check(!ListenRule.counts(listenedMs: 4_000, durationMs: 200_000), "under 5 seconds never counts")
    check(ListenRule.counts(listenedMs: 100_000, durationMs: 200_000), "half a song counts")
    check(ListenRule.counts(listenedMs: 240_000, durationMs: 900_000), "4 minutes of a long song counts")
    check(!ListenRule.counts(listenedMs: 20_000, durationMs: 0), "without a length, 30 seconds are needed")
}
