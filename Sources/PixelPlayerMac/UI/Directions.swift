import SwiftUI

/// The window: the system sidebar as the library, the content beside it, the queue in the inspector,
/// and the player as a glass capsule floating at the bottom (Mark's pick from round 2).
struct RootView: View {
    private static var screen: CGSize { NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900) }
    @Environment(PlayerModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    /// The lyrics get the whole width: the library steps aside while they show (Settings › General).
    @AppStorage("lyrics.hideSidebar") private var hideSidebarForLyrics = true
    /// The search field only has focus after a click or ⌘L; otherwise its ring shows at launch and over full screen.
    @FocusState private var searchFocused: Bool

    /// Laid out as Spotify on the Mac: a black band at the top with the traffic lights, back and forward, Home and the
    /// search field; under it three panels with round corners and thin black lines between them: Your Library, the page
    /// with the floating player over it, and the queue.
    var body: some View {
        let hideLibrary = model.fullPlayer && hideSidebarForLyrics
        ZStack {
            VStack(spacing: 0) {
                TopBar(searchFocused: $searchFocused)
                HStack(spacing: 0) {
                    if !hideLibrary {
                        LibraryColumn()
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    detail
                        .background(PP.page)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // The queue slides in from the right. Spotify opens it in one frame, but Mark likes the slide (2026-11-26).
                    if model.showQueue {
                        QueueInspector()
                            .frame(width: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.leading, 8)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .ignoresSafeArea(.container, edges: .top)
            .background(PP.sidebar.ignoresSafeArea())
            if model.fullScreen {
                FullScreenPlayer()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
            // Spotify's menus, over everything.
            MenuLayer().zIndex(20)
        }
        .animation(Motion.panel, value: hideLibrary)
        // Spotify's letter for everything without a font of its own, at the size the system used (sheets keep the system's).
        .font(.mix(13))
        // With keyboard navigation on in macOS, every button would get a square blue ring, also round covers and glass
        // buttons. The app's own buttons go without; Tab still moves between them.
        .focusEffectDisabled()
        .sheet(isPresented: Bindable(model).showOnboarding) { OnboardingView().environment(model) }
        .sheet(item: Bindable(model).infoSong) { SongInfoSheet(song: $0) }
        // Room for the library, the content and the queue side by side, so none of them is ever pushed aside.
        // The zoom of View › Zoom In and Out: laid out at a larger or smaller size, then scaled to the window.
        .zoomed(ZoomLevel.shared.value)
        // Never larger than the screen: zoomed in far, the window would not fit a laptop.
        .frame(minWidth: min(1100 * ZoomLevel.shared.value, Self.screen.width), minHeight: min(640 * ZoomLevel.shared.value, Self.screen.height))
        .onAppear {
            model.startClock()
            Debug.windowAppeared()
        }
        .onChange(of: model.settingsRequest) { openSettings() }
        .onChange(of: model.fullScreen) { if model.fullScreen { searchFocused = false } }
        .onChange(of: model.searchRequest) { searchFocused = true }
        .task {
            // The window gives the first field focus when it opens; take it back.
            for delay in [0.1, 0.5, 1.0] {
                try? await Task.sleep(for: .seconds(delay))
                if model.searchText.isEmpty { searchFocused = false }
            }
        }
    }

    /// The content with the floating player over it.
    private var detail: some View {
        ZStack {
            if model.fullPlayer {
                NowPlayingView()
                    .transition(.opacity)
            } else {
                RouteContent()
                    // A new version shows as a small popup over the top right of the page.
                    .overlay(alignment: .topTrailing) { UpdateCard() }
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
        .navigationTitle(model.fullPlayer ? "Now Playing" : "PixelPlayer")
    }
}

/// The black band at the top, as in Spotify: back and forward beside the traffic lights, and in the middle Home in a round
/// button and the search field. Measured on Spotify (64 px, items 48 px with 8 px around them, Home and the field 8 px
/// apart, the field 474 px at most) and taken at the 75% Mark uses, as everything else.
struct TopBar: View {
    /// Spotify's band at 100% (64 px, Home and the search field 48, 8 apart, the field at most 474 wide).
    static let height: CGFloat = 64
    var searchFocused: FocusState<Bool>.Binding
    @Environment(PlayerModel.self) private var model

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Just past the traffic lights, which keep their size whatever the zoom.
                HistoryButtons().padding(.leading, 82 / ZoomLevel.shared.value)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                HomeButton()
                SearchField(focused: searchFocused)
                    .frame(maxWidth: 474)
            }
            .padding(.horizontal, 200)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ProfileButton().padding(.trailing, 8)
            }
        }
        // As tall as the band the traffic lights are moved into, so all of them share one centre line.
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(TrafficLightsPlacer().frame(width: 0, height: 0))
    }
}

/// The account in a round button at the right of the band, as Spotify's (measured: 48 px round in #1F1F1F with a 32 px
/// picture, 8 px from the edge). A click says who is signed in and opens the settings.
struct ProfileButton: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        let account = Library.shared.account
        MenuButton(entries: {
            [
                .header(account.map { "Signed in as \($0.username)" } ?? "Not signed in"),
                .item(account == nil ? "Connect to Navidrome…" : "Account…", icon: .svg("account")) { open(.sources) },
                .item("Settings…", icon: .svg("settings")) { open(.general) },
            ]
        }) {
            AccountPicture(size: 32)
                .frame(width: 48, height: 48)
                .background(Circle().fill(hovering ? PP.fieldHover : PP.field))
                .scaleEffect(hovering ? 1.04 : 1)
                .contentShape(Circle())
        }
        .fixedSize()
        .onHover { hovering = $0 && !Debug.active }
        .animation(.easeInOut(duration: 0.2 * Motion.slow), value: hovering)
        .help(account?.username ?? "Account")
    }

    private func open(_ tab: SettingsTab) {
        model.settingsTab = tab
        model.settingsRequest += 1
    }
}

/// The account's photo when the server has a real one, otherwise its first letter on a colour, as Spotify shows an account
/// without a photo. The colour comes from the name, so it stays the same.
struct AccountPicture: View {
    let size: CGFloat
    private static let colours: [UInt32] = [0xF59B23, 0x509BF5, 0xAF2896, 0x1ED760, 0xE8115B, 0x27856A, 0xE1118C]

    var body: some View {
        if let photo = Library.shared.avatar {
            Image(nsImage: photo).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            let name = Owner.firstName
            let colour = Self.colours[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colours.count]
            Text(String(name.prefix(1)).uppercased())
                .font(.mix(size * 0.55, .bold))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(hex: colour)))
        }
    }
}

