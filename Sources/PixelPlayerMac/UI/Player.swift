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
                LinkText(model.current.title) { model.go(.album(model.current.album.id)) }.fontWeight(.semibold)
                LinkText(model.current.artist) { model.go(.artist(model.current.artist)) }.foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        // Another song slides in from the side and the old one fades, instead of everything changing at once.
        .id(model.current.id)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        .animation(Motion.panel, value: model.current.id)
        .contextMenu { SongMenu(song: model.current) }
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
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
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
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 4) {
            BarIcon(symbol: lyricsSymbol, label: "Lyrics", active: model.fullPlayer) { model.setFullPlayer(!model.fullPlayer) }
            BarIcon(symbol: RemoteController.shared.isActive ? "iphone" : "hifispeaker", label: "Connect · \(model.groupName)", active: !model.group.isEmpty || RemoteController.shared.isActive || SonosOutput.shared.controlsPlayback) { model.showDevices.toggle() }
                .popover(isPresented: $model.showDevices, arrowEdge: .top) { DevicesPopover() }
            BarIcon(symbol: "list.bullet", label: "Up Next", active: model.showQueue) {
                withAnimation(Motion.panel) { model.showQueue.toggle() }
            }
            BarIcon(symbol: "arrow.up.left.and.arrow.down.right", label: "Full screen") { model.setFullScreen(true) }
        }
    }
}

/// The player: a glass capsule floating at the bottom of the content. The cover is round so it sits concentric
/// in the capsule: 56 high, 8 in, so a circle of 40. When the column is narrow (the queue open) the position
/// slider steps aside, so the capsule never runs over the queue.
struct FloatingPlayer: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            capsule(withPosition: true)
            capsule(withPosition: false)
            capsule(withPosition: false, withTitle: false)
        }
    }

    private func capsule(withPosition: Bool, withTitle: Bool = true) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                if withTitle {
                    NowPlayingInfo(cover: 40, round: true)
                } else {
                    CoverArt(album: PlayerModel.shared.current.album, radius: 20).frame(width: 40, height: 40)
                }
                LikeButton().font(.title3)
            }
            .frame(minWidth: withTitle ? 150 : 0, maxWidth: 230, alignment: .leading)
            TransportButtons(modes: false)
            if withPosition {
                InlinePosition().frame(width: 240)
            }
            PlayerSideButtons()
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
        // A longer or shorter title makes the capsule grow or shrink smoothly, never in a jump.
        .animation(Motion.panel, value: PlayerModel.shared.current.id)
    }
}

// MARK: Lyrics

/// The lyrics over the content, across its whole width. The cover and the song are already in the player.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button { model.setFullPlayer(false) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .help("Close lyrics")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lyrics").font(.headline)
                    Text("\(model.current.title) · \(model.current.artist)").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 28)
            ScrollView {
                LyricsLines(size: 40)
                    .frame(maxWidth: 820, alignment: .leading)
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
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .background { CoverBackdrop(album: model.current.album) }
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
        // Up to the top and bottom of the window, but not under the sidebar: the sidebar keeps its own colour.
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }
}

// MARK: Full screen

