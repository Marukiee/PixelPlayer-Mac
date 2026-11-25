import SwiftUI
import Charts

/// One margin for every page, so headers, rows and shelves start on the same line.
private let margin: CGFloat = 28

struct RouteContent: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        if !model.searchText.isEmpty {
            SearchPage(term: model.searchText)
        } else {
            switch model.route {
            case .home:
                HomePage()
            case .search:
                SearchPage(term: "")
            case .songs:
                TrackListPage(header: TrackHeader(kind: "Library", title: "All Songs", meta: "1,284 songs · 81 h 12 m",
                                                  art: .songs, tint: Color(hex: 0x0058CA)),
                              songs: Sample.songs.sorted { $0.title < $1.title })
            case .liked:
                TrackListPage(header: TrackHeader(kind: "Playlist", title: "Liked Songs", meta: "141 songs · 9 h 12 m",
                                                  art: .liked, tint: Color(hex: 0x4B37D8)),
                              songs: Sample.liked)
            case .playlist(let id):
                let list = Sample.playlists.first { $0.id == id } ?? Sample.playlists[0]
                TrackListPage(header: TrackHeader(kind: "Playlist", title: list.title, meta: "\(list.songs.count) songs",
                                                  art: .collage(list.songs.map(\.album)), tint: Color(hex: list.songs[0].album.tint)),
                              songs: list.songs)
            case .album(let id):
                let album = Sample.albums.first { $0.id == id } ?? Sample.albums[0]
                let songs = Sample.songs.filter { $0.album == album }
                TrackListPage(header: TrackHeader(kind: "Album", title: album.title, meta: "\(album.artist) · \(album.year) · \(songs.count) songs",
                                                  art: .album(album), tint: Color(hex: album.tint)),
                              songs: songs, showAlbum: false, showAdded: false, showCover: false, showSort: false,
                              more: Sample.albums.filter { $0 != album })
            case .artist(let id):
                let album = Sample.albums.first { $0.id == id } ?? Sample.albums[0]
                TrackListPage(header: TrackHeader(kind: "Artist", title: album.artist, meta: "\(album.genre) · 1 album",
                                                  art: .artist(album), tint: Color(hex: album.tint)),
                              songs: Sample.songs.filter { $0.artist == album.artist }, showAdded: false,
                              more: Sample.albums.filter { $0 != album })
            }
        }
    }
}

// MARK: Home

struct HomePage: View {
    @LocalState private var width: CGFloat = 900

    private var quick: [LibraryItem] {
        let all = LibraryItem.all
        return [all[0], all[3], all[1], all[2], all[5], all[4], all[8], all[6]]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                MixHero()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: width > 760 ? 4 : 2), spacing: 12) {
                    ForEach(quick) { QuickTile(item: $0) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                Shelf(title: "Mixes for you") {
                    FittingRow(items: Sample.mixes, minWidth: 160) { mix in
                        CoverCell(art: .collage(mix.covers + mix.covers.reversed()), title: mix.title, subtitle: mix.subtitle)
                    }
                }
                Shelf(title: "Recently played") {
                    FittingRow(items: Array(Sample.albums.enumerated()), minWidth: 160) { pair in
                        if pair.offset % 3 == 2 {
                            CoverCell(art: .artist(pair.element), title: pair.element.artist, subtitle: "Artist", round: true)
                        } else {
                            CoverCell(art: .album(pair.element), title: pair.element.title, subtitle: pair.element.artist)
                        }
                    }
                }
                WeekCard()
            }
            .padding(.horizontal, margin)
            .padding(.top, margin)
            .padding(.bottom, 24)
        }
        // The same margin above as at the sides, whatever the title bar's safe area is at that moment.
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Your Mix across the whole width, so nothing beside it has to match its height.
struct MixHero: View {
    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            Collage(albums: [Sample.albums[0], Sample.albums[2], Sample.albums[4], Sample.albums[1]], radius: 8)
                .frame(width: 184, height: 184)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text("Made for you").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                Text("Your Mix").font(.system(size: 52, weight: .heavy)).foregroundStyle(.white)
                Text("Blue Hour, Night Signal, Orbit and 18 more").foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    PlayCircle()
                    RoundButton(symbol: "shuffle", label: "Shuffle")
                    RoundMenu()
                }
            }
            .frame(height: 184)
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(LinearGradient(colors: [Color(hex: 0x23408F), Color(hex: 0x5B2A86)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The big round play button: the system's prominent glass button.
struct PlayCircle: View {
    var body: some View { RoundButton(symbol: "play.fill", label: "Play", prominent: true) }
}

/// Round glass buttons that stand together are one size (56): play in the accent, shuffle and more neutral,
/// so they read as one set.
struct RoundButton: View {
    let symbol: String
    let label: String
    var prominent = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            RoundIcon(symbol: symbol, prominent: prominent)
        }
        .buttonStyle(.plain)
        .glassEffect(prominent ? .regular.tint(PP.primary).interactive() : .regular.interactive(), in: Circle())
        .help(label)
    }
}

struct RoundIcon: View {
    let symbol: String
    var prominent = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(PP.onPrimary) : AnyShapeStyle(.primary))
            .frame(width: 56, height: 56)
            .contentShape(Circle())
    }
}

