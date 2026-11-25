import SwiftUI

/// The window: the system sidebar as the library, the content beside it, the queue in the inspector,
/// and the player as a glass capsule floating at the bottom (Mark's pick from round 2).
struct RootView: View {
    @Environment(PlayerModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @LocalState private var columns = NavigationSplitViewVisibility.all
    /// The lyrics get the whole width: the sidebar slides away while they show (Settings › General).
    @AppStorage("lyrics.hideSidebar") private var hideSidebarForLyrics = true
    /// The search field only has focus after a click or ⌘L; otherwise its ring shows at launch and over full screen.
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        ZStack {
            NavigationSplitView(columnVisibility: $columns) {
                Sidebar()
            } detail: {
                detail
                    // Without its own width the floating player decides how wide the content is, and squeezes the sidebar.
                    .navigationSplitViewColumnWidth(min: 640, ideal: 900)
                    // A dark page in dark mode; it also runs under the sidebar, so the sidebar's glass is dark too.
                    .background(PP.page.ignoresSafeArea())
            }
            .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search")
            .searchFocused($searchFocused)
            if model.fullScreen {
                FullScreenPlayer()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
        }
        // With keyboard navigation on in macOS, every button would get a square blue ring, also round covers and glass
        // buttons. The app's own buttons go without; Tab still moves between them.
        .focusEffectDisabled()
        .sheet(isPresented: $model.showOnboarding) { OnboardingView().environment(model) }
        .sheet(item: $model.infoSong) { SongInfoSheet(song: $0) }
        // Room for the sidebar, the content and the queue side by side, so none of them is ever pushed aside.
        .frame(minWidth: 1100, minHeight: 640)
        .onAppear {
            model.startClock()
            Debug.windowAppeared()
        }
        .onChange(of: model.settingsRequest) { openSettings() }
        .onChange(of: model.fullScreen) { if model.fullScreen { searchFocused = false } }
        .onChange(of: model.fullPlayer) {
            let hide = model.fullPlayer && hideSidebarForLyrics
            withAnimation(Motion.panel) { columns = hide ? .detailOnly : .all }
        }
        .onChange(of: hideSidebarForLyrics) {
            guard model.fullPlayer else { return }
            withAnimation(Motion.panel) { columns = hideSidebarForLyrics ? .detailOnly : .all }
        }
        .onChange(of: model.searchRequest) { searchFocused = true }
        .task {
            // The window gives the first field focus when it opens; take it back.
            for delay in [0.1, 0.5, 1.0] {
                try? await Task.sleep(for: .seconds(delay))
                if model.searchText.isEmpty { searchFocused = false }
            }
        }
    }

    /// The content with the floating player over it, and the queue as a column on the right. A column of our
    /// own and not the system inspector: at this window size the inspector takes its room from the sidebar.
    private var detail: some View {
        HStack(spacing: 0) {
            ZStack {
                if model.fullPlayer {
                    NowPlayingView()
                        .transition(.opacity)
                } else {
                    RouteContent()
                        // A new version shows as a small popup over the top right of the page.
                        .overlay(alignment: .topTrailing) {
                            // Up in the empty band at the top of the window, level with the traffic lights.
                            UpdateCard().ignoresSafeArea(.container, edges: .top)
                        }
                    .transition(.opacity)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            // safeAreaBar gives the system's soft edge under the floating player, so content fades out beneath it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                FloatingPlayer()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    // The bar is hosted apart from the page, so it needs its own: no square ring around round buttons.
                    .focusEffectDisabled()
            }
            if model.showQueue {
                QueueInspector()
                    .frame(width: 320)
                    .overlay(alignment: .leading) { Rectangle().fill(PP.hairline).frame(width: 1).ignoresSafeArea() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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

    /// Liked Songs and all songs first, then the playlists, then recent albums and their artists.
    /// Your Library: pinned items first, then Liked Songs and All Songs, then everything else. Cheap: the collections are
    /// made once per rebuild of the library.
    @MainActor static var all: [LibraryItem] {
        let library = Library.shared
        let fixed = [
            LibraryItem(route: .liked, title: "Liked Songs", subtitle: "Playlist · \(songCount(library.likedIDs.count))", art: .liked, kind: .playlists),
            LibraryItem(route: .songs, title: "All Songs", subtitle: "Library · \(songCount(library.songs.count))", art: .songs, kind: .playlists),
        ]
        let everything = fixed + library.collectionItems
        guard !library.pinned.isEmpty else { return everything }
        let byKey = Dictionary(everything.map { ($0.route.key, $0) }, uniquingKeysWith: { first, _ in first })
        let pins = library.pinned.compactMap { byKey[$0] }
        let pinnedKeys = Set(library.pinned)
        return pins + everything.filter { !pinnedKeys.contains($0.route.key) }
    }

    /// Playlists, then the albums and artists played lately mixed as a library of recent things reads, then every other
    /// album and artist by name, so all the music is there to scroll to.
    @MainActor static func collections(of library: Library) -> [LibraryItem] {
        let playlists = library.playlists.map { list in
            LibraryItem(route: .playlist(list.id), title: list.title, subtitle: "Playlist · \(songCount(list.songs.count))",
                        art: .collage(list.songs.isEmpty ? [library.album(at: 0)] : list.songs.map(\.album)), kind: .playlists)
        }
        func albumItem(_ album: Album) -> LibraryItem {
            LibraryItem(route: .album(album.id), title: album.title, subtitle: "Album · \(album.artist)", art: .album(album), kind: .albums)
        }
        func artistItem(_ album: Album) -> LibraryItem {
            LibraryItem(route: .artist(album.artist), title: album.artist, subtitle: "Artist", art: .artist(album), kind: .artists)
        }
        let recent = Array(library.recentAlbums.prefix(12))
        var seenArtists = Set<String>()
        let recentArtists = Array(library.recentAlbums.filter { seenArtists.insert($0.artist).inserted }.prefix(8))
        var items: [LibraryItem] = []
        let longest = max(playlists.count, recent.count, recentArtists.count)
        for index in 0..<longest {
            if index < recent.count { items.append(albumItem(recent[index])) }
            if index < playlists.count { items.append(playlists[index]) }
            if index < recentArtists.count { items.append(artistItem(recentArtists[index])) }
        }
        let recentIDs = Set(recent.map(\.id))
        let shownArtists = Set(recentArtists.map(\.artist))
        let otherAlbums = library.albums.filter { !recentIDs.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        var artistSeen = shownArtists
        let otherArtists = library.albums.filter { !$0.artist.isEmpty && artistSeen.insert($0.artist).inserted }
            .sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        items += otherAlbums.map(albumItem)
        items += otherArtists.map(artistItem)
        return items
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
            NavRow(symbol: "house", title: "Home", route: .home).tag(Route.home)
            NavRow(symbol: "square.grid.2x2.fill", title: "Browse", route: .search).tag(Route.search)
            Section {
                ForEach(items) { item in
                    LibraryRow(item: item).tag(item.route)
                }
            } header: {
                // A small menu instead of a segmented bar: four words never fit a sidebar without being cut.
                HStack(alignment: .firstTextBaseline) {
                    Text("Your Library")
                        .font(.headline)
                        .foregroundStyle(.primary)
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
                    .tint(PP.icon)
                    .fixedSize()
                }
                // The same inset as the rows below, so the words line up with the covers, with air above and below.
                .padding(.leading, 6)
                .padding(.trailing, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
        }
        .scrollContentBackground(.hidden)
        // Never the keyboard focus: a focused list draws its selection in bright blue, an unfocused one in a calm grey,
        // as Spotify does. Clicks still select and double clicks still play.
        .focusable(false)
        .background(PP.sidebar.ignoresSafeArea())
        .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 420)
        // A filter change moves rows under a still pointer, and macOS sends no hover end for them.
        .onChange(of: model.filter) { SidebarHoverState.shared.route = nil }
        // A quick move out of the sidebar can skip the last row's hover end; leaving the sidebar clears it for sure.
        .onHover { inside in if !inside { SidebarHoverState.shared.route = nil } }
        .toolbar(removing: .sidebarToggle)
        // Back and forward beside the traffic lights, as in a browser and in Spotify.
        .overlay(alignment: .topLeading) {
            HistoryButtons()
                .padding(.leading, 82)
                .padding(.top, 5)
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}

/// Back and forward through the pages, small and plain like the traffic lights beside them, grey when there is nowhere to go.
struct HistoryButtons: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            HistoryButton(symbol: "chevron.left", label: "Back", enabled: model.canGoBack) { model.goBack() }
            HistoryButton(symbol: "chevron.right", label: "Forward", enabled: model.canGoForward) { model.goForward() }
        }
    }
}

private struct HistoryButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? (hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)) : AnyShapeStyle(.quaternary))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hovering && enabled ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .animation(Motion.fade, value: enabled)
        .help(label)
    }
}

/// A row of the library: the cover and two lines, like Spotify, in the system's own list.
struct LibraryRow: View {
    let item: LibraryItem
    @Environment(PlayerModel.self) private var model
    private var hovering: Bool { SidebarHoverState.shared.route == item.route }

    private var playing: Bool {
        if case .album(let id) = item.route { return id == model.current.album.id }
        return false
    }

    private var selected: Bool { model.searchText.isEmpty && model.route == item.route }

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(art: item.art, radius: 4).frame(width: 40, height: 40)
                .overlay {
                    // Hovering shows play on the cover, as in Spotify, instead of a zoom. Always there and shown at once,
                    // like the grey box behind the row, so the two always change together, also under a quick pointer.
                    ZStack {
                        Color.black.opacity(0.4)
                        Image(systemName: "play.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    }
                    .clipShape(item.kind == .artists ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)))
                    .opacity(hovering ? 1 : 0)
                    .animation(nil, value: hovering)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                HStack(spacing: 4) {
                    // A pinned item carries a small green pin, as in Spotify.
                    if Library.shared.isPinned(item.route) {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(PP.primary).rotationEffect(.degrees(45))
                    }
                    Text(item.subtitle)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if playing { NowPlayingMark() }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        // The hover box is the system's selection box, same size and corners, so moving over the open item shows one box.
        .listRowBackground(SidebarHover(on: hovering && !selected))
        .contentShape(Rectangle())
        // A double click plays it from the top; one click still opens it.
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.play(Library.shared.songs(for: item.route)) })
        .onHover { inside in SidebarHoverState.shared.set(item.route, inside) }
        .onAppear { if Debug.hovered(item.title) { SidebarHoverState.shared.route = item.route } }
        .contextMenu {
            Button("Play", systemImage: "play.fill") { model.play(Library.shared.songs(for: item.route)) }
            Button("Shuffle", systemImage: "shuffle") { model.play(Library.shared.songs(for: item.route), shuffled: true) }
            Button {
                model.userQueue.append(contentsOf: Library.shared.songs(for: item.route))
            } label: {
                Label { Text("Add to Queue") } icon: { Image(nsImage: GlyphImage.addToQueue) }
            }
            Divider()
            let pinned = Library.shared.isPinned(item.route)
            Button(pinned ? "Unpin" : "Pin to Your Library", systemImage: pinned ? "pin.slash" : "pin") {
                withAnimation(Motion.panel) { Library.shared.togglePin(item.route) }
            }
            if case .album(let id) = item.route {
                Divider()
                Button("Go to Artist", systemImage: "music.microphone") {
                    model.go(.artist(Library.shared.albums.first { $0.id == id }?.artist ?? ""))
                }
            }
        }
    }
}

/// Home and Browse in the sidebar: a tile as large as the covers below, so every row starts on the same line.
struct NavRow: View {
    let symbol: String
    let title: String
    let route: Route
    @Environment(PlayerModel.self) private var model
    private var hovering: Bool { SidebarHoverState.shared.route == route }