/// The player for full screen: the cover large with everything you need under it, and the lyrics beside it.
struct FullScreenPlayer: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let cover = min(geo.size.height * 0.52, geo.size.width * 0.34, 520)
            HStack(alignment: .center, spacing: 72) {
                VStack(alignment: .leading, spacing: 22) {
                    CoverArt(album: model.current.album, radius: 12)
                        .frame(width: cover, height: cover)
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.current.title).font(.system(size: 30, weight: .bold))
                            Text(model.current.artist).font(.title3).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        Spacer()
                        LikeButton().font(.title2)
                    }
                    PositionSlider()
                    HStack {
                        Spacer()
                        TransportButtons(large: true)
                        Spacer()
                    }
                }
                .frame(width: cover)
                ScrollView {
                    LyricsLines(size: 36)
                        .padding(.vertical, 40)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: 620, maxHeight: cover + 180)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                             .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { CoverBackdrop(album: model.current.album) }
        .overlay(alignment: .topTrailing) {
            Button { model.setFullScreen(false) } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary).frame(width: 40, height: 40).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .keyboardShortcut(.escape, modifiers: [])
            .help("Exit full screen")
            .padding(28)
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

    enum Tab: String, CaseIterable, Identifiable {
        case upNext = "Up Next", history = "History"
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
        .background(PP.panel.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .animation(Motion.fade, value: tab)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("Queue").font(.title2.weight(.bold))
                Spacer()
                Menu {
                    Button("Shuffle Up Next", systemImage: "shuffle") { withAnimation(Motion.panel) { model.upNext.shuffle() } }
                        .disabled(model.upNext.count < 2)
                    Button("Clear Queue", systemImage: "xmark.circle") {
                        withAnimation(Motion.panel) { model.userQueue = []; model.upNext = [] }
                    }
                    .disabled(model.userQueue.isEmpty && model.upNext.isEmpty)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).frame(width: 32, height: 32).contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                BarIcon(symbol: "xmark", label: "Close") { withAnimation(Motion.panel) { model.showQueue = false } }
            }
            Picker("Show", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.leading, 20).padding(.trailing, 12)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    // MARK: Up Next

    private var upNext: some View {
        List {
            QueueHeading(text: "Now playing")
            NowPlayingCard()
            if !model.userQueue.isEmpty {
                QueueHeading(text: "Next in queue") {
                    Button("Clear") { withAnimation(Motion.panel) { model.userQueue = [] } }
                        .buttonStyle(.link)
                        .help("Remove the songs you added")
                }
                ForEach(model.userQueue) { song in
                    QueueRow(song: song) { remove(song, from: \.userQueue) }
                }
                .onMove { from, to in withAnimation(Motion.panel) { model.userQueue.move(fromOffsets: from, toOffset: to) } }
            }
            if !model.upNext.isEmpty {
                QueueHeading(text: model.playingFrom.isEmpty ? "Next up" : "Next from \(model.playingFrom)")
                ForEach(model.upNext) { song in
                    QueueRow(song: song) { remove(song, from: \.upNext) }
                }
                .onMove { from, to in withAnimation(Motion.panel) { model.upNext.move(fromOffsets: from, toOffset: to) } }
            }
            if model.userQueue.isEmpty && model.upNext.isEmpty {
                QueueEmpty(symbol: "text.line.last.and.arrowtriangle.forward", title: "Nothing up next",
                           text: "Songs you add with Add to Queue or Play Next show up here.")
            }
        }
        .queueListStyle()
        .animation(Motion.panel, value: model.userQueue)
        .animation(Motion.panel, value: model.upNext)
    }

    private func remove(_ song: Song, from list: ReferenceWritableKeyPath<PlayerModel, [Song]>) {
        withAnimation(Motion.panel) { model[keyPath: list].removeAll { $0.id == song.id } }
    }

    // MARK: History

    private var history: some View {
        let played = Array(Playback.shared.history.reversed().prefix(50))
        return List {
            if played.isEmpty {
                QueueEmpty(symbol: "clock.arrow.circlepath", title: "Nothing played yet", text: "Songs you played show up here.")
            } else {
                QueueHeading(text: "Played before")
                ForEach(Array(played.enumerated()), id: \.offset) { _, song in
                    QueueRow(song: song, play: { model.play(song) })
                }
            }
        }
        .queueListStyle()
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
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            trailing.font(.subheadline)
        }
        .padding(.top, 14).padding(.bottom, 4).padding(.horizontal, 8)
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

    var body: some View {
        let song = model.current
        HStack(spacing: 12) {
            CoverArt(album: song.album, radius: 6).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).fontWeight(.semibold).foregroundStyle(.tint)
                LinkText(song.artist) { model.go(.artist(song.artist)) }.font(.callout).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if !song.id.isEmpty { NowPlayingMark() }
        }
        .id(song.id)
        .transition(.opacity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        .contextMenu { if !song.id.isEmpty { SongMenu(song: song) } }
        .animation(Motion.fade, value: song.id)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .moveDisabled(true)
    }
}

