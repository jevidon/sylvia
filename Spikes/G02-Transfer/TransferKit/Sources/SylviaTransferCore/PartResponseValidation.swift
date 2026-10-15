import CryptoKit
import Foundation

/// Why a part request did not produce verified bytes, and what the client does next.
/// Plan 15.4: "Accept only a correct 206, matching Content-Range and expected length/digest. A 200
/// for a partial request, 412, 416, changed ETag, unexpected encoding or changed manifest
/// pauses/restarts explicitly; never append it to a previous partial file."
public enum PartFailure: Error, Equatable, Hashable, Sendable {
    case rangeIgnored                       // 200 to a range request
    case preconditionFailed                 // 412: the asset version changed
    case rangeNotSatisfiable                // 416
    case contentRangeMismatch               // 206 for different bytes than requested
    case contentLengthMismatch
    case missingContentLength
    case etagChanged                        // 206 for a different version
    case unexpectedContentEncoding
    case unauthorized                       // 401: token unknown, expired or revoked
    case forbidden                          // 403
    case notFound                           // 404
    case rateLimited                        // 429
    case serverError(Int)                   // 5xx
    case unexpectedStatus(Int)
    case bodyLengthMismatch(expected: Int64, received: Int64)
    case digestMismatch
    case transport(String)                  // connection lost, timeout, truncated body
    case sourceIdentityChanged              // TLS pin mismatch
    /// This device's storage is full (ENOSPC) while keeping a part: not the Mac's fault, and fetching
    /// the part again cannot help until space is freed (plan 15.4, 15.5).
    case localStorageFull
    /// Writing a part to this device's storage failed for another reason (an I/O error, not the network).
    case localWriteFailed(String)

    public var recovery: Recovery {
        switch self {
        case .localStorageFull:
            .pause(.insufficientSpace)
        case .preconditionFailed, .rangeNotSatisfiable, .etagChanged:
            .refreshManifest
        case .unauthorized:
            .pause(.reauthenticationRequired)
        case .forbidden:
            .pause(.accessRevoked)
        case .sourceIdentityChanged:
            .pause(.sourceIdentityChanged)
        case .notFound:
            .refreshManifest
        case .rangeIgnored, .contentRangeMismatch, .contentLengthMismatch, .missingContentLength,
            .unexpectedContentEncoding, .bodyLengthMismatch, .digestMismatch, .rateLimited, .serverError,
            .unexpectedStatus, .transport, .localWriteFailed:
            .retryPart
        }
    }

    /// Why a job pauses once a part has failed `maxAttemptsPerPart` times: the network, this device's
    /// storage, or the part itself. Each reason has its own next step.
    public var exhaustedRetriesReason: PauseReason {
        switch self {
        case .transport: .sourceUnreachable
        case .localWriteFailed: .storageUnavailable
        default: .repeatedPartFailure
        }
    }

    public enum Recovery: Equatable, Hashable, Sendable {
        /// Discard the received bytes of this part only and request it again.
        case retryPart
        /// The version may have changed: fetch the manifest again and reconcile parts by digest.
        case refreshManifest
        /// Stop the job, keep every verified part, and show the reason.
        case pause(PauseReason)
    }
}

public enum PauseReason: String, Equatable, Hashable, Sendable, Codable {
    case reauthenticationRequired = "reauthentication_required"
    case accessRevoked = "access_revoked"
    case sourceIdentityChanged = "source_identity_changed"
    case sourceUnreachable = "source_unreachable"
    case sourcePreparing = "source_preparing"
    case repeatedPartFailure = "repeated_part_failure"
    case itemRemoved = "item_removed"
    case manifestInvalid = "manifest_invalid"
    case finalDigestMismatch = "final_digest_mismatch"
    case insufficientSpace = "insufficient_space"
    /// Parts could not be written to this device's storage (an I/O error other than a full disk).
    case storageUnavailable = "storage_unavailable"
    /// The Keychain refused to read the token (errSecInteractionNotAllowed) while the job store was
    /// readable. Defensive: before the first unlock the job store itself is unreadable and the client
    /// defers its whole launch instead (ADR-0008). Nothing is downgraded or erased.
    case deviceLocked = "device_locked"
    /// iOS local network privacy refuses connections to the Mac for this app (review finding R2-03).
    case localNetworkDenied = "local_network_denied"
    case cancelled

