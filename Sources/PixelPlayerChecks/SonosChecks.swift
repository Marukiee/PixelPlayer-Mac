import Foundation
import PixelPlayerKit

/// Checks of the Sonos part of the kit. The pure checks run whenever this is called; the live ones run against the fake
/// household (tools/sonos-test/fake_sonos.py on 127.0.0.1:1400 to 1402) only when PP_FAKE_SONOS is set. Set
/// PP_FAKE_SONOS_LOG to the fake's log file to also check what went over the wire, and PP_FAKE_SONOS_STALL to the fake's
/// FAKE_SONOS_STALL file to check the stalled speaker (takes about 20 s). Nothing here sends SSDP or talks to anything
/// but 127.0.0.1: there may be real speakers on the network.
func sonosChecks() async {
    sonosPureChecks()
    if ProcessInfo.processInfo.environment["PP_FAKE_SONOS"] != nil {
        await sonosLiveChecks()
    }
}

// MARK: Pure

private func sonosPureChecks() {
    // Escaping and the SOAP envelope (spec 5.2)
    check(SonosSoapClient.xmlEscape("a&b<c>\"d\"'e'") == "a&amp;b&lt;c&gt;&quot;d&quot;&apos;e&apos;", "sonos: xml escape of all five")
    check(SonosService.avTransport.soapAction("Play") == "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"", "sonos: SOAPACTION with quotes")
    check(SonosService.groupRenderingControl.controlPath == "/MediaRenderer/GroupRenderingControl/Control", "sonos: GRC control path")
    check(SonosService.zoneGroupTopology.controlPath == "/ZoneGroupTopology/Control", "sonos: ZGT control path")
    let play = SonosSoapClient.envelope(service: .avTransport, action: "Play", args: [("InstanceID", "0"), ("Speed", "1")])
    check(play == "<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
        + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:Play xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"
        + "<InstanceID>0</InstanceID><Speed>1</Speed></u:Play></s:Body></s:Envelope>", "sonos: Play envelope exact")

    // DIDL-Lite (spec 5.4), and its second layer of escaping on the wire
    let stream = "http://music.local:4533/rest/stream?u=a&t=b&id=s1"
    let cover = "https://covers.example.com/rest/getCoverArt?u=a&id=al-1&size=500"
    let didl = SonosTracks.didl(itemID: "pixelplay-s1", title: "Tom & Jerry", artist: "<Cat>", album: "Album \"1\"", artURI: cover,
                                uri: stream, mimeType: "audio/flac", durationMs: 185_000)
    check(didl == "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" "
        + "xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">"
        + "<item id=\"pixelplay-s1\" parentID=\"pixelplay\" restricted=\"true\"><dc:title>Tom &amp; Jerry</dc:title>"
        + "<dc:creator>&lt;Cat&gt;</dc:creator><upnp:album>Album &quot;1&quot;</upnp:album>"
        + "<upnp:albumArtURI>https://covers.example.com/rest/getCoverArt?u=a&amp;id=al-1&amp;size=500</upnp:albumArtURI>"
        + "<upnp:class>object.item.audioItem.musicTrack</upnp:class><res protocolInfo=\"http-get:*:audio/flac:*\" duration=\"0:03:05\">"
        + "http://music.local:4533/rest/stream?u=a&amp;t=b&amp;id=s1</res></item></DIDL-Lite>", "sonos: DIDL exact")
    let bare = SonosTracks.didl(itemID: "pixelplay-s2", title: "T", artist: "A", album: "B", artURI: nil, uri: "http://h/x", mimeType: "audio/mpeg", durationMs: 0)
    check(!bare.contains("albumArtURI") && !bare.contains("duration="), "sonos: DIDL leaves out a missing cover and duration")
    let add = SonosSoapClient.envelope(service: .avTransport, action: "AddURIToQueue",
                                       args: [("InstanceID", "0"), ("EnqueuedURI", stream), ("EnqueuedURIMetaData", didl),
                                              ("DesiredFirstTrackNumberEnqueued", "0"), ("EnqueueAsNext", "0")])
    check(add.contains("<EnqueuedURI>http://music.local:4533/rest/stream?u=a&amp;t=b&amp;id=s1</EnqueuedURI>"), "sonos: stream URL escaped once as argument")
    check(add.contains("u=a&amp;amp;t=b&amp;amp;id=s1"), "sonos: stream URL in DIDL escaped twice on the wire")
    // Read it back the way the fake does: two XML parses, and the res text must equal EnqueuedURI.
    let wire = try? XMLDocument(xmlString: add)
    let metaText = (try? wire?.nodes(forXPath: "//*[local-name()='EnqueuedURIMetaData']"))??.first?.stringValue
    let uriText = (try? wire?.nodes(forXPath: "//*[local-name()='EnqueuedURI']"))??.first?.stringValue
    let inner = metaText.flatMap { try? XMLDocument(xmlString: $0) }
    let resText = (try? inner?.nodes(forXPath: "//*[local-name()='res']"))??.first?.stringValue
    check(resText != nil && resText == uriText && uriText == stream, "sonos: DIDL res equals EnqueuedURI after two parses")

    // Time format
    check(SonosSoapClient.hmsToMs("0:03:41") == 221_000, "sonos: hms to ms")
    check(SonosSoapClient.hmsToMs("1:02:03.500") == 3_723_000, "sonos: hms with fraction")
    check(SonosSoapClient.hmsToMs("NOT_IMPLEMENTED") == 0 && SonosSoapClient.hmsToMs("") == 0 && SonosSoapClient.hmsToMs(nil) == 0, "sonos: bad hms is 0")
    check(SonosSoapClient.msToHms(221_999) == "0:03:41" && SonosSoapClient.msToHms(3_723_000) == "1:02:03" && SonosSoapClient.msToHms(-5) == "0:00:00", "sonos: ms to hms")

    // Responses and faults
    let position = "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body>"
        + "<u:GetPositionInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><Track>2</Track><RelTime>0:01:05</RelTime>"
        + "<TrackURI>http://h/rest/stream?u=a&amp;id=s2</TrackURI><TrackMetaData></TrackMetaData></u:GetPositionInfoResponse></s:Body></s:Envelope>"
    let parsed = SonosSoapClient.parseResponse(position, action: "GetPositionInfo")
    check(parsed["Track"] == "2" && parsed["RelTime"] == "0:01:05" && parsed["TrackURI"] == "http://h/rest/stream?u=a&id=s2" && parsed["TrackMetaData"] == "",
          "sonos: response children as name to text")
    let fault = "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:Client</faultcode>"
        + "<faultstring>UPnPError</faultstring><detail><UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>701</errorCode></UPnPError>"
        + "</detail></s:Fault></s:Body></s:Envelope>"
    check(SonosSoapClient.parseFaultCode(fault) == 701, "sonos: UPnP fault code")

    // Topology (spec 5.1): hidden members left out, a group led by a hidden speaker dropped, default name, sort order
    let topology = "<ZoneGroupState><ZoneGroups>"
        + "<ZoneGroup Coordinator=\"RINCON_B\" ID=\"RINCON_B:12\">"
        + "<ZoneGroupMember UUID=\"RINCON_B\" Location=\"http://kitchen.local:1400/xml/device_description.xml\" ZoneName=\"Kitchen\"/>"
        + "<ZoneGroupMember UUID=\"RINCON_A\" Location=\"http://bath.local:1400/xml/device_description.xml\" ZoneName=\"Bathroom\"></ZoneGroupMember>"
        + "<ZoneGroupMember UUID=\"RINCON_S\" Location=\"http://sub.local:1400/xml/device_description.xml\" ZoneName=\"Kitchen\" Invisible=\"1\"/>"
        + "</ZoneGroup>"
        + "<ZoneGroup Coordinator=\"RINCON_C\" ID=\"RINCON_C:3\"><ZoneGroupMember UUID=\"RINCON_C\" Location=\"http://attic.local:1400/xml/device_description.xml\" ZoneName=\"Attic\">"
        + "<Satellite UUID=\"RINCON_SAT\" Location=\"http://sat.local:1400/xml/device_description.xml\" ZoneName=\"Attic\" Invisible=\"1\"/></ZoneGroupMember></ZoneGroup>"
        + "<ZoneGroup Coordinator=\"RINCON_H\" ID=\"RINCON_H:7\">"
        + "<ZoneGroupMember UUID=\"RINCON_H\" Location=\"http://hidden.local:1400/xml/device_description.xml\" ZoneName=\"Sub\" Invisible=\"1\"/>"
        + "<ZoneGroupMember UUID=\"RINCON_V\" Location=\"http://hall.local:1400/xml/device_description.xml\" ZoneName=\"Hall\"/></ZoneGroup>"
        + "<ZoneGroup Coordinator=\"RINCON_D\" ID=\"RINCON_D:1\"><ZoneGroupMember UUID=\"RINCON_D\" Location=\"http://den.local:1400/xml/device_description.xml\" ZoneName=\"\"/></ZoneGroup>"
        + "</ZoneGroups><VanishedDevices/></ZoneGroupState>"
    let answer = "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body>"
        + "<u:GetZoneGroupStateResponse xmlns:u=\"urn:schemas-upnp-org:service:ZoneGroupTopology:1\"><ZoneGroupState>"
        + SonosSoapClient.xmlEscape(topology) + "</ZoneGroupState></u:GetZoneGroupStateResponse></s:Body></s:Envelope>"
    let groups = SonosDiscovery.parseZoneGroupState(SonosSoapClient.parseResponse(answer, action: "GetZoneGroupState")["ZoneGroupState"] ?? "")
    check(groups.map(\.displayName) == ["Attic", "Kitchen + Bathroom", "Sonos"], "sonos: topology groups, hidden left out, sorted")
    if let kitchen = groups.first(where: { $0.coordinatorUUID == "RINCON_B" }) {
        check(kitchen.id == "RINCON_B:12" && kitchen.coordinator.host == "kitchen.local:1400" && kitchen.members.map(\.uuid) == ["RINCON_B", "RINCON_A"],
              "sonos: topology members coordinator first")
        check(kitchen.shortName == "Kitchen +1" && kitchen.queueURI == "x-rincon-queue:RINCON_B#0", "sonos: short name and queue URI")
    } else { check(false, "sonos: topology has the kitchen group") }
    check(!groups.contains { $0.members.contains { $0.name == "Hall" } }, "sonos: group led by a hidden speaker is dropped")

    // Discovery helpers, without sending anything
    check(SonosDiscovery.ssdpMessage == "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n",
          "sonos: M-SEARCH text")
    let ssdpAnswer = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age = 1800\r\nlocation: http://kitchen.local:1400/xml/device_description.xml\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
    check(SonosDiscovery.parseLocationHost(ssdpAnswer) == "kitchen.local:1400", "sonos: host from LOCATION header")
    check(SonosDiscovery.parseModelName("<root><device><modelName>Sonos Era 300</modelName></device></root>") == "Era 300", "sonos: model name without Sonos")
    check(SonosDiscovery.hosts(fromList: "127.0.0.1:1400\n\n  127.0.0.1:1401 \n") == ["127.0.0.1:1400", "127.0.0.1:1401"], "sonos: manual host list")
    if let json = try? JSONEncoder().encode(groups.first), let text = String(data: json, encoding: .utf8) {
        check(text.contains("\"coordinator\":\"RINCON_C\""), "sonos: group JSON uses the Android keys")
    } else { check(false, "sonos: group encodes") }

    // Addresses (spec 5.4)
    check(SonosAddresses.rebase("http://h:4533/rest/stream?id=1", loginBase: "http://h:4533", homeBase: "http://home:4533") == "http://home:4533/rest/stream?id=1", "sonos: rebase swaps the login base")
    check(SonosAddresses.rebase("http://h:45330/rest/stream?id=1", loginBase: "http://h:4533", homeBase: "http://home:4533") == "http://h:45330/rest/stream?id=1", "sonos: rebase needs the slash after the base")
    check(SonosAddresses.normalize("  Music.Local:4533/ ") == "http://music.local:4533", "sonos: normalize adds http and drops the slash")
    check(SonosAddresses.normalize("HTTPS://Example.com:443/") == "https://example.com", "sonos: normalize drops the default port")
    check(SonosAddresses.normalize("http://music.local/navidrome/") == "http://music.local/navidrome", "sonos: normalize keeps a path")
    check(SonosAddresses.normalize("") == nil && SonosAddresses.normalize(":4533") == nil && SonosAddresses.normalize("ftp://x") == nil, "sonos: normalize refuses junk")
    check(SonosAddresses.normalizeCover("covers.example.com") == "https://covers.example.com", "sonos: cover address defaults to https")
    check(SonosAddresses.normalizeCover("http://covers.example.com") == nil && SonosAddresses.normalizeCover("") == nil, "sonos: cover address refuses http and empty")
    check(SonosAddresses.suggestCoverAddress(login: "https://music.example.com/") == "https://music.example.com", "sonos: cover suggestion from https login")
    check(SonosAddresses.suggestCoverAddress(login: "http://music.example.com") == nil && SonosAddresses.suggestCoverAddress(login: "https://box.tail1234.ts.net") == nil,
          "sonos: no cover suggestion for http or Tailscale")
    check(SonosAddresses.isTailscaleHost("100.64.0.1") && SonosAddresses.isTailscaleHost("100.127.255.255") && SonosAddresses.isTailscaleHost("box.tail1234.TS.NET"),
          "sonos: Tailscale hosts")
    check(!SonosAddresses.isTailscaleHost("100.128.0.1") && !SonosAddresses.isTailscaleHost("music.local"), "sonos: not Tailscale")
    let remote = SonosAddressSettings(loginAddress: "http://100.100.1.2:4533/", homeAddress: "music.local:4533", coverAddress: "")
    let appStream = "http://100.100.1.2:4533/rest/stream?u=a&id=s1"
    let appCover = "http://100.100.1.2:4533/rest/getCoverArt?u=a&id=al-1&size=500"
    check(SonosAddresses.streamForSonos(appStream, settings: remote) == "http://music.local:4533/rest/stream?u=a&id=s1", "sonos: stream rebased onto the home address")
    check(SonosAddresses.coverForSonos(appCover, settings: remote) == "http://music.local:4533/rest/getCoverArt?u=a&id=al-1&size=500", "sonos: cover follows the home address when empty")
    var withCover = remote
    withCover.coverAddress = "covers.example.com"
    check(SonosAddresses.coverForSonos(appCover, settings: withCover) == "https://covers.example.com/rest/getCoverArt?u=a&id=al-1&size=500", "sonos: cover rebased onto the cover address")
    let plain = SonosAddressSettings(loginAddress: "http://music.local:4533")
    check(SonosAddresses.streamForSonos("http://music.local:4533/rest/stream?id=1", settings: plain) == "http://music.local:4533/rest/stream?id=1", "sonos: no home address keeps the URL")
    check(SonosAddresses.sourceProblem(SonosAddressSettings()) == .notLoggedIn, "sonos: not logged in")
    check(SonosAddresses.sourceProblem(SonosAddressSettings(loginAddress: "http://100.100.1.2:4533")) == .tailscaleAddress, "sonos: Tailscale login without home address")
    check(SonosAddresses.sourceProblem(remote) == nil, "sonos: Tailscale login with home address is fine")

    // Tracks
    let input = SonosTrackInput(id: "local-7", title: "T & U", artist: "A", album: "B", durationMs: 61_000,
                                streamURL: URL(string: appStream), coverURL: URL(string: appCover), mimeType: "audio/flac")
    if let track = SonosTracks.queued(input, settings: withCover) {
        check(track.mediaID == "local-7" && track.uri == "http://music.local:4533/rest/stream?u=a&id=s1", "sonos: queued track uses the speaker address")
        check(track.metadata.contains("id=\"pixelplay-s1\"") && track.metadata.contains("audio/flac") && track.metadata.contains("duration=\"0:01:01\""), "sonos: queued DIDL fields")
        check(track.metadata.contains(">http://music.local:4533/rest/stream?u=a&amp;id=s1</res>"), "sonos: res text is the rebased stream URL")
        check(track.metadata.contains("https://covers.example.com/rest/getCoverArt"), "sonos: queued cover on the cover address")
    } else { check(false, "sonos: queued track built") }
    var transcoded = input
    transcoded.streamURL = URL(string: appStream + "&maxBitRate=320&format=mp3")
    check(SonosTracks.queued(transcoded, settings: withCover)?.metadata.contains("http-get:*:audio/mpeg:*") == true, "sonos: transcoded stream is audio/mpeg")
    var missing = input
    missing.streamURL = nil
    check(SonosTracks.queued(missing, settings: withCover) == nil, "sonos: no stream URL is unplayable")
    check(SonosTracks.mimeType(suffix: "FLAC") == "audio/flac" && SonosTracks.mimeType(suffix: "alac") == "audio/mp4" && SonosTracks.mimeType(suffix: "xyz") == "audio/mpeg",
          "sonos: MIME by suffix")
    check(SonosTracks.needsTranscode(suffix: "flac", sampleRate: 96_000) && SonosTracks.needsTranscode(suffix: "opus", sampleRate: 48_000)
          && !SonosTracks.needsTranscode(suffix: "flac", sampleRate: 48_000), "sonos: transcode rule")
    check(SonosTracks.sameStream("http://h/rest/stream?u=a&id=s2&t=x", "http://other/rest/stream?id=s2&u=b"), "sonos: same stream by id")
    check(!SonosTracks.sameStream("http://h/rest/stream?id=s2", "http://h/rest/stream?id=s3"), "sonos: other id is another stream")
    check(SonosTracks.sameStream("http://h/rest/stream?u=a&id=s2", "http://h/rest/stream?u=a&amp;id=s2"), "sonos: amp;id counts")
    check(SonosTracks.sameStream("http://h/rest/stream?id=s2", "") && SonosTracks.sameStream("http://h/x", "http://h/rest/stream?id=s3"), "sonos: unknown counts as same")
    check(SonosTracks.subsonicID("http://h/rest/stream?u=a&id=s%201#f") == "s 1", "sonos: id is URL-decoded")
    check(SonosTracks.subsonicID("http://h/rest/getTranscodeStream?u=a&mediaId=m1&mediaType=song&transcodeParams=x.y.z") == "m1",
          "sonos: a converted stream is known by its mediaId")
    // Songs above 48 kHz go converted to FLAC 48 kHz through Navidrome's getTranscodeDecision, never as MP3.
    let profile = (try? JSONSerialization.jsonObject(with: SonosTracks.speakerProfile)) as? [String: Any]
    let converts = (profile?["transcodingProfiles"] as? [[String: Any]])?.compactMap { $0["audioCodec"] as? String }
    check(converts == ["flac"], "sonos: speaker profile is JSON and converts only to FLAC")
    // A real ticket from Navidrome 0.64.2 (test server): exp 1795938614.
    let ticket = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJiZCI6MjQsImNoIjoxLCJleHAiOjE3OTU5Mzg2MDEsImYiOiJmbGFjIiwiaXNzIjoiTkQiLCJtaWQiOiI1NjdlMkVUa3gyNnJKOWtKRHhldjRZIiwic3IiOjQ4MDAwLCJ1YSI6MTc5NTc2NTc1M30.eMGpGFO9UcwoQb2PC1sWgKNZRBcP0aT6wGrFn2B0bkg"
    check(SubsonicTranscodeDecision.expiry(ofTicket: ticket) == Date(timeIntervalSince1970: 1_795_938_601), "sonos: ticket expiry read from the JWT")
    check(SubsonicTranscodeDecision.expiry(ofTicket: "not-a-ticket") == nil, "sonos: unreadable ticket has no expiry")

    // Controller rules
    check(SonosController.playStateCommand(wantPlaying: true, transport: "TRANSITIONING") == nil, "sonos: TRANSITIONING counts as playing")
    check(SonosController.playStateCommand(wantPlaying: false, transport: "TRANSITIONING") == "Pause", "sonos: TRANSITIONING takes a pause")
    check(SonosController.playStateCommand(wantPlaying: true, transport: "PAUSED_PLAYBACK") == "Play" && SonosController.playStateCommand(wantPlaying: false, transport: "STOPPED") == nil,
          "sonos: play state commands")
    check(SonosController.groupVolumeTargets(["a": 30, "b": 21], groupVolume: 40) == ["a": 47, "b": 33], "sonos: group volume keeps shares")
    check(SonosController.groupVolumeTargets(["a": 90, "b": 10], groupVolume: 80) == ["a": 100, "b": 60], "sonos: group volume caps at 100")
    check(SonosController.groupVolumeTargets(["a": 0, "b": 0], groupVolume: 25) == ["a": 25, "b": 25], "sonos: silent rooms move together")
    check(SonosController.nearestIndex(of: "a", in: ["a", "b", "a", "c", "a"], around: 3) == 2 && SonosController.nearestIndex(of: "z", in: ["a"], around: 0) == -1,
          "sonos: nearest index")
    var estimate = SonosSpeakerOffsetEstimate()
    var answerMs: Int?
    for k in 0..<12 {
        let local = 10_000 + k * SonosTiming.pollInterval
        if let value = estimate.add(speakerWholeSecondsMs: (local + 300) / 1000 * 1000, localMs: local) { answerMs = value }
    }
    check(answerMs.map { abs($0 - 300) <= 200 } == true, "sonos: offset estimate finds the speaker lead")
}

// MARK: Live, against the fake household

private struct FakeSpeaker: Decodable {
    var coordinator: String
    var volume: Int
    var state: String
    var track: Int
    var pos: Double
    var mode: String
    var uri: String
    var cover: String?
    var queue: [String]
}

private final class SonosEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SonosEvent] = []

    func add(_ event: SonosEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var messages: [SonosMessage] {
        lock.lock()
        defer { lock.unlock() }
        return events.compactMap { if case .message(let message) = $0 { message } else { nil } }
    }
}

