import Foundation
import Synchronization

/// A URLProtocol that fails requests for registered hosts with a chosen URLError, for failure classes that
/// cannot be produced deterministically on loopback (DNS failure, untrusted certificate, offline).
/// Requests to unregistered hosts are not intercepted.
public final class StubURLProtocol: URLProtocol {
    private static let failures = Mutex<[String: URLError.Code]>([:])
    private static let seen = Mutex<[String]>([])

    public static func fail(host: String, with code: URLError.Code) {
        failures.withLock { $0[host.lowercased()] = code }
    }

    public static func reset() {
        failures.withLock { $0.removeAll() }
        seen.withLock { $0.removeAll() }
    }

    /// Hosts of intercepted requests, in order.
    public static var interceptedHosts: [String] { seen.withLock { $0 } }

    override public class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host()?.lowercased() else { return false }
        return failures.withLock { $0[host] != nil }
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        let host = request.url?.host()?.lowercased() ?? ""
        Self.seen.withLock { $0.append(host) }
        let code = Self.failures.withLock { $0[host] } ?? .unknown
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }

    override public func stopLoading() {}
}
