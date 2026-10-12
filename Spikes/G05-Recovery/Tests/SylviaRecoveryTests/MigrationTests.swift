import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

@Suite("Migrations (plan 7.4, T45)")
struct MigrationTests {
    static var fixture: URL {
        Bundle.module.url(forResource: "library-v1", withExtension: "sqlite", subdirectory: "Fixtures")!
    }

    /// Tables whose shape v2 does not change; their rows must be identical after migrating.
    static let unchangedTables = LibrarySchema.knowledgeTables.filter { !["rating", "recommendation_event", "edition"].contains($0) }

    /// v2 adds the two cover-thumbnail columns to `edition`; every v1 column must be unchanged.
    static let editionV1Columns = ["abridged", "created_at_ms", "id", "identifiers_json", "language_tag", "medium", "narrator",
                                   "page_count", "published_date", "published_date_precision", "publisher", "work_id"]

    static func editionV1Dump(_ db: Database) throws -> String {
        try Row.fetchAll(db, sql: "SELECT \(editionV1Columns.joined(separator: ", ")) FROM edition ORDER BY id").map { row in
            editionV1Columns.map { "\($0)=\(CanonicalValue.render(row[$0] as DatabaseValue))" }.joined(separator: "|")
        }.joined(separator: "\n")
    }

    /// The rows v2 must keep exactly: every unchanged table plus the v1 columns of `edition`.
    static func preservedDump(_ db: Database) throws -> String {
        try LibraryChecks.canonicalDump(db, tables: unchangedTables) + "## edition (v1 columns)\n" + editionV1Dump(db)
    }

    func installV1(_ scratch: Scratch, mutate: ((Database) throws -> Void)? = nil) throws -> LibraryLayout {
        let layout = scratch.layout()
        try LibraryStore.prepareDirectories(layout, protector: .library)
        try FileManager.default.copyItem(at: Self.fixture, to: layout.databaseURL)
        if let mutate {
            let queue = try DatabaseQueue(path: layout.databaseURL.path)
            try queue.write(mutate)
            try queue.close()
        }
        return layout
    }

    func readOnly(_ layout: LibraryLayout) throws -> (applied: [String], dump: String, all: String) {
        let queue = try RecoveryAccess.openReadOnly(layout.databaseURL)
        defer { try? queue.close() }
        return try queue.read { (db: Database) throws in
            (try LibrarySchema.applied(db),
             try Self.preservedDump(db),
             try LibraryChecks.knowledgeDump(db))
        }
    }

    @Test("committed v1 fixture upgrades to v2 with a recovery snapshot, integrity and foreign-key checks")
    func upgradeFixture() throws {
        let scratch = try Scratch()
        let layout = try installV1(scratch)
        let before = try readOnly(layout)
        #expect(before.applied == ["v1-initial"])

        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        #expect(store.openReport.appliedBefore == ["v1-initial"])
        #expect(store.openReport.appliedNow == LibrarySchema.migrations.map(\.identifier))
        let snapshot = try #require(store.openReport.recoverySnapshot)
        let snapshotQueue = try RecoveryAccess.openReadOnly(snapshot)
        let snapshotState = try snapshotQueue.read { (db: Database) throws in
            (try LibrarySchema.applied(db), try LibraryChecks.knowledgeDump(db), try LibraryChecks.integrity(db))
        }
        try snapshotQueue.close()
        #expect(snapshotState.0 == ["v1-initial"] && snapshotState.1 == before.all && snapshotState.2 == ["ok"],
                "recovery snapshot must equal the pre-migration library")

