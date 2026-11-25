import Foundation
@testable import PixelPlayerKit

/// The remote player protocol (spec section 6): path tails, line framing and the messages the Mac sends and reads.
func remoteChecks() {
    check(RemoteProtocol.pathTail("/Users/me/Music/Glass Coast/Harbour Nights/01 Neon Pier.flac") == "Glass Coast/Harbour Nights/01 Neon Pier.flac",
          "path tail keeps the last three parts")
    check(RemoteProtocol.pathTail("C:\\Music\\Artist\\Album\\song.mp3") == "Artist/Album/song.mp3", "path tail turns backslashes into slashes")
    check(RemoteProtocol.pathTail("Album//song.mp3") == "Album/song.mp3", "path tail drops empty parts")
    check(RemoteProtocol.pathTail("https://server/rest/stream?id=1") == "", "path tail is empty for a URL")
    check(RemoteProtocol.pathTail("   ") == "", "path tail is empty for a blank path")
    check(RemoteProtocol.pathTail(nil) == "" && RemoteProtocol.pathTail("") == "", "path tail is empty without a path")

    let buffer = LineBuffer()
    check(buffer.append(Data("{\"t\":\"sta".utf8)).isEmpty, "half a line waits")
    check(buffer.append(Data("te\"}\n\n{\"t\":\"bye\"}\n".utf8)) == ["{\"t\":\"state\"}", "{\"t\":\"bye\"}"], "lines split across chunks come out whole, blank lines skipped")
    let big = Data(repeating: 0x61, count: 4 * 1024 * 1024 + 10) + Data("\n{\"t\":\"ping\"}\n".utf8)
    check(LineBuffer().append(big) == ["{\"t\":\"ping\"}"], "a line over 4 MiB is dropped")

    let state = RemoteMessage.parse("{\"t\":\"state\",\"qid\":1795604735776,\"id\":\"so3\",\"foreign\":false,\"pos\":5178,\"dur\":214000,\"play\":true,\"playing\":true,\"vol\":50,\"steps\":15}")
    check(state == .state(RemoteState(qid: 1795604735776, id: "so3", foreign: false, positionMs: 5178, durationMs: 214000, playWhenReady: true, playing: true, volume: 50)),
          "a state is read")
    if case .state(let s) = RemoteMessage.parse("{\"t\":\"state\",\"qid\":2,\"id\":null}") { check(s.id == nil, "a state with id null has no id") } else { check(false, "a state with id null is read") }
    check(RemoteMessage.parse("{\"t\":\"queued\",\"qid\":2,\"missing\":[\"a\"],\"found\":3}") == .queued(qid: 2, missing: ["a"], found: 3), "queued is read")
    check(RemoteMessage.parse("not json") == nil && RemoteMessage.parse("{\"x\":1}") == nil, "unreadable lines are ignored")

    let queue = RemoteMessage.queue(qid: 7, items: [RemoteTrack(id: "local:A/B/c.flac", path: "A/B/c.flac", title: "C", artist: "A", album: "B", durationMs: 1000)],
                                    index: 0, positionMs: 1500, play: true, repeatMode: 2)
    check(queue.last == 0x0A, "messages end with a newline")
    if let json = try? JSONSerialization.jsonObject(with: queue.dropLast()) as? [String: Any], let items = json["items"] as? [[String: Any]] {
        check(json["t"] as? String == "queue" && json["qid"] as? Int == 7 && json["pos"] as? Int == 1500 && json["repeat"] as? Int == 2, "queue fields")
        check(items.first?["p"] as? String == "A/B/c.flac" && items.first?["d"] as? Int == 1000, "queue items carry tail and duration")
    } else { check(false, "queue is JSON") }
    check(RemoteMessage.volume(130).contains(Data("\"v\":100".utf8)), "volume is capped at 100")
}