private let fakeHosts = ["127.0.0.1:1400", "127.0.0.1:1401", "127.0.0.1:1402"]

private func fakeState() async -> [String: FakeSpeaker]? {
    guard let url = URL(string: "http://127.0.0.1:1400/debug/state"),
          let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
    return try? JSONDecoder().decode([String: FakeSpeaker].self, from: data)
}

/// Polls until the condition holds (background appends, the volume flush and TRANSITIONING all take a moment).
private func waitFor(_ timeoutMs: Int = 6_000, _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return await condition()
}

private func waitForFake(_ timeoutMs: Int = 6_000, _ condition: @escaping ([String: FakeSpeaker]) -> Bool) async -> Bool {
    await waitFor(timeoutMs) { await fakeState().map(condition) ?? false }
}

private func sonosLiveChecks() async {
    let soap = SonosSoapClient()
    guard await fakeState() != nil else {
        check(false, "sonos live: fake household answers on 127.0.0.1:1400 (start tools/sonos-test/fake_sonos.py)")
        return
    }
    let logPath = ProcessInfo.processInfo.environment["PP_FAKE_SONOS_LOG"]
    let logStart = logPath.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int } ?? 0

    // A known start, whatever an earlier run left: every room on its own, volumes as the fake starts them.
    for (offset, host) in fakeHosts.enumerated() {
        if offset > 0 { _ = try? await soap.call(host, .avTransport, "BecomeCoordinatorOfStandaloneGroup", [("InstanceID", "0")]) }
        _ = try? await soap.call(host, .renderingControl, "SetVolume", [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(20 + offset)")])
    }

    // Manual hosts only and SSDP off: nothing leaves 127.0.0.1.
    let discovery = SonosDiscovery(manualHosts: fakeHosts, allowSSDP: false, soap: soap)
    let player = SonosVirtualPlayer()
    let settings = SonosAddressSettings(loginAddress: "http://127.0.0.1:4533", coverAddress: "https://covers.example.com")
    let controller = SonosController(local: player, discovery: discovery, settings: settings, soap: soap)
    let log = SonosEventLog()
    await controller.setEventHandler { log.add($0) }

    let groups = await controller.refresh()
    check(groups.map(\.displayName) == ["Bedroom", "Kitchen", "Living room"], "sonos live: three standalone rooms from manual hosts")
    let known = await discovery.knownHosts
    check(Set(known) == Set(fakeHosts), "sonos live: member hosts remembered")
    guard let living = groups.first(where: { $0.coordinator.name == "Living room" }),
          let kitchen = groups.first(where: { $0.coordinator.name == "Kitchen" })?.coordinator else {
        check(false, "sonos live: Living room and Kitchen found")
        return
    }
    check(living.coordinator.model == "Era 300" && living.coordinator.host == "127.0.0.1:1400", "sonos live: model and host of Living room")

    let allTracks = (1...6).map { i in
        SonosTrackInput(id: "local-\(i)", title: "Song \(i) & more", artist: "Test <artist>", album: "Album \"\(i)\"", durationMs: 185_000,
                        streamURL: URL(string: "http://127.0.0.1:4533/rest/stream?u=test&t=abc&s=def&v=1.16.1&c=PixelPlayerMac&f=json&id=s\(i)"),
                        coverURL: URL(string: "http://127.0.0.1:4533/rest/getCoverArt?u=test&t=abc&s=def&id=a1&size=500"), mimeType: "audio/flac")
    }
    let tracks = Array(allTracks.prefix(4))
    await player.sonosReplaceQueue(tracks, startAt: 0, positionMs: 0, playing: false)

    // Connect: full reset, the first two songs at once and the rest in the background.
    let connected = await controller.connect(groupID: living.id)
    check(connected, "sonos live: connect")
    let filled = await waitForFake { $0["Living room"]?.queue.count == 4 }
    check(filled, "sonos live: queue mirrored with four songs")
    if let room = await fakeState()?["Living room"] {
        check(room.queue == tracks.map(\.title), "sonos live: queue titles in order")
        check(room.uri == "x-rincon-queue:RINCON_LIVING01400#0" && room.mode == "NORMAL", "sonos live: our queue with play mode NORMAL")
        check(room.cover == "https://covers.example.com", "sonos live: covers on the cover address")
        check(room.state == "STOPPED", "sonos live: a paused queue does not start")
    } else { check(false, "sonos live: state after connect") }

    // Play
    await controller.play()
    let playing = await waitForFake { $0["Living room"]?.state == "PLAYING" && $0["Living room"]?.track == 1 }
    check(playing, "sonos live: play")

    // Next goes as a track seek, never as Next
    await controller.next()
    let second = await waitForFake { $0["Living room"]?.track == 2 && $0["Living room"]?.state == "PLAYING" }
    check(second, "sonos live: next plays track 2")
    let localIndex = await player.currentIndex
    check(localIndex == 1, "sonos live: local player on the second song")

    // Position, from the speaker and as the controller follows it
    try? await Task.sleep(for: .milliseconds(2_600))
    let info = (try? await soap.call(living.coordinator.host, .avTransport, "GetPositionInfo", [("InstanceID", "0")])) ?? [:]
    let speakerMs = SonosSoapClient.hmsToMs(info["RelTime"])
    check(info["Track"] == "2" && speakerMs >= 1_000, "sonos live: position read from the speaker")
    let followed = await waitFor(3_000) {
        guard let state = await controller.session else { return false }
        return state.track == 2 && state.positionMs >= 1_000
    }
    check(followed, "sonos live: poll reports track and position")
    let localMs = await player.positionMs
    check(abs(localMs - speakerMs) < SonosTiming.driftLimit, "sonos live: local position follows the speaker")

    // A run of skips: the speaker goes quiet once, then plays the song the run ends on
    await controller.next()
    await controller.next()
    let ranTo = await waitForFake { $0["Living room"]?.track == 4 && $0["Living room"]?.state == "PLAYING" }
    check(ranTo, "sonos live: skip run ends on track 4")

    // Queue edits keep the current song and only change what follows
    let atGrow = await player.positionMs
    await player.sonosReplaceQueue(allTracks, startAt: 3, positionMs: atGrow, playing: true)
    await controller.localQueueChanged()
    let grown = await waitForFake { $0["Living room"]?.queue == allTracks.map(\.title) }
    check(grown, "sonos live: added songs appended")
    let edited = allTracks.filter { $0.id != "local-5" }
    let atTrim = await player.positionMs
    await player.sonosReplaceQueue(edited, startAt: 3, positionMs: atTrim, playing: true)
    await controller.localQueueChanged()
    let trimmed = await waitForFake { state in
        state["Living room"]?.queue == edited.map(\.title) && state["Living room"]?.track == 4 && state["Living room"]?.state == "PLAYING"
    }
    check(trimmed, "sonos live: removed song taken out without stopping the current one")

    // A skip made on the speaker (Sonos app): the local player follows it
    if let skip = URL(string: "http://127.0.0.1:1400/debug/skip") { _ = try? await URLSession.shared.data(from: skip) }
    let follows = await waitFor(8_000) { await player.current?.id == "local-6" }
    check(follows, "sonos live: local player follows a skip made on the speaker")

    // Pause
    await controller.pause()
    let paused = await waitForFake { $0["Living room"]?.state == "PAUSED_PLAYBACK" }
    check(paused, "sonos live: pause")

    // Group volume on one room goes through SetGroupVolume
    await controller.setGroupVolume(30)
    let volume = await waitForFake { $0["Living room"]?.volume == 30 }
    check(volume, "sonos live: group volume on one room")

    // Group Kitchen with Living room
    await controller.setGroupMembers(groupID: living.id, memberUUIDs: [kitchen.uuid])
    let joined = await waitForFake(3_000) { $0["Kitchen"]?.coordinator == "Living room" }
    check(joined, "sonos live: Kitchen joined Living room")
    let members = await controller.session?.group.members.map(\.name)
    check(members == ["Living room", "Kitchen"], "sonos live: session group has both rooms")

    // With both room volumes known, the group volume keeps each room's share
    let known2 = await waitFor(10_000) { await controller.session?.speakerVolumes.count == 2 }
    check(known2, "sonos live: room volumes read for the group")
    await controller.setGroupVolume(40)
    let shared = await waitForFake { $0["Living room"]?.volume == 47 && $0["Kitchen"]?.volume == 33 }
    check(shared, "sonos live: group volume spread by share")
    await controller.setSpeakerVolume(uuid: kitchen.uuid, 25)
    let single = await waitForFake { $0["Kitchen"]?.volume == 25 && $0["Living room"]?.volume == 47 }
    check(single, "sonos live: one room's volume")

    // Ungroup
    if let groupID = await controller.session?.group.id {
        await controller.ungroup(groupID: groupID)
    }
    let alone = await waitForFake(3_000) { $0["Kitchen"]?.coordinator == "Kitchen" }
    check(alone, "sonos live: Kitchen on its own again")
    let after = await controller.session?.group.members.count
    check(after == 1, "sonos live: session group back to one room")

    // Another source takes the speaker: the session ends and the local player pauses
    await controller.play()
    let resumed = await waitForFake { $0["Living room"]?.state == "PLAYING" }
    check(resumed, "sonos live: plays again before the takeover")
    if let takeover = URL(string: "http://127.0.0.1:1400/debug/takeover") { _ = try? await URLSession.shared.data(from: takeover) }
    let takenOver = await waitFor(4_000) { await controller.session == nil }
    check(takenOver && log.messages.contains(.takenOver(room: "Living room")), "sonos live: takeover ends the session")
    let localPaused = await player.playWhenReady == false
    check(localPaused, "sonos live: takeover pauses the local player")

    // Connecting again releases the other source first (Pause, then 300 ms) and puts our queue back
    let again = await controller.connect(groupID: living.id)
    check(again, "sonos live: connect again after a takeover")
    // A full reset queues the current song and what follows it, not the songs already played.
    let fromCurrent = edited.drop { $0.id != "local-6" }.map(\.title)
    let back = await waitForFake { $0["Living room"]?.uri == "x-rincon-queue:RINCON_LIVING01400#0" && $0["Living room"]?.queue == fromCurrent }
    check(back, "sonos live: our queue back after the takeover")

    // Opt in with PP_FAKE_SONOS_STALL set to the file the fake watches (its FAKE_SONOS_STALL): while it exists the
    // speaker hangs in TRANSITIONING, and after 12 s without progress both sides pause (spec 5.10).
    if let stallFile = ProcessInfo.processInfo.environment["PP_FAKE_SONOS_STALL"] {
        await controller.play()
        let started = await waitForFake { $0["Living room"]?.state == "PLAYING" }
        check(started, "sonos live: plays before the stall")
        FileManager.default.createFile(atPath: stallFile, contents: Data())
        let stalled = await waitFor(SonosTiming.stall + SonosTiming.trackCommandGrace + 4_000) {
            log.messages.contains(.stalled) || log.messages.contains(.serverUnreachable)
        }
        try? FileManager.default.removeItem(atPath: stallFile)
        check(stalled, "sonos live: stalled speaker noticed")
        let bothPaused = await player.playWhenReady == false
        let speakerPaused = await waitForFake { $0["Living room"]?.state == "PAUSED_PLAYBACK" }
        check(bothPaused && speakerPaused, "sonos live: stall pauses the local player and the speaker")
    }

    // Back to the Mac
    await controller.switchToLocal()
    let ended = await controller.session == nil
    check(ended, "sonos live: session ended")
    let failures = log.messages.filter { if case .failed = $0 { true } else { false } }
    check(failures.isEmpty, "sonos live: no failed commands (\(failures))")

    if let logPath, let handle = FileHandle(forReadingAtPath: logPath) {
        try? handle.seek(toOffset: UInt64(logStart))
        let lines = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
        try? handle.close()
        let entries = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let actions = entries.compactMap { $0["action"] as? String }
        check(!actions.contains("Next") && !actions.contains("Previous") && !actions.contains("Stop"), "sonos live: Next, Previous and Stop never sent")
        check(entries.contains { ($0["action"] as? String) == "Seek" && (($0["args"] as? [String: Any])?["Unit"] as? String) == "TRACK_NR" }, "sonos live: next went as Seek TRACK_NR")
        check(entries.contains { ($0["action"] as? String) == "RemoveTrackRangeFromQueue" && $0["fault"] == nil }, "sonos live: queue edit trimmed with RemoveTrackRangeFromQueue")
        if let takeover = entries.firstIndex(where: { ($0["event"] as? String) == "debug_takeover" }) {
            let next = entries[takeover...].compactMap { $0["action"] as? String }.prefix(3)
            check(Array(next) == ["SetPlayMode", "Pause", "RemoveAllTracksFromQueue"], "sonos live: other source paused before the reset (\(Array(next)))")
        } else { check(false, "sonos live: takeover in the log") }
        check(!entries.contains { $0["parse_error"] != nil } && !entries.contains { ($0["error"] as? Int) == 401 || ($0["fault"] as? Int) == 402 },
              "sonos live: no escaping or SOAPACTION faults")
        let headers = entries.compactMap { $0["hdr"] as? [String: Any] }
        check(!headers.isEmpty && headers.allSatisfy { header in
            header.contains { $0.key.lowercased() == "connection" && ($0.value as? String)?.lowercased() == "close" }
        }, "sonos live: Connection close on every request")
    }

    // Leave the fake as it started.
    for (offset, host) in fakeHosts.enumerated() {
        _ = try? await soap.call(host, .renderingControl, "SetVolume", [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(20 + offset)")])
    }
}
