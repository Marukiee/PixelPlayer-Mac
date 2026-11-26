import AppKit
import CoreText
import PixelPlayerKit
import SwiftUI

/// The weights Spotify uses (open.spotify.com, 2026-11-26): 400 for nearly all text, 700 for headings and buttons, 800 for
/// the big titles. Nothing in between.
enum MixWeight: Int {
    case regular = 400
    case bold = 700
    case extrabold = 800

    /// The system's weight when no font is imported.
    var system: Font.Weight {
        switch self {
        case .regular: .regular
        case .bold: .bold
        case .extrabold: .heavy
        }
    }
}

/// Spotify's own letter, Mix, once imported in Settings › Appearance › Font. Its licence keeps it out of this repository and
/// out of the releases, so the app copies what is imported to Application Support and uses it from there; without it the
/// titles are Figtree and the rest the system's font.
///
/// Measured on open.spotify.com against the imported files (70 characters a weight, 2026-11-26): Spotify's UI letter,
/// SpotifyMixUI, is Mix drawn 0.967 as wide, with the same height, shapes and kerning (within 0.1 px a letter at 100 px).
/// Its title letter, SpotifyMixUITitle, is that with every letter 0.015 em closer at 800 and 0.019 em at 700.
@MainActor
@Observable
final class FontStore {
    static let shared = FontStore()

    /// How much narrower Spotify draws Mix.
    nonisolated static let narrow: CGFloat = 0.967

    /// The upright faces by weight; empty without an imported font.
    private(set) var faces: [Int: CTFontDescriptor] = [:]
    /// The imported family as found ("Spotify Mix") and how many styles were kept.
    private(set) var name: String?
    private(set) var styleCount = 0
    /// What the last import said when it could not be used.
    var problem: String?
    private(set) var importing = false

    @ObservationIgnored private var cache: [String: CTFont] = [:]

    var available: Bool { !faces.isEmpty }

    nonisolated static var folder: URL {
        if let path = ProcessInfo.processInfo.environment["PP_FONTS_DIR"] { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PixelPlayer/Fonts", isDirectory: true)
    }

    private init() {
        load(FontImport.pick(installedFaces()))
    }

    private func installedFaces() -> [FontImport.Face] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(FontImport.inspect)
    }

    private func load(_ picked: [FontImport.Face]) {
        cache = [:]
        guard FontImport.missing(picked) == nil else {
            faces = [:]; name = nil; styleCount = 0
            return
        }
        var found: [Int: CTFontDescriptor] = [:]
        for face in picked where !face.italic {
            if let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(face.url as CFURL) as? [CTFontDescriptor])?.first {
                found[face.weight] = descriptor
            }
        }
        faces = found
        name = FontImport.displayName(picked)
        styleCount = picked.count
    }

    /// Takes what was chosen or dropped (a zip as it downloads, a folder, loose files), keeps one file per style, copies them
    /// to Application Support and uses them at once. Leaves the current font when regular or bold is missing.
    func importFonts(from urls: [URL]) {
        guard !importing else { return }
        importing = true
        problem = nil
        Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let scratch = manager.temporaryDirectory.appendingPathComponent("PixelPlayer-font-\(UUID().uuidString)", isDirectory: true)
            defer { try? manager.removeItem(at: scratch) }
            let picked = FontImport.pick(FontImport.collect(urls, unpackingInto: scratch).compactMap(FontImport.inspect))
            var problem = FontImport.missing(picked)
            var installed: [FontImport.Face] = []
            if problem == nil {
                // A fresh folder, so an earlier font never mixes in. Named by style, as the download's names can't be trusted.
                let folder = FontStore.folder
                try? manager.removeItem(at: folder)
                try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
                for face in picked {
                    let target = folder.appendingPathComponent("\(face.weight)\(face.italic ? "i" : "").\(face.url.pathExtension.lowercased())")
                    if (try? manager.copyItem(at: face.url, to: target)) != nil, let copied = FontImport.inspect(target) {
                        installed.append(copied)
                    }
                }
                if FontImport.missing(installed) != nil { problem = "The font could not be copied" }
            }
            let result = problem, faces = installed
            await MainActor.run {
                let store = FontStore.shared
                store.importing = false
                store.problem = result
                if result == nil { store.load(faces) }
            }
        }
    }

    /// Back to Figtree and the system's font; the copy is removed.
    func useDefault() {
        try? FileManager.default.removeItem(at: Self.folder)
        problem = nil
        load([])
    }

    /// Mix at this size, narrowed as Spotify draws it; nil without an imported font. Reading `faces` here is what makes a view
    /// draw again after an import.
    func font(size: CGFloat, weight: MixWeight, tabular: Bool = false) -> CTFont? {
        guard !faces.isEmpty else { return nil }
        let key = "\(size)-\(weight.rawValue)-\(tabular)"
        if let font = cache[key] { return font }
        // The weight asked for, or the nearest one imported (Spotify's 800 from 700 when there is no Extrabold).
        guard let base = faces[weight.rawValue] ?? faces.min(by: { abs($0.key - weight.rawValue) < abs($1.key - weight.rawValue) })?.value else { return nil }
        var descriptor = base
        if tabular {
            let features: [[CFString: Any]] = [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]]
            descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontFeatureSettingsAttribute: features] as CFDictionary)
        }
        var matrix = CGAffineTransform(scaleX: Self.narrow, y: 1)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, &matrix)
        cache[key] = font
        return font
    }

    /// How much closer Spotify sets the letters of its title letter, per point of size.
    nonisolated static func titleTracking(_ weight: MixWeight) -> CGFloat {
        weight == .extrabold ? -0.015 : -0.019
    }
}

extension Font {
    /// Spotify's UI letter (SpotifyMixUI) at this size and weight; the system's font when none is imported. `tabular` gives
    /// figures of one width, as Spotify's track numbers, durations and play times.
    @MainActor static func mix(_ size: CGFloat, _ weight: MixWeight = .regular, tabular: Bool = false) -> Font {
        if let font = FontStore.shared.font(size: size, weight: weight, tabular: tabular) { return Font(font) }
        let system = Font.system(size: size, weight: weight.system)
        return tabular ? system.monospacedDigit() : system
    }
}

extension View {
    /// Spotify's title letter (SpotifyMixUITitle): section headings at 700, the big titles at 800. Without an imported font:
    /// the system's bold, and Figtree for the big titles.
    func titleFont(_ size: CGFloat, _ weight: MixWeight = .bold) -> some View {
        modifier(TitleLetter(size: size, weight: weight))
    }
}

private struct TitleLetter: ViewModifier {
    let size: CGFloat
    let weight: MixWeight

    func body(content: Content) -> some View {
        let store = FontStore.shared
        if let font = store.font(size: size, weight: weight) {
            content.font(Font(font)).tracking(FontStore.titleTracking(weight) * size)
        } else if weight == .extrabold {
            content.font(TitleFont.figtree(size))
        } else {
            content.font(.system(size: size, weight: weight.system))
        }
    }
}
