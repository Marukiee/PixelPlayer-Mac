import SwiftUI

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
    @LocalState private var watch = true
    @LocalState private var server = "http://music.local:4533"
    @LocalState private var user = "listener"
    @LocalState private var password = "geheim"
    @LocalState private var sonos = true

    var body: some View {
        Form {
            Section("Music on this Mac") {
                LabeledContent("Folder") {
                    HStack {
                        Text("~/Music").foregroundStyle(.secondary)
                        Button("Choose…") {}
                    }
                }
                Toggle("Add new songs automatically", isOn: $watch)
            }
            Section {
                TextField("Server", text: $server)
                TextField("User", text: $user)
                SecureField("Password", text: $password)
            } header: {
                Text("Navidrome")
            } footer: {
                Text("\(Text("Navidrome › Settings › Users").bold()). The password stays in your keychain.")
                    .foregroundStyle(.secondary)
            }
            Section("Sonos") {
                Toggle("Find speakers on this network", isOn: $sonos)
                LabeledContent("Found", value: "4 rooms")
            }
            Section("Spotify") {
                LabeledContent("Account") { Button("Sign In…") {} }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
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
