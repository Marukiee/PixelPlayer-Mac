import SwiftUI

// MARK: Player bars

/// The song that plays: cover, title and artist. A click on the cover opens Speelt nu.
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
            .help(model.fullPlayer ? "Close Now Playing" : "Now Playing")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.current.title).fontWeight(.semibold)
                Text(model.current.artist).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

/// The two buttons on the right of every player: where it plays, and what plays next.
struct PlayerSideButtons: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 16) {
            // Lyrics at a glance: opens Now Playing, where the lyrics sit beside the cover.
            Button { model.setFullPlayer(!model.fullPlayer) } label: {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(model.fullPlayer ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .help("Lyrics")
            Button { model.showDevices.toggle() } label: {
                Image(systemName: "hifispeaker")
                    .foregroundStyle(model.group.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
            }
            .help("Connect · \(model.groupName)")
            .popover(isPresented: $model.showDevices, arrowEdge: .top) { DevicesPopover() }
            Button { withAnimation(Motion.panel) { model.showQueue.toggle() } } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(model.showQueue ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .help("Up Next")
        }
        .font(.title3)
        .buttonStyle(.borderless)
    }
}

/// The player: a glass capsule floating at the bottom of the content. The cover is round so it sits concentric
/// in the capsule: 56 high, 8 in, so a circle of 40.
struct FloatingPlayer: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            NowPlayingInfo(cover: 40, round: true)
                .frame(minWidth: 120, maxWidth: 190, alignment: .leading)
            TransportButtons(modes: false)
            InlinePosition()
                .frame(minWidth: 90, maxWidth: 300)
            PlayerSideButtons()
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: Speelt nu

/// The full player: the cover large and the lyrics beside it. The controls stay where they always are,
/// in the player at the bottom, so nothing is shown twice.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var model
    private let lyrics = [
        "The streetlights hum a quiet tune",
        "The city folds into the blue",
        "We wait between the day and night",
        "Two coffees going cold",
        "Your coat still on the chair",
        "The radio is low",
        "And everything is slow",
    ]

    var body: some View {
        GeometryReader { geo in
            let cover = min(geo.size.height - 64, geo.size.width * 0.44, 440)
            HStack(alignment: .center, spacing: 40) {
                CoverArt(album: model.current.album, radius: 10)
                    .frame(width: cover, height: cover)
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blue Hour Sessions · 2023").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.current.title).font(.largeTitle.weight(.bold))
                            Spacer()
                            LikeButton().font(.title2)
                        }
                        Text(model.current.artist).font(.title2).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Lyrics").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(lyrics.indices, id: \.self) { i in
                            Text(lyrics[i])
                                .font(.title3.weight(i == 2 ? .semibold : .regular))
                                .foregroundStyle(i == 2 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        }
                    }
                    Spacer(minLength: 0)
                    Text("44.1 kHz · 192 kbps · MP3").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 400, maxHeight: cover, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(24)
        .overlay(alignment: .topLeading) {
            Button { model.setFullPlayer(false) } label: {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    .frame(width: 40, height: 40).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .help("Close Now Playing")
            .padding(.leading, 28).padding(.top, 28)
        }
        .background {
            ZStack {
                CoverArt(album: model.current.album, radius: 0)
                    .scaledToFill()
                    .blur(radius: 70)
                    .opacity(0.5)
                Rectangle().fill(.regularMaterial)
            }
            .clipped()
            .ignoresSafeArea()
        }
    }
}

// MARK: Queue

/// What plays next, in the inspector on the right: a plain list with sections, rows can be dragged.
struct QueueInspector: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // The title on the same line as the top of the page beside it: 28 points down, like the side margins.
            HStack(alignment: .firstTextBaseline) {
                Text("Up Next").font(.title3.weight(.semibold))
                Text("\(model.userQueue.count + model.upNext.count) songs").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Shuffle", systemImage: "shuffle") {}
                    Button("Clear queue", systemImage: "trash") {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 4)
            List {
                Section("Now playing") {
                    SongLine(song: model.current, playing: true, cover: 48).padding(.vertical, 3)
                }
                Section("Added by you") {
                    ForEach(model.userQueue) { SongLine(song: $0, queued: true, cover: 40).padding(.vertical, 3) }
                        .onMove { model.userQueue.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("Then from your library") {
                    ForEach(model.upNext) { SongLine(song: $0, cover: 40).padding(.vertical, 3) }
                        .onMove { model.upNext.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .ignoresSafeArea(.container, edges: .top)
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
