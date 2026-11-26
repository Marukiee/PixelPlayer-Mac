import SwiftUI

/// The player's own icons, drawn after Mark's screenshots of Spotify's and laid over them to check: every point below is
/// measured on those screenshots, as a share of the icon's box (the box includes the line's own thickness).
enum GlyphKind {
    case shuffle, loop, previous, next, mic, queue, addQueue, connect

    /// Width over height of the box, as measured.
    var aspect: CGFloat {
        switch self {
        case .shuffle: 66.0 / 58.0
        case .loop: 62.0 / 60.0
        case .previous, .next: 61.0 / 67.0
        case .queue, .addQueue: 1
        case .mic: 155.0 / 154.0
        case .connect: 53.0 / 45.0
        }
    }

    /// SpotCopy's icon from Android (Resources/Icons, traced over Spotify's), for all but the microphone, which Android
    /// has only as its own vector.
    var file: String? {
        switch self {
        case .shuffle: "shuffle"
        case .loop: "repeat"
        case .previous: "previous"
        case .next: "next"
        case .queue: "queue"
        case .addQueue: "m_addqueue"
        case .connect: "connect"
        case .mic: nil
        }
    }
}

/// One icon, in the current foreground style: SpotCopy's traced Android icon, or the drawn microphone.
struct Glyph: View {
    let kind: GlyphKind

    /// The parts only shape a mask, and the style fills it once: with a see-through style (white at 75% on a coloured
    /// header, or secondary grey) the spots where two parts overlap would otherwise come out lighter.
    var body: some View {
        Rectangle().mask { parts.foregroundStyle(.black) }
    }

    private var parts: some View {
        GeometryReader { geo in
            if let file = kind.file {
                SpotifyIcon(name: file).fill(style: FillStyle(eoFill: true))
            } else {
                Self.mic(geo.size.width, geo.size.height)
                    .stroke(style: StrokeStyle(lineWidth: geo.size.width * 0.096, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private static func mic(_ w: CGFloat, _ h: CGFloat) -> Path {
        let side = min(w, h)
        let head = CGPoint(x: 0.69 * w, y: 0.30 * h)
        let radius = side * 0.235
        let end = CGPoint(x: 0.17 * w, y: 0.83 * h)
        let half = side * 0.13
        let dx = end.x - head.x, dy = end.y - head.y
        let length = sqrt(dx * dx + dy * dy)
        let ux = dx / length, uy = dy / length
        let nx = -uy, ny = ux
        let along = sqrt(max(0, radius * radius - half * half))
        let joinA = CGPoint(x: head.x + ux * along + nx * half, y: head.y + uy * along + ny * half)
        let joinB = CGPoint(x: head.x + ux * along - nx * half, y: head.y + uy * along - ny * half)
        let angleA = atan2(joinA.y - head.y, joinA.x - head.x), angleB = atan2(joinB.y - head.y, joinB.x - head.x)
        let angle = atan2(uy, ux)
        var path = Path()
        // The head: the long way round from one join to the other, and straight back across.
        path.move(to: joinA)
        path.addArc(center: head, radius: radius, startAngle: .radians(angleA), endAngle: .radians(angleB), clockwise: false)
        path.closeSubpath()
        // The handle.
        path.move(to: joinA)
        path.addLine(to: CGPoint(x: end.x + nx * half, y: end.y + ny * half))
        path.addArc(center: end, radius: half, startAngle: .radians(angle + .pi / 2), endAngle: .radians(angle - .pi / 2), clockwise: true)
        path.addLine(to: joinB)
        return path
    }
}

extension Glyph {
    /// The icon at a height, as wide as its own proportions ask.
    func sized(height: CGFloat) -> some View { frame(width: height * kind.aspect, height: height) }
}
