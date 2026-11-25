import SwiftUI

/// The panel under the menu bar icon: the mini player for when the window is closed, with the
/// system's own buttons and sliders.
struct MenuBarPanel: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CoverArt(album: model.current.album, radius: 6).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.current.title).font(.headline)
                    Text(model.current.artist).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                LikeButton()
            }
            PositionSlider(small: true)
            HStack {
                Spacer()
                TransportButtons()
                Spacer()
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker").foregroundStyle(.tint)
                Text(model.groupName).lineLimit(1)
                Spacer()
                Menu("Change") {
                    ForEach(Sample.rooms) { room in
                        Toggle(room.name, isOn: Binding(get: { model.group.contains(room.id) },
                                                        set: { on in if on { model.group.insert(room.id) } else { model.group.remove(room.id) } }))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            VolumeSlider(width: nil)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Up Next").font(.headline)
                    Spacer()
                    Text("\(model.userQueue.count + model.upNext.count) songs").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.userQueue.prefix(2)) { SongLine(song: $0, queued: true, cover: 28) }
                SongLine(song: model.upNext[0], cover: 28)
            }
            Divider()
            HStack {
                Button("Open PixelPlayer") {}
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// For the screenshot only: the menu bar panel over a quiet desktop, so its material has something to show.
struct MenuBarStage: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: scheme == .dark ? [Color(hex: 0x1B2450), Color(hex: 0x4A2C6E), Color(hex: 0x0D1A33)]
                                                   : [Color(hex: 0x8FB4FF), Color(hex: 0xF3B8D9), Color(hex: 0xFFE3B8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: "music.note").font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 20).background(RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.15)))
                Image(systemName: "wifi").font(.system(size: 12, weight: .semibold))
                Image(systemName: "battery.100").font(.system(size: 13, weight: .semibold))
                Text("Tue 24 Nov  21:41").font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14).frame(height: 28)
            .background(.ultraThinMaterial)
            MenuBarPanel()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                .padding(.top, 33).padding(.trailing, 112)
        }
        .frame(width: 560, height: 640)
    }
}