/// Home in a dark round button, the house filled while Home is open, as in Spotify: #1F1F1F, lighter (#2A2A2A) and a
/// little bigger under the pointer, the house white.
struct HomeButton: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        let open = model.route == .home && model.searchText.isEmpty && !model.fullPlayer
        Button { model.go(.home) } label: {
            SpotifyIcon(name: open ? "home_on" : "home")
                .fill(style: FillStyle(eoFill: true))
                .frame(width: 24, height: 24)
                .foregroundStyle(open || hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(PP.icon))
                .frame(width: 48, height: 48)
                .background(Circle().fill(hovering ? PP.fieldHover : PP.field))
                .scaleEffect(hovering ? 1.04 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.2 * Motion.slow), value: hovering)
        .help("Home")
    }
}

/// "What do you want to play?", as in Spotify: a dark round field with the magnifier, and at its end, after a thin line, the
/// button to the browse page. Under the pointer it lightens with a faint ring; while typing the ring is white and thicker.
/// Typing shows the results on the page; Esc clears it.
struct SearchField: View {
    var focused: FocusState<Bool>.Binding
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false
    /// Only a focus after launch opens the search page; the window hands the field focus by itself when it opens.
    @LocalState private var armed = false

    var body: some View {
        @Bindable var model = model
        // The white ring stays while the search page is open or something is typed, also after a click elsewhere, as in
        // Spotify on the Mac (Mark, 2026-11-26).
        let active = focused.wrappedValue || model.route == .search || !model.searchText.isEmpty
        HStack(spacing: 0) {
            SpotifyIcon(name: "search")
                .fill(style: FillStyle(eoFill: true))
                .frame(width: 24, height: 24)
                .foregroundStyle(active || hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(PP.icon))
                .padding(.trailing, 12)
            TextField("What do you want to play?", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.mix(16))
                .focused(focused)
                .onExitCommand { model.searchText = ""; focused.wrappedValue = false }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    PlayerIconImage(symbol: "xmark", size: 14).foregroundStyle(PP.icon)
                        .frame(width: 29, height: 29).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear")
                .padding(.trailing, 8)
            }
            Rectangle().fill(PP.fieldDivider).frame(width: 1, height: 25)
                .padding(.trailing, 12)
            BrowseButton()
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 48)
        .background(Capsule().fill(hovering || active ? PP.fieldHover : PP.field))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(active ? 1 : hovering ? 0.1 : 0), lineWidth: active ? 2 : 1))
        .contentShape(Capsule())
        .onTapGesture { focused.wrappedValue = true }
        .onHover { hovering = $0 }
        // Lighter under the pointer in 0.05 s (Spotify's hover); the white ring comes at once.
        .animation(.easeIn(duration: (hovering ? 0.05 : 0.22) * Motion.slow), value: hovering)
        .animation(nil, value: active)
        // A click in the field opens the search page with the recent searches, as in Spotify.
        .onChange(of: focused.wrappedValue) { _, now in
            guard now, armed, model.searchText.isEmpty, model.route != .search else { return }
            model.go(.search)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            armed = true
        }
    }
}

/// The button at the end of the search field that opens the browse page.
private struct BrowseButton: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        let open = model.route == .search && model.searchText.isEmpty
        Button { model.go(.search) } label: {
            BrowseGlyph()
                .fill(style: FillStyle(eoFill: true))
                .foregroundStyle(open || hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(PP.icon))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help("Browse")
    }
}

