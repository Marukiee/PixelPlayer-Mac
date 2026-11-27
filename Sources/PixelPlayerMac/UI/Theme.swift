import SwiftUI
import AppKit

/// `@State` is a macro in the newest SDK and its plugin ships only with the full Xcode app.
/// The property wrapper underneath is still there, so this alias builds with the Command Line Tools.
typealias LocalState<Value> = SwiftUI.State<Value>

/// The big page titles at 800. Spotify's own title letter when Mix is imported (see `FontStore`); otherwise Figtree
/// (Resources/Fonts, SIL Open Font License), of forty free fonts the one that lies closest over Spotify's title letter
/// (measured on open.spotify.com: Figtree shares 78% of the pixels, Inter Display 74%, SF Pro 69%), with its own kerning.
enum TitleFont {
    private static let figtreeBase: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "FigtreeVariable", withExtension: "ttf", subdirectory: "Fonts"),
              let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        let axes: [Int: Double] = [0x7767_6874: 800]  // wght
        return CTFontDescriptorCreateCopyWithAttributes(found[0], [kCTFontVariationAttribute: axes] as CFDictionary)
    }()

    private static let figtreeCapHeight: CGFloat =
        figtreeBase.map { CTFontGetCapHeight(CTFontCreateWithFontDescriptor($0, 100, nil)) / 100 } ?? 0.705

    /// How high the capitals are, as a share of the size, so a title can be sized by its capitals as Spotify's are.
    @MainActor static var capHeight: CGFloat {
        FontStore.shared.font(size: 100, weight: .extrabold).map { CTFontGetCapHeight($0) / 100 } ?? figtreeCapHeight
    }

    /// Figtree at 800; the system's heavy font when the file is missing.
    static func figtree(_ size: CGFloat) -> Font {
        guard let figtreeBase else { return .system(size: size, weight: .heavy) }
        return Font(CTFontCreateWithFontDescriptor(figtreeBase, size, nil))
    }

    /// A big title: Spotify's title letter with its closer letters, or Figtree.
    @MainActor static func text(_ string: String, size: CGFloat) -> Text {
        if let font = FontStore.shared.font(size: size, weight: .extrabold) {
            return Text(string).font(Font(font)).tracking(FontStore.titleTracking(.extrabold) * size)
        }
        return Text(string).font(figtree(size))
    }
}

