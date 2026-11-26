import SwiftUI
import Charts
import PixelPlayerKit

/// One margin for every page, so headers, rows and shelves start on the same line.
private let margin: CGFloat = 28

struct RouteContent: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        if !Library.shared.hasMusic {
            ConnectPage()
        } else if !model.searchText.isEmpty {
            SearchPage(term: model.searchText)
        } else {
            switch model.route {
            case .home:
                HomePage()
            case .search:
                SearchPage(term: "")
            case .songs:
                TrackListPage(header: TrackHeader(kind: "Library", title: "All Songs", meta: Library.shared.isSample ? "1,284 songs, 81 hr 12 min" : Library.summary(Library.shared.songs),
                                                  art: .songs, tint: Color(hex: 0x0058CA)),
                              songs: Library.shared.songs, firstOrder: .title)
            case .liked:
                TrackListPage(header: TrackHeader(kind: "Playlist", title: "Liked Songs", meta: Library.shared.isSample ? "141 songs, 9 hr 12 min" : Library.summary(Library.shared.liked),
                                                  art: .liked, tint: Color(hex: 0x5038A0)),
                              songs: Library.shared.liked, share: "Liked Songs")
            case .playlist(let id):
                let list = Library.shared.playlists.first { $0.id == id } ?? Playlist(id: id, title: "Playlist", songs: [])
                TrackListPage(header: TrackHeader(kind: "Playlist", title: list.title, meta: Library.summary(list.songs),
                                                  art: .collage(list.songs.map(\.album)), tint: Color(hex: list.songs.first?.album.tint ?? 0x23408F)),
                              songs: list.songs, orders: TrackOrder.allCases, firstOrder: .custom, share: list.title)
            case .album(let id):
                let album = Library.shared.albums.first { $0.id == id } ?? Library.shared.songs.first { $0.album.id == id }?.album
                    ?? Library.shared.album(at: 0)
                let songs = Library.shared.songs(for: .album(album.id))
                TrackListPage(header: TrackHeader(kind: "Album", title: album.title,
                                                  meta: [album.year > 0 ? String(album.year) : "", Library.summary(songs)].filter { !$0.isEmpty }.joined(separator: " • "),
                                                  art: .album(album), tint: Color(hex: album.tint), artist: album.artist),
                              songs: songs, showAlbum: false, showAdded: false, showCover: false, showSort: false, share: "\(album.title) by \(album.artist)",
                              more: Shelves.items("more-album:\(album.id)"), moreRoute: .shelf("more-album:\(album.id)"))
            case .artist(let name) where !Library.shared.isSample:
                ArtistPage(name: name)
            case .artist(let name):
                // The name is the artist's own, also when no album has it as album artist; the cover comes from their songs.
                let album = Library.shared.albums.first { $0.artist == name } ?? Library.shared.songs.first { $0.artist == name }?.album
                    ?? Library.shared.album(at: 0)
                let albumCount = Set(Library.shared.songs(for: .artist(name)).map(\.album.id)).count
                TrackListPage(header: TrackHeader(kind: "Artist", title: name,
                                                  meta: [album.genre, albumCount == 1 ? "1 album" : "\(albumCount) albums"].filter { !$0.isEmpty }.joined(separator: " · "),
                                                  art: .artist(album), tint: Color(hex: album.tint)),
                              songs: Library.shared.songs(for: .artist(name)), showAdded: false, firstOrder: .album, share: album.artist,
                              more: Shelves.items("more-artist:\(name)"), moreRoute: .shelf("more-artist:\(name)"))
            case .genre(let name):
                let songs = Library.shared.songs(for: .genre(name))
                let album = songs.first?.album ?? Library.shared.album(at: 0)
                TrackListPage(header: TrackHeader(kind: "Genre", title: name, meta: Library.summary(songs),
                                                  art: .collage(Array(Set(songs.map(\.album))).prefix(4).map { $0 }), tint: Color(hex: album.tint)),
                              songs: songs, share: name)
            case .mix(let id):
                let mix = Library.shared.mixes.first { $0.id == id }
                let songs = mix.map { Library.shared.songs(for: $0) } ?? []
                TrackListPage(header: TrackHeader(kind: "Mix", title: mix?.title ?? "Mix",
                                                  meta: [mix?.subtitle ?? "", Library.summary(songs)].filter { !$0.isEmpty }.joined(separator: " • "),
                                                  art: .collage((mix?.covers ?? []) + (mix?.covers.reversed() ?? [])),
                                                  tint: Color(hex: mix?.covers.first?.tint ?? 0x23408F)),
                              songs: songs, share: mix?.title)
            case .shelf(let key):
                ShelfPage(key: key)
            }
        }
    }
}

// MARK: Home

struct HomePage: View {
    @LocalState private var width: CGFloat = 900

    private var quick: [LibraryItem] {
        // Always a full grid: the first eight things of the library, never a fixed position that may not exist.
        Array(LibraryItem.all.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                MixHeader()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: width > 940 ? 4 : 2), spacing: 8) {
                    ForEach(quick) { QuickTile(item: $0) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                // A shelf with nothing on it is left out.
                if !Shelves.items("mixes").isEmpty {
                    Shelf(title: Shelves.title("mixes"), showAll: .shelf("mixes")) {
                        FittingRow(items: Shelves.items("mixes"), minWidth: 160) { ShelfCell(item: $0) }
                    }
                }
                if !Shelves.items("recent").isEmpty {
                    Shelf(title: Shelves.title("recent"), showAll: .shelf("recent")) {
                        FittingRow(items: Shelves.items("recent"), minWidth: 160) { ShelfCell(item: $0) }
                    }
                }
                // Listening time is only known for the sample music so far.
                if Library.shared.isSample { WeekCard() }
            }
            .padding(.horizontal, margin)
            .padding(.top, margin)
            .padding(.bottom, 24)
            // The covers' colour behind the top of the page, edge to edge, fading into it.
            .background(alignment: .top) { MixWash().frame(height: 380) }
        }
        // The same margin above as at the sides, whatever the title bar's safe area is at that moment.
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// The big round play button, in Spotify's green. With a list name it turns into pause while that list plays.
struct PlayCircle: View {
    var title: String = ""
    var songs: (() -> [Song])? = nil
    var action: () -> Void = {}
    @Environment(PlayerModel.self) private var model

