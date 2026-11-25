import SwiftUI
import AppKit
import Observation

/// Where the window is. The sidebar is the library, as in Spotify: every playlist, album and artist
/// is a place of its own, with Home and search above them.
enum Route: Hashable {
    case home, search, songs, liked
    case playlist(Int), album(Int), artist(Int)

    /// From a script step such as `page:album:2`.
    init?(script: String) {
        let parts = script.split(separator: ":").map(String.init)
        let id = parts.count > 1 ? Int(parts[1]) : nil
        switch parts.first ?? "" {
        case "home": self = .home
        case "search": self = .search
        case "songs": self = .songs
        case "liked": self = .liked
        case "playlist": guard let id else { return nil }; self = .playlist(id)
        case "album": guard let id else { return nil }; self = .album(id)
        case "artist": guard let id else { return nil }; self = .artist(id)
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
    var current: Song = Sample.nowPlaying
    var isPlaying = true
    var position: Double = 104
    /// The songs in Liked Songs. The heart in the player follows the song that plays.
    var likedIDs: Set<Int> = Set(Sample.liked.map(\.id))
    var liked: Bool {
        get { likedIDs.contains(current.id) }
        set { if newValue { likedIDs.insert(current.id) } else { likedIDs.remove(current.id) } }
    }
    var fullScreen = false
    /// The song whose details are shown in a sheet.
    var infoSong: Song?
    var shuffle = false
    var repeatAll = true
    var volume: Double = 60
    var showQueue = false
    var showDevices = false
    var fullPlayer = false
    var searchText = ""
    var selectedSong: Song.ID?
    var settingsTab: SettingsTab = .general
    /// Raised to open the Settings window from a script.
    var settingsRequest = 0

    /// Devices: where the music plays, and the group around it.
    var group: Set<String> = ["living", "kitchen"]
    var volumes: [String: Double] = ["living": 42, "kitchen": 28, "bedroom": 30, "study": 20]
    var individualVolume = false

    var userQueue: [Song] = Sample.userQueue
    var upNext: [Song] = Sample.upNext

    var duration: Double { Double(current.seconds) }

    var groupName: String {
        let names = Sample.rooms.filter { group.contains($0.id) }.map(\.name)
        if names.isEmpty { return "This Mac" }
        return names.count == 1 ? names[0] : names.joined(separator: " + ")
    }

    var groupVolume: Double {
        get { group.isEmpty ? volume : group.map { volumes[$0] ?? 0 }.reduce(0, +) / Double(group.count) }
        set {
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

    func play(_ song: Song) {
        current = song
        position = 0
        isPlaying = true
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
                guard model.isPlaying, !Debug.freezeClock else { return }
                model.position = model.position >= model.duration ? 0 : model.position + 1
            }
        }
    }
}

func timeString(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}
