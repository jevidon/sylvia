import CryptoKit
import Foundation
import Synchronization
import SylviaTransferCore

/// What the phone stores about a paired source. The token itself lives only in a CredentialStore.
public struct PairedSource: Codable, Hashable, Sendable {
    public var sourceID: String
    public var sourceName: String
    public var deviceID: String
    public var spkiSHA256: String
    public var endpoints: [PairingPayload.Endpoint]
    public var scopes: [Scope]

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case sourceName = "source_name"
        case deviceID = "device_id"
        case spkiSHA256 = "spki_sha256"
        case endpoints
        case scopes
    }

    public init(
        sourceID: String, sourceName: String, deviceID: String, spkiSHA256: String,
        endpoints: [PairingPayload.Endpoint], scopes: [Scope]
    ) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.deviceID = deviceID
        self.spkiSHA256 = spkiSHA256
        self.endpoints = endpoints
        self.scopes = scopes
    }
}

/// HTTPS client for one source, pinned to its SPKI digest. Usable on iOS and macOS.
///
/// Foreground URLSession data tasks are used here; the iOS background-download client (G0.2 part 2)
/// reuses the same pin evaluation, header and body validation and staging store.
public final class SourceClient: Sendable {
    public let baseURL: URL
    public let pin: SPKIPin
    public let sourceID: String
    private let session: URLSession
    private let delegate: PinnedSessionDelegate
    private let token: String?

    public init(baseURL: URL, pin: SPKIPin, sourceID: String, token: String?, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.pin = pin
        self.sourceID = sourceID
        self.token = token
        (session, delegate) = PinnedSessionFactory.make(pin: pin, timeout: timeout)
    }

    deinit { session.invalidateAndCancel() }

    /// Number of TLS handshakes this client refused because the peer's key did not match the pin.
    public var pinMismatchesObserved: Int { delegate.pinMismatchesObserved }

    /// Observes the negotiated TLS version and ALPN protocol of each completed request.
    public func observeConnectionMetrics(_ observer: @escaping @Sendable (tls_protocol_version_t?, String?) -> Void) {
        delegate.metricsObserver.withLock { $0 = observer }
    }

    // MARK: Pairing

    /// Pairs with the source described by `payload`. The secret is sent only over a connection whose
    /// certificate matches the payload's pin; endpoints are tried in order and a mismatching endpoint
    /// is never sent anything.
    public static func pair(
        payload: PairingPayload, deviceID: String, deviceName: String, now: Date = Date(), timeout: TimeInterval = 150
    ) async throws(ClientError) -> (PairedSource, token: String) {
        do { try payload.validate(now: now) } catch { throw .invalidPayload(error) }
        let pin: SPKIPin
        do { pin = try payload.pin } catch { throw .invalidPayload(.invalidPin) }
        let request = PairRequest(
            invitationID: payload.invitationID, invitationSecret: payload.invitationSecret,
            sourceID: payload.sourceID, deviceID: deviceID, deviceName: deviceName)
        var lastError = ClientError.unreachable
        for endpoint in payload.endpoints {
            guard let base = endpoint.baseURL() else { continue }
            let client = SourceClient(baseURL: base, pin: pin, sourceID: payload.sourceID, token: nil, timeout: timeout)
            let response: PairResponse
            do throws(ClientError) {
                response = try await client.send(method: "POST", path: "/v1/pair", body: request)
            } catch {
                switch error {
                case .unreachable, .dnsFailure, .timedOut, .transport, .pinMismatch, .tlsFailure:
                    // Try the next address. A pin mismatch means this address is not the source,
                    // and the handshake was refused before the request (and its secret) was sent.
                    lastError = error
                    continue
                default:
                    throw error
                }
            }
            guard response.sourceID == payload.sourceID, response.deviceID == deviceID,
                response.spkiSHA256 == pin.hex, response.tokenType == "bearer",
                let tokenBytes = Base64URL.decode(response.token), tokenBytes.count >= 32
            else { throw .invalidResponse("pairing response does not match the invitation") }
            let paired = PairedSource(
                sourceID: payload.sourceID, sourceName: payload.sourceName, deviceID: deviceID,
                spkiSHA256: pin.hex, endpoints: payload.endpoints, scopes: response.scopes)
            return (paired, response.token)
        }
        // Every address failed. If iOS refused them because the local network is denied to the app, say so
        // (plan 14.3, 15.5): nothing was sent either way.
        throw await lastError.classifyingLocalNetwork(endpoints: payload.endpoints)
    }

