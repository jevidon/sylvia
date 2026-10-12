import Foundation
import Testing
@testable import SylviaRecovery

/// The Swift reader enforces the `backup-manifest.v1` contract itself, not only the parts the
/// file checks need: every committed contract fixture goes through `BackupValidator.validateManifest`,
/// the manifest stage a restore runs before it reads any other file.
@Suite("Backup manifest reader agrees with the contract (Contracts/schemas/backup-manifest.v1)")
struct ManifestContractTests {
    static let fixtures: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Contracts/fixtures/backup-manifest.v1", directoryHint: .isDirectory)

    static var fixturesReadable: Bool {
        FileManager.default.isReadableFile(atPath: fixtures.appending(path: "valid/empty-library-complete.json").path)
    }

    /// The precise error each invalid fixture must produce; one reason per fixture, as in the contract.
    static let expected: [String: BackupError] = [
        "absolute-path.json": .unsafePath("/etc/passwd"),
        "backslash-path.json": .unsafePath("export\\markdown\\x.md"),
        "blob-path-not-digest.json": .roleMismatch(path: "blobs/excerpts/clip.mp3", role: "retained_excerpt"),
        "complete-with-excluded-media.json": .invalidField("complete"),
        "cover-unsupported-extension.json": .roleMismatch(
            path: "blobs/covers/9c1e5a7b3d2f4e6a8c0b1d3f5e7a9c2b4d6f8a0c1e3b5d7f9a2c4e6b8d0f1a3c.gif", role: "cover_thumbnail"),
        "database-role-on-other-path.json": .roleMismatch(path: "export/other.sqlite", role: "database_snapshot"),
        "dot-component-path.json": .unsafePath("export/markdown/../../x.md"),
        "duplicate-migration.json": .invalidField("library.migrations"),
        "encryption-claimed.json": .invalidField("encryption"),
        "incomplete-without-excluded-media.json": .invalidField("complete"),
        "negative-byte-count.json": .invalidField("files.byte_count"),
        "newer-manifest-version.json": .unsupportedManifestVersion(2),
        "no-database-snapshot.json": .databaseCount(0),
        "non-utc-created-at.json": .invalidField("created_at"),
        "path-traversal.json": .unsafePath("../outside.md"),
        "unknown-snapshot-method.json": .invalidField("snapshot.method"),
        "unknown-storage-class.json": .invalidField("included_classes"),
        "uppercase-digest.json": .invalidField("files.sha256"),
        "uppercase-uuid.json": .invalidField("backup_id"),
    ]

    @Test("every valid contract fixture passes the reader's manifest stage",
          .enabled(if: fixturesReadable, "the repository's Contracts/ directory is not readable from this test process"))
    func validFixtures() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.appending(path: "valid").path).filter { $0.hasSuffix(".json") }.sorted()
        #expect(!names.isEmpty)
        for name in names {
            let data = try Data(contentsOf: Self.fixtures.appending(path: "valid/\(name)"))
            do { _ = try BackupValidator.validateManifest(data) } catch { Issue.record("\(name): \(error)") }
        }
        evidence("contract valid fixtures accepted by the Swift reader: \(names.joined(separator: ", "))")
    }

    @Test("every invalid contract fixture is rejected by the reader for its one reason",
          .enabled(if: fixturesReadable, "the repository's Contracts/ directory is not readable from this test process"))
    func invalidFixtures() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.appending(path: "invalid").path).filter { $0.hasSuffix(".json") }.sorted()
        // A new fixture without an expected error fails here rather than being skipped.
        #expect(Set(names) == Set(Self.expected.keys).union(["missing-originating-device.json"]))
        for name in names {
            let data = try Data(contentsOf: Self.fixtures.appending(path: "invalid/\(name)"))
            var thrown: (any Error)?
            do { _ = try BackupValidator.validateManifest(data) } catch { thrown = error }
            guard let error = thrown as? BackupError else {
                Issue.record("\(name): expected a BackupError, got \(String(describing: thrown))"); continue
            }
            if name == "missing-originating-device.json" {
                // A missing required field fails decoding; the message names the field.
                guard case .manifestUnreadable(let why) = error, why.contains("originating_device_id") else {
                    Issue.record("\(name): unexpected error \(error)"); continue
                }
            } else {
                #expect(error == Self.expected[name], "\(name): got \(error)")
            }
            evidence("contract invalid fixture \(name): rejected: \(error)")
        }
    }
}
