import SwiftUI
import AppKit
import Observation
import PixelPlayerKit

/// Where the window is. The sidebar is the library, as in Spotify: every playlist, album and artist
/// is a place of its own, with Home and search above them.
enum Route: Hashable {
    case home, search, songs, liked
    /// Playlists and albums by id; an artist by name, which is what both the server and local files share.
    case playlist(String), album(String), artist(String)
    /// All songs of one genre, from Browse.
    case genre(String)
    /// One of the Mixes for you, by id.
    case mix(String)
    /// Everything on one shelf, from its Show all: `mixes`, `recent`, `more-album:<id>`, `more-artist:<name>`, `albums:<search>`.
    case shelf(String)

    /// A stable text form, the same one `init?(script:)` reads: for pins and anything else that is stored.
    var key: String {
        switch self {
        case .home: "home"
        case .search: "search"
        case .songs: "songs"
        case .liked: "liked"
        case .playlist(let id): "playlist:\(id)"
        case .album(let id): "album:\(id)"
        case .artist(let name): "artist:\(name)"
        case .genre(let name): "genre:\(name)"
        case .mix(let id): "mix:\(id)"
        case .shelf(let key): "shelf:\(key)"
        }
    }

    /// From a script step such as `page:album:2`.
    init?(script: String) {
        let parts = script.split(separator: ":").map(String.init)
        let id = parts.count > 1 ? parts[1] : nil
        switch parts.first ?? "" {
        case "home": self = .home
        case "search": self = .search
        case "songs": self = .songs
        case "liked": self = .liked
        case "playlist": guard let id else { return nil }; self = .playlist(id)
        case "album": guard let id else { return nil }; self = .album(id)
        case "artist": guard let id else { return nil }; self = .artist(id)
        case "genre": guard let id else { return nil }; self = .genre(id)
        case "mix": guard let id else { return nil }; self = .mix(id)
        case "shelf": guard id != nil else { return nil }; self = .shelf(parts.dropFirst().joined(separator: ":"))
        default: return nil
        }
    }
}

/// What the library in the sidebar shows.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, playlists, albums, artists
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .artists: "Artists"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, sources, playback, appearance, developer
    var id: String { rawValue }
}

/// The state of the prototype. Nothing plays: the clock only moves the position so the bar is alive.
@MainActor @Observable
final class PlayerModel {
    static let shared = PlayerModel()

    var route: Route = .home {
        didSet {
            // Every move to another page goes on the back list, as in a browser; a new page clears forward.
            guard route != oldValue, !walkingHistory else { return }
            backStack.append(oldValue)
            if backStack.count > 100 { backStack.removeFirst() }
            forwardStack.removeAll()
        }
    }
    /// The pages before and after this one, for the back and forward buttons.
    private(set) var backStack: [Route] = []
    private(set) var forwardStack: [Route] = []
    @ObservationIgnored private var walkingHistory = false