/// Spotify's browse icon, drawn after it on a 24 grid: a tray (a trapezoid two units thick with round outer corners), the
/// top of a card behind it, and an oval in the tray.
struct BrowseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        // The tray: round outer corners, a sharp cut-out inside.
        let outer = [p(1.056, 9), p(22.944, 9), p(20.18, 22), p(3.82, 22)]
        path.move(to: p(12, 9))
        for index in 1...4 {
            path.addArc(tangent1End: outer[index % 4], tangent2End: outer[(index + 1) % 4], radius: s)
        }
        path.closeSubpath()
        path.addLines([p(3.525, 11), p(20.475, 11), p(18.561, 20), p(5.438, 20)])
        path.closeSubpath()
        // The card behind it: up from the tray, across, and down again.
        path.move(to: p(4, 6))
        path.addArc(tangent1End: p(4, 1), tangent2End: p(20, 1), radius: s)
        path.addArc(tangent1End: p(20, 1), tangent2End: p(20, 6), radius: s)
        path.addLine(to: p(20, 6))
        path.addLine(to: p(18, 6))
        path.addLine(to: p(18, 3))
        path.addLine(to: p(6, 3))
        path.addLine(to: p(6, 6))
        path.closeSubpath()
        // The oval in the tray.
        path.addEllipse(in: CGRect(x: ox + 9 * s, y: oy + 13.5 * s, width: 6 * s, height: 4 * s))
        return path
    }
}

/// Your Library on the left: the panel, or folded to a narrow strip of covers, and the thin line beside it to drag it wider
/// or narrower, as in Spotify. Dragged narrow enough, it folds.
struct LibraryColumn: View {
    @Environment(PlayerModel.self) private var model
    @AppStorage("library.width") private var width: Double = 320
    @AppStorage("library.wide") private var wide = false
    @LocalState private var dragStart: Double?
    /// The width while dragging; stored once the drag ends, not on every step.
    @LocalState private var liveWidth: Double?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                // Folding and opening glide, the panel and the strip fading into each other. Spotify does it in one frame,
                // but Mark likes the animation (2026-11-26).
                if model.libraryCollapsed {
                    LibraryRail().frame(width: 72).transition(.opacity)
                } else {
                    LibraryPanel().frame(width: wide ? 460 : (liveWidth ?? width)).transition(.opacity)
                }
            }
            .animation(Motion.panel, value: wide)
            // The thin black line between the library and the page; drag it to change the width.
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(
                    // Measured in the window, not on the line itself: the line moves with the width, and measured on it the
                    // width jumped back and forth under the pointer.
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = dragStart ?? (model.libraryCollapsed ? 72 : (wide ? 460 : width))
                            if dragStart == nil { dragStart = start }
                            let target = start + value.translation.width
                            if target < 180 {
                                if !model.libraryCollapsed { withAnimation(Motion.panel) { model.libraryCollapsed = true } }
                            } else {
                                if model.libraryCollapsed { withAnimation(Motion.panel) { model.libraryCollapsed = false } }
                                if wide { wide = false }
                                // The panel follows the pointer exactly, with nothing animating behind it.
                                var still = Transaction()
                                still.disablesAnimations = true
                                withTransaction(still) { liveWidth = min(480, max(280, target)) }
                            }
                        }
                        .onEnded { _ in
                            if let liveWidth { width = liveWidth }
                            liveWidth = nil
                            dragStart = nil
                        }
                )
        }
    }
}

/// Your Library folded, as in Spotify: a narrow strip with the library button to open it again, the plus, and the covers.
struct LibraryRail: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            LibraryToggleButton(collapse: false)
                .padding(.top, 13)
            CreateButton()
                .padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(LibraryItem.all) { item in
                        RailCover(item: item)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PP.libraryPanel))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A cover in the folded library: a click opens it, a double click plays it; its name shows on a pause of the pointer.
private struct RailCover: View {
    let item: LibraryItem
    @Environment(PlayerModel.self) private var model
    private var hovering: Bool { SidebarHoverState.shared.route == item.route }

    var body: some View {
        let selected = model.searchText.isEmpty && model.route == item.route
        ArtworkView(art: item.art, radius: 4)
            .frame(width: 48, height: 48)
            .clipShape(item.kind == .artists ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)))
            .padding(8)
            .background(RowHighlight(selected: selected, hovering: hovering))
            .contentShape(Rectangle())
            .onTapGesture { model.go(item.route) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.play(Library.shared.songs(for: item.route)) })
            .onHover { inside in SidebarHoverState.shared.set(item.route, inside) }
            .help("\(item.title) • \(item.subtitle)")
            .spotContextMenu(owner: "library:\(item.id)") { LibraryItemMenu.entries(for: item) }
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
            // Spotify's own gradient for Liked Songs, with its heart: a third of the tile, flat white.
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: Color.steps(from: 0x450AF5, to: 0xC4EFD9), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { LikedHeart().fill(.white).frame(width: geo.size.width * 0.323, height: geo.size.width * 0.323 * 113 / 125) }
            }
            .aspectRatio(1, contentMode: .fit)
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

