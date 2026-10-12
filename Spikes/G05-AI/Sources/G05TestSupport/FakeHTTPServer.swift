import Foundation
import Network
import Synchronization

public struct RecordedRequest: Sendable {
    public let index: Int
    public let method: String
    public let path: String
    /// Header names lowercased.
    public let headers: [String: String]
    public let body: Data

    public var bodyText: String { String(decoding: body, as: UTF8.self) }
    public var json: [String: Any]? { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] }
}

public enum FakeStep: Sendable {
    /// Writes these bytes as one HTTP chunk.
    case send(Data)
    case pause(milliseconds: Int)
    /// Closes the TCP connection without the terminating zero-length chunk (an early EOF the client can detect).
    case abort
}

public struct FakeResponse: Sendable {
    public var status: Int
    public var headers: [(String, String)]
    public var steps: [FakeStep]

    public init(status: Int, headers: [(String, String)] = [], steps: [FakeStep] = []) {
        self.status = status
        self.headers = headers
        self.steps = steps
    }

    public static func json(_ status: Int, _ text: String, headers: [(String, String)] = []) -> FakeResponse {
        FakeResponse(status: status, headers: [("Content-Type", "application/json")] + headers, steps: [.send(Data(text.utf8))])
    }

    public static func text(_ status: Int, _ text: String, contentType: String = "text/plain") -> FakeResponse {
        FakeResponse(status: status, headers: [("Content-Type", contentType)], steps: [.send(Data(text.utf8))])
    }

    /// An SSE response whose body is sent in the given raw pieces (each its own HTTP chunk).
    public static func sse(_ pieces: [String], pauseMs: Int = 0, abortAtEnd: Bool = false) -> FakeResponse {
        var steps: [FakeStep] = []
        for piece in pieces {
            steps.append(.send(Data(piece.utf8)))
            if pauseMs > 0 { steps.append(.pause(milliseconds: pauseMs)) }
        }
        if abortAtEnd { steps.append(.abort) }
        return FakeResponse(status: 200, headers: [("Content-Type", "text/event-stream"), ("Cache-Control", "no-cache")], steps: steps)
    }

    public static func sseBytes(_ pieces: [Data], abortAtEnd: Bool = false) -> FakeResponse {
        FakeResponse(status: 200, headers: [("Content-Type", "text/event-stream")],
                     steps: pieces.map { .send($0) } + (abortAtEnd ? [.abort] : []))
    }

    public static func redirect(to location: String, status: Int = 307) -> FakeResponse {
        FakeResponse(status: status, headers: [("Location", location)], steps: [])
    }
}

/// An in-process HTTP/1.1 server on 127.0.0.1 and an ephemeral port (bind port 0), for deterministic provider
/// tests. Responses use chunked transfer encoding so an early close is distinguishable from a clean end.
/// It never listens on a non-loopback interface.
public final class FakeHTTPServer: Sendable {
    public typealias Handler = @Sendable (RecordedRequest) -> FakeResponse

    struct State {
        var requests: [RecordedRequest] = []
        var nonHTTPConnections = 0
        var connections: [NWConnection] = []
    }

    private let listener: NWListener
    private let queue: DispatchQueue
    private let state = Mutex(State())
    private let handler: Handler
    public let port: UInt16

    public init(handler: @escaping Handler) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "g05.fake-http-server")
        self.listener = listener
        self.queue = queue
        self.handler = handler
        self.port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, any Error>) in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.withLock({ let was = $0; $0 = true; return !was }) {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case .failed(let error):
                    if resumed.withLock({ let was = $0; $0 = true; return !was }) { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    deinit { stop() }

    public var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
    public func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
    public var requests: [RecordedRequest] { state.withLock { $0.requests } }
    public var nonHTTPConnectionCount: Int { state.withLock { $0.nonHTTPConnections } }

    public func stop() {
        listener.cancel()
        let connections = state.withLock { state in
            defer { state.connections.removeAll() }
            return state.connections
        }
        connections.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        state.withLock { $0.connections.append(connection) }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch Self.parse(buffer) {
            case .needMore:
                if isComplete || error != nil || buffer.count > 64 << 20 { connection.cancel(); return }
                self.receive(on: connection, buffer: buffer)
            case .notHTTP:
                self.state.withLock { $0.nonHTTPConnections += 1 }
                connection.cancel()
            case .request(let method, let path, let headers, let body):
                let recorded = self.state.withLock { state -> RecordedRequest in
                    let request = RecordedRequest(index: state.requests.count, method: method, path: path, headers: headers, body: body)
                    state.requests.append(request)
                    return request
                }
                self.respond(self.handler(recorded), on: connection)
            }
        }
    }

    enum ParseResult {
        case needMore
        case notHTTP
        case request(String, String, [String: String], Data)
    }

    static func parse(_ buffer: Data) -> ParseResult {
        if let first = buffer.first, !(0x41...0x5A).contains(first) { return .notHTTP }  // e.g. a TLS ClientHello (0x16)
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > 65_536 ? .notHTTP : .needMore
        }
        let head = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .notHTTP }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .needMore }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        return .request(String(requestLine[0]), String(requestLine[1]), headers, body)
    }

    private func respond(_ response: FakeResponse, on connection: NWConnection) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
        head += "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        run(response.steps[...], on: connection)
    }

    private func run(_ steps: ArraySlice<FakeStep>, on connection: NWConnection) {
        guard let step = steps.first else {
            connection.send(content: Data("0\r\n\r\n".utf8), contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let rest = steps.dropFirst()
        switch step {
        case .send(let data):
            guard !data.isEmpty else { run(rest, on: connection); return }
            var chunk = Data(String(data.count, radix: 16).utf8)
            chunk.append(Data("\r\n".utf8))
            chunk.append(data)
            chunk.append(Data("\r\n".utf8))
            connection.send(content: chunk, completion: .contentProcessed { [weak self] _ in self?.run(rest, on: connection) })
        case .pause(let milliseconds):
            queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [weak self] in self?.run(rest, on: connection) }
        case .abort:
            connection.forceCancel()
        }
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 307: "Temporary Redirect"
        case 308: "Permanent Redirect"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        case 529: "Overloaded"
        default: "Status"
        }
    }
}
