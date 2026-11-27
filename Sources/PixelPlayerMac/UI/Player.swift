import SwiftUI

// MARK: Player bar

/// The song that plays: cover, title and artist. A click on the cover opens the lyrics.
struct NowPlayingInfo: View {
    var cover: CGFloat = 48
    var round = false
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Button { model.setFullPlayer(!model.fullPlayer) } label: {
                CoverArt(album: model.current.album, radius: round ? cover / 2 : 6)
                    .frame(width: cover, height: cover)
            }
            .buttonStyle(.plain)
            .hoverLift(scale: 1.06)
            .help(model.fullPlayer ? "Close lyrics" : "Lyrics")
            VStack(alignment: .leading, spacing: 2) {
                LinkText(model.current.title) { model.go(.album(model.current.album.id)) }.font(.mix(14))
                LinkText(model.current.artist) { model.go(.artist(model.current.artist)) }.font(.mix(12)).foregroundStyle(PP.subdued)
            }
            .lineLimit(1)
        }
        // Another song slides in from the side and the old one fades, instead of everything changing at once.
        .id(model.current.id)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        .animation(Motion.panel, value: model.current.id)
        .spotContextMenu { SongMenu.entries(for: PlayerModel.shared.current) }
    }
}

/// An icon button in the player: a soft round under the pointer, the accent when it is on.
struct BarIcon: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            PlayerIconImage(symbol: symbol, size: 15)
                .foregroundStyle(active ? PP.primary : hovering ? PP.iconHover : PP.icon)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 && !Debug.active }
        .animation(Motion.hover, value: hovering)
        .help(label)
    }
}

/// Lyrics, where it plays, what plays next and full screen, on the right of the player.
/// The lyrics button's symbol. PP_LYRICS_SYMBOL tries another one in a scripted run.
let lyricsSymbol = ProcessInfo.processInfo.environment["PP_LYRICS_SYMBOL"] ?? "music.mic"

struct PlayerSideButtons: View {
    /// The volume slider between Up Next and full screen, as in Spotify; left out where room is short.
    var volume = false
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 4) {
            if SleepTimer.shared.isOn { SleepTimerBadge() }
            BarIcon(symbol: lyricsSymbol, label: "Lyrics", active: model.fullPlayer) { model.setFullPlayer(!model.fullPlayer) }
            BarIcon(symbol: RemoteController.shared.isActive ? "iphone" : "hifispeaker", label: "Connect · \(model.groupName)", active: model.showDevices || !model.group.isEmpty || RemoteController.shared.isActive || SonosOutput.shared.controlsPlayback) { model.showDevices.toggle() }
                .popover(isPresented: $model.showDevices, arrowEdge: .top) { DevicesPopover() }
            BarIcon(symbol: "list.bullet", label: "Up Next", active: model.showQueue) {
                withAnimation(Motion.panel) { model.showQueue.toggle() }
            }
            if volume { BarVolume().padding(.horizontal, 4) }
            BarIcon(symbol: "arrow.up.left.and.arrow.down.right", label: "Full screen") { model.setFullScreen(true) }
        }
    }
}

/// A green moon in the player while the sleep timer runs: its time left on hover, and the timer's menu on a click.
struct SleepTimerBadge: View {
    @LocalState private var hovering = false

    var body: some View {
        let timer = SleepTimer.shared
        MenuButton(entries: { SleepTimerMenu.choices }) {
            PlayerIconImage(symbol: "moon.fill", size: 13)
                .foregroundStyle(PP.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .fixedSize()
        .help("Sleep timer: \(timer.label ?? "")")
        .transition(.opacity)
    }
}

/// The volume in the player, as in Spotify: a speaker that mutes with a click and a thin bar that turns green under the
/// pointer, with its knob while it is dragged.
struct BarVolume: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false
    @LocalState private var dragging = false
    /// The volume before muting, for the second click.
    @LocalState private var beforeMute: Double = 50

    var body: some View {
        let volume = model.groupVolume
        HStack(spacing: 6) {
            Button {
                if volume > 0 { beforeMute = volume; model.groupVolume = 0 } else { model.groupVolume = max(beforeMute, 10) }
            } label: {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : volume < 34 ? "speaker.wave.1.fill" : volume < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PP.icon)
                    .frame(width: 22, height: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(volume == 0 ? "Unmute" : "Mute")
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let filled = CGFloat(volume / 100) * width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.2)).frame(height: 3)
                    Capsule().fill(hovering || dragging ? AnyShapeStyle(PP.primary) : AnyShapeStyle(Color.primary.opacity(0.8)))
                        .frame(width: filled, height: 3)
                }
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    // As in Spotify: the knob shows as soon as the pointer is over the bar.
                    Circle().fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: 12, height: 12)
                        .offset(x: filled - 6)
                        .opacity(hovering || dragging ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            model.groupVolume = Double(min(max(value.location.x / width, 0), 1) * 100).rounded()
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(width: 92, height: 16)
            .animation(.easeOut(duration: 0.12), value: hovering || dragging)
            // `PP_VOLUME_HOVER=1` shows the bar as under the pointer, for screenshots.
            .onAppear { if Debug.active, ProcessInfo.processInfo.environment["PP_VOLUME_HOVER"] != nil { hovering = true } }
        }
        .help("Volume")
    }
}

