import Foundation

/// The two-way likes plan of the Android app (spec section 3). Pure, so the rules can be checked on their own.
///
/// A first sync (empty base) only adds on both sides. A server unstar removes a local like only for songs both sides
/// had agreed on before. A local unlike reaches the server only as a pending event, never because a like is missing.
public enum FavoritesMerge {
    public struct Plan: Equatable, Sendable {
        public var toStar: Set<String>
        public var toLike: Set<String>
        public var toUnlike: Set<String>
        public var removed: Set<String>
        public var serverLost: Bool
    }

    /// - liked: liked local song id to its server id, for liked songs that have a match.
    /// - base: server ids both sides agreed were liked after the last sync.
    /// - starred: server ids starred now.
    /// - likeTargets: for each star, the local song ids it lights up.
    public static func plan(liked: [String: String], base: Set<String>, starred: Set<String>, likeTargets: [String: Set<String>]) -> Plan {
        let likedServer = Set(liked.values)
        let gone = likedServer.intersection(base).subtracting(starred)
        // Many stars gone at once means a moved library or a new database, not a wish: then nothing is removed.
        let serverLost = gone.count >= 20 && 2 * gone.count > base.count
        let removed = serverLost ? Set<String>() : gone
        let toStar = likedServer.subtracting(starred).subtracting(removed)
        var toLike = Set<String>()
        for star in starred { toLike.formUnion(likeTargets[star] ?? []) }
        toLike.subtract(liked.keys)
        let toUnlike = Set(liked.filter { removed.contains($0.value) }.keys)
        return Plan(toStar: toStar, toLike: toLike, toUnlike: toUnlike, removed: removed, serverLost: serverLost)
    }

    /// The new agreed set: what is liked here or lit up by a star, and starred on the server now.
    public static func newBase(likedServerIDs: Set<String>, starsWithTargets: Set<String>, starredNow: Set<String>) -> Set<String> {
        likedServerIDs.union(starsWithTargets).intersection(starredNow)
    }
}

/// When a listen counts as a play for the server (spec section 4).
public enum ListenRule {
    /// Recorded at all from 5 seconds; counted for the server at half the song or 4 minutes, or 30 seconds when the length is unknown.
    public static func counts(listenedMs: Int, durationMs: Int) -> Bool {
        guard listenedMs >= 5_000 else { return false }
        if durationMs > 0 { return listenedMs >= min(durationMs / 2, 240_000) }
        return listenedMs >= 30_000
    }
}
