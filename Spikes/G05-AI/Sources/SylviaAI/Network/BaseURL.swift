import Foundation

public enum BaseURLError: Error, Equatable, Sendable {
    case empty
    case notAURL
    case unsupportedScheme(String)
    case missingHost
    case containsCredentials
    case containsQueryOrFragment

    public var userMessage: String {
        switch self {
        case .empty: "Enter the API base address, for example https://example.com/v1."
        case .notAURL: "This is not a valid web address."
        case .unsupportedScheme(let scheme): "Addresses starting with \(scheme): are not supported. Use https://."
        case .missingHost: "The address has no host name."
        case .containsCredentials: "Remove the user name or password from the address. Keys are entered separately and kept in the Keychain."
        case .containsQueryOrFragment: "Remove the ? or # part from the address. Keys never go in a URL."
        }
    }
}

/// Base URL normalization, done once when an endpoint is configured (plan 14.1).
///
/// Rules:
/// 1. Trim whitespace; require http or https; lowercase scheme and host; drop default ports.
/// 2. Reject user info, query strings and fragments (keys never travel in a URL; plan 18.1).
/// 3. Strip trailing slashes. If the user pasted a full endpoint (".../chat/completions", ".../responses",
///    ".../messages", ".../audio/transcriptions"), strip that suffix.
/// 4. Collapse a repeated trailing version segment ("/v1/v1" -> "/v1").
/// 5. Never append "/v1" on the user's behalf: the generic contract is relative to an explicit base. A
///    connection test that receives 404 suggests the "/v1" form instead.
///
/// Endpoint paths never contain a version segment, so `join` cannot produce "/v1/v1".
public enum BaseURL {
    static let endpointSuffixes = ["/audio/transcriptions", "/chat/completions", "/responses", "/messages", "/completions"]

    public static func normalize(_ raw: String) throws(BaseURLError) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard var components = URLComponents(string: trimmed) else { throw .notAURL }
        guard let scheme = components.scheme?.lowercased() else { throw .notAURL }
        guard scheme == "https" || scheme == "http" else { throw .unsupportedScheme(scheme) }
        guard let host = components.host, !host.isEmpty else { throw .missingHost }
        if components.user != nil || components.password != nil { throw .containsCredentials }
        if components.query != nil || components.fragment != nil { throw .containsQueryOrFragment }

        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }

        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        var stripped = true
        while stripped {
            stripped = false
            for suffix in endpointSuffixes where path.lowercased().hasSuffix(suffix) {
                path.removeLast(suffix.count)
                while path.hasSuffix("/") { path.removeLast() }
                stripped = true
            }
        }
        // Collapse repeated trailing version segments such as /v1/v1 or /api/v1/v1.
        while let range = path.range(of: #"/(v[0-9]+)/\1$"#, options: .regularExpression) {
            let segment = path[range].split(separator: "/").first.map(String.init) ?? ""
            path.replaceSubrange(range, with: "/" + segment)
        }
        components.percentEncodedPath = path
        guard let url = components.url else { throw .notAURL }
        return url
    }

    /// Joins a normalized base and a relative endpoint path with exactly one slash.
    public static func join(_ base: URL, _ endpoint: String) -> URL {
        var absolute = base.absoluteString
        while absolute.hasSuffix("/") { absolute.removeLast() }
        var tail = endpoint
        while tail.hasPrefix("/") { tail.removeFirst() }
        // Force-unwrap is safe: both halves come from a valid URL and a fixed ASCII path.
        return URL(string: absolute + "/" + tail)!
    }
}
