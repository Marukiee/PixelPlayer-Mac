import Foundation
import PixelPlayerKit

/// Where sync state is kept. A scripted run gets a throwaway store, so test likes and listens never mix with real ones.
@MainActor
enum Store {
    static let defaults: UserDefaults = {
        guard Debug.active else { return .standard }
        let name = "nl.markmaaktmedia.PixelPlayer.run-\(ProcessInfo.processInfo.processIdentifier)"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }()
}

/// The stored state of the likes sync: kept per server and user, wiped when that changes.
private struct FavoritesState: Codable {
    var account = ""
    var base: Set<String> = []
    /// Song id to true (like) or false (unlike). One entry per song; the newest wins.
    var pending: [String: Bool] = [:]
    /// The likes on this Mac, by song id, including songs the server does not have.
    var liked: Set<String> = []
}

/// Likes in two directions with Navidrome, by the Android rules (spec section 3). The server is changed only by a like or
/// an unlike made here, or by bringing over stars the Mac did not know; nothing is ever removed because it is missing.
@MainActor
final class FavoritesSync {
    static let shared = FavoritesSync()
    private var state = FavoritesState()
    private var pushTask: Task<Void, Never>?
    private let key = "favorites.state"
    private var library: Library { .shared }

    private init() {
        if let data = Store.defaults.data(forKey: key), let saved = try? JSONDecoder().decode(FavoritesState.self, from: data) { state = saved }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { Store.defaults.set(data, forKey: key) }
    }

    /// The likes stored on this Mac, for a library that has just been built.
    var storedLikes: Set<String> { state.liked }

    /// A different server or user starts from nothing, so likes of one account never reach another.
    func use(account: String) {
        guard state.account != account else { return }
        state = FavoritesState(account: account)
        save()
        ScrobbleQueue.shared.clear()
    }

    /// A like or unlike made here: stored first, then pushed a second later (a burst becomes one push).
    func localChange(songID: String, liked: Bool) {
        if liked { state.liked.insert(songID) } else { state.liked.remove(songID) }
        state.pending[songID] = liked
        save()
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            _ = await flushPending()
        }
    }

    private func key(for song: Song) -> TrackKey {
        TrackKey(id: song.id, title: song.title, artist: song.artist, album: song.album.title, durationMs: song.seconds * 1000,
                 serverID: song.isLocal ? nil : song.source.serverID)
    }

    private func serverID(for song: Song, index: FavoriteIndex) -> String? {
        song.source.serverID ?? index.serverID(for: key(for: song))
    }

    /// Sends what is waiting. False when the network failed; what is left stays for the next run.
    @discardableResult
    func flushPending() async -> Bool {
        guard let client = library.client, !library.isSample else { return true }
        let index = FavoriteIndex(server: library.serverKeys)
        // Unlikes first, so their star is not read back as a like.
        for (songID, liked) in state.pending.sorted(by: { !$0.value && $1.value }) {
            guard let song = library.song(id: songID) ?? library.hiddenServerSong(id: songID) else { state.pending[songID] = nil; continue }
            do {
                if liked {
                    var id = serverID(for: song, index: index)
                    if id == nil {
                        let found = try await client.search(song.title, songCount: 50).song ?? []
                        id = FavoriteIndex(server: found.map(Library.key(for:))).serverID(for: key(for: song))
                    }
                    if let id {
                        try await client.star(songIDs: [id])
                        state.base.insert(id)
                    }
                } else {
                    let starred = try await client.starred().song ?? []
                    var ids = Set(starred.filter { FavoriteIndex.locals(for: Library.key(for: $0), in: library.songKeys).contains(songID) }.map(\.id))
                    if let own = serverID(for: song, index: index) { ids.insert(own) }
                    try await client.unstar(songIDs: Array(ids))
                    state.base.subtract(ids)
                    // The file copy and the server copy go out together, or the leftover heart would star it again.
                    for other in library.songs where other.source.serverID.map(ids.contains) == true { state.liked.remove(other.id) }
                }
                if state.pending[songID] == liked { state.pending[songID] = nil }
            } catch SubsonicError.server {
                // A refusal by the server counts as done.
                if state.pending[songID] == liked { state.pending[songID] = nil }
            } catch {
                save()
                library.likedIDs = state.liked
                return false
            }
        }
        save()
        library.likedIDs = state.liked
        return true
    }

    /// The full two-way sync: pending first, then bring the stars and the likes together.
    func sync() async {
        guard let client = library.client, !library.isSample else { return }
        guard await flushPending() else { return }
        guard let starredSongs = try? await client.starred().song else { return }
        let starred = Set(starredSongs.map(\.id))
        let index = FavoriteIndex(server: library.serverKeys + starredSongs.map(Library.key(for:)))
        var liked: [String: String] = [:]
        for id in state.liked {
            guard let song = library.song(id: id), let server = serverID(for: song, index: index) else { continue }
            liked[id] = server
        }
        var targets: [String: Set<String>] = [:]
        for star in starredSongs { targets[star.id] = FavoriteIndex.locals(for: Library.key(for: star), in: library.songKeys) }
        let plan = FavoritesMerge.plan(liked: liked, base: state.base, starred: starred, likeTargets: targets)
        for id in plan.toStar {
            do { try await client.star(songIDs: [id]) } catch SubsonicError.server { continue } catch { break }
        }
        state.liked.formUnion(plan.toLike)
        state.liked.subtract(plan.toUnlike)
        let starredNow = starred.union(plan.toStar)
        state.base = FavoritesMerge.newBase(likedServerIDs: Set(liked.values), starsWithTargets: Set(targets.filter { !$0.value.isEmpty }.keys),
                                            starredNow: starredNow)
        save()
        library.likedIDs = state.liked
    }
}

