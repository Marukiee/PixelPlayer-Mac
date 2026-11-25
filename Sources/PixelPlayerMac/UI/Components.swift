import SwiftUI
import AppKit

// Round 2: everything here is a thin wrapper around the system's own controls.

/// The small mark for songs the listener queued: they play first.
struct QueuedMark: View {
    var body: some View {
        Image(systemName: "text.line.first.and.arrowtriangle.forward")
            .foregroundStyle(.tint)
            .help("Added by you, plays first")
    }
}

/// The speaker that shows which song is playing, moving while it plays.
struct NowPlayingMark: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .foregroundStyle(.tint)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: model.isPlaying)
    }
}

/// A song in a plain list (queue, menu bar): cover, title and artist, in the system's row layout.
struct SongLine: View {
    let song: Song
    var playing = false
    var queued = false
    var cover: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            CoverArt(album: song.album, radius: 4).frame(width: cover, height: cover)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).fontWeight(playing ? .semibold : .regular)
                Text(song.artist).font(.callout).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if playing { NowPlayingMark() } else if queued { QueuedMark() }
        }
    }
}

/// The song's position: the system slider with the times under it.
struct PositionSlider: View {
    var small = false
    var showQuality = false
    @Environment(PlayerModel.self) private var model

    var body: some View {
        VStack(spacing: 2) {
            ScrubBar()
            HStack {
                Text(timeString(model.position))
                Spacer()
                if showQuality { Text("44.1 kHz · 192 kbps · MP3") }
                Spacer()
                RemainingTime()
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// The song's position as a thin bar with a round knob, like the system slider, with what Spotify adds: under the pointer
/// the bar turns green with its knob, the time at the pointer shows above it, and the stretch up to the pointer lights up.
struct ScrubBar: View {
    @Environment(PlayerModel.self) private var model
    /// Where the pointer is over the bar, and where it is held while dragging the knob.
    @LocalState private var hoverX: CGFloat?
    @LocalState private var dragX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let duration = max(1, model.duration)
            let played = min(max(dragX ?? CGFloat(model.position / duration) * width, 0), width)
            // Nothing to show or move while no song is chosen.
            let hasSong = model.duration > 0
            let active = hasSong && (hoverX != nil || dragX != nil)
            let pointer = hasSong ? (dragX ?? hoverX) : nil
            // Each part has its own height: in a ZStack a shape takes the height of the largest part, which made it thick.
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.2)).frame(height: 3)
                // Up to the pointer, lighter, where a click would go.
                if hasSong, let hoverX, dragX == nil, hoverX > played {
                    Capsule().fill(Color.primary.opacity(0.4)).frame(width: hoverX, height: 3)
                }
                Capsule().fill(active ? AnyShapeStyle(PP.primary) : AnyShapeStyle(Color.primary.opacity(0.8))).frame(width: played, height: 3)
            }
            .frame(height: 3)
            // The knob only while it is dragged, as in Spotify.
            .overlay(alignment: .leading) {
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: 11, height: 11)
                    .offset(x: played - 5.5)
                    .opacity(dragX != nil ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if let pointer {
                    Text(timeString(Double(min(max(pointer, 0), width) / width) * duration))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(hex: 0x2A2A2A)))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .fixedSize()
                        .position(x: min(max(pointer, 18), width - 18), y: -12)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverX = min(max(point.x, 0), width)
                case .ended: hoverX = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragX = min(max($0.location.x, 0), width) }
                    .onEnded { value in
                        let x = min(max(value.location.x, 0), width)
                        model.seek(to: Double(x / width) * duration)
                        dragX = nil
                    }
            )
            .onAppear {
                // `PP_SCRUB_HOVER=0.6` shows the pointer at 60% of the bar, for screenshots.
                if Debug.active, let at = Double(ProcessInfo.processInfo.environment["PP_SCRUB_HOVER"] ?? "") { hoverX = width * at }
            }
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.12), value: hoverX != nil || dragX != nil)
    }
}

/// The time to go, or with a click the length of the whole song, as in Spotify. Remembered.
struct RemainingTime: View {
    @Environment(PlayerModel.self) private var model
    @AppStorage("player.totalTime") private var total = false

    var body: some View {
        Text(total ? timeString(model.duration) : "-" + timeString(max(0, model.duration - model.position)))
            .contentShape(Rectangle())
            .onTapGesture { total.toggle() }
            .help(total ? "Show time left" : "Show song length")
    }
}

