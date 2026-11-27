import SwiftUI
import PixelPlayerKit

// MARK: The panel under the search field

/// Spotify's panel under the search field, measured from Mark's screenshots (2026-11-27, one Spotify pixel is 1.667 of
/// his at 83%): as wide as the field, 4 under it, #2A2A2A with a corner of 8, at most 400 high. With nothing typed it
/// lists the recent searches; while typing a line with the keys, four suggestions to search for (the typed part bold),
/// then songs, artists, albums and playlists to open at once. Enter searches, or opens the row the arrow keys are on.
@MainActor @Observable
final class SearchPanel {
    static let shared = SearchPanel()

    /// The field, in the window's space over the zoom (MenuPresenter.space), so the panel can hang under it.
    var fieldFrame: CGRect = .zero
    /// Whether the typing cursor is in the field.
    var focused = false
    /// Closed by Enter, Esc or a pick, until the next key or click in the field.
    var dismissed = false
    /// The row the arrow keys are on.
    var highlighted: Int?
    /// The mouse button is down on the panel. macOS takes the cursor out of the field at that moment; the panel stays
    /// until the button comes up, so the click on a row counts (it closed before, and the row never opened).
    var holding = false
    /// Where the panel is, in the same space: a click there does not end the typing.
    @ObservationIgnored var panelFrame: CGRect = .zero

    private var model: PlayerModel { .shared }
    @ObservationIgnored private var cache: (draft: String, recents: [String], rows: [SearchPanelRow])?
    @ObservationIgnored private var keys: Any?
    @ObservationIgnored private var mouseUps: Any?

    var isOpen: Bool { (focused || holding) && !dismissed && fieldFrame != .zero && !rows.isEmpty }

    /// What the panel shows for what is typed now, worked out once per text.
    var rows: [SearchPanelRow] {
        let draft = model.searchDraft.trimmingCharacters(in: .whitespaces)
        let recents = SearchHistory.shared.codes
        if let cache, cache.draft == draft, cache.recents == recents { return cache.rows }
        var rows = draft.isEmpty ? recents.compactMap(RecentSearch.init(code:)).map(SearchPanelRow.init(recent:))
            : Self.suggestions(for: draft).map(SearchPanelRow.suggestion) + Self.results(for: draft)
        // Nothing in the library for it: the typed text itself to search for, so the panel and Enter still say what happens.
        if rows.isEmpty, !draft.isEmpty { rows = [.suggestion(draft)] }
        cache = (draft, recents, rows)
        return rows
    }

    func typingStarted() {
        dismissed = false
        highlighted = nil
        installKeys()
    }

    /// Enter: the row the arrow keys are on, or a search for what is typed.
    func submit() {
        if let highlighted, rows.indices.contains(highlighted) {
            open(rows[highlighted])
        } else {
            let draft = model.searchDraft.trimmingCharacters(in: .whitespaces)
            guard !draft.isEmpty else { return }
            search(draft)
        }
    }

    func open(_ row: SearchPanelRow) {
        switch row {
        case .suggestion(let text):
            search(text)
            return
        case .song(let song):
            SearchHistory.shared.remember(SearchHistory.code(song: song))
            model.play(song, in: Library.shared.songs(for: .album(song.album.id)))
        case .album(let album):
            SearchHistory.shared.remember(SearchHistory.code(album: album))
            model.go(.album(album.id))
        case .artist(let name, _):
            SearchHistory.shared.remember(SearchHistory.code(artist: name))
            model.go(.artist(name))
        case .playlist(let playlist):
            model.go(.playlist(playlist.id))
        }
        close()
    }

    /// The results page for this text; the field keeps it.
    private func search(_ text: String) {
        model.searchText = text
        dismissed = true
        highlighted = nil
    }