/// The player: a glass capsule floating at the bottom of the content, laid out like Spotify's bar: the song on the left,
/// the controls with the position under them in the middle, and the buttons and volume on the right. The cover is round
/// so it sits concentric in the capsule: 68 high, 10 in, so a circle of 48. When the column is narrow (the queue open)
/// the volume and then the title step aside, so the capsule never runs over the queue.
struct FloatingPlayer: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            capsule(volume: true)
            capsule(volume: false)
            capsule(volume: false, withTitle: false)
            capsule(volume: false, withTitle: false, narrow: true)
        }
    }

    private func capsule(volume: Bool, withTitle: Bool = true, narrow: Bool = false) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                if withTitle {
                    NowPlayingInfo(cover: 48, round: true)
                } else {
                    CoverArt(album: PlayerModel.shared.current.album, radius: 24).frame(width: 48, height: 48)
                }
                LikeButton(size: 17)
            }
            .frame(minWidth: withTitle ? 170 : 0, maxWidth: 240, alignment: .leading)
            VStack(spacing: 2) {
                TransportButtons(modes: !narrow, roundPlay: true)
                InlinePosition()
            }
            .frame(width: narrow ? 230 : 340)
            PlayerSideButtons(volume: volume)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 68)
        // Glass with a dark tint in dark mode (a light one in light), so the icons read over bright covers, closer to
        // Spotify's black bar.
        .glassEffect(.regular.tint(PP.adaptive(0xFFFFFF, 0x000000, opacityLight: 0.25, opacityDark: 0.45)), in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
        // A longer or shorter title makes the capsule grow or shrink smoothly, never in a jump.
        .animation(Motion.panel, value: PlayerModel.shared.current.id)
    }
}

// MARK: Lyrics

/// The lyrics over the content, across its whole width. The cover and the song are already in the player.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var model
    /// With the sidebar gone the view starts under the traffic lights, so it keeps more room at the top and side.
    @AppStorage("lyrics.hideSidebar") private var sidebarHidden = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button { model.setFullPlayer(false) } label: {
                    PlayerIconImage(symbol: "chevron.down", size: 16).foregroundStyle(.primary)
                        .frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .help("Close lyrics")
                // The song itself, title over artist, rather than the word Lyrics over both.
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.current.title).font(.mix(14))
                    Text(model.current.artist).font(.mix(12)).foregroundStyle(PP.subdued)
                }
                .lineLimit(1)
            }
            .padding(.bottom, 28)
            ScrollView {
                LyricsLines(size: 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .padding(.bottom, 48)
            }
            .scrollIndicators(.never)
            // Lines fade out under the title instead of being cut off by it.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 36)
                    Color.black
                }
            }
        }
        // One column, left aligned inside but in the middle of the window, as in Spotify; on a narrow window it fills it.
        .frame(maxWidth: 820, alignment: .leading)
        .padding(.horizontal, sidebarHidden ? 56 : 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .background { CoverBackdrop(album: model.current.album).ignoresSafeArea(.all, edges: [.top, .bottom]) }
    }
}

/// The cover, blurred far, under a material: the colour of the song without the picture.
struct CoverBackdrop: View {
    let album: Album

    var body: some View {
        ZStack {
            CoverArt(album: album, radius: 0)
                .scaledToFill()
                .blur(radius: 70)
                .opacity(0.5)
            Rectangle().fill(.regularMaterial)
        }
        .clipped()
        // Up to the top and bottom of the window, behind the floating player too, but not under the sidebar: the sidebar
        // keeps its own colour.
        .ignoresSafeArea(.all, edges: [.top, .bottom])
    }
}

