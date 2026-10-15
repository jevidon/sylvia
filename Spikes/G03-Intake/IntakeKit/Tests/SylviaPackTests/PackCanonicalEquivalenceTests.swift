import CryptoKit
import Foundation
import SylviaIntakeCore
@testable import SylviaPack
import Testing

/// G0.3 review R4-01: Swift's `String` equality, hashing and therefore `Dictionary` lookup treat canonically equivalent
/// text as equal, and U+212A KELVIN SIGN is canonically equivalent to "K". A file `group_id` of "WALDEN_" + U+212A
/// found the group "WALDEN_K", so the manifest reader, the writer's own check and extraction all accepted a pack whose
/// manifest the schema refuses: the contract's `group_id` pattern `^[A-Za-z0-9_-]{1,64}$` compares code points. The
/// reader now applies the pattern to a file's `group_id` before the lookup. The same inputs go through the schema in
/// Spikes/G03-Intake/scripts/contract_differential.py (cases `group_id-kelvin-*`).
@Suite("a file's group_id must name its group exactly: canonically equivalent spellings are refused", .removesTemporaryFiles)
struct PackCanonicalEquivalenceTests {
    static let kelvin = "\u{212A}"

    /// The standard fixture with its audiobook group named `audiobook` and its members pointing at `members`, plus a
    /// publication group `publication` that the Markdown file points at as `publicationMember`.
    static func fixture(audiobook: String = "MEDITATIONS_K", members: String = "MEDITATIONS_K",
                        publication: String = "WALDEN_K", publicationMember: String = "WALDEN_K") -> PackFixture {
        var fixture = PackFixture.standard()
        fixture.groups = fixture.groups.map { group in
            var renamed = group
            renamed.groupID = audiobook
            return renamed
        } + [.init(groupID: publication, kind: .publication, title: "Walden")]
        fixture.groupOf = fixture.groupOf.mapValues { (members, $0.1) }
        fixture.groupOf["Walden/notes.md"] = (publicationMember, nil)
        return fixture
    }

    @Test("platform fact (recorded): Swift's ==, Set and Dictionary take U+212A for K; byte comparison does not")
    func platformFact() {
        let twin = "WALDEN_" + Self.kelvin
        #expect(twin == "WALDEN_K")
        #expect(Set(["WALDEN_K"]).contains(twin))
        #expect(["WALDEN_K": 1][twin] == 1)
        #expect(!PathBytes.equal(twin, "WALDEN_K"))
        print("canonical equivalence: \"WALDEN_\\u{212A}\" == \"WALDEN_K\" is \(twin == "WALDEN_K"); as bytes: \(PathBytes.equal(twin, "WALDEN_K"))")
    }

    @Test("the manifest reader refuses a file group_id that is a canonical twin of its group's, for audiobook members and a publication")
    func readerRefuses() throws {
        let limits = PackLimits()
        let control = Self.fixture().manifest()
        #expect(throws: Never.self) { try control.validate(limits: limits) }
        for (label, manifest) in [
            ("audiobook members", Self.fixture(members: "MEDITATIONS_" + Self.kelvin).manifest()),
            ("publication member", Self.fixture(publicationMember: "WALDEN_" + Self.kelvin).manifest()),
        ] {
            #expect(throws: PackRejection(.manifestInvalid, "files.group_id"), "\(label)") { try manifest.validate(limits: limits) }
        }
        // A group whose own id holds the twin was already refused by the group check.
        #expect(throws: PackRejection(.manifestInvalid, "group_id")) {
            try Self.fixture(publication: "WALDEN_" + Self.kelvin).manifest().validate(limits: limits)
        }
        // Decoded from text, as the reader sees it (the escape and the raw character alike).
        for spelling in [#"\u212A"#, Self.kelvin] {
            let text = try String(decoding: Self.fixture().manifest().encoded(), as: UTF8.self)
                .replacingOccurrences(of: "\"group_id\" : \"WALDEN_K\",\n      \"kind\" : \"markdown\"",
                                      with: "\"group_id\" : \"WALDEN_\(spelling)\",\n      \"kind\" : \"markdown\"")
            #expect(text.contains("WALDEN_\(spelling)"))
            let decoded = try PackManifest.decode(Data(text.utf8), limits: limits)
            #expect(throws: PackRejection(.manifestInvalid, "files.group_id")) { try decoded.validate(limits: limits) }
        }
    }

    @Test("the writer refuses such a manifest before writing anything")
    func writerRefuses() async throws {
        let dir = try temporaryDirectory()
        let fixture = Self.fixture(members: "MEDITATIONS_" + Self.kelvin)
        var sources: [PackSource] = []
        for file in fixture.files {
            let url = dir.appendingPathComponent("src-\(sources.count)")
            try file.data.write(to: url)
            sources.append(PackSource(url: url, path: file.path, kind: file.kind, mediaType: file.mediaType,
                                      groupID: fixture.groupOf[file.path]?.0, order: fixture.groupOf[file.path]?.1))
        }
        let destination = dir.appendingPathComponent("kelvin.sylviapack")
        await #expect(throws: PackWriterError.invalidInput(PackRejection(.manifestInvalid, "files.group_id"))) {
            try await PackWriter().write(sources: sources, groups: fixture.groups, to: destination)
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("src-") }
        #expect(left.isEmpty, "nothing written: \(left)")
    }

    @Test("a pack whose manifest holds such a group_id is refused by validation and by extraction, which writes nothing")
    func readerRefusesThePack() async throws {
        let dir = try temporaryDirectory()
        let url = dir.appendingPathComponent("kelvin.sylviapack")
        try Self.fixture(members: "MEDITATIONS_" + Self.kelvin).rawZip().build().write(to: url)
        await #expect(throws: PackRejection(.manifestInvalid, "files.group_id")) { try await PackReader().validate(url) }
        let destination = dir.appendingPathComponent("extracted")
        await #expect(throws: PackRejection(.manifestInvalid, "files.group_id")) {
            try await PackReader().extract(url, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        // Control: the same pack with the ASCII K extracts.
        #expect(try await verdict(Self.fixture().rawZip().build()) == nil)
    }
}