    /// Esc, or a pick: the panel goes and the typing ends.
    func close() {
        dismissed = true
        highlighted = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Whether a click at this point of the window lands on the panel.
    func contains(_ locationInWindow: NSPoint, in window: NSWindow) -> Bool {
        guard isOpen, let content = window.contentView else { return false }
        let zoom = ZoomLevel.shared.value
        let point = CGPoint(x: locationInWindow.x / zoom, y: (content.bounds.height - locationInWindow.y) / zoom)
        return panelFrame.contains(point)
    }

    /// The up and down arrows move along the rows while the panel is open; the field itself would only move the cursor.
    private func installKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let used = MainActor.assumeIsolated { SearchPanel.shared.arrow(event.keyCode) }
            return used ? nil : event
        }
        // Let go only after the row has had the click.
        mouseUps = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { event in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated { SearchPanel.shared.holding = false }
            }
            return event
        }
    }

    private func arrow(_ keyCode: UInt16) -> Bool {
        guard isOpen, keyCode == 125 || keyCode == 126 else { return false }
        let count = rows.count
        guard count > 0 else { return false }
        if keyCode == 125 {
            highlighted = highlighted.map { min(count - 1, $0 + 1) } ?? 0
        } else {
            highlighted = highlighted.flatMap { $0 > 0 ? $0 - 1 : nil }
        }
        return true
    }

    // MARK: What to show

    /// Four things to search for, as Spotify's lowercase suggestions: names in the library that start with the text, the
    /// shortest first, then names with a word that starts with it.
    static func suggestions(for text: String) -> [String] {
        let query = TextMatch.fold(text)
        guard !query.isEmpty else { return [] }
        let library = Library.shared
        var seen = Set<String>()
        var starts: [String] = []
        var words: [String] = []
        let names = library.albums.map(\.artist) + library.songs.compactMap(\.artistName) + library.albums.map(\.title) + library.songs.map(\.title)
        for name in names {
            let folded = TextMatch.fold(name)
            guard !folded.isEmpty, folded != query, seen.insert(folded).inserted else { continue }
            if folded.hasPrefix(query) { starts.append(name.lowercased()) } else if folded.contains(" " + query) { words.append(name.lowercased()) }
        }
        starts.sort { $0.count < $1.count }
        words.sort { $0.count < $1.count }
        return Array((starts + words).prefix(4))
    }

    /// Songs, artists, albums and playlists to open straight away: names that start with the text first, then a word that
    /// starts with it, then the rest that holds it; artists before songs before albums, the most played first.
    static func results(for text: String) -> [SearchPanelRow] {
        let library = Library.shared
        func rank(_ name: String) -> Int? {
            if name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return 0 }
            let folded = TextMatch.fold(name), query = TextMatch.fold(text)
            if folded.contains(" " + query) { return 1 }
            return name.looselyContains(text) ? 2 : nil
        }
        var found: [(rank: Int, kind: Int, plays: Int, row: SearchPanelRow)] = []
        var artists = Set<String>()
        for album in library.albums where artists.insert(album.artist).inserted {
            if let r = rank(album.artist) { found.append((r, 0, 0, .artist(album.artist, album))) }
        }
        for song in library.songs {
            if let r = rank(song.title) { found.append((r, 1, song.playCount, .song(song))) }
        }
        for album in library.albums {
            if let r = rank(album.title) { found.append((r, 2, 0, .album(album))) }
        }
        for playlist in library.playlists {
            if let r = rank(playlist.title) { found.append((r, 3, 0, .playlist(playlist))) }
        }
        found.sort { ($0.rank, $0.kind, -$0.plays) < ($1.rank, $1.kind, -$1.plays) }
        return found.prefix(8).map(\.row)
    }
}

/// One row of the panel.
enum SearchPanelRow: Identifiable {
    case suggestion(String)
    case song(Song), album(Album), artist(String, Album), playlist(Playlist)

    var id: String {
        switch self {
        case .suggestion(let text): "find:" + text
        case .song(let song): SearchHistory.code(song: song)
        case .album(let album): SearchHistory.code(album: album)
        case .artist(let name, _): SearchHistory.code(artist: name)
        case .playlist(let playlist): "playlist:" + playlist.id
        }
    }

    init(recent: RecentSearch) {
        switch recent {
        case .song(let song): self = .song(song)
        case .album(let album): self = .album(album)
        case .artist(let name, let album): self = .artist(name, album)
        }
    }
}

// MARK: Drawing

/// The panel over everything, under the search field. Only the panel itself takes clicks.
struct SearchPanelLayer: View {
    var body: some View {
        let panel = SearchPanel.shared
        GeometryReader { geo in
            let origin = geo.frame(in: .named(MenuPresenter.space)).origin
            if panel.isOpen {
                SearchPanelView()
                    .frame(width: panel.fieldFrame.width)
                    .offset(x: panel.fieldFrame.minX - origin.x, y: panel.fieldFrame.maxY + 4 - origin.y)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.12), value: panel.isOpen)
    }
}

private struct SearchPanelView: View {
    @Environment(PlayerModel.self) private var model
    @LocalState private var contentHeight: CGFloat = 0

    var body: some View {
        let panel = SearchPanel.shared
        let rows = panel.rows
        let typing = !model.searchDraft.trimmingCharacters(in: .whitespaces).isEmpty
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if typing { KeysLine() } else { RecentsTitle() }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        SearchPanelRowView(row: row, typed: model.searchDraft, recent: !typing, highlighted: panel.highlighted == index)
                            .id(index)
                    }
                }
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(contentHeight, 1), 400))
            .onChange(of: panel.highlighted) { _, index in
                if let index { scroller.scrollTo(index) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PP.searchPanel))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MenuPresenter.space)) } action: { SearchPanel.shared.panelFrame = $0 }
    }
}