// MARK: Full screen

/// The player for full screen: the cover large with everything you need under it, and the lyrics beside it.
struct FullScreenPlayer: View {
    @Environment(PlayerModel.self) private var model
    /// Lyrics beside the cover, or only the cover, large in the middle. Remembered for next time.
    @AppStorage("fullscreen.lyrics") private var showLyrics = true
    /// Whether the song that plays has lyrics; nil while that is being looked up.
    @LocalState private var hasLyrics: Bool?
    /// Holds keyboard focus while open, so the search field in the sidebar beneath does not draw its ring on top.
    @FocusState private var focused: Bool

    /// A song without lyrics shows the cover alone, as if the lyrics were switched off.
    private var lyricsShown: Bool { showLyrics && hasLyrics != false }

    var body: some View {
        let showLyrics = lyricsShown
        GeometryReader { geo in
            // With lyrics the cover shares the screen; without, it grows and moves to the middle.
            let cover = showLyrics ? min(geo.size.height * 0.52, geo.size.width * 0.34, 520) : min(geo.size.height * 0.62, geo.size.width * 0.5, 680)
            HStack(alignment: .center, spacing: showLyrics ? 72 : 0) {
                VStack(alignment: .leading, spacing: 22) {
                    CoverArt(album: model.current.album, radius: 12)
                        .frame(width: cover, height: cover)
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
                    // The check sits level with the artist, large like in Spotify's full screen player.
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.current.title).titleFont(30)
                            Text(model.current.artist).font(.mix(16)).foregroundStyle(PP.subdued)
                        }
                        .lineLimit(1)
                        Spacer()
                        LikeButton(size: 30)
                    }
                    PositionSlider()
                    HStack {
                        Spacer()
                        TransportButtons(large: true)
                        Spacer()
                    }
                }
                .frame(width: cover)
                if showLyrics {
                    ScrollView {
                        LyricsLines(size: 36)
                            .padding(.vertical, 40)
                    }
                    .scrollIndicators(.never)
                    .frame(maxWidth: 620, maxHeight: cover + 180)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                                 .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { CoverBackdrop(album: model.current.album) }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) { model.setFullScreen(false); return .handled }
        .task(id: model.current.id) {
            let song = model.current
            let found: Bool = Library.shared.isSample ? true : (song.id.isEmpty ? false : await LyricsLoader.lyrics(for: song) != nil)
            withAnimation(Motion.morph) { hasLyrics = found }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                // Lyrics on or off, in the accent while they show, like the lyrics button in the player.
                Button { withAnimation(Motion.morph) { self.showLyrics.toggle() } } label: {
                    PlayerIconImage(symbol: lyricsSymbol, size: 15, weight: .semibold)
                        .foregroundStyle(showLyrics ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .disabled(hasLyrics == false)
                .opacity(hasLyrics == false ? 0.5 : 1)
                .help(hasLyrics == false ? "No lyrics for this song" : showLyrics ? "Hide lyrics" : "Show lyrics")
                Button { model.setFullScreen(false) } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary).frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .keyboardShortcut(.escape, modifiers: [])
                .help("Exit full screen")
            }
            // As far from the top of the window as from its side, whatever the title bar takes.
            .padding(24)
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

// MARK: Queue

/// What plays next, as a column on the right: a title with a close button, then roomy rows without lines.
/// The queue, as a column beside the page in the colour of the sidebar. Up Next shows the song that plays, the songs you
/// added and the rest of the list it came from; History the songs played before. Rows can be played, removed and dragged
/// into another order, and every change moves the rows around instead of jumping.
struct QueueInspector: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var tab: Tab = .upNext
    /// Where a dragged song would land, for the green line Spotify shows there: "user:<id>" or "next:<id>" before that
    /// song, "user:end" or "next:end" at the end of that part.
    @LocalState private var dropTarget: String?

    enum Tab: String, CaseIterable, Identifiable {
        case upNext = "Queue", history = "Recently played"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch tab {
                case .upNext: upNext
                case .history: history
                }
            }
            .transition(.opacity)
        }
        .background(PP.libraryPanel)
        .animation(Motion.fade, value: tab)
    }

    /// As in Spotify: the two tabs are the title, with the more menu and the close button beside them.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                QueueTabs(tab: $tab)
                Spacer()
                BarMenu(symbol: "ellipsis", label: "More") {
                    [
                        .item("Shuffle Up Next", icon: .svg("shuffle"), disabled: model.upNext.count < 2) {
                            withAnimation(Motion.panel) { model.upNext.shuffle() }
                        },
                        .item("Clear queue", icon: .svg("trash"), disabled: model.userQueue.isEmpty && model.upNext.isEmpty) {
                            withAnimation(Motion.panel) { model.userQueue = []; model.upNext = [] }
                        },
                    ]
                }
                BarIcon(symbol: "xmark", label: "Close") { withAnimation(Motion.panel) { model.showQueue = false } }
            }
        }
        .padding(.leading, 20).padding(.trailing, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: Up Next

    private var upNext: some View {
        // A list of our own rather than the system's: no blue frame around a row on a right click, and the rows move
        // with the same animation as everything else. Drag a song onto another to put it there.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                // Nothing to show until something plays, as in Spotify.
                if !model.current.id.isEmpty {
                    QueueHeading(text: "Now playing")
                    NowPlayingCard()
                }
                if !model.userQueue.isEmpty {
                    QueueHeading(text: "Next in queue") {
                        ShowAllButton(title: "Clear") { withAnimation(Motion.panel) { model.userQueue = [] } }
                            .help("Remove the songs you added")
                    }
                    ForEach(model.userQueue) { song in
                        QueueRow(song: song, remove: { remove(song, from: \.userQueue) })
                            .draggable("user:" + song.id) { QueueDragPreview(song: song) }
                            .dropDestination(for: String.self) { items, _ in move(items.first, before: song, in: \.userQueue) }
                                isTargeted: { target("user:" + song.id, $0) }
                            .overlay(alignment: .top) { DropLine(visible: dropTarget == "user:" + song.id) }
                    }
                    dropEnd("user:end", list: \.userQueue)
                }
                if !model.upNext.isEmpty {
                    QueueHeading(text: model.playingFrom.isEmpty ? "Next up" : "Next from: \(model.playingFrom)")
                    ForEach(model.upNext) { song in
                        QueueRow(song: song, remove: { remove(song, from: \.upNext) })
                            .draggable("next:" + song.id) { QueueDragPreview(song: song) }
                            .dropDestination(for: String.self) { items, _ in move(items.first, before: song, in: \.upNext) }
                                isTargeted: { target("next:" + song.id, $0) }
                            .overlay(alignment: .top) { DropLine(visible: dropTarget == "next:" + song.id) }
                    }
                    dropEnd("next:end", list: \.upNext)
                }
                if model.userQueue.isEmpty && model.upNext.isEmpty {
                    QueueEmpty(symbol: "text.line.last.and.arrowtriangle.forward", title: "Nothing up next",
                               text: "Songs you add with Add to Queue or Play Next show up here.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 90)
        }
        .scrollIndicators(.automatic)
        .animation(Motion.panel, value: model.userQueue)
        .animation(Motion.panel, value: model.upNext)
    }

    /// A dragged song lands before the song it was dropped on, in that part of the queue, or at its end.
    private func move(_ payload: String?, before target: Song?, in list: ReferenceWritableKeyPath<PlayerModel, [Song]>) -> Bool {
        dropTarget = nil
        guard let payload, let colon = payload.firstIndex(of: ":") else { return false }
        let from: ReferenceWritableKeyPath<PlayerModel, [Song]> = payload.hasPrefix("user:") ? \.userQueue : \.upNext
        let id = String(payload[payload.index(after: colon)...])
        guard id != target?.id, let song = model[keyPath: from].first(where: { $0.id == id }) else { return false }
        // A short, firm move into place: a slow spring here made the drop feel sluggish.
        withAnimation(.easeOut(duration: 0.18)) {
            model[keyPath: from].removeAll { $0.id == id }
            let index = target.flatMap { t in model[keyPath: list].firstIndex { $0.id == t.id } } ?? model[keyPath: list].count
            model[keyPath: list].insert(song, at: index)
        }
        return true
    }

    /// The line follows the pointer from row to row; leaving a row only clears it when no other row took it over.
    private func target(_ key: String, _ inside: Bool) {
        if inside { dropTarget = key } else if dropTarget == key { dropTarget = nil }
    }

    /// Room under the last song of a part to drop a song at its end, with the line at its top.
    private func dropEnd(_ key: String, list: ReferenceWritableKeyPath<PlayerModel, [Song]>) -> some View {
        Color.clear
            .frame(height: 14)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in move(items.first, before: nil, in: list) } isTargeted: { target(key, $0) }
            .overlay(alignment: .top) { DropLine(visible: dropTarget == key) }
    }

    private func remove(_ song: Song, from list: ReferenceWritableKeyPath<PlayerModel, [Song]>) {
        withAnimation(Motion.panel) { model[keyPath: list].removeAll { $0.id == song.id } }
    }

    // MARK: History

    private var history: some View {
        let played = Array(Playback.shared.history.reversed().prefix(50))
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if played.isEmpty {
                    QueueEmpty(symbol: "clock.arrow.circlepath", title: "Nothing played yet", text: "Songs you played show up here.")
                } else {
                    QueueHeading(text: "Played before")
                    ForEach(Array(played.enumerated()), id: \.offset) { _, song in
                        QueueRow(song: song, play: { model.play(song) })
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 90)
        }
    }
}

