import ServiceManagement
import UniformTypeIdentifiers
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
            Tab("Developer", systemImage: "chevron.left.forwardslash.chevron.right", value: SettingsTab.developer) { DeveloperPane() }
        }
        .frame(width: 520)
    }
}

private struct GeneralPane: View {
    @LocalState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var menuBar: Binding<Bool> { Binding(get: { MenuBarSetting.shared.show }, set: { MenuBarSetting.shared.set($0) }) }
    @LocalState private var updater = Updater.shared
    @AppStorage("lyrics.hideSidebar") private var hideSidebarForLyrics = true

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
                Toggle("Player in the menu bar", isOn: menuBar)
                Toggle("Hide the sidebar while lyrics show", isOn: $hideSidebarForLyrics)
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
    @AppStorage("sonos.hires") private var hiRes = "flac"
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
                SecureField("Password", text: $password, prompt: Text(ServerSettings.savedAuth != nil ? "Saved" : ""))
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        statusText
                        Button(library.client == nil ? "Connect" : "Reconnect") {
                            Task { await library.connect(ServerSettings(server: server, user: user), password: password) }
                        }
                        .disabled(server.isEmpty || user.isEmpty || (password.isEmpty && ServerSettings.savedAuth == nil) || library.isSample)
                    }
                }
                SaveMixesToggle()
            } header: {
                Text("Navidrome")
            } footer: {
                Text("\(Text("Navidrome › Settings › Users").bold()). Only a login token is kept, not the password itself.")
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
                Picker("Hi-res songs", selection: $hiRes) {
                    Text("FLAC 48 kHz").tag("flac")
                    Text("MP3 320").tag("mp3")
                }
                .onChange(of: hiRes) { SonosOutput.shared.settingsChanged() }
            } header: {
                Text("Sonos")
            } footer: {
                Text("Speakers: addresses of speakers the search misses. Home address: how the speakers reach Navidrome, when this Mac uses another address (such as Tailscale). Hi-res: Sonos plays up to 48 kHz; for FLAC 48 kHz add in \(Text("Navidrome › Settings › Transcodings").bold()) one named flac, target format flac, command ffmpeg -i %s -ss %t -map 0:a:0 -v 0 -c:a flac -sample_fmt s16 -ar 48000 -f flac -")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Spotify") {
                LabeledContent("Account") { Text("Coming later").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 640)
        .onAppear {
            if library.isSample {
                server = "http://music.local:4533"; user = "listener"; password = "secret"
            } else if let saved = ServerSettings.saved {
                // The password is not kept, so the field stays empty; Reconnect uses the saved token.
                server = saved.server; user = saved.user; password = ""
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

/// Your Mix as a playlist on Navidrome, so every app shows the same one. Without an account grey, and only a click on it
/// says why: no lasting warning.
private struct SaveMixesToggle: View {
    @LocalState private var why = false
    private var library: Library { .shared }
    private var hasAccount: Bool { library.client != nil || library.isSample }
    private var on: Binding<Bool> {
        Binding(get: { hasAccount && library.saveMixes }, set: { library.answerMixQuestion(save: $0) })
    }

    var body: some View {
        Toggle(isOn: on) {
            Text("Save mixes to Navidrome")
            Text("Your Mix becomes a playlist on your server, so every app shows the same one.")
        }
        .disabled(!hasAccount)
        .overlay {
            // A greyed switch takes no clicks, so a clear layer over it takes them and tells why.
            if !hasAccount {
                Color.clear.contentShape(Rectangle()).onTapGesture { why = true }
            }
        }
        .popover(isPresented: $why, arrowEdge: .trailing) {
            Text("Connect to Navidrome first. Your mixes are saved to your account there.")
                .padding(12)
                .frame(width: 240)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// For finding out what happened and trying again: the welcome, the mixes, the server's list on disk, the Sonos log.
private struct DeveloperPane: View {
    @LocalState private var remaking = false
    @LocalState private var cacheGone = false
    private var library: Library { .shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("Welcome") {
                    Button("Show Again") {
                        PlayerModel.shared.onboardingStep = 0
                        PlayerModel.shared.onboardingOnlyMixes = false
                        PlayerModel.shared.showOnboarding = true
                    }
                }
            }
            Section {
                LabeledContent("Your Mix") {
                    HStack(spacing: 8) {
                        if remaking { ProgressView().controlSize(.small) }
                        Button("Make Again") {
                            remaking = true
                            Task {
                                await library.remakeMixes()
                                remaking = false
                            }
                        }
                        .disabled(remaking || library.isSample)
                    }
                }
                LabeledContent("Last sync") {
                    if let last = library.lastMixSync {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(last.date.formatted(date: .abbreviated, time: .shortened))
                            Text(last.text).foregroundStyle(last.failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        Text("Not yet").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Mixes")
            } footer: {
                Text(library.saveMixes ? "Make Again also writes Your Mix of today over the one on Navidrome."
                     : "Saving mixes to Navidrome is off, so Make Again only changes Your Mix on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Server cache") {
                    HStack(spacing: 8) {
                        Text(cacheGone || !library.serverCacheExists ? "Empty" : "server-library.json").foregroundStyle(.secondary)
                        Button("Clear") {
                            library.clearServerCache()
                            cacheGone = true
                        }
                        .disabled(cacheGone || !library.serverCacheExists)
                    }
                }
                LabeledContent("Sonos log") {
                    Button("Open") { NSWorkspace.shared.open(SonosLog.fileURL) }
                        .disabled(!FileManager.default.fileExists(atPath: SonosLog.fileURL.path))
                }
            } footer: {
                Text("The server cache is read at launch, before Navidrome answers. Cleared, the next launch loads everything from Navidrome again.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: Updater.shared.currentVersion)
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
            }
        }
        .formStyle(.grouped)
        .frame(height: 500)
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
    @AppStorage("appearance.mode") private var theme = "Dark"
    @LocalState private var accent = "Green"
    @LocalState private var fromCover = false

    var body: some View {
        Form {
            Section {
                // Dark, as Spotify, also by day; light only when chosen here (Mark, 2026-11-26).
                Picker("Mode", selection: $theme) {
                    ForEach(["Dark", "Light"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { Appearance.apply(theme) }
            }
            FontSection()
            Section {
                Picker("Accent colour", selection: $accent) {
                    ForEach(["Green", "Blue", "Purple", "Pink"], id: \.self) { Text($0) }
                }
                Toggle("Colour from the cover in Now Playing", isOn: $fromCover)
            } footer: {
                Text("Other accent colours come in a later version.").foregroundStyle(.secondary)
            }
            .disabled(true)
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

/// Spotify's own letter, Mix, can't come with the app: it is imported here, as it downloads (a zip, the folder a browser
/// unpacks it to, or font files), with the button or by dropping it on the row. Without it: Figtree and the system's font.
private struct FontSection: View {
    @LocalState private var store = FontStore.shared
    @LocalState private var targeted = false

    /// Where Mark gets the font (his choice, 2026-11-26).
    private static let source = URL(string: "https://en.bestfonts.pro/font/spotify-mix")!

    var body: some View {
        Section {
            LabeledContent("Font") {
                HStack(spacing: 8) {
                    if store.importing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(store.name.map { "\($0), \(store.styleCount) styles" } ?? "Default").foregroundStyle(.secondary)
                    }
                    if store.available {
                        Button("Use Default") { store.useDefault() }
                    }
                    Button("Import Font…") { choose() }
                        .disabled(store.importing)
                }
            }
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(targeted ? 0.15 : 0)).padding(-4))
            .dropDestination(for: URL.self) { urls, _ in
                store.importFonts(from: urls)
                return !urls.isEmpty
            } isTargeted: { targeted = $0 }
        } footer: {
            HStack(spacing: 6) {
                if let problem = store.problem {
                    Text(problem + ".").foregroundStyle(.secondary)
                }
                Link("Get the Font", destination: Self.source)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, .font, .folder] + ["ttf", "otf", "woff", "woff2"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Import"
        panel.message = "Choose the font as it downloaded: the zip, its folder or the font files."
        if panel.runModal() == .OK { store.importFonts(from: panel.urls) }
    }
}

/// Dark for the whole app, as Spotify, whatever the Mac is set to and also by day; light only when chosen in Settings.
@MainActor
enum Appearance {
    static func apply(_ mode: String) {
        // A scripted run sets its own appearance.
        guard !Debug.active else { return }
        NSApp.appearance = NSAppearance(named: mode == "Light" ? .aqua : .darkAqua)
    }

    /// The saved choice, with the old "System" (from before dark was the rule) read as dark.
    static var saved: String {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "appearance.mode") == "System" { defaults.set("Dark", forKey: "appearance.mode") }
        return defaults.string(forKey: "appearance.mode") ?? "Dark"
    }
}
