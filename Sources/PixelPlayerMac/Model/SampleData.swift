import SwiftUI

/// Made-up music for the design prototype: the same invented albums as the Android demo screenshots,
/// plus a few more so the grids fill. Nothing here belongs to anyone.
enum ArtStyle: Hashable {
    case sunset, blueDisc, bubbles, hills, orbit, prism, aurora, tide, copperMoon
}

struct Album: Identifiable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let year: Int
    let genre: String
    let art: ArtStyle
    /// The colour the player borrows from the cover, light and dark.
    let tint: UInt32
}

struct Song: Identifiable, Hashable {
    let id: Int
    let title: String
    let album: Album
    let seconds: Int
    var artist: String { album.artist }
    var duration: String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

struct Playlist: Identifiable, Hashable {
    let id: Int
    let title: String
    let songs: [Song]
}

struct Mix: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let symbol: String
    let tone: Tone
    let covers: [Album]
}

enum DeviceKind: Hashable { case mac, sonos, phone }

struct Device: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: DeviceKind
    var symbol: String {
        switch kind {
        case .mac: "laptopcomputer"
        case .sonos: "hifispeaker.fill"
        case .phone: "iphone.gen3"
        }
    }
}

enum Sample {
    static let albums: [Album] = [
        Album(id: 1, title: "Midnight Arcade", artist: "Kestrel Bay", year: 2024, genre: "Synthwave", art: .sunset, tint: 0x5B2A86),
        Album(id: 2, title: "Blue Hour Sessions", artist: "Odile Brandt Trio", year: 2023, genre: "Jazz", art: .blueDisc, tint: 0x1D3A8A),
        Album(id: 3, title: "Sunday Static", artist: "The Paper Comets", year: 2025, genre: "Indie Pop", art: .bubbles, tint: 0xE8708F),
        Album(id: 4, title: "Juniper Road", artist: "Juniper Vale", year: 2022, genre: "Folk", art: .hills, tint: 0x3F7A63),
        Album(id: 5, title: "Satellite Hearts", artist: "Nova Lind", year: 2025, genre: "Indie Pop", art: .orbit, tint: 0x4A2C7A),
        Album(id: 6, title: "Glasshouse", artist: "Ferro & June", year: 2024, genre: "Electronic", art: .prism, tint: 0x0F7C80),
        Album(id: 7, title: "Northern Lines", artist: "Halden", year: 2021, genre: "Ambient", art: .aurora, tint: 0x14594F),
        Album(id: 8, title: "Tidal Hours", artist: "Sea of Maple", year: 2023, genre: "Indie Rock", art: .tide, tint: 0x2B5C8F),
        Album(id: 9, title: "Copper Moon", artist: "Ruby Ash", year: 2022, genre: "Soul", art: .copperMoon, tint: 0x8C3A1E),
    ]

    private static func album(_ id: Int) -> Album { albums.first { $0.id == id }! }

    static let songs: [Song] = {
        let list: [(Int, String, Int)] = [
            (1, "Night Signal", 214), (1, "Afterglow Drive", 236), (1, "Pixel Rain", 198), (1, "Coastline 1987", 251), (1, "Midnight Arcade", 227),
            (2, "Late Train to Lisbon", 262), (2, "Smoke and Velvet", 241), (2, "Blue Hour", 288), (2, "Quiet Corner", 219),
            (3, "Golden Static", 187), (3, "Bicycle Summer", 203), (3, "Polaroid Days", 195), (3, "Lemonade Sky", 176), (3, "Small Town Radio", 214),
            (4, "Wildflower Morning", 205), (4, "River Stones", 232), (4, "Lantern Song", 248), (4, "Home by Autumn", 221),
            (5, "Satellite Hearts", 199), (5, "Orbit", 183), (5, "Soft Landing", 226),
            (6, "Glasshouse", 241), (6, "Mirror Steps", 207), (6, "Low Sun", 233),
            (7, "Northern Lines", 312), (7, "Snowfield", 274),
            (8, "Tidal Hours", 219), (8, "Harbour Lights", 244),
            (9, "Copper Moon", 236), (9, "Slow Burn", 251),
        ]
        return list.enumerated().map { Song(id: $0.offset + 1, title: $0.element.1, album: album($0.element.0), seconds: $0.element.2) }
    }()

