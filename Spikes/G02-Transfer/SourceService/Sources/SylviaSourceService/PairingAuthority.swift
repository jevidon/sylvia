import CryptoKit
import Foundation
import Synchronization
import SylviaTransferCore

/// What the Mac user sees when a phone asks to pair (plan 15.2: display the device identity on both
/// ends, with the fingerprint grouped in fours).
public struct PairingApprovalRequest: Sendable, Equatable {
    public let deviceID: String
    public let deviceName: String
    public let remoteAddress: String
    /// The Mac's own SPKI fingerprint, which the phone also displays, for comparison.
    public let sourceFingerprint: String
}

/// Decides whether a pairing request is approved. The CLI asks on the terminal; tests drive it.
public protocol PairingApprover: Sendable {
    func approve(_ request: PairingApprovalRequest) async -> Bool
}

/// An approver backed by a closure.
public struct ClosureApprover: PairingApprover {
    let decide: @Sendable (PairingApprovalRequest) async -> Bool
    public init(_ decide: @escaping @Sendable (PairingApprovalRequest) async -> Bool) { self.decide = decide }
    public func approve(_ request: PairingApprovalRequest) async -> Bool { await decide(request) }
}

/// A paired phone as the Mac records it. Only the SHA-256 of the token is stored.
public struct PairedDevice: Codable, Hashable, Sendable {
    public var deviceID: String
    public var deviceName: String
    public var tokenSHA256: String
    public var scopes: [Scope]
    public var pairedAt: Date
    public var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case tokenSHA256 = "token_sha256"
        case scopes
        case pairedAt = "paired_at"
        case revokedAt = "revoked_at"
    }

    public var isActive: Bool { revokedAt == nil }
}

/// Pairing outcomes that map to HTTP errors (ADR-0008).
public enum PairingFailure: Error, Equatable, Sendable {
    case invitationInvalid       // unknown invitation or wrong secret
    case invitationExpired
    case invitationUsed
    case sourceMismatch
    case denied
    case approvalTimeout
    case rateLimited(retryAfterSeconds: Int)
    case invalidRequest
    case storageFailure
}

