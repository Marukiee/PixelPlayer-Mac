import Foundation

/// The four UPnP services PixelPlayer talks to on a speaker (spec 5.2).
public enum SonosService: String, Sendable, CaseIterable {
    case avTransport
    case renderingControl
    case groupRenderingControl
    case zoneGroupTopology

    public var controlPath: String {
        switch self {
        case .avTransport: "/MediaRenderer/AVTransport/Control"
        case .renderingControl: "/MediaRenderer/RenderingControl/Control"
        case .groupRenderingControl: "/MediaRenderer/GroupRenderingControl/Control"
        case .zoneGroupTopology: "/ZoneGroupTopology/Control"
        }
    }

    public var urn: String {
        switch self {
        case .avTransport: "urn:schemas-upnp-org:service:AVTransport:1"
        case .renderingControl: "urn:schemas-upnp-org:service:RenderingControl:1"
        case .groupRenderingControl: "urn:schemas-upnp-org:service:GroupRenderingControl:1"
        case .zoneGroupTopology: "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
        }
    }

    /// The exact SOAPACTION value, quotes included; the fake household answers 401 to anything else.
    public func soapAction(_ action: String) -> String { "\"\(urn)#\(action)\"" }
}

/// A UPnP fault or a network failure. `upnpCode` is the speaker's errorCode (701, 711, 714, 800, 804) when it sent one,
/// else the HTTP status for a failed answer, and nil when no answer came at all.
public struct SonosError: Error, Equatable, LocalizedError, Sendable {
    public var action: String
    public var upnpCode: Int?
    public var message: String

    public init(action: String, upnpCode: Int? = nil, message: String) {
        self.action = action
        self.upnpCode = upnpCode
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Minimal UPnP SOAP client for Sonos speakers on the local network, the same as the Android `SonosSoapClient`.
/// Arguments are escaped once here, so callers pass plain text (DIDL-Lite included, which therefore ends up escaped twice).
public final class SonosSoapClient: Sendable {
    private let session: URLSession
    private let quickSession: URLSession

    public init() {
        session = Self.makeSession(resourceLimitMs: SonosTiming.soapConnectTimeout + SonosTiming.soapReadTimeout)
        // Gives up quickly, for a call that must never hold up what comes after it.
        quickSession = Self.makeSession(resourceLimitMs: SonosTiming.quickCallLimit)
    }

    private static func makeSession(resourceLimitMs: Int) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Double(SonosTiming.soapReadTimeout) / 1000
        config.timeoutIntervalForResource = Double(resourceLimitMs) / 1000
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    /// One SOAP call; returns the children of `<ActionResponse>` as name to text.
    @discardableResult
    public func call(_ host: String, _ service: SonosService, _ action: String, _ args: [(String, String)] = []) async throws -> [String: String] {
        try await execute(session, host, service, action, args)
    }

    /// Like `call`, with a total limit of 1.5 s.
    @discardableResult
    public func callQuick(_ host: String, _ service: SonosService, _ action: String, _ args: [(String, String)] = []) async throws -> [String: String] {
        try await execute(quickSession, host, service, action, args)
    }

    private func execute(_ session: URLSession, _ host: String, _ service: SonosService, _ action: String, _ args: [(String, String)]) async throws -> [String: String] {
        guard let url = URL(string: "http://\(host)\(service.controlPath)") else {
            throw SonosError(action: action, message: "\(action): bad host")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(service.soapAction(action), forHTTPHeaderField: "SOAPACTION")
        // Speakers close the socket after each answer; reusing it stalls the next call.
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.envelope(service: service, action: action, args: args).utf8)
        let (data, response) = try await load(session, request, action: action)
        let text = String(decoding: data, as: UTF8.self)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = Self.parseFaultCode(text) ?? status
            throw SonosError(action: action, upnpCode: code, message: "\(action) failed (UPnP \(code))")
        }
        return Self.parseResponse(text, action: action)
    }

    /// `GET http://host/path`, used for the device description.
    public func get(host: String, path: String) async throws -> String {
        guard let url = URL(string: "http://\(host)\(path)") else { throw SonosError(action: "GET", message: "GET \(path): bad host") }
        var request = URLRequest(url: url)
        request.setValue("close", forHTTPHeaderField: "Connection")
        let (data, response) = try await load(session, request, action: "GET \(path)")
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SonosError(action: "GET", upnpCode: status, message: "GET \(path): \(status)") }
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the first byte of a song can be fetched (spec 5.10). Never logs the address: it holds the login.
    public func canReach(_ url: String) async -> Bool {
        guard let target = URL(string: url) else { return false }
        var request = URLRequest(url: target, timeoutInterval: Double(SonosTiming.reachTimeout) / 1000)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (200...399).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func load(_ session: URLSession, _ request: URLRequest, action: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SonosError(action: action, message: "\(action): \(error.localizedDescription)")
        }
    }

    // MARK: Pure parts

    public static func envelope(service: SonosService, action: String, args: [(String, String)]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        xml += "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
        xml += "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
        xml += "<u:\(action) xmlns:u=\"\(service.urn)\">"
        for (name, value) in args {
            xml += "<\(name)>\(xmlEscape(value))</\(name)>"
        }
        xml += "</u:\(action)></s:Body></s:Envelope>"
        return xml
    }

    public static func xmlEscape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.utf8.count + 16)
        for c in value {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(c)
            }
        }
        return out
    }

    /// The child elements of `<u:ActionResponse>` as name to text.
    public static func parseResponse(_ xml: String, action: String) -> [String: String] {
        guard !xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let reader = ResponseReader(target: "\(action)Response")
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        parser.parse()
        return reader.result
    }

    public static func parseFaultCode(_ xml: String) -> Int? {
        let reader = ElementTextReader(target: "errorCode")
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        parser.parse()
        return reader.text.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// "0:03:41" to milliseconds; "NOT_IMPLEMENTED" or blanks give 0.
    public static func hmsToMs(_ value: String?) -> Int {
        guard let parts = value?.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false),
              parts.count == 3,
              let h = Int(parts[0]), let m = Int(parts[1]),
              let s = Int(parts[2].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        else { return 0 }
        return ((h * 60 + m) * 60 + s) * 1000
    }

    public static func msToHms(_ ms: Int) -> String {
        let total = max(ms, 0) / 1000
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

/// Collects the children of the first element with the given local name.
private final class ResponseReader: NSObject, XMLParserDelegate {
    let target: String
    var result: [String: String] = [:]
    private var depth = -1
    private var done = false
    private var child = ""
    private var text = ""

    init(target: String) { self.target = target }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if done { return }
        if depth < 0 {
            if elementName == target { depth = 0 }
            return
        }
        depth += 1
        if depth == 1 { child = elementName; text = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth >= 1 { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if depth >= 1 { text += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard !done, depth >= 0 else { return }
        if depth == 1 { result[child] = text }
        depth -= 1
        // The response element itself closed: nothing after it matters.
        if depth < 0 { done = true; parser.abortParsing() }
    }
}

/// The text of the first element with the given local name.
private final class ElementTextReader: NSObject, XMLParserDelegate {
    let target: String
    var text: String?
    private var inside = false

    init(target: String) { self.target = target }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if text == nil && elementName == target { inside = true; text = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inside { text? += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if inside && elementName == target { inside = false; parser.abortParsing() }
    }
}