/// More actions, in the same round glass button.
struct RoundMenu: View {
    var body: some View {
        Menu {
            Button("Add to queue", systemImage: "text.line.first.and.arrowtriangle.forward") {}
            Button("Share", systemImage: "square.and.arrow.up") {}
        } label: {
            RoundIcon(symbol: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: Circle())
        .help("More")
    }
}

/// A small tile with the cover flush left, so its corners follow the tile.
struct QuickTile: View {
    let item: LibraryItem
    @LocalState private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(art: item.art, radius: 0)
                .frame(width: 56, height: 56)
                .clipShape(item.kind == .artists ? AnyShape(Circle().inset(by: 4)) : AnyShape(Rectangle()))
            Text(item.title).fontWeight(.semibold).lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 56)
        .background(Color.primary.opacity(hovering ? 0.1 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering = $0 && !Debug.active }
        .animation(Motion.fade, value: hovering)
    }
}

struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.weight(.bold))
                Spacer()
                Button("Show all") {}.buttonStyle(.link)
            }
            content
        }
    }
}

/// One row of equal cells: as many as fit at their smallest width, never a half row.
struct FittingRow<Item, Cell: View>: View {
    let items: [Item]
    let minWidth: CGFloat
    var spacing: CGFloat = 20
    @ViewBuilder let cell: (Item) -> Cell
    @LocalState private var width: CGFloat = 800

    var body: some View {
        let columns = max(1, Int((width + spacing) / (minWidth + spacing)))
        let cellWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<min(items.count, columns), id: \.self) { index in
                cell(items[index]).frame(width: cellWidth, alignment: .leading)
            }
        }
        // Never ask for more room than the column has, or the sidebar gets pushed shut.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

struct CoverCell: View {
    let art: Artwork
    let title: String
    let subtitle: String
    var round = false

