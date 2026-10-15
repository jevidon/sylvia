import Foundation
import SylviaContainerLayout
import SylviaImportHandoff
import SylviaIntakeCore
import Testing

/// The handoff reader and the drop area apply the same byte-level separator rule as the pack reader
/// (PackPathSeparatorTests): a "/" followed by a combining mark is one Swift `Character` with it, so Character-based
/// `contains("/")` and `hasPrefix` do not see it, while the schema's pattern and the file system do (report F18).
@Suite("separators are bytes, not Characters: handoff file names and drop-area names", .removesTemporaryFiles)
struct PathSeparatorTests {
    @Test("a handoff manifest whose original_filename holds a slash inside a grapheme cluster is refused, as the schema refuses it")
    func handoffOriginalFilename() throws {
        let url = ContractFixtureTests.contracts.appendingPathComponent("import-handoff-manifest.v1/valid/one-file-representation.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var items = try #require(object["items"] as? [[String: Any]])
        for name in ["Meditations/\u{301}.epub", "/\u{301}Meditations.epub", "Meditations\u{600}/.epub"] {
            items[0]["original_filename"] = name
            object["items"] = items
            let manifest = try HandoffManifest.decode(JSONSerialization.data(withJSONObject: object))
            #expect(throws: HandoffManifestError.invalidField("original_filename"), "\(name.debugDescription)") {
                try manifest.validate(directoryName: manifest.handoffID.uuidString)
            }
        }
    }

    @Test("drop-area names: a slash inside a grapheme cluster cannot reach a file outside Documents")
    func dropAreaNames() async throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let outside = c.root.appendingPathComponent("\u{301}outside.epub")   // beside Documents, not in it
        try Data("not in the drop area".utf8).write(to: outside)
        let name = "../\u{301}outside.epub"
        #expect(throws: DropAreaImporter.ImportError.notInDropArea) { try importer.removeFromDropArea(named: name) }
        await #expect(throws: DropAreaImporter.ImportError.notInDropArea) { try await importer.importDropAreaItem(named: name) }
        #expect(FileManager.default.fileExists(atPath: outside.path), "the file outside Documents must be untouched")
        #expect(importer.journal.jobs.isEmpty)
    }
}