    // MARK: Authenticated endpoints

    public func capabilities() async throws(ClientError) -> Capabilities {
        let capabilities: Capabilities = try await send(method: "GET", path: "/v1/capabilities")
        guard capabilities.supportedMajorVersions.contains(TransferProtocol.major) else {
            throw .unsupportedProtocol(major: capabilities.protocolVersion.major)
        }
        guard capabilities.sourceID == sourceID else { throw .invalidResponse("capabilities are for another source") }
        return capabilities
    }

    public func catalog(cursor: String? = nil, limit: Int? = nil) async throws(ClientError) -> CatalogPage {
        var query: [URLQueryItem] = []
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await send(method: "GET", path: "/v1/catalog", query: query)
    }

    public func deviceInbox(cursor: String? = nil) async throws(ClientError) -> DeviceInboxPage {
        var query: [URLQueryItem] = []
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(method: "GET", path: "/v1/device-inbox", query: query)
    }

    /// Fetches and validates a manifest before any byte is requested (A.3).
    public func manifest(itemID: String, partSize: Int64? = nil) async throws(ClientError) -> TransferManifest {
        guard CanonicalID.isValid(itemID) else { throw .invalidResponse("invalid item id") }
        var query: [URLQueryItem] = []
        if let partSize { query.append(URLQueryItem(name: "part_size", value: String(partSize))) }
        let data = try await sendRaw(method: "GET", path: "/v1/items/\(itemID)/manifest", query: query, body: nil)
        do {
            return try ManifestValidator.decodeAndValidate(
                data, expecting: .init(sourceID: sourceID, itemID: itemID))
        } catch {
            throw .invalidManifest(error)
        }
    }

    public func postReceipt(_ receipt: Receipt) async throws(ClientError) -> ReceiptAck {
        try await send(method: "POST", path: "/v1/receipts", body: receipt)
    }

    /// Self-revocation (DELETE /v1/pairings/{device_id}).
    public func revoke(deviceID: String) async throws(ClientError) {
        guard CanonicalID.isValid(deviceID) else { throw .invalidResponse("invalid device id") }
        _ = try await sendRaw(method: "DELETE", path: "/v1/pairings/\(deviceID)", query: [], body: nil)
    }

    // MARK: Parts

