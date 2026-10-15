import Foundation
import SylviaTransferCore

/// Classified client failures (plan 14.3: DNS, permission denied, host unreachable, TLS/pin
/// mismatch, authentication, rate limit, invalid response). Descriptions never include secrets.
public enum ClientError: Error, Equatable, Sendable {
    /// The peer's key does not match the pinned key. Nothing was sent. Requires re-pairing.
    case pinMismatch
    case dnsFailure
    case unreachable
    case tlsFailure
    case timedOut
    case cancelled
    case transport(code: Int)
    /// A non-2xx response with the server's error code (from ErrorBody) when present.
    case http(status: Int, code: String?)
    case invalidResponse(String)
    case invalidManifest(ManifestError)
    case invalidPayload(PairingPayloadError)
    case unsupportedProtocol(major: Int)
    case notPaired
    /// iOS local network privacy refuses connections to the Mac for this app (found by `LocalNetworkProbe`
    /// after a network failure; never produced by a request alone). Next step: Settings > Privacy & Security
    /// > Local Network.
    case localNetworkDenied

    static func from(transportError error: any Error, pinMismatch: Bool) -> ClientError {
        if pinMismatch { return .pinMismatch }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return .transport(code: nsError.code) }
        switch nsError.code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .dnsFailure
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
            // A denied iOS local-network permission also lands here. URLSession does not say which; callers
            // that can tell the person what to do run `classifyingLocalNetwork(endpoints:)` (LocalNetworkProbe.swift),
            // which reads the network path's unsatisfied reason (review finding R2-03).
            return .unreachable
        case NSURLErrorTimedOut: return .timedOut
        case NSURLErrorCancelled: return .cancelled
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected:
            return .tlsFailure
        default: return .transport(code: nsError.code)
        }
    }

    /// Whether the failure means the stored pairing can no longer be used.
    public var requiresRepairing: Bool {
        switch self {
        case .pinMismatch: true
        case .http(let status, _): status == 401
        default: false
        }
    }
}