extension Color {
    /// A gradient's colours mixed the way a web page mixes them (straight in sRGB), in small steps: SwiftUI on its own mixes
    /// in linear light, which makes the middle lighter and bluer than Spotify's.
    static func steps(from a: UInt32, to b: UInt32, count: Int = 9) -> [Color] {
        func part(_ c: UInt32, _ shift: UInt32) -> Double { Double((c >> shift) & 0xFF) / 255 }
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            func mix(_ shift: UInt32) -> Double { part(a, shift) + (part(b, shift) - part(a, shift)) * t }
            return Color(.sRGB, red: mix(16), green: mix(8), blue: mix(0))
        }
    }
}

/// Spotify's heart: two round lobes that overlap a little, so the dip between them is shallow, and straight sides down to a
/// softly rounded point. Measured on Mark's screenshot of the Liked Songs cover (125 by 113).
struct LikedHeart: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 125
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }
        let radius: CGFloat = 34.5, left = p(34, 34.5), right = p(91, 34.5), tip = p(62.5, 117)
        // Where each side leaves its lobe on the way to the point.
        let reach = acos(radius / hypot(62.5 - 34, 117 - 34.5)), base = atan2(117 - 34.5, 62.5 - 34)
        let leftAngle = base + reach, rightAngle = Double.pi - leftAngle
        let dip = atan2(-sqrt(radius * radius - 28.5 * 28.5), 28.5)
        var path = Path()
        path.move(to: p(34 + radius * cos(leftAngle), 34.5 + radius * sin(leftAngle)))
        path.addArc(center: left, radius: radius * u, startAngle: .radians(leftAngle), endAngle: .radians(dip), clockwise: false)
        path.addArc(center: right, radius: radius * u, startAngle: .radians(Double.pi - dip), endAngle: .radians(rightAngle), clockwise: false)
        path.addArc(tangent1End: tip, tangent2End: p(34 + radius * cos(leftAngle), 34.5 + radius * sin(leftAngle)), radius: 9 * u)
        path.closeSubpath()
        return path
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
            LibraryItem(route: .liked, title: "Liked Songs", subtitle: "Playlist • \(songCount(library.likedIDs.count))", art: .liked, kind: .playlists),
            LibraryItem(route: .songs, title: "All Songs", subtitle: "Library • \(songCount(library.songs.count))", art: .songs, kind: .playlists),
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
            LibraryItem(route: .playlist(list.id), title: list.title, subtitle: "Playlist • \(songCount(list.songs.count))",
                        art: .collage(list.songs.isEmpty ? [library.album(at: 0)] : list.songs.map(\.album)), kind: .playlists)
        }
        func albumItem(_ album: Album) -> LibraryItem {
            LibraryItem(route: .album(album.id), title: album.title, subtitle: "Album • \(album.artist)", art: .album(album), kind: .albums)
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

/// How Your Library is sorted, as in Spotify's menu. Pinned items stay on top in every order.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recents, added, alphabetical, creator
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recents: "Recents"
        case .added: "Recently added"
        case .alphabetical: "Alphabetical"
        case .creator: "Creator"
        }
    }
}

/// How Your Library looks: plain lines, rows with covers, or a grid of covers in two sizes.
enum LibraryView: String, CaseIterable, Identifiable {
    case compact, list, grid, largeGrid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: "Compact"
        case .list: "List"
        case .grid: "Grid"
        case .largeGrid: "Large grid"
        }
    }
    var symbol: String {
        switch self {
        case .compact: "line.3.horizontal"
        case .list: "list.bullet"
        case .grid: "square.grid.3x3"
        case .largeGrid: "square.grid.2x2"
        }
    }
}

