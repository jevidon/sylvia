import Foundation
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack
import Testing

/// G0.3 review R3-01: the manifest readers must accept nothing their contract refuses. These tests pin the text rules
/// (`StrictJSON`), the refusal of explicit null and the canonical UUID form. The same inputs go through the schemas and
/// the readers side by side in Spikes/G03-Intake/scripts/contract_differential.py.
@Suite("manifest text: strict JSON, no null members, canonical UUIDs", .removesTemporaryFiles)
struct ManifestTextTests {
    static let fixtures = ContractFixtureTests.contracts

    static func text(_ relativePath: String) throws -> String {
        try String(contentsOf: fixtures.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func violation(_ bytes: [UInt8]) -> StrictJSON.Violation.Kind? {
        do throws(StrictJSON.Violation) {
            try StrictJSON.check(Data(bytes))
            return nil
        } catch {
            return error.kind
        }
    }

    static func violation(_ text: String) -> StrictJSON.Violation.Kind? { violation(Array(text.utf8)) }

    @Test("strict JSON: what the writers produce and every committed manifest fixture passes the text check")
    func writersAndFixturesPass() throws {
        for contract in ["import-handoff-manifest.v1", "sylviapack-manifest.v1"] {
            for kind in ["valid", "invalid"] {
                for url in try ContractFixtureTests.fixtures(contract, kind) {
                    #expect(Self.violation(Array(try Data(contentsOf: url))) == nil, "\(contract)/\(kind)/\(url.lastPathComponent)")
                }
            }
        }
        // PackManifest.encoded() and HandoffManifest.encoded() (JSONEncoder, sorted keys, pretty-printed) read back.
        let pack = try PackManifest.decode(Data(Self.text("sylviapack-manifest.v1/valid/publication-and-audiobook.json").utf8))
        #expect(try PackManifest.decode(pack.encoded()) == pack)
        let handoff = try HandoffManifest.decode(Data(Self.text("import-handoff-manifest.v1/valid/one-file-representation.json").utf8))
        #expect(try HandoffManifest.decode(handoff.encoded()) == handoff)
    }

    @Test("strict JSON: refuses texts that are not JSON, not UTF-8, or carry a byte order mark")
    func refusesNonJSON() {
        let object = #"{"a": "x", "b": [1, 2]}"#
        let encodings: [(String, [UInt8], StrictJSON.Violation.Kind)] = [
            ("UTF-8 byte order mark", [0xEF, 0xBB, 0xBF] + Array(object.utf8), .byteOrderMark),
            ("UTF-16LE", object.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }, .syntax),
            ("UTF-16BE", object.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }, .syntax),
            ("UTF-16LE with its byte order mark", [0xFF, 0xFE] + object.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }, .syntax),
            ("UTF-32LE", object.unicodeScalars.flatMap { s in (0..<4).map { UInt8((s.value >> (8 * UInt32($0))) & 0xFF) } }, .syntax),
            ("invalid UTF-8: lone continuation byte", Array(#"{"a": ""#.utf8) + [0x80] + Array(#""}"#.utf8), .invalidUTF8),
            ("invalid UTF-8: overlong slash", Array(#"{"a": ""#.utf8) + [0xC0, 0xAF] + Array(#""}"#.utf8), .invalidUTF8),
            ("invalid UTF-8: encoded surrogate", Array(#"{"a": ""#.utf8) + [0xED, 0xA0, 0x80] + Array(#""}"#.utf8), .invalidUTF8),
            ("invalid UTF-8: above U+10FFFF", Array(#"{"a": ""#.utf8) + [0xF4, 0x90, 0x80, 0x80] + Array(#""}"#.utf8), .invalidUTF8),
            ("invalid UTF-8: truncated sequence", Array(#"{"a": ""#.utf8) + [0xE2, 0x82] + Array(#""}"#.utf8), .invalidUTF8),
            ("invalid UTF-8 in a member nobody decodes", Array(#"{"a": "x", "unknown": ""#.utf8) + [0xC3, 0x28] + Array(#""}"#.utf8), .invalidUTF8),
        ]
        for (label, bytes, expected) in encodings {
            #expect(Self.violation(bytes) == expected, "\(label)")
        }
        let texts: [(String, String, StrictJSON.Violation.Kind)] = [
            ("trailing comma in an object", #"{"a": "x",}"#, .syntax),
            ("trailing comma in a nested object", #"{"a": "x", "u": {"v": 1,}}"#, .syntax),
            ("trailing comma in an array", #"{"a": "x", "u": [1, 2,]}"#, .syntax),
            ("two commas", #"{"a": "x",, "u": 1}"#, .syntax),
            ("missing comma", #"{"a": "x" "u": 1}"#, .syntax),
            ("missing colon", #"{"a" "x"}"#, .syntax),
            ("unquoted name", #"{a: "x"}"#, .syntax),
            ("single quotes", "{'a': 'x'}", .syntax),
            ("comment", #"{"a": "x" /* c */}"#, .syntax),
            ("leading zero", #"{"a": "x", "u": -01}"#, .syntax),
            ("exponent without digits", #"{"a": "x", "u": 1e+}"#, .syntax),
            ("fraction without digits", #"{"a": "x", "u": 1.}"#, .syntax),
            ("number starting with a point", #"{"a": "x", "u": .5}"#, .syntax),
            ("plus sign", #"{"a": "x", "u": +1}"#, .syntax),
            ("hexadecimal number", #"{"a": "x", "u": 0x10}"#, .syntax),
            ("unescaped control character", "{\"a\": \"x\u{01}y\"}", .syntax),
            ("unescaped tab in a member nobody decodes", "{\"a\": \"x\", \"u\": \"\t\"}", .syntax),
            ("bad escape in a member nobody decodes", #"{"a": "x", "u": "\x"}"#, .syntax),
            ("short unicode escape", #"{"a": "\u00e"}"#, .syntax),
            ("unterminated string", #"{"a": "x}"#, .syntax),
            ("unterminated object", #"{"a": "x""#, .syntax),
            ("text after the value", #"{"a": "x"} x"#, .syntax),
            ("two values", #"{"a": "x"} {"a": "y"}"#, .syntax),
            ("NUL after the value", "{\"a\": \"x\"}\u{0}", .syntax),
            ("empty text", "", .syntax),
            ("whitespace only", " \n", .syntax),
            ("vertical tab is not JSON whitespace", "\u{0B}{\"a\": \"x\"}", .syntax),
            ("form feed is not JSON whitespace", "\u{0C}{\"a\": \"x\"}", .syntax),
            ("no-break space is not JSON whitespace", "\u{A0}{\"a\": \"x\"}", .syntax),
            ("upper-case literal", #"{"a": NULL}"#, .syntax),
            ("truncated literal", #"{"a": tru}"#, .syntax),
            ("literal with a suffix", #"{"a": truex}"#, .syntax),
            ("NaN", #"{"a": "x", "u": NaN}"#, .nonStandardNumber),
            ("Infinity", #"{"a": "x", "u": Infinity}"#, .nonStandardNumber),
            ("-Infinity", #"{"a": "x", "u": -Infinity}"#, .nonStandardNumber),
        ]
        for (label, text, expected) in texts {
            #expect(Self.violation(text) == expected, "\(label): \(text.debugDescription)")
        }
        let accepted = [
            " \t\r\n" + object + "\r\n", #"{"a": "\/\"\\\b\f\n\r\t\u00e9\u00E9"}"#, "{\"a\": \"x\u{7F}y\"}",
            #"{"a": "\u0000"}"#, #"{"a": "\uffff"}"#, #"{"a": -0, "b": 0.5e-3, "c": 1E+2, "d": [true, false, null, {}, []]}"#,
            #"{"a": 1e400, "b": -1e400}"#, "[]", "\"top-level string\"", "0",
        ]
        for text in accepted {
            #expect(Self.violation(text) == nil, "\(text.debugDescription)")
        }
    }

    @Test("strict JSON: a member name twice in one object is refused, compared code point by code point after escapes")
    func duplicateNames() {
        #expect(Self.violation(#"{"a": 1, "a": 2}"#) == .duplicateName)
        #expect(Self.violation(#"{"a": 1, "\u0061": 2}"#) == .duplicateName)                  // an escape of the same name
        #expect(Self.violation("{\"\u{E9}\": 1, \"\\u00e9\": 2}") == .duplicateName)          // literal and escaped é
        #expect(Self.violation("{\"\u{1F600}\": 1, \"\\ud83d\\ude00\": 2}") == .duplicateName) // a surrogate pair is the same code point
        #expect(Self.violation(#"{"a": {"b": 1, "b": 2}}"#) == .duplicateName)                 // nested
        #expect(Self.violation(#"{"a": [{"b": 1}, {"c": 1, "c": 1}]}"#) == .duplicateName)
        // Not duplicates: the same name in different objects, and distinct code points that look alike (U+00E9 and
        // e + U+0301 are canonically equivalent, but JSON, I-JSON and the validator compare code points).
        #expect(Self.violation(#"{"a": 1, "b": {"a": 2}}"#) == nil)
        #expect(Self.violation(#"[{"a": 1}, {"a": 2}]"#) == nil)
        #expect(Self.violation("{\"\u{E9}\": 1, \"e\u{301}\": 2}") == nil)
        #expect(Self.violation(#"{"a": 1, "A": 2}"#) == nil)
    }

    @Test("strict JSON: unpaired surrogate escapes are refused anywhere; surrogate pairs are one character")
    func surrogates() {
        for text in [#"{"a": "\ud800"}"#, #"{"a": "\udc00"}"#, #"{"a": "\ud800x"}"#, #"{"a": "\ud800\u0041"}"#,
                     #"{"a": "\ud800\ud800"}"#, #"{"a": "\udc00\ud800"}"#, #"{"\ud800": 1}"#, #"{"a": "x", "u": ["\ud800"]}"#] {
            #expect(Self.violation(text) == .unpairedSurrogate, "\(text)")
        }
        #expect(Self.violation(#"{"a": "\ud83d\ude00", "b": "\uD83D\uDE00"}"#) == nil)
        #expect(Self.violation("{\"a\": \"\u{1F600}\"}") == nil)
    }

    @Test("strict JSON: nesting and integer length at their limits (512 levels, as JSONDecoder; 4,300 digits, as the validator)")
    func limits() {
        func nested(_ levels: Int) -> String { String(repeating: "[", count: levels) + String(repeating: "]", count: levels) }
        #expect(Self.violation(nested(512)) == nil)
        #expect(Self.violation(nested(513)) == .tooDeep)
        #expect(Self.violation("{\"a\": " + nested(511) + "}") == nil)        // the object is the first of 512 levels
        #expect(Self.violation("{\"a\": " + nested(512) + "}") == .tooDeep)
        #expect(Self.violation(nested(100_000)) == .tooDeep)                  // refused without recursion
        let digits4300 = "1" + String(repeating: "0", count: 4299)
        #expect(Self.violation("{\"a\": \(digits4300)}") == nil)
        #expect(Self.violation("{\"a\": -\(digits4300)}") == nil)
        #expect(Self.violation("{\"a\": \(digits4300)0}") == .integerTooLong)
        #expect(Self.violation("{\"a\": -\(digits4300)0}") == .integerTooLong)
        #expect(Self.violation("{\"a\": \(digits4300)0.0}") == nil)           // not an integer: Python reads it as a float
        #expect(Self.violation("{\"a\": \(digits4300)0e0}") == nil)
    }

    /// The facts on this platform that StrictJSON and CanonicalUUID exist for. Recorded, not required: if a later OS
    /// changes them the readers still hold, because they no longer depend on them.
    @Test("platform facts behind the strict reader (recorded): what JSONDecoder and UUID(uuidString:) accept on their own")
    func platformFacts() {
        struct Probe: Decodable { var a: String }
        func decoderAccepts(_ bytes: [UInt8]) -> Bool { (try? JSONDecoder().decode(Probe.self, from: Data(bytes))) != nil }
        func decoderAccepts(_ text: String) -> Bool { decoderAccepts(Array(text.utf8)) }
        let duplicate = try? JSONDecoder().decode(Probe.self, from: Data(#"{"a": "first", "a": "second"}"#.utf8))
        let facts: [(String, Bool)] = [
            ("trailing comma accepted", decoderAccepts(#"{"a": "x",}"#)),
            ("trailing comma in an array accepted", decoderAccepts(#"{"a": "x", "u": [1,]}"#)),
            ("UTF-8 byte order mark accepted", decoderAccepts([0xEF, 0xBB, 0xBF] + Array(#"{"a": "x"}"#.utf8))),
            ("UTF-16LE accepted", decoderAccepts(#"{"a": "x"}"#.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })),
            ("invalid UTF-8 in an undecoded member accepted", decoderAccepts(Array(#"{"a": "x", "u": ""#.utf8) + [0xC3, 0x28] + Array(#""}"#.utf8))),
            ("unpaired surrogate in an undecoded member accepted", decoderAccepts(#"{"a": "x", "u": "\ud800"}"#)),
            ("malformed number in an undecoded member accepted", decoderAccepts(#"{"a": "x", "u": 1e+}"#)),
            ("duplicate name keeps the first value", duplicate?.a == "first"),
            ("UUID(uuidString:) accepts a UUID followed by NUL and more", UUID(uuidString: "5E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D10\u{0}junk") != nil),
        ]
        print("platform JSONDecoder: " + facts.map { "\($0.0): \($0.1)" }.joined(separator: "; "))
        // The strict reader refuses each of these inputs whatever the platform does.
        #expect(Self.violation(#"{"a": "x",}"#) == .syntax)
        #expect(CanonicalUUID.parse("5E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D10\u{0}junk") == nil)
    }

    // MARK: - Manifests

    static func packText(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(
            with: Data(text("sylviapack-manifest.v1/valid/publication-and-audiobook.json").utf8)) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func handoffText(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(
            with: Data(text("import-handoff-manifest.v1/valid/one-file-representation.json").utf8)) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func editFile(_ index: Int, _ key: String, _ value: Any?) -> (inout [String: Any]) -> Void {
        { object in
            var files = object["files"] as! [[String: Any]]
            files[index][key] = value
            object["files"] = files
        }
    }

    static func editGroup(_ index: Int, _ key: String, _ value: Any?) -> (inout [String: Any]) -> Void {
        { object in
            var groups = object["groups"] as! [[String: Any]]
            groups[index][key] = value
            object["groups"] = groups
        }
    }

    static func isExplicitNull(_ error: any Error) -> Bool {
        guard case let DecodingError.valueNotFound(_, context) = error else { return false }
        return context.debugDescription.contains("explicit null")
    }

    @Test("pack reader refuses an explicit null in every optional member, as the schema does, and accepts the member absent")
    func packNullMembers() throws {
        let cases: [(String, (inout [String: Any]) -> Void, (inout [String: Any]) -> Void)] = [
            // group_id on the EPUB (which has no order), order on an audio member.
            ("files[0].group_id", Self.editFile(0, "group_id", NSNull()), Self.editFile(0, "group_id", nil)),
            ("files[1].order", Self.editFile(1, "order", NSNull()), { _ in }),
            ("groups[0].title", Self.editGroup(0, "title", NSNull()), Self.editGroup(0, "title", nil)),
            ("groups[0].creators", Self.editGroup(0, "creators", NSNull()), Self.editGroup(0, "creators", nil)),
            ("groups[0].language", Self.editGroup(0, "language", NSNull()), Self.editGroup(0, "language", nil)),
            ("groups[0].identifiers", Self.editGroup(0, "identifiers", NSNull()), Self.editGroup(0, "identifiers", nil)),
            ("groups[1].member_order_basis", Self.editGroup(1, "member_order_basis", NSNull()), Self.editGroup(1, "member_order_basis", nil)),
        ]
        for (label, withNull, without) in cases {
            do {
                _ = try PackManifest.decode(Self.packText(withNull))
                Issue.record("\(label): an explicit null was accepted")
            } catch {
                #expect(Self.isExplicitNull(error), "\(label): \(error)")
            }
            #expect(throws: Never.self, "\(label): absent") { try PackManifest.decode(Self.packText(without)).validate(limits: PackLimits()) }
        }
        // A null in a member the contract does not define is ignored, as the schema ignores it.
        #expect(throws: Never.self) {
            try PackManifest.decode(Self.packText { $0["x_future"] = NSNull() }).validate(limits: PackLimits())
        }
    }

    @Test("readers accept UUIDs only in their canonical form (a NUL suffix, extra or missing hyphens, braces and signs are refused)")
    func canonicalUUIDs() throws {
        let canonical = "5E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D10"
        let refused = [canonical + "\u{0}", canonical + "\u{0}junk", "5E0D7C1A-2B3F-4A9C-8D7E--6F5A4B3C2D10",
                       "5E0D7C1A-2B3F-4A9C-8D7E-6F5A-4B3C2D10", canonical + "-", "{" + canonical + "}",
                       "5E0D7C1A2B3F4A9C8D7E6F5A4B3C2D10", "5E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2_10", "+E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D10",
                       "\u{665}E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D10", canonical + " ", " " + canonical, canonical + "\n",
                       "urn:uuid:" + canonical, "5E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D1G", ""]
        for text in refused {
            #expect(CanonicalUUID.parse(text) == nil, "\(text.debugDescription)")
            #expect(throws: DecodingError.self, "pack_id \(text.debugDescription)") {
                try PackManifest.decode(Self.packText { $0["pack_id"] = text })
            }
            #expect(throws: DecodingError.self, "handoff_id \(text.debugDescription)") {
                try HandoffManifest.decode(Self.handoffText { $0["handoff_id"] = text })
            }
            #expect(throws: DecodingError.self, "item_id \(text.debugDescription)") {
                try HandoffManifest.decode(Self.handoffText { object in
                    var items = object["items"] as! [[String: Any]]
                    items[0]["item_id"] = text
                    object["items"] = items
                })
            }
        }
        #expect(CanonicalUUID.parse(canonical) == UUID(uuidString: canonical))
        #expect(CanonicalUUID.parse(canonical.lowercased()) == UUID(uuidString: canonical))
        #expect(try PackManifest.decode(Self.packText { $0["pack_id"] = canonical.lowercased() }).packID == UUID(uuidString: canonical))
    }

    @Test("readers refuse a member name given twice, whichever of the two values is valid")
    func duplicateMembersInManifests() throws {
        let text = try Self.text("import-handoff-manifest.v1/valid/one-file-representation.json")
        let tooLong = String(repeating: "x", count: 65)
        for (first, second) in [("1", tooLong), (tooLong, "1"), ("1", "2")] {
            let edited = text.replacingOccurrences(of: #""build_version": "1","#,
                                                   with: "\"build_version\": \"\(first)\", \"build_version\": \"\(second)\",")
            #expect(edited != text)
            #expect(throws: StrictJSON.Violation.self, "\(first.count) then \(second.count) characters") {
                try HandoffManifest.decode(Data(edited.utf8))
            }
        }
        let pack = try Self.text("sylviapack-manifest.v1/valid/publication-and-audiobook.json")
        let doubled = pack.replacingOccurrences(of: #""schema_version": 1,"#, with: #""schema_version": 1, "schema_version": 1,"#)
        #expect(doubled != pack)
        #expect(throws: StrictJSON.Violation.self) { try PackManifest.decode(Data(doubled.utf8)) }
    }
}
