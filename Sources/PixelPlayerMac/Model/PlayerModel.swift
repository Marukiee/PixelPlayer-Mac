import SwiftUI
import Observation

/// Round 2: two ways to place the player at the bottom, both with the system's own controls.
enum Direction: String, CaseIterable, Identifiable {
    case bar = "a", floating = "b"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bar: "A · Balk onderin"
        case .floating: "B · Zwevende speler"
        }
    }
}

enum Page: String, CaseIterable, Identifiable, Hashable {
    case home, songs, albums, artists, playlists, liked, search
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .songs: "Nummers"
        case .albums: "Albums"
        case .artists: "Artiesten"
        case .playlists: "Afspeellijsten"
        case .liked: "Vind ik leuk"
        case .search: "Zoeken"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.microphone"
        case .playlists: "music.note.list"
        case .liked: "heart"
        case .search: "magnifyingglass"
        }
    }
    static let library: [Page] = [.songs, .albums, .artists, .playlists, .liked]
}

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, sources, playback, appearance
    var id: String { rawValue }
}

/// The state of the prototype. Nothing plays: the clock only moves the position so the bar is alive.
@MainActor @Observable
final class PlayerModel {
    static let shared = PlayerModel()

    var direction: Direction = .bar
    var page: Page = .home
    var current: Song = Sample.nowPlaying
    var isPlaying = true
    var position: Double = 104
    var liked = true
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
        if names.isEmpty { return "Deze Mac" }
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