/// While typing, as Spotify: the arrow keys and Navigate on the left, Enter and Search on the right. 8 above, 4 under.
private struct KeysLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Keycap { Image(systemName: "arrow.up").font(.system(size: 10, weight: .regular)) }
            Keycap { Image(systemName: "arrow.down").font(.system(size: 10, weight: .regular)) }.padding(.leading, 8)
            Text("Navigate").font(.mix(12)).padding(.leading, 10)
            Spacer(minLength: 8)
            Keycap { Text("Enter").font(.mix(12)) }
            Text("Search").font(.mix(12)).padding(.leading, 10)
        }
        .foregroundStyle(PP.subdued)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// A key drawn as a small box with a thin grey edge.
private struct Keycap<Label: View>: View {
    @ViewBuilder var label: Label

    var body: some View {
        label
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20, maxHeight: 20)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color(hex: 0x727272), lineWidth: 1))
    }
}

/// With nothing typed: Recent searches, 16 in from the edge, 16 from the top.
private struct RecentsTitle: View {
    var body: some View {
        Text("Recent searches")
            .font(.mix(16, .bold))
            .frame(height: 24)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

/// A suggestion (56 high, a magnifier in a round) or something to open (64 high, its cover, the title and what it is).
/// Lighter under the pointer or when the arrow keys are on it.
private struct SearchPanelRowView: View {
    let row: SearchPanelRow
    let typed: String
    let recent: Bool
    let highlighted: Bool
    @LocalState private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            picture
            switch row {
            case .suggestion(let text):
                suggestionText(text).lineLimit(1)
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.mix(16)).foregroundStyle(Color.primary).lineLimit(1)
                    Text(subtitle).font(.mix(14)).foregroundStyle(PP.subdued).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if recent, hovering {
                // Out of the recent searches, as on the search page.
                Button { withAnimation(Motion.panel) { SearchHistory.shared.forget(row.id) } } label: {
                    PlayerIconImage(symbol: "xmark", size: 13).foregroundStyle(PP.subdued)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from recent searches")
            } else if case .song(let song) = row, saved(song) {
                // Spotify's green check: the song is in Liked Songs or a playlist, as the button in the player shows it.
                PlayerIconImage(symbol: "checkmark.circle.fill", size: 16).foregroundStyle(PP.primary)
                    .padding(.trailing, 4)
                    .help("Saved")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: isSuggestion ? 56 : 64)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(hovering || highlighted ? 0.1 : 0)))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { SearchPanel.shared.open(row) }
        .onHover { hovering = $0 && !Debug.active }
        .animation(nil, value: hovering)
    }

    private var isSuggestion: Bool { if case .suggestion = row { true } else { false } }

    private func saved(_ song: Song) -> Bool { PlayerModel.shared.likedIDs.contains(song.id) || Library.shared.inPlaylist(song) }

    @ViewBuilder
    private var picture: some View {
        switch row {
        case .suggestion:
            SpotifyIcon(name: "search").fill(style: FillStyle(eoFill: true))
                .frame(width: 20, height: 20)
                .foregroundStyle(PP.subdued)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.black.opacity(0.04)))
        case .song(let song):
            CoverArt(album: song.album, radius: 4).frame(width: 48, height: 48)
        case .album(let album):
            CoverArt(album: album, radius: 4).frame(width: 48, height: 48)
        case .artist(_, let album):
            CoverArt(album: album, radius: 0).frame(width: 48, height: 48).clipShape(Circle())
        case .playlist(let playlist):
            if let album = playlist.songs.first?.album {
                CoverArt(album: album, radius: 4).frame(width: 48, height: 48)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)).frame(width: 48, height: 48)
            }
        }
    }

    /// The typed part bold and white, the rest grey; a suggestion that does not start with it white all through.
    private func suggestionText(_ text: String) -> Text {
        let typed = typed.trimmingCharacters(in: .whitespaces)
        guard let range = text.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else {
            return Text(text).font(.mix(16)).foregroundStyle(Color.primary)
        }
        let head = Text(String(text[range])).font(.mix(16, .bold)).foregroundStyle(Color.primary)
        let rest = Text(String(text[range.upperBound...])).font(.mix(16)).foregroundStyle(PP.subdued)
        return Text("\(head)\(rest)")
    }

    private var title: String {
        switch row {
        case .suggestion(let text): text
        case .song(let song): song.title
        case .album(let album): album.title
        case .artist(let name, _): name
        case .playlist(let playlist): playlist.title
        }
    }

    private var subtitle: String {
        switch row {
        case .suggestion: ""
        case .song(let song): "Song • \(song.artist)"
        case .album(let album): "Album • \(album.artist)"
        case .artist: "Artist"
        case .playlist(let playlist): "Playlist • \(playlist.songs.count) songs"
        }
    }
}
