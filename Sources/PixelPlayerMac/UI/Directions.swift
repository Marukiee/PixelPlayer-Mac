import SwiftUI

/// The window: the system sidebar as the library, the content beside it, the queue in the inspector,
/// and the player as a glass capsule floating at the bottom (Mark's pick from round 2).
struct RootView: View {
    @Environment(PlayerModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @LocalState private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
        } detail: {
            detail
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search")
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            model.startClock()
            Debug.windowAppeared()
        }
        .onChange(of: model.settingsRequest) { openSettings() }
    }

    /// The content with the floating player over it, and the queue as a column on the right. A column of our
    /// own and not the system inspector: at this window size the inspector takes its room from the sidebar.
    private var detail: some View {
        HStack(spacing: 0) {
            ZStack {
                if model.fullPlayer {
                    NowPlayingView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    RouteContent()
                        .transition(.opacity)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            // safeAreaBar gives the system's soft edge under the floating player, so content fades out beneath it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                FloatingPlayer()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            if model.showQueue {
                QueueInspector()
                    .frame(width: 300)
                    .background(.background)
                    .overlay(alignment: .leading) { Divider() }
                    .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle(model.fullPlayer ? "Now Playing" : "PixelPlayer")
    }
}

// MARK: Library in the sidebar

enum Artwork {
    case liked, songs
    case album(Album), collage([Album]), artist(Album)
}

struct ArtworkView: View {
    let art: Artwork
    var radius: CGFloat = 4

    var body: some View {
        switch art {
        case .liked:
            tile(colors: [Color(hex: 0x4B37D8), Color(hex: 0x9FCBF2)], symbol: "heart.fill")
        case .songs:
            tile(colors: [Color(hex: 0x0058CA), Color(hex: 0x74B0FF)], symbol: "music.note")
        case .album(let album):
            CoverArt(album: album, radius: radius)
        case .collage(let albums):
            Collage(albums: albums, radius: radius)
        case .artist(let album):
            CoverArt(album: album, radius: 0).clipShape(Circle())
        }
    }

    private func tile(colors: [Color], symbol: String) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: geo.size.width * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct LibraryItem: Identifiable {
    let route: Route
    let title: String
    let subtitle: String
    let art: Artwork
    let kind: LibraryFilter
    var id: Route { route }

    static var all: [LibraryItem] {
        let albums = Sample.albums
        func playlist(_ index: Int) -> LibraryItem {
            let list = Sample.playlists[index]
            return LibraryItem(route: .playlist(list.id), title: list.title, subtitle: "Playlist · \(list.songs.count) songs",
                               art: .collage(list.songs.map(\.album)), kind: .playlists)
        }
        func album(_ index: Int) -> LibraryItem {
            LibraryItem(route: .album(albums[index].id), title: albums[index].title, subtitle: "Album · \(albums[index].artist)",
                        art: .album(albums[index]), kind: .albums)
        }
        func artist(_ index: Int) -> LibraryItem {
            LibraryItem(route: .artist(albums[index].id), title: albums[index].artist, subtitle: "Artist",
                        art: .artist(albums[index]), kind: .artists)
        }
        return [
            LibraryItem(route: .liked, title: "Liked Songs", subtitle: "Playlist · 141 songs", art: .liked, kind: .playlists),
            LibraryItem(route: .songs, title: "All Songs", subtitle: "Library · 1,284 songs", art: .songs, kind: .playlists),
            album(1), playlist(0), artist(0), playlist(1), album(2), artist(4), playlist(2), album(5),
            artist(3), playlist(3), album(8), artist(6), playlist(4), album(3),
        ]
    }
}

struct Sidebar: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let items = LibraryItem.all.filter { model.filter == .all || $0.kind == model.filter }
        List(selection: Binding(get: { model.searchText.isEmpty ? model.route : .search },
                                set: { route in
                                    guard let route else { return }
                                    if route != .search { model.searchText = "" }
                                    model.route = route
                                    if model.fullPlayer { model.setFullPlayer(false) }
                                })) {
            NavRow(symbol: "house.fill", title: "Home").tag(Route.home)
            NavRow(symbol: "square.grid.2x2.fill", title: "Browse").tag(Route.search)
            Section {
                ForEach(items) { item in
                    LibraryRow(item: item).tag(item.route)
                }
            } header: {
                // A small menu instead of a segmented bar: four words never fit a sidebar without being cut.
                HStack {
                    Text("Your Library")
                        .padding(.leading, 2)
                    Spacer()
                    Menu {
                        Picker("Show", selection: $model.filter) {
                            ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(model.filter.title)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                // Same distance from the edge as the speaker mark in the rows below.
                .padding(.trailing, 10)
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 290, max: 360)
        .toolbar(removing: .sidebarToggle)
    }
}

/// A row of the library: the cover and two lines, like Spotify, in the system's own list.
struct LibraryRow: View {
    let item: LibraryItem
    @Environment(PlayerModel.self) private var model

    private var playing: Bool {
        if case .album(let id) = item.route { return id == model.current.album.id }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(art: item.art, radius: 4).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(item.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if playing { NowPlayingMark() }
        }
        .padding(.vertical, 3)
    }
}

/// Home and Browse in the sidebar: a tile as large as the covers below, so every row starts on the same line.
struct NavRow: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.07)))
            Text(title).fontWeight(.medium)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