/// Your Library as Spotify draws it: a dark panel with round corners. Its title, with a button that slides in under the
/// pointer to fold the library away; a plus to make a playlist and a button to widen the library; chips to show one kind;
/// a magnifier that goes to the search page and a menu to sort and change the view; then the list, with a soft shadow
/// under the chips once it scrolls.
struct LibraryPanel: View {
    @Environment(PlayerModel.self) private var model
    @AppStorage("library.sort") private var sort = LibrarySort.recents.rawValue
    @AppStorage("library.view") private var view = LibraryView.list.rawValue
    /// The title slides right first and the fold icon comes in after it; leaving, the icon goes first and the title follows.
    @LocalState private var titleIn = false
    @LocalState private var iconIn = false
    @LocalState private var scrolled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            chips.padding(.horizontal, 16)
            tools.padding(.leading, 8).padding(.trailing, 16).padding(.top, 8).padding(.bottom, 2)
            ScrollView {
                // Its own view, so the hover over the panel never sorts the library again.
                LibraryItems(sort: sort, view: view)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 1 } action: { _, value in scrolled = value }
            // A soft shadow under the chips once the list has scrolled under them, as in Spotify.
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
                    .opacity(scrolled ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(Motion.fade, value: scrolled)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PP.libraryPanel))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Spotify's timing (open.spotify.com): in, the title moves in 0.1 s and the icon follows after 0.1 s; out, the
        // icon leaves in 0.1 s and the title follows after 0.1 s. Both ease out.
        .onHover { inside in
            guard !Debug.active else { return }
            withAnimation(.easeOut(duration: 0.1).delay(inside ? 0 : 0.1)) { titleIn = inside }
            withAnimation(.easeOut(duration: 0.1).delay(inside ? 0.1 : 0)) { iconIn = inside }
        }
        .onAppear { if Debug.hovered("Your Library") { titleIn = true; iconIn = true } }
    }

    /// As in Spotify the title is the fold button itself: under the pointer the whole of it slides right and the icon
    /// comes in at its left, from further left and from nothing; a click on either folds the library.
    private var header: some View {
        HStack(spacing: 4) {
            LibraryTitleButton(titleIn: titleIn, iconIn: iconIn)
            Spacer(minLength: 4)
            CreateButton()
            WidenButton()
        }
        .padding(.trailing, 8)
        .frame(height: 59)
    }

    /// One kind at a time, as in Spotify: the chosen chip turns white, the others step aside and a cross shows to go back.
    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if model.filter != .all {
                    FilterChip(title: nil, chosen: false) { withAnimation(Motion.panel) { model.filter = .all } }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                ForEach([LibraryFilter.playlists, .albums, .artists]) { kind in
                    if model.filter == .all || model.filter == kind {
                        FilterChip(title: kind.title, chosen: model.filter == kind) {
                            withAnimation(Motion.panel) { model.filter = model.filter == kind ? .all : kind }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var tools: some View {
        HStack(spacing: 0) {
            // To the search page, not a search in the library (Mark's wish).
            SidebarIconButton(symbol: "magnifyingglass", label: "Search") {
                model.go(.search)
                model.searchRequest += 1
            }
            Spacer(minLength: 8)
            LibraryOptionsMenu(sort: $sort, view: $view)
        }
    }
}

/// The library, filtered and sorted, in the chosen view. Worked out only when the library, the filter, the order or the
/// view change, not on every hover over the panel around it.
struct LibraryItems: View {
    let sort: String
    let view: String
    @Environment(PlayerModel.self) private var model

    var body: some View {
        let shown = LibraryItem.all.filter { model.filter == .all || $0.kind == model.filter }
        LibraryList(items: LibraryItem.sorted(shown, by: LibrarySort(rawValue: sort) ?? .recents), view: LibraryView(rawValue: view) ?? .list)
    }
}

/// The library in the chosen view.
struct LibraryList: View {
    let items: [LibraryItem]
    let view: LibraryView

    var body: some View {
        switch view {
        case .compact:
            LazyVStack(spacing: 0) { ForEach(items) { LibraryRow(item: $0, compact: true) } }
        case .list:
            LazyVStack(spacing: 0) { ForEach(items) { LibraryRow(item: $0) } }
        case .grid, .largeGrid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: view == .grid ? 92 : 140), spacing: 2, alignment: .top)], spacing: 2) {
                ForEach(items) { LibraryTile(item: $0) }
            }
        }
    }
}

extension LibraryItem {
    /// Your Library in an order from Spotify's menu, pinned items first.
    @MainActor static func sorted(_ items: [LibraryItem], by sort: LibrarySort) -> [LibraryItem] {
        guard sort != .recents else { return items }
        let library = Library.shared
        let pinned = items.filter { library.isPinned($0.route) }
        let rest = items.filter { !library.isPinned($0.route) }
        let ordered: [LibraryItem]
        switch sort {
        case .recents:
            ordered = rest
        case .added:
            // One pass over the songs for every album and artist, instead of searching all songs for each item.
            var byAlbum: [String: Double] = [:], byArtist: [String: Double] = [:]
            for song in library.songs {
                guard let added = song.addedAt else { continue }
                byAlbum[song.album.id] = max(byAlbum[song.album.id] ?? 0, added)
                byArtist[song.artist] = max(byArtist[song.artist] ?? 0, added)
            }
            func added(_ item: LibraryItem) -> Double {
                switch item.route {
                case .album(let id): byAlbum[id] ?? 0
                case .artist(let name): byArtist[name] ?? 0
                default: library.songs(for: item.route).compactMap(\.addedAt).max() ?? 0
                }
            }
            let keys = Dictionary(rest.map { ($0.route, added($0)) }, uniquingKeysWith: { first, _ in first })
            ordered = rest.sorted { (keys[$0.route] ?? 0) > (keys[$1.route] ?? 0) }
        case .alphabetical:
            ordered = rest.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .creator:
            ordered = rest.sorted { ($0.creator, $0.title).0.localizedCaseInsensitiveCompare($1.creator) == .orderedAscending }
        }
        return pinned + ordered
    }

    /// Who made it, for Sort by Creator: the artist of an album, the artist itself, nothing for a playlist.
    var creator: String {
        switch route {
        case .artist(let name): name
        default: subtitle.components(separatedBy: " • ").last ?? subtitle
        }
    }
}