    var body: some View {
        let active = songs.map { model.isPlaying(from: title, songs: $0) } ?? false
        GreenPlayButton(size: 56, playing: active && model.isPlaying, label: title.isEmpty ? "Play" : title) {
            if let songs { model.togglePlay(from: title, songs: songs) } else { action() }
        }
    }
}

/// Spotify's play button: a solid green round with a black play or pause, a little larger under the pointer.
struct GreenPlayButton: View {
    let size: CGFloat
    var playing = false
    var label = "Play"
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            // SpotCopy's green-button triangle from Android, a little right of the middle; pause as two bars.
            ZStack {
                if playing {
                    PauseGlyph().frame(width: size * 0.25, height: size * 0.32)
                } else {
                    SpotifyIcon(name: "play_green").fill(style: FillStyle(eoFill: true))
                        .frame(width: size * 0.32 * 39 / 45, height: size * 0.32).offset(x: size * 0.02)
                }
            }
                .foregroundStyle(PP.onPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(Circle().fill(PP.primary))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help(playing ? "Pause \(label)" : "Play \(label)")
    }
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
        .hoverLift(scale: 1.06)
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
    /// The songs the menu acts on, and the line that is shared.
    var songs: [Song] = []
    var share: String? = nil
    /// On a coloured header (Your Mix): white instead of the text colour.
    var onColour = false
    @LocalState private var hovering = false

    var body: some View {
        Menu {
            Button("Add to queue", systemImage: "text.line.first.and.arrowtriangle.forward") { PlayerModel.shared.userQueue.append(contentsOf: songs) }
                .disabled(songs.isEmpty)
            if let share {
                Button("Share", systemImage: "square.and.arrow.up") { Share.text(share) }
            }
        } label: {
            PlainIcon(symbol: "ellipsis", hovering: hovering, onColour: onColour)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 && !Debug.active }
        .help("More")
    }
}

/// Shuffle and more beside the big play button, as in Spotify: just the symbol, no circle, lighter under the pointer.
struct PlainIconButton: View {
    let symbol: String
    let label: String
    var onColour = false
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) { PlainIcon(symbol: symbol, hovering: hovering, onColour: onColour) }
            .buttonStyle(PressStyle())
            .onHover { hovering = $0 && !Debug.active }
            .help(label)
    }
}

/// Shuffle on a list, as in Spotify and SpotCopy: a switch for shuffle, green with a dot under it while on and this list
/// plays. The dot hangs below the icon, so the icon stays exactly where it is.
struct ShuffleToggle: View {
    let on: Bool
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        Button { model.shuffle.toggle() } label: {
            Glyph(kind: .shuffle).sized(height: 24)
                .foregroundStyle(on ? AnyShapeStyle(PP.primary) : AnyShapeStyle(hovering ? PP.iconHover : PP.icon))
                .overlay(alignment: .bottom) {
                    Circle().fill(PP.primary).frame(width: 4, height: 4).offset(y: 9).opacity(on ? 1 : 0)
                }
                .frame(width: 44, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: on)
        .animation(Motion.fade, value: hovering)
        .help(model.shuffle ? "Disable shuffle" : "Enable shuffle")
    }
}

struct PlainIcon: View {
    let symbol: String
    let hovering: Bool
    var onColour = false

    var body: some View {
        let style = onColour ? AnyShapeStyle(.white.opacity(hovering ? 1 : 0.75)) : (hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        Group {
            if symbol == "shuffle" {
                // The same drawn shuffle as in the player: square, with a fine line, like Spotify's.
                Glyph(kind: .shuffle).sized(height: 24).foregroundStyle(style)
            } else {
                PlayerIconImage(symbol: symbol, size: 26).foregroundStyle(style)
            }
        }
            .frame(width: 44, height: 56)
            .contentShape(Rectangle())
            .animation(Motion.fade, value: hovering)
    }
}

/// A small tile with the cover flush left, so its corners follow the tile.
struct QuickTile: View {
    let item: LibraryItem
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    /// Spotify's shortcut tiles, measured on Mark's screenshots side by side: 47 high with the cover square and flush (artists
    /// too), the title bold, a lighter grey than the page, a small corner. While it plays: green bars, the button on hover.
    var body: some View {
        let active = model.isPlaying(from: item.title) { Library.shared.songs(for: item.route) }
        HStack(spacing: 8) {
            // Square for an artist too, as Spotify's shortcuts are.
            Group {
                if case .artist(let album) = item.art { CoverArt(album: album, radius: 0) } else { ArtworkView(art: item.art, radius: 0) }
            }
                .frame(width: 47, height: 47)
            Text(item.title).font(.mix(14, .bold)).lineLimit(2)
            Spacer(minLength: 10)
        }
        // The play button lies over the end of the tile, so the title has the whole width when it is not shown.
        .overlay(alignment: .trailing) {
            ZStack {
                PlayingBars(playing: model.isPlaying)
                    .opacity(active && !hovering ? 1 : 0)
                GreenPlayButton(size: 31, playing: active && model.isPlaying, label: item.title) {
                    model.togglePlay(from: item.title) { Library.shared.songs(for: item.route) }
                }
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
            .padding(.trailing, 8)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 47)
        .background(Color.primary.opacity(hovering ? 0.2 : 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        // A click on the tile opens it; the play button plays it.
        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onTapGesture { model.go(item.route) }
        .onHover { hovering = $0 && !Debug.active }
        .onAppear { if Debug.hovered(item.title) { hovering = true } }
        .animation(Motion.fade, value: hovering)
    }
}

/// "Show all" as in Spotify: grey and bold, white with an underline under the pointer. Not the system's blue link.
struct ShowAllButton: View {
    var title = "Show all"
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.mix(14, .bold))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
    }
}

struct Shelf<Content: View>: View {
    let title: String
    /// The page with everything on the shelf.
    var showAll: Route? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).titleFont(24)
                Spacer()
                if let showAll {
                    ShowAllButton { PlayerModel.shared.go(showAll) }
                }
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
    /// The songs the play button plays; no button without them.
    var songs: (() -> [Song])? = nil
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        // While this plays, the button stays on the cover as a pause button, as in Spotify.
        let active = songs.map { model.isPlaying(from: title, songs: $0) } ?? false
        let showButton = hovering || active
        VStack(alignment: round ? .center : .leading, spacing: 8) {
            ArtworkView(art: art, radius: 6)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    if let songs {
                        GreenPlayButton(size: 46, playing: active && model.isPlaying, label: title) {
                            model.togglePlay(from: title, songs: songs)
                        }
                        .padding(10)
                        .opacity(showButton ? 1 : 0)
                        .offset(y: showButton ? 0 : 8)
                        .allowsHitTesting(showButton)
                        .animation(Motion.card, value: showButton)
                    }
                }
            VStack(alignment: round ? .center : .leading, spacing: 2) {
                Text(title).font(.mix(16))
                Text(subtitle).font(.mix(14)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        // A grey card around cover and text on hover, as in Spotify. It reaches 10 past the edges, so the grid stays put.
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0))
        }
        .padding(-10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 && !Debug.active }
        .onAppear { if Debug.hovered(title) { hovering = true } }
    }
}

