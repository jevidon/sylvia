import Foundation
import SylviaIntakeCore
@testable import SylviaPack
import Testing

/// A "/" followed by a combining mark (U+0301), or preceded by a prepended concatenation mark (U+0600), forms one Swift
/// `Character` with that mark (Unicode UAX #29 rules GB9 and GB9b). Character-based String operations (`split`,
/// `hasPrefix`, `contains`, `==`) therefore do not see such a "/" as a separator, while the file system, the contract's
/// pattern and every other reader do. Path rules must work on bytes. Found while closing G0.3 review round 3 (report
/// finding F18): the reader accepted "../" + U+0301 + "x", and extraction wrote that file into the parent of its
/// extraction directory.
@Suite("sylviapack paths: separators are bytes, not Characters (T13)", .removesTemporaryFiles)
struct PackPathSeparatorTests {
    static let acute = "\u{301}"        // COMBINING ACUTE ACCENT: "/" + it is one Character
    static let numberSign = "\u{600}"   // ARABIC NUMBER SIGN (Prepend): it + "/" is one Character

    @Test("the platform fact: a slash inside a grapheme cluster is invisible to Character-based String operations")
    func platformFact() {
        let path = "../" + Self.acute + "x"
        #expect(path.split(separator: "/").count == 1)
        #expect(!path.contains("/"))
        #expect(!("/" + Self.acute + "x").hasPrefix("/"))
        #expect(path.utf8.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false).count == 2)
    }

    /// (label, manifest path, the pack's rejection code). The pack whose entry name ends in a "/" byte is refused as a
    /// directory entry by the structure check, which runs before the name rules.
    static let hiddenSeparatorPaths: [(String, String, PackRejection.Code)] = [
        ("traversal: '..' then a slash carrying a combining mark", "../" + acute + "escape.md", .unsafePath),
        ("traversal in the middle", "Walden/../" + acute + "escape.md", .unsafePath),
        ("a '.' component", "./" + acute + "dot.md", .unsafePath),
        ("absolute: a leading slash carrying a combining mark", "/" + acute + "escape.md", .unsafePath),
        ("an empty component", "Walden//" + acute + "x.md", .unsafePath),
        ("an empty last component after a prepended mark", "Walden/x" + numberSign + "/", .specialEntry),
        ("16 components joined by slashes that carry combining marks",
         (1...16).map { "d\($0)" }.joined(separator: "/" + acute) + ".md", .unsafePath),
        ("16 components joined by slashes after prepended marks",
         (1...16).map { "d\($0)" + numberSign }.joined(separator: "/") + ".md", .unsafePath),
    ]

    @Test("manifest paths whose separators hide inside a grapheme cluster are refused",
          arguments: PackPathSeparatorTests.hiddenSeparatorPaths)
    func hiddenSeparatorsInManifestPaths(label: String, path: String, code: PackRejection.Code) async throws {
        #expect(throws: PackRejection.self, "\(label): PackPath") { try PackPath.validateManifestPath(path) }
        #expect(throws: PackRejection.self, "\(label): entry name") { try PackPath.validate(PackLayout.contentPrefix + path) }
        var fixture = PackFixture.standard()
        fixture.files[0].path = path   // the entry name is content/ + the same path
        #expect(try await verdict(fixture.rawZip().build()) == code, "\(label)")
    }

    @Test("a file that is also used as a folder is refused when the separator hides inside a grapheme cluster")
    func hiddenFileFolderConflict() async throws {
        var fixture = PackFixture.standard()
        fixture.files.append(("Walden/notes.md/" + Self.acute + "inside.txt", Data("x".utf8), .text, "text/plain"))
        #expect(try await verdict(fixture.rawZip().build()) == .pathConflict)
        #expect(throws: PackRejection(.pathConflict, "a file is also used as a folder")) {
            try PackPath.checkNoFileDirectoryConflicts(["a", "a/" + Self.acute + "b"])
        }
    }

    @Test("an entry name ending in a slash after a prepended mark is a directory entry and is refused")
    func hiddenDirectoryEntry() async throws {
        var zip = try PackFixture.standard().rawZip()
        zip.entries.append(RawEntry("content/Walden/x" + Self.numberSign + "/", Data()))
        let code = try await verdict(zip.build())
        #expect(code == .specialEntry || code == .unsafePath, "\(String(describing: code))")
        #expect(throws: PackRejection.self) {
            _ = try PackStructure.checkEntryType(versionMadeBy: 3 << 8 | 63, externalAttributes: 0o100644 << 16,
                                                 name: "content/x" + Self.numberSign + "/")
        }
    }

    @Test("extraction never writes outside its directory: a hidden '..' is refused before anything is written")
    func extractionStaysInside() async throws {
        let dir = try temporaryDirectory()
        let parent = dir.appendingPathComponent("parent", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var fixture = PackFixture.standard()
        fixture.files[0].path = "../" + Self.acute + "escape.md"
        let pack = dir.appendingPathComponent("hostile.sylviapack")
        try fixture.rawZip().build().write(to: pack)
        let destination = parent.appendingPathComponent("extract", isDirectory: true)
        let escaped = parent.appendingPathComponent(Self.acute + "escape.md")
        do {
            _ = try await PackReader().extract(pack, to: destination)
            Issue.record("the hostile pack was extracted")
        } catch {
            #expect(error.code == .unsafePath)
        }
        let leaked = (try? Durability.lstatInfo(escaped)) != nil
        print("hidden-separator extraction: file written outside the extraction directory: \(leaked)")
        #expect(!leaked, "a file was written outside the extraction directory")
        #expect(try Durability.lstatInfo(destination) == nil)
    }

    @Test("the byte-level rules still accept ordinary non-ASCII paths, including combining marks inside a component")
    func ordinaryPathsStillAccepted() async throws {
        for path in ["Walden/caf\u{E9}.md", "Walden/x" + Self.acute + "y.md", "\u{1F4D6}/Walden.md", "Walden/" + Self.numberSign + "1.md"] {
            #expect(throws: Never.self, "\(path.debugDescription)") { try PackPath.validateManifestPath(path) }
        }
        var fixture = PackFixture.standard()
        fixture.files[0].path = "Walden/caf\u{E9}.md"
        #expect(try await verdict(fixture.rawZip().build()) == nil)
    }
}
