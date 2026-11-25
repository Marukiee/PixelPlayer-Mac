import Foundation
import AVFoundation

/// A music file on this Mac, with the tags the matching rules need.
public struct LocalTrack: Codable, Sendable, Hashable {
    public var path: String
    public var relativePath: String
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String?
    public var genre: String?
    public var year: Int?
    public var track: Int?
    public var durationMs: Int
    public var modified: Double
    public var size: Int
    public var suffix: String
}

/// Reads a music folder. Tags are read once per file and kept in a cache next to the app's other data, so a second scan
/// of a large library only looks at files that changed.
public actor LocalScanner {
    public static let extensions: Set<String> = ["mp3", "flac", "m4a", "mp4", "aac", "alac", "ogg", "oga", "opus", "wav", "aiff", "aif"]
    private let cacheURL: URL

    public init(cacheURL: URL) {
        self.cacheURL = cacheURL
    }

    public func scan(root: URL) async -> [LocalTrack] {
        var cache = Dictionary(uniqueKeysWithValues: loadCache().map { ($0.path, $0) })
        let files = Self.audioFiles(in: root)
        var result: [LocalTrack] = []
        var toRead: [(URL, Double, Int)] = []
        for (url, modified, size) in files {
            if let known = cache[url.path], known.modified == modified, known.size == size { result.append(known) } else { toRead.append((url, modified, size)) }
        }
        // A few at a time: tag reading is IO bound and AVFoundation does not like hundreds at once.
        await withTaskGroup(of: LocalTrack?.self) { group in
            var iterator = toRead.makeIterator()
            for _ in 0..<8 {
                guard let next = iterator.next() else { break }
                group.addTask { await Self.read(next.0, root: root, modified: next.1, size: next.2) }
            }
            for await track in group {
                if let track { result.append(track); cache[track.path] = track }
                if let next = iterator.next() { group.addTask { await Self.read(next.0, root: root, modified: next.1, size: next.2) } }
            }
        }
        saveCache(result)
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    static func audioFiles(in root: URL) -> [(URL, Double, Int)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [(URL, Double, Int)] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate?.timeIntervalSince1970 ?? 0, values?.fileSize ?? 0))
        }
        return files
    }

    static func read(_ url: URL, root: URL, modified: Double, size: Int) async -> LocalTrack? {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        func string(_ identifiers: [AVMetadataIdentifier], common: AVMetadataKey? = nil) async -> String? {
            for id in identifiers {
                if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id).first,
                   let value = try? await item.load(.stringValue), !value.isEmpty { return value }
            }
            if let common, let item = AVMetadataItem.metadataItems(from: metadata, withKey: common, keySpace: .common).first,
               let value = try? await item.load(.stringValue), !value.isEmpty { return value }
            return nil
        }
        let fileTitle = url.deletingPathExtension().lastPathComponent
        let title = await string([.commonIdentifierTitle, .id3MetadataTitleDescription, .iTunesMetadataSongName], common: .commonKeyTitle) ?? fileTitle
        let artist = await string([.commonIdentifierArtist, .id3MetadataLeadPerformer, .iTunesMetadataArtist], common: .commonKeyArtist) ?? ""
        let album = await string([.commonIdentifierAlbumName, .id3MetadataAlbumTitle, .iTunesMetadataAlbum], common: .commonKeyAlbumName) ?? ""
        let albumArtist = await string([.id3MetadataBand, .iTunesMetadataAlbumArtist])
        let genre = await string([.id3MetadataContentType, .iTunesMetadataUserGenre], common: .commonKeyType)
        let trackText = await string([.id3MetadataTrackNumber])
        let yearText = await string([.id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate], common: .commonKeyCreationDate)
        var relative = url.path
        if relative.hasPrefix(root.path) { relative = String(relative.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return LocalTrack(path: url.path, relativePath: relative, title: title, artist: artist, album: album, albumArtist: albumArtist, genre: genre,
                          year: yearText.flatMap { Int($0.prefix(4)) }, track: trackText.flatMap { Int($0.split(separator: "/").first ?? "") },
                          durationMs: Int((duration.isFinite ? duration : 0) * 1000), modified: modified, size: size, suffix: url.pathExtension.lowercased())
    }

    private func loadCache() -> [LocalTrack] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([LocalTrack].self, from: data)) ?? []
    }

    private func saveCache(_ tracks: [LocalTrack]) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(tracks).write(to: cacheURL)
    }

    /// The embedded cover of a file, for local albums without a server cover.
    public static func artwork(of path: String) async -> Data? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let metadata = (try? await asset.load(.metadata)) ?? []
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first else { return nil }
        return try? await item.load(.dataValue)
    }
}
