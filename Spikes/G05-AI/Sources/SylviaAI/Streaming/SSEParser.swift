import Foundation

public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

public enum SSEError: Error, Equatable, Sendable {
    /// A single line exceeded the bound; the stream is rejected rather than buffered without limit.
    case lineTooLong(limit: Int)
    /// One event's accumulated data exceeded the bound.
    case eventTooLarge(limit: Int)
}

/// A bounded, incremental parser for `text/event-stream` (WHATWG HTML, "Server-sent events").
///
/// - Accepts bytes in arbitrary chunks. Lines are split on CRLF, LF or CR at the byte level, including a CR at
///   the end of one chunk followed by LF at the start of the next. Because 0x0A and 0x0D never occur inside a
///   multi-byte UTF-8 sequence, a character split across chunks is reassembled before decoding.
/// - Decodes each complete line as UTF-8 (invalid sequences become U+FFFD, as the standard requires).
/// - Ignores comment lines (keepalives) and unknown fields; strips one leading U+FEFF at stream start.
/// - Bounds memory: a line longer than `maxLineBytes` or an event larger than `maxEventBytes` throws.
public struct SSEParser: Sendable {
    public var maxLineBytes: Int
    public var maxEventBytes: Int

    private var line: [UInt8] = []
    private var lastWasCR = false
    private var atStreamStart = true
    private var dataLines: [String] = []
    private var dataBytes = 0
    private var eventName: String?
    private var lastEventID: String?
    public private(set) var commentCount = 0

    public init(maxLineBytes: Int = 1 << 20, maxEventBytes: Int = 4 << 20) {
        self.maxLineBytes = maxLineBytes
        self.maxEventBytes = maxEventBytes
    }

    /// True when bytes of an unfinished line or event are buffered. At end of input such an event is
    /// discarded (per the standard) and the caller treats the stream as ended early.
    public var hasPartialEvent: Bool { !line.isEmpty || !dataLines.isEmpty || eventName != nil }

    public mutating func feed(_ bytes: some Sequence<UInt8>) throws(SSEError) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for byte in bytes {
            if lastWasCR {
                lastWasCR = false
                if byte == 0x0A { continue }
            }
            switch byte {
            case 0x0D:
                lastWasCR = true
                if let event = try processLine() { events.append(event) }
            case 0x0A:
                if let event = try processLine() { events.append(event) }
            default:
                guard line.count < maxLineBytes else { throw .lineTooLong(limit: maxLineBytes) }
                line.append(byte)
            }
        }
        return events
    }

    /// Call at end of input. Returns nothing: an event without its terminating blank line is discarded.
    public mutating func finish() -> [SSEEvent] {
        line.removeAll()
        dataLines.removeAll()
        dataBytes = 0
        eventName = nil
        return []
    }

    private mutating func processLine() throws(SSEError) -> SSEEvent? {
        var bytes = line[...]
        line.removeAll(keepingCapacity: true)
        if atStreamStart {
            atStreamStart = false
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        }
        if bytes.isEmpty { return dispatch() }
        if bytes.first == UInt8(ascii: ":") {
            commentCount += 1
            return nil
        }
        let field: String
        var value: String
        if let colon = bytes.firstIndex(of: UInt8(ascii: ":")) {
            field = String(decoding: bytes[..<colon], as: UTF8.self)
            var rest = bytes[bytes.index(after: colon)...]
            if rest.first == UInt8(ascii: " ") { rest = rest.dropFirst() }
            value = String(decoding: rest, as: UTF8.self)
        } else {
            field = String(decoding: bytes, as: UTF8.self)
            value = ""
        }
        switch field {
        case "event":
            eventName = value
        case "data":
            dataBytes += value.utf8.count + 1
            guard dataBytes <= maxEventBytes else { throw .eventTooLarge(limit: maxEventBytes) }
            dataLines.append(value)
        case "id":
            if !value.contains("\u{0}") { lastEventID = value }
        default:
            value = ""  // "retry" and unknown fields are ignored.
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            dataLines.removeAll(keepingCapacity: true)
            dataBytes = 0
            eventName = nil
        }
        guard !dataLines.isEmpty else { return nil }
        let name = (eventName?.isEmpty ?? true) ? nil : eventName
        return SSEEvent(event: name, data: dataLines.joined(separator: "\n"), id: lastEventID)
    }
}
