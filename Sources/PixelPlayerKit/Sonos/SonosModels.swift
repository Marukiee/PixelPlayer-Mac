import Foundation

/// One room. Codable in the same shape the Android app caches (`{uuid, name, host, model}`).
public struct SonosSpeaker: Codable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var name: String
    /// "ip:port" of the speaker's UPnP server, usually port 1400.
    public var host: String
    public var model: String?

    public var id: String { uuid }

    public init(uuid: String, name: String, host: String, model: String? = nil) {
        self.uuid = uuid
        self.name = name
        self.host = host
        self.model = model
    }
}

/// A group of rooms that play together. Codable as `{id, coordinator, members}` like the Android cache.
public struct SonosGroup: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var coordinatorUUID: String
    /// Coordinator first, then the other rooms by name.
    public var members: [SonosSpeaker]

    enum CodingKeys: String, CodingKey {
        case id
        case coordinatorUUID = "coordinator"
        case members
    }

    public init(id: String, coordinatorUUID: String, members: [SonosSpeaker]) {
        self.id = id
        self.coordinatorUUID = coordinatorUUID
        self.members = members
    }

    /// The parser drops a group whose coordinator is not visible, so the fallback is only for hand-made values.
    public var coordinator: SonosSpeaker { members.first { $0.uuid == coordinatorUUID } ?? members[0] }
    public var displayName: String { members.map(\.name).joined(separator: " + ") }
    /// Every room on its own line, for places with room to show the whole group.
    public var stackedNames: String { members.map(\.name).joined(separator: "\n") }
    /// "Living room +2": fits in a small pill.
    public var shortName: String { members.count > 1 ? "\(coordinator.name) +\(members.count - 1)" : coordinator.name }
    public var queueURI: String { "x-rincon-queue:\(coordinatorUUID)#0" }
}

/// One song to play on the speakers, as the app hands it over.
public struct SonosTrackInput: Sendable, Hashable, Identifiable {
    /// The id of the item in the app's queue; the queue mirror compares these.
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int
    /// The Navidrome stream URL as the app built it (login address). Nil: the song is not on Navidrome (spec 5.8).
    /// Build it once per song: a Subsonic URL gets a new salt each time, and the DIDL `res` must equal `EnqueuedURI`.
    public var streamURL: URL?
    /// Navidrome `getCoverArt` URL (size 500), login address.
    public var coverURL: URL?
    /// Server MIME type; nil means `audio/mpeg`, as on the phone. See `SonosTracks.mimeType(suffix:)`.
    public var mimeType: String?

    public init(id: String, title: String, artist: String, album: String, durationMs: Int,
                streamURL: URL?, coverURL: URL? = nil, mimeType: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.streamURL = streamURL
        self.coverURL = coverURL
        self.mimeType = mimeType
    }
}

/// A song as the speaker plays it: the stream URL on the speakers' address plus its DIDL-Lite metadata.
public struct SonosQueuedTrack: Sendable, Hashable {
    public var mediaID: String
    public var uri: String
    public var metadata: String

    public init(mediaID: String, uri: String, metadata: String) {
        self.mediaID = mediaID
        self.uri = uri
        self.metadata = metadata
    }
}

/// Why the speakers cannot play from Navidrome at all.
public enum SonosSourceProblem: String, Sendable, Equatable {
    case notLoggedIn
    /// The speakers cannot route to a Tailscale address; set a home address.
    case tailscaleAddress
    /// The app found no songs on the server (the app checks this itself; the kit only passes it on).
    case noSongs
}

/// The Sonos settings that change URLs (spec 5.4), as typed by the user.
public struct SonosAddressSettings: Sendable, Equatable {
    /// The Navidrome address the app logged in with; nil when not logged in.
    public var loginAddress: String?
    /// "Home address for Sonos": the LAN address the speakers use while the app uses another one. Empty: the login address.
    public var homeAddress: String
    /// "Address for covers": https only, because the Sonos app loads covers only over https. Empty: covers use the home address.
    public var coverAddress: String

    public init(loginAddress: String? = nil, homeAddress: String = "", coverAddress: String = "") {
        self.loginAddress = loginAddress
        self.homeAddress = homeAddress
        self.coverAddress = coverAddress
    }
}