private extension View {
    /// The queue's lists: no separators, no backgrounds of their own, rows close to the edges of the column.
    func queueListStyle() -> some View {
        self.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listSectionSeparator(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
    }
}

/// A heading between the parts of the queue. A list row, not a section header: those stay on top with a band of their own.
struct QueueHeading<Trailing: View>: View {
    let text: String
    var trailing: Trailing

    init(text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            // As in Spotify: the headings bold and white.
            Text(text).font(.mix(16, .bold)).lineLimit(1)
            Spacer(minLength: 8)
            trailing.font(.mix(14, .bold))
        }
        .padding(.top, 16).padding(.bottom, 6).padding(.horizontal, 8)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .moveDisabled(true)
    }
}

extension QueueHeading where Trailing == EmptyView {
    init(text: String) { self.init(text: text) { EmptyView() } }
}

/// The song that plays now, a little larger than the rows under it, on a soft card.
struct NowPlayingCard: View {
    @Environment(PlayerModel.self) private var model

    @LocalState private var hovering = false

    /// As in Spotify: a row like the ones under it, the title green; the more button under the pointer.
    var body: some View {
        let song = model.current
        // Lit under the pointer and while its menu is open.
        let lit = hovering || MenuPresenter.shared.owner == "now:" + song.id
        HStack(spacing: 12) {
            CoverArt(album: song.album, radius: 4).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.mix(16)).foregroundStyle(.tint)
                LinkText(song.artist) { model.go(.artist(song.artist)) }.font(.mix(14)).foregroundStyle(PP.subdued)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if !song.id.isEmpty { QueueMore(song: song, owner: "now:" + song.id).opacity(lit ? 1 : 0) }
        }
        // Its own identity, so a song that plays and is also queued shows in both places instead of one blank row.
        .id("now-" + song.id)
        .transition(.opacity)
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(lit ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 && !Debug.active }
        // At once under the pointer, as Spotify's rows.
        .animation(nil, value: lit)
        .spotContextMenu(owner: "now:" + song.id) { song.id.isEmpty ? [] : SongMenu.entries(for: song) }
        .animation(Motion.fade, value: song.id)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .moveDisabled(true)
    }
}

