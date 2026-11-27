import SwiftUI
import PixelPlayerKit

/// Album art drawn in code, so the prototype needs no images. Drawn on a 1000 by 1000 grid
/// that is scaled to whatever size the cover gets.
struct CoverArt: View {
    let album: Album
    var radius: CGFloat = Metrics.cover

    var body: some View {
        Group {
            if let art = album.art {
                Canvas { context, size in
                    context.scaleBy(x: size.width / 1000, y: size.height / 1000)
                    CoverArt.draw(art, in: &context)
                }
            } else {
                RemoteCover(album: album)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    private static let full = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    private static func linear(_ a: UInt32, _ b: UInt32) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [Color(hex: a), Color(hex: b)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 1000))
    }

    private static func radial(_ a: UInt32, _ b: UInt32) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: [Color(hex: a), Color(hex: b)]), center: CGPoint(x: 500, y: 500), startRadius: 0, endRadius: 720)
    }

    static func draw(_ art: ArtStyle, in c: inout GraphicsContext) {
        switch art {
        case .sunset:
            c.fill(Path(full), with: linear(0x2B0A4F, 0xFF4F9A))
            c.fill(circle(500, 470, 280), with: .linearGradient(Gradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xFF7A59)]),
                                                                startPoint: CGPoint(x: 0, y: 190), endPoint: CGPoint(x: 0, y: 500)))
            for (y, h) in [(360.0, 12.0), (400, 16), (440, 20)] {
                c.fill(Path(CGRect(x: 0, y: y, width: 1000, height: h)), with: .color(Color(hex: 0x2B0A4F)))
            }
            c.fill(Path(CGRect(x: 0, y: 500, width: 1000, height: 500)), with: .color(Color(hex: 0x2B0A4F)))
            var grid = Path()
            for y in [560.0, 630, 720, 840, 990] { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: 1000, y: y)) }
            for x in [-400.0, 0, 250, 500, 750, 1000, 1400] { grid.move(to: CGPoint(x: 500, y: 500)); grid.addLine(to: CGPoint(x: x, y: 1000)) }
            c.stroke(grid, with: .color(Color(hex: 0xFF4FD8)), lineWidth: 5)
        case .blueDisc:
            c.fill(Path(full), with: radial(0x1D3A8A, 0x0A1430))
            c.fill(circle(420, 560, 310), with: .color(Color(hex: 0x3D7BFF)))
            var arc = Path()
            arc.addArc(center: CGPoint(x: 730, y: 370), radius: 210, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            c.stroke(arc, with: .color(Color(hex: 0xF2C14E)), lineWidth: 12)
            var arc2 = Path()
            arc2.addArc(center: CGPoint(x: 730, y: 370), radius: 260, startAngle: .degrees(210), endAngle: .degrees(330), clockwise: false)
            c.stroke(arc2, with: .color(Color(hex: 0xF2C14E)), lineWidth: 7)
            c.fill(circle(760, 760, 60), with: .color(Color(hex: 0xF2C14E)))
        case .bubbles:
            c.fill(Path(full), with: linear(0xFFF1C1, 0xFFC8A8))
            c.fill(circle(340, 360, 220), with: .color(Color(hex: 0xFF8FAB)))
            c.fill(circle(640, 420, 190), with: .color(Color(hex: 0x7BDFF2).opacity(0.92)))
            c.fill(circle(470, 690, 190), with: .color(Color(hex: 0xB2F7EF).opacity(0.92)))
            c.fill(circle(760, 760, 100), with: .color(Color(hex: 0xF7D6E0)))
            c.fill(circle(230, 780, 80), with: .color(Color(hex: 0xFFD166)))
        case .hills:
            c.fill(Path(full), with: linear(0xF6EFD9, 0xCFE8D5))
            c.fill(circle(700, 300, 90), with: .color(Color(hex: 0xF4A259)))
            c.fill(ellipse(250, 760, 600, 260), with: .color(Color(hex: 0x8CB369)))
            c.fill(ellipse(800, 860, 600, 280), with: .color(Color(hex: 0x5B8E7D)))
            c.fill(ellipse(420, 1040, 800, 260), with: .color(Color(hex: 0x2F5D50)))
        case .orbit:
            c.fill(Path(full), with: radial(0x36215E, 0x0D0B1E))
            c.stroke(ellipse(500, 520, 400, 140), with: .color(Color(hex: 0x9D8CFF)), lineWidth: 6)
            c.stroke(circle(500, 520, 300), with: .color(Color(hex: 0xFF9ECD)), lineWidth: 5)
            c.fill(circle(500, 520, 120), with: .color(Color(hex: 0xFF6FA5)))
            c.fill(circle(800, 440, 28), with: .color(Color(hex: 0xFFE8A3)))
            for (x, y) in [(160.0, 170.0), (820, 140), (300, 860), (880, 860), (120, 560)] {
                c.fill(circle(x, y, 6), with: .color(.white))
            }
        case .prism:
            c.fill(Path(full), with: linear(0x0B3D40, 0x0F7C80))
            let tris: [([CGPoint], UInt32, Double)] = [
                ([CGPoint(x: 150, y: 820), CGPoint(x: 500, y: 180), CGPoint(x: 850, y: 820)], 0xFFB86B, 1),
                ([CGPoint(x: 330, y: 820), CGPoint(x: 600, y: 360), CGPoint(x: 870, y: 820)], 0xFF6F59, 0.85),
                ([CGPoint(x: 100, y: 820), CGPoint(x: 330, y: 470), CGPoint(x: 560, y: 820)], 0x7FE3D6, 0.8),
            ]
            for (points, color, opacity) in tris {
                var p = Path(); p.addLines(points); p.closeSubpath()
                c.fill(p, with: .color(Color(hex: color).opacity(opacity)))
            }
            c.fill(Path(CGRect(x: 0, y: 820, width: 1000, height: 180)), with: .color(Color(hex: 0x072B2D)))
        case .aurora:
            c.fill(Path(full), with: linear(0x07131F, 0x123A3A))
            for (i, color) in [0x3DFFB0, 0x7A6BFF, 0x2FD3FF].enumerated() {
                var wave = Path()
                let base = 300.0 + Double(i) * 110
                wave.move(to: CGPoint(x: 0, y: base))
                for x in stride(from: 0.0, through: 1000, by: 20) {
                    wave.addLine(to: CGPoint(x: x, y: base + sin(x / 150 + Double(i)) * 70))
                }
                c.stroke(wave, with: .color(Color(hex: UInt32(color)).opacity(0.75)), lineWidth: 46)
            }
            var hills = Path()
            hills.move(to: CGPoint(x: 0, y: 1000))
            hills.addLine(to: CGPoint(x: 0, y: 820)); hills.addLine(to: CGPoint(x: 260, y: 700)); hills.addLine(to: CGPoint(x: 470, y: 820))
            hills.addLine(to: CGPoint(x: 700, y: 680)); hills.addLine(to: CGPoint(x: 1000, y: 840)); hills.addLine(to: CGPoint(x: 1000, y: 1000))
            c.fill(hills, with: .color(Color(hex: 0x050B12)))
        case .tide:
            c.fill(Path(full), with: linear(0xF4E9D6, 0xE9D7BC))
            c.fill(circle(500, 360, 170), with: .color(Color(hex: 0xF08A5D)))
            for i in 0..<6 {
                var band = Path()
                let y = 520.0 + Double(i) * 80
                band.move(to: CGPoint(x: 0, y: y))
                for x in stride(from: 0.0, through: 1000, by: 25) { band.addLine(to: CGPoint(x: x, y: y + sin(x / 70 + Double(i)) * 18)) }
                band.addLine(to: CGPoint(x: 1000, y: 1000)); band.addLine(to: CGPoint(x: 0, y: 1000)); band.closeSubpath()
                c.fill(band, with: .color(Color(hex: [0x9CC5E8, 0x6FA6D6, 0x4A86C2, 0x2F68A8, 0x1F4F86, 0x163A66][i])))
            }
        case .copperMoon:
            c.fill(Path(full), with: radial(0x8C3A1E, 0x2A0E08))
            c.fill(circle(500, 470, 260), with: .radialGradient(Gradient(colors: [Color(hex: 0xFFC48A), Color(hex: 0xD9733F)]),
                                                                center: CGPoint(x: 420, y: 390), startRadius: 10, endRadius: 330))
            c.fill(circle(430, 420, 40), with: .color(Color(hex: 0xC2602F).opacity(0.5)))
            c.fill(circle(580, 540, 60), with: .color(Color(hex: 0xC2602F).opacity(0.45)))
            c.fill(circle(560, 360, 24), with: .color(Color(hex: 0xC2602F).opacity(0.5)))
            c.fill(Path(CGRect(x: 0, y: 840, width: 1000, height: 160)), with: .color(Color(hex: 0x1A0704)))
        }
    }
}