/// Issues single-use invitations, exchanges them for scoped per-device tokens after the Mac user
/// approves, authenticates bearer tokens, and revokes devices.
///
/// Controls (plan 15.2, ADR-0008):
/// - invitation secret: 32 random bytes; only its SHA-256 is kept, compared in constant time;
/// - single use: the invitation is consumed when a request with the right secret arrives, before the
///   approval prompt, so a concurrent or later request with the same invitation fails whatever the
///   user decides;
/// - expiry (default 10 minutes) checked on the Mac's clock;
/// - attempt limit: after `maxFailedAttempts` wrong secrets the invitation is burned;
/// - rate limit: at most `rateLimit.count` pairing requests per remote address per window;
/// - approval: the Mac user approves the named device; no answer within the timeout is a denial;
/// - tokens: 32 random bytes, scoped to catalog/read/download/receipt, stored as SHA-256 only;
/// - revocation is immediate and persisted; a revoked device must pair again.
public actor PairingAuthority {
    public struct Limits: Sendable {
        public var invitationLifetime: TimeInterval = 600
        public var maxFailedAttempts = 5
        public var rateLimitCount = 10
        public var rateLimitWindow: TimeInterval = 60
        public var approvalTimeout: Duration = .seconds(120)
        public init() {}
    }

    private enum InvitationState: Equatable {
        case open
        case consumed
    }

    private struct Invitation {
        var secretSHA256: [UInt8]
        var expiresAt: Date
        var failedAttempts: Int
        var state: InvitationState
    }

    private let sourceID: String
    private let sourceFingerprint: String
    private let pinHex: String
    private let limits: Limits
    private let approver: any PairingApprover
    private let now: @Sendable () -> Date
    private let devicesURL: URL?
    private var invitations: [String: Invitation] = [:]
    private var devices: [String: PairedDevice] = [:]
    private var requestTimes: [String: [Date]] = [:]

    public init(
        sourceID: String, pin: SPKIPin, limits: Limits, approver: any PairingApprover, devicesURL: URL?,
        now: @escaping @Sendable () -> Date
    ) throws {
        self.sourceID = sourceID
        sourceFingerprint = pin.displayFingerprint
        pinHex = pin.hex
        self.limits = limits
        self.approver = approver
        self.devicesURL = devicesURL
        self.now = now
        if let devicesURL, let stored = try DurableFile.read([PairedDevice].self, from: devicesURL) {
            devices = Dictionary(uniqueKeysWithValues: stored.map { ($0.deviceID, $0) })
        }
    }

    /// Creates a single-use invitation. The secret appears only in the returned payload.
    public func issueInvitation(sourceName: String, endpoints: [PairingPayload.Endpoint], spki: SPKIPin) -> PairingPayload {
        let invitationID = CanonicalID.make()
        let secret = secureRandomBytes(count: 32)
        // Whole seconds, so the expiry in the payload (RFC 3339, whole seconds) is exactly the Mac's.
        let expiresAt = Date(timeIntervalSince1970: now().addingTimeInterval(limits.invitationLifetime).timeIntervalSince1970.rounded(.down))
        invitations[invitationID] = Invitation(
            secretSHA256: Array(SHA256.hash(data: secret)), expiresAt: expiresAt, failedAttempts: 0, state: .open)
        return PairingPayload(
            sourceID: sourceID, sourceName: sourceName, endpoints: endpoints, spki: spki, invitationID: invitationID,
            invitationSecret: secret, expiresAt: expiresAt)
    }

    public func pair(_ request: PairRequest, remoteAddress: String) async throws(PairingFailure) -> PairResponse {
        try checkRateLimit(remoteAddress)
        guard request.schemaVersion == 1, CanonicalID.isValid(request.invitationID), CanonicalID.isValid(request.deviceID),
            !request.deviceName.isEmpty, request.deviceName.unicodeScalars.count <= 64,
            !request.deviceName.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw .invalidRequest }
        guard var invitation = invitations[request.invitationID] else { throw .invitationInvalid }
        // The secret is checked before any state is revealed.
        let presented = Base64URL.decode(request.invitationSecret) ?? []
        guard constantTimeEquals(Array(SHA256.hash(data: presented)), invitation.secretSHA256) else {
            invitation.failedAttempts += 1
            if invitation.failedAttempts >= limits.maxFailedAttempts {
                invitations.removeValue(forKey: request.invitationID)
            } else {
                invitations[request.invitationID] = invitation
            }
            throw .invitationInvalid
        }
        guard invitation.state == .open else { throw .invitationUsed }
        guard now() < invitation.expiresAt else {
            invitations.removeValue(forKey: request.invitationID)
            throw .invitationExpired
        }
        guard request.sourceID == sourceID else { throw .sourceMismatch }
        // Consume before asking, so the invitation is single-use whatever happens next.
        invitation.state = .consumed
        invitations[request.invitationID] = invitation

        let approval = PairingApprovalRequest(
            deviceID: request.deviceID, deviceName: request.deviceName, remoteAddress: remoteAddress,
            sourceFingerprint: sourceFingerprint)
        let approved = await decide(approval)
        switch approved {
        case .none: throw .approvalTimeout
        case .some(false): throw .denied
        case .some(true): break
        }
        let token = Base64URL.encode(secureRandomBytes(count: 32))
        let device = PairedDevice(
            deviceID: request.deviceID, deviceName: request.deviceName, tokenSHA256: SHA256Hex.digest(Data(token.utf8)),
            scopes: TransferProtocol.allScopes, pairedAt: now(), revokedAt: nil)
        devices[request.deviceID] = device
        do {
            try persistDevices()
        } catch {
            // Never hand out a token the Mac could forget it issued.
            devices.removeValue(forKey: request.deviceID)
            throw .storageFailure
        }
        return PairResponse(
            sourceID: sourceID, deviceID: request.deviceID, token: token, scopes: device.scopes, spkiSHA256: pinHex,
            pairedAt: device.pairedAt)
    }

    /// Returns the active device for a bearer token, or nil.
    public func authenticate(token: String) -> PairedDevice? {
        guard let bytes = Base64URL.decode(token), bytes.count == 32 else { return nil }
        let digest = SHA256Hex.digest(Data(token.utf8))
        return devices.values.first { device in
            device.isActive && constantTimeEquals(Array(device.tokenSHA256.utf8), Array(digest.utf8))
        }
    }

    /// Revokes a device. Future requests with its token get 401. Already imported files are unaffected.
    /// Throws if the revocation could not be persisted; it still applies in memory until restart.
    @discardableResult
    public func revoke(deviceID: String) throws -> Bool {
        guard var device = devices[deviceID], device.isActive else { return false }
        device.revokedAt = now()
        devices[deviceID] = device
        try persistDevices()
        return true
    }

    public func pairedDevices() -> [PairedDevice] { devices.values.sorted { $0.pairedAt < $1.pairedAt } }

    /// After an identity reset every token is void: phones must pair again with the new key.
    public func revokeAll() throws {
        for id in devices.keys where devices[id]?.isActive == true { devices[id]?.revokedAt = now() }
        try persistDevices()
    }

    /// Asks the approver, but answers nil after the approval timeout even if the approver never returns
    /// (a terminal prompt nobody answers cannot be cancelled). A late answer is ignored.
    private func decide(_ approval: PairingApprovalRequest) async -> Bool? {
        let approver = self.approver
        let timeout = limits.approvalTimeout
        let slot = DecisionSlot()
        return await withCheckedContinuation { continuation in
            slot.set(continuation)
            let asking = Task {
                let answer = await approver.approve(approval)
                slot.resume(answer)
            }
            Task {
                try? await Task.sleep(for: timeout)
                if slot.resume(nil) { asking.cancel() }
            }
        }
    }

    private func checkRateLimit(_ remoteAddress: String) throws(PairingFailure) {
        let current = now()
        let windowStart = current.addingTimeInterval(-limits.rateLimitWindow)
        // Forget addresses with no request inside the window, so the table cannot grow without bound.
        if requestTimes.count > 256 {
            requestTimes = requestTimes.filter { $0.value.contains { $0 > windowStart } }
        }
        var times = (requestTimes[remoteAddress] ?? []).filter { $0 > windowStart }
        guard times.count < limits.rateLimitCount else {
            let oldest = times.min() ?? current
            let retry = max(1, Int((oldest.addingTimeInterval(limits.rateLimitWindow).timeIntervalSince(current)).rounded(.up)))
            requestTimes[remoteAddress] = times
            throw .rateLimited(retryAfterSeconds: retry)
        }
        times.append(current)
        requestTimes[remoteAddress] = times
    }

    private func persistDevices() throws {
        guard let devicesURL else { return }
        try DurableFile.write(pairedDevices(), to: devicesURL)
    }
}

/// Holds the continuation of one approval decision; only the first answer resumes it.
private final class DecisionSlot: Sendable {
    private let continuation = Mutex<CheckedContinuation<Bool?, Never>?>(nil)

    func set(_ value: CheckedContinuation<Bool?, Never>) { continuation.withLock { $0 = value } }

    @discardableResult
    func resume(_ answer: Bool?) -> Bool {
        let taken = continuation.withLock { stored -> CheckedContinuation<Bool?, Never>? in
            defer { stored = nil }
            return stored
        }
        taken?.resume(returning: answer)
        return taken != nil
    }
}