    var canGoBack: Bool { !backStack.isEmpty || !searchText.isEmpty || fullPlayer }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Back as in a browser: first out of search results or the lyrics, then to the page before.
    func goBack() {
        if fullPlayer { setFullPlayer(false); return }
        if !searchText.isEmpty { searchText = ""; return }
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(route)
        walk(to: previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(route)
        walk(to: next)
    }

    private func walk(to page: Route) {
        walkingHistory = true
        searchText = ""
        fullPlayer = false
        route = page
        walkingHistory = false
    }
    var filter: LibraryFilter = .all
    var current: Song = Library.shared.isSample ? Sample.nowPlaying : (Library.shared.songs.first ?? Song.nothing)
    var isPlaying = Library.shared.isSample
    /// Where the song is, in seconds. The sample music starts in the middle of a song, as in the design shots.
    var position: Double = Library.shared.isSample ? 104 : 0
    /// The songs in Liked Songs. The heart in the player follows the song that plays.
    var likedIDs: Set<String> {
        get { Library.shared.likedIDs }
        set { Library.shared.likedIDs = newValue }
    }
    var liked: Bool {
        get { likedIDs.contains(current.id) }
        set { setLiked(current, newValue) }
    }

    /// A like here: stored, and sent to the server through the two-way sync.
    func setLiked(_ song: Song, _ on: Bool) {
        if on { likedIDs.insert(song.id) } else { likedIDs.remove(song.id) }
        if !Library.shared.isSample { FavoritesSync.shared.localChange(songID: song.id, liked: on) }
    }
    var fullScreen = false
    /// The welcome at first launch (not in scripted runs, which open it with a script step).
    var showOnboarding = PlayerModel.firstWelcome || PlayerModel.onlyMixQuestion
    var onboardingStep = 0
    /// Someone who went through the welcome before the mixes question existed gets only that question, once, with an account.
    var onboardingOnlyMixes = PlayerModel.onlyMixQuestion

    private static var firstWelcome: Bool {
        !Library.shared.isSample && !Debug.active && !UserDefaults.standard.bool(forKey: "onboarding.done")
    }

    private static var onlyMixQuestion: Bool {
        !Library.shared.isSample && !Debug.active && UserDefaults.standard.bool(forKey: "onboarding.done")
            && !Library.shared.mixQuestionAsked && ServerSettings.saved != nil
    }
    /// The song whose details are shown in a sheet.
    var infoSong: Song?
    /// Shuffle as in Spotify and in SpotCopy (Media3's shuffle mode): on, what comes after the current song plays in a mixed
    /// order; off, it goes back to the list's own order. A list started while it is on plays mixed from the start.
    var shuffle = false {
        didSet {
            guard shuffle != oldValue, !applyingShuffle else { return }
            if shuffle {
                unshuffled = upNext
                upNext.shuffle()
            } else if let original = unshuffled {
                // Back to the list's order, without what played since and keeping songs that came in meanwhile.
                let left = Set(upNext.map(\.id))
                let known = Set(original.map(\.id))
                upNext = original.filter { left.contains($0.id) } + upNext.filter { !known.contains($0.id) }
                unshuffled = nil
            }
            RemoteController.shared.modesChanged()
        }
    }
    /// What comes next in the list's own order, kept while shuffle is on to go back to.
    private var unshuffled: [Song]?
    private var applyingShuffle = false
    var repeatAll = true {
        didSet { RemoteController.shared.modesChanged() }
    }
    var volume: Double = 60 {
        didSet { Playback.shared.setVolume(volume) }
    }
    var showQueue = false
    /// Your Library folded away with the button that slides in at its title, as in Spotify. Remembered.
    var libraryCollapsed = UserDefaults.standard.bool(forKey: "library.collapsed") {
        didSet { UserDefaults.standard.set(libraryCollapsed, forKey: "library.collapsed") }
    }
    var showDevices = false
    var fullPlayer = false
    var searchText = ""
    var selectedSong: Song.ID?
    var settingsTab: SettingsTab = .general
    /// Raised to open the Settings window from a script.
    var settingsRequest = 0
    /// Bumped by ⌘L: the search field takes focus.
    var searchRequest = 0

    /// Devices: where the music plays, and the group around it. Only the sample music has made-up rooms in it.
    var group: Set<String> = Library.shared.isSample ? ["living", "kitchen"] : []
    var volumes: [String: Double] = ["living": 42, "kitchen": 28, "bedroom": 30, "study": 20]
    var individualVolume = false

    var userQueue: [Song] = Library.shared.isSample ? Sample.userQueue : [] {
        didSet { RemoteController.shared.queueChanged(); SonosOutput.shared.queueChanged() }
    }
    var upNext: [Song] = Library.shared.isSample ? Sample.upNext : [] {
        didSet { RemoteController.shared.queueChanged(); SonosOutput.shared.queueChanged() }
    }

    var duration: Double { Double(current.seconds) }

    var groupName: String {
        if let phone = RemoteController.shared.active { return phone.name }
        if let speakers = SonosOutput.shared.groupName { return speakers }
        let names = Library.shared.isSample ? Sample.rooms.filter { group.contains($0.id) }.map(\.name) : []
        if names.isEmpty { return "This Mac" }
        return names.count == 1 ? names[0] : names.joined(separator: " + ")
    }

    var groupVolume: Double {
        get {
            if SonosOutput.shared.session != nil { return SonosOutput.shared.groupVolume }
            return group.isEmpty ? volume : group.map { volumes[$0] ?? 0 }.reduce(0, +) / Double(group.count)
        }
        set {
            if SonosOutput.shared.session != nil { SonosOutput.shared.groupVolume = newValue; return }
            guard !group.isEmpty else { volume = newValue; return }
            let delta = newValue - groupVolume
            for id in group { volumes[id] = min(100, max(0, (volumes[id] ?? 0) + delta)) }
        }
    }

    func setFullPlayer(_ on: Bool) {
        // A calm crossfade: a spring here also moved covers elsewhere in the window.
        withAnimation(Motion.fade) { fullPlayer = on }
    }

    /// The full screen player, and the window in macOS full screen with it (not during scripted captures).
    func setFullScreen(_ on: Bool) {
        let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 800 })
        // A focused search field would draw its ring over the full screen player.
        window?.makeFirstResponder(nil)
        withAnimation(Motion.morph) { fullScreen = on }
        guard !Debug.active, let window else { return }
        if window.styleMask.contains(.fullScreen) != on { window.toggleFullScreen(nil) }
    }

    /// Plays a song, with the list it was picked from as what follows it.
    /// The list the music plays from, for "Next from …" in the queue; empty when it is not one of the library's lists.
    var playingFrom = ""

    func play(_ song: Song, in context: [Song] = []) {
        if !context.isEmpty { playingFrom = Self.source(of: context) }
        if Library.shared.isSample {
            current = song
            position = 0
            isPlaying = true
            if let index = context.firstIndex(of: song) { upNext = Array(context[(index + 1)...]) }
        } else {
            Playback.shared.play(song, in: context)
        }
        // With shuffle on, the rest of the list follows in a mixed order, as in Spotify.
        if shuffle, !context.isEmpty {
            unshuffled = upNext
            upNext.shuffle()
        }
    }

    // MARK: The song in the player when the app opens

    private struct Saved: Codable {
        var id: String
        var position: Double
        var userQueue: [String]
        var upNext: [String]
        var playingFrom: String
    }

    /// Remembers the song, the place in it and the queue, so the player is never empty when the app opens again.
    func saveNowPlaying() {
        guard !Library.shared.isSample, !current.id.isEmpty else { return }
        let saved = Saved(id: current.id, position: position, userQueue: userQueue.map(\.id), upNext: upNext.prefix(300).map(\.id),
                          playingFrom: playingFrom)
        if let data = try? JSONEncoder().encode(saved) { Store.defaults.set(data, forKey: "player.last") }
    }

    /// Once the library is there: the last song where it was, paused, with its queue; the first time, Your Mix.
    func restoreIfEmpty() {
        guard current.id.isEmpty, !Library.shared.isSample, Library.shared.hasMusic else { return }
        let library = Library.shared
        if let data = Store.defaults.data(forKey: "player.last"), let saved = try? JSONDecoder().decode(Saved.self, from: data),
           let song = library.song(id: saved.id) {
            current = song
            position = min(saved.position, Double(song.seconds))
            userQueue = saved.userQueue.compactMap(library.song(id:))
            upNext = saved.upNext.compactMap(library.song(id:))
            playingFrom = saved.playingFrom
        } else if !Debug.active, let first = library.yourMix.first {
            // Scripted runs start empty, so their checks do not depend on what a mix picks.
            current = first
            upNext = Array(library.yourMix.dropFirst())
            playingFrom = "Your Mix"
            position = 0
        }
    }

    /// After the library is rebuilt: the songs in the player become the library's newest copies, so a queue restored from
    /// the local files alone learns where each song is on the server once that list is in (Mark, 2026-11-26: the Sonos
    /// skipped through the whole queue because none of it seemed to be on the server). Only what changed is set, so the
    /// phone and the speakers are not told about a queue that stayed the same.
    func refreshFromLibrary() {
        guard !current.id.isEmpty else { return }
        let library = Library.shared
        let freshCurrent = library.fresh(current)
        if freshCurrent.id == current.id && freshCurrent.source.serverID != current.source.serverID { current = freshCurrent }
        let freshUser = userQueue.map(library.fresh)
        if freshUser.map(\.source.serverID) != userQueue.map(\.source.serverID) { userQueue = freshUser }
        let freshNext = upNext.map(library.fresh)
        if freshNext.map(\.source.serverID) != upNext.map(\.source.serverID) { upNext = freshNext }
    }

    /// Which list of the library a set of songs is, in any order (sorted or shuffled).
    static func source(of context: [Song]) -> String {
        let ids = Set(context.map(\.id))
        let library = Library.shared
        if Set(library.yourMix.map(\.id)) == ids { return "Your Mix" }
        // One album or one artist: known from the songs themselves, without going through the whole library.
        if let album = context.first?.album, context.allSatisfy({ $0.album.id == album.id }),
           Set(library.songs(for: .album(album.id)).map(\.id)) == ids { return album.title }
        if let artist = context.first?.artist, context.allSatisfy({ $0.artist == artist }),
           Set(library.songs(for: .artist(artist)).map(\.id)) == ids { return artist }
        if ids.count == library.songs.count { return "All Songs" }
        if Set(library.liked.map(\.id)) == ids { return "Liked Songs" }
        for list in library.playlists where Set(list.songs.map(\.id)) == ids { return list.title }
        for mix in library.mixes where Set(library.songs(for: mix).map(\.id)) == ids { return mix.title }
        return ""
    }

    /// Whether the music comes from this list: it was started from a list with this name and the song that plays is in it.
    func isPlaying(from title: String, songs: () -> [Song]) -> Bool {
        guard !title.isEmpty, playingFrom == title, !current.id.isEmpty else { return false }
        return songs().contains { $0.id == current.id }
    }

    /// A list's play button: pauses or resumes when the music comes from that list, otherwise plays it from the top.
    func togglePlay(from title: String, songs: () -> [Song]) {
        if isPlaying(from: title, songs: songs) { setPlaying(!isPlaying) } else { play(songs(), from: title) }
    }

    /// Plays a whole list from the top, or in a shuffled order.
    /// `from` names the list for its play button and "Next from" in the queue, when the songs alone do not tell.
    func play(_ songs: [Song], shuffled: Bool = false, from title: String? = nil) {
        // Shuffle play turns shuffle on, as in Spotify; with shuffle on any list starts on a random song.
        if shuffled && !shuffle {
            applyingShuffle = true
            shuffle = true
            applyingShuffle = false
        }
        guard let first = shuffle ? songs.randomElement() : songs.first else { return }
        play(first, in: songs)
        if let title { playingFrom = title }
    }

    /// The order each list of songs is shown in, once it was changed from the sort menu.
    var trackOrders: [Route: TrackOrder] = [:]
    /// Lists shown the other way round, after a second click on the column title.
    var trackReversed: [Route: Bool] = [:]

    /// A click on a column title: sort by it, or turn it round when it already sorts by it. `#` goes back to the list's own order.
    func sortTracks(by order: TrackOrder, current: TrackOrder, default first: TrackOrder) {
        if order == .custom {
            trackOrders[route] = first
            trackReversed[route] = false
        } else if order == current {
            trackReversed[route] = !(trackReversed[route] ?? false)
        } else {
            trackOrders[route] = order
            trackReversed[route] = false
        }
    }

    func setPlaying(_ playing: Bool) {
        // Play with nothing chosen yet: Your Mix from the top, or the whole library when there is no mix.
        if playing, current.id.isEmpty, !Library.shared.isSample {
            let mix = Library.shared.yourMix
            let songs = mix.isEmpty ? Library.shared.songs(for: .songs) : mix
            if let first = songs.first { play(first, in: songs) }
            return
        }
        withAnimation(.easeOut(duration: 0.12)) { isPlaying = playing }
        Playback.shared.setPlaying(playing)
    }

    /// Moves to a point in the song, from the slider or the media keys.
    func seek(to seconds: Double) {
        position = seconds
        Playback.shared.seek(to: seconds)
    }

    func go(_ route: Route) {
        searchText = ""
        fullPlayer = false
        self.route = route
    }

    private var clock: Timer?

    func startClock() {
        guard clock == nil else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let model = PlayerModel.shared
                // Only the sample music needs a pretend clock; real playback moves the position itself.
                guard Library.shared.isSample, model.isPlaying, !Debug.freezeClock else { return }
                model.position = model.position >= model.duration ? 0 : model.position + 1
            }
        }
    }
}

func timeString(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

extension Song {
    /// What the player shows before anything has played.
    static let nothing = Song(id: "", title: "Not playing", album: Album(id: "", title: "", artist: "", year: 0, genre: ""), seconds: 0,
                              artistName: "Pick something to play")
}
