import Foundation

/// The harness's log format: one line per record, `<UTC time> <event> key=value ... [reason="..."]`.
///
/// Values never contain a space, so a line splits into its fields at spaces; the optional `reason` field, last on the
/// line, is quoted and holds an error's description with its quotes made single and any absolute path cut to its last
/// component. Lines hold only the harness's own synthetic values (attempt numbers, outcomes, classes, error codes):
/// never a quotation, note, title or other user text (CLAUDE.md, plan 18.1).
public enum HarnessLog {
    public static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt))
    }

    public static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f", value)
    }

    /// Builds a line. A value containing whitespace has it replaced by `_`, so the line still splits at spaces.
    public static func line(_ date: Date, _ event: String, _ fields: [(String, String)], reason: String? = nil) -> String {
        var parts = [timestamp(date), event]
        for (key, value) in fields {
            parts.append("\(key)=\(value.isEmpty ? "-" : value.replacing(/\s+/, with: "_"))")
        }
        if let reason, !reason.isEmpty {
            parts.append("reason=\"\(sanitizedReason(reason))\"")
        }
        return parts.joined(separator: " ")
    }

    /// A line recorded earlier and written to the log file at `date`: `written-late=<date>` goes before the reason, so
    /// the line keeps its fields and its recorded time.
    public static func markedWrittenLate(_ line: String, at date: Date) -> String {
        let field = " written-late=\(timestamp(date))"
        if let range = line.range(of: " reason=\"") {
            return line[..<range.lowerBound] + field + line[range.lowerBound...]
        }
        return line + field
    }

    /// The fields of a line written by `line(_:_:_:reason:)`: "time", "event" and each key. For tests and for reading
    /// the log back; the harness's own decisions never parse its log.
    public static func fields(of line: String) -> [String: String] {
        var result: [String: String] = [:]
        var body = Substring(line)
        if let range = line.range(of: " reason=\"") {
            var reason = line[range.upperBound...]
            if reason.hasSuffix("\"") { reason = reason.dropLast() }
            result["reason"] = String(reason)
            body = line[..<range.lowerBound]
        }
        let parts = body.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count > 0 { result["time"] = String(parts[0]) }
        if parts.count > 1 { result["event"] = String(parts[1]) }
        for part in parts.dropFirst(2) {
            guard let equals = part.firstIndex(of: "=") else { continue }
            result[String(part[..<equals])] = String(part[part.index(after: equals)...])
        }
        return result
    }

    /// A compact code for an error and the errors under it, outermost first: `NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1`.
    public static func code(_ error: any Error) -> String {
        var chain: [String] = []
        var current: NSError? = error as NSError
        while let ns = current, chain.count < 4 {
            chain.append("\(ns.domain):\(ns.code)")
            current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain.joined(separator: "/").replacing(/\s+/, with: "_")
    }

    /// An error's description for the `reason` field, without absolute paths.
    public static func reason(_ error: any Error) -> String {
        let ns = error as NSError
        var text = String(describing: error)
        if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain {
            text = ns.localizedDescription
        }
        return sanitizedReason(text)
    }

    static func sanitizedReason(_ text: String) -> String {
        let flat = scrubPaths(text).replacing("\"", with: "'").replacing(/\s+/, with: " ")
        return flat.count > 300 ? String(flat.prefix(299)) + "…" : flat
    }

    /// Replaces every absolute path (a run of non-space characters that starts with `/` after a space, a quote or the
    /// start of the text, and has at least two components) by `…/` and its last component, so a log line never carries
    /// a container path, a user name or a file layout beyond the file's own name.
    public static func scrubPaths(_ text: String) -> String {
        text.replacing(/(?<lead>^|[\s"'“(\[=])(?<path>\/[^\s"'”)\],;]+\/[^\s"'”)\],;]+)/) { match in
            let path = String(match.output.path)
            let last = path.split(separator: "/").last.map(String.init) ?? ""
            return "\(match.output.lead)…/\(last)"
        }
    }
}
