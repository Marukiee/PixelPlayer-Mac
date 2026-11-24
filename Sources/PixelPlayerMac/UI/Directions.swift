import SwiftUI

/// Round 2: one native structure (sidebar, toolbar, inspector) with the player at the bottom,
/// in two ways: a bar across the whole window (A) or a glass capsule floating over the content (B).
struct RootView: View {
    @Environment(PlayerModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            switch model.direction {
            case .bar:
                VStack(spacing: 0) {
                    split
                    PlayerBar()
                }
            case .floating:
                split
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            model.startClock()
            Debug.windowAppeared()
        }
        .onChange(of: model.settingsRequest) { openSettings() }
    }

    private var split: some View {
        @Bindable var model = model
        return NavigationSplitView {
            Sidebar()
        } detail: {
            detail
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Zoeken")
    }

    private var detail: some View {
        @Bindable var model = model
        return ZStack {
            if model.fullPlayer {
                NowPlayingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                PageContent()
                    .transition(.opacity)
            }
        }
        // safeAreaBar gives the system's soft edge under the floating player, so content fades out beneath it.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if model.direction == .floating {
                FloatingPlayer()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle(model.fullPlayer ? "Speelt nu" : (model.searchText.isEmpty ? model.page.title : "Zoeken"))
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .inspector(isPresented: $model.showQueue) {
            QueueInspector()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
    }

    private var subtitle: String {
        guard !model.fullPlayer, model.searchText.isEmpty else { return "" }
        switch model.page {
        case .songs: return "1.284 nummers"
        case .liked: return "141 nummers"
        case .albums: return "96 albums"
        default: return ""
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.fullPlayer {
            ToolbarItem(placement: .navigation) {
                Button("Terug", systemImage: "chevron.left") { model.setFullPlayer(false) }
            }
        } else if model.page == .songs || model.page == .liked {
            ToolbarItemGroup {
                Button("Willekeurig", systemImage: "shuffle") {}
                Menu("Sorteren", systemImage: "arrow.up.arrow.down") {
                    Button("Titel") {}
                    Button("Artiest") {}
                    Button("Album") {}
                    Button("Laatst toegevoegd") {}
                }
            }
        } else if model.page == .albums || model.page == .artists || model.page == .playlists {
            ToolbarItem {
                Menu("Sorteren", systemImage: "arrow.up.arrow.down") {
                    Button("Naam") {}
                    Button("Laatst gespeeld") {}
                }
            }
        }
    }
}

/// The library in the system sidebar.
struct Sidebar: View {
    @Environment(PlayerModel.self) private var model

    var body: some View {
        List(selection: Binding(get: { model.searchText.isEmpty ? model.page : nil },
                                set: { page in
                                    guard let page else { return }
                                    model.searchText = ""
                                    model.page = page
                                    if model.fullPlayer { model.setFullPlayer(false) }
                                })) {
            Label(Page.home.title, systemImage: Page.home.symbol).tag(Page.home)
            Section("Bibliotheek") {
                ForEach(Page.library) { page in Label(page.title, systemImage: page.symbol).tag(page) }
            }
            Section("Afspeellijsten") {
                ForEach(Sample.playlists) { list in Label(list.title, systemImage: "music.note.list") }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
    }
}
