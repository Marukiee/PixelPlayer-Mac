import Foundation
@testable import PixelPlayerKit

/// Checks of what the local library needs without a window: lyrics, cover pictures beside the music, sorting and the scan cache.
func libraryChecks() {
    // MARK: LRC

    let lrc = LRC.parse("""
    [ar:Mando Diao]
    [ti:Dance With Somebody]
    [offset:+500]
    [00:10.00]First line
    [00:05.5][00:20.123]Twice <00:05.80>with <00:06.10>words
    [01:02:50]Colon hundredths

    [01:30.00]
    """)
    check(lrc.isSynced, "LRC with times is synced")
    check(lrc.lines.map(\.text) == ["Twice with words", "First line", "Twice with words", "Colon hundredths", ""],
          "LRC lines come in time order, a line with two times twice, tags and word marks gone")
    check(lrc.lines.first?.time == 5.0, "LRC offset +500 makes lines half a second sooner")
    check(abs((lrc.lines[2].time ?? 0) - 19.623) < 0.0001, "three fraction digits are milliseconds")
    check(abs((lrc.lines[3].time ?? 0) - 62.0) < 0.0001, "mm:ss:xx reads the last part as hundredths")
    check(lrc.index(at: 0) == nil, "no line before the first one starts")
    check(lrc.index(at: 9.6) == 1 && lrc.index(at: 19.7) == 2, "the current line is the last one that started")
    check(lrc.index(at: 500) == 4, "after the last line the last line stays current")

    let plain = LRC.parse("\n\nVerse one\nstill one\n\n\n\nVerse two\n\n")
    check(!plain.isSynced && plain.lines.map(\.text) == ["Verse one", "still one", "", "Verse two"], "plain text keeps one blank line between verses")
    check(plain.index(at: 30) == nil, "plain lyrics have no current line")
    check(LRC.parse("[00:12]No fraction").lines.first?.time == 12, "mm:ss without a fraction")
    check(LRC.parse("[Chorus]\nla la").lines.map(\.text) == ["[Chorus]", "la la"], "a bracket that is not a time stays text")
    check(LRC.parse("[ar:Someone]\n[length: 03:20]\n").isEmpty, "only information tags is no lyrics")
    check(LRC.parse("\u{FEFF}[00:01.00]Byte order mark").lines.first?.text == "Byte order mark", "a byte order mark is ignored")

    check(LocalLyrics.sidecar(for: "01 Song.flac", in: ["01 Song.FLAC", "cover.jpg", "01 song.LRC", "02 Other.lrc"]) == "01 song.LRC",
          "the .lrc beside a file is found whatever its case")
    check(LocalLyrics.sidecar(for: "01 Song.flac", in: ["01 Song 2.lrc"]) == nil, "another song's .lrc is not used")

    // MARK: Server lyrics

    let structured = """
    {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,"lyricsList":{"structuredLyrics":[
      {"displayArtist":"A","displayTitle":"T","lang":"xxx","synced":false,"line":[{"value":"Plain one"},{"value":"Plain two"}]},
      {"displayArtist":"A","displayTitle":"T","lang":"eng","offset":-100,"synced":true,"line":[{"start":0,"value":"Hello"},{"start":2500,"value":"World"}]}
    ]}}}
    """
    if let list = try? SubsonicClient.decode(Data(structured.utf8), key: "lyricsList", as: SubsonicClient.LyricsList.self),
       let lyrics = Lyrics(structured: list.structuredLyrics ?? []) {
        check(lyrics.isSynced && lyrics.lines.map(\.text) == ["Hello", "World"], "server lyrics prefer the synced set")
        check(lyrics.lines.map(\.time) == [0.1, 2.6], "server line starts are milliseconds, a negative offset makes them later")
    } else { check(false, "structured lyrics decode") }
    let unsynced = [SubsonicStructuredLyrics(displayArtist: nil, displayTitle: nil, lang: nil, offset: nil, synced: false,
                                             line: [.init(start: nil, value: "Only words")])]
    check(Lyrics(structured: unsynced)?.isSynced == false, "plain server lyrics have no times")
    check(Lyrics(structured: []) == nil, "no server lyrics is nil")
    let old = """
    {"subsonic-response":{"status":"ok","version":"1.16.1","lyrics":{"artist":"A","title":"T","value":"Line one\\nLine two"}}}
    """
    let oldLyrics = try? SubsonicClient.decode(Data(old.utf8), key: "lyrics", as: SubsonicLyrics.self)
    check(oldLyrics?.value.map { LRC.parse($0).lines.map(\.text) } == ["Line one", "Line two"], "getLyrics text becomes plain lyrics")
    let none = """
    {"subsonic-response":{"status":"ok","version":"1.16.1","lyrics":{}}}
    """
    check((try? SubsonicClient.decode(Data(none.utf8), key: "lyrics", as: SubsonicLyrics.self))?.value == nil, "getLyrics without lyrics has no text")

    // MARK: Cover pictures beside the music

    check(LocalScanner.bestFolderArt(["01 Song.flac", "back.jpg", "Folder.JPG", "cover.png"]) == "cover.png", "cover beats folder")
    check(LocalScanner.bestFolderArt(["Folder.JPG", "AlbumArtSmall.jpg"]) == "Folder.JPG", "folder beats the small album art")
    check(LocalScanner.bestFolderArt(["00-flemming-twee_stappen_voor-nl-24bit-web-flac-2024-cover.jpg", "spectrogram.png"])
          == "00-flemming-twee_stappen_voor-nl-24bit-web-flac-2024-cover.jpg", "a scene name ending in cover is a cover")
    check(LocalScanner.bestFolderArt(["back.jpg", "spectrogram.png", "Back Cover.jpg", "cd.png", "notes.txt", "cover.txt"]) == nil,
          "backs, discs, spectrograms and text are never the cover")
    check(LocalScanner.bestFolderArt(["Front.jpeg"]) == "Front.jpeg" && LocalScanner.bestFolderArt(["AlbumArt_{1234}_Large.jpg"]) != nil,
          "front and Windows album art are covers")
    check(LocalScanner.isDiscFolder("CD1") && LocalScanner.isDiscFolder("Disc 2") && !LocalScanner.isDiscFolder("Discography")
          && !LocalScanner.isDiscFolder("CD"), "disc folders are CD or Disc with a number")

    // MARK: Sorting

    struct Row { let title: String, artist: String, album: String, track: Int?, added: Double? }
    let rows = [
        Row(title: "track 10", artist: "beta", album: "B", track: 2, added: 100),
        Row(title: "Track 2", artist: "Alpha", album: "B", track: 10, added: nil),
        Row(title: "apple", artist: "", album: "A", track: 1, added: 300),
        Row(title: "Banana", artist: "alpha", album: "A", track: nil, added: 200),
    ]
    func order(_ order: TrackOrder) -> [String] {
        order.sorted(rows) { TrackOrder.Fields(title: $0.title, artist: $0.artist, album: $0.album, track: $0.track, added: $0.added) }.map(\.title)
    }
    check(order(.custom) == ["track 10", "Track 2", "apple", "Banana"], "custom order keeps the list as it is")
    check(order(.title) == ["apple", "Banana", "Track 2", "track 10"], "title order ignores case and reads numbers by value")
    check(order(.artist) == ["Banana", "Track 2", "track 10", "apple"], "artist order goes by album, then track; no artist last")
    check(order(.album) == ["apple", "Banana", "track 10", "Track 2"], "album order goes by track, unknown track last")
    check(order(.added) == ["apple", "Banana", "track 10", "Track 2"], "recently added is newest first, unknown dates last")

    // MARK: Scan cache

    let track = LocalTrack(path: "/m/a.flac", relativePath: "a.flac", title: "A", artist: "B", album: "C", albumArtist: nil, genre: "Rock",
                           year: 2009, track: 2, durationMs: 1000, modified: 1, size: 2, suffix: "flac")
    check(LocalScanner.decodeCache(LocalScanner.encodeCache([track]) ?? Data()) == [track], "the scan cache reads back what it wrote")
    let oldCache = (try? JSONEncoder().encode([track])) ?? Data()
    check(LocalScanner.decodeCache(oldCache).isEmpty, "a cache from the scanner before Vorbis tags is read again")
}
