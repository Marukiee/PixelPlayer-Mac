import CoreText
import Foundation

/// A font imported in Settings (Spotify's own Mix, which may not ship with the app): which files of a download to keep.
/// Weight and slant come from each file's OS/2 table, never from its name: the same font comes as SpotifyMix-Bold.ttf from
/// one place and Mix-Bold.ttf from another.
public enum FontImport {
    public struct Face: Equatable, Sendable {
        public let url: URL
        /// usWeightClass: 400 regular, 700 bold.
        public let weight: Int
        public let italic: Bool
        public let family: String
        /// Whether its layout tables can be read. The TrueType files of the download Mark uses have a table directory that
        /// points into the middle of GPOS, GSUB and GDEF, so they draw without kerning; the WOFF files beside them are whole.
        public let intact: Bool

        public init(url: URL, weight: Int, italic: Bool, family: String, intact: Bool) {
            self.url = url
            self.weight = weight
            self.italic = italic
            self.family = family
            self.intact = intact
        }
    }

    /// What CoreText reads. EOT, HTML and CSS in a download are left alone.
    public static let extensions: Set<String> = ["ttf", "otf", "woff", "woff2"]

    /// Weight and slant from an OS/2 table: usWeightClass at byte 4, fsSelection at byte 62 (bit 0 italic, bit 9 oblique).
    public static func style(os2: [UInt8]) -> (weight: Int, italic: Bool)? {
        guard os2.count >= 64 else { return nil }
        let weight = Int(os2[4]) << 8 | Int(os2[5])
        let selection = Int(os2[62]) << 8 | Int(os2[63])
        guard (1...1000).contains(weight) else { return nil }
        return (weight, selection & 0x201 != 0)
    }

    /// A layout table (GPOS, GSUB, GDEF) is whole when it starts with its version: major 1, minor 0 to 3. No table at all is
    /// not broken.
    public static func wholeLayout(_ table: [UInt8]?) -> Bool {
        guard let table else { return true }
        guard table.count >= 4 else { return false }
        return table[0] == 0 && table[1] == 1 && table[2] == 0 && table[3] <= 3
    }

    /// The face in one file, or nil when it is not a font CoreText reads.
    public static func inspect(_ url: URL) -> Face? {
        guard extensions.contains(url.pathExtension.lowercased()),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        func table(_ tag: Int) -> [UInt8]? {
            (CTFontCopyTable(font, CTFontTableTag(tag), []) as Data?).map { [UInt8]($0) }
        }
        guard let os2 = table(kCTFontTableOS2), let style = style(os2: os2) else { return nil }
        let intact = [kCTFontTableGPOS, kCTFontTableGSUB, kCTFontTableGDEF].allSatisfy { wholeLayout(table($0)) }
        return Face(url: url, weight: style.weight, italic: style.italic, family: CTFontCopyFamilyName(font) as String, intact: intact)
    }

    /// Every font file in what was chosen or dropped: loose files, folders with their subfolders, and zip archives as a
    /// browser leaves them (unpacked into `scratch`).
    public static func collect(_ urls: [URL], unpackingInto scratch: URL) -> [URL] {
        let manager = FileManager.default
        var found: [URL] = []
        var zips = 0
        func walk(_ url: URL) {
            var isFolder: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isFolder) else { return }
            if isFolder.boolValue {
                let items = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                items.sorted { $0.lastPathComponent < $1.lastPathComponent }.forEach(walk)
            } else if url.pathExtension.lowercased() == "zip" {
                zips += 1
                let into = scratch.appendingPathComponent("zip\(zips)")
                try? manager.createDirectory(at: into, withIntermediateDirectories: true)
                if unzip(url, into: into) { walk(into) }
            } else if extensions.contains(url.pathExtension.lowercased()) {
                found.append(url)
            }
        }
        urls.forEach(walk)
        return found
    }

    private static func unzip(_ archive: URL, into folder: URL) -> Bool {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, folder.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        do { try ditto.run() } catch { return false }
        ditto.waitUntilExit()
        return ditto.terminationStatus == 0
    }

    /// One face per weight and slant: a whole file before a broken one, then TrueType or OpenType before WOFF and WOFF2
    /// (they hold the same letters). Sorted by slant, then weight.
    public static func pick(_ faces: [Face]) -> [Face] {
        func rank(_ face: Face) -> Int {
            let format = ["otf": 0, "ttf": 0, "woff": 1, "woff2": 2][face.url.pathExtension.lowercased()] ?? 3
            return (face.intact ? 0 : 10) + format
        }
        var best: [String: Face] = [:]
        for face in faces {
            let key = "\(face.weight)-\(face.italic)"
            if let kept = best[key], rank(kept) <= rank(face) { continue }
            best[key] = face
        }
        return best.values.sorted { ($0.italic ? 1 : 0, $0.weight) < ($1.italic ? 1 : 0, $1.weight) }
    }

    /// Why these faces can't stand in for the app's text, or nil when they can: an upright regular and bold are needed.
    public static func missing(_ faces: [Face]) -> String? {
        let upright = Set(faces.filter { !$0.italic }.map(\.weight))
        if faces.isEmpty { return "No fonts in what you chose" }
        switch (upright.contains(400), upright.contains(700)) {
        case (true, true): return nil
        case (false, false): return "Regular and Bold are missing"
        case (false, true): return "Regular is missing"
        case (true, false): return "Bold is missing"
        }
    }

    /// A family name to show: the font's own, unless its name table can't be read (then the file's name up to the first dash).
    public static func displayName(_ faces: [Face]) -> String {
        let readable = faces.map(\.family).first { name in
            !name.isEmpty && name.unicodeScalars.allSatisfy { $0.isASCII && (0x20..<0x7F).contains($0.value) } && name.count > 2
        }
        if let readable { return readable }
        let stem = faces.first?.url.deletingPathExtension().lastPathComponent ?? "Font"
        return String(stem.split(separator: "-").first ?? Substring(stem))
    }
}
