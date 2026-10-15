import Foundation

/// The single-use invitation the Mac shows and the phone reads through a user-mediated channel
/// (copyable code, link, or QR). It carries the trust anchor, so the phone can pin the source's key
/// before it sends the secret (plan 15.2, ADR-0008).
///
/// Text forms:
///   code: `SYLVIA1-<base64url(JSON)>`
///   link: `sylvia://pair/v1#<base64url(JSON)>` (the payload is in the fragment, never a query)
public struct PairingPayload: Codable, Hashable, Sendable {
    public struct Endpoint: Codable, Hashable, Sendable {
        public var host: String
        public var port: Int
        public init(host: String, port: Int) {
            self.host = host
            self.port = port
        }

        /// Host as it appears in a URL authority (IPv6 literals in brackets).
        public var urlHost: String { host.contains(":") ? "[\(host)]" : host }

        public func baseURL() -> URL? { URL(string: "https://\(urlHost):\(port)") }
    }

    public var schemaVersion: Int
    public var protocolVersion: ProtocolVersion
    public var sourceID: String
    public var sourceName: String
    public var endpoints: [Endpoint]
    public var spkiSHA256: String
    public var invitationID: String
    public var invitationSecret: String
    public var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case protocolVersion = "protocol_version"
        case sourceID = "source_id"
        case sourceName = "source_name"
        case endpoints
        case spkiSHA256 = "spki_sha256"
        case invitationID = "invitation_id"
        case invitationSecret = "invitation_secret"
        case expiresAt = "expires_at"
    }

    public static let codePrefix = "SYLVIA1-"
    public static let linkPrefix = "sylvia://pair/v1#"
    public static let minimumSecretBytes = 16
    public static let maximumEndpoints = 8
    public static let maximumSourceNameLength = 64
    /// Upper bound on the encoded payload, so a pasted blob cannot exhaust memory.
    public static let maximumEncodedLength = 4_096

    public init(
        sourceID: String, sourceName: String, endpoints: [Endpoint], spki: SPKIPin, invitationID: String,
        invitationSecret: [UInt8], expiresAt: Date
    ) {
        schemaVersion = 1
        protocolVersion = TransferProtocol.version
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.endpoints = endpoints
        spkiSHA256 = spki.hex
        self.invitationID = invitationID
        self.invitationSecret = Base64URL.encode(invitationSecret)
        self.expiresAt = expiresAt
    }

    public var pin: SPKIPin {
        get throws { try SPKIPin(hex: spkiSHA256) }
    }

    public func code() throws -> String {
        PairingPayload.codePrefix + Base64URL.encode(try TransferJSON.encode(self))
    }

    public func link() throws -> String {
        PairingPayload.linkPrefix + Base64URL.encode(try TransferJSON.encode(self))
    }

    /// Decodes a code or link and validates it. Expiry is checked against `now`.
    public static func decode(_ text: String, now: Date) throws(PairingPayloadError) -> PairingPayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maximumEncodedLength else { throw .tooLong }
        let body: Substring
        if trimmed.hasPrefix(codePrefix) {
            body = trimmed.dropFirst(codePrefix.count)
        } else if trimmed.hasPrefix(linkPrefix) {
            body = trimmed.dropFirst(linkPrefix.count)
        } else {
            throw .unrecognizedFormat
        }
        guard let json = Base64URL.decode(String(body)) else { throw .malformed }
        let payload: PairingPayload
        do {
            payload = try TransferJSON.decode(PairingPayload.self, from: Data(json))
        } catch {
            throw .malformed
        }
        try payload.validate(now: now)
        return payload
    }

    public func validate(now: Date) throws(PairingPayloadError) {
        guard schemaVersion == 1 else { throw .unsupportedSchemaVersion }
        guard protocolVersion.major == TransferProtocol.major else { throw .unsupportedProtocolVersion }
        guard CanonicalID.isValid(sourceID), CanonicalID.isValid(invitationID) else { throw .invalidIdentifier }
        guard !sourceName.isEmpty, sourceName.unicodeScalars.count <= PairingPayload.maximumSourceNameLength,
            !sourceName.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw .invalidSourceName }
        guard !endpoints.isEmpty, endpoints.count <= PairingPayload.maximumEndpoints else { throw .invalidEndpoints }
        for endpoint in endpoints {
            guard (1...65_535).contains(endpoint.port), HostValidation.isValid(endpoint.host) else {
                throw .invalidEndpoints
            }
        }
        guard Hex.isSHA256(spkiSHA256) else { throw .invalidPin }
        guard let secret = Base64URL.decode(invitationSecret), secret.count >= PairingPayload.minimumSecretBytes,
            secret.count <= 64
        else { throw .weakSecret }
        guard expiresAt > now else { throw .expired }
    }
}

public enum PairingPayloadError: Error, Equatable, Sendable {
    case tooLong
    case unrecognizedFormat
    case malformed
    case unsupportedSchemaVersion
    case unsupportedProtocolVersion
    case invalidIdentifier
    case invalidSourceName
    case invalidEndpoints
    case invalidPin
    case weakSecret
    case expired
}

/// Accepts DNS host names (RFC 1123 labels), IPv4 dotted quads and IPv6 literals without brackets.
public enum HostValidation {
    public static func isValid(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        if host.contains(":") { return isIPv6(host) }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return isIPv4(host) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard (1...63).contains(label.utf8.count), label.first != "-", label.last != "-" else { return false }
            return label.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                    || scalar == "-"
            }
        }
    }

    public static func isIPv4(_ host: String) -> Bool {
        var address = in_addr()
        return inet_pton(AF_INET, host, &address) == 1
    }

    public static func isIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        return inet_pton(AF_INET6, host, &address) == 1
    }
}
