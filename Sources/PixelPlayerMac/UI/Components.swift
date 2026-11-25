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
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: large ? 28 : 20) {
            if modes { toggle("shuffle", "Shuffle", on: model.shuffle) { model.shuffle.toggle() } }
            Button { Playback.shared.previous() } label: { Image(systemName: "backward.fill") }.help("Previous")
            Button { model.setPlaying(!model.isPlaying) } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: large ? 34 : 24))
                    // A quick swap, no bounce: the button answers at once.
                    .contentTransition(.opacity)
                    .frame(width: large ? 40 : 28)
            }
            .help(model.isPlaying ? "Pause" : "Play")
            Button { Playback.shared.next() } label: { Image(systemName: "forward.fill") }.help("Next")
            if modes { toggle("repeat", "Repeat", on: model.repeatAll) { model.repeatAll.toggle() } }
        }
        .font(large ? .title2 : .title3)
        .buttonStyle(PressStyle())
        .foregroundStyle(.primary)
    }

    private func toggle(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(large ? .title3 : .body)
                .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
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
