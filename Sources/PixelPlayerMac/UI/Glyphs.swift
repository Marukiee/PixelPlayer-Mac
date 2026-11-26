import SwiftUI

/// The player's own icons, drawn after Mark's screenshots of Spotify's and laid over them to check: every point below is
/// measured on those screenshots, as a share of the icon's box (the box includes the line's own thickness).
enum GlyphKind {
    case shuffle, loop, previous, next, mic, queue, addQueue, connect

    /// Width over height of the box, as measured.
    var aspect: CGFloat {
        switch self {
        case .shuffle: 66.0 / 58.0
        case .loop: 160.0 / 148.0
        case .previous, .next, .queue: 1
        case .mic: 155.0 / 154.0
        case .addQueue, .connect: 160.0 / 150.0
        }
    }
}

/// One icon, in the current foreground style. Lines are about a tenth of the icon's width, as in Spotify's.
struct Glyph: View {
    let kind: GlyphKind

    /// The parts only shape a mask, and the style fills it once: with a see-through style (white at 75% on a coloured
    /// header, or secondary grey) the spots where a line and its arrowhead overlap would otherwise come out lighter.
    var body: some View {
        Rectangle().mask { parts.foregroundStyle(.black) }
    }

    private var parts: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let line = w * (kind == .queue ? 0.107 : 0.096)
            ZStack(alignment: .topLeading) {
                switch kind {
                // The same shuffle as SpotCopy on Android (Resources/Icons/sp_shuffle.svg, laid over Spotify's).
                case .shuffle: SpotifyIcon(name: "shuffle").fill(style: FillStyle(eoFill: true))
                case .loop: Self.loop(w, h, line)
                case .previous, .next:
                    Self.skip(w, h, forward: kind == .next).fill()
                case .mic:
                    Self.mic(w, h).stroke(style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                case .queue: Self.queue(w, h, line)
                case .addQueue: Self.addQueue(w, h, line)
                case .connect: Self.connect(w, h, line)
                }
            }
        }
    }

    /// Straight cut ends, as Spotify's lines have.
    private static func butt(_ line: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: line, lineCap: .butt, lineJoin: .round) }
    /// Arrowheads: round ends and a pointed tip.
    private static func arrow(_ line: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .miter) }

    private static func loop(_ w: CGFloat, _ h: CGFloat, _ line: CGFloat) -> some View {
        func n(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        let left: CGFloat = 0.05, right: CGFloat = 0.953, top: CGFloat = 0.054, bottom: CGFloat = 0.794
        let radius = w * 0.1375
        return ZStack {
            Path { p in
                // From the cut end left of the opening, round the loop, back to the arrow's tip.
                p.move(to: n(0.31, bottom))
                p.addArc(tangent1End: n(left, bottom), tangent2End: n(left, top), radius: radius)
                p.addArc(tangent1End: n(left, top), tangent2End: n(right, top), radius: radius)
                p.addArc(tangent1End: n(right, top), tangent2End: n(right, bottom), radius: radius)
                p.addArc(tangent1End: n(right, bottom), tangent2End: n(left, bottom), radius: radius)
                p.addLine(to: n(0.49, bottom))
            }
            .stroke(style: butt(line))
            Path { p in
                p.move(to: n(0.645, 0.62)); p.addLine(to: n(0.49, bottom)); p.addLine(to: n(0.645, 0.968))
            }
            .stroke(style: arrow(line))
        }
    }

    /// A square: a bar of a fifth with softly rounded corners, and a triangle whose tip runs into the bar.
    private static func skip(_ w: CGFloat, _ h: CGFloat, forward: Bool) -> Path {
        let bar = w * 0.21
        var path = Path()
        path.addRoundedTriangle([CGPoint(x: 0, y: 0), CGPoint(x: w * 0.96, y: h / 2), CGPoint(x: 0, y: h)], radius: w * 0.035)
        path.addRoundedRect(in: CGRect(x: w - bar, y: 0, width: bar, height: h), cornerSize: CGSize(width: w * 0.055, height: w * 0.055))
        return forward ? path : path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
    }

    /// A round head, cut straight across where the handle joins it, and the handle in outline down to a round end.
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

    private static func queue(_ w: CGFloat, _ h: CGFloat, _ line: CGFloat) -> some View {
        ZStack {
            Path { p in
                let pill = CGRect(x: w * 0.054, y: h * 0.05, width: w * 0.892, height: h * 0.25)
                p.addRoundedRect(in: pill, cornerSize: CGSize(width: pill.height / 2, height: pill.height / 2))
            }
            .stroke(style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            Path { p in
                for y in [0.62, 0.95] as [CGFloat] { p.move(to: CGPoint(x: 0, y: y * h)); p.addLine(to: CGPoint(x: w, y: y * h)) }
            }
            .stroke(style: butt(line))
        }
    }

    private static func addQueue(_ w: CGFloat, _ h: CGFloat, _ line: CGFloat) -> some View {
        func n(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        return Path { p in
            p.move(to: n(0, 0.183)); p.addLine(to: n(0.344, 0.183))
            p.move(to: n(0.172, 0)); p.addLine(to: n(0.172, 0.367))
            // The hook for the queue: in from the left, round, and back.
            let turn = (0.35 - 0.117) / 2 * h
            p.move(to: n(0.5, 0.117))
            p.addLine(to: n(0.844, 0.117))
            p.addArc(center: n(0.844, 0.2335), radius: turn, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: n(0.45, 0.35))
            for y in [0.65, 0.95] as [CGFloat] { p.move(to: n(0.125, y)); p.addLine(to: n(1, y)) }
        }
        .stroke(style: butt(line))
    }

    private static func connect(_ w: CGFloat, _ h: CGFloat, _ line: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                let box = CGRect(x: w * 0.375 + line / 2, y: line / 2, width: w * 0.625 - line, height: h - line)
                p.addRoundedRect(in: box, cornerSize: CGSize(width: w * 0.11, height: w * 0.11))
                // The bracket: in at the top, down the side, in again at the bottom.
                let left = line / 2, radius = w * 0.07
                p.move(to: CGPoint(x: w * 0.25, y: line / 2))
                p.addArc(tangent1End: CGPoint(x: left, y: line / 2), tangent2End: CGPoint(x: left, y: h), radius: radius)
                p.addArc(tangent1End: CGPoint(x: left, y: h - line / 2), tangent2End: CGPoint(x: w * 0.25, y: h - line / 2), radius: radius)
                p.addLine(to: CGPoint(x: w * 0.25, y: h - line / 2))
            }
            .stroke(style: butt(line))
            Path { p in
                p.addEllipse(in: CGRect(x: w * 0.69 - w * 0.0625, y: h * 0.3 - w * 0.0625, width: w * 0.125, height: w * 0.125))
                p.addEllipse(in: CGRect(x: w * 0.69 - w * 0.125, y: h * 0.65 - w * 0.125, width: w * 0.25, height: w * 0.25))
            }
            .fill()
        }
    }
}

extension Glyph {
    /// The icon at a height, as wide as its own proportions ask.
    func sized(height: CGFloat) -> some View { frame(width: height * kind.aspect, height: height) }
}
