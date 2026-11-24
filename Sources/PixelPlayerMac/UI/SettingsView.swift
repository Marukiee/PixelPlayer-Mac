import SwiftUI

/// The Settings window of a Mac app: tabs in the toolbar and grouped forms with the system's own rows.
struct SettingsView: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("Algemeen", systemImage: "gearshape", value: SettingsTab.general) { GeneralPane() }
            Tab("Bronnen", systemImage: "music.note.house", value: SettingsTab.sources) { SourcesPane() }
            Tab("Afspelen", systemImage: "play.circle", value: SettingsTab.playback) { PlaybackPane() }
            Tab("Uiterlijk", systemImage: "paintpalette", value: SettingsTab.appearance) { AppearancePane() }
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
                Toggle("Openen bij inloggen", isOn: $launchAtLogin)
                Toggle("Speler in de menubalk", isOn: $menuBar)
            }
            Section("Updates") {
                Toggle("Automatisch bijwerken", isOn: $autoUpdate)
                LabeledContent("Versie", value: "0.1, ontwerpproef")
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct SourcesPane: View {
    @LocalState private var watch = true
    @LocalState private var server = "http://muziek.local:4533"
    @LocalState private var user = "luisteraar"
    @LocalState private var password = "geheim"
    @LocalState private var sonos = true

    var body: some View {
        Form {
            Section("Muziek op deze Mac") {
                LabeledContent("Map") {
                    HStack {
                        Text("~/Muziek").foregroundStyle(.secondary)
                        Button("Kies…") {}
                    }
                }
                Toggle("Nieuwe nummers vanzelf toevoegen", isOn: $watch)
            }
            Section {
                TextField("Server", text: $server)
                TextField("Gebruiker", text: $user)
                SecureField("Wachtwoord", text: $password)
            } header: {
                Text("Navidrome")
            } footer: {
                Text("\(Text("Navidrome › Instellingen › Gebruikers").bold()). Het wachtwoord blijft in de sleutelhanger.")
                    .foregroundStyle(.secondary)
            }
            Section("Sonos") {
                Toggle("Speakers op dit netwerk zoeken", isOn: $sonos)
                LabeledContent("Gevonden", value: "4 ruimtes")
            }
            Section("Spotify") {
                LabeledContent("Account") { Button("Inloggen…") {} }
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
    @LocalState private var preset = "Uit"

    var body: some View {
        Form {
            Section {
                Toggle("Crossfade", isOn: $crossfade)
                LabeledContent("Duur") {
                    HStack {
                        Slider(value: $seconds, in: 1...12, step: 1).frame(width: 180)
                        Text("\(Int(seconds)) s").monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                }
                .disabled(!crossfade)
                Toggle("Volume gelijk trekken", isOn: $normalize)
            }
            Section("Equalizer") {
                Picker("Voorkeur", selection: $preset) {
                    ForEach(["Uit", "Akoestisch", "Bas versterken", "Elektronisch", "Spraak"], id: \.self) { Text($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct AppearancePane: View {
    @LocalState private var theme = "Systeem"
    @LocalState private var accent = "Blauw"
    @LocalState private var fromCover = false

    var body: some View {
        Form {
            Section {
                Picker("Weergave", selection: $theme) {
                    ForEach(["Systeem", "Licht", "Donker"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                Picker("Accentkleur", selection: $accent) {
                    ForEach(["Blauw", "Paars", "Roze", "Groen"], id: \.self) { Text($0) }
                }
                Toggle("Kleur uit de hoes in Speelt nu", isOn: $fromCover)
            }
        }
        .formStyle(.grouped)
        .frame(height: 220)
    }
}