/// Four covers in a square, for playlists and mixes.
struct Collage: View {
    let albums: [Album]
    var radius: CGFloat = Metrics.cover

    var body: some View {
        // Four different covers when there are four, as Spotify's mosaics: a list of songs often has one album several
        // times. Fewer than four keep the order given (a mix's two covers crosswise).
        var seen = Set<String>()
        let different = albums.filter { seen.insert($0.id).inserted }
        // Never empty: a list without songs (or a mix that is gone) shows the library's first cover.
        let source = different.count >= 4 ? different : albums.isEmpty ? [Library.shared.album(at: 0)] : albums
        let picks = (0..<4).map { source[$0 % source.count] }
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow { CoverArt(album: picks[0], radius: 0); CoverArt(album: picks[1], radius: 0) }
            GridRow { CoverArt(album: picks[2], radius: 0); CoverArt(album: picks[3], radius: 0) }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .aspectRatio(1, contentMode: .fit)
    }
}

extension Album {
    /// A wash of the cover's colour, for the player's background.
    func wash(dark: Bool) -> LinearGradient {
        let base = Color(hex: tint)
        return dark
            ? LinearGradient(colors: [base.opacity(0.75), Color(hex: 0x0B0D14)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xD9E2FF), Color(hex: 0xEEF1FF)], startPoint: .top, endPoint: .bottom)
    }
}

