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
            .help(model.fullPlayer ? "Speelt nu sluiten" : "Speelt nu")
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
            Button { model.showDevices.toggle() } label: {
                Image(systemName: "hifispeaker.fill")
                    .foregroundStyle(model.group.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
            }
            .help("Verbinden · \(model.groupName)")
            .popover(isPresented: $model.showDevices, arrowEdge: .top) { DevicesPopover() }
            Button { withAnimation(Motion.panel) { model.showQueue.toggle() } } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(model.showQueue ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .help("Hierna")
        }
        .font(.title3)
        .buttonStyle(.borderless)
    }
}

/// A: one bar across the whole window, under the sidebar and the content, as in most Mac players.
struct PlayerBar: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    NowPlayingInfo()
                    LikeButton()
                }
                .frame(width: 270, alignment: .leading)
                Spacer(minLength: 16)
                VStack(spacing: 4) {
                    TransportButtons()
                    InlinePosition().frame(maxWidth: 440)
                }
                Spacer(minLength: 16)
                HStack(spacing: 16) {
                    PlayerSideButtons()
                    VolumeSlider(width: 84)
                }
                .frame(width: 270, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: 76)
        }
        .background(.bar)
    }
}

/// B: a glass capsule floating at the bottom of the content. The cover is round so it sits concentric
/// in the capsule: 56 high, 8 in, so a circle of 40.
struct FloatingPlayer: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            NowPlayingInfo(cover: 40, round: true)
                .frame(width: 190, alignment: .leading)
            TransportButtons(modes: false)
            InlinePosition()
                .frame(minWidth: 140, maxWidth: 300)
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
                    Text("Songtekst").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(lyrics.indices, id: \.self) { i in
                            Text(lyrics[i])
                                .font(.title3.weight(i == 2 ? .semibold : .regular))
                                .foregroundStyle(i == 2 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        }
                    }
                    Spacer(minLength: 0)
                    Text("44,1 kHz · 192 kbps · MP3").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 400, maxHeight: cover, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(24)
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
        List {
            Section {
                SongLine(song: model.current, playing: true, cover: 36)
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hierna").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Text("\(model.userQueue.count + model.upNext.count) nummers").foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button("Willekeurig", systemImage: "shuffle") {}
                        Button("Wachtrij wissen", systemImage: "trash") {}
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.bottom, 4)
            }
            Section("Zelf toegevoegd") {
                ForEach(model.userQueue) { SongLine(song: $0, queued: true) }
                    .onMove { model.userQueue.move(fromOffsets: $0, toOffset: $1) }
            }
            Section("Daarna uit je bibliotheek") {
                ForEach(model.upNext) { SongLine(song: $0) }
                    .onMove { model.upNext.move(fromOffsets: $0, toOffset: $1) }
            }
        }
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
            Section("Speelt op") {
                LabeledContent {
                    Button("Loskoppelen") { model.group = [] }.controlSize(.small)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.groupName)
                            Text(model.group.isEmpty ? "Luidsprekers van de Mac" : "Sonos").font(.caption).foregroundStyle(.secondary)
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
                    DisclosureGroup("Individueel volume", isExpanded: $model.individualVolume) {
                        ForEach(Sample.rooms.filter { model.group.contains($0.id) }) { room in
                            Slider(value: Binding(get: { model.volumes[room.id] ?? 0 }, set: { model.volumes[room.id] = $0 }), in: 0...100) {
                                Text(room.name)
                            }
                        }
                    }
                }
            }
            Section("Deze Mac") {
                Toggle(isOn: Binding(get: { model.group.isEmpty }, set: { if $0 { model.group = [] } })) {
                    Label("Luidsprekers van de Mac", systemImage: "laptopcomputer")
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
                Text("Telefoons")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.checkbox)
        .frame(width: 340, height: 600)
    }
}
