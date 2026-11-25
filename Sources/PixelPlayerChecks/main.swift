import Foundation
@testable import PixelPlayerKit

// Plain checks of the kit, run with `swift run PixelPlayerChecks`. With PP_STUB=http://127.0.0.1:<port> set,
// the Subsonic checks also run against the fake Navidrome from the Android repo (tools/sonos-test/navidrome_stub.py).

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    if condition() { passes += 1 } else { failures += 1; print("FAIL \(name) (\(file):\(line))") }
}

// MARK: Subsonic

// The example from the Subsonic API documentation.
check(SubsonicClient.token(password: "sesame", salt: "c19b2d") == "26719a1196d2a940705a59634eb18eab", "token matches the API example")

let okAlbums = """
{"subsonic-response":{"status":"ok","version":"1.16.1","albumList2":{"album":[{"id":"al-1","name":"Blue Hour Sessions","artist":"Odile Brandt Trio","songCount":4,"year":2023}]}}}
"""
struct AlbumList: Decodable { var album: [SubsonicAlbum]? }
if let list = try? SubsonicClient.decode(Data(okAlbums.utf8), key: "albumList2", as: AlbumList.self) {
    check(list.album?.first?.name == "Blue Hour Sessions", "album list decodes")
    check(list.album?.first?.year == 2023, "album year decodes")
} else { check(false, "album list decodes") }

let failed = """
{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}
"""
do {
    _ = try SubsonicClient.decode(Data(failed.utf8), key: "albumList2", as: AlbumList.self)
    check(false, "a failed answer throws")
} catch let error as SubsonicError {
    check(error == .server(code: 40, message: "Wrong username or password"), "a failed answer carries the server message")
} catch { check(false, "a failed answer throws a SubsonicError") }

let config = SubsonicConfig(server: URL(string: "http://music.local:4533")!, user: "listener", password: "secret")
let streamURL = SubsonicClient(config: config).streamURL(id: "so-1").absoluteString
check(streamURL.hasPrefix("http://music.local:4533/rest/stream?"), "stream URL points at the server")
check(streamURL.contains("id=so-1") && streamURL.contains("u=listener") && !streamURL.contains("secret"), "stream URL has the id and no password")

// MARK: Against the fake Navidrome

if let stub = ProcessInfo.processInfo.environment["PP_STUB"], let server = URL(string: stub) {
    let user = ProcessInfo.processInfo.environment["PP_STUB_USER"] ?? "test"
    let password = ProcessInfo.processInfo.environment["PP_STUB_PASSWORD"] ?? "test"
    let client = SubsonicClient(config: SubsonicConfig(server: server, user: user, password: password))
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            try await client.ping()
            passes += 1
            let songs = try await client.search("", songCount: 500)
            print("stub: \(songs.song?.count ?? 0) songs")
            check((songs.song?.count ?? 0) > 0, "the stub returns songs for an empty search")
            let albums = try await client.albums()
            print("stub: \(albums.count) albums")
            let playlists = try await client.playlists()
            print("stub: \(playlists.count) playlists")
        } catch {
            check(false, "stub: \(error)")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

matchingChecks()
if ProcessInfo.processInfo.environment["PP_FAKE_SONOS"] != nil {
    let done = DispatchSemaphore(value: 0)
    Task { await sonosChecks(); done.signal() }
    done.wait()
}

print(failures == 0 ? "all \(passes) checks passed" : "\(failures) failed, \(passes) passed")
exit(failures == 0 ? 0 : 1)
