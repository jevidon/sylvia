import Foundation

extension JSONValue {
    /// Returns a copy with the value at `path` replaced (or removed when `value` is nil).
    /// Intermediate members must exist and be objects.
    func setting(_ path: [String], to value: JSONValue?) -> JSONValue {
        guard case .object(var members) = self, let key = path.first else {
            preconditionFailure("path \(path) does not lead through objects")
        }
        let index = members.firstIndex { $0.0 == key }
        if path.count == 1 {
            if let value {
                if let index { members[index].1 = value } else { members.append((key, value)) }
            } else if let index {
                members.remove(at: index)
            }
            return .object(members)
        }
        guard let index else { preconditionFailure("missing \(key) in path \(path)") }
        members[index].1 = members[index].1.setting(Array(path.dropFirst()), to: value)
        return .object(members)
    }
}

/// Fixtures for `Contracts/schemas/design-tokens.v1.schema.json` (Contracts/README.md): the real
/// export as the valid case, and the export with exactly one defect for each invalid case.
public enum ContractFixtures {
    public static let directory = "Contracts/fixtures/design-tokens.v1"

    /// (file name, path, replacement or nil to remove, why it must fail)
    static let invalidCases: [(String, [String], JSONValue?, String)] = [
        ("missing-marker-pending", ["marker", "pending"], nil, "the marker set must have all seven markers"),
        ("color-hex-without-hash", ["color", "ground", "light"], .string("F4F2ED"), "colors are #RRGGBB"),
        ("unknown-appearance-key", ["color", "ground", "sepia"], .string("#F4F2ED"), "the four appearances are a closed set"),
        ("weakened-contrast-threshold", ["contrast", "minimum_ratio"], .number(4.0), "the 4.5:1 threshold may not be weakened"),
        ("large-text-boundary-lowered", ["contrast", "large_text_minimum_points"], .number(10),
         "3:1 applies only from 24 pt; a lower boundary would weaken the rule for smaller text"),
        ("busy-state-exempted", ["contrast", "component_pairs"],
         .array([TokenExport.componentPairJSON(ComponentContrastPairs.all.first { $0.state == "busy" }!,
                                               requirement: ComponentContrastPair.Requirement.exemptDisabled.rawValue)]),
         "only a disabled control may be exempt from the contrast minimum"),
        ("schema-version-2",["schema_version"], .integer(2), "this schema is version 1"),
        ("vocabulary-exclamation-mark", ["vocabulary", "save.done"], .string("Saved!"), "no exclamation marks"),
        ("marker-label-not-uppercase", ["marker", "quote", "label"], .string("Quote"), "marker labels are exported uppercase"),
        ("missing-type-role-micro", ["type", "micro"], nil, "all eight type roles are required"),
        ("reading-without-user-range", ["type", "reading", "user_range"], nil, "the reading role carries its user range"),
        ("unknown-kind-renders-as-quote", ["capture_kind_mapping", "unrecognized", "marker"], .string("quote"),
         "an unrecognized capture kind never renders as a quote"),
    ]

    public static func files() -> [String: String] {
        let document = TokenExport.document()
        var files: [String: String] = [
            directory + "/valid/marginalia-v1-export.json": document.serialized(style: .standard),
            directory + "/valid/unknown-optional-top-level-field.json": document
                .setting(["x_reader_note"], to: .string("Readers tolerate unknown optional fields (Contracts/README.md)."))
                .serialized(style: .standard),
        ]
        for (name, path, value, _) in invalidCases {
            files[directory + "/invalid/\(name).json"] = document.setting(path, to: value).serialized(style: .standard)
        }
        return files
    }
}