    var body: some View {
        VStack(alignment: round ? .center : .leading, spacing: 8) {
            ArtworkView(art: art, radius: 6)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            VStack(alignment: round ? .center : .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

/// This week's listening in one card across the width.
struct WeekCard: View {
    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Listened this week").font(.headline)
                Text("6 h 49 m").font(.system(size: 34, weight: .bold)).monospacedDigit()
                Text("12% more than last week").font(.callout).foregroundStyle(.secondary)
            }
            .frame(width: 210, alignment: .leading)
            Chart {
                ForEach(Sample.week.indices, id: \.self) { i in
                    BarMark(x: .value("Day", days[i]), y: .value("Minutes", Sample.week[i]), width: .ratio(0.5))
                        .foregroundStyle(i == 5 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .chartYAxis(.hidden)
            .frame(minWidth: 60)
            .frame(height: 96)
            VStack(spacing: 6) {
                ArtworkView(art: .artist(Sample.albums[0])).frame(width: 64, height: 64)
                Text("Kestrel Bay").fontWeight(.semibold)
                Text("Most played").font(.callout).foregroundStyle(.secondary)
            }
            .frame(width: 130)
        }
        .padding(20)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: Lists of songs

struct TrackHeader {
    let kind: String
    let title: String
    let meta: String
    let art: Artwork
    let tint: Color
}

/// A playlist, album or artist: a large header in the colour of its cover, then roomy rows.
struct TrackListPage: View {
    let header: TrackHeader
    let songs: [Song]
    var showAlbum = true
    var showAdded = true
    var showCover = true
    var showSort = true
    /// Albums to show under the songs, so a short album does not leave the page empty.
    var more: [Album] = []
    @LocalState private var width: CGFloat = 900

    var body: some View {
        let wide = width > 760
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 24) {
                    ArtworkView(art: header.art, radius: 8)
                        .frame(width: 200, height: 200)
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(header.kind).font(.subheadline.weight(.semibold))
                        Text(header.title).font(.system(size: 60, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.5)
                        Text(header.meta).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, margin)
                .padding(.top, margin)
                HStack(spacing: 12) {
                    PlayCircle()
                    RoundButton(symbol: "shuffle", label: "Shuffle")
                    RoundMenu()
                    Spacer()
                    if showSort {
                        Menu("Recently added") {
                            Button("Title") {}
                            Button("Artist") {}
                            Button("Album") {}
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        // The menu has its own inset; this puts its edge on the duration column below.
                        .padding(.trailing, -6)
                    }
                }
                .padding(.horizontal, margin)
                .padding(.vertical, 24)
                TrackColumns(showAlbum: showAlbum, showAdded: showAdded && wide)
                    .padding(.horizontal, margin - 12)
                Divider()
                    .padding(.horizontal, margin)
                    .padding(.bottom, 8)
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(index: index + 1, song: song, showAlbum: showAlbum, showAdded: showAdded && wide, showCover: showCover)
                    }
                }
                .padding(.horizontal, margin - 12)
                if !more.isEmpty {
                    Shelf(title: "More like this") {
                        FittingRow(items: more, minWidth: 160) { album in
                            CoverCell(art: .album(album), title: album.title, subtitle: album.artist)
                        }
                    }
                    .padding(.horizontal, margin)
                    .padding(.top, 36)
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(alignment: .top) {
            LinearGradient(colors: [header.tint.opacity(0.55), header.tint.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 440)
                .ignoresSafeArea()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The same frames as `TrackRow`, so every title sits above its column.
struct TrackColumns: View {
    var showAlbum = true
    var showAdded = true

    var body: some View {
        HStack(spacing: 16) {
            Text("#").frame(width: 24)
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            if showAlbum { Text("Album").frame(maxWidth: .infinity, alignment: .leading) }
            if showAdded { Text("Date added").frame(width: 130, alignment: .leading) }
            Image(systemName: "clock").frame(width: 44, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}

struct TrackRow: View {
    let index: Int
    let song: Song
    var showAlbum = true
    var showAdded = true
    var showCover = true
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        let playing = song == model.current
        HStack(spacing: 16) {
            ZStack {
                if playing {
                    NowPlayingMark()
                } else if hovering {
                    Image(systemName: "play.fill").font(.callout)
                } else {
                    Text("\(index)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 24)
            HStack(spacing: 12) {
                if showCover { CoverArt(album: song.album, radius: 4).frame(width: 40, height: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    Text(song.artist).font(.callout).foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showAlbum {
                Text(song.album.title).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showAdded {
                Text(song.added).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: 130, alignment: .leading)
            }
            Text(song.duration).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 && !Debug.active }
        .animation(Motion.fade, value: hovering)
    }
}

// MARK: Search

struct SearchPage: View {
    let term: String

    private var songs: [Song] {
        Sample.songs.filter { [$0.title, $0.artist, $0.album.title].contains { $0.localizedCaseInsensitiveContains(term) } }
    }
    private var albums: [Album] {
        Sample.albums.filter { [$0.title, $0.artist].contains { $0.localizedCaseInsensitiveContains(term) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if term.isEmpty { browse } else { results }
            }
            .padding(.horizontal, margin)
            .padding(.top, margin)
            .padding(.bottom, 24)
        }
        // The same margin above as at the sides, whatever the title bar's safe area is at that moment.
        .ignoresSafeArea(.container, edges: .top)
    }

    private var genres: [Album] {
        var seen = Set<String>()
        return Sample.albums.filter { seen.insert($0.genre).inserted }
    }

    private let moods: [(String, Int)] = [("Focus", 6), ("Late Night", 0), ("Sunday Morning", 3), ("Rainy Days", 7)]

    private var browse: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Browse").font(.title2.weight(.bold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(genres) { album in BrowseTile(title: album.genre, album: album) }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Moods").font(.title2.weight(.bold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(moods, id: \.0) { mood in BrowseTile(title: mood.0, album: Sample.albums[mood.1]) }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Top result").font(.title2.weight(.bold))
                if let album = albums.first {
                    // Fits the four song rows beside it exactly: 20 + 96 + space + 56 + 20 within 224.
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 16) {
                            CoverArt(album: album, radius: 6).frame(width: 96, height: 96)
                                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(album.title).font(.title2.weight(.bold)).lineLimit(2)
                                Text("Album · \(album.artist)").foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            PlayCircle()
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 224)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(width: 320)
            VStack(alignment: .leading, spacing: 14) {
                Text("Songs").font(.title2.weight(.bold))
                VStack(spacing: 0) {
                    ForEach(Array(songs.prefix(4).enumerated()), id: \.element.id) { index, song in
                        TrackRow(index: index + 1, song: song, showAlbum: false, showAdded: false)
                    }
                }
                .frame(height: 224, alignment: .top)
            }
        }
        Shelf(title: "Albums") {
            FittingRow(items: albums, minWidth: 160) { album in
                CoverCell(art: .album(album), title: album.title, subtitle: "\(album.year) · \(album.artist)")
            }
        }
    }
}

/// A coloured tile with its cover tipped into the corner, for genres and moods.
struct BrowseTile: View {
    let title: String
    let album: Album

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: album.tint)
            CoverArt(album: album, radius: 6)
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(22))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 14, y: 10)
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.white).padding(16)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
