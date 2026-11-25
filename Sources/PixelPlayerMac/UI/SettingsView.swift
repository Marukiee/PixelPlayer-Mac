import ServiceManagement
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
    @LocalState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("menubar.show") private var menuBar = true
    @LocalState private var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        if launchAtLogin { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                    // Only the installed app opens at login, not a development build.
                    .disabled(Updater.isDevelopmentBuild)
                Toggle("Player in the menu bar", isOn: $menuBar)
                LabeledContent("Welcome") {
                    Button("Show Again") {
                        PlayerModel.shared.onboardingStep = 0
                        PlayerModel.shared.showOnboarding = true
                    }
                }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.autoCheck)
                    .disabled(Updater.isDevelopmentBuild)
                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(Updater.isDevelopmentBuild ? "\(updater.currentVersion), development build" : updaterStatus)
                            .foregroundStyle(.secondary)
                        Button("Check Now") { Task { await updater.check(manual: true) } }
                            .disabled(Updater.isDevelopmentBuild || updater.state == .checking)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }

    private var updaterStatus: String {
        switch updater.state {
        case .checking: "\(updater.currentVersion), checking…"
        case .upToDate: "\(updater.currentVersion), up to date"
        case .available(let release): "\(release.version) is ready, see the top of the window"
        case .failed(let message): "\(updater.currentVersion). \(message)"
        default: updater.currentVersion
        }
    }
}

private struct SourcesPane: View {
    @Environment(PlayerModel.self) private var model
    @AppStorage("music.watch") private var watch = true
    @LocalState private var server = ""
    @LocalState private var user = ""
    @LocalState private var password = ""
    @LocalState private var folder = MusicFolder.path
    @LocalState private var sonos = UserDefaults.standard.object(forKey: "sonos.search") as? Bool ?? true
    @LocalState private var sonosHosts = UserDefaults.standard.string(forKey: "sonos.hosts") ?? ""
    @LocalState private var sonosHome = UserDefaults.standard.string(forKey: "sonos.home") ?? ""
    @LocalState private var remoteHosts = UserDefaults.standard.string(forKey: "remote.hosts") ?? ""

    private var library: Library { Library.shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(folder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None").foregroundStyle(.secondary)
                        Button("Choose…") {
                            if let chosen = MusicFolder.choose() {
                                folder = chosen
                                Task { await library.scanLocal() }
                            }
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
            Section {
                TextField("Over the network", text: $remoteHosts, prompt: Text("192.168.1.20:47123 Pixel"))
                    .onChange(of: remoteHosts) { UserDefaults.standard.set(remoteHosts, forKey: "remote.hosts") }
            } header: {
                Text("Phones")
            } footer: {
                Text("Pair the phone with this Mac, then on the phone: \(Text("PixelPlayer › Settings › Play from › Use this phone as remote player").bold()). It shows up in Connect.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Find speakers on this network", isOn: $sonos)
                    .onChange(of: sonos) { UserDefaults.standard.set(sonos, forKey: "sonos.search"); SonosOutput.shared.settingsChanged() }
                TextField("Speakers", text: $sonosHosts, prompt: Text("192.168.1.30"))
                    .onChange(of: sonosHosts) { UserDefaults.standard.set(sonosHosts, forKey: "sonos.hosts"); SonosOutput.shared.settingsChanged() }
                TextField("Home address", text: $sonosHome, prompt: Text("http://192.168.1.10:4533"))
                    .onChange(of: sonosHome) { UserDefaults.standard.set(sonosHome, forKey: "sonos.home") }
                LabeledContent("Found", value: SonosOutput.shared.rooms.isEmpty ? "None yet" : "\(SonosOutput.shared.rooms.count) rooms")
            } header: {
                Text("Sonos")
            } footer: {
                Text("Speakers: addresses of speakers the search misses. Home address: how the speakers reach Navidrome, when this Mac uses another address (such as Tailscale).")
                    .foregroundStyle(.secondary)
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
        case .ready:
            Text(library.client == nil ? "\(library.songs.count.formatted()) songs on this Mac"
                 : "Connected · \(library.serverSongCount.formatted()) songs on the server").foregroundStyle(.secondary)
        case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(2)
        }
    }
}

private struct PlaybackPane: View {
    @LocalState private var crossfade = false
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
            Section {
                Picker("Preset", selection: $preset) {
                    ForEach(["Off", "Acoustic", "Bass Booster", "Electronic", "Spoken Word"], id: \.self) { Text($0) }
                }
            } header: {
                Text("Equalizer")
            } footer: {
                Text("Crossfade, normalising and the equalizer come in a later version.").foregroundStyle(.secondary)
            }
        }
        // Grey until they work, so nothing here pretends to do something.
        .disabled(true)
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct AppearancePane: View {
    @AppStorage("appearance.mode") private var theme = "System"
    @LocalState private var accent = "Blue"
    @LocalState private var fromCover = false

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $theme) {
                    ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { Appearance.apply(theme) }
            }
            Section {
                Picker("Accent colour", selection: $accent) {
                    ForEach(["Blue", "Purple", "Pink", "Green"], id: \.self) { Text($0) }
                }
                Toggle("Colour from the cover in Now Playing", isOn: $fromCover)
            } footer: {
                Text("Other accent colours come in a later version.").foregroundStyle(.secondary)
            }
            .disabled(true)
        }
        .formStyle(.grouped)
        .frame(height: 220)
    }
}

/// Light, dark or the system's choice, for the whole app.
@MainActor
enum Appearance {
    static func apply(_ mode: String) {
        // A scripted run sets its own appearance.
        guard !Debug.active else { return }
        switch mode {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
