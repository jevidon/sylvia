import Foundation
import Testing
@testable import SylviaDesignTokens

/// The repository root, from this file's location (Packages/Design/Tests/<target>/<file>).
let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

private func parsedExport() throws -> [String: Any] {
    let data = Data(TokenExport.serialized().utf8)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Token export (plan 4.4.9, Appendix A.5)")
struct ExportTests {
    @Test("Deterministic output")
    func deterministic() {
        #expect(TokenExport.serialized() == TokenExport.serialized())
        #expect(GeneratedFiles.all() == GeneratedFiles.all())
    }

    @Test("Complete: every color, marker, role, radius, spacing step, shadow, motion value and entry")
    func complete() throws {
        let json = try parsedExport()
        #expect(json["schema_version"] as? Int == 1)
        #expect(json["language"] as? String == "marginalia")
        let colors = try #require(json["color"] as? [String: [String: Any]])
        let colorTokens = ColorToken.allCases.filter { $0.reference.hasPrefix("color.") }
        #expect(Set(colors.keys) == Set(colorTokens.map { String($0.reference.dropFirst(6)) }))
        for (_, entry) in colors {
            for appearance in Appearance.allCases { #expect(entry[appearance.rawValue] is String) }
        }
        let markers = try #require(json["marker"] as? [String: [String: Any]])
        #expect(Set(markers.keys) == Set(Marker.allCases.map(\.rawValue)))
        let roles = try #require(json["type"] as? [String: [String: Any]])
        #expect(Set(roles.keys) == Set(TypeRole.allCases.map(\.rawValue)))
        let radius = try #require(json["radius"] as? [String: Any])
        #expect(Set(radius.keys) == Set(Radius.allCases.map(\.rawValue)))
        let space = try #require(json["space"] as? [String: Any])
        #expect(space["steps"] as? [Double] == Spacing.steps)
        let shadow = try #require((json["elevation"] as? [String: Any])?["shadow"] as? [String: Any])
        #expect(shadow["y"] as? Double == 8 && shadow["blur"] as? Double == 24)
        let motion = try #require(json["motion"] as? [String: Any])
        #expect((motion["sheet"] as? [String: Any])?["duration_ms"] as? Int == 200)
        let vocabulary = try #require(json["vocabulary"] as? [String: String])
        #expect(vocabulary.count == VocabularyKey.allCases.count)
        let labels = try #require(json["labels"] as? [String: String])
        #expect(labels.count == LabelKey.allCases.count)
        let mapping = try #require(json["import_state_mapping"] as? [String: Any])
        #expect(Set(mapping.keys) == Set(ImportState.allCases.map(\.rawValue)))
    }

    @Test("Matches the A.5 sketch where the sketch is correct")
    func matchesSketch() throws {
        let json = try parsedExport()
        let colors = try #require(json["color"] as? [String: [String: Any]])
        #expect(colors["ground"]?["light"] as? String == "#F4F2ED")
        #expect(colors["ochre_tint"]?["light"] as? String == "#F1E4C8")
        let markers = try #require(json["marker"] as? [String: [String: Any]])
        let expectations: [(String, String, String)] = [
            ("quote", "quote.opening", "QUOTE"), ("note", "pencil.tip", "NOTE"), ("audio", "waveform", "AUDIO"),
            ("generated", "sylvia.prompt", "GENERATED"), ("word", "book", "WORD"),
            ("attention", "exclamationmark.triangle", "NEEDS ATTENTION"), ("pending", "circle.fill", "QUEUED"),
        ]
        for (kind, glyph, label) in expectations {
            #expect(markers[kind]?["glyph"] as? String == glyph, "\(kind)")
            #expect(markers[kind]?["label"] as? String == label, "\(kind)")
        }
        #expect(markers["generated"]?["frame"] as? String == "dashed")
        let quoteText = try #require(markers["quote"]?["text"] as? [String: String])
        #expect(quoteText["light"] == "#8A5410" && quoteText["dark"] == "#D9A24A")
        let roles = try #require(json["type"] as? [String: [String: Any]])
        #expect(roles["display"]?["size"] as? Double == 34)
        #expect(roles["display"]?["line"] as? Double == 40)
        #expect(roles["display"]?["maps_to"] as? String == "largeTitle")
        #expect(roles["reading"]?["user_range"] as? [Double] == [14, 28])
        #expect(roles["body"]?["face"] as? String == "system")
        let vocabulary = try #require(json["vocabulary"] as? [String: String])
        #expect(vocabulary["save.in_progress"] == "Saving…")
        #expect(vocabulary["save.done"] == "Saved")
        #expect(vocabulary["save.failed"] == "Not saved · your text is still here")
        #expect(vocabulary["import.ready_indexing"] == "Ready · indexing continues")
    }

    @Test("Lint lists: every permitted form and every forbidden phrase")
    func lintLists() {
        let permitted = TokenExport.permittedPhrases()
        #expect(permitted.contains("Indexing {n} of {m} chapters"))
        #expect(permitted.contains("Indexing {n} of {m} chapter"))
        #expect(permitted.count == VocabularyKey.allCases.count + 1)
        let forbidden = TokenExport.forbiddenPhrases()
        #expect(forbidden.contains("Thinking…") && forbidden.contains("Delete") && forbidden.contains("Error"))
        #expect(Set(forbidden).count == forbidden.count)
        #expect(forbidden.count == 22)
    }

    @Test("String Catalog: every key, positional specifiers, plural substitution")
    func stringCatalog() throws {
        let data = Data(StringCatalog.serialized().utf8)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(catalog["sourceLanguage"] as? String == "en")
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        #expect(strings.count == VocabularyKey.allCases.count + LabelKey.allCases.count + FormatKey.allCases.count)
        func value(_ key: String) -> String? {
            let en = ((strings[key]?["localizations"] as? [String: Any])?["en"] as? [String: Any])
            return (en?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        #expect(value("import.waiting_for_source") == "Waiting for %1$@")
        #expect(value("endpoint.hosted_model") == "%1$@ · hosted · %2$@")
        #expect(value("search.indexing") == "Indexing %1$lld of %2$#@m@")
        #expect(value("duration.hours_minutes") == "%1$lldh %2$lldm")
        for key in VocabularyKey.allCases where key.placeholders.isEmpty {
            #expect(value(key.rawValue) == key.text)
            #expect(!(value(key.rawValue) ?? "").contains("%"), "\(key) has no format specifiers")
        }
        for (_, entry) in strings { #expect(entry["extractionState"] as? String == "manual") }
    }

    @Test("Symbol templates: three masters with identical path structure, as interpolation requires")
    func symbolTemplates() throws {
        for symbol in CustomSymbol.allCases {
            let svg = try #require(SymbolCatalog.files()
                .first { $0.key.hasSuffix("\(symbol.rawValue).svg") }?.value)
            for master in ["Ultralight-S", "Regular-S", "Black-S"] {
                #expect(svg.contains("<g id=\"\(master)\""), "\(symbol) \(master)")
                #expect(svg.contains("id=\"left-margin-\(master)\"") && svg.contains("id=\"right-margin-\(master)\""))
            }
            let groups = svg.components(separatedBy: "<g id=\"").dropFirst(4) // preamble, Notes, Guides, Symbols
            let structures = groups.map { group in
                group.components(separatedBy: "<path d=\"").dropFirst()
                    .map { $0.prefix { $0 != "\"" }.filter { "MLCZ".contains($0) } }
            }
            #expect(structures.count == 3)
            #expect(structures.allSatisfy { $0 == structures.first! }, "\(symbol) masters must be compatible")
            let segments = symbol.polylines.reduce(0) { $0 + $1.count - 1 }
            #expect(structures.first?.count == segments)
        }
    }

    @Test("Committed generated files match the token definitions (same check as CI)")
    func committedFilesMatch() throws {
        for (path, content) in GeneratedFiles.all() {
            let url = repositoryRoot.appendingPathComponent(path)
            let onDisk = try String(contentsOf: url, encoding: .utf8)
            #expect(onDisk == content, "\(path) is out of date; run sylvia-design-export write")
        }
    }
}