    static func song(_ title: String) -> Song { songs.first { $0.title == title }! }

    static var nowPlaying: Song { song("Blue Hour") }

    /// The queue as on Android: three songs the listener queued play first, then the rest of the library.
    static let userQueue: [Song] = ["Night Signal", "Polaroid Days", "Satellite Hearts"].map(song)
    static let upNext: [Song] = ["Coastline 1987", "Golden Static", "Home by Autumn", "Lantern Song", "Glasshouse",
                                 "Harbour Lights", "Copper Moon", "Orbit", "River Stones", "Smoke and Velvet",
                                 "Mirror Steps", "Snowfield", "Lemonade Sky", "Low Sun", "Slow Burn", "Afterglow Drive"].map(song)

    static let liked: [Song] = ["Blue Hour", "Afterglow Drive", "Bicycle Summer", "Lantern Song", "Orbit", "Glasshouse",
                                "Copper Moon", "Harbour Lights", "Pixel Rain", "Quiet Corner"].map(song)

    static let playlists: [Playlist] = [
        Playlist(id: 1, title: "Avondrit", songs: ["Night Signal", "Afterglow Drive", "Coastline 1987", "Glasshouse", "Low Sun", "Harbour Lights"].map(song)),
        Playlist(id: 2, title: "Zondagochtend", songs: ["Wildflower Morning", "Bicycle Summer", "Quiet Corner", "Home by Autumn", "Soft Landing"].map(song)),
        Playlist(id: 3, title: "Focus", songs: ["Northern Lines", "Snowfield", "Smoke and Velvet", "Mirror Steps", "Orbit"].map(song)),
        Playlist(id: 4, title: "Keukendans", songs: ["Golden Static", "Copper Moon", "Slow Burn", "Lemonade Sky", "Pixel Rain"].map(song)),
        Playlist(id: 5, title: "Regenachtig", songs: ["Blue Hour", "Tidal Hours", "River Stones", "Late Train to Lisbon"].map(song)),
    ]

    static let mixes: [Mix] = [
        Mix(id: 1, title: "Daily Mix", subtitle: "Op basis van je luistergedrag", symbol: "sparkles", tone: .lilac, covers: [album(2), album(3), album(4)]),
        Mix(id: 2, title: "Synthwave", subtitle: "Genre-mix", symbol: "pianokeys", tone: .pink, covers: [album(1), album(6)]),
        Mix(id: 3, title: "Jazz", subtitle: "Genre-mix", symbol: "music.quarternote.3", tone: .blue, covers: [album(2), album(9)]),
        Mix(id: 4, title: "Folk", subtitle: "Genre-mix", symbol: "guitars.fill", tone: .green, covers: [album(4), album(7)]),
        Mix(id: 5, title: "Indie Pop", subtitle: "Genre-mix", symbol: "music.mic", tone: .amber, covers: [album(3), album(5)]),
        Mix(id: 6, title: "Herontdekken", subtitle: "Lang niet gehoord", symbol: "clock.arrow.circlepath", tone: .teal, covers: [album(8), album(7), album(9)]),
    ]

    /// Minutes listened per day this week, Monday first.
    static let week: [Int] = [52, 38, 71, 44, 96, 108, 0]

    static let thisMac = Device(id: "mac", name: "Deze Mac", kind: .mac)
    static let rooms: [Device] = [
        Device(id: "living", name: "Woonkamer", kind: .sonos),
        Device(id: "kitchen", name: "Keuken", kind: .sonos),
        Device(id: "bedroom", name: "Slaapkamer", kind: .sonos),
        Device(id: "study", name: "Werkkamer", kind: .sonos),
    ]
    static let phones: [Device] = [
        Device(id: "pixel", name: "Pixel 9", kind: .phone),
        Device(id: "galaxy", name: "Galaxy S25", kind: .phone),
    ]

    static let recentSearches = ["odile", "synthwave", "lantern", "juniper vale"]
}
