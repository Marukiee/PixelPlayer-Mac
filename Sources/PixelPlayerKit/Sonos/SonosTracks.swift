import Foundation

/// Addresses the speakers use (spec 5.4). Pure functions; the settings come in as parameters.
public enum SonosAddresses {
    /// Cleans up a typed address: adds http:// (home servers rarely have https), drops the trailing slash.
    public static func normalize(_ input: String?) -> String? {
        let raw = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme = "http"
        var rest = raw
        if let range = raw.range(of: "^(https?)://", options: [.regularExpression, .caseInsensitive]) {
            scheme = raw[range].dropLast(3).lowercased()
            rest = String(raw[range.upperBound...])
        }
        while rest.hasSuffix("/") { rest.removeLast() }
        if rest.isEmpty || rest.contains("://") || rest.hasPrefix(":") { return nil }
        guard let parts = URLComponents(string: "\(scheme)://\(rest)"),
              let host = parts.percentEncodedHost, !host.isEmpty else { return nil }
        if let port = parts.port, !(1...65535).contains(port) { return nil }
        // Rebuilt the way OkHttp prints a URL: lowercase host, no default port.
        var url = "\(scheme)://"
        if let user = parts.percentEncodedUser {
            url += user
            if let password = parts.percentEncodedPassword { url += ":\(password)" }
            url += "@"
        }
        url += host.lowercased()
        if let port = parts.port, port != (scheme == "https" ? 443 : 80) { url += ":\(port)" }
        url += parts.percentEncodedPath
        if let query = parts.percentEncodedQuery { url += "?\(query)" }
        if let fragment = parts.percentEncodedFragment { url += "#\(fragment)" }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    /// Like `normalize`, but assumes https and refuses http: the Sonos app shows no covers over http.
    public static func normalizeCover(_ input: String?) -> String? {
        let raw = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = normalize(withScheme), url.hasPrefix("https://") else { return nil }
        return url
    }

    /// A first value for the cover address after logging in: the login address when it is https and not Tailscale.
    public static func suggestCoverAddress(login: String?) -> String? {
        guard let login, let url = URL(string: login.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !isTailscaleHost(host) else { return nil }
        return normalizeCover(login)
    }

    /// Swaps `loginBase` at the start of `url` for `homeBase`; other URLs stay as they are.
    public static func rebase(_ url: String, loginBase: String, homeBase: String) -> String {
        url.hasPrefix(loginBase + "/") ? homeBase + url.dropFirst(loginBase.count) : url
    }

    public static func isTailscaleHost(_ host: String) -> Bool {
        if host.lowercased().hasSuffix(".ts.net") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        // 100.64.0.0/10 is the carrier-grade NAT range Tailscale hands out.
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    public static func loginBase(_ settings: SonosAddressSettings) -> String? {
        guard let login = settings.loginAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty else { return nil }
        if let normalized = normalize(login) { return normalized }
        var trimmed = login
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    public static func homeBase(_ settings: SonosAddressSettings) -> String? { normalize(settings.homeAddress) }
    public static func coverBase(_ settings: SonosAddressSettings) -> String? { normalizeCover(settings.coverAddress) }

    /// The Navidrome address the speakers will use.
    public static func speakerBase(_ settings: SonosAddressSettings) -> String? { homeBase(settings) ?? loginBase(settings) }

    /// Moves a URL built for the app (maybe over Tailscale) onto the address the speakers can reach.
    public static func streamForSonos(_ url: String, settings: SonosAddressSettings) -> String {
        guard let home = homeBase(settings) else { return url }
        return rebase(url, settings: settings, onto: home)
    }

    /// Covers go through their own https address when one is set, else they follow the stream URLs.
    public static func coverForSonos(_ url: String, settings: SonosAddressSettings) -> String {
        guard let cover = coverBase(settings) else { return streamForSonos(url, settings: settings) }
        return rebase(url, settings: settings, onto: cover)
    }

    /// Why the speakers cannot use the server at all, or nil. The empty library (`noSongs`) is the app's own check.
    public static func sourceProblem(_ settings: SonosAddressSettings) -> SonosSourceProblem? {
        guard loginBase(settings) != nil else { return .notLoggedIn }
        if let base = speakerBase(settings), let host = URLComponents(string: base)?.host, isTailscaleHost(host) {
            return .tailscaleAddress
        }
        return nil
    }

    private static func rebase(_ url: String, settings: SonosAddressSettings, onto base: String) -> String {
        guard let login = loginBase(settings) else { return url }
        let moved = rebase(url, loginBase: login, homeBase: base)
        if moved != url { return moved }
        // A URL built from the address exactly as typed (other case, trailing slash) still counts as the login address.
        guard var raw = settings.loginAddress?.trimmingCharacters(in: .whitespacesAndNewlines) else { return url }
        while raw.hasSuffix("/") { raw.removeLast() }
        return raw == login ? url : rebase(url, loginBase: raw, homeBase: base)
    }
}

/// Turning the app's songs into what the speaker gets (spec 5.4).
public enum SonosTracks {
    /// Sonos plays FLAC up to 48 kHz and no Opus or DSD; ask Navidrome for MP3 320 (`maxBitRate=320&format=mp3`) then.
    public static let unsupportedSuffixes: Set<String> = ["opus", "ape", "wv", "dsf", "dff", "mka", "tak"]

    public static func needsTranscode(suffix: String?, sampleRate: Int?) -> Bool {
        (sampleRate ?? 0) > 48_000 || unsupportedSuffixes.contains(suffix?.lowercased() ?? "")
    }

    public static func mimeType(suffix: String?) -> String {
        switch suffix?.lowercased() {
        case "flac": "audio/flac"
        case "mp3": "audio/mpeg"
        case "m4a", "aac", "alac": "audio/mp4"
        case "ogg", "oga": "audio/ogg"
        case "wav": "audio/wav"
        case "aif", "aiff": "audio/aiff"
        default: "audio/mpeg"
        }
    }

    /// DIDL-Lite with every value escaped once. It is escaped a second time as a SOAP argument.
    public static func didl(itemID: String, title: String, artist: String, album: String, artURI: String?,
                            uri: String, mimeType: String, durationMs: Int) -> String {
        let e = SonosSoapClient.xmlEscape
        var xml = "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" "
        xml += "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" "
        xml += "xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" "
        xml += "xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">"
        xml += "<item id=\"\(e(itemID))\" parentID=\"pixelplay\" restricted=\"true\">"
        xml += "<dc:title>\(e(title))</dc:title>"
        xml += "<dc:creator>\(e(artist))</dc:creator>"
        xml += "<upnp:album>\(e(album))</upnp:album>"
        if let artURI, !artURI.trimmingCharacters(in: .whitespaces).isEmpty {
            xml += "<upnp:albumArtURI>\(e(artURI))</upnp:albumArtURI>"
        }
        xml += "<upnp:class>object.item.audioItem.musicTrack</upnp:class>"
        xml += "<res protocolInfo=\"http-get:*:\(mimeType):*\""
        if durationMs > 0 { xml += " duration=\"\(SonosSoapClient.msToHms(durationMs))\"" }
        xml += ">\(e(uri))</res>"
        xml += "</item></DIDL-Lite>"
        return xml
    }

    /// The queued form of a song, or nil when it has no stream URL (not on Navidrome).
    public static func queued(_ input: SonosTrackInput, settings: SonosAddressSettings) -> SonosQueuedTrack? {
        guard let stream = input.streamURL?.absoluteString else { return nil }
        let uri = SonosAddresses.streamForSonos(stream, settings: settings)
        let navidromeID = subsonicID(stream) ?? input.id
        let transcoded = queryValue("format", in: stream) == "mp3"
        let mime = transcoded ? "audio/mpeg" : (input.mimeType ?? "audio/mpeg")
        let art = input.coverURL.map { SonosAddresses.coverForSonos($0.absoluteString, settings: settings) }
        let metadata = didl(itemID: "pixelplay-\(navidromeID)", title: input.title, artist: input.artist, album: input.album,
                            artURI: art, uri: uri, mimeType: mime, durationMs: input.durationMs)
        return SonosQueuedTrack(mediaID: input.id, uri: uri, metadata: metadata)
    }

    /// Whether the speaker plays the stream we queued. Compares the Subsonic song id only, because a speaker may hand the
    /// URL back with other encoding or parameter order. When either id is unknown it assumes a match.
    public static func sameStream(_ queued: String, _ reported: String) -> Bool {
        if reported.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        guard let a = subsonicID(queued), let b = subsonicID(reported) else { return true }
        return a == b
    }

    /// The `id` query parameter (also as `amp;id`, from a URL that came back escaped once too often), URL-decoded.
    public static func subsonicID(_ uri: String) -> String? {
        queryValue("id", in: uri, alsoEscaped: true) ?? queryValue("mediaId", in: uri, alsoEscaped: true)
    }

    /// What a Sonos speaker plays, for Navidrome's getTranscodeDecision: the usual formats as they are, FLAC and ALAC only
    /// up to 48 kHz and 24-bit. Anything else comes converted as FLAC, so it stays lossless (48 kHz, 24-bit at most).
    public static let speakerProfile = Data("""
    {"name":"Sonos","platform":"Sonos",
     "directPlayProfiles":[
      {"containers":["flac"],"audioCodecs":["flac"],"protocols":["http"],"maxAudioChannels":2},
      {"containers":["mp3"],"audioCodecs":["mp3"],"protocols":["http"],"maxAudioChannels":2},
      {"containers":["mp4","m4a"],"audioCodecs":["aac","alac"],"protocols":["http"],"maxAudioChannels":2},
      {"containers":["ogg"],"audioCodecs":["vorbis"],"protocols":["http"],"maxAudioChannels":2},
      {"containers":["wav","aiff"],"audioCodecs":["pcm"],"protocols":["http"],"maxAudioChannels":2}],
     "transcodingProfiles":[{"container":"flac","audioCodec":"flac","protocol":"http","maxAudioChannels":2}],
     "codecProfiles":[
      {"type":"AudioCodec","name":"flac","limitations":[
       {"name":"audioSamplerate","comparison":"LessThanEqual","values":["48000"],"required":true},
       {"name":"audioBitdepth","comparison":"LessThanEqual","values":["24"],"required":true}]},
      {"type":"AudioCodec","name":"alac","limitations":[
       {"name":"audioSamplerate","comparison":"LessThanEqual","values":["48000"],"required":true},
       {"name":"audioBitdepth","comparison":"LessThanEqual","values":["24"],"required":true}]}]}
    """.utf8)

    static func queryValue(_ name: String, in uri: String, alsoEscaped: Bool = false) -> String? {
        guard let q = uri.firstIndex(of: "?") else { return nil }
        let query = uri[uri.index(after: q)...].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        if query.isEmpty { return nil }
        for part in query.split(separator: "&", omittingEmptySubsequences: false) {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = pair[0]
            guard key == name || (alsoEscaped && key == "amp;\(name)") else { continue }
            let raw = pair.count > 1 ? String(pair[1]) : ""
            if let value = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value
            }
        }
        return nil
    }
}
