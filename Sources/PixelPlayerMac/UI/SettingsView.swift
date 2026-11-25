import SwiftUI
import PixelPlayerKit

/// The Settings window of a Mac app: tabs in the toolbar and grouped forms with the system's own rows.
struct SettingsView: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) { GeneralPane() }
            Tab("Sources", systemImage: "music.note.house", value: SettingsTab.sources) { SourcesPane() }
            Tab("Playback", systemImage: "play.circle", value: SettingsTab.playback) { PlaybackPane() }
            Tab("Appearance", systemImage: "paintpalette", value: SettingsTab.appearance) { AppearancePane() }
        }
        .frame(width: 520)
    }
}

private struct GeneralPane: View {
    @LocalState private var launchAtLogin = false
    @LocalState private var menuBar = true
    @LocalState private var autoUpdate = true

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                Toggle("Player in the menu bar", isOn: $menuBar)
            }
            Section("Updates") {
                Toggle("Update automatically", isOn: $autoUpdate)
                LabeledContent("Version", value: "0.1, design prototype")
            }
        }
        .formStyle(.grouped)
        .frame(height: 262)
    }
}

private struct SourcesPane: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var watch = true
    @LocalState private var server = ""
    @LocalState private var user = ""
    @LocalState private var password = ""
    @LocalState private var folder = MusicFolder.path
    @LocalState private var sonos = true

    private var library: Library { Library.shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(folder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None").foregroundStyle(.secondary)
                        Button("Choose…") {
                            if let chosen = MusicFolder.choose() { folder = chosen }
                        }
                    }
                }
                Toggle("Add new songs automatically", isOn: $watch)
            } header: {
                Text("Music on this Mac")
            } footer: {
                Text("A song that is both here and on the server always plays from this Mac.").foregroundStyle(.secondary)
            }
            Section {
                TextField("Server", text: $server, prompt: Text("http://server:4533"))
                TextField("User", text: $user)
                SecureField("Password", text: $password)
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        statusText
                        Button(library.client == nil ? "Connect" : "Reconnect") {
                            Task { await library.connect(ServerSettings(server: server, user: user), password: password) }
                        }
                        .disabled(server.isEmpty || user.isEmpty || password.isEmpty || library.isSample)
                    }
                }
            } header: {
                Text("Navidrome")
            } footer: {
                Text("\(Text("Navidrome › Settings › Users").bold()). The password stays in your keychain.")
                    .foregroundStyle(.secondary)
            }
            Section("Sonos") {
                Toggle("Find speakers on this network", isOn: $sonos)
                LabeledContent("Found", value: library.isSample ? "4 rooms" : "Coming in the next step")
            }
            Section("Spotify") {
                LabeledContent("Account") { Text("Coming later").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 600)
        .onAppear {
            if library.isSample {
                server = "http://music.local:4533"; user = "listener"; password = "secret"
            } else if let saved = ServerSettings.saved {
                server = saved.server; user = saved.user; password = Keychain.password(for: saved.user) ?? ""
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch library.status {
        case .sample: Text("Connected · 1,284 songs").foregroundStyle(.secondary)
        case .notConnected: Text("Not connected").foregroundStyle(.secondary)
        case .loading(let what): HStack(spacing: 6) { ProgressView().controlSize(.small); Text(what).foregroundStyle(.secondary) }
        case .ready: Text("Connected · \(library.songs.count.formatted()) songs").foregroundStyle(.secondary)
        case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(2)
        }
    }
}

private struct PlaybackPane: View {
    @LocalState private var crossfade = true
    @LocalState private var seconds = 4.0
    @LocalState private var normalize = false
    @LocalState private var preset = "Off"

    var body: some View {
        Form {
            Section {
                Toggle("Crossfade", isOn: $crossfade)
                LabeledContent("Length") {
                    HStack {
                        Slider(value: $seconds, in: 1...12, step: 1).frame(width: 180)
                        Text("\(Int(seconds)) s").monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                }
                .disabled(!crossfade)
                Toggle("Normalise volume", isOn: $normalize)
            }
            Section("Equalizer") {
                Picker("Preset", selection: $preset) {
                    ForEach(["Off", "Acoustic", "Bass Booster", "Electronic", "Spoken Word"], id: \.self) { Text($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct AppearancePane: View {
    @LocalState private var theme = "System"
    @LocalState private var accent = "Blue"
    @LocalState private var fromCover = false

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $theme) {
                    ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                Picker("Accent colour", selection: $accent) {
                    ForEach(["Blue", "Purple", "Pink", "Green"], id: \.self) { Text($0) }
                }
                Toggle("Colour from the cover in Now Playing", isOn: $fromCover)
            }
        }
        .formStyle(.grouped)
        .frame(height: 220)
    }
}
