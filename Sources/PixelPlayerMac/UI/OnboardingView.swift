import SwiftUI
import PixelPlayerKit

/// The welcome at first launch, as a sheet over the window in the style of the Mac's own setup: one thing per step, the
/// same grouped rows as Settings, and every step can be skipped. Everything in it can be changed later in Settings.
struct OnboardingView: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var server = ServerSettings.saved?.server ?? ""
    @LocalState private var user = ServerSettings.saved?.user ?? ""
    @LocalState private var password = ""
    @LocalState private var folder = MusicFolder.path
    @LocalState private var findSpeakers = UserDefaults.standard.object(forKey: "sonos.search") as? Bool ?? true

    private var library: Library { .shared }

    enum Page { case welcome, music, navidrome, mixes, sonos, more }

    /// The steps there are now: the mixes question only with an account, and only that one for someone who saw the
    /// welcome before it existed.
    private var pages: [Page] {
        if model.onboardingOnlyMixes { return [.mixes] }
        return [.welcome, .music, .navidrome] + (hasAccount ? [.mixes] : []) + [.sonos, .more]
    }

    private var page: Page { pages[min(max(model.onboardingStep, 0), pages.count - 1)] }
    private var isLast: Bool { model.onboardingStep >= pages.count - 1 }
    /// The made-up music of the design shots counts as connected, as it does in Settings.
    private var hasAccount: Bool { library.client != nil || library.isSample }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .welcome: welcome
                case .music: musicHere
                case .navidrome: navidrome
                case .mixes: mixes
                case .sonos: sonos
                case .more: more
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(model.onboardingStep)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            footer
        }
        .frame(width: 600, height: 500)
        .animation(Motion.panel, value: model.onboardingStep)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("Welcome to PixelPlayer").titleFont(32)
            Text("Your music from this Mac and from your Navidrome server in one place, on your speakers and your phone too. A few steps and you are listening.")
                .font(.mix(16)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            Spacer(minLength: 0)
        }
        .padding(32)
    }

    private var musicHere: some View {
        step(symbol: "folder.fill", title: "Music on this Mac",
             text: "Pick the folder with your music. A song that is here and on your server always plays from this Mac.") {
            Form {
                LabeledContent("Folder") {
                    HStack {
                        Text(folder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None").foregroundStyle(.secondary).lineLimit(1)
                        Button("Choose…") {
                            if let chosen = MusicFolder.choose() {
                                folder = chosen
                                Task { await library.scanLocal() }
                            }
                        }
                        .focusable(false)
                    }
                }
                LabeledContent("Found", value: localCount == 0 ? "No songs yet" : "\(localCount.formatted()) songs")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    private var navidrome: some View {
        step(symbol: "server.rack", title: "Navidrome",
             text: "Connect your server for the rest of your library, your playlists, your likes and your listens. No server? Skip this step.") {
            Form {
                Section {
                    TextField("Server", text: $server, prompt: Text("http://server:4533"))
                    TextField("User", text: $user)
                    SecureField("Password", text: $password)
                    LabeledContent("Status") {
                        HStack(spacing: 8) {
                            serverStatus
                            Button(library.client == nil ? "Connect" : "Reconnect") {
                                Task { await library.connect(ServerSettings(server: server, user: user), password: password) }
                            }
                            .disabled(server.isEmpty || user.isEmpty || password.isEmpty || library.isSample)
                            .focusable(false)
                        }
                    }
                } footer: {
                    Text("\(Text("Navidrome › Settings › Users").bold()). Only a login token is kept, not the password itself.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    /// As SpotCopy asks it (STIJL.md › Onboarding): two mix covers fanned out, the question and a line under it. The
    /// answers are the Mac's own buttons below.
    private var mixes: some View {
        VStack(spacing: 0) {
            MixFan().frame(height: 236).padding(.top, 40)
            Text("Save your mixes to Navidrome?").titleFont(28).multilineTextAlignment(.center).padding(.top, 20)
            Text("Your Mix becomes a playlist on your server, so every app you use shows the same one. You can change this in Settings.")
                .font(.mix(15)).foregroundStyle(PP.subdued).multilineTextAlignment(.center).frame(maxWidth: 420).padding(.top, 12)
        }
        .padding(.horizontal, 32)
    }

    private var sonos: some View {
        step(symbol: "hifispeaker.2.fill", title: "Sonos",
             text: "Play on your speakers from this Mac, in one room or several. macOS asks once if PixelPlayer may look on this network.") {
            Form {
                Toggle("Find speakers on this network", isOn: $findSpeakers)
                    .onChange(of: findSpeakers) {
                        UserDefaults.standard.set(findSpeakers, forKey: "sonos.search")
                        SonosOutput.shared.settingsChanged()
                        if findSpeakers { SonosOutput.shared.connectShown(true) }
                    }
                LabeledContent("Found") {
                    let rooms = SonosOutput.shared.rooms
                    Text(rooms.isEmpty ? (findSpeakers ? "Looking…" : "Off") : rooms.map(\.name).joined(separator: ", "))
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .onAppear { if findSpeakers { SonosOutput.shared.connectShown(true) } }
        .onDisappear { SonosOutput.shared.connectShown(false) }
    }

    private var more: some View {
        step(symbol: "iphone.gen3", title: "More places to play",
             text: "Everything is ready. These come up in Connect, next to the player.") {
            Form {
                LabeledContent {
                    EmptyView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your phone")
                            Text("Pair it with this Mac, then on the phone: \(Text("PixelPlayer › Settings › Play from › Use this phone as remote player").bold()).")
                                .font(.mix(12)).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "iphone") }
                }
                LabeledContent {
                    Text("Later").foregroundStyle(.secondary)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spotify")
                            Text("Comes in a later version of PixelPlayer.").font(.mix(12)).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "music.note.list") }
                }
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    // MARK: Pieces

    private var localCount: Int { library.songs.filter(\.isLocal).count }

    @ViewBuilder private var serverStatus: some View {
        if library.client == nil {
            if case .loading(let what) = library.status {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(what).foregroundStyle(.secondary) }
            } else if case .failed(let reason) = library.status {
                Text(reason).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Not connected").foregroundStyle(.secondary)
            }
        } else {
            Text("Connected").foregroundStyle(.secondary)
        }
    }

    /// One step: a symbol in a tinted square, a title, a line of text, and what is to be set.
    private func step<Content: View>(symbol: String, title: String, text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(PP.onPrimary)
                .frame(width: 64, height: 64)
                .background(PP.primary.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 36)
            Text(title).titleFont(24)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            content().frame(maxWidth: 520)
        }
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            // Where you are: one dot per step, none when there is only the one question.
            if pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle().fill(index == model.onboardingStep ? AnyShapeStyle(PP.primary) : AnyShapeStyle(Color.primary.opacity(0.18)))
                            .frame(width: 7, height: 7)
                    }
                }
            }
            Spacer()
            if model.onboardingStep > 0 {
                Button("Back") { model.onboardingStep -= 1 }
                    .controlSize(.large)
                    .focusable(false)
            }
            if page == .mixes {
                // The answer goes on at once: Not now or Yes, no Continue.
                Button("Not now") { answer(false) }
                    .controlSize(.large)
                    .focusable(false)
                Button("Yes") { answer(true) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .focusable(false)
            } else {
                if page == .navidrome && library.client == nil || page == .sonos && !findSpeakers {
                    Button("Skip") { model.onboardingStep += 1 }
                        .controlSize(.large)
                        .focusable(false)
                }
                Button(primaryTitle) { next() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    // No blue ring: Return presses it, the pointer clicks it.
                    .focusable(false)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var primaryTitle: String {
        if page == .welcome { return "Get Started" }
        return isLast ? "Start Listening" : "Continue"
    }

    private func next() {
        if isLast { finish() } else { model.onboardingStep += 1 }
    }

    private func answer(_ save: Bool) {
        library.answerMixQuestion(save: save)
        next()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarding.done")
        model.showOnboarding = false
        model.onboardingOnlyMixes = false
    }
}

/// Two mix covers fanned out, as on SpotCopy's question: Your Mix in front, the Daily Mix behind it leaning left and
/// higher so its name stays in sight. With the first covers of the library, else only their colours.
private struct MixFan: View {
    private var library: Library { .shared }

    var body: some View {
        let albums = library.albums
        ZStack {
            DailyMixCover(title: "Daily Mix", pair: 6, album: albums.count > 1 ? albums[1] : nil)
                .frame(width: 168, height: 168)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .rotationEffect(.degrees(-8))
                .offset(x: -78, y: -26)
            DailyMixCover(title: "Your Mix", pair: 5, album: albums.first)
                .frame(width: 168, height: 168)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .rotationEffect(.degrees(6))
                .offset(x: 62, y: 14)
        }
    }
}