/// Sort by and View as, as in Spotify: the order's name with a list icon, and a menu with the orders and the views.
struct LibraryOptionsMenu: View {
    @Binding var sort: String
    @Binding var view: String
    @LocalState private var hovering = false

    var body: some View {
        let order = LibrarySort(rawValue: sort) ?? .recents
        MenuButton(entries: { entries }) {
            HStack(spacing: 6) {
                Text(order.title).font(.mix(14))
                Image(systemName: (LibraryView(rawValue: view) ?? .list).symbol).font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(hovering ? PP.iconHover : PP.icon)
            .contentShape(Rectangle())
        }
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Sort and view")
    }

    /// As Spotify's: Sort by and View as under small grey headings, the chosen one green with a check.
    private var entries: [MenuEntry] {
        var entries: [MenuEntry] = [.header("Sort by")]
        for option in LibrarySort.allCases {
            entries.append(.item(option.title, checked: option.rawValue == sort) { sort = option.rawValue })
        }
        entries += [.divider, .header("View as")]
        for option in LibraryView.allCases {
            entries.append(.item(option.title, icon: .custom(AnyView(Image(systemName: option.symbol).font(.system(size: 12, weight: .medium)))),
                                 checked: option.rawValue == view) { view = option.rawValue })
        }
        return entries
    }
}

/// A chip in the library, as in Spotify: grey, white when chosen; without a title it is the round cross that shows all again.
struct FilterChip: View {
    let title: String?
    let chosen: Bool
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Group {
            if let title {
                Text(title).font(.mix(14)).padding(.horizontal, 12)
            } else {
                PlayerIconImage(symbol: "xmark", size: 12).frame(width: 32)
            }
        }
        .foregroundStyle(chosen ? Color.black : Color.primary)
        .frame(height: 32)
        .background(Capsule().fill(chosen ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.16 : 0.1))))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help(title == nil ? "Show everything" : "")
    }
}

/// A small round icon button in the library panel: grey, white under the pointer.
struct SidebarIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            PlayerIconImage(symbol: symbol, size: 16)
                .foregroundStyle(hovering ? PP.iconHover : PP.icon)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help(label)
    }
}

/// "Your Library" with the fold icon before it, one button as in Spotify. Measured there: the icon 16 wide and 12 before the
/// title; resting, the pair sits 24 further left with the icon 16 further still and see-through, out of the panel.
struct LibraryTitleButton: View {
    let titleIn: Bool
    let iconIn: Bool
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.panel) { model.libraryCollapsed = true }
        } label: {
            HStack(spacing: 12) {
                FoldGlyph()
                    .foregroundStyle(hovering ? PP.iconHover : PP.icon)
                    .frame(width: 16, height: 16)
                    .opacity(iconIn ? 1 : 0)
                    .offset(x: iconIn ? 0 : -16)
                Text("Your Library")
                    .font(.mix(16, .bold))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 16)
            .frame(height: 30)
            .offset(x: titleIn ? 0 : -24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Collapse Your Library")
    }
}

/// The fold icon: a panel with a narrow column on its left and a small arrow pointing left in the rest.
struct FoldGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height), line = s * 0.094
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: s * 0.08, style: .continuous).inset(by: line / 2).stroke(lineWidth: line)
                Path { p in
                    p.move(to: CGPoint(x: s * 0.36, y: line / 2))
                    p.addLine(to: CGPoint(x: s * 0.36, y: s - line / 2))
                }
                .stroke(lineWidth: line)
                Path { p in
                    p.move(to: CGPoint(x: s * 0.72, y: s * 0.36))
                    p.addLine(to: CGPoint(x: s * 0.57, y: s * 0.5))
                    p.addLine(to: CGPoint(x: s * 0.72, y: s * 0.64))
                }
                .stroke(style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            }
            .frame(width: s, height: s)
        }
    }
}

/// The library icon at the top of the folded strip: it opens Your Library again.
struct LibraryToggleButton: View {
    let collapse: Bool
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.panel) { model.libraryCollapsed = collapse }
        } label: {
            // Folding: a small panel with an arrow; opening again from the strip: Spotify's library icon.
            Group {
                if collapse {
                    FoldGlyph().frame(width: 16, height: 16)
                } else {
                    SpotifyIcon(name: hovering ? "library_on" : "library").fill(style: FillStyle(eoFill: true)).frame(width: 24, height: 24)
                }
            }
                .foregroundStyle(hovering ? PP.iconHover : PP.icon)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help(collapse ? "Collapse Your Library" : "Open Your Library")
    }
}

/// The plus beside Your Library: a dark round button that makes a playlist, as in Spotify.
struct CreateButton: View {
    @LocalState private var hovering = false

