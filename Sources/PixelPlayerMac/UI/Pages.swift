import SwiftUI
import Charts

/// What the detail column shows for the chosen page, built from the system's own views:
/// `Table` for songs, grids of covers, `GroupBox` and Swift Charts on Home.
struct PageContent: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        if !model.searchText.isEmpty {
            SearchResults(term: model.searchText)
        } else {
            switch model.page {
            case .home: HomePage()
            case .songs: SongTable(songs: Sample.songs.sorted { $0.title < $1.title })
            case .albums: CoverGrid { ForEach(Sample.albums) { AlbumCell(album: $0) } }
            case .artists: CoverGrid { ForEach(Sample.albums) { ArtistCell(album: $0) } }
            case .playlists: CoverGrid { ForEach(Sample.playlists) { PlaylistCell(list: $0) } }
            case .liked: SongTable(songs: Sample.liked)
            case .search: SearchResults(term: "blue")
            }
        }
    }
}

// MARK: Home

struct HomePage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 16) {
                    YourMix()
                    WeekBox().frame(width: 290)
                }
                .fixedSize(horizontal: false, vertical: true)
                Shelf(title: "Mixen voor jou") {
                    ForEach(Sample.mixes) { MixCell(mix: $0) }
                }
                Shelf(title: "Recent gespeeld") {
                    ForEach(Array((Sample.albums + Sample.albums.prefix(3)).enumerated()), id: \.offset) { AlbumCell(album: $0.element) }
                }
            }
            .padding(20)
        }
    }
}

struct YourMix: View {
    var body: some View {
        GroupBox {
            HStack(spacing: 18) {
                Collage(albums: [Sample.albums[0], Sample.albums[2], Sample.albums[4], Sample.albums[1]], radius: 8)
                    .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jouw mix").font(.largeTitle.weight(.bold))
                    Text("21 nummers, elke dag nieuw").foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Button("Afspelen", systemImage: "play.fill") {}.buttonStyle(.borderedProminent)
                        Button("Willekeurig", systemImage: "shuffle") {}.buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }
}

struct WeekBox: View {
    private let days = ["ma", "di", "wo", "do", "vr", "za", "zo"]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Deze week geluisterd").font(.headline)
                Text("6 u 49 m").font(.title.weight(.semibold)).monospacedDigit()
                Chart {
                    ForEach(Sample.week.indices, id: \.self) { i in
                        BarMark(x: .value("Dag", days[i]), y: .value("Minuten", Sample.week[i]), width: .ratio(0.55))
                            .foregroundStyle(i == 5 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.35)))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 56)
                Text("Meest geluisterd: Kestrel Bay").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled row of covers that fills the width it gets.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.weight(.bold))
                Spacer()
                Button("Alles bekijken") {}.buttonStyle(.link)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
                content
            }
        }
    }
}

struct CoverGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18, alignment: .top)], alignment: .leading, spacing: 20) {
                content
            }
            .padding(20)
        }
    }
}

struct AlbumCell: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(album: album, radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(album.title).fontWeight(.medium)
                Text(album.artist).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

struct ArtistCell: View {
    let album: Album

    var body: some View {
        VStack(spacing: 6) {
            CoverArt(album: album, radius: 0).clipShape(Circle())
            Text(album.artist).fontWeight(.medium).lineLimit(1)
        }
    }
}

struct MixCell: View {
    let mix: Mix

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Collage(albums: mix.covers + mix.covers.reversed(), radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(mix.title).fontWeight(.medium)
                Text(mix.subtitle).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

struct PlaylistCell: View {
    let list: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Collage(albums: list.songs.map(\.album), radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(list.title).fontWeight(.medium)
                Text("\(list.songs.count) nummers").foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

// MARK: Songs

struct SongTable: View {
    let songs: [Song]
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(songs, selection: $model.selectedSong) {
            TableColumn("") { (song: Song) in
                if song == model.current { NowPlayingMark() }
            }
            .width(16)
            TableColumn("Titel") { (song: Song) in
                HStack(spacing: 8) {
                    CoverArt(album: song.album, radius: 3).frame(width: 24, height: 24)
                    Text(song.title)
                }
            }
            .width(min: 180, ideal: 260)
            TableColumn("Artiest") { (song: Song) in Text(song.artist) }
            TableColumn("Album") { (song: Song) in Text(song.album.title) }
            TableColumn("Genre") { (song: Song) in Text(song.album.genre) }
                .width(min: 70, ideal: 100)
            TableColumn("Tijd") { (song: Song) in
                Text(song.duration).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(44)
        }
    }
}

// MARK: Search

struct SearchResults: View {
    let term: String

    private var songs: [Song] {
        Sample.songs.filter { [$0.title, $0.artist, $0.album.title].contains { $0.localizedCaseInsensitiveContains(term) } }
    }
    private var albums: [Album] {
        Sample.albums.filter { [$0.title, $0.artist].contains { $0.localizedCaseInsensitiveContains(term) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nummers").font(.title2.weight(.bold))
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(Array(songs.prefix(6).enumerated()), id: \.element.id) { index, song in
                                if index > 0 { Divider() }
                                HStack {
                                    SongLine(song: song, playing: song == Sample.nowPlaying)
                                    Text(song.duration).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                Shelf(title: "Albums") {
                    ForEach(albums) { AlbumCell(album: $0) }
                }
            }
            .padding(20)
        }
    }
}
