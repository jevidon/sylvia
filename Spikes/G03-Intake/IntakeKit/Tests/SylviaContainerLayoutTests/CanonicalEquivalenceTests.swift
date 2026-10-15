import Foundation
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack
import Testing

/// G0.3 review R4-01: what Swift's canonical equivalence can and cannot do to the manifest readers.
///
/// Swift compares `String`s by canonical equivalence (`==`, `Set`, `Dictionary`, `switch`, `init(rawValue:)`), and so
/// does JSONDecoder when it matches member names to coding keys and decodes a `String` enum. JSON Schema compares code
/// points. The readers therefore compare manifest text byte for byte, or look it up only once the schema's pattern has
/// proved it ASCII. What remains outside the readers' own code is JSONDecoder's member-name matching; the tests below
/// show it cannot confuse any member of the two contracts: a non-ASCII spelling of ASCII text must decompose to ASCII
/// code point by code point (canonical reordering moves combining marks but never removes one), only three code points
/// do, and none of the contracts' names, enum values or constants contains the three characters they stand for.
@Suite("canonical equivalence: what Swift equates, and why the contracts' names cannot be confused", .removesTemporaryFiles)
struct CanonicalEquivalenceTests {
    enum Probe: String, Decodable { case k = "K" }
    struct MemberProbe: Decodable { let K: Int }
    struct ValueProbe: Decodable { let e: Probe }

    enum Exact: String, CaseIterable, Decodable {
        case k = "K"
        init(from decoder: any Decoder) throws { self = try decodeExactCase(Self.self, from: decoder) }
    }
    struct ExactProbe: Decodable { let e: Exact }

    @Test("platform facts (recorded): ==, init(rawValue:) and JSONDecoder's member names and enum values all take U+212A for K")
    func platformFacts() {
        let kelvin = "\u{212A}"
        let equal = kelvin == "K"
        let rawValue = Probe(rawValue: kelvin)
        let member = try? JSONDecoder().decode(MemberProbe.self, from: Data(#"{"\u212A": 1}"#.utf8))
        let value = try? JSONDecoder().decode(ValueProbe.self, from: Data(#"{"e": "\u212A"}"#.utf8))
        print("platform canonical equivalence: \"\\u{212A}\" == \"K\": \(equal); init(rawValue:) gives \(String(describing: rawValue)); JSONDecoder matches the member \"\\u212A\" to the key K: \(member != nil); decodes the enum value \"\\u212A\" as K: \(value?.e == .k)")
        #expect(equal)
        #expect(rawValue == .k)
        #expect(member != nil)
        #expect(value?.e == .k)
    }

    @Test("decodeExactCase, which the readers' enums use, refuses the canonical twin and takes the exact value")
    func exactEnumDecoding() {
        #expect((try? JSONDecoder().decode(ExactProbe.self, from: Data(#"{"e": "K"}"#.utf8)))?.e == .k)
        #expect((try? JSONDecoder().decode(ExactProbe.self, from: Data(#"{"e": "\u212A"}"#.utf8))) == nil)
        // The readers' own enums still decode every value they define.
        for kind in PackManifest.Kind.allCases {
            #expect((try? JSONDecoder().decode([PackManifest.Kind].self, from: Data("[\"\(kind.rawValue)\"]".utf8))) == [kind])
        }
        for kind in PackManifest.GroupKind.allCases {
            #expect((try? JSONDecoder().decode([PackManifest.GroupKind].self, from: Data("[\"\(kind.rawValue)\"]".utf8))) == [kind])
        }
        for basis in PackManifest.MemberOrderBasis.allCases {
            #expect((try? JSONDecoder().decode([PackManifest.MemberOrderBasis].self, from: Data("[\"\(basis.rawValue)\"]".utf8))) == [basis])
        }
        for representation in HandoffManifest.Representation.allCases {
            #expect((try? JSONDecoder().decode([HandoffManifest.Representation].self, from: Data("[\"\(representation.rawValue)\"]".utf8))) == [representation])
        }
    }

    @Test("only three non-ASCII code points are canonically equivalent to ASCII text: U+037E (;), U+1FEF (`) and U+212A (K)")
    func asciiTwins() {
        // Foundation's canonical decomposition, over every code point ...
        var decomposingToASCII: [UInt32: String] = [:]
        // ... and Swift's own String equality (its hashing agrees with ==), against every ASCII character.
        let ascii = Set((0..<128).map { String(Unicode.Scalar(UInt8($0))) })
        var equalToASCII: [UInt32] = []
        for value in UInt32(0x80)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let text = String(scalar)
            let decomposed = text.decomposedStringWithCanonicalMapping
            if decomposed.unicodeScalars.allSatisfy(\.isASCII) { decomposingToASCII[value] = decomposed }
            if ascii.contains(text) { equalToASCII.append(value) }
        }
        print("canonical twins of ASCII: Foundation \(decomposingToASCII.keys.sorted().map { "U+" + String($0, radix: 16, uppercase: true) }); Swift == \(equalToASCII.map { "U+" + String($0, radix: 16, uppercase: true) })")
        #expect(decomposingToASCII == [0x037E: ";", 0x1FEF: "`", 0x212A: "K"])
        #expect(equalToASCII == [0x037E, 0x1FEF, 0x212A])
    }

    @Test("no member name, enum value or constant of either G0.3 contract holds ;, ` or K, so no other spelling can match one")
    func contractNamesHaveNoTwins() throws {
        let schemas = ContractFixtureTests.contracts.deletingLastPathComponent().appendingPathComponent("schemas")
        var names: Set<String> = []
        var values: Set<String> = []
        func walk(_ node: Any) {
            if let object = node as? [String: Any] {
                if let properties = object["properties"] as? [String: Any] { names.formUnion(properties.keys) }
                if let required = object["required"] as? [String] { names.formUnion(required) }
                if let options = object["enum"] as? [Any] { values.formUnion(options.compactMap { $0 as? String }) }
                if let constant = object["const"] as? String { values.insert(constant) }
                object.values.forEach(walk)
            } else if let array = node as? [Any] {
                array.forEach(walk)
            }
        }
        for contract in ["sylviapack-manifest.v1", "import-handoff-manifest.v1"] {
            let url = schemas.appendingPathComponent("\(contract).schema.json")
            walk(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
        }
        let twins: Set<UInt8> = [UInt8(ascii: ";"), UInt8(ascii: "`"), UInt8(ascii: "K")]
        let offending = names.union(values).filter { text in
            text.utf8.contains(where: { twins.contains($0) }) || !text.utf8.allSatisfy { $0 < 0x80 }
        }
        print("contract names checked: \(names.count) member names, \(values.count) enum values and constants; holding ;, ` or K, or non-ASCII: \(offending.sorted())")
        #expect(names.count > 30 && values.count > 10, "the walk found the schemas' names")
        #expect(offending.isEmpty)
    }
}