    var body: some View {
        MenuButton(entries: {
            [.item("Playlist", icon: .svg("m_addplaylist"), disabled: Library.shared.client == nil,
                   help: Library.shared.client == nil ? "Playlists are made on your Navidrome server." : nil) { CreateButton.askForName() }]
        }) {
            PlayerIconImage(symbol: "plus", size: 16)
                .foregroundStyle(hovering ? PP.iconHover : PP.icon)
                .frame(width: 35, height: 35)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.16 : 0.1)))
                .contentShape(Circle())
        }
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help("Create a playlist")
    }

    /// The name for the new playlist, asked in a small sheet of the system's own.
    @MainActor static func askForName() {
        let alert = NSAlert()
        alert.messageText = "New playlist"
        alert.informativeText = "It is made on your server and shows up in Your Library."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "My playlist"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task { await Library.shared.createPlaylist(named: name) }
    }
}

/// The two arrows beside the plus: they make the library wider, and back, as Spotify's "Show more".
struct WidenButton: View {
    @AppStorage("library.wide") private var wide = false
    @LocalState private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.panel) { wide.toggle() }
        } label: {
            Image(systemName: wide ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hovering ? PP.iconHover : PP.icon)
                .frame(width: 35, height: 35)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .help(wide ? "Show less" : "Show more")
    }
}

/// Back and forward through the pages, beside the traffic lights: white when there is somewhere to go, grey when not, as
/// in Spotify.
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 32, height: 32)
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

/// A row of the library, as in Spotify: the cover (round for an artist) and two lines, the second with a green pin when it
/// is pinned. Compact: one line without a cover. A click opens it, a double click plays it.
struct LibraryRow: View {
    let item: LibraryItem
    var compact = false
    @Environment(PlayerModel.self) private var model
    private var hovering: Bool { SidebarHoverState.shared.route == item.route }

    private var playing: Bool {
        if case .album(let id) = item.route { return id == model.current.album.id }
        return false
    }

    private var selected: Bool { model.searchText.isEmpty && model.route == item.route }

    var body: some View {
        // Spotify's rows (open.spotify.com, 100%): 64 high, the cover 48 with 8 around it, the words 12 after it.
        HStack(spacing: 12) {
            if !compact {
                ArtworkView(art: item.art, radius: 4).frame(width: 48, height: 48)
                    .overlay {
                        // Hovering shows play on the cover, as in Spotify. Shown at once, like the grey behind the row.
                        ZStack {
                            Color.black.opacity(0.4)
                            PlayGlyph().fill(Color.white).frame(width: 15, height: 17.5).offset(x: 1)
                        }
                        .clipShape(item.kind == .artists ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)))
                        .opacity(hovering ? 1 : 0)
                        .animation(nil, value: hovering)
                    }
            }
            if compact {
                HStack(spacing: 4) {
                    Text(item.title).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    Text("• " + (item.subtitle.components(separatedBy: " • ").first ?? "")).foregroundStyle(PP.subdued)
                }
                .font(.mix(14))
                .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.mix(16)).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    HStack(spacing: 4) {
                        // A pinned item carries a small green pin, as in Spotify.
                        if Library.shared.isPinned(item.route) {
                            PlayerIconImage(symbol: "pin.fill", size: 12).foregroundStyle(PP.primary)
                        }
                        Text(item.subtitle)
                    }
                    .font(.mix(14)).foregroundStyle(PP.subdued)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if playing { NowPlayingMark() }
        }
        .padding(.vertical, compact ? 8 : 8)
        .padding(.horizontal, 8)
        .background(RowHighlight(selected: selected, hovering: hovering))
        .contentShape(Rectangle())
        .onTapGesture { model.go(item.route) }
        // A double click plays it from the top; the first click already opened it.
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.play(Library.shared.songs(for: item.route)) })
        .onHover { inside in SidebarHoverState.shared.set(item.route, inside) }
        .onAppear { if Debug.hovered(item.title) { SidebarHoverState.shared.route = item.route } }
        .spotContextMenu(owner: "library:\(item.id)") { LibraryItemMenu.entries(for: item) }
    }
}

/// Behind an item of Your Library, as Spotify's (measured on open.spotify.com): the open one tinted white 10%; under the
/// pointer another one gets #1F1F1F, growing in from 3 pt inside its edge, and the open one 14% lighter on top of its tint.
/// So the open one and the one under the pointer are two grey areas at once. In 0.05 s, out in 0.15 s.
struct RowHighlight: View {
    let selected: Bool
    let hovering: Bool
    var radius: CGFloat = 6

    var body: some View {
        // One row lit at a time, as in Spotify (Mark, 2026-11-26): the one under the pointer, and the open one only while the
        // pointer is on no other row. Moving to another row swaps them at once; off the list the open one comes back.
        let elsewhere = !hovering && SidebarHoverState.shared.route != nil
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(Color.primary.opacity(selected && !elsewhere ? 0.1 : 0))
            shape.fill(selected ? AnyShapeStyle(Color.primary.opacity(0.14)) : AnyShapeStyle(PP.rowHover))
                .padding(hovering || selected ? 0 : 3)
                .opacity(hovering ? 1 : 0)
        }
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: (hovering || elsewhere ? 0.05 : 0.15) * Motion.slow), value: hovering)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: (elsewhere ? 0.05 : 0.15) * Motion.slow), value: elsewhere)
        .animation(nil, value: selected)
    }
}

