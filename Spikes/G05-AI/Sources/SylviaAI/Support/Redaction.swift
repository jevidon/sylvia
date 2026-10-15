import Foundation

/// Scrubs provider text before it can reach an error, a log line or a persisted record (plan 14.3, 18.1).
///
/// Providers sometimes echo a key or part of it in an error body ("Incorrect API key provided: sk-ab***yz").
/// The redactor removes: every known secret in full; any run of 6+ characters copied from a known secret's
/// start or end; key-shaped tokens (`sk-…`, `sk-ant-…`, `Bearer …`, `x-api-key: …`); and caps the length.
public struct Redactor: Sendable {
    public var knownSecrets: [Secret]
    public var maxLength: Int

    public init(knownSecrets: [Secret] = [], maxLength: Int = 300) {
        self.knownSecrets = knownSecrets
        self.maxLength = maxLength
    }

    static let patterns: [NSRegularExpression] = [
        #"sk-ant-[A-Za-z0-9_\-*.]{4,}"#,
        #"sk-[A-Za-z0-9_\-*.]{4,}"#,
        #"(?i)bearer\s+[A-Za-z0-9_\-.~+/=*]{4,}"#,
        #"(?i)(x-api-key|api[_-]?key|authorization)\s*[:=]\s*"?[^\s",}]{4,}"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    public func scrub(_ text: String) -> String {
        var out = text
        for secret in knownSecrets where !secret.isEmpty {
            let value = secret.revealForAuthorizationHeader()
            out = out.replacingOccurrences(of: value, with: "<redacted>")
            // Partial echoes: any 6+ character prefix or suffix of the secret.
            if value.count >= 8 {
                for length in stride(from: value.count - 1, through: 6, by: -1) {
                    let prefix = String(value.prefix(length))
                    let suffix = String(value.suffix(length))
                    if out.contains(prefix) { out = out.replacingOccurrences(of: prefix, with: "<redacted>") }
                    if out.contains(suffix) { out = out.replacingOccurrences(of: suffix, with: "<redacted>") }
                }
            }
        }
        for pattern in Self.patterns {
            let range = NSRange(out.startIndex..., in: out)
            out = pattern.stringByReplacingMatches(in: out, range: range, withTemplate: "<redacted>")
        }
        if out.count > maxLength { out = String(out.prefix(maxLength)) + "…" }
        return out
    }
}

/// Diagnostic log events. Events carry only kinds, states, counts, durations and hosts: never prompts,
/// selected text, notes, titles, answers or credentials (plan 18.1). Tests install a capturing sink and assert
/// that no canary secret or content string ever reaches it.
public struct AILogEvent: Sendable, Equatable {
    public let name: String
    public let fields: [String: String]

    public init(_ name: String, _ fields: [String: String] = [:]) {
        self.name = name
        self.fields = fields
    }

    public var rendered: String {
        let body = fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: " ")
        return body.isEmpty ? name : "\(name) \(body)"
    }
}

public protocol AILogSink: Sendable {
    func record(_ event: AILogEvent)
}

public struct NullLogSink: AILogSink {
    public init() {}
    public func record(_ event: AILogEvent) {}
}