enum PP {
    static let primary = adaptive(0x1DB954, 0x1ED760)
    static let onPrimary = adaptive(0x000000, 0x000000)
    static let primaryContainer = adaptive(0xD2F5DE, 0x1B4A2C)
    static let onPrimaryContainer = adaptive(0x0B5A28, 0xC4F3D4)
    static let secondary = adaptive(0x485D92, 0xB1C5FF)
    static let secondaryContainer = adaptive(0xE8DDFF, 0x3D3560)
    static let onSecondaryContainer = adaptive(0x4A3D78, 0xE8DDFF)
    static let tertiaryContainer = adaptive(0xFFD8EC, 0x5A2F50)
    static let onTertiaryContainer = adaptive(0x7A2E5E, 0xFFD8EC)
    static let window = adaptive(0xFAF8FF, 0x111318)
    /// The frame around the panels and the band at the top: black, as Spotify's (measured #000). In light a soft grey, so the
    /// white panels still stand apart from it as Spotify's dark grey ones do from the black.
    static let sidebar = adaptive(0xE6E6E8, 0x000000)
    /// Home and the search field in the band: #1F1F1F, and #2A2A2A under the pointer or while typing (measured on Spotify).
    static let field = adaptive(0xFFFFFF, 0x1F1F1F)
    /// Spotify's menus (measured: #1F1F1F, the row under the pointer #2A2A2A).
    static let menu = adaptive(0xFFFFFF, 0x1F1F1F)
    static let menuHover = adaptive(0xEDEDED, 0x2A2A2A)
    static let fieldHover = adaptive(0xF7F7F7, 0x2A2A2A)
    /// The panel under the search field: Spotify's #2A2A2A, the same as the field while typing.
    static let searchPanel = adaptive(0xFFFFFF, 0x2A2A2A)
    /// Under the pointer in Your Library: #1F1F1F on the #121212 panel (Spotify's --background-highlight).
    static let rowHover = adaptive(0xEDEDED, 0x1F1F1F)
    /// The thin line before the browse button in the search field (measured #7C7C7C).
    static let fieldDivider = adaptive(0xB8B8B8, 0x7C7C7C)
    /// The queue column: the same as the sidebar beside the page, near black in dark and the sidebar's grey in light.
    /// The panels in the sidebar (Home and Search, Your Library), as Spotify's: dark grey on the black window.
    static let libraryPanel = adaptive(0xFFFFFF, 0x121212)
    static let panel = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0x060606 : 0xF0F0F2, alpha: 1)
    })
    /// The page panel: Spotify's #121212 in dark, white in light.
    static let page = adaptive(0xFFFFFF, 0x121212)
    static let surface = adaptive(0xF0F2FD, 0x1A1C23)
    static let surfaceHigh = adaptive(0xE5E8F7, 0x242733)
    static let ink = adaptive(0x1A1B21, 0xE4E2EA)
    static let inkSecondary = adaptive(0x5A5E70, 0xA8ACBE)
    static let hairline = adaptive(0x1A1B21, 0xFFFFFF, opacityLight: 0.07, opacityDark: 0.08)
    /// Spotify's second text colour (text-subdued, #B3B3B3 measured on open.spotify.com): artists, albums, times, "Show all".
    /// The system's secondary grey came out darker (#A4A4A4), so that text looked thinner than Spotify's.
    static let subdued = adaptive(0x6A6A6A, 0xB3B3B3)
    /// The player's icons, as solid colours: on glass the system's text colours take on the colour beneath and look washed.
    static let icon = adaptive(0x5E5E5E, 0xB3B3B3)
    static let iconHover = adaptive(0x000000, 0xFFFFFF)

    static func adaptive(_ light: UInt32, _ dark: UInt32, opacityLight: CGFloat = 1, opacityDark: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? opacityDark : opacityLight)
        })
    }
}

/// The tonal pairs for icons in a round and for tiles: a soft container and the ink that reads on it.
struct Tone: Hashable {
    let fill: Color
    let ink: Color

    static let blue = Tone(fill: PP.adaptive(0xD3E4FF, 0x1E3A66), ink: PP.adaptive(0x0B4FB3, 0xB7D0FF))
    static let lilac = Tone(fill: PP.adaptive(0xE8DDFF, 0x3D3560), ink: PP.adaptive(0x5B45A6, 0xD8CCFF))
    static let pink = Tone(fill: PP.adaptive(0xFFD8EC, 0x5A2F50), ink: PP.adaptive(0xA0306F, 0xFFC4E3))
    static let amber = Tone(fill: PP.adaptive(0xFFE2B5, 0x553D12), ink: PP.adaptive(0x8A5300, 0xFFD493))
    static let green = Tone(fill: PP.adaptive(0xCDEFD6, 0x1F4A30), ink: PP.adaptive(0x1F7A44, 0xA6E5BC))
    static let teal = Tone(fill: PP.adaptive(0xC8EEF0, 0x15474B), ink: PP.adaptive(0x0B6E75, 0x9FE3E8))
    static let red = Tone(fill: PP.adaptive(0xFFDAD5, 0x5C2520), ink: PP.adaptive(0xB3261E, 0xFFB4AB))
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// One place for how things move. Position and size use springs, because a spring carries momentum
/// and reads as an object being moved. Colour and opacity use a short ease, because a bouncing colour
/// looks like a bug. `Motion.slow` stretches everything for frame captures of the motion.
enum Motion {
    nonisolated(unsafe) static var slow: Double = 1

    /// Panels sliding in and out, lists making room.
    static var panel: Animation { .spring(response: 0.46 * slow, dampingFraction: 0.86) }
    /// A shape that turns into another one: the mini player into the full player, a button into a panel.
    static var morph: Animation { .spring(response: 0.56 * slow, dampingFraction: 0.8) }
    /// Arrivals and presses that may overshoot a little.
    static var bouncy: Animation { .bouncy(duration: 0.42 * slow, extraBounce: 0.08) }
    /// The lens under a text tab.
    static var lens: Animation { .spring(response: 0.4 * slow, dampingFraction: 0.76) }
    /// What the pointer sets going.
    static var hover: Animation { .spring(response: 0.24 * slow, dampingFraction: 0.74) }
    /// Colour, opacity and small presses, as Spotify's buttons and chips (open.spotify.com: 0.15 s, cubic-bezier(0.3, 0, 0, 1)).
    static var fade: Animation { .timingCurve(0.3, 0, 0, 1, duration: 0.15 * slow) }
    /// The play button rising on a card, as Spotify's (0.3 s, the browser's own ease).
    static var card: Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.3 * slow) }
}

