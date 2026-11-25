import SwiftUI
import AppKit

/// `@State` is a macro in the newest SDK and its plugin ships only with the full Xcode app.
/// The property wrapper underneath is still there, so this alias builds with the Command Line Tools.
typealias LocalState<Value> = SwiftUI.State<Value>

/// The palette: Spotify's green as the accent (Mark's pick), with black on it as in Spotify, and the soft
/// tones of PixelPlayer on Android for the rest. Every colour is a role, never a raw hex in a view.
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
    /// The sidebar in dark: nearly black, darker than the pages, as Spotify's frame. In light the system's own sidebar stays.
    static let sidebar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x060606, alpha: 1) : .clear
    })
    /// The queue column: the same as the sidebar beside the page, near black in dark and the sidebar's grey in light.
    static let panel = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0x060606 : 0xF0F0F2, alpha: 1)
    })
    /// Behind the pages: the system's window colour in light, near black in dark, as dark as Spotify feels.
    static let page = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x121212, alpha: 1) : .windowBackgroundColor
    })
    static let surface = adaptive(0xF0F2FD, 0x1A1C23)
    static let surfaceHigh = adaptive(0xE5E8F7, 0x242733)
    static let ink = adaptive(0x1A1B21, 0xE4E2EA)
    static let inkSecondary = adaptive(0x5A5E70, 0xA8ACBE)
    static let hairline = adaptive(0x1A1B21, 0xFFFFFF, opacityLight: 0.07, opacityDark: 0.08)

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
    /// Colour and opacity only.
    static var fade: Animation { .easeOut(duration: 0.2 * slow) }
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
