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
                    lines(lyrics, current: lyrics.index(at: model.position), follow: lyrics.isSynced)
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
                ForEach(lyrics.lines.indices, id: \.self) { i in
                    // A timed empty line is a pause in the singing.
                    Text(lyrics.lines[i].text.isEmpty && lyrics.lines[i].time != nil ? "\u{266A}" : lyrics.lines[i].text)
                        .font(.system(size: size, weight: .bold))
                        .foregroundStyle(plain || i == current ? AnyShapeStyle(.primary)
                                         : i < (current ?? -1) ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .id(i)
                }
            }
            .onAppear { if follow, let current { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.35)) } }
            .onChange(of: current) { _, line in
                guard follow else { return }
                withAnimation(Motion.panel) { proxy.scrollTo(line ?? 0, anchor: line == nil ? .top : UnitPoint(x: 0, y: 0.35)) }
            }
        }
    }
}
