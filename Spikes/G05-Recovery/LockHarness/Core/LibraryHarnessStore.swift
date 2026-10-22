import Foundation
import GRDB
import SylviaRecovery

/// The library under test: the G0.5 recovery spike's `LibraryStore`, opened with D17's class (class C, from the
/// configuration) and durability (`DurabilityPolicy.acknowledgedSaves`: WAL, synchronous=FULL, fullfsync, read back on
/// every open), saving the crash drill's captures (`CrashDrill.command`), each with two anchors, a note and its ledger
/// and journal entries in one transaction.
@MainActor
public final class LibraryHarnessStore: HarnessStore {
    public let layout: LibraryLayout
    public let protector: FileProtector
    private var store: LibraryStore?

    public init(layout: LibraryLayout, configuration: HarnessConfiguration) {
        self.layout = layout
        self.protector = FileProtector(protection: configuration.protection)
    }

    public var isOpen: Bool { store != nil }

    private var options: StoreOptions {
        var options = StoreOptions()
        options.durability = .acknowledgedSaves
        options.protector = protector
        return options
    }

    public func open() throws -> String {
        if let store { return store.openReport.durability }
        let store = try LibraryStore.open(layout, options: options)
        do {
            // The crash drill's one work, which every capture refers to (`CrashDrill.seed` does the same with the
            // library's default protector; this keeps the configuration's).
            try store.pool.write { db in
                if try Bool.fetchOne(db, sql: "SELECT 1 FROM work WHERE id = ?", arguments: [CrashDrill.seedWorkID]) == nil {
                    try store.insertJournaled(db, "work", id: CrashDrill.seedWorkID, [
                        "id": CrashDrill.seedWorkID, "title": "Crash drill", "sort_title": "crash drill", "description": nil,
                        "language_tag": "en", "metadata_revision": 1, "created_at_ms": 0, "updated_at_ms": 0, "deleted_at_ms": nil,
                    ])
                }
            }
        } catch {
            try? store.close()
            throw error
        }
        self.store = store
        return store.openReport.durability
    }

    public func close() {
        try? store?.close()
        store = nil
    }

    public func save(item: Int) throws -> SaveResult {
        guard let store else { throw HarnessError.storeNotOpen }
        switch try store.saveCapture(CrashDrill.command(item)) {
        case .saved: return .saved
        case .alreadySaved: return .alreadySaved
        }
    }

    public func readBack(item: Int) throws -> ReadBack {
        guard let store else { throw HarnessError.storeNotOpen }
        let key = CrashDrill.key(item)
        let row = try store.pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT c.quoted_text AS quote, r.body AS note,
                       (SELECT count(*) FROM capture WHERE idempotency_key = ?) AS copies
                FROM capture c JOIN note n ON n.capture_id = c.id JOIN note_revision r ON r.note_id = n.id
                WHERE c.idempotency_key = ?
                """, arguments: [key, key])
        }
        guard let row else { return .missing }
        let copies: Int = row["copies"]
        let quote: String? = row["quote"]
        let note: String? = row["note"]
        return copies == 1 && quote == CrashDrill.quote(item) && note == CrashDrill.comment(item) ? .equal : .differs
    }

    public func verify(acknowledged: Int) throws -> VerifyReport {
        guard let store else { throw HarnessError.storeNotOpen }
        let items = Set(0..<max(acknowledged, 0))
        return try store.pool.read { db in
            VerifyReport(
                acknowledged: acknowledged,
                libraryCaptures: try Int.fetchOne(db, sql: "SELECT count(*) FROM capture WHERE idempotency_key LIKE 'crash-%'") ?? -1,
                integrity: try LibraryChecks.integrity(db),
                foreignKeyViolations: try LibraryChecks.foreignKeyViolations(db).count,
                failures: try CrashDrill.verify(db, acknowledged: items, checkContentOf: items))
        }
    }
}