/// Listens waiting to be counted on the server (spec section 4): saved before sending, oldest first, at most 5000.
@MainActor
final class ScrobbleQueue {
    static let shared = ScrobbleQueue()
    private let key = "scrobbles.pending"
    private var pending: [String]
    private var sending = false

    private init() {
        pending = Store.defaults.stringArray(forKey: key) ?? []
    }

    private func save() { Store.defaults.set(pending, forKey: key) }

    /// Listens of another account never go to this one.
    func clear() {
        pending = []
        save()
    }

    /// A listen that ended: counted when it was long enough, then sent five seconds later.
    func record(song: Song, listenedMs: Int, endedAt: Date = .now) {
        guard ListenRule.counts(listenedMs: listenedMs, durationMs: song.seconds * 1000), !song.id.isEmpty else { return }
        let started = max(0, Int(endedAt.timeIntervalSince1970 * 1000) - listenedMs)
        pending.append("\(started):\(song.id)")
        if pending.count > 5000 { pending.removeFirst(pending.count - 5000) }
        save()
        Task {
            try? await Task.sleep(for: .seconds(5))
            await send()
        }
    }

    func send() async {
        guard !sending, let client = Library.shared.client, !Library.shared.isSample else { return }
        sending = true
        defer { sending = false }
        while let entry = pending.first {
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let started = Int(parts[0]) else { pending.removeFirst(); continue }
            let song = Library.shared.song(id: parts[1]) ?? Library.shared.hiddenServerSong(id: parts[1])
            guard let serverID = song?.source.serverID else {
                // Not on the server yet: kept for 14 days, time for the server to scan a new file.
                if Date.now.timeIntervalSince1970 * 1000 - Double(started) > 14 * 86_400_000 { pending.removeFirst(); save(); continue }
                break
            }
            do {
                try await client.scrobble(id: serverID, time: Date(timeIntervalSince1970: Double(started) / 1000), submission: true)
                pending.removeFirst()
                save()
            } catch SubsonicError.server(let code, _) where (40...59).contains(code) {
                break
            } catch SubsonicError.server {
                pending.removeFirst()
                save()
            } catch {
                break
            }
        }
    }
}
