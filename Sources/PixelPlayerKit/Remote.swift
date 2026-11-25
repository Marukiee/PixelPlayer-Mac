import Foundation
import Network
import IOBluetooth

// The remote player protocol of the Android app (spec section 6): one phone plays its own copy of each song while
// another device keeps the queue. The Mac takes the controller's part. JSON objects, one per line, over Bluetooth RFCOMM
// or, as a test hook, TCP.

public enum RemoteProtocol {
    /// The RFCOMM service the phone listens on while "Use this phone as remote player" is on.
    public static let serviceUUID = "6f0c6a52-8d1e-4b0e-9f3a-2c7d1e5b9a41"
    public static let pingInterval: TimeInterval = 2
    public static let silenceLimit: TimeInterval = 8
    public static let windowBefore = 20
    public static let windowAhead = 300

    /// The last three parts of a path, so the phone finds its own copy in a differently named music folder.
    public static func pathTail(_ path: String?) -> String {
        guard let path, !path.isEmpty, !path.contains("://") else { return "" }
        let parts = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return parts.suffix(3).joined(separator: "/")
    }
}

public struct RemoteTrack: Codable, Sendable, Hashable {
    public var id: String
    public var p: String
    public var ti: String
    public var ar: String
    public var al: String
    public var d: Int

    public init(id: String, path: String?, title: String, artist: String, album: String, durationMs: Int) {
        self.id = id
        self.p = RemoteProtocol.pathTail(path)
        self.ti = title
        self.ar = artist
        self.al = album
        self.d = durationMs
    }
}

/// What the phone reports.
public struct RemoteState: Sendable, Equatable {
    public var qid: Int64
    public var id: String?
    public var foreign: Bool
    public var positionMs: Int
    public var durationMs: Int
    public var playWhenReady: Bool
    public var playing: Bool
    public var volume: Int
}

public enum RemoteMessage: Sendable, Equatable {
    case hello(name: String, role: String)
    case state(RemoteState)
    case queued(qid: Int64, missing: [String], found: Int)
    case volumeHeld
    case bye
    case other(String)

    /// Reads one line; nil for blank or unreadable lines, which the protocol ignores.
    public static func parse(_ line: String) -> RemoteMessage? {
        guard let data = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["t"] as? String else { return nil }
        func int(_ key: String) -> Int { (json[key] as? NSNumber)?.intValue ?? 0 }
        func long(_ key: String) -> Int64 { (json[key] as? NSNumber)?.int64Value ?? 0 }
        func bool(_ key: String) -> Bool { (json[key] as? NSNumber)?.boolValue ?? false }
        switch type {
        case "hello": return .hello(name: json["name"] as? String ?? "", role: json["role"] as? String ?? "")
        case "state":
            return .state(RemoteState(qid: long("qid"), id: json["id"] as? String, foreign: bool("foreign"), positionMs: int("pos"),
                                      durationMs: int("dur"), playWhenReady: bool("play"), playing: bool("playing"), volume: int("vol")))
        case "queued": return .queued(qid: long("qid"), missing: json["missing"] as? [String] ?? [], found: int("found"))
        case "volume_held": return .volumeHeld
        case "bye": return .bye
        default: return .other(type)
        }
    }

    /// The controller's messages, ready to send (with the newline).
    public static func encode(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    public static func hello(name: String, session: Bool) -> Data {
        encode(["t": "hello", "v": 1, "name": name, "role": "controller", "session": session])
    }

    public static func queue(qid: Int64, items: [RemoteTrack], index: Int, positionMs: Int, play: Bool, repeatMode: Int) -> Data {
        let tracks = items.map { ["id": $0.id, "p": $0.p, "ti": $0.ti, "ar": $0.ar, "al": $0.al, "d": $0.d] as [String: Any] }
        return encode(["t": "queue", "qid": qid, "items": tracks, "index": index, "pos": positionMs, "play": play, "repeat": repeatMode])
    }

    public static func jump(qid: Int64, id: String, index: Int, positionMs: Int, play: Bool) -> Data {
        encode(["t": "jump", "qid": qid, "id": id, "index": index, "pos": positionMs, "play": play])
    }

    public static func simple(_ type: String) -> Data { encode(["t": type]) }
    public static func seek(_ positionMs: Int) -> Data { encode(["t": "seek", "pos": positionMs]) }
    public static func volume(_ value: Int) -> Data { encode(["t": "volume", "v": max(0, min(100, value))]) }
}

// MARK: Transports

/// A line-based link to a phone. Received lines arrive on the main queue.
public protocol RemoteLink: AnyObject {
    var onLine: ((String) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func open(timeout: TimeInterval) async -> Bool
    func send(_ data: Data)
    func close()
}

/// Splits a byte stream into lines, dropping lines over 4 MiB as the protocol says.
final class LineBuffer {
    private var buffer = Data()
    func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if lineData.count <= 4 * 1024 * 1024, let line = String(data: lineData, encoding: .utf8),
               !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
        }
        if buffer.count > 4 * 1024 * 1024 { buffer.removeAll() }
        return lines
    }
}