let pressedScale: CGFloat = 0.96

/// One grid: everything is a multiple of 4.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let page: CGFloat = 24
}

/// Corner radii that nest: an inner shape gets the outer radius minus the gap, so curves stay parallel.
enum Metrics {
    static let tile: CGFloat = 24
    static let card: CGFloat = 20
    static let row: CGFloat = 14
    static let cover: CGFloat = 8
    static let panel: CGFloat = 28
    static func inner(_ outer: CGFloat, inset: CGFloat) -> CGFloat { max(4, outer - inset) }
}

extension Font {
    /// The rounded face stands in for Google Sans Flex with its ROND axis on Android.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: Surfaces and hover

extension View {
    /// The quiet plane content sits on. Glass is only for what floats above it.
    func surface(_ radius: CGFloat = Metrics.card, fill: Color = PP.surface) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }

    func hoverHighlight(radius: CGFloat = Metrics.row, selected: Bool = false, selectedFill: Color = PP.primaryContainer) -> some View {
        modifier(HoverHighlight(radius: radius, selected: selected, selectedFill: selectedFill))
    }

    func pressable() -> some View { buttonStyle(PressStyle()) }

    /// Grows a little under the pointer, on a spring. Still in scripted captures, where the pointer is not part of the design.
    func hoverLift(scale: CGFloat = 1.03) -> some View { modifier(HoverLift(scale: scale)) }

    /// A floating panel that holds content (the queue, the devices): glass at the rim, with a quiet plane
    /// under the rows so busy covers behind it never fight the text.
    func panelGlass(radius: CGFloat = Metrics.panel) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(PP.window.opacity(0.72)).padding(1))
            .glassEffect(.regular, in: shape)
    }
}

struct HoverHighlight: ViewModifier {
    var radius: CGFloat
    var selected: Bool
    var selectedFill: Color
    @LocalState private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(selected ? selectedFill : (hovering ? PP.ink.opacity(0.06) : Color.clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 && !Debug.active }
            .animation(Motion.fade, value: hovering)
    }
}

/// A plain button that dips a little when pressed, the same dip everywhere.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The whole frame takes the click, not only the strokes of a symbol.
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(Motion.bouncy, value: configuration.isPressed)
    }
}

/// Spotify's buttons: the main one a green pill with black text, a second one a pill with a grey ring and white text,
/// and in a dialog's footer plain white text. Bold and easy to read on the dark panels (the system's tinted buttons gave
/// white on light green and green on dark green).
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, outline, text }
    var kind: Kind = .text
    var height: CGFloat = 36

    init(kind: Kind = .text, height: CGFloat = 36) { self.kind = kind; self.height = height }
    init(prominent: Bool) { kind = prominent ? .primary : .text }

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, height: height)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled

        var body: some View {
        configuration.label
            .font(.mix(height >= 36 ? 15 : 13, .bold))
            .foregroundStyle(kind == .primary ? PP.onPrimary : Color.primary)
            .padding(.horizontal, kind == .text ? 14 : (height >= 36 ? 24 : 16))
            .frame(height: height)
            .background(Capsule().fill(kind == .primary ? PP.primary : Color.clear))
            .overlay(Capsule().strokeBorder(kind == .outline ? Color.primary.opacity(0.45) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
            .hoverLift()
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(Motion.bouncy, value: configuration.isPressed)
        }
    }
}

/// Hover without zooming, as in Spotify: what the pointer is on gets a little lighter.
struct HoverLift: ViewModifier {
    var scale: CGFloat
    @LocalState private var hovering = false

    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.06 : 0)
            .onHover { hovering = $0 && !Debug.active }
            .animation(Motion.fade, value: hovering)
    }
}