/// A cover with its title under it, for the grid views of the library.
struct LibraryTile: View {
    let item: LibraryItem
    @Environment(PlayerModel.self) private var model
    private var hovering: Bool { SidebarHoverState.shared.route == item.route }
    private var selected: Bool { model.searchText.isEmpty && model.route == item.route }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ArtworkView(art: item.art, radius: 4)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(item.kind == .artists ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)))
            Text(item.title).font(.mix(16)).lineLimit(1)
            Text(item.subtitle).font(.mix(14)).foregroundStyle(PP.subdued).lineLimit(1)
        }
        .padding(8)
        .background(RowHighlight(selected: selected, hovering: hovering))
        .contentShape(Rectangle())
        .onTapGesture { model.go(item.route) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.play(Library.shared.songs(for: item.route)) })
        .onHover { inside in SidebarHoverState.shared.set(item.route, inside) }
        .spotContextMenu(owner: "library:\(item.id)") { LibraryItemMenu.entries(for: item) }
    }
}

/// The right click on something in the library.
@MainActor
enum LibraryItemMenu {
    static func entries(for item: LibraryItem) -> [MenuEntry] {
        let model = PlayerModel.shared
        let songs = { Library.shared.songs(for: item.route) }
        let pinned = Library.shared.isPinned(item.route)
        var entries: [MenuEntry] = [
            .item("Play", icon: .svg("play")) { model.play(songs()) },
            .item("Shuffle", icon: .svg("shuffle")) { model.play(songs(), shuffled: true) },
            .item("Add to queue", icon: .svg("m_addqueue"), shortcut: "Q") { model.userQueue.append(contentsOf: songs()) },
            .divider,
            // Green while pinned, as Spotify's.
            .item(pinned ? "Unpin" : "Pin to Your Library", icon: .svg("pin"), green: pinned) {
                withAnimation(Motion.panel) { Library.shared.togglePin(item.route) }
            },
        ]
        if case .album(let id) = item.route {
            entries += [.divider, .item("Go to artist", icon: .svg("artist"), shortcut: "⌥A") {
                model.go(.artist(Library.shared.albums.first { $0.id == id }?.artist ?? ""))
            }]
        }
        return entries
    }
}

/// Home and Search at the top of the sidebar, as Spotify had them: its icon and the word, grey, white when open or under the
/// pointer, the icon filled when open.
struct NavRow: View {
    let icon: String
    let title: String
    let route: Route
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    /// Search is open while searching too.
    private var selected: Bool { route == .search ? (model.route == .search || !model.searchText.isEmpty) : (model.searchText.isEmpty && model.route == route) }

    var body: some View {
        let lit = selected || hovering
        HStack(spacing: 16) {
            SpotifyIcon(name: selected ? icon + "_on" : icon)
                .fill(style: FillStyle(eoFill: true))
                .frame(width: 20, height: 20)
            Text(title).font(.mix(13, .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(lit ? AnyShapeStyle(.primary) : AnyShapeStyle(PP.icon))
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture { model.go(route) }
        .onHover { hovering = $0 && !Debug.active }
        .animation(Motion.fade, value: lit)
    }
}

/// An icon traced from Spotify by the SpotCopy session (Resources/Icons/sp_<name>.svg): one outline path, filled even-odd,
/// fitted in the frame.
struct SpotifyIcon: Shape {
    let name: String

    func path(in rect: CGRect) -> Path {
        guard let icon = SpotifyIcon.icons[name] else { return Path() }
        let scale = min(rect.width / icon.size.width, rect.height / icon.size.height)
        let x = rect.midX - icon.size.width * scale / 2, y = rect.midY - icon.size.height * scale / 2
        return icon.path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y))
    }

    private static let icons: [String: (path: Path, size: CGSize)] = {
        var found: [String: (path: Path, size: CGSize)] = [:]
        guard let folder = Bundle.main.url(forResource: "Icons", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return found }
        for file in files where file.pathExtension == "svg" {
            guard let text = try? String(contentsOf: file, encoding: .utf8), let icon = parse(text) else { continue }
            found[file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "sp_", with: "")] = icon
        }
        return found
    }()

    /// The viewBox and the path of an SVG that holds only moves, lines and closes, as the traced icons do.
    private static func parse(_ svg: String) -> (path: Path, size: CGSize)? {
        func attribute(_ name: String) -> String? {
            guard let start = svg.range(of: name + "=\"") else { return nil }
            let rest = svg[start.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        guard let box = attribute("viewBox")?.split(separator: " ").compactMap({ Double($0) }), box.count == 4,
              let d = attribute(" d") else { return nil }
        var path = Path()
        for token in d.split(separator: " ") {
            guard let command = token.first else { continue }
            if command == "Z" || command == "z" { path.closeSubpath(); continue }
            let numbers = token.dropFirst().split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 2 else { continue }
            let point = CGPoint(x: numbers[0] - box[0], y: numbers[1] - box[1])
            if command == "M" { path.move(to: point) } else { path.addLine(to: point) }
        }
        return (path, CGSize(width: box[2], height: box[3]))
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
