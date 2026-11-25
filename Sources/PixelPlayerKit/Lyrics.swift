import Foundation
import AVFoundation

/// The words of a song: lines with the moment they are sung (synced), or plain lines without times.
public struct Lyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// Seconds into the song, nil for plain lyrics.
        public var time: Double?
        public var text: String

        public init(time: Double? = nil, text: String) {
            self.time = time
            self.text = text
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    public var isSynced: Bool { lines.contains { $0.time != nil } }
    public var isEmpty: Bool { !lines.contains { !$0.text.isEmpty } }

    /// The line sung at a moment: the last one that has started. Nil before the first line and for plain lyrics.
    public func index(at seconds: Double) -> Int? {
        var found: Int?
        for (i, line) in lines.enumerated() {
            guard let time = line.time else { continue }
            if time <= seconds { found = i } else { break }
        }
        return found
    }
}

/// LRC, the text format of synced lyrics: `[01:20.77]Break your happy home`. Also reads plain text, which becomes plain lyrics.
public enum LRC {
    public static func parse(_ text: String) -> Lyrics {
        var timed: [(order: Int, line: Lyrics.Line)] = []
        var plain: [Lyrics.Line] = []
        var offset = 0.0
        let rows = text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines)
        for row in rows {
            var rest = Substring(row.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            var tagOnly = false
            // Leading tags: one or more times, or one information tag such as [ar:Artist] or [offset:+200].
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = time(tag) {
                    times.append(time)
                } else if times.isEmpty, let colon = tag.firstIndex(of: ":"), tag[..<colon].allSatisfy({ $0.isLetter || $0 == "#" }) {
                    if tag[..<colon].lowercased() == "offset" {
                        offset = (Double(tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces)) ?? 0) / 1000
                    }
                    tagOnly = true
                    break
                } else {
                    break
                }
                rest = rest[rest.index(after: close)...]
            }
            if tagOnly { continue }
            let words = stripWordTimes(String(rest)).trimmingCharacters(in: .whitespaces)
            if times.isEmpty {
                plain.append(Lyrics.Line(text: words))
            } else {
                for time in times { timed.append((timed.count, Lyrics.Line(time: time, text: words))) }
            }
        }
        if !timed.isEmpty {
            // A positive offset makes the lines come sooner.
            let lines = timed.sorted { $0.line.time! != $1.line.time! ? $0.line.time! < $1.line.time! : $0.order < $1.order }
                .map { Lyrics.Line(time: max(0, $0.line.time! - offset), text: $0.line.text) }
            return Lyrics(lines: lines)
        }
        // Plain text: no blank lines at the ends, and never two in a row.
        var lines: [Lyrics.Line] = []
        for line in plain where !(line.text.isEmpty && (lines.last?.text.isEmpty ?? true)) { lines.append(line) }
        while lines.last?.text.isEmpty == true { lines.removeLast() }
        return Lyrics(lines: lines)
    }

    /// `mm:ss`, `mm:ss.xx`, `mm:ss.xxx`, `mm:ss:xx` or `h:mm:ss.xx` in seconds.
    static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber || $0 == "." } }) else { return nil }
        func seconds(_ text: String) -> Double? { Double(text.hasPrefix(".") ? "0" + text : text) }
        if parts.count == 2 {
            guard let minutes = Double(parts[0]), let secs = seconds(parts[1]) else { return nil }
            return minutes * 60 + secs
        }
        // Three parts: minutes, seconds and hundredths (mm:ss:xx), or hours, minutes and seconds.
        if !parts[2].contains("."), parts[2].count == 2, let minutes = Double(parts[0]), let secs = Double(parts[1]), let hundredths = Double(parts[2]),
           !parts[1].contains(".") {
            return minutes * 60 + secs + hundredths / 100
        }
        guard let hours = Double(parts[0]), let minutes = Double(parts[1]), let secs = seconds(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + secs
    }

    /// Enhanced LRC marks every word: `<00:12.10>Break <00:12.60>your`. The words stay, the marks go.
    static func stripWordTimes(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: ">"), time(rest[rest.index(after: open)..<close]) != nil else {
                result.append("<")
                rest = rest[rest.index(after: open)...]
                continue
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result.replacingOccurrences(of: "  ", with: " ")
    }
}

/// Lyrics for a file on this Mac: a .lrc file beside it, otherwise the lyrics inside the file. Only reads.
public enum LocalLyrics {
    /// The .lrc file for an audio file among the names in its folder: the same name with .lrc, any case.
    public static func sidecar(for audioName: String, in names: [String]) -> String? {
        let stem = (audioName as NSString).deletingPathExtension.lowercased()
        return names.first { ($0 as NSString).pathExtension.lowercased() == "lrc" && ($0 as NSString).deletingPathExtension.lowercased() == stem }
    }

    public static func lyrics(for file: URL) async -> Lyrics? {
        let folder = file.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        if let name = sidecar(for: file.lastPathComponent, in: names), let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            let lyrics = LRC.parse(text)
            if !lyrics.isEmpty { return lyrics }
        }
        return await embedded(in: file)
    }

    /// Lyrics stored in the file: the Vorbis LYRICS comment of FLAC and Ogg, ID3 USLT in MP3, ©lyr in M4A. Often LRC text.
    public static func embedded(in file: URL) async -> Lyrics? {
        let metadata = (try? await AVURLAsset(url: file).load(.metadata)) ?? []
        let ids: [AVMetadataIdentifier] = [AVMetadataIdentifier(rawValue: "vorb/LYRICS"), AVMetadataIdentifier(rawValue: "vorb/UNSYNCEDLYRICS"),
                                           .id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics]
        for id in ids {
            for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id) {
                guard let text = try? await item.load(.stringValue), !text.isEmpty else { continue }
                let lyrics = LRC.parse(text)
                if !lyrics.isEmpty { return lyrics }
            }
        }
        return nil
    }
}

extension Lyrics {
    /// The best of the server's lyrics: synced before plain, each line at its start plus the offset.
    public init?(structured list: [SubsonicStructuredLyrics]) {
        guard let pick = list.first(where: { $0.synced && !($0.line ?? []).isEmpty }) ?? list.first(where: { !($0.line ?? []).isEmpty }) else { return nil }
        let offset = Double(pick.offset ?? 0) / 1000
        let lines = (pick.line ?? []).map { line in
            Lyrics.Line(time: pick.synced ? line.start.map { max(0, Double($0) / 1000 - offset) } : nil, text: line.value.trimmingCharacters(in: .whitespaces))
        }
        let lyrics = Lyrics(lines: lines)
        guard !lyrics.isEmpty else { return nil }
        self = lyrics
    }
}