/// The TCP test hook: the phone listens on the port in its remote_listen_port.txt.
public final class TCPRemoteLink: RemoteLink, @unchecked Sendable {
    public var onLine: ((String) -> Void)?
    public var onClose: (() -> Void)?
    private let connection: NWConnection
    private let lines = LineBuffer()
    private var closed = false

    public init(host: String, port: UInt16) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: nil, tcp: tcp))
    }

    public func open(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            var finished = false
            let finish: (Bool) -> Void = { ok in
                guard !finished else { return }
                finished = true
                done.resume(returning: ok)
            }
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: finish(true); self?.receive()
                // A refused connection waits for the network to change; for a phone that is simply not listening.
                case .waiting: finish(false); self?.connection.cancel()
                case .failed, .cancelled: finish(false); self?.finishClose()
                default: break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if !finished { finish(false); self?.connection.cancel() }
            }
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { for line in self.lines.append(data) { self.onLine?(line) } }
            if complete || error != nil { self.finishClose() } else { self.receive() }
        }
    }

    public func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    public func close() {
        connection.cancel()
        finishClose()
    }

    private func finishClose() {
        guard !closed else { return }
        closed = true
        onClose?()
    }
}

/// Bluetooth RFCOMM to a paired phone: the service is found by its UUID, as the phones do.
public final class BluetoothRemoteLink: NSObject, RemoteLink, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    public var onLine: ((String) -> Void)?
    public var onClose: (() -> Void)?
    private let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private let lines = LineBuffer()
    private var openContinuation: CheckedContinuation<Bool, Never>?
    private var sdpContinuation: CheckedContinuation<Bool, Never>?
    private var closed = false

    public init(device: IOBluetoothDevice) {
        self.device = device
    }

    /// Paired devices that are phones (or of unknown class), as the Android controller lists them.
    public static func pairedPhones() -> [IOBluetoothDevice] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return devices.filter { $0.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone) || $0.deviceClassMajor == 0 }
    }

    private static var serviceUUID: IOBluetoothSDPUUID {
        let uuid = UUID(uuidString: RemoteProtocol.serviceUUID)!
        var bytes = uuid.uuid
        return withUnsafeBytes(of: &bytes) { IOBluetoothSDPUUID(bytes: $0.baseAddress!, length: 16) }
    }

    public func open(timeout: TimeInterval) async -> Bool {
        // Ask the phone which RFCOMM channel the service is on. Not tried against a real phone yet.
        let queried = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            sdpContinuation = done
            if device.performSDPQuery(self, uuids: [Self.serviceUUID]) != kIOReturnSuccess { finishSDP(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finishSDP(false) }
        }
        guard queried || device.services != nil, let record = device.getServiceRecord(for: Self.serviceUUID) else { return false }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { return false }
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            openContinuation = done
            var opened: IOBluetoothRFCOMMChannel?
            let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
            channel = opened
            if result != kIOReturnSuccess { finishOpen(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finishOpen(false) }
        }
    }

    @objc public func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        finishSDP(status == kIOReturnSuccess)
    }

    private func finishSDP(_ ok: Bool) {
        sdpContinuation?.resume(returning: ok)
        sdpContinuation = nil
    }

    private func finishOpen(_ ok: Bool) {
        openContinuation?.resume(returning: ok)
        openContinuation = nil
    }

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        finishOpen(error == kIOReturnSuccess)
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        DispatchQueue.main.async { for line in self.lines.append(data) { self.onLine?(line) } }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async { self.finishClose() }
    }

    public func send(_ data: Data) {
        guard let channel else { return }
        // RFCOMM takes at most the channel's MTU per write.
        let mtu = max(64, Int(channel.getMTU()))
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + mtu)
            var chunk = [UInt8](data[offset..<end])
            _ = channel.writeSync(&chunk, length: UInt16(chunk.count))
            offset = end
        }
    }

    public func close() {
        channel?.close()
        finishClose()
    }

    private func finishClose() {
        guard !closed else { return }
        closed = true
        onClose?()
    }
}