/// A cover from the music file or the server, kept in a cache on disk so it is fetched once.
struct RemoteCover: View {
    let album: Album
    @LocalState private var image: NSImage?

    var body: some View {
        // A cover already in memory shows at once, also in a picture made in one go (the one under the pointer while a
        // song is dragged), where the loading below never gets its turn.
        let shown = CoverCache.shared.cached(for: album) ?? image
        ZStack {
            LinearGradient(colors: [Color(hex: album.tint), Color(hex: album.tint).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let shown {
                Image(nsImage: shown).resizable().scaledToFill()
            } else {
                // Never bigger than the cover: 28 pt on a big one, smaller on a small one.
                Image(systemName: "music.note").resizable().scaledToFit()
                    .frame(maxWidth: 28, maxHeight: 28).padding(6).foregroundStyle(.white.opacity(0.6))
            }
        }
        .task(id: album.id) { image = await CoverCache.shared.image(for: album) }
    }
}

/// Covers in memory and in ~/Library/Caches/PixelPlayer/covers, keyed by the server's cover id or the file path.
actor CoverCache {
    static let shared = CoverCache()
    /// The covers in memory, also readable at once from a view (NSCache is safe from any thread).
    private nonisolated(unsafe) let quick = NSCache<NSString, NSImage>()

    nonisolated static func key(for album: Album) -> String { album.coverArtID ?? album.localCover?.path ?? album.id }

    /// A cover that is already in memory, without waiting.
    nonisolated func cached(for album: Album) -> NSImage? { quick.object(forKey: Self.key(for: album) as NSString) }

    private func keep(_ image: NSImage, _ key: String) { quick.setObject(image, forKey: key as NSString) }
    private let folder: URL = {
        // A scripted run keeps its covers to itself, apart from the real app's.
        let url = ProcessInfo.processInfo.environment["PP_DEBUG_DIR"].map { URL(fileURLWithPath: $0).appendingPathComponent("covers", isDirectory: true) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PixelPlayer/covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func image(for album: Album) async -> NSImage? {
        let key = Self.key(for: album)
        if let image = cached(for: album) { return image }
        let file = folder.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".img")
        if let image = NSImage(contentsOf: file) { keep(image, key); return image }
        // A local album uses the cover inside its music file, unless the server has one; without one inside,
        // a picture in the album's folder (cover.jpg, folder.jpg and the like).
        if album.coverArtID == nil, let local = album.localCover {
            var data = await LocalScanner.artwork(of: local.path)
            if data.flatMap(NSImage.init(data:)) == nil, let picture = LocalScanner.folderArtwork(near: local.path) {
                data = try? Data(contentsOf: picture)
            }
            if let data, let image = NSImage(data: data) {
                try? data.write(to: file)
                keep(image, key)
                return image
            }
            return nil
        }
        guard let url = await MainActor.run(body: { Library.shared.coverURL(for: album) }),
              let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return nil }
        try? data.write(to: file)
        keep(image, key)
        return image
    }
}