/// One song in the queue, as in Spotify: cover, title, artist. Under the pointer a light grey round, a play triangle on the
/// cover and the more button at the end (with Remove from Queue). A double click plays it too; drag it to move it.
struct QueueRow: View {
    let song: Song
    var remove: (() -> Void)? = nil
    var play: (() -> Void)? = nil
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    private var menuOwner: String { "queue:" + song.id }
    /// Lit under the pointer and while its menu is open, as Spotify's rows.
    private var lit: Bool { hovering || MenuPresenter.shared.owner == menuOwner }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: playIt) {
                CoverArt(album: song.album, radius: 4).frame(width: 48, height: 48)
                    .overlay {
                        if hovering {
                            ZStack {
                                Color.black.opacity(0.5)
                                PlayGlyph().fill(Color.white).frame(width: 15, height: 17.5).offset(x: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .transition(.opacity)
                        }
                    }
            }
            .buttonStyle(PressStyle())
            .help("Play \(song.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.mix(16))
                LinkText(song.artist) { model.go(.artist(song.artist)) }.font(.mix(14)).foregroundStyle(PP.subdued)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            QueueMore(song: song, remove: remove, owner: menuOwner).opacity(lit ? 1 : 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(lit ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: playIt)
        .onHover { hovering = $0 && !Debug.active }
        .onAppear { if Debug.hovered(song.title) { hovering = true } }
        // At once under the pointer, as Spotify's rows.
        .animation(nil, value: hovering)
        .spotContextMenu(owner: menuOwner) { SongMenu.entries(for: song, remove: remove) }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
    }

    /// A song in the queue plays from its place in the queue, so what lies before it counts as passed.
    private func playIt() {
        if let play { play() } else { Playback.shared.jump(to: song.id) }
    }
}

/// Spotify's green line between the rows where a dragged song will land.
struct DropLine: View {
    let visible: Bool

    var body: some View {
        Capsule()
            .fill(PP.primary)
            .frame(height: 2)
            .padding(.horizontal, 8)
            .offset(y: -1)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: visible)
            .allowsHitTesting(false)
    }
}

/// What hangs under the pointer while a song is dragged in the queue: small and light, as Spotify's, instead of a picture
/// of the whole row.
struct QueueDragPreview: View {
    let song: Song

    var body: some View {
        HStack(spacing: 8) {
            CoverArt(album: song.album, radius: 3).frame(width: 24, height: 24)
            Text(song.title).font(.mix(12, .bold)).lineLimit(1)
        }
        .padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.16)))
        .foregroundStyle(.white)
    }
}

