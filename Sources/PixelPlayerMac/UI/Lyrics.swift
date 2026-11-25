import SwiftUI
import PixelPlayerKit

/// The made-up lyrics of the design shots. Only the sample music shows them.
let sampleLyrics = [
    "The streetlights hum a quiet tune",
    "The city folds into the blue",
    "We wait between the day and night",
    "Two coffees going cold",
    "Your coat still on the chair",
    "The radio is low",
    "And everything is slow",
    "Stay a little longer",
    "Before the lights come on",
    "Here in the blue hour",
    "We don't need a song",
]

/// Where the lyrics of a song come from: a .lrc file beside the local file, the lyrics inside the file, or the server
/// (only read, never written). Looked up once per song while the app runs.
@MainActor
enum LyricsLoader {
    private static var known: [String: Lyrics?] = [:]

    static func lyrics(for song: Song) async -> Lyrics? {
        if let lyrics = known[song.id] { return lyrics }
        var found: Lyrics?
        if let file = song.source.localURL { found = await LocalLyrics.lyrics(for: file) }
        if found == nil, let id = song.source.serverID, let client = Library.shared.client {
            found = await fromServer(client, id: id, artist: song.artist, title: song.title)
        }
        known[song.id] = .some(found)
        return found
    }

    /// OpenSubsonic lyrics by song id first, then the older search by artist and title.
    nonisolated private static func fromServer(_ client: SubsonicClient, id: String, artist: String, title: String) async -> Lyrics? {
        if let list = try? await client.lyrics(songID: id), let lyrics = Lyrics(structured: list) { return lyrics }
        if let text = try? await client.lyrics(artist: artist, title: title).value {
            let lyrics = LRC.parse(text)
            if !lyrics.isEmpty { return lyrics }
        }
        return nil
    }
}

/// Lyrics in large type: the line sung now in full colour, the ones before it faded, the ones after it waiting.
/// Synced lyrics follow the song and keep the current line in view; plain lyrics are shown whole.
struct LyricsLines: View {
    var size: CGFloat = 40
    @Environment(PlayerModel.self) private var model
    @LocalState private var loaded: Loaded?
    /// Synced lyrics stay hidden until they are scrolled to the line sung now, so opening the panel never shows a jump.
    @LocalState private var placed = false

    private struct Loaded: Equatable {
        let songID: String
        let lyrics: Lyrics?
    }

    var body: some View {
        let song = model.current
        VStack(alignment: .leading, spacing: 0) {
            if Library.shared.isSample {
                lines(Lyrics(lines: sampleLyrics.map { Lyrics.Line(text: $0) }), current: 3, follow: false)
            } else if song.id.isEmpty {
                empty
            } else if let loaded, loaded.songID == song.id {
                if let lyrics = loaded.lyrics {
                    lines(lyrics, current: lyrics.index(at: model.position + 0.1), follow: lyrics.isSynced)
                } else {
                    empty
                }
            } else {
                // Still reading: nothing yet, rather than a flash of the empty state.
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: song.id) {
            guard !Library.shared.isSample, !song.id.isEmpty else { return }
            let lyrics = await LyricsLoader.lyrics(for: song)
            loaded = Loaded(songID: song.id, lyrics: lyrics)
        }
    }

    private var empty: some View {
        Text("No lyrics for this song")
            .font(.system(size: size * 0.6, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func lines(_ lyrics: Lyrics, current: Int?, follow: Bool) -> some View {
        // Plain lyrics have no line that is sung now: all of it reads in full colour.
        let plain = !lyrics.isSynced && current == nil
        return ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: size * 0.55) {
                if follow {
                    // Room above the first line, so before the singing starts it waits where the sung line will be,
                    // not at the very top.
                    Color.clear
                        .containerRelativeFrame(.vertical) { height, _ in max(0, height * 0.35 - size * 0.55) }
                        .id(-1)
                }
                ForEach(lyrics.lines.indices, id: \.self) { i in
                    LyricLine(line: lyrics.lines[i], size: size,
                              state: plain || i == current ? .now : i < (current ?? -1) ? .sung : .coming)
                        .id(i)
                }
            }
            .opacity(follow && !placed ? 0 : 1)
            .onAppear {
                guard follow else { placed = true; return }
                if let current { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.35)) } else { proxy.scrollTo(-1, anchor: .top) }
                // One turn later the scroll has landed; then the lines fade in where they belong.
                DispatchQueue.main.async { withAnimation(Motion.fade) { placed = true } }
            }
            .onChange(of: current) { _, line in
                guard follow else { return }
                withAnimation(Motion.panel) {
                    if let line { proxy.scrollTo(line, anchor: UnitPoint(x: 0, y: 0.35)) } else { proxy.scrollTo(-1, anchor: .top) }
                }
            }
        }
    }
}

/// One line of lyrics. A timed line is a place in the song: a click goes there, and under the pointer it lights up a little.
private struct LyricLine: View {
    enum State { case sung, now, coming }
    let line: Lyrics.Line
    let size: CGFloat
    let state: State
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        // A timed empty line is a pause in the singing.
        Text(line.text.isEmpty && line.time != nil ? "\u{266A}" : line.text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onHover { inside in
                guard line.time != nil, !Debug.active else { return }
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                guard let time = line.time else { return }
                model.seek(to: time)
                if !model.isPlaying { model.setPlaying(true) }
            }
            .animation(Motion.fade, value: hovering)
    }

    private var color: AnyShapeStyle {
        switch state {
        case .now: AnyShapeStyle(.primary)
        case .sung: hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
        case .coming: hovering ? AnyShapeStyle(Color.primary.opacity(0.8)) : AnyShapeStyle(.secondary)
        }
    }
}
