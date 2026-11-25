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
            Slider(value: Binding(get: { model.position }, set: { model.seek(to: $0) }), in: 0...max(1, model.duration))
                .controlSize(small ? .mini : .small)
            HStack {
                Text(timeString(model.position))
                Spacer()
                if showQuality { Text("44.1 kHz · 192 kbps · MP3") }
                Spacer()
                Text("-" + timeString(model.duration - model.position))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// Position in one line, times on either side, for the player bar.
struct InlinePosition: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text(timeString(model.position)).frame(width: 36, alignment: .trailing)
            Slider(value: Binding(get: { model.position }, set: { model.seek(to: $0) }), in: 0...max(1, model.duration))
                .controlSize(.mini)
            Text("-" + timeString(model.duration - model.position)).frame(width: 40, alignment: .leading)
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
                    .contentTransition(.symbolEffect(.replace))
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

struct LikeButton: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        Button { withAnimation(Motion.bouncy) { model.liked.toggle() } } label: {
            Image(systemName: model.liked ? "heart.fill" : "heart")
                .foregroundStyle(model.liked ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressStyle())
        .help(model.liked ? "Remove from Liked Songs" : "Liked Songs")
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
