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

/// Lyrics: a plain microphone on a slant, a round head and a slim handle drawn as an outline, like Spotify's; the
/// outlined handle keeps it from reading as a magnifying glass.
struct MicGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let headRadius = w * 0.26
        let head = CGPoint(x: rect.minX + w * 0.7, y: rect.minY + h * 0.3)
        var path = Path()
        path.addEllipse(in: CGRect(x: head.x - headRadius, y: head.y - headRadius, width: headRadius * 2, height: headRadius * 2))
        // The handle: a slim rounded bar from the head down to the lower left, drawn along the x axis and turned.
        let handleWidth = w * 0.2
        let length = w * 0.62
        let bar = Path(roundedRect: CGRect(x: 0, y: -handleWidth / 2, width: length, height: handleWidth),
                       cornerSize: CGSize(width: handleWidth / 2, height: handleWidth / 2))
        let angle = CGFloat.pi * 0.75
        let start = CGPoint(x: head.x + cos(angle) * (headRadius - handleWidth * 0.3), y: head.y + sin(angle) * (headRadius - handleWidth * 0.3))
        path.addPath(bar, transform: CGAffineTransform(translationX: start.x, y: start.y).rotated(by: angle))
        return path
    }
}

/// A player icon by name: the drawn ones where the system symbol is too busy, else the symbol.
struct PlayerIconImage: View {
    let symbol: String
    let size: CGFloat
    var weight: Font.Weight = .medium

    var body: some View {
        if symbol == "music.mic" {
            MicGlyph()
                .stroke(style: StrokeStyle(lineWidth: max(1.4, size * 0.1), lineCap: .round, lineJoin: .round))
                .frame(width: size * 1.05, height: size * 1.05)
        } else {
            Image(systemName: symbol).font(.system(size: size, weight: weight))
        }
    }
}

/// Shuffle: two arrows that cross in a square, with a little gap in the one that runs under, like Spotify's.
struct ShuffleGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let head = rect.height * 0.24
        let top = rect.minY + head * 0.9
        let bottom = rect.maxY - head * 0.9
        let w = rect.width
        let bendLeft = rect.minX + w * 0.22, bendRight = rect.minX + w * 0.68
        func point(_ t: CGFloat, from a: CGPoint, to b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        var path = Path()
        // Over: from the top left down to the bottom right.
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: bendLeft, y: top))
        path.addLine(to: CGPoint(x: bendRight, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        // Under: from the bottom left up to the top right, open where it crosses.
        let start = CGPoint(x: bendLeft, y: bottom), end = CGPoint(x: bendRight, y: top)
        path.move(to: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: start)
        path.addLine(to: point(0.36, from: start, to: end))
        path.move(to: point(0.64, from: start, to: end))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        for y in [top, bottom] {
            path.move(to: CGPoint(x: rect.maxX - head, y: y - head))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - head, y: y + head))
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
                        .frame(width: size * 1.0, height: size * 1.0)
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
