import Foundation

/// Suppresses a reasoning block that some local models emit inline as `<think>…</think>` at the very start of
/// the answer content. Only a block that opens the content (after optional whitespace) is removed; the same tags
/// later in an answer are left alone because they could be legitimate text. Memory is bounded: reasoning text is
/// dropped as it arrives, keeping only enough tail to match a closing tag split across chunks.
public struct ThinkTagFilter: Sendable {
    enum State: Sendable { case undecided, inThink, afterThink, passthrough }
    var state = State.undecided
    var pending = ""
    static let open = "<think>"
    static let close = "</think>"

    public init() {}

    /// Returns the visible text released by this chunk and whether a think block was detected so far.
    public mutating func consume(_ chunk: String) -> (visible: String, sawThink: Bool) {
        pending += chunk
        var output = ""
        while true {
            switch state {
            case .passthrough:
                output += pending
                pending = ""
                return (output, sawThink)
            case .undecided:
                let trimmed = String(pending.drop(while: { $0.isWhitespace }))
                if trimmed.hasPrefix(Self.open) {
                    sawThink = true
                    state = .inThink
                    pending = String(trimmed.dropFirst(Self.open.count))
                } else if trimmed.isEmpty || Self.open.hasPrefix(trimmed) {
                    return (output, sawThink)  // not enough characters yet to decide
                } else {
                    state = .passthrough
                }
            case .inThink:
                if let range = pending.range(of: Self.close) {
                    pending = String(pending[range.upperBound...])
                    state = .afterThink
                } else {
                    pending = String(pending.suffix(Self.close.count - 1))
                    return (output, sawThink)
                }
            case .afterThink:
                pending = String(pending.drop(while: { $0.isWhitespace }))
                if pending.isEmpty { return (output, sawThink) }
                state = .passthrough
            }
        }
    }

    public private(set) var sawThink = false

    /// Releases any text still held at end of stream. Text inside an unterminated think block is dropped.
    public mutating func finish() -> String {
        defer { pending = "" }
        switch state {
        case .undecided, .passthrough: return pending
        case .inThink, .afterThink: return ""
        }
    }
}
