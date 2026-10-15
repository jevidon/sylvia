import Foundation

/// A JSON value whose objects keep insertion order, written deterministically. Used for every
/// generated file so the CI drift check is byte-for-byte.
public indirect enum JSONValue: Sendable, Hashable {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        lhs.serialized(style: .standard) == rhs.serialized(style: .standard)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(serialized(style: .standard))
    }

    public enum Style: Sendable {
        /// `"key": value`, used for Contracts/.
        case standard
        /// `"key" : value`, the way Xcode writes asset catalogs and String Catalogs.
        case xcode
    }

    /// Pretty-printed with two-space indentation and a trailing newline.
    public func serialized(style: Style) -> String {
        var out = ""
        write(to: &out, indent: 0, style: style)
        out.append("\n")
        return out
    }

    private func write(to out: inout String, indent: Int, style: Style) {
        let pad = String(repeating: " ", count: indent)
        let innerPad = String(repeating: " ", count: indent + 2)
        switch self {
        case .object(let members):
            if members.isEmpty { out.append("{}"); return }
            out.append("{\n")
            for (index, (key, value)) in members.enumerated() {
                out.append(innerPad)
                out.append(JSONValue.quote(key))
                out.append(style == .xcode ? " : " : ": ")
                value.write(to: &out, indent: indent + 2, style: style)
                out.append(index == members.count - 1 ? "\n" : ",\n")
            }
            out.append(pad + "}")
        case .array(let items):
            if items.isEmpty { out.append("[]"); return }
            if items.allSatisfy(\.isScalar) {
                out.append("[")
                out.append(items.map { $0.serialized(style: style).trimmingCharacters(in: .newlines) }
                    .joined(separator: ", "))
                out.append("]")
                return
            }
            out.append("[\n")
            for (index, item) in items.enumerated() {
                out.append(innerPad)
                item.write(to: &out, indent: indent + 2, style: style)
                out.append(index == items.count - 1 ? "\n" : ",\n")
            }
            out.append(pad + "]")
        case .string(let s):
            out.append(JSONValue.quote(s))
        case .integer(let i):
            out.append(String(i))
        case .number(let d):
            precondition(d.isFinite, "JSON numbers must be finite")
            if d == d.rounded(), abs(d) < 1e15 {
                out.append(String(Int(d)))
            } else {
                out.append(String(d)) // shortest round-trip representation
            }
        case .bool(let b):
            out.append(b ? "true" : "false")
        case .null:
            out.append("null")
        }
    }

    private var isScalar: Bool {
        switch self {
        case .object, .array: false
        default: true
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case _ where scalar.value < 0x20:
                out.append(String(format: "\\u%04X", scalar.value))
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out.append("\"")
        return out
    }
}

extension JSONValue {
    /// An object with members sorted by key (Xcode's order).
    static func sortedObject(_ members: [String: JSONValue]) -> JSONValue {
        .object(members.sorted { $0.key < $1.key })
    }
}