/// Position in one line, times on either side, for the player bar.
struct InlinePosition: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text(timeString(model.position)).frame(width: 36, alignment: .trailing)
            ScrubBar()
            RemainingTime().frame(width: 40, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// Shuffle, previous, play or pause, next, repeat: borderless buttons as in every Mac player.
struct TransportButtons: View {
    var large = false
    /// Shuffle and repeat on either side; left out where room is short.
    var modes = true
    /// Play in a filled round, white in dark and black in light, as in Spotify's bar.
    var roundPlay = false
    @Environment(PlayerModel.self) private var model

    var body: some View {
        // Spotify's set: single skip arrows with a bar, grey until the pointer is on them, shuffle and repeat green with a
        // dot under them while on.
        let size: CGFloat = large ? 22 : 15
        HStack(spacing: large ? 30 : 22) {
            if modes { TransportIcon(glyph: .shuffle, label: "Shuffle", size: size, on: model.shuffle) { model.shuffle.toggle() } }
            TransportIcon(glyph: .back, label: "Previous", size: size) { Playback.shared.previous() }
            Button { model.setPlaying(!model.isPlaying) } label: {
                if roundPlay {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PP.page)
                        .contentTransition(.opacity)
                        .frame(width: 32, height: 32)
                        // A solid colour: the text colour on glass is blended with what lies under it and came out grey.
                        .background(Circle().fill(PP.adaptive(0x000000, 0xFFFFFF)))
                } else {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: large ? 34 : 24))
                        // A quick swap, no bounce: the button answers at once.
                        .contentTransition(.opacity)
                        .frame(width: large ? 40 : 28)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(PressStyle())
            .help(model.isPlaying ? "Pause" : "Play")
            TransportIcon(glyph: .forward, label: "Next", size: size) { Playback.shared.next() }
            if modes { TransportIcon(glyph: .loop, label: "Repeat", size: size, on: model.repeatAll) { model.repeatAll.toggle() } }
        }
    }
}

enum TransportGlyph { case back, forward, loop, shuffle }

/// Lyrics, after Spotify's: a round head in outline and, joined to it on a slant, a slim handle in outline with a round end.
struct MicGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let side = min(rect.width, rect.height)
        let head = p(0.71, 0.29)
        let radius = side * 0.24
        let end = p(0.16, 0.84)
        let half = side * 0.125
        var path = Path()
        path.addEllipse(in: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2))
        // The handle's two sides start where they meet the head's outline and run to the round end.
        let dx = end.x - head.x, dy = end.y - head.y
        let length = sqrt(dx * dx + dy * dy)
        let ux = dx / length, uy = dy / length
        let nx = -uy, ny = ux
        let along = sqrt(max(0, radius * radius - half * half))
        for side in [1, -1] as [CGFloat] {
            path.move(to: CGPoint(x: head.x + ux * along + nx * half * side, y: head.y + uy * along + ny * half * side))
            path.addLine(to: CGPoint(x: end.x + nx * half * side, y: end.y + ny * half * side))
        }
        let angle = atan2(uy, ux)
        path.addArc(center: end, radius: half, startAngle: .radians(angle - .pi / 2), endAngle: .radians(angle + .pi / 2), clockwise: false)
        return path
    }
}

/// The drawn icons as template images, for menus, which only take pictures.
@MainActor
enum GlyphImage {
    static func make<S: Shape>(_ shape: S, size: CGSize, line: CGFloat) -> NSImage {
        let view = shape.stroke(Color.black, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            .frame(width: size.width, height: size.height)
            .padding(1)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: size)
        image.isTemplate = true
        return image
    }

    static let addToQueue = make(AddQueueGlyph(), size: CGSize(width: 15, height: 14), line: 1.3)
    static let listView = make(ViewModeGlyph(compact: false), size: CGSize(width: 15, height: 12), line: 1.5)
    static let compactView = make(ViewModeGlyph(compact: true), size: CGSize(width: 15, height: 12), line: 1.5)
}

/// A player icon by name: the drawn ones where the system symbol is too busy, else the symbol.
struct PlayerIconImage: View {
    let symbol: String
    let size: CGFloat
    var weight: Font.Weight = .medium

