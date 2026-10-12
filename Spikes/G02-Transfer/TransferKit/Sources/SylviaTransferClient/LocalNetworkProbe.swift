import Foundation
import Network
import Synchronization
import SylviaTransferCore

/// Tells a denied local network permission apart from an unreachable Mac (plan 14.3 "permission denied",
/// 15.5 "a clear next step"; review finding R2-03).
///
/// URLSession reports a connection that iOS local network privacy blocked like any other failed connection
/// (for example "not connected to the internet" or "cannot connect to host"). Network framework exposes the
/// reason: a connection the system refuses for that reason waits with a path whose `unsatisfiedReason` is
/// `.localNetworkDenied` (Apple TN3179, "Understanding local network privacy"). After a request failed, the
/// client opens a plain TCP connection to the same address (no TLS, nothing is sent; it is closed at once)
/// and reads that reason.
///
/// Environment: the denial itself happens only on a device (the simulator and the Mac's command-line tools
/// are not subject to it), so the `.denied` branch is a device checklist step (steps 4 and 18). Host tests
/// cover the other answers and the classification around it.
public enum LocalNetworkProbe {
    public enum Result: String, Sendable, Equatable {
        /// The system refuses connections to this address because the local network is denied to the app.
        case denied
        /// The connection was made, or failed for another reason (refused, unreachable): not a permission problem.
        case notDenied
        /// No answer in time.
        case unknown
    }

    public static func check(_ endpoint: PairingPayload.Endpoint, timeout: Duration = .seconds(5)) async -> Result {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: endpoint.port)), endpoint.port > 0 else { return .unknown }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let once = Once()
        let queue = DispatchQueue(label: "SylviaTransferClient.LocalNetworkProbe")
        let result: Result = await withCheckedContinuation { continuation in
            @Sendable func finish(_ result: Result) {
                if once.claim() { continuation.resume(returning: result) }
            }
            @Sendable func denied(_ path: NWPath?) -> Bool { path?.unsatisfiedReason == .localNetworkDenied }
            connection.pathUpdateHandler = { path in
                if denied(path) { finish(.denied) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.notDenied)
                case .waiting, .failed: finish(denied(connection.currentPath) ? .denied : .notDenied)
                case .cancelled: finish(.unknown)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout.components.seconds * 1000))) { finish(.unknown) }
        }
        connection.cancel()
        return result
    }

    /// Whether any of `endpoints` is refused because the local network is denied (checked in order; stops at
    /// the first denial).
    public static func anyDenied(_ endpoints: [PairingPayload.Endpoint]) async -> Bool {
        for endpoint in endpoints where await check(endpoint) == .denied { return true }
        return false
    }

    final class Once: Sendable {
        private let done = Mutex(false)
        func claim() -> Bool { done.withLock { was in defer { was = true }; return !was } }
    }
}

extension ClientError {
    /// A failure that a denied local network permission would also produce (the request never left the
    /// phone, or name resolution of a `.local` name was refused).
    public var mayBeLocalNetworkDenial: Bool {
        switch self {
        case .unreachable, .dnsFailure, .timedOut, .transport: true
        default: false
        }
    }

    /// `.localNetworkDenied` when the error could be a denial and `isDenied` says the endpoints are refused for
    /// that reason; otherwise the error unchanged. `isDenied` defaults to `LocalNetworkProbe.anyDenied`.
    public func classifyingLocalNetwork(
        endpoints: [PairingPayload.Endpoint],
        isDenied: (@Sendable ([PairingPayload.Endpoint]) async -> Bool)? = nil
    ) async -> ClientError {
        guard mayBeLocalNetworkDenial, !endpoints.isEmpty else { return self }
        let denied = await (isDenied ?? LocalNetworkProbe.anyDenied)(endpoints)
        return denied ? .localNetworkDenied : self
    }
}