    /// Next step shown to the person (plan 15.5: "a resumable state and clear next step").
    public var nextStep: String {
        switch self {
        case .reauthenticationRequired: "Pair this iPhone with the Mac again. Verified parts are kept."
        case .accessRevoked: "This iPhone's access was removed on the Mac. Pair again to continue."
        case .sourceIdentityChanged: "The Mac's identity changed. Pair again and compare the fingerprint."
        case .sourceUnreachable: "Make sure the Mac is awake, running Sylvia and reachable, then resume."
        case .sourcePreparing: "The Mac is still preparing this item. Resume later; nothing was lost."
        case .repeatedPartFailure: "The same part failed several times. Resume to try again."
        case .itemRemoved: "The item is no longer shared by the Mac."
        case .manifestInvalid: "The Mac described the file inconsistently. Update Sylvia on the Mac."
        case .finalDigestMismatch: "The finished file did not match the Mac's checksum. Resume to download it again."
        case .insufficientSpace: "Free up space on this iPhone, then resume. Verified parts are kept."
        case .storageUnavailable: "Sylvia could not save parts on this iPhone. Restart Sylvia, then resume. Verified parts are kept."
        case .deviceLocked: "Unlock this iPhone to continue. Verified parts are kept."
        case .localNetworkDenied:
            "Turn on Local Network for Sylvia in Settings > Privacy & Security > Local Network, then resume. Verified parts are kept."
        case .cancelled: "Resume when ready. Verified parts are kept."
        }
    }
}

/// Header checks for one part response, done before any body byte is kept (plan 15.4).
public enum PartResponseValidator {
    public struct Expectation: Sendable, Hashable {
        public var offset: Int64
        public var length: Int64
        public var assetLength: Int64
        public var etag: String

        public init(part: TransferManifest.Part, asset: TransferManifest.Asset) {
            offset = part.offset
            length = part.length
            assetLength = asset.length
            etag = asset.etag
        }

        public var rangeHeader: String { "bytes=\(offset)-\(offset + length - 1)" }
    }

    /// `header` looks a header up case-insensitively and returns its value.
    public static func validateHead(
        status: Int, header: (String) -> String?, expectation: Expectation
    ) -> PartFailure? {
        switch status {
        case 206: break
        case 200: return .rangeIgnored
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 412: return .preconditionFailed
        case 416: return .rangeNotSatisfiable
        case 429: return .rateLimited
        case 500...599: return .serverError(status)
        default: return .unexpectedStatus(status)
        }
        if let encoding = header("Content-Encoding"), encoding.lowercased() != "identity" {
            return .unexpectedContentEncoding
        }
        if let transferEncoding = header("Transfer-Encoding"), transferEncoding.lowercased() != "identity" {
            // Chunked framing would hide a short body behind a 206; the protocol requires Content-Length.
            return .missingContentLength
        }
        guard let etag = header("ETag"), ETag.strongMatch(etag, expectation.etag) else { return .etagChanged }
        guard let rangeText = header("Content-Range"), let range = ContentRange.parse(rangeText),
            range.length == expectation.assetLength, range.range.lowerBound == expectation.offset,
            range.range.upperBound == expectation.offset + expectation.length - 1
        else { return .contentRangeMismatch }
        guard let lengthText = header("Content-Length") else { return .missingContentLength }
        guard let length = Int64(lengthText), length == expectation.length else { return .contentLengthMismatch }
        return nil
    }

    /// Body checks after the bytes were written to the part's temporary file.
    public static func validateBody(receivedBytes: Int64, sha256Hex: String, part: TransferManifest.Part) -> PartFailure? {
        guard receivedBytes == part.length else {
            return .bodyLengthMismatch(expected: part.length, received: receivedBytes)
        }
        guard constantTimeEquals(Array(sha256Hex.utf8), Array(part.sha256.utf8)) else { return .digestMismatch }
        return nil
    }
}
