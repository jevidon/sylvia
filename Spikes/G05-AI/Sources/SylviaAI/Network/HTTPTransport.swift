import Foundation
import Synchronization

public struct HTTPRequestSpec: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data
    public var timeout: TimeInterval

    public init(url: URL, method: String = "POST", headers: [String: String], body: Data, timeout: TimeInterval = 60) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPStreamResponse: Sendable {
    public var status: Int
    /// Header names lowercased.
    public var headers: [String: String]
    public var body: AsyncThrowingStream<Data, any Error>

    public init(status: Int, headers: [String: String], body: AsyncThrowingStream<Data, any Error>) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// How a bounded body read ended.
    public enum BodyEnd: Sendable, Equatable {
        case complete
        /// More than `limit` bytes arrived; the data holds the first `limit`.
        case sizeLimit
        /// Bytes were still arriving at the deadline (a server can trickle a body without ever going idle long
        /// enough for URLRequest's idle timeout).
        case timeLimit
    }

    /// Reads the body up to `limit` bytes and until `deadline` (plan 14.5: bounded jobs). A transport failure
    /// mid-body ends the read with what arrived.
    /// The deadline is enforced by a timer as well as on each chunk, because URLSession may hold back a slowly
    /// arriving body (content sniffing waits for the first 512 bytes), so no chunk may arrive to check it against.
    public func readBody(limit: Int, deadline: ContinuousClock.Instant) async -> (data: Data, end: BodyEnd) {
        let body = body
        return await withTaskGroup(of: (data: Data, end: BodyEnd)?.self) { group in
            group.addTask { await Self.read(body, limit: limit, deadline: deadline) }
            group.addTask {
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return nil }
                return (Data(), .timeLimit)
            }
            while let next = await group.next() {
                if let result = next {
                    group.cancelAll()
                    return result
                }
            }
            return (Data(), .complete)
        }
    }

    static func read(_ body: AsyncThrowingStream<Data, any Error>, limit: Int,
                     deadline: ContinuousClock.Instant) async -> (data: Data, end: BodyEnd) {
        var data = Data()
        var received = 0
        do {
            for try await chunk in body {
                received += chunk.count
                data.append(chunk.prefix(max(0, limit - data.count)))
                if received > limit { return (data, .sizeLimit) }
                if ContinuousClock.now > deadline { return (data, .timeLimit) }
            }
        } catch {}
        return (data, .complete)
    }

    /// Reads at most `limit` bytes of an error body, for at most `maxDuration`; whatever arrived is returned.
    public func collectBody(limit: Int = 65_536, maxDuration: Duration = .seconds(30)) async -> Data {
        await readBody(limit: limit, deadline: .now + maxDuration).data
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequestSpec) async throws -> HTTPStreamResponse
}

/// URLSession transport for AI endpoints.
///
/// - Ephemeral session: no cookies, no URL cache, no credential storage; credentials travel only in the
///   request headers the adapter sets for this one origin.
/// - Redirects to a different origin (scheme, host or port) are blocked: the redirect is not followed, so the
///   body and the credential header are never sent to the new origin, and a local endpoint's cleartext
///   exception never extends to a remote host. The caller receives `redirectBlocked`.
/// - Normal system TLS evaluation; there is no trust override of any kind.
public final class URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(protocolClasses: [AnyClass] = []) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        }
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ spec: HTTPRequestSpec) async throws -> HTTPStreamResponse {
        var request = URLRequest(url: spec.url)
        request.httpMethod = spec.method
        request.timeoutInterval = spec.timeout
        request.httpShouldHandleCookies = false
        for (name, value) in spec.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = spec.body.isEmpty ? nil : spec.body

        guard let origin = Origin(spec.url) else { throw URLError(.badURL) }
        let guardDelegate = RedirectGuard(origin: origin)
        let (bytes, response) = try await session.bytes(for: request, delegate: guardDelegate)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if let target = guardDelegate.blockedTarget {
            bytes.task.cancel()
            throw ProviderError(kind: .redirectBlocked, acceptance: .rejected, host: origin.host,
                                httpStatus: http.statusCode, detail: target)
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
        }
        let stream = AsyncThrowingStream<Data, any Error> { continuation in
            let reader = Task {
                var buffer = Data()
                buffer.reserveCapacity(4096)
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 0x0A || buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
        return HTTPStreamResponse(status: http.statusCode, headers: headers, body: stream)
    }
}

/// Blocks cross-origin redirects and records where the server tried to send the request.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    let origin: Origin
    private let blocked = Mutex<String?>(nil)

    init(origin: Origin) { self.origin = origin }

    var blockedTarget: String? { blocked.withLock { $0 } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, let target = Origin(url), target == origin else {
            let description = request.url.flatMap(Origin.init)?.description ?? "an invalid address"
            blocked.withLock { $0 = description }
            return nil
        }
        return request
    }
}
