import Foundation
import Darwin

/// Finds Sonos speakers and reads the room groups from any one of them (spec 5.1).
///
/// With a manual host list (like Android's `sonos_hosts.txt`, one `ip:port` per line) no SSDP is sent at all, so tests
/// against the fake household never reach real speakers. Hosts that answered before are remembered and tried again,
/// so a network that drops multicast still finds known speakers; the app keeps `knownHosts` and passes them back in.
public actor SonosDiscovery {
    public let manualHosts: [String]
    public private(set) var knownHosts: [String]
    private let allowSSDP: Bool
    private let soap: SonosSoapClient
    private var modelCache: [String: String] = [:]

    public init(manualHosts: [String] = [], knownHosts: [String] = [], allowSSDP: Bool = true, soap: SonosSoapClient = SonosSoapClient()) {
        self.manualHosts = manualHosts
        self.knownHosts = knownHosts
        self.allowSSDP = allowSSDP
        self.soap = soap
    }

    /// Tries every host in order (SSDP, manual, known); the first that gives a topology wins. Empty when none answers.
    public func discoverGroups() async -> [SonosGroup] {
        var hosts: [String] = []
        if allowSSDP && manualHosts.isEmpty { hosts += await Self.ssdpSearch() }
        hosts += manualHosts
        hosts += knownHosts
        var seen = Set<String>()
        for host in hosts where seen.insert(host).inserted {
            guard let groups = try? await readGroups(host: host) else { continue }
            var known: [String] = []
            for host in groups.flatMap({ $0.members.map(\.host) }) where !known.contains(host) { known.append(host) }
            knownHosts = known
            return groups
        }
        return []
    }

    /// Reads `GetZoneGroupState` from one speaker and fills in each room's model.
    public func readGroups(host: String) async throws -> [SonosGroup] {
        guard let state = try await soap.call(host, .zoneGroupTopology, "GetZoneGroupState")["ZoneGroupState"] else {
            throw SonosError(action: "GetZoneGroupState", message: "No ZoneGroupState")
        }
        var groups = Self.parseZoneGroupState(state)
        for g in groups.indices {
            for m in groups[g].members.indices {
                groups[g].members[m].model = await model(for: groups[g].members[m])
            }
        }
        return groups
    }

    private func model(for speaker: SonosSpeaker) async -> String? {
        if let cached = modelCache[speaker.uuid] { return cached }
        guard let xml = try? await soap.get(host: speaker.host, path: "/xml/device_description.xml"),
              let model = Self.parseModelName(xml) else { return nil }
        modelCache[speaker.uuid] = model
        return model
    }

    // MARK: Pure parts

    /// The lines of a `sonos_hosts.txt`: one `ip:port` per line, blanks skipped.
    public static func hosts(fromList text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `<modelName>` from a device description, without the leading "Sonos ".
    public static func parseModelName(_ xml: String) -> String? {
        guard let range = xml.range(of: "<modelName>[^<]*</modelName>", options: .regularExpression) else { return nil }
        var name = String(xml[range].dropFirst("<modelName>".count).dropLast("</modelName>".count))
        if name.hasPrefix("Sonos ") { name.removeFirst("Sonos ".count) }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Takes "ip:port" out of the LOCATION header of an SSDP answer.
    public static func parseLocationHost(_ response: String) -> String? {
        for line in response.split(whereSeparator: \.isNewline) where line.lowercased().hasPrefix("location:") {
            return hostOf(String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    public static func hostOf(_ url: String) -> String? {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: "^https?://[^/]+", options: .regularExpression),
              let separator = text.range(of: "://") else { return nil }
        return String(text[separator.upperBound..<range.upperBound])
    }

    /// Parses the ZoneGroupState XML. Hidden members (surrounds, subs, bonded pairs) are left out; a group whose
    /// coordinator is not visible is dropped. Members: coordinator first, then by name. Groups: by coordinator name.
    public static func parseZoneGroupState(_ xml: String) -> [SonosGroup] {
        let reader = TopologyReader()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        parser.parse()
        var groups: [SonosGroup] = []
        for raw in reader.groups {
            guard raw.members.contains(where: { $0.uuid == raw.coordinator }) else { continue }
            let sorted = raw.members.enumerated().sorted { a, b in
                let ac = a.element.uuid != raw.coordinator, bc = b.element.uuid != raw.coordinator
                if ac != bc { return !ac }
                if a.element.name != b.element.name { return a.element.name < b.element.name }
                return a.offset < b.offset
            }.map(\.element)
            groups.append(SonosGroup(id: raw.id, coordinatorUUID: raw.coordinator, members: sorted))
        }
        return groups.enumerated().sorted { a, b in
            a.element.coordinator.name != b.element.coordinator.name
                ? a.element.coordinator.name < b.element.coordinator.name : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: SSDP

    /// M-SEARCH for ZonePlayers over a plain BSD UDP socket (the Network framework needs a multicast entitlement).
    /// Sent twice, 400 ms socket timeout, 2 s of listening. Returns "ip:port" from each LOCATION header.
    public static func ssdpSearch(timeoutMs: Int = SonosTiming.ssdpListen) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ssdpSearchBlocking(timeoutMs: timeoutMs))
            }
        }
    }

    /// The exact M-SEARCH the phone sends (spec 5.1).
    public static let ssdpMessage = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\n" +
        "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"

    private static func ssdpSearchBlocking(timeoutMs: Int) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: Int32(SonosTiming.ssdpSocketTimeout * 1000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &address.sin_addr)
        let message = Array(ssdpMessage.utf8)
        for _ in 0..<SonosTiming.ssdpSends {
            _ = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, message, message.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        var found: [String] = []
        var buffer = [UInt8](repeating: 0, count: 2048)
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0 {
                // A timeout (EAGAIN) just means nobody answered in this slice; keep listening until the deadline.
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                break
            }
            guard count > 0 else { continue }
            let text = String(decoding: buffer[0..<count], as: UTF8.self)
            if let host = parseLocationHost(text), !found.contains(host) { found.append(host) }
        }
        return found
    }
}

/// Collects `ZoneGroup` and visible `ZoneGroupMember` elements.
private final class TopologyReader: NSObject, XMLParserDelegate {
    struct RawGroup { var id: String; var coordinator: String; var members: [SonosSpeaker] }
    var groups: [RawGroup] = []
    private var current: RawGroup?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "ZoneGroup":
            current = RawGroup(id: attributes["ID"] ?? "", coordinator: attributes["Coordinator"] ?? "", members: [])
        case "ZoneGroupMember":
            guard current != nil, attributes["Invisible"] != "1",
                  let host = SonosDiscovery.hostOf(attributes["Location"] ?? "") else { return }
            let name = attributes["ZoneName"].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "Sonos"
            current?.members.append(SonosSpeaker(uuid: attributes["UUID"] ?? "", name: name, host: host))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "ZoneGroup", let group = current {
            groups.append(group)
            current = nil
        }
    }
}
