import AppKit
import SwiftUI

/// Your Mix at the top of Home as the head of the page, Mark's choice of three designs (2026-11-26): no card, the colour
/// of its covers behind it, the same covers as the Your Mix tile.
@MainActor
enum YourMixArt {
    /// The covers of the mix in its own order, as the Your Mix tile draws them.
    static var albums: [Album] {
        let mix = Library.shared.yourMix
        return mix.isEmpty ? [Library.shared.album(at: 0)] : mix.map(\.album)
    }

    static var art: Artwork { .collage(albums) }

    /// Opens Your Mix as a list when it is one in the library, otherwise plays it.
    static func open() {
        if let item = LibraryItem.all.first(where: { $0.title == Library.mixName }) {
            PlayerModel.shared.go(item.route)
        } else {
            PlayerModel.shared.play(Library.shared.yourMix)
        }
    }
}

/// The colour behind a cover: its strongest colour, a little darker so white reads on it, as Spotify's headers.
enum CoverTone {
    static func color(for albums: [Album]) async -> Color {
        for album in albums.prefix(4) {
            if album.art != nil { return Color(hex: album.tint) }
            if let image = await CoverCache.shared.image(for: album), let tone = strongest(in: image) { return Color(nsColor: tone) }
        }
        return Color(hex: albums.first?.tint ?? 0x23408F)
    }

    /// The pixels of the busiest hue (twelve bins, each pixel counted by how vivid it is), averaged.
    static func strongest(in image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var bins = [(weight: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 13)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let saturation = high == 0 ? 0 : (high - low) / high
            var bin = 12
            if saturation > 0.2 && high > 0.15 {
                var hue: Double
                if high == r { hue = (g - b) / (high - low) } else if high == g { hue = 2 + (b - r) / (high - low) } else { hue = 4 + (r - g) / (high - low) }
                hue = (hue < 0 ? hue + 6 : hue) / 6
                bin = min(11, Int(hue * 12))
            }
            let weight = bin == 12 ? 0.05 : saturation * high
            bins[bin].weight += weight
            bins[bin].r += r * weight; bins[bin].g += g * weight; bins[bin].b += b * weight
        }
        guard let best = bins.max(by: { $0.weight < $1.weight }), best.weight > 0 else { return nil }
        let color = NSColor(srgbRed: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return NSColor(hue: hue, saturation: min(max(saturation, 0.3), 0.75), brightness: min(max(brightness, 0.4), 0.58), alpha: 1)
    }
}

/// Your Mix as the head of the page, the way Spotify heads a playlist: no card, the colour of the covers running to the
/// edges behind it and fading into the page.
struct MixHeader: View {
    var body: some View {
        let cover: CGFloat = 200
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .bottom, spacing: 24) {
                Button { YourMixArt.open() } label: {
                    ArtworkView(art: YourMixArt.art, radius: 4)
                        .frame(width: cover, height: cover)
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 4)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Made for \(Owner.firstName)").font(.mix(14))
                    TitleFont.text("Your Mix", size: (cover * 0.302 / TitleFont.capHeight).rounded())
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(Library.shared.yourMixSummary).font(.mix(14)).opacity(0.7).lineLimit(1)
                }
                .foregroundStyle(.white)
            }
            HStack(spacing: 18) {
                PlayCircle(title: "Your Mix", songs: { Library.shared.yourMix })
                PlainIconButton(symbol: "shuffle", label: "Shuffle", onColour: true) { PlayerModel.shared.play(Library.shared.yourMix, shuffled: true) }
                RoundMenu(songs: Library.shared.yourMix, share: "Your Mix: \(Library.shared.yourMixSummary)", onColour: true)
            }
        }
    }

    /// The wash behind the top of the page, from the covers' colour to the page.
    static func wash(_ tone: Color) -> some View {
        LinearGradient(stops: [.init(color: tone, location: 0), .init(color: tone.opacity(0.75), location: 0.55), .init(color: PP.page, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// The colour of Your Mix's covers, for the wash behind the top of Home.
struct MixWash: View {
    @LocalState private var tone: Color = Color(hex: 0x23408F)

    var body: some View {
        MixHeader.wash(tone)
            .task(id: YourMixArt.albums.map(\.id)) { tone = await CoverTone.color(for: YourMixArt.albums) }
    }
}