/// The three dots at the end of a queue row: the song's menu, and Remove from Queue where it can be taken out.
struct QueueMore: View {
    let song: Song
    var remove: (() -> Void)? = nil
    var owner: String? = nil
    @LocalState private var hovering = false

    var body: some View {
        MenuButton(owner: owner, entries: { SongMenu.entries(for: song, remove: remove) }) {
            PlayerIconImage(symbol: "ellipsis", size: 14)
                .foregroundStyle(hovering ? PP.iconHover : PP.icon)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .fixedSize()
        .onHover { hovering = $0 }
        .help("More options for \(song.title)")
    }
}

/// What an empty part of the queue says, calmly, in the middle of the column.
struct QueueEmpty: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(.tertiary)
            Text(title).font(.mix(16, .bold))
            Text(text).font(.mix(14)).foregroundStyle(PP.subdued).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 16)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .moveDisabled(true)
    }
}

// MARK: Right click and song info

/// What you can do with a song, on a right click anywhere a song is shown and behind its three dots.
@MainActor
enum SongMenu {
    /// Mark's order, the same as SpotCopy's on Android: Liked Songs, a playlist, the queue, the album, the artist, Share
    /// and the sleep timer. Song Info, which only the Mac has, comes last, then Remove from Queue in the queue. Spotify's
    /// letters on the right.
    static func entries(for song: Song, remove: (() -> Void)? = nil) -> [MenuEntry] {
        let model = PlayerModel.shared
        let liked = model.likedIDs.contains(song.id)
        let onServer = song.source.serverID != nil && Library.shared.client != nil
        var entries: [MenuEntry] = [
            .item(liked ? "Remove from Liked Songs" : "Add to Liked Songs", icon: .likedCover, shortcut: "L") { model.setLiked(song, !liked) },
            // Shown, but greyed: adding would change the playlists on the server.
            .submenu("Add to playlist", icon: .svg("add"), shortcut: "P", disabled: !onServer,
                     help: song.source.serverID == nil ? "This song is only on this Mac, so it can't go into a Navidrome playlist." : nil) {
                playlists(for: song)
            },
            .item("Add to queue", icon: .svg("m_addqueue"), shortcut: "Q") { model.userQueue.append(song) },
            .item("Go to album", icon: .svg("album"), shortcut: "A") { model.go(.album(song.album.id)) },
            .item("Go to artist", icon: .svg("artist"), shortcut: "⌥A") { model.go(.artist(song.artist)) },
            .item("Share", icon: .svg("share"), shortcut: "S") { Share.text(Share.text(for: song)) },
            SleepTimerMenu.entry,
            .divider,
            .item("Song Info", icon: .svg("info")) { model.infoSong = song },
        ]
        if let remove {
            entries += [.divider, .item("Remove from queue", icon: .svg("trash"), action: remove)]
        }
        return entries
    }

    /// As Spotify's: New playlist first, then the playlists; one that has the song already is greyed.
    private static func playlists(for song: Song) -> [MenuEntry] {
        var entries: [MenuEntry] = [.item("New playlist", icon: .svg("plus")) { NewPlaylistPrompt.ask(for: song) }]
        let lists = Library.shared.playlists
        if !lists.isEmpty { entries.append(.divider) }
        for list in lists {
            entries.append(.item(list.title, disabled: list.songs.contains { $0.id == song.id }) {
                Task { await Library.shared.setInPlaylist(song, playlistID: list.id, on: true) }
            })
        }
        return entries
    }
}