        try store.pool.read { (db: Database) throws in
            #expect(try LibraryChecks.integrity(db) == ["ok"])
            #expect(try LibraryChecks.foreignKeyViolations(db).isEmpty)
            #expect(try Self.preservedDump(db) == before.dump)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM edition WHERE cover_thumbnail_sha256 IS NOT NULL OR cover_thumbnail_extension IS NOT NULL") == 0)
            let precisions = try Row.fetchAll(db, sql: "SELECT event_date, event_date_precision FROM recommendation_event ORDER BY event_date")
                .map { "\($0["event_date"] as String)=\($0["event_date_precision"] as String)" }
            #expect(precisions == ["2019=year", "2024-05=month", "2026-09-14=day"])
            #expect(try db.columns(in: "rating").contains { $0.name == "review_note" })
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM rating") == 2)
        }
        evidence("v1 fixture upgraded: \(store.openReport.appliedNow.joined(separator: " -> ")); snapshot \(snapshot.lastPathComponent)")
    }

    @Test("insufficient space: migration refused, library logically unchanged, no snapshot written")
    func insufficientSpace() throws {
        let scratch = try Scratch()
        let layout = try installV1(scratch)
        let before = try readOnly(layout)
        var options = StoreOptions()
        options.space = FixedSpaceProbe(bytes: 1024)
        #expect {
            _ = try LibraryStore.open(layout, options: options)
        } throws: { error in
            guard case StoreError.insufficientSpace(let required, let available) = error else { return false }
            return available == 1024 && required > 1024
        }
        let after = try readOnly(layout)
        #expect(after.applied == before.applied && after.all == before.all)
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.recoveryDirectory.path).isEmpty)
    }

    @Test("a migration that throws: snapshot put back, data readable for export, retry succeeds")
    func failedMigration() throws {
        let scratch = try Scratch()
        let layout = try installV1(scratch)
        let before = try readOnly(layout)
        var options = StoreOptions()
        options.faults.throwDuringRecommendationRebuild = true
        #expect(throws: StoreError.migrationFailed(identifier: "v2-recommendation-date-precision",
                                                   reason: "injected fault during v2-recommendation-date-precision",
                                                   restoredFromSnapshot: true)) {
            _ = try LibraryStore.open(layout, options: options)
        }
        // Not an empty library: the pre-migration state is back and readable (the recovery screen).
        let after = try readOnly(layout)
        #expect(after.applied == ["v1-initial"])
        #expect(after.all == before.all)
        let kept = try FileManager.default.contentsOfDirectory(atPath: layout.recoveryDirectory.path)
        #expect(kept.contains { $0.hasPrefix("failed-") } && kept.contains { $0.hasPrefix("pre-migration-") })

        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        #expect(try store.schemaVersion == 2)
        #expect(try store.pool.read { try Self.preservedDump($0) } == before.dump)
    }

    @Test("a migration that silently loses rows is caught by the post-migration count check")
    func lossyMigration() throws {
        let scratch = try Scratch()
        let layout = try installV1(scratch)
        let before = try readOnly(layout)
        var options = StoreOptions()
        options.faults.dropRowsDuringRecommendationRebuild = true
        #expect {
            _ = try LibraryStore.open(layout, options: options)
        } throws: { error in
            guard case StoreError.postMigrationCheckFailed(let reason, true) = error else { return false }
            return reason.contains("recommendation_event")
        }
        let after = try readOnly(layout)
        #expect(after.applied == ["v1-initial"] && after.all == before.all)
    }

    @Test("a value the migration cannot convert fails it instead of being dropped")
    func unconvertibleValue() throws {
        let scratch = try Scratch()
        let layout = try installV1(scratch) { (db: Database) throws in
            try db.execute(sql: "UPDATE recommendation_event SET event_date = 'around 2019' WHERE event_date = '2019'")
        }
        let before = try readOnly(layout)
        #expect {
            _ = try LibraryStore.open(layout)
        } throws: { error in
            guard case StoreError.migrationFailed(let id, _, true) = error else { return false }
            return id == "v2-recommendation-date-precision"
        }
        let after = try readOnly(layout)
        #expect(after.all == before.all && after.all.contains("around 2019"))
    }

    @Test("a library from a newer build is refused without changes")
    func newerSchema() throws {
        let scratch = try Scratch()
        let (store, _) = try corpusLibrary(scratch)
        try store.pool.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v3-future-table')") }
        let before = try store.pool.read { try LibraryChecks.knowledgeDump($0) }
        try store.close()
        #expect(throws: StoreError.newerSchema(unknownMigrations: ["v3-future-table"])) {
            _ = try LibraryStore.open(scratch.layout())
        }
        let queue = try RecoveryAccess.openReadOnly(scratch.layout().databaseURL)
        #expect(try queue.read { try LibraryChecks.knowledgeDump($0) } == before)
        try queue.close()
    }
}