    /// Downloads one part into a new temporary file in `directory` and validates it.
    ///
    /// The response head is checked before any body byte is written (a 200, 412, 416, wrong
    /// Content-Range, changed ETag or encoding is rejected without keeping bytes); the body is
    /// streamed to disk with an incremental SHA-256, so memory stays bounded by the URLSession
    /// buffer, not the part size. On success the caller owns the returned file.
    public func fetchPart(
        _ part: TransferManifest.Part, of asset: TransferManifest.Asset, into directory: URL
    ) async -> Result<URL, PartFailure> {
        guard let token else { return .failure(.unauthorized) }
        let expectation = PartResponseValidator.Expectation(part: part, asset: asset)
        var request = URLRequest(url: url(path: "/v1/assets/\(asset.assetID)/content", query: []))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(expectation.rangeHeader, forHTTPHeaderField: "Range")
        request.setValue(asset.etag, forHTTPHeaderField: "If-Match")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let temporary = directory.appendingPathComponent("part-\(part.index)-\(CanonicalID.make()).incoming")
        let sink: PartFileSink
        do {
            sink = try PartFileSink(file: temporary, expectation: expectation)
        } catch {
            return .failure(.transport("cannot create part file"))
        }
        let task = session.dataTask(with: request)
        delegate.register(sink, for: task)
        let outcome: PartFileSink.Outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sink.setContinuation(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        switch outcome {
        case .failure(let failure):
            try? FileManager.default.removeItem(at: temporary)
            return .failure(failure)
        case .complete(let received, let digest):
            if let failure = PartResponseValidator.validateBody(receivedBytes: received, sha256Hex: digest, part: part) {
                try? FileManager.default.removeItem(at: temporary)
                return .failure(failure)
            }
            return .success(temporary)
        }
    }

    // MARK: Raw requests (tests only)

    public struct RawResponse: Sendable {
        public let status: Int
        public let headers: [String: String]
        public let body: Data
        public func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    /// Sends a request with exactly the given path (no encoding) and headers over the pinned session.
    /// Used by contract tests to send malformed or hostile requests; pinning still applies.
    @_spi(Testing)
    public func raw(method: String, pathAndQuery: String, headers: [String: String] = [:], body: Data? = nil) async throws(ClientError) -> RawResponse {
        guard let url = URL(string: baseURL.absoluteString + pathAndQuery) else { throw .invalidResponse("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.httpBody = body }
        let sink = BufferSink(limit: 64 * 1_048_576)
        let task = session.dataTask(with: request)
        delegate.register(sink, for: task)
        let outcome: BufferSink.Outcome = await withCheckedContinuation { continuation in
            sink.setContinuation(continuation)
            task.resume()
        }
        switch outcome {
        case .transport(let error): throw error
        case .response(let status, let data):
            let response = task.response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (key, value) in response?.allHeaderFields ?? [:] {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
            return RawResponse(status: status, headers: headers, body: data)
        }
    }

    // MARK: Plumbing

    func url(path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    func send<Response: Decodable>(
        method: String, path: String, query: [URLQueryItem] = []
    ) async throws(ClientError) -> Response {
        let data = try await sendRaw(method: method, path: path, query: query, body: nil)
        do { return try TransferJSON.decode(Response.self, from: data) } catch {
            throw .invalidResponse("response does not match the contract")
        }
    }

    func send<Body: Encodable, Response: Decodable>(
        method: String, path: String, query: [URLQueryItem] = [], body: Body
    ) async throws(ClientError) -> Response {
        let encoded: Data
        do { encoded = try TransferJSON.encode(body) } catch { throw .invalidResponse("cannot encode request") }
        let data = try await sendRaw(method: method, path: path, query: query, body: encoded)
        do { return try TransferJSON.decode(Response.self, from: data) } catch {
            throw .invalidResponse("response does not match the contract")
        }
    }

    func sendRaw(method: String, path: String, query: [URLQueryItem], body: Data?) async throws(ClientError) -> Data {
        var request = URLRequest(url: url(path: path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let sink = BufferSink(limit: 32 * 1_048_576)
        let task = session.dataTask(with: request)
        delegate.register(sink, for: task)
        let outcome: BufferSink.Outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sink.setContinuation(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        switch outcome {
        case .transport(let error):
            throw error
        case .response(let status, let data):
            guard (200..<300).contains(status) else {
                let code = (try? TransferJSON.decode(ErrorBody.self, from: data))?.error.code
                throw .http(status: status, code: code)
            }
            return data
        }
    }
}

/// Collects a small JSON response body.
final class BufferSink: TaskSink {
    enum Outcome: Sendable {
        case response(status: Int, data: Data)
        case transport(ClientError)
    }

    private struct State {
        var status = 0
        var data = Data()
        var overflow = false
        var continuation: CheckedContinuation<Outcome, Never>?
        var pending: Outcome?
    }

    private let limit: Int
    private let state = Mutex(State())

    init(limit: Int) { self.limit = limit }

    func setContinuation(_ continuation: CheckedContinuation<Outcome, Never>) {
        let ready: Outcome? = state.withLock { state in
            if let pending = state.pending { return pending }
            state.continuation = continuation
            return nil
        }
        if let ready { continuation.resume(returning: ready) }
    }

    func head(_ response: HTTPURLResponse) -> Bool {
        state.withLock { $0.status = response.statusCode }
        return true
    }

    func body(_ data: Data) {
        state.withLock { state in
            if state.data.count + data.count > limit { state.overflow = true } else { state.data.append(data) }
        }
    }

    func complete(error: (any Error)?, pinMismatch: Bool) {
        let (continuation, outcome): (CheckedContinuation<Outcome, Never>?, Outcome) = state.withLock { state in
            let outcome: Outcome
            if let error {
                outcome = .transport(ClientError.from(transportError: error, pinMismatch: pinMismatch))
            } else if state.overflow {
                outcome = .transport(.invalidResponse("response too large"))
            } else {
                outcome = .response(status: state.status, data: state.data)
            }
            let continuation = state.continuation
            state.continuation = nil
            if continuation == nil { state.pending = outcome }
            return (continuation, outcome)
        }
        continuation?.resume(returning: outcome)
    }
}

/// Streams one part body to a file while hashing it.
final class PartFileSink: TaskSink {
    enum Outcome: Sendable {
        case complete(received: Int64, sha256: String)
        case failure(PartFailure)
    }

    private struct State {
        var handle: FileHandle?
        var hasher = SHA256()
        var received: Int64 = 0
        var headFailure: PartFailure?
        var writeFailed = false
        var continuation: CheckedContinuation<Outcome, Never>?
        var pending: Outcome?
    }

    private let expectation: PartResponseValidator.Expectation
    private let state: Mutex<State>

    init(file: URL, expectation: PartResponseValidator.Expectation) throws {
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: file)
        self.expectation = expectation
        state = Mutex(State(handle: handle))
    }

    func setContinuation(_ continuation: CheckedContinuation<Outcome, Never>) {
        let ready: Outcome? = state.withLock { state in
            if let pending = state.pending { return pending }
            state.continuation = continuation
            return nil
        }
        if let ready { continuation.resume(returning: ready) }
    }

    func head(_ response: HTTPURLResponse) -> Bool {
        let failure = PartResponseValidator.validateHead(
            status: response.statusCode, header: { response.value(forHTTPHeaderField: $0) }, expectation: expectation)
        state.withLock { $0.headFailure = failure }
        return failure == nil
    }

    func body(_ data: Data) {
        state.withLock { state in
            guard state.headFailure == nil, !state.writeFailed, let handle = state.handle else { return }
            // Never keep more than the part's length, whatever the peer sends.
            guard state.received + Int64(data.count) <= expectation.length else {
                state.headFailure = .bodyLengthMismatch(
                    expected: expectation.length, received: state.received + Int64(data.count))
                return
            }
            do {
                try handle.write(contentsOf: data)
                state.hasher.update(data: data)
                state.received += Int64(data.count)
            } catch {
                state.writeFailed = true
            }
        }
    }

    func complete(error: (any Error)?, pinMismatch: Bool) {
        let (continuation, outcome): (CheckedContinuation<Outcome, Never>?, Outcome) = state.withLock { state in
            try? state.handle?.close()
            state.handle = nil
            let outcome: Outcome
            if let failure = state.headFailure {
                outcome = .failure(failure)
            } else if pinMismatch {
                outcome = .failure(.sourceIdentityChanged)
            } else if let error {
                let nsError = error as NSError
                outcome = .failure(.transport("\(nsError.domain) \(nsError.code)"))
            } else if state.writeFailed {
                outcome = .failure(.transport("local write failed"))
            } else {
                outcome = .complete(received: state.received, sha256: Hex.encode(state.hasher.finalize()))
            }
            let continuation = state.continuation
            state.continuation = nil
            if continuation == nil { state.pending = outcome }
            return (continuation, outcome)
        }
        continuation?.resume(returning: outcome)
    }
}