/// One song in the queue. Under the pointer: a play button on the cover, and a button to take it out of the queue.
/// A double click plays it too; drag it to put it somewhere else.
struct QueueRow: View {
    let song: Song
    var remove: (() -> Void)? = nil
    var play: (() -> Void)? = nil
    @Environment(PlayerModel.self) private var model
    @LocalState private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: playIt) {
                CoverArt(album: song.album, radius: 4).frame(width: 40, height: 40)
                    .overlay {
                        if hovering {
                            ZStack {
                                Color.black.opacity(0.4)
                                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .transition(.opacity)
                        }
                    }
            }
            .buttonStyle(PressStyle())
            .help("Play \(song.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                LinkText(song.artist) { model.go(.artist(song.artist)) }.font(.callout).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            ZStack(alignment: .trailing) {
                Text(song.duration).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    .opacity(hovering && remove != nil ? 0 : 1)
                if let remove, hovering {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(PressStyle())
                    .help("Remove from queue")
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: playIt)
        .onHover { hovering = $0 && !Debug.active }
        .onAppear { if Debug.hovered(song.title) { hovering = true } }
        .animation(Motion.fade, value: hovering)
        .contextMenu {
            SongMenu(song: song)
            if let remove {
                Divider()
                Button("Remove from Queue", systemImage: "minus.circle", action: remove)
            }
        }
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

/// What an empty part of the queue says, calmly, in the middle of the column.
struct QueueEmpty: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 16)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .moveDisabled(true)
    }
}

// MARK: Right click and song info

/// What you can do with a song, on a right click anywhere a song is shown.
struct SongMenu: View {
    let song: Song
    @Environment(PlayerModel.self) private var model

    var body: some View {
        let liked = model.likedIDs.contains(song.id)
        Button("Play", systemImage: "play.fill") { model.play(song) }
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { model.userQueue.insert(song, at: 0) }
        Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { model.userQueue.append(song) }
        Divider()
        // Shown, but greyed: adding would change the playlists on the server.
        Menu("Add to Playlist", systemImage: "text.badge.plus") {
            ForEach(Library.shared.playlists) { list in Button(list.title) {}.disabled(true).help(playlistEditingNote) }
            Divider()
            Button("New Playlist…") {}.disabled(true).help(playlistEditingNote)
        }
        .help(playlistEditingNote)
        Button(liked ? "Remove from Liked Songs" : "Save to Liked Songs", systemImage: liked ? "heart.slash" : "heart") {
            model.setLiked(song, !liked)
        }
        Divider()
        Button("Go to Artist", systemImage: "music.microphone") { model.go(.artist(song.artist)) }
        Button("Go to Album", systemImage: "square.stack") { model.go(.album(song.album.id)) }
        Divider()
        Button("Song Info", systemImage: "info.circle") { model.infoSong = song }
        Button("Share", systemImage: "square.and.arrow.up") { Share.text(Share.text(for: song)) }
    }
}

let playlistEditingNote = "Playlists come from Navidrome; editing them here comes later"

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
                    DisclosureGroup("Individual volume", isExpanded: $model.individualVolume) {
                        ForEach(groupedRooms) { room in
                            Slider(value: Binding(get: { Library.shared.isSample ? model.volumes[room.id] ?? 0 : sonos.volume(of: room) },
                                                  set: { Library.shared.isSample ? (model.volumes[room.id] = $0) : sonos.setVolume(of: room, $0) }),
                                   in: 0...100) {
                                Text(room.name)
                            }
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
                    Text("Pair a phone with this Mac and turn on \(Text("PixelPlayer › Settings › Play from › Use this phone as remote player").bold()) on it.")
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