    var body: some View {
        if symbol == "music.mic" {
            MicGlyph()
                .stroke(style: StrokeStyle(lineWidth: max(1.3, size * 0.085), lineCap: .round, lineJoin: .round))
                .frame(width: size * 1.05, height: size * 1.05)
        } else if symbol == "list.bullet" {
            QueueGlyph()
                .stroke(style: StrokeStyle(lineWidth: max(1.3, size * 0.09), lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.95, height: size * 0.95)
        } else {
            Image(systemName: symbol).font(.system(size: size, weight: weight))
        }
    }
}

/// Shuffle, after Spotify's: two S-curves that cross, the one from the bottom left running over and the one from the top
/// left broken where it passes under, each ending in an arrowhead on the right. Laid out on a box a little wider than tall.
struct ShuffleGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let x = u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x
            let y = u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y
            return CGPoint(x: x, y: y)
        }
        let left: CGFloat = 0.05, bend: CGFloat = 0.12, join: CGFloat = 0.72, tip: CGFloat = 0.95
        let top: CGFloat = 0.17, bottom: CGFloat = 0.84
        var path = Path()
        // Over: bottom left to top right, in one piece.
        path.move(to: p(left, bottom))
        path.addLine(to: p(bend, bottom))
        path.addCurve(to: p(join, top), control1: p(0.36, bottom), control2: p(0.46, top))
        path.addLine(to: p(tip, top))
        // Under: top left to bottom right, open around the crossing.
        let a = p(bend, top), b = p(0.36, top), c = p(0.46, bottom), d = p(join, bottom)
        path.move(to: p(left, top))
        path.addLine(to: a)
        for step in 1...14 { path.addLine(to: cubic(a, b, c, d, 0.34 * CGFloat(step) / 14)) }
        path.move(to: cubic(a, b, c, d, 0.67))
        for step in 1...14 { path.addLine(to: cubic(a, b, c, d, 0.67 + 0.33 * CGFloat(step) / 14)) }
        path.addLine(to: p(tip, bottom))
        // Arrowheads.
        for y in [top, bottom] {
            path.move(to: p(tip - 0.17, y - 0.16))
            path.addLine(to: p(tip, y))
            path.addLine(to: p(tip - 0.17, y + 0.16))
        }
        return path
    }
}

/// Up Next, after Spotify's: a pill for the song that plays over two lines for what comes after.
struct QueueGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        let pill = CGRect(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.04,
                          width: rect.width * 0.92, height: rect.height * 0.27)
        path.addRoundedRect(in: pill, cornerSize: CGSize(width: pill.height / 2, height: pill.height / 2))
        for y in [0.645, 0.95] as [CGFloat] {
            path.move(to: p(0.02, y))
            path.addLine(to: p(0.98, y))
        }
        return path
    }
}

/// Add to queue, after Spotify's: a plus, a hook for the queue, and two lines.
struct AddQueueGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.04, 0.2)); path.addLine(to: p(0.34, 0.2))
        path.move(to: p(0.19, 0.05)); path.addLine(to: p(0.19, 0.35))
        let turn = rect.height * 0.12
        path.move(to: p(0.5, 0.11))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.96 - turn, y: rect.minY + rect.height * 0.11))
        path.addArc(center: CGPoint(x: rect.minX + rect.width * 0.96 - turn, y: rect.minY + rect.height * 0.23), radius: turn,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: p(0.5, 0.35))
        for y in [0.66, 0.97] as [CGFloat] {
            path.move(to: p(0.15, y))
            path.addLine(to: p(0.98, y))
        }
        return path
    }
}

/// The two ways a list of songs can look, for the View as menu: list rows with a mark in front, or plain compact lines.
struct ViewModeGlyph: Shape {
    var compact: Bool

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        for y in [0.15, 0.5, 0.85] as [CGFloat] {
            if compact {
                path.move(to: p(0.05, y)); path.addLine(to: p(0.95, y))
            } else {
                path.move(to: p(0.05, y)); path.addLine(to: p(0.17, y))
                path.move(to: p(0.38, y)); path.addLine(to: p(0.95, y))
            }
        }
        return path
    }
}

/// Previous or next: a triangle against a thin bar, with softly rounded corners.
struct SkipGlyph: Shape {
    var forward: Bool

    func path(in rect: CGRect) -> Path {
        let bar = max(1.6, rect.width * 0.15)
        let gap = rect.width * 0.04
        let tip = rect.width - bar - gap
        var path = Path()
        // Drawn pointing right, then mirrored for previous.
        let triangle = [CGPoint(x: 0, y: 0), CGPoint(x: tip, y: rect.height / 2), CGPoint(x: 0, y: rect.height)]
        path.addRoundedTriangle(triangle, radius: rect.width * 0.08)
        path.addRoundedRect(in: CGRect(x: rect.width - bar, y: 0, width: bar, height: rect.height),
                            cornerSize: CGSize(width: bar / 2, height: bar / 2))
        let flip = forward ? CGAffineTransform.identity : CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0)
        return path.applying(flip).applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// Repeat: a rounded, nearly square loop with an opening at the bottom, where an arrowhead points left into it, like
/// Spotify's.
struct LoopGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let head = rect.height * 0.2
        let box = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - head)
        let radius = box.height * 0.32
        let gapLeft = box.minX + box.width * 0.36
        let tip = box.minX + box.width * 0.5
        var path = Path()
        path.move(to: CGPoint(x: gapLeft, y: box.maxY))
        path.addArc(tangent1End: CGPoint(x: box.minX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: box.minX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.maxY), radius: radius)
        path.addLine(to: CGPoint(x: tip, y: box.maxY))
        path.move(to: CGPoint(x: tip + head, y: box.maxY - head))
        path.addLine(to: CGPoint(x: tip, y: box.maxY))
        path.addLine(to: CGPoint(x: tip + head, y: box.maxY + head))
        return path
    }
}