/// This week's listening in one card across the width.
struct WeekCard: View {
    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Listened this week").font(.mix(16, .bold))
                Text("6 h 49 m").titleFont(32)
                Text("12% more than last week").font(.mix(14)).foregroundStyle(.secondary)
            }
            .frame(width: 210, alignment: .leading)
            Chart {
                ForEach(Library.shared.week.indices, id: \.self) { i in
                    BarMark(x: .value("Day", days[i]), y: .value("Minutes", Library.shared.week[i]), width: .ratio(0.5))
                        .foregroundStyle(i == 5 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .chartYAxis(.hidden)
            .frame(minWidth: 60)
            .frame(height: 96)
            VStack(spacing: 6) {
                ArtworkView(art: .artist(Library.shared.album(at: 0))).frame(width: 64, height: 64)
                Text("Kestrel Bay").font(.mix(16))
                Text("Most played").font(.mix(14)).foregroundStyle(.secondary)
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
    /// A name at the start of the meta line that opens its artist, as on an album page.
    var artist: String? = nil
}

/// Whose music this is, for the lists the app makes ("Made for Mark"), as Spotify and SpotCopy name them. SpotCopy asks at
/// the first start; the Mac knows the name of whoever is logged in.
@MainActor
enum Owner {
    /// Never a name in the code: the Navidrome account's, otherwise the first name of this Mac's user.
    static var firstName: String {
        if let set = UserDefaults.standard.string(forKey: "owner.name"), !set.isEmpty { return set }
        if let account = Library.shared.account { return account.firstName }
        return NSFullUserName().split(separator: " ").first.map(String.init) ?? "you"
    }
}

/// "1 song", "12 songs".
func songCount(_ count: Int) -> String { count == 1 ? "1 song" : "\(count.formatted()) songs" }

/// A playlist, album or artist: a large header in the colour of its cover, then roomy rows.
struct TrackListPage: View {
    let header: TrackHeader
    let songs: [Song]
    var showAlbum = true
    var showAdded = true
    var showCover = true
    var showSort = true
    /// The orders the sort menu offers, and the one the page opens in.
    var orders: [TrackOrder] = [.added, .title, .artist, .album]
    var firstOrder: TrackOrder = .added
    /// The line Share sends; no Share without it.
    var share: String? = nil
    /// Albums to show under the songs, so a short album does not leave the page empty.
    var more: [ShelfItem] = []
    var moreRoute: Route? = nil
    @Environment(PlayerModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @LocalState private var width: CGFloat = 900
    /// List rows with covers, or compact lines without them (View as, as in Spotify). Remembered for every list.
    @AppStorage("tracks.view") private var viewMode = "list"
    /// A genre chip that filters the list, and the search in it, as on Spotify's Liked Songs.
    @LocalState private var genre: String?
    @LocalState private var filterText = ""
    @LocalState private var searching = false

    var body: some View {
        let wide = width > 760
        let compact = viewMode == "compact"
        let order = model.trackOrders[model.route] ?? firstOrder
        let reversed = model.trackReversed[model.route] ?? false
        let sorted = showSort ? order.sorted(self.songs, reversed: reversed, fields: \.orderFields) : self.songs
        // What a genre chip and the search leave of it; play and shuffle take that part, as on Spotify.
        let songs = sorted.filter { song in
            (genre.map { song.genres.contains($0) } ?? true) && (filterText.isEmpty || song.matches(filterText))
        }
        // As on Spotify, the cover grows with the page, at the size Mark sees Spotify: his runs zoomed to three quarters, so
        // its 128 to 232 pixels are 96 to 174 points here (measured against his screenshots side by side).
        let zoom: CGFloat = 0.75
        let cover = zoom * min(232, max(128, 128 + (width / zoom - 600) / 424 * 104))
        // Spotify's capitals are three tenths of the cover high.
        let titleSize = (cover * 0.302 / TitleFont.capHeight).rounded()
        let dark = colorScheme == .dark
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 18) {
                    ArtworkView(art: header.art, radius: 4)
                        .frame(width: cover, height: cover)
                        // One shadow for the whole cover, not one for the heart on it as well.
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 4)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(header.kind).font(.mix(14))
                        TitleFont.text(header.title, size: titleSize)
                            .lineLimit(1).minimumScaleFactor(0.4)
                            .padding(.top, 2)
                        HStack(spacing: 0) {
                            if let artist = header.artist {
                                LinkText(artist) { PlayerModel.shared.go(.artist(artist)) }.font(.mix(14, .bold))
                                    .foregroundStyle(dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                                if !header.meta.isEmpty { Text(" • ") }
                            }
                            Text(header.meta)
                        }
                        .font(.mix(14))
                        .foregroundStyle(dark ? AnyShapeStyle(Color.white.opacity(0.7)) : AnyShapeStyle(.secondary))
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }
                    .foregroundStyle(dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                }
                .padding(.horizontal, margin)
                .padding(.top, margin)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .top) {
                    // Dark: the header in its own colour, darker towards the bottom, then a short fall to the page under the
                    // buttons, as on Spotify. Light keeps the soft wash.
                    if dark {
                        VStack(spacing: 0) {
                            header.tint.overlay(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                            header.tint.overlay(LinearGradient(colors: [.black.opacity(0.6), PP.page], startPoint: .top, endPoint: .bottom))
                                .frame(height: 232)
                        }
                        .padding(.bottom, -232)
                        .ignoresSafeArea()
                    }
                }
                HStack(spacing: 18) {
                    PlayCircle(title: header.title, songs: { songs })
                    ShuffleToggle(on: model.shuffle && model.isPlaying(from: header.title) { songs })
                    DownloadedMark(songs: self.songs)
                    RoundMenu(songs: songs, share: share)
                    Spacer()
                    ListSearch(text: $filterText, open: $searching, placeholder: "Search in \(header.kind.lowercased())")
                    // Sort by and View as in one menu, as in Spotify; the column titles sort too.
                    ViewAsMenu(viewMode: $viewMode, orders: showSort ? orders : [], order: order) { key in
                        withAnimation(Motion.panel) {
                            model.trackOrders[model.route] = key
                            model.trackReversed[model.route] = false
                        }
                    }
                }
                .padding(.horizontal, margin)
                .padding(.top, 24)
                .padding(.bottom, genres.count > 1 ? 16 : 24)
                if genres.count > 1 {
                    GenreChips(genres: genres, chosen: $genre)
                        .padding(.horizontal, margin)
                        .padding(.bottom, 14)
                }
                TrackColumns(showAlbum: showAlbum, showAdded: showAdded && wide, compact: compact,
                             order: showSort ? order : nil, reversed: reversed) { key in
                    withAnimation(Motion.panel) { model.sortTracks(by: key, current: order, default: firstOrder) }
                }
                    .padding(.horizontal, margin - 12)
                Divider()
                    .padding(.horizontal, margin)
                    .padding(.bottom, 8)
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(index: index + 1, song: song, context: songs, showAlbum: showAlbum, showAdded: showAdded && wide, showCover: showCover,
                                 compact: compact)
                    }
                    if songs.isEmpty && (genre != nil || !filterText.isEmpty) {
                        Text("No songs match").font(.mix(14)).foregroundStyle(.secondary).padding(.vertical, 32)
                    }
                }
                .padding(.horizontal, margin - 12)
                if !more.isEmpty {
                    Shelf(title: "More like this", showAll: moreRoute) {
                        FittingRow(items: more, minWidth: 160) { ShelfCell(item: $0) }
                    }
                    .padding(.horizontal, margin)
                    .padding(.top, 36)
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(alignment: .top) {
            if !dark {
                LinearGradient(colors: [header.tint.opacity(0.55), header.tint.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 440)
                    .ignoresSafeArea()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The same frames as `TrackRow`, so every title sits above its column. As in Spotify a click on a title sorts the list by
/// it and a second click turns it round, with a small green arrow on the title that sorts; `#` goes back to the list's own order.
struct TrackColumns: View {
    var showAlbum = true
    var showAdded = true
    var compact = false
    /// The order the list is in; nil where the titles do not sort (an album).
    var order: TrackOrder? = nil
    var reversed = false
    var onSort: (TrackOrder) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 16) {
            header("#", .custom).frame(width: 24)
            header("Title", .title).frame(maxWidth: .infinity, alignment: .leading)
            if compact { header("Artist", .artist).frame(maxWidth: .infinity, alignment: .leading) }
            if showAlbum { header("Album", .album).frame(maxWidth: .infinity, alignment: .leading) }
            if showAdded { header("Date added", .added).frame(width: 130, alignment: .leading) }
            // Room for the saved check, then the clock centred over the times, then room for the more button.
            Color.clear.frame(width: 24)
            header(nil, .duration).frame(width: 44, alignment: .center)
            Color.clear.frame(width: 24)
        }
        .font(.mix(14))
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private func header(_ title: String?, _ key: TrackOrder) -> some View {
        // Newest first is the natural way for dates, smallest first for the rest; the arrow points up for A to Z.
        let active = order == key && key != .custom
        let ascending = key == .added ? reversed : !reversed
        return SortHeader(title: title, active: active, ascending: ascending, sortable: order != nil) { onSort(key) }
    }
}

private struct SortHeader: View {
    let title: String?
    let active: Bool
    let ascending: Bool
    let sortable: Bool
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let title { Text(title).lineLimit(1) } else { Image(systemName: "clock") }
                if active {
                    Image(systemName: ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(PP.primary)
                }
            }
            .foregroundStyle(active || (hovering && sortable) ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!sortable)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help(sortable ? (title.map { "Sort by \($0.lowercased())" } ?? "Sort by length") : "")
    }
}

/// View as, as in Spotify: List (rows with covers) or Compact (plain lines), in a small grey menu.
struct ViewAsMenu: View {
    @Binding var viewMode: String
    /// The orders it offers under Sort by; none where the list keeps its own order (an album).
    var orders: [TrackOrder] = []
    var order: TrackOrder = .custom
    var onSort: (TrackOrder) -> Void = { _ in }
    @LocalState private var hovering = false

    var body: some View {
        let compact = viewMode == "compact"
        Menu {
            if !orders.isEmpty {
                Picker("Sort by", selection: Binding(get: { order }, set: { onSort($0) })) {
                    ForEach(orders, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Picker("View as", selection: $viewMode) {
                Label { Text("Compact") } icon: { Image(nsImage: GlyphImage.compactView) }.tag("compact")
                Label { Text("List") } icon: { Image(nsImage: GlyphImage.listView) }.tag("list")
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                // As on Spotify: the order the list is in, or how it looks where it cannot be sorted.
                Text(orders.isEmpty ? (compact ? "Compact" : "List") : order.label).font(.mix(14))
                ViewModeGlyph(compact: compact)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 15, height: 12)
            }
            .foregroundStyle(hovering ? PP.iconHover : PP.icon)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("View as")
    }
}

struct TrackRow: View {
    let index: Int
    let song: Song
    /// The list the row is in: what plays after it when it is started.
    var context: [Song] = []
    var showAlbum = true
    var showAdded = true
    var showCover = true
    /// Compact: one line, no cover, the artist in a column of its own.
    var compact = false
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false
    @LocalState private var showPlaylists = false

    var body: some View {
        let playing = song == model.current
        let saved = model.likedIDs.contains(song.id) || Library.shared.inPlaylist(song)
        HStack(spacing: 16) {
            ZStack {
                if hovering {
                    // The play mark under the pointer plays this song, as in Spotify; on the song that plays it pauses.
                    Button {
                        if playing { model.setPlaying(!model.isPlaying) } else { model.play(song, in: context) }
                    } label: {
                        PlayerIconImage(symbol: playing && model.isPlaying ? "pause.fill" : "play.fill", size: 14)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PressStyle())
                    .help(playing && model.isPlaying ? "Pause" : "Play \(song.title)")
                } else if playing {
                    NowPlayingMark()
                } else {
                    Text("\(index)").font(.mix(16, tabular: true)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 24)
            HStack(spacing: 12) {
                if showCover && !compact { CoverArt(album: song.album, radius: 4).frame(width: 40, height: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.mix(16)).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    if !compact {
                        LinkText(song.artist) { model.go(.artist(song.artist)) }.font(.mix(14)).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if compact {
                LinkText(song.artist) { model.go(.artist(song.artist)) }.font(.mix(14)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showAlbum {
                LinkText(song.album.title) { model.go(.album(song.album.id)) }.font(.mix(14)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showAdded {
                Text(song.added).font(.mix(14)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: 130, alignment: .leading)
            }
            // As in Spotify: a green check when the song is saved (liked or in a playlist), a plus under the pointer to
            // save it. The plus saves it to Liked Songs and opens the list of playlists; the check opens that list too.
            ZStack {
                if saved {
                    Button { showPlaylists = true } label: {
                        PlayerIconImage(symbol: "checkmark.circle.fill", size: 17).foregroundStyle(PP.primary)
                    }
                    .buttonStyle(PressStyle())
                    .help("Saved. Change where")
                } else if hovering || showPlaylists {
                    Button {
                        model.setLiked(song, true)
                        showPlaylists = true
                    } label: {
                        PlayerIconImage(symbol: "plus.circle", size: 17).foregroundStyle(.secondary)
                    }
                    .buttonStyle(PressStyle())
                    .help("Save to Liked Songs")
                }
            }
            .frame(width: 24)
            .popover(isPresented: $showPlaylists, arrowEdge: .bottom) { AddToPlaylistView(song: song) }
            Text(song.duration).font(.mix(14, tabular: true)).foregroundStyle(.secondary).frame(width: 44, alignment: .center)
            ZStack {
                if hovering {
                    Menu { SongMenu(song: song) } label: {
                        PlayerIconImage(symbol: "ellipsis", size: 15).foregroundStyle(.secondary)
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More for \(song.title)")
                }
            }
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? 34 : 56)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.play(song, in: context) }
        .onHover { hovering = $0 && !Debug.active }
        .onAppear {
            if Debug.hovered(song.title) { hovering = true }
            // A scripted run presses the plus: saved to Liked Songs, and the list of playlists open.
            if Debug.active, ProcessInfo.processInfo.environment["PP_SHOW_PLAYLISTS"] == song.title {
                model.setLiked(song, true)
                showPlaylists = true
            }
        }
        .animation(nil, value: hovering)
        .contextMenu { SongMenu(song: song) }
    }
}

// MARK: Search

struct SearchPage: View {
    let term: String

    private var songs: [Song] {
        Library.shared.songs.filter { [$0.title, $0.artist, $0.album.title].contains { $0.looselyContains(term) } }
    }
    private var albums: [Album] {
        Library.shared.albums.filter { [$0.title, $0.artist].contains { $0.looselyContains(term) } }
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
        return Array(Library.shared.albums.filter { !$0.genre.isEmpty && seen.insert($0.genre).inserted }.prefix(8))
    }

    private let moods: [(String, Int)] = [("Focus", 6), ("Late Night", 0), ("Sunday Morning", 3), ("Rainy Days", 7)]

    private var browse: some View {
        VStack(alignment: .leading, spacing: 36) {
            RecentSearches()
            if !genres.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Browse").titleFont(24)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        ForEach(genres) { album in BrowseTile(title: album.genre, album: album) }
                    }
                }
            }
            // The moods are made up: only the sample music has them.
            if Library.shared.isSample {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Moods").titleFont(24)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        ForEach(moods, id: \.0) { mood in BrowseTile(title: mood.0, album: Library.shared.album(at: mood.1)) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Top result").titleFont(24)
                if let album = albums.first {
                    // Fits the four song rows beside it exactly: 20 + 96 + space + 56 + 20 within 224.
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 16) {
                            CoverArt(album: album, radius: 6).frame(width: 96, height: 96)
                                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(album.title).titleFont(32).lineLimit(2)
                                Text("Album · \(album.artist)").foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            PlayCircle(title: album.title, songs: { Library.shared.songs(for: .album(album.id)) })
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 224)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture { PlayerModel.shared.go(.album(album.id)) }
                    // Whatever is opened or played from the results goes into Recent searches, as in Spotify.
                    .simultaneousGesture(TapGesture().onEnded { SearchHistory.shared.remember(SearchHistory.code(album: album)) })
                }
            }
            .frame(width: 320)
            VStack(alignment: .leading, spacing: 14) {
                Text("Songs").titleFont(24)
                VStack(spacing: 0) {
                    ForEach(Array(songs.prefix(4).enumerated()), id: \.element.id) { index, song in
                        TrackRow(index: index + 1, song: song, context: songs, showAlbum: false, showAdded: false)
                            .simultaneousGesture(TapGesture().onEnded { SearchHistory.shared.remember(SearchHistory.code(song: song)) })
                    }
                }
                .frame(height: 224, alignment: .top)
            }
        }
        if !albums.isEmpty {
            Shelf(title: "Albums", showAll: .shelf("albums:\(term)")) {
                FittingRow(items: albums, minWidth: 160) { album in
                    ShelfCell(item: .album(album))
                        .simultaneousGesture(TapGesture().onEnded { SearchHistory.shared.remember(SearchHistory.code(album: album)) })
                }
            }
        }
    }
}

/// Recent searches on the search page while nothing is typed, as in Spotify: what was opened from a search, newest first,
/// each with a cross under the pointer, and a way to clear them all. Works as SpotCopy's on Android.
struct RecentSearches: View {
    private var history: SearchHistory { SearchHistory.shared }

    var body: some View {
        let recent = history.codes.compactMap(RecentSearch.init(code:))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent searches").titleFont(24)
                    Spacer()
                    ShowAllButton(title: "Clear recent searches") { withAnimation(Motion.panel) { history.clear() } }
                }
                FittingRow(items: Array(recent.prefix(12)), minWidth: 150, spacing: 12) { item in
                    RecentSearchCard(item: item)
                }
            }
            .transition(.opacity)
        }
    }
}

private struct RecentSearchCard: View {
    let item: RecentSearch
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                switch item {
                case .album(let album): CoverArt(album: album, radius: 6)
                case .song(let song): CoverArt(album: song.album, radius: 6)
                case .artist(_, let album): CoverArt(album: album, radius: 0).clipShape(Circle())
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            Text(title).font(.mix(16)).lineLimit(1)
            Text(subtitle).font(.mix(14)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        // The cross in the corner, under the pointer, takes it out of the list.
        .overlay(alignment: .topTrailing) {
            Button { withAnimation(Motion.panel) { SearchHistory.shared.forget(item.id) } } label: {
                PlayerIconImage(symbol: "xmark", size: 10)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.7)))
            }
            .buttonStyle(PressStyle())
            .padding(14)
            .opacity(hovering ? 1 : 0)
            .help("Remove from recent searches")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
    }

    private var title: String {
        switch item {
        case .album(let album): album.title
        case .song(let song): song.title
        case .artist(let name, _): name
        }
    }

    private var subtitle: String {
        switch item {
        case .album(let album): "Album • \(album.artist)"
        case .song(let song): "Song • \(song.artist)"
        case .artist: "Artist"
        }
    }

    /// As from the results: an album or artist opens, a song plays with its album after it.
    private func open() {
        SearchHistory.shared.remember(item.id)
        switch item {
        case .album(let album): model.go(.album(album.id))
        case .artist(let name, _): model.go(.artist(name))
        case .song(let song): model.play(song, in: Library.shared.songs(for: .album(song.album.id)))
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
            Text(title).titleFont(24).foregroundStyle(.white).padding(16)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .hoverLift()
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { PlayerModel.shared.go(.genre(title)) }
    }
}

/// Before there is any music: what PixelPlayer needs, and the one step to get there.
struct ConnectPage: View {
    @Environment(PlayerModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let library = Library.shared
        VStack(spacing: 20) {
            Image(systemName: "music.note.house")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 96, height: 96)
                .background(Circle().fill(Color.primary.opacity(0.06)))
            VStack(spacing: 6) {
                Text(library.scanning ? "Reading your music" : "Connect your music").titleFont(24)
                Text(library.scanning ? "The first time takes a moment for a large folder. Your songs appear here by themselves."
                     : "PixelPlayer plays your Navidrome library, with the music on this Mac first.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if library.scanning {
                ProgressView().controlSize(.small)
            }
            switch library.status {
            case .loading(let what):
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(what).foregroundStyle(.secondary) }
            case .failed(let message):
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
            default:
                EmptyView()
            }
            HStack(spacing: 12) {
                Button("Connect to Navidrome…") {
                    model.settingsTab = .sources
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                Button("Choose Music Folder…") { _ = MusicFolder.choose() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Shelves

/// One thing on a shelf: an album, an artist (round) or a mix.
enum ShelfItem {
    case album(Album), artist(Album), mix(Mix)
}

/// What each shelf holds, the same in its row and on its Show all page.
@MainActor
enum Shelves {
    static func title(_ key: String) -> String {
        if key == "mixes" { return "Mixes for you" }
        if key == "recent" { return "Recently played" }
        if key.hasPrefix("albums:") { return "Albums for \u{201C}\(key.dropFirst("albums:".count))\u{201D}" }
        return "More like this"
    }

    static func items(_ key: String) -> [ShelfItem] {
        let library = Library.shared
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "mixes":
            return library.mixes.map(ShelfItem.mix)
        case "recent":
            // Every third one as its artist, the way a list of recent things reads.
            return library.recentAlbums.enumerated().map { $0.offset % 3 == 2 ? .artist($0.element) : .album($0.element) }
        case "more-album":
            return library.albums.filter { $0.id != value }.map(ShelfItem.album)
        case "more-artist":
            let album = library.albums.first { $0.artist == value } ?? library.album(at: 0)
            return library.albums.filter { ($0.artist == value || $0.genre == album.genre) && $0.id != album.id }.map(ShelfItem.album)
        case "albums":
            return library.albums.filter { [$0.title, $0.artist].contains { $0.looselyContains(value) } }.map(ShelfItem.album)
        default:
            return []
        }
    }
}

/// A cover on a shelf. A click opens the album or the artist, or plays the mix.
struct ShelfCell: View {
    let item: ShelfItem

    var body: some View {
        Group {
            switch item {
            case .album(let album):
                CoverCell(art: .album(album), title: album.title, subtitle: album.artist) { Library.shared.songs(for: .album(album.id)) }
            case .artist(let album):
                CoverCell(art: .artist(album), title: album.artist, subtitle: "Artist", round: true) { Library.shared.songs(for: .artist(album.artist)) }
            case .mix(let mix):
                CoverCell(art: .collage(mix.covers + mix.covers.reversed()), title: mix.title, subtitle: mix.subtitle) { Library.shared.songs(for: mix) }
            }
        }
        // A click on the cover opens it; the green button on the cover plays it.
        .onTapGesture {
            let model = PlayerModel.shared
            switch item {
            case .album(let album): model.go(.album(album.id))
            case .artist(let album): model.go(.artist(album.artist))
            case .mix(let mix): model.go(.mix(mix.id))
            }
        }
    }
}

/// Everything on one shelf, from its Show all: the covers in a grid, as many across as fit.
struct ShelfPage: View {
    let key: String

    var body: some View {
        let items = Shelves.items(key)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Shelves.title(key)).titleFont(32)
                if items.isEmpty {
                    Text("Nothing here yet").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)], alignment: .leading, spacing: 28) {
                    ForEach(items.indices, id: \.self) { ShelfCell(item: items[$0]) }
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, margin)
            .padding(.bottom, 24)
        }
        // The same margin above as at the sides, whatever the title bar's safe area is at that moment.
        .ignoresSafeArea(.container, edges: .top)
    }
}

extension String {
    /// A search that ignores capitals and accents, so "stenstrom" finds "Stenström" and "cafe" finds "Café".
    func looselyContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension Song {
    /// The genres in the song's tags; several in one tag are split at a semicolon, comma or bar.
    var genres: [String] {
        album.genre.split(whereSeparator: { ";,|".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Whether the search in a list finds it: in the title, the artist or the album.
    func matches(_ text: String) -> Bool {
        title.looselyContains(text) || artist.looselyContains(text) || album.title.looselyContains(text)
    }
}

extension TrackListPage {
    /// The genres in the list from the songs' own tags, the one with most songs first.
    fileprivate var genres: [String] {
        var counts: [String: Int] = [:]
        for song in songs { for genre in song.genres { counts[genre, default: 0] += 1 } }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(15).map(\.key)
    }
}

/// Spotify's download button, filled green: every song in the list is on this Mac. Empty and grey while some still come
/// from the server only.
struct DownloadedMark: View {
    let songs: [Song]

    var body: some View {
        let streaming = songs.filter { !$0.isLocal }.count
        Group {
            if streaming == 0 && !songs.isEmpty {
                PlayerIconImage(symbol: "arrow.down.circle", size: 27).foregroundStyle(PP.primary)
            } else {
                PlayerIconImage(symbol: "arrow.down.circle", size: 27).foregroundStyle(PP.icon)
            }
        }
        .font(.system(size: 27, weight: .light))
        .frame(width: 36, height: 56)
        .help(streaming == 0 ? "Downloaded: every song is on this Mac" : streaming == 1 ? "1 song plays from your server" : "\(streaming) songs play from your server")
    }
}

/// The magnifier beside the sort menu: it opens a field that searches the list, as on Spotify. Esc or the magnifier again
/// closes it and shows the whole list.
struct ListSearch: View {
    @Binding var text: String
    @Binding var open: Bool
    var placeholder = "Search in playlist"
    @FocusState private var focused: Bool
    @LocalState private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(Motion.panel) { open.toggle() }
                if open { focused = true } else { text = "" }
            } label: {
                PlayerIconImage(symbol: "magnifyingglass", size: 15)
                    .foregroundStyle(hovering || open ? PP.iconHover : PP.icon)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(open ? "Close search" : placeholder)
            if open {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.mix(14))
                    .frame(width: 170)
                    .focused($focused)
                    .onExitCommand { withAnimation(Motion.panel) { open = false }; text = "" }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.trailing, open ? 10 : 0)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(open ? 0.1 : 0)))
    }
}

/// The genres under the buttons, as Spotify's: one row of at most 15, the most common first, and only as many as fit whole,
/// without scrolling or an arrow (Mark, 2026-11-26). A click filters the list to that genre; again shows all.
struct GenreChips: View {
    let genres: [String]
    @Binding var chosen: String?

    var body: some View {
        ChipRow(spacing: 8) {
            ForEach(genres.prefix(15), id: \.self) { genre in
                GenreChip(title: genre, chosen: chosen == genre) {
                    withAnimation(Motion.fade) { chosen = chosen == genre ? nil : genre }
                }
            }
        }
        .clipped()
    }
}

/// Measured on Mark's screenshot against the play button (56 pt in both): 32 high, 12 at the sides, text 14.
private struct GenreChip: View {
    let title: String
    let chosen: Bool
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Text(title)
            .font(.mix(14))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(chosen ? Color.black : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(chosen ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.16 : 0.1))))
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .animation(Motion.fade, value: hovering)
    }
}

/// One row, left to right, that leaves out whatever does not fit whole at the end instead of cutting it off or scrolling.
struct ChipRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
        let width = proposal.width.map { $0.isFinite ? $0 : natural } ?? natural
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var full = false
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !full && x + size.width <= bounds.maxX + 0.5 {
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            } else {
                // Out of sight, past the clipped end of the row.
                full = true
                subview.place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            }
        }
    }
}

extension TrackOrder {
    /// The words in the sort menu.
    var label: String {
        switch self {
        case .custom: "Custom order"
        case .added: "Recently added"
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .duration: "Length"
        }
    }
}

/// An artist, the way Spotify shows one: a wide picture with the name large over it, play and shuffle, the songs played
/// most, and the albums.
struct ArtistPage: View {
    let name: String
    @Environment(PlayerModel.self) private var model
    @LocalState private var showMore = false

    private var songs: [Song] { Library.shared.songs(for: .artist(name)) }

    /// Most played first (Navidrome counts the plays of every device); without counts, liked songs and then album order.
    private var popular: [Song] {
        let liked = model.likedIDs
        return songs.enumerated().sorted { a, b in
            if a.element.playCount != b.element.playCount { return a.element.playCount > b.element.playCount }
            let la = liked.contains(a.element.id), lb = liked.contains(b.element.id)
            if la != lb { return la }
            return a.offset < b.offset
        }.map(\.element)
    }

    private var albums: [Album] {
        var seen = Set<String>()
        return songs.map(\.album).filter { seen.insert($0.id).inserted }.sorted { $0.year > $1.year }
    }

    /// Other artists in the same genre, one album each for their round picture.
    private func similar(to genre: String) -> [Album] {
        guard !genre.isEmpty else { return [] }
        var seen: Set<String> = [name]
        return Array(Library.shared.albums.filter { $0.genre == genre && seen.insert($0.artist).inserted }.prefix(12))
    }

    @LocalState private var width: CGFloat = 900
    private let bannerHeight: CGFloat = 360

    var body: some View {
        let songs = songs
        let albums = albums
        let own = albums.filter { $0.artist == name }
        let appearsOn = albums.filter { $0.artist != name }
        let cover = own.first ?? albums.first ?? Library.shared.album(at: 0)
        let liked = songs.filter { model.likedIDs.contains($0.id) }
        let similar = similar(to: cover.genre)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner(cover: cover, songs: songs, albums: albums)
                HStack(spacing: 18) {
                    PlayCircle(title: name, songs: { popular })
                    PlainIconButton(symbol: "shuffle", label: "Shuffle") { model.play(songs, shuffled: true) }
                    RoundMenu(songs: songs, share: name)
                }
                .padding(.horizontal, margin)
                .padding(.top, 24)
                .padding(.bottom, 20)
                VStack(alignment: .leading, spacing: 44) {
                    // Popular, and beside it on a wide window the songs you liked by this artist, as in Spotify.
                    HStack(alignment: .top, spacing: 36) {
                        popularList(songs: songs)
                        if !liked.isEmpty && width >= 1000 {
                            likedCard(liked, cover: cover).frame(width: 300)
                        }
                    }
                    if !liked.isEmpty && width < 1000 {
                        likedCard(liked, cover: cover).frame(maxWidth: 420, alignment: .leading)
                    }
                    if !own.isEmpty {
                        discography(own)
                    }
                    if !appearsOn.isEmpty {
                        Shelf(title: "Appears On") {
                            FittingRow(items: appearsOn, minWidth: 160) { album in ShelfCell(item: .album(album)) }
                        }
                    }
                    if !similar.isEmpty {
                        Shelf(title: "More \(cover.genre)") {
                            FittingRow(items: similar, minWidth: 150) { album in ShelfCell(item: .artist(album)) }
                        }
                    }
                }
                .padding(.horizontal, margin)
                .padding(.bottom, 110)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // The artist's colour behind the top of the page: the cover far blurred, running on from the banner and
            // fading into the page, so the page is not one flat grey under a picture.
            .background(alignment: .top) {
                // Under the banner only: a dark glow in the colour of the cover that fades into the plain page.
                // Long and eased, so it never ends in a visible line.
                CoverArt(album: cover, radius: 0)
                    .scaledToFill()
                    .frame(height: 520)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: 80, opaque: true)
                    .overlay(PP.page.opacity(0.62))
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.75), location: 0.3),
                                                 .init(color: .black.opacity(0.35), location: 0.6), .init(color: .black.opacity(0.1), location: 0.82),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(.top, bannerHeight)
                    .allowsHitTesting(false)
            }
        }
        .background(PP.page)
        .ignoresSafeArea(.container, edges: .top)
    }

    private func popularList(songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Popular").titleFont(24)
            VStack(spacing: 0) {
                let shown = Array(popular.prefix(showMore ? 10 : 5))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, song in
                    TrackRow(index: index + 1, song: song, context: popular, showAlbum: false, showAdded: false)
                        .transition(.opacity)
                }
            }
            if songs.count > 5 {
                Button(showMore ? "Show less" : "Show more") { withAnimation(Motion.panel) { showMore.toggle() } }
                    .buttonStyle(.plain)
                    .font(.mix(14, .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.leading, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Liked songs": the artist's picture with a green heart, and how many of their songs you saved. Plays them.
    private func likedCard(_ liked: [Song], cover: Album) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Liked Songs").titleFont(24)
            Button { model.play(liked, from: "Liked Songs by \(name)") } label: {
                HStack(spacing: 14) {
                    ArtworkView(art: .artist(cover), radius: 0)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(PP.primary))
                                .overlay(Circle().stroke(PP.page, lineWidth: 2))
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(liked.count == 1 ? "You\u{2019}ve liked 1 song" : "You\u{2019}ve liked \(liked.count) songs")
                            .font(.mix(16, .bold))
                        Text("By \(name)").font(.mix(14)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 10)
            .help("Play the songs you liked by \(name)")
        }
    }

    /// Every album of the artist, newest first, with its year, as many rows as it takes (two at most, then Show all).
    private func discography(_ own: [Album]) -> some View {
        let columns = max(1, Int((width - margin * 2 + 20) / (170 + 20)))
        let shown = Array(own.prefix(columns * 2))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Discography").titleFont(24)
                Spacer()
                if own.count > shown.count {
                    ShowAllButton { model.go(.shelf("more-artist:\(name)")) }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: columns), alignment: .leading, spacing: 24) {
                ForEach(shown) { album in
                    CoverCell(art: .album(album), title: album.title,
                              subtitle: [album.year > 0 ? String(album.year) : "", "Album"].filter { !$0.isEmpty }.joined(separator: " · ")) {
                        Library.shared.songs(for: .album(album.id))
                    }
                    .onTapGesture { model.go(.album(album.id)) }
                }
            }
        }
    }

    /// The cover across the whole width, fading at the bottom into the blurred colour behind the page, with the name on it.
    private func banner(cover: Album, songs: [Song], albums: [Album]) -> some View {
        let plays = songs.reduce(0) { $0 + $1.playCount }
        return ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                CoverArt(album: cover, radius: 0)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            // A sharp picture to the edge, darker towards the bottom so the name reads; no blurred band.
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.4), .init(color: .black.opacity(0.55), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("Artist")
                    .font(.mix(14, .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.4), radius: 8)
                TitleFont.text(name, size: 84)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
                Text([songCount(songs.count), albums.count == 1 ? "1 album" : "\(albums.count) albums",
                      plays > 0 ? (plays == 1 ? "1 play" : "\(plays.formatted()) plays") : "", cover.genre]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.mix(16))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.4), radius: 8)
            }
            .padding(.horizontal, margin)
            .padding(.bottom, 20)
        }
        .frame(height: bannerHeight)
        .clipped()
    }
}

