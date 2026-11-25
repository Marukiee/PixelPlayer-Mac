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
                Text(model.current.title).fontWeight(.semibold)
                Text(model.current.artist).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
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
struct PlayerSideButtons: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 4) {
            BarIcon(symbol: "quote.bubble", label: "Lyrics", active: model.fullPlayer) { model.setFullPlayer(!model.fullPlayer) }
            BarIcon(symbol: "hifispeaker", label: "Connect · \(model.groupName)", active: !model.group.isEmpty) { model.showDevices.toggle() }
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
    }
}

// MARK: Lyrics

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

/// Lyrics in large type: the line sung now in full colour, the ones before it faded, the ones after it waiting.
struct LyricsLines: View {
    var size: CGFloat = 40
    var current = 3

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.55) {
            ForEach(sampleLyrics.indices, id: \.self) { i in
                Text(sampleLyrics[i])
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i == current ? AnyShapeStyle(.primary)
                                     : i < current ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
                    .padding(.bottom, 48)
            }
            .scrollIndicators(.never)
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
        .ignoresSafeArea()
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
struct QueueInspector: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // The title on the same line as the top of the page beside it: 28 points down, like the side margins.
            HStack(alignment: .center, spacing: 6) {
                Text("Up Next").font(.title2.weight(.bold))
                Spacer()
                Menu {
                    Button("Shuffle", systemImage: "shuffle") {}
                    Button("Clear queue", systemImage: "trash") {}
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                BarIcon(symbol: "xmark", label: "Close") { withAnimation(Motion.panel) { model.showQueue = false } }
            }
            .padding(.leading, 20).padding(.trailing, 14)
            .padding(.top, 24)
            .padding(.bottom, 8)
            List {
                Section {
                    QueueRow(song: model.current, playing: true)
                } header: { QueueHeader(text: "Now playing") }
                Section {
                    ForEach(model.userQueue) { QueueRow(song: $0, queued: true) }
                        .onMove { model.userQueue.move(fromOffsets: $0, toOffset: $1) }
                } header: { QueueHeader(text: "Added by you") }
                Section {
                    ForEach(model.upNext) { QueueRow(song: $0) }
                        .onMove { model.upNext.move(fromOffsets: $0, toOffset: $1) }
                } header: { QueueHeader(text: "Next from Your Mix") }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct QueueHeader: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 10).padding(.bottom, 2)
    }
}

struct QueueRow: View {
    let song: Song
    var playing = false
    var queued = false
    @LocalState private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(album: song.album, radius: 4).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(song.artist).font(.callout).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if playing { NowPlayingMark() } else if hovering { Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary) }
            else if queued { QueuedMark() }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 && !Debug.active }
        .animation(Motion.fade, value: hovering)
        .contextMenu { SongMenu(song: song) }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
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
        Menu("Add to Playlist", systemImage: "text.badge.plus") {
            ForEach(Library.shared.playlists) { list in Button(list.title) {} }
            Divider()
            Button("New Playlist…") {}
        }
        Button(liked ? "Remove from Liked Songs" : "Save to Liked Songs", systemImage: liked ? "heart.slash" : "heart") {
            if liked { model.likedIDs.remove(song.id) } else { model.likedIDs.insert(song.id) }
        }
        Divider()
        Button("Go to Artist", systemImage: "music.microphone") { model.go(.artist(song.artist)) }
        Button("Go to Album", systemImage: "square.stack") { model.go(.album(song.album.id)) }
        Divider()
        Button("Song Info", systemImage: "info.circle") { model.infoSong = song }
        Button("Share", systemImage: "square.and.arrow.up") {}
    }
}

/// The details of one song, in a sheet with the system's own form rows.
struct SongInfoSheet: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss

    private var trackNumber: String {
        let songs = Library.shared.songs.filter { $0.album.id == song.album.id }
        let index = (songs.firstIndex(of: song) ?? 0) + 1
        return "\(index) of \(songs.count)"
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
                    LabeledContent("Year", value: String(song.album.year))
                    LabeledContent("Genre", value: song.album.genre)
                    LabeledContent("Track", value: trackNumber)
                    LabeledContent("Duration", value: song.duration)
                }
                Section("File") {
                    LabeledContent("Format", value: "MP3 · 192 kbps · 44.1 kHz")
                    LabeledContent("Source", value: "Navidrome")
                    LabeledContent("Location", value: "~/Music/\(song.artist)/\(song.album.title)")
                }
                Section("Listening") {
                    LabeledContent("Plays", value: "37")
                    LabeledContent("Added", value: song.added)
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

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Playing on") {
                LabeledContent {
                    Button("Disconnect") { model.group = [] }.controlSize(.small)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.groupName)
                            Text(model.group.isEmpty ? "Mac speakers" : "Sonos").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: model.group.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill").foregroundStyle(.tint)
                    }
                }
                Slider(value: Binding(get: { model.groupVolume }, set: { model.groupVolume = $0 }), in: 0...100) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
                if model.group.count > 1 {
                    DisclosureGroup("Individual volume", isExpanded: $model.individualVolume) {
                        ForEach(Sample.rooms.filter { model.group.contains($0.id) }) { room in
                            Slider(value: Binding(get: { model.volumes[room.id] ?? 0 }, set: { model.volumes[room.id] = $0 }), in: 0...100) {
                                Text(room.name)
                            }
                        }
                    }
                }
            }
            Section("This Mac") {
                Toggle(isOn: Binding(get: { model.group.isEmpty }, set: { if $0 { model.group = [] } })) {
                    Label("Mac speakers", systemImage: "laptopcomputer")
                }
            }
            Section("Sonos") {
                ForEach(Sample.rooms) { room in
                    Toggle(isOn: Binding(get: { model.group.contains(room.id) },
                                         set: { on in if on { model.group.insert(room.id) } else { model.group.remove(room.id) } })) {
                        Label(room.name, systemImage: "hifispeaker")
                    }
                }
            }
            Section {
                ForEach(Sample.phones) { phone in
                    LabeledContent {
                        Text("Later")
                    } label: {
                        Label(phone.name, systemImage: "iphone")
                    }
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Phones")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.checkbox)
        .frame(width: 280, height: 600)
    }
}
