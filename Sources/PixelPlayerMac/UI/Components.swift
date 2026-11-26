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
            // The knob at the end of what played, while the pointer is over the bar or drags it, as in Spotify.
            .overlay(alignment: .leading) {
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: 12, height: 12)
                    .offset(x: played - 6)
                    .opacity(active ? 1 : 0)
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
                    // Spotify's proportions: the triangle 0.44 of the round high, a little right of the middle.
                    ZStack {
                        if model.isPlaying {
                            PauseGlyph().fill(PP.page).frame(width: 10.5, height: 12.5)
                        } else {
                            PlayGlyph().fill(PP.page).frame(width: 12.5, height: 14).offset(x: 1.1)
                        }
                    }
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

/// The drawn icons as template images, for menus, which only take pictures.
@MainActor
enum GlyphImage {
    static func make<V: View>(_ view: V, size: CGSize) -> NSImage {
        let renderer = ImageRenderer(content: view.foregroundStyle(Color.black).frame(width: size.width, height: size.height).padding(1))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: size)
        image.isTemplate = true
        return image
    }

    static let addToQueue = make(Glyph(kind: .addQueue), size: CGSize(width: 15, height: 14))
    static let listView = make(ViewModeGlyph(compact: false).stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .butt)), size: CGSize(width: 15, height: 12))
    static let compactView = make(ViewModeGlyph(compact: true).stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .butt)), size: CGSize(width: 15, height: 12))
}

/// A player icon by name: the drawn ones where the system symbol is too busy, else the symbol.
struct PlayerIconImage: View {
    let symbol: String
    let size: CGFloat
    var weight: Font.Weight = .medium

    var body: some View {
        if symbol == "music.mic" {
            Glyph(kind: .mic).sized(height: size * 1.05)
        } else if symbol == "hifispeaker" {
            Glyph(kind: .connect).sized(height: size * 0.95)
        } else if symbol == "list.bullet" {
            Glyph(kind: .queue).sized(height: size * 0.92)
        } else {
            Image(systemName: symbol).font(.system(size: size, weight: weight))
        }
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

/// Play in the round button, after Spotify's: a triangle with rounded corners, a little right of the middle.
struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedTriangle([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.maxY)],
                                radius: rect.width * 0.1)
        return path
    }
}

/// Pause in the round button: two bars with rounded corners.
struct PauseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bar = rect.width * 0.32
        let corner = CGSize(width: bar * 0.3, height: bar * 0.3)
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: bar, height: rect.height), cornerSize: corner)
        path.addRoundedRect(in: CGRect(x: rect.maxX - bar, y: rect.minY, width: bar, height: rect.height), cornerSize: corner)
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
                case .back?: Glyph(kind: .previous).sized(height: size * 0.8)
                case .forward?: Glyph(kind: .next).sized(height: size * 0.8)
                case .shuffle?: Glyph(kind: .shuffle).sized(height: size * 0.95)
                case .loop?: Glyph(kind: .loop).sized(height: size * 0.95)
                case nil:
                    Image(systemName: symbol)
                        .font(.system(size: size, weight: on == nil ? .regular : .medium))
                }
            }
                .foregroundStyle(colour)
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

/// The green bars Spotify shows on a tile that plays: four thin bars that move while the music plays and rest when it
/// pauses.
struct PlayingBars: View {
    var playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<4, id: \.self) { i in
                    // Each bar its own speed and phase, so they never move together.
                    let speeds = [5.1, 3.7, 6.3, 4.4], phases = [0.0, 1.3, 2.1, 0.7]
                    let level = playing ? 0.3 + 0.7 * (0.5 + 0.5 * sin(t * speeds[i] + phases[i])) : [0.35, 0.6, 0.25, 0.8][i]
                    Capsule(style: .continuous).fill(PP.primary).frame(width: 2.5, height: 3 + 11 * level)
                }
            }
            .frame(width: 14.5, height: 14, alignment: .bottom)
        }
        .accessibilityLabel(playing ? "Playing" : "Paused")
    }
}