/// Where a song is saved, as Spotify asks it: Liked Songs and every playlist, each with a circle to tick. Changes go to
/// Navidrome at once. A playlist can be found by name and a new one made here.
struct AddToPlaylistView: View {
    let song: Song
    @Environment(PlayerModel.self) private var model
    @LocalState private var search = ""
    @LocalState private var newName = ""
    @LocalState private var naming = false
    @LocalState private var busy: String?

    private var library: Library { .shared }
    private var onServer: Bool { song.source.serverID != nil && library.client != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add to playlist").font(.mix(14, .bold))
            // A plain field on a soft fill: no blue focus ring, and not focused before you click it.
            HStack(spacing: 6) {
                PlayerIconImage(symbol: "magnifyingglass", size: 13).foregroundStyle(.secondary)
                TextField("Find a playlist", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .focusEffectDisabled()
            if naming {
                HStack {
                    TextField("Playlist name", text: $newName).textFieldStyle(.roundedBorder)
                        .onSubmit(create)
                    Button("Create", action: create).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button { naming = true } label: { Label("New playlist", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .disabled(!onServer)
                    .help(onServer ? "" : noServerNote)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("Saved in").font(.mix(12, .bold)).foregroundStyle(.secondary).padding(.top, 2)
                    row(title: "Liked Songs", subtitle: songCount(model.likedIDs.count), art: .liked,
                        on: model.likedIDs.contains(song.id), busy: false) { model.setLiked(song, !model.likedIDs.contains(song.id)) }
                    let lists = library.playlists.filter { search.isEmpty || $0.title.looselyContains(search) }
                    if !lists.isEmpty {
                        Text("Playlists").font(.mix(12, .bold)).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    ForEach(lists) { list in
                        let inList = list.songs.contains { $0.id == song.id }
                        row(title: list.title, subtitle: songCount(list.songs.count),
                            art: .collage(list.songs.isEmpty ? [library.album(at: 0)] : list.songs.map(\.album)),
                            on: inList, busy: busy == list.id) {
                            busy = list.id
                            Task {
                                await library.setInPlaylist(song, playlistID: list.id, on: !inList)
                                busy = nil
                            }
                        }
                        .disabled(!onServer)
                        .help(onServer ? "" : noServerNote)
                    }
                }
            }
            .frame(height: 300)
        }
        .padding(16)
        // A fixed size, so the popover opens at once instead of measuring every playlist first.
        .frame(width: 320, height: 470)
    }

    private var noServerNote: String { "This song is only on this Mac, so it can't go into a Navidrome playlist." }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        naming = false
        newName = ""
        Task { await library.createPlaylist(named: name, with: song) }
    }

    private func row(title: String, subtitle: String, art: Artwork, on: Bool, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ArtworkView(art: art, radius: 4).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.mix(14)).lineLimit(1)
                    Text(subtitle).font(.mix(12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(on ? AnyShapeStyle(PP.primary) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.vertical, 4).padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
