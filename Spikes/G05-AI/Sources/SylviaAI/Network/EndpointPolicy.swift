import Foundation

/// scheme://host[:port], lowercased. Credentials are scoped to exactly one origin (plan 18.1).
public struct Origin: Hashable, Sendable, CustomStringConvertible {
    public let scheme: String
    public let host: String
    public let port: Int

    public init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
    }

    public var description: String {
        let defaultPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return defaultPort ? "\(scheme)://\(hostPart)" : "\(scheme)://\(hostPart):\(port)"
    }
}

public enum EndpointPolicyViolation: Error, Equatable, Sendable {
    case invalidURL
    /// Cleartext HTTP to a host that is not an eligible local address, or without the explicit opt-in.
    case cleartextNotAllowed(host: String, reason: String)
    /// First-party hosted providers are HTTPS only.
    case hostedProviderRequiresHTTPS

    public var userMessage: String {
        switch self {
        case .invalidURL:
            "The endpoint address is not valid."
        case .cleartextNotAllowed(let host, let reason):
            "Sylvia will not send requests to \(host) without encryption: \(reason) Use an https:// address."
        case .hostedProviderRequiresHTTPS:
            "This provider is only reachable over https://."
        }
    }
}

public struct EndpointAssessment: Sendable, Equatable {
    public let origin: Origin
    public let automaticClassification: EndpointClassification
    public let effectiveClassification: EndpointClassification
    public let usesCleartext: Bool
}

/// Network policy for AI endpoints (plan 14.3; ADR-0011).
///
/// Classification (what the user is told):
/// - `hosted`: the first-party hosts of the OpenAI and Anthropic adapters.
/// - `local`: an IP literal in loopback (127.0.0.0/8, ::1), RFC 1918 private (10/8, 172.16/12, 192.168/16),
///   link-local (169.254/16, fe80::/10) or IPv6 unique-local (fc00::/7) space.
/// - `user_managed`: everything else, including `.local` names, Tailscale CGNAT addresses (100.64/10),
///   MagicDNS names and public hosts reached through the generic adapter. Sylvia cannot see who operates them
///   or where they forward requests (plan 14.1 on Hermes, 14.3 on Tailscale).
/// The user may declare a broader class (for example `hosted` for a commercial gateway) but never a narrower one.
///
/// Cleartext HTTP is allowed only when all of these hold:
/// 1. the user switched on "allow unencrypted connection" for this endpoint;
/// 2. the host is an IP literal in the `local` ranges above (a name, including `localhost` and `.local`, is
///    never enough because name resolution can be spoofed or rebound);
/// 3. the adapter is not a first-party hosted provider.
/// Redirects never inherit this exception: cross-origin redirects are blocked outright (URLSessionTransport).
public enum EndpointPolicy {
    public static let firstPartyHostedHosts: Set<String> = ["api.openai.com", "api.anthropic.com"]

    public static func assess(_ config: ProviderConfig) throws(EndpointPolicyViolation) -> EndpointAssessment {
        guard let origin = Origin(config.baseURL) else { throw .invalidURL }
        let automatic = automaticClassification(host: origin.host, kind: config.kind)
        let effective = max(automatic, config.declaredClassification ?? automatic)
        let cleartext = origin.scheme == "http"
        if cleartext {
            if config.kind == .openAIResponses || config.kind == .anthropicMessages || firstPartyHostedHosts.contains(origin.host) {
                throw .hostedProviderRequiresHTTPS
            }
            guard config.allowInsecureLocalHTTP else {
                throw .cleartextNotAllowed(host: origin.host, reason: "unencrypted connections are off for this endpoint.")
            }
            guard isEligibleLocalAddress(origin.host) else {
                throw .cleartextNotAllowed(host: origin.host,
                                           reason: "unencrypted connections are only allowed to a local IP address (for example 192.168.1.20), not to a name or an internet address.")
            }
            guard effective == .local else {
                throw .cleartextNotAllowed(host: origin.host, reason: "this endpoint is declared as \(effective.disclosureWord).")
            }
        } else if origin.scheme != "https" {
            throw .invalidURL
        }
        return EndpointAssessment(origin: origin, automaticClassification: automatic,
                                  effectiveClassification: effective, usesCleartext: cleartext)
    }

    public static func automaticClassification(host: String, kind: ProviderKind) -> EndpointClassification {
        let host = host.lowercased()
        if firstPartyHostedHosts.contains(host) { return .hosted }
        if isEligibleLocalAddress(host) { return .local }
        return .userManaged
    }

    /// True only for IP literals in loopback, private, link-local or unique-local ranges.
    public static func isEligibleLocalAddress(_ host: String) -> Bool {
        var host = host
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if let v4 = parseIPv4(host) {
            let (a, b) = (v4[0], v4[1])
            if a == 127 { return true }
            if a == 10 { return true }
            if a == 172 && (16...31).contains(b) { return true }
            if a == 192 && b == 168 { return true }
            if a == 169 && b == 254 { return true }
            return false
        }
        if let v6 = parseIPv6(host) {
            if v6 == [UInt8](repeating: 0, count: 15) + [1] { return true } // ::1
            if v6[0] & 0xFE == 0xFC { return true } // fc00::/7
            if v6[0] == 0xFE && v6[1] & 0xC0 == 0x80 { return true } // fe80::/10
            return false
        }
        return false
    }

    static func parseIPv4(_ s: String) -> [Int]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [Int] = []
        for part in parts {
            // Reject leading zeros and non-digits so "0177.0.0.1" style octal tricks are not treated as local.
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCIIDigit),
                  part == "0" || !part.hasPrefix("0"), let value = Int(part), value <= 255 else { return nil }
            out.append(value)
        }
        return out
    }

    static func parseIPv6(_ s: String) -> [UInt8]? {
        var address = in6_addr()
        // Strip a zone index (fe80::1%en0) before parsing.
        let bare = s.split(separator: "%", maxSplits: 1).first.map(String.init) ?? s
        guard bare.contains(":"), inet_pton(AF_INET6, bare, &address) == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

extension EndpointIdentity {
    /// The destination a request to `config` actually goes to, as disclosed for consent and recorded in the
    /// ContextPack (plan 11.2, 14.2). Applies `EndpointPolicy`, so a configuration the policy refuses has no identity.
    public static func of(_ config: ProviderConfig) throws(EndpointPolicyViolation) -> EndpointIdentity {
        let assessment = try EndpointPolicy.assess(config)
        return EndpointIdentity(providerKind: config.kind, host: assessment.origin.host, origin: assessment.origin.description,
                                basePath: config.baseURL.path(), classification: assessment.effectiveClassification, model: config.model)
    }
}
