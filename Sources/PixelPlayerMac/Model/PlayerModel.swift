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
    /// Everything on one shelf, from its Show all: `mixes`, `recent`, `more-album:<id>`, `more-artist:<name>`, `albums:<search>`.
    case shelf(String)

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
    case general, sources, playback, appearance
    var id: String { rawValue }
}

/// The state of the prototype. Nothing plays: the clock only moves the position so the bar is alive.
@MainActor @Observable
final class PlayerModel {
    static let shared = PlayerModel()

    var route: Route = .home
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
    /// The song whose details are shown in a sheet.
    var infoSong: Song?
    var shuffle = false
    var repeatAll = true {
        didSet { RemoteController.shared.modesChanged() }
    }
    var volume: Double = 60 {
        didSet { Playback.shared.setVolume(volume) }
    }
    var showQueue = false
    var showDevices = false
    var fullPlayer = false
    var searchText = ""
    var selectedSong: Song.ID?
    var settingsTab: SettingsTab = .general
    /// Raised to open the Settings window from a script.
    var settingsRequest = 0

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
        withAnimation(Motion.morph) { fullPlayer = on }
    }

    /// The full screen player, and the window in macOS full screen with it (not during scripted captures).
    func setFullScreen(_ on: Bool) {
        withAnimation(Motion.morph) { fullScreen = on }
        guard !Debug.active, let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 800 }) else { return }
        if window.styleMask.contains(.fullScreen) != on { window.toggleFullScreen(nil) }
    }

    /// Plays a song, with the list it was picked from as what follows it.
    func play(_ song: Song, in context: [Song] = []) {
        if Library.shared.isSample {
            current = song
            position = 0
            isPlaying = true
        } else {
            Playback.shared.play(song, in: context)
        }
    }

    /// Plays a whole list from the top, or in a shuffled order.
    func play(_ songs: [Song], shuffled: Bool = false) {
        let list = shuffled ? songs.shuffled() : songs
        if let first = list.first { play(first, in: list) }
    }

    /// The order each list of songs is shown in, once it was changed from the sort menu.
    var trackOrders: [Route: TrackOrder] = [:]

    func setPlaying(_ playing: Bool) {
        // Play with nothing chosen yet: Your Mix from the top, or the whole library when there is no mix.
        if playing, current.id.isEmpty, !Library.shared.isSample {
            let mix = Library.shared.yourMix
            let songs = mix.isEmpty ? Library.shared.songs(for: .songs) : mix
            if let first = songs.first { play(first, in: songs) }
            return
        }
        withAnimation(Motion.bouncy) { isPlaying = playing }
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
