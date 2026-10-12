import Foundation
import Synchronization
import SylviaTransferCore

/// Deterministic faults for the host fault tests (T38-T41). Exposed only through `@_spi(Testing)`;
/// the command-line source never installs a plan, so a production build serves without faults.
@_spi(Testing)
public enum ContentFault: Sendable, Equatable {
    /// Answer a range request with 200 and the whole asset.
    case ignoreRange
    /// Answer 412 although the version is current.
    case preconditionFailed
    /// Answer 416 although the range is satisfiable.
    case rangeNotSatisfiable
    /// Flip one byte at this offset within the response body.
    case corruptByte(at: Int64)
    /// Send the correct head, then close the connection after this many body bytes.
    case dropAfter(bytes: Int64)
    /// Send a different strong ETag on an otherwise correct 206.
    case wrongETag
    /// Send a 206 for fewer bytes than requested (consistent Content-Range and Content-Length).
    case shortRange(by: Int64)
    /// Claim `Content-Encoding: gzip` on the 206.
    case gzipEncoding
}

@_spi(Testing)
public struct ContentRequestInfo: Sendable {
    public let assetID: String
    public let range: ClosedRange<Int64>?
    /// 1-based count of content requests for this asset and range start.
    public let attempt: Int
}

@_spi(Testing)
public final class FaultPlan: Sendable {
    public typealias Rule = @Sendable (ContentRequestInfo) -> ContentFault?
    private let rules = Mutex<[Rule]>([])
    private let attempts = Mutex<[String: Int]>([:])
    private let manifestDigestCorruption = Mutex<Bool>(false)
    /// Called while streaming a body, after each chunk, with the asset and bytes sent so far.
    public let bodyProgress = Mutex<(@Sendable (String, Int64, Int64) async -> Void)?>(nil)

    private let closeConnections = Mutex<Bool>(false)

    public init() {}

    public func add(_ rule: @escaping Rule) { rules.withLock { $0.append(rule) } }

    /// Answer every request with `Connection: close`, so each request needs a new TLS handshake (and so a
    /// new server-trust challenge on the phone). Used to observe when a background session asks the app.
    public func setCloseAfterEachResponse(_ value: Bool) { closeConnections.withLock { $0 = value } }
    var closeAfterEachResponse: Bool { closeConnections.withLock { $0 } }

    /// Serve manifests whose asset SHA-256 disagrees with the parts (re-sealed so the manifest itself
    /// is consistent): tests the final full-digest check before handoff.
    public func setCorruptManifestFullDigest(_ value: Bool) { manifestDigestCorruption.withLock { $0 = value } }
    var corruptManifestFullDigest: Bool { manifestDigestCorruption.withLock { $0 } }

    func fault(assetID: String, range: ClosedRange<Int64>?) -> (ContentFault?, Int) {
        let key = "\(assetID)@\(range?.lowerBound ?? -1)"
        let attempt = attempts.withLock { counts in
            counts[key, default: 0] += 1
            return counts[key]!
        }
        let info = ContentRequestInfo(assetID: assetID, range: range, attempt: attempt)
        let fault = rules.withLock { rules in rules.lazy.compactMap { $0(info) }.first }
        return (fault, attempt)
    }
}

/// One line per request for test assertions and evidence. Never holds tokens, secrets or titles.
@_spi(Testing)
public struct LoggedRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    public let range: String?
    public let status: Int
    public let fault: String?
}