    /// Browse is open while searching too.
    private var selected: Bool { route == .search ? (model.route == .search || !model.searchText.isEmpty) : (model.searchText.isEmpty && model.route == route) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                // White in dark mode, as in Spotify; near black in light.
                .foregroundStyle(PP.adaptive(0x1A1B21, 0xFFFFFF))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.07)))
            Text(title).fontWeight(.medium)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .listRowBackground(SidebarHover(on: hovering && !selected))
        .contentShape(Rectangle())
        .onHover { inside in SidebarHoverState.shared.set(route, inside) }
    }
}

/// The hover in the sidebar, drawn where the system draws its selection: inset from the sidebar's sides, round corners.
struct SidebarHover: View {
    let on: Bool

    var body: some View {
        // At once, as in Spotify: a fade here ran behind the play button on the cover, which is drawn apart from it.
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(on ? 0.07 : 0))
            .padding(.horizontal, 10)
            .padding(.vertical, 1)
            .animation(nil, value: on)
    }
}

/// Which sidebar row the pointer is on. One for the whole sidebar, so two rows can never both look hovered when the list
/// changes under a still pointer.
@MainActor @Observable
final class SidebarHoverState {
    static let shared = SidebarHoverState()
    var route: Route?

    func set(_ route: Route, _ inside: Bool) {
        guard !Debug.active else { return }
        if inside { self.route = route } else if self.route == route { self.route = nil }
    }
}