/// The sleep timer's choices, in the song menu and behind the moon in the player: Spotify's minutes and End of track, and
/// Turn off with the time left while it runs.
@MainActor
enum SleepTimerMenu {
    static var entry: MenuEntry {
        .submenu(SleepTimer.shared.label.map { "Sleep timer: \($0)" } ?? "Sleep timer", icon: .svg("m_sleep")) { choices }
    }

    static var choices: [MenuEntry] {
        let timer = SleepTimer.shared
        var entries: [MenuEntry] = []
        if let left = timer.label {
            entries += [.item("Turn off timer (\(left))") { timer.off() }, .divider]
        }
        for minutes in SleepTimer.minutes {
            entries.append(.item(minutes == 60 ? "1 hour" : "\(minutes) minutes") { timer.start(minutes: minutes) })
        }
        entries.append(.item("End of track") { timer.endOfTrack() })
        return entries
    }
}

/// Asks for a name, then makes a playlist on Navidrome with the song in it.
@MainActor
enum NewPlaylistPrompt {
    static func ask(for song: Song) {
        let alert = NSAlert()
        alert.messageText = "New playlist"
        alert.informativeText = "With \(song.title) in it."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Playlist name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task { await Library.shared.createPlaylist(named: name, with: song) }
    }
}

/// The details of one song, in a sheet with the system's own form rows.
struct SongInfoSheet: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss

    private var trackNumber: String {
        let songs = Library.shared.songs.filter { $0.album.id == song.album.id }
        let index = song.track ?? (songs.firstIndex(of: song) ?? 0) + 1
        return "\(index) of \(songs.count)"
    }

    // What the file really is. The sample music keeps the made-up values of the design shots.
    private var sample: Bool { Library.shared.isSample }
    private var format: String? {
        if sample { return "MP3 · 192 kbps · 44.1 kHz" }
        let parts = [song.source.suffix?.uppercased(), song.source.bitRate.map { "\($0) kbps" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var source: String {
        if sample || !song.isLocal { return "Navidrome" }
        return song.source.serverID == nil ? "This Mac" : "This Mac and Navidrome"
    }
    private var location: String? {
        if sample { return "~/Music/\(song.artist)/\(song.album.title)" }
        if let file = song.source.localURL { return (file.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
        return song.source.serverPath
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                CoverArt(album: song.album, radius: 6).frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.title2.weight(.bold))
                    Text(song.artist).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 20)
            Form {
                Section {
                    LabeledContent("Album", value: song.album.title)
                    LabeledContent("Artist", value: song.artist)
                    if song.album.year > 0 { LabeledContent("Year", value: String(song.album.year)) }
                    if !song.album.genre.isEmpty { LabeledContent("Genre", value: song.album.genre) }
                    LabeledContent("Track", value: trackNumber)
                    LabeledContent("Duration", value: song.duration)
                }
                Section("File") {
                    if let format { LabeledContent("Format", value: format) }
                    LabeledContent("Source", value: source)
                    if let location { LabeledContent("Location", value: location) }
                }
                if sample || !song.added.isEmpty {
                    Section("Listening") {
                        if sample { LabeledContent("Plays", value: "37") }
                        if !song.added.isEmpty { LabeledContent("Added", value: song.added) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .frame(width: 460, height: 680)
    }
}

// MARK: Devices

/// Where the music plays, as a popover from the player: the Android design (one card with the group
/// volume, Individueel volume that opens) told with the Mac's own form rows.
struct DevicesPopover: View {
    @Environment(PlayerModel.self) private var model
    private var remote: RemoteController { .shared }
    private var sonos: SonosOutput { .shared }

    private var onSonos: Bool { sonos.controlsPlayback || !model.group.isEmpty }
    private var groupedRooms: [SonosOutput.Room] { sonos.rooms.filter { sonos.isOn($0) } }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Playing on") {
                LabeledContent {
                    Button("Disconnect") { remote.disconnect(); sonos.backToMac(); model.group = [] }.controlSize(.small)
                        .disabled(!onSonos && !remote.isActive)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.groupName)
                            Text(remote.isActive ? "Phone" : onSonos ? "Sonos" : "Mac speakers")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: remote.isActive ? "iphone" : groupedRooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                            .foregroundStyle(.tint)
                    }
                }
                Slider(value: Binding(get: { model.groupVolume }, set: { model.groupVolume = $0 }), in: 0...100) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
                if groupedRooms.count > 1 {
                    // A row of its own instead of a disclosure group, which did not open on a click in this popover.
                    Button { withAnimation(Motion.panel) { model.individualVolume.toggle() } } label: {
                        HStack {
                            Text("Individual volume")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(model.individualVolume ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if model.individualVolume {
                        ForEach(groupedRooms) { room in
                            Slider(value: Binding(get: { Library.shared.isSample ? model.volumes[room.id] ?? 0 : sonos.volume(of: room) },
                                                  set: { Library.shared.isSample ? (model.volumes[room.id] = $0) : sonos.setVolume(of: room, $0) }),
                                   in: 0...100) {
                                Text(room.name)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            Section("This Mac") {
                Toggle(isOn: Binding(get: { !onSonos && !remote.isActive },
                                     set: { if $0 { remote.disconnect(); sonos.backToMac(); model.group = [] } })) {
                    Label("Mac speakers", systemImage: "laptopcomputer")
                }
            }
            Section {
                ForEach(sonos.rooms) { room in
                    Toggle(isOn: Binding(get: { sonos.isOn(room) }, set: { sonos.setRoom(room, on: $0) })) {
                        Label(room.name, systemImage: "hifispeaker")
                    }
                    .disabled(sonos.isLocked(room))
                    .help(sonos.isLocked(room) ? "This room leads the group. Remove the other rooms first." : "")
                }
            } header: {
                Text("Sonos")
            } footer: {
                if let note = sonos.note {
                    Text(note).foregroundStyle(.secondary)
                } else if sonos.rooms.isEmpty {
                    Text("Looking for speakers…").foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(remote.phones) { phone in
                    Toggle(isOn: Binding(get: { remote.active == phone },
                                         set: { on in on ? remote.connect(phone) : remote.disconnect() })) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(phone.name)
                                if let note = remote.note(for: phone) {
                                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        } icon: {
                            Image(systemName: "iphone")
                        }
                    }
                }
            } header: {
                Text("Phones")
            } footer: {
                if remote.phones.isEmpty {
                    Text("Pair a phone with this Mac and turn on \(Text.path("PixelPlayer", "Settings", "Remote player", "Use this phone as remote player")) on it.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.checkbox)
        .frame(width: 280, height: 600)
        .onAppear { remote.refreshPhones(); sonos.connectShown(true) }
        .onDisappear { sonos.connectShown(false) }
    }
}

/// Up Next and History: two tabs with a soft round under the pointer and a blue pill that slides to the chosen one,
/// instead of the system's segmented control, which only lit up on a click and flashed grey before it turned blue.
/// Queue and Recently played as Spotify shows them: the chosen one in full white with a green line under it that slides to
/// the other, the other grey until the pointer is on it. Sizes as in Mark's screenshot of Spotify, measured against the close
/// button beside them: the words a little under four times its width, the line a sixth of it.
struct QueueTabs: View {
    @Binding var tab: QueueInspector.Tab
    @Namespace private var line
    @LocalState private var hovered: QueueInspector.Tab?

    var body: some View {
        HStack(spacing: 26) {
            ForEach(QueueInspector.Tab.allCases) { item in
                let chosen = item == tab
                Text(item.rawValue)
                    .font(.mix(14.5, .bold))
                    .foregroundStyle(chosen || hovered == item ? AnyShapeStyle(.primary) : AnyShapeStyle(PP.icon))
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .overlay(alignment: .bottom) {
                        if chosen {
                            Capsule().fill(PP.primary).frame(height: 2).matchedGeometryEffect(id: "line", in: line)
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { hovered = item } else if hovered == item { hovered = nil } }
                    .onTapGesture { withAnimation(Motion.panel) { tab = item } }
            }
        }
        .animation(Motion.fade, value: hovered)
    }
}

/// A menu in the player's icon style: the same soft round under the pointer as the icon buttons beside it.
struct BarMenu: View {
    let symbol: String
    let label: String
    let entries: () -> [MenuEntry]
    @LocalState private var hovering = false

    var body: some View {
        MenuButton(entries: entries) {
            PlayerIconImage(symbol: symbol, size: 15)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .fixedSize()
        .onHover { hovering = $0 && !Debug.active }
        .animation(Motion.fade, value: hovering)
        .help(label)
    }
}
