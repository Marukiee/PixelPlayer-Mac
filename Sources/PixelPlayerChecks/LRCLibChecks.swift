import Foundation
@testable import PixelPlayerKit

/// Lyrics from LRCLIB as Android picks them: same title and artist, a length that fits, synced first.
func lrclibChecks() {
    check(LRCLib.clean("Hjälp! (Live) [2024 Remaster]") == "Hjälp!", "brackets go from a title")
    check(LRCLib.key("Hjälp!") == LRCLib.key("hjälp"), "names compare without case and punctuation")
    check(LRCLib.key("Hjälp") != LRCLib.key("Hjalp"), "accents count")
    check(LRCLib.tolerance(212, synced: true) == 5, "synced: at least 5 s")
    check(LRCLib.tolerance(500, synced: true) == 8, "synced: at most 8 s")
    check(LRCLib.tolerance(300, synced: false) == 12, "plain: 4% of the length")

    let lines = "[00:15.35] Jag ångrar mycket, ja, jag ångrar fan nästan allt\n[00:19.08] Att den jag var och den jag är, den tog mig ingenstans"
    let entries = [
        LRCLib.Entry(id: 1, trackName: "Hjälp!", artistName: "Thomas Stenström", duration: 240, syncedLyrics: lines),
        LRCLib.Entry(id: 2, trackName: "Hjälp!", artistName: "Thomas Stenström", duration: 213, plainLyrics: "Jag ångrar mycket"),
        LRCLib.Entry(id: 3, trackName: "Hjälp!", artistName: "Thomas Stenström", duration: 212, syncedLyrics: lines),
        LRCLib.Entry(id: 4, trackName: "Hjälp! (Akustisk)", artistName: "Thomas Stenström", duration: 212, syncedLyrics: lines),
        LRCLib.Entry(id: 5, trackName: "Hjälp!", artistName: "Someone Else", duration: 212, syncedLyrics: lines),
        LRCLib.Entry(id: 6, trackName: "Hjälp!", artistName: "Thomas Stenström", duration: 212, instrumental: true),
    ]
    check(LRCLib.best(entries, title: "Hjälp!", artist: "Thomas Stenström", seconds: 212)?.id == 3, "the synced entry of the same length wins")
    check(LRCLib.best(Array(entries.prefix(2)), title: "Hjälp!", artist: "Thomas Stenström", seconds: 212)?.id == 2,
          "a synced entry of another length is passed over, plain of the right length used")
    check(LRCLib.best(entries, title: "Hjälp!", artist: "Thomas Stenström, Veronica Maggio", seconds: 212)?.id == 3, "the first of several artists is enough")
    check(LRCLib.best(entries, title: "Hjälp", artist: "Nobody", seconds: 212) == nil, "another artist is not used")

    if let entry = LRCLib.best(entries, title: "Hjälp!", artist: "Thomas Stenström", seconds: 212), let lyrics = Lyrics(lrclib: entry) {
        check(lyrics.index(at: 18.9) == 0 && lyrics.index(at: 19.1) == 1, "the second half of the sentence starts at 0:19.08")
    } else { check(false, "LRCLIB lines parse") }

    // With PP_LRCLIB=1 the real LRCLIB is asked for that song (only reads).
    if ProcessInfo.processInfo.environment["PP_LRCLIB"] == "1" {
        let done = DispatchSemaphore(value: 0)
        Task {
            let entry = await LRCLib.lookup(title: "Hjälp!", artist: "Thomas Stenström", seconds: 212)
            print("lrclib: \(entry.map { "\($0.id) \($0.trackName ?? "") \($0.duration ?? 0) s" } ?? "nothing")")
            check(entry?.synced == true, "LRCLIB has synced lyrics for Hjälp!")
            done.signal()
        }
        done.wait()
    }
}