extension Path {
    /// A closed triangle whose corners are rounded with the given radius.
    mutating func addRoundedTriangle(_ points: [CGPoint], radius: CGFloat) {
        guard points.count == 3 else { return }
        let a = points[0], b = points[1], c = points[2]
        move(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2))
        addArc(tangent1End: a, tangent2End: b, radius: radius)
        addArc(tangent1End: b, tangent2End: c, radius: radius)
        addArc(tangent1End: c, tangent2End: a, radius: radius)
        closeSubpath()
    }
}

/// One of the small player buttons: grey, white under the pointer, and for shuffle and repeat green with a dot while on.
struct TransportIcon: View {
    var symbol = ""
    /// A drawn icon instead of a symbol: the system's skip bars are thick, and its repeat arrows sit off centre.
    var glyph: TransportGlyph? = nil
    let label: String
    let size: CGFloat
    /// Nil for a plain button; true or false for a mode that can be on.
    var on: Bool? = nil
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        let colour = on == true ? PP.primary : hovering ? PP.iconHover : PP.icon
        Button(action: action) {
            Group {
                switch glyph {
                case .back?, .forward?:
                    SkipGlyph(forward: glyph == .forward)
                        .fill(colour)
                        .frame(width: size * 0.82, height: size * 0.86)
                case .shuffle?:
                    ShuffleGlyph()
                        .stroke(colour, style: StrokeStyle(lineWidth: max(1.4, size * 0.1), lineCap: .round, lineJoin: .round))
                        .frame(width: size * 1.1, height: size * 0.96)
                case .loop?:
                    LoopGlyph()
                        .stroke(colour, style: StrokeStyle(lineWidth: max(1.4, size * 0.1), lineCap: .round, lineJoin: .round))
                        .frame(width: size * 1.05, height: size * 1.0)
                case nil:
                    Image(systemName: symbol)
                        .font(.system(size: size, weight: on == nil ? .regular : .medium))
                        .foregroundStyle(colour)
                }
            }
                .frame(width: size + 12, height: size + 12)
                .overlay(alignment: .bottom) {
                    if on == true {
                        Circle().fill(PP.primary).frame(width: 4, height: 4).offset(y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 && !Debug.active }
        .animation(Motion.fade, value: hovering)
        .help(label)
    }
}

/// Save the song that plays, as in Spotify: a plus that saves it to Liked Songs and opens the list of playlists, or a green
/// check when it is saved, which opens that list to change where.
struct LikeButton: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var showPlaylists = false

    var body: some View {
        let song = model.current
        let saved = model.likedIDs.contains(song.id) || Library.shared.inPlaylist(song)
        Button {
            guard !song.id.isEmpty else { return }
            if !saved { model.setLiked(song, true) }
            showPlaylists = true
        } label: {
            Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(saved ? AnyShapeStyle(PP.primary) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
        }
        .buttonStyle(PressStyle())
        .disabled(song.id.isEmpty)
        .help(saved ? "Saved. Change where" : "Save to Liked Songs")
        .popover(isPresented: $showPlaylists, arrowEdge: .top) { AddToPlaylistView(song: song) }
        .animation(.easeOut(duration: 0.15), value: saved)
    }
}

/// Volume with the system slider between a quiet and a loud speaker.
struct VolumeSlider: View {
    var width: CGFloat? = 100
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { model.groupVolume }, set: { model.groupVolume = $0 }), in: 0...100)
                .controlSize(.mini)
                .frame(width: width)
            Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
        }
        .help("Volume")
    }
}

/// Text that leads somewhere, like a link on the web: underlined and a pointing hand under the pointer.
struct LinkText: View {
    let text: String
    let action: () -> Void
    @LocalState private var hovering = false

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Text(text)
            .underline(hovering)
            .onHover { inside in
                hovering = inside && !Debug.active
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture(perform: action)
    }
}
