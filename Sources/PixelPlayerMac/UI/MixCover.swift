import SwiftUI

/// A Daily Mix cover as SpotCopy draws it (Mark chose variant B, STIJL.md › Daily Mix-hoezen): the cover of the first
/// artist in two colours, a glow from the top left, a fade to the deep colour at the bottom and the name on one line.
/// Without a cover only the two colours. Grey until the cover is there, then it fades in.
struct DailyMixCover: View {
    let title: String
    /// 1 to 6: the colour pair, as SpotCopy's Daily Mix N.
    let pair: Int
    var album: Album? = nil
    var radius: CGFloat = 6

    /// Deep and light per pair (STIJL.md).
    static let pairs: [(deep: UInt32, light: UInt32)] = [
        (0x1B2A80, 0xFF8F8F), (0x3B0F6E, 0xF7E26B), (0x0A3F3B, 0x78F0C6),
        (0x6E0F1E, 0xFFB98C), (0x102544, 0x8CC8FF), (0x4B0E3B, 0xFF9FD5),
    ]

    static func colours(_ pair: Int) -> (deep: UInt32, light: UInt32) { pairs[(max(pair, 1) - 1) % pairs.count] }

    @State private var image: NSImage?
    @State private var ready = false

    var body: some View {
        let (deep, light) = Self.colours(pair)
        GeometryReader { geo in
            let size = geo.size.width
            ZStack(alignment: .bottomLeading) {
                Color(hex: deep)
                if let image {
                    // Duotone: the dark of the picture becomes the deep colour, the light the light one.
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: size, height: size).clipped()
                        .grayscale(1).contrast(1.25)
                        .colorMultiply(Self.span(deep, light))
                        .blendMode(.plusLighter)
                } else {
                    LinearGradient(colors: [Color(hex: light), Color(hex: deep)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                RadialGradient(colors: [Color(hex: light).opacity(0.45), .clear], center: .topLeading, startRadius: 0, endRadius: size * 2.2)
                LinearGradient(stops: [.init(color: Color(hex: deep).opacity(0), location: 0.35), .init(color: Color(hex: deep).opacity(0.95), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                Text(title)
                    .font(.mix(size * 0.11, .extrabold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, size * 0.075)
                    .padding(.bottom, size * 0.07)
            }
            .compositingGroup()
            .opacity(ready ? 1 : 0)
            .background(Color(hex: 0x2A2A2A))
            .animation(.easeOut(duration: 0.18), value: ready)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: album?.id) {
            if let album {
                if album.art != nil {
                    // The made-up covers of the design shots are drawn in code: drawn once into a picture here.
                    image = ImageRenderer(content: CoverArt(album: album, radius: 0).frame(width: 600, height: 600)).nsImage
                } else {
                    image = await CoverCache.shared.image(for: album)
                }
            }
            ready = true
        }
    }

    /// Light minus deep, per channel: what the grey of the picture is multiplied by before it is added to the deep colour.
    private static func span(_ deep: UInt32, _ light: UInt32) -> Color {
        func part(_ c: UInt32, _ shift: UInt32) -> Double { Double((c >> shift) & 0xFF) / 255 }
        func diff(_ shift: UInt32) -> Double { max(0, part(light, shift) - part(deep, shift)) }
        return Color(.sRGB, red: diff(16), green: diff(8), blue: diff(0))
    }
}
