import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

@Suite("Schema, identity and mutation rules (plan 7.2, 7.3)")
struct SchemaTests {
    @Test("fresh library: all migrations, WAL, foreign keys on, every table STRICT")
    func freshLibrary() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        defer { try? store.close() }
        #expect(store.openReport.appliedNow == LibrarySchema.migrations.map(\.identifier))
        #expect(try store.schemaVersion == LibrarySchema.currentVersion)
        try store.pool.read { (db: Database) throws in
            #expect(try String.fetchOne(db, sql: "PRAGMA journal_mode") == "wal")
            #expect(try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1)
            #expect(try LibraryChecks.integrity(db) == ["ok"])
            for table in LibrarySchema.tables.map(\.name) {
                let sql = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", arguments: [table])
                #expect(sql?.hasSuffix("STRICT") == true, "\(table) is not STRICT")
            }
            // The spike covers every entity the brief names.
            let required = ["work", "contributor", "work_contributor", "edition", "asset", "edition_asset", "asset_location",
                            "capture", "capture_anchor", "note", "note_revision", "retained_excerpt", "conversation", "message",
                            "context_pack", "context_evidence", "consumption_run", "ledger_event", "rating",
                            "recommendation_event", "change_journal", "export_record"]
            #expect(Set(required).isSubset(of: try LibraryChecks.existingTables(db)))
        }
        #expect(store.layout.databaseURL.path.contains("/Install/Library/library.sqlite"))
    }

    @Test("no column can hold a credential (secrets are Keychain-only, plan 17.1)")
    func noSecretColumns() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        defer { try? store.close() }
        let suspicious = try store.pool.read { (db: Database) throws in
            try LibrarySchema.tables.map(\.name).flatMap { table in
                try db.columns(in: table).map(\.name).filter { name in
                    ["key", "token", "secret", "password", "credential", "api_key"].contains { name.lowercased().contains($0) }
                        && name != "idempotency_key"
                }.map { "\(table).\($0)" }
            }
        }
        #expect(suspicious.isEmpty, "\(suspicious)")
    }

    @Test("rating: 1-10 half-stars, null clears, 0 and 11 rejected by code and by the schema")
    func rating() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let work = corpus.works["meditations"]!
        #expect(throws: ValidationError.invalidRating(0)) { try store.setRating(workID: work, value: 0) }
        #expect(throws: ValidationError.invalidRating(11)) { try store.setRating(workID: work, value: 11) }
        try store.setRating(workID: work, value: 1)
        try store.setRating(workID: work, value: 10)
        try store.setRating(workID: work, value: nil)
        try store.pool.read { (db: Database) throws in
            let row = try Row.fetchOne(db, sql: "SELECT value, scale FROM rating WHERE work_id = ?", arguments: [work])!
            #expect(row["value"] as Int? == nil)
            #expect(row["scale"] as String == "half_stars_1_10")
        }
        for bad in [0, 11, -1] {
            #expect(throws: DatabaseError.self) {
                try store.pool.write { try $0.execute(sql: "UPDATE rating SET value = ? WHERE work_id = ?", arguments: [bad, work]) }
            }
        }
    }

    @Test("STRICT typing, 64-bit sizes, digests and effective-date precision are enforced")
    func typing() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        try store.pool.read { (db: Database) throws in
            let size = try Int64.fetchOne(db, sql: "SELECT byte_count FROM asset WHERE id = ?", arguments: [corpus.assets["walden-audio"]!])
            #expect(size == corpus.remoteAssetBytes && corpus.remoteAssetBytes > Int64(UInt32.max))
            #expect(try String.fetchOne(db, sql: "SELECT typeof(byte_count) FROM asset LIMIT 1") == "integer")
        }
        let work = corpus.works["walden"]!
        // Text in an INTEGER column, a non-hex digest, a date without precision, a bad precision.
        let rejected: [String] = [
            "UPDATE work SET created_at_ms = 'yesterday' WHERE id = '\(work)'",
            "UPDATE asset SET sha256 = 'XYZ' WHERE id = '\(corpus.assets["walden-epub"]!)'",
            "UPDATE consumption_run SET started_date_precision = NULL WHERE work_id = '\(work)'",
            "UPDATE consumption_run SET started_date_precision = 'week' WHERE work_id = '\(work)'",
            "UPDATE asset_location SET local_relative_path = NULL WHERE availability = 'on_device'",
        ]
        for sql in rejected {
            #expect(throws: DatabaseError.self, "\(sql)") { try store.pool.write { try $0.execute(sql: sql) } }
        }
        #expect(throws: ValidationError.self) { try EffectiveDate("2019-13", precision: .month) }
        #expect(throws: ValidationError.self) { try EffectiveDate("2019-02-30", precision: .day) }
        #expect(throws: ValidationError.self) { try EffectiveDate("2019-02", precision: .year) }
        #expect(try EffectiveDate.month(2026, 9).value == "2026-09")
        #expect(try EffectiveDate.day(2024, 2, 29).value == "2024-02-29")

        // The schema checks the precision value and the null pairing, not the date text: that is
        // checked in code (`EffectiveDate`, and `RowCheck` for databases Sylvia did not write).
        #expect(try store.pool.read { try RowCheck.problems($0) }.isEmpty)
        try store.pool.write { try $0.execute(sql: "UPDATE consumption_run SET started_date = 'banana', started_date_precision = 'day' WHERE work_id = ?", arguments: [work]) }
        let problems = try store.pool.read { try RowCheck.problems($0) }
        #expect(problems.count == 1 && problems[0].contains("consumption_run.started_date") && problems[0].contains("'banana'"), "\(problems)")
        evidence("schema accepts started_date 'banana' with precision day; RowCheck reports: \(problems.joined(separator: "; "))")
    }

    @Test("every user-effective date column is paired with a precision column and checked by RowCheck")
    func everyEffectiveDateColumnIsChecked() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        defer { try? store.close() }
        let found = try store.pool.read { (db: Database) throws in
            try LibrarySchema.tables.map(\.name).flatMap { table in
                try db.columns(in: table).map(\.name).filter { $0.hasSuffix("_date") }.map { "\(table).\($0)" }
            }
        }
        #expect(Set(found) == Set(RowCheck.effectiveDateColumns.map { "\($0.table).\($0.date)" }), "\(found)")
        for pair in RowCheck.effectiveDateColumns {
            #expect(pair.precision == pair.date + "_precision")
        }
    }

    @Test("media removal can never cascade into knowledge: deleting media rows is refused (RESTRICT)")
    func restrictKnowledge() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let before = try store.pool.read { try LibraryChecks.knowledgeDump($0) }
        let attempts = [
            "DELETE FROM asset WHERE id = '\(corpus.assets["med-epub"]!)'",
            "DELETE FROM asset",
            "DELETE FROM edition WHERE id = '\(corpus.editions["med-audio"]!)'",
            "DELETE FROM work WHERE id = '\(corpus.works["meditations"]!)'",
            "DELETE FROM capture WHERE id = '\(corpus.captures["epub-quote"]!)'",
            "DELETE FROM context_pack",
        ]
        for sql in attempts {
            #expect(throws: DatabaseError.self, "\(sql) should be refused") { try store.pool.write { try $0.execute(sql: sql) } }
        }
        #expect(try store.pool.read { try LibraryChecks.knowledgeDump($0) } == before)
    }

    @Test("capture save is one transaction with anchors, note, ledger and journal; idempotent (T02)")
    func captureTransaction() throws {
        let scratch = try Scratch()
        let layout = scratch.layout()
        try CrashDrill.seed(layout, durability: .acknowledgedSaves)
        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        let first = try store.saveCapture(CrashDrill.command(1))
        guard case .saved = first else { Issue.record("expected saved"); return }
        let retry = try store.saveCapture(CrashDrill.command(1))
        #expect(retry == .alreadySaved(captureID: first.captureID))
        try store.pool.read { (db: Database) throws in
            #expect(try CrashDrill.verify(db, acknowledged: [1], checkContentOf: [1]).isEmpty)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM ledger_event WHERE event_type = 'capture_saved'") == 1)
        }
        // A failure inside the transaction leaves nothing behind, including no journal entry.
        let journalBefore = try store.pool.read { try Int.fetchOne($0, sql: "SELECT max(seq) FROM change_journal") }
        struct Boom: Error {}
        #expect(throws: Boom.self) { try store.saveCapture(CrashDrill.command(2), beforeCommit: { throw Boom() }) }
        try store.pool.read { (db: Database) throws in
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM capture WHERE idempotency_key = 'crash-2'") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM note_revision") == 1)
            #expect(try Int.fetchOne(db, sql: "SELECT max(seq) FROM change_journal") == journalBefore)
        }
        #expect(throws: ValidationError.emptyCapture) {
            var command = CrashDrill.command(3)
            command.anchors = []
            try store.saveCapture(command)
        }
    }

    @Test("ChangeJournal: one ordered local sequence, written in the mutation's transaction")
    func journal() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        try store.pool.read { (db: Database) throws in
            let seqs = try Int64.fetchAll(db, sql: "SELECT seq FROM change_journal ORDER BY rowid")
            #expect(seqs == seqs.sorted() && Set(seqs).count == seqs.count && !seqs.isEmpty)
            let noteOps = try String.fetchAll(db, sql: "SELECT operation || ':' || coalesce(revision, '') FROM change_journal WHERE entity = 'note' AND entity_id = ? ORDER BY seq",
                                              arguments: [corpus.notes["epub-quote"]!])
            #expect(noteOps == ["insert:1", "update:2", "update:3"])
            for table in ["work", "edition", "asset", "capture", "conversation", "context_pack", "message", "retained_excerpt"] {
                let missing = try Int.fetchOne(db, sql: """
                    SELECT count(*) FROM \(table) t WHERE NOT EXISTS (
                      SELECT 1 FROM change_journal j WHERE j.entity = '\(table)' AND j.entity_id = t.id)
                    """)
                #expect(missing == 0, "\(table) rows without a journal entry")
            }
        }
    }

    @Test("revision-checked note edits: a stale editor cannot overwrite a later edit (T26)")
    func staleEditor() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let note = corpus.notes["epub-quote"]!
        #expect(throws: StoreError.staleRevision(noteID: note, expected: 1, current: 3)) {
            try store.reviseNote(note, expectedRevision: 1, body: "stale editor text")
        }
        #expect(try store.reviseNote(note, expectedRevision: 3, body: "fresh") == 4)
        let bodies = try store.pool.read { try String.fetchAll($0, sql: "SELECT body FROM note_revision WHERE note_id = ? ORDER BY revision", arguments: [note]) }
        #expect(bodies.count == 4 && bodies.first == "First thought." && bodies.last == "fresh")
    }
}
