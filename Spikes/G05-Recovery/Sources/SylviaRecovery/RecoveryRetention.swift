import Foundation
import GRDB

/// Retention of the copies in `Recovery/` (plan 17.1: staging and recovery data need a visible
/// cleanup policy; review round 3 found that every failing launch added a new pre-migration snapshot
/// and a new `failed-<id>/` copy, about twice the library each time, and that nothing removed them).
///
/// The rule (ADR-0003, ADR-0012):
///
/// * **Pre-migration snapshots** (`pre-migration-<ms>-<id8>.sqlite`). A guarded migration reuses an
///   existing snapshot whose whole logical content equals the live library's
///   (`LibraryChecks.contentDigest`, which covers the schema, the applied migrations and every row)
///   instead of taking another, so retrying from the same pre-state never adds a copy. Once a
///   put-back completes or a guarded migration succeeds, only the snapshot it used is kept; older
///   ones are removed. The kept one therefore stays until a later guarded migration succeeds or is
///   put back with another snapshot, so damage found after an upgrade can still be recovered.
/// * **Failed copies** (`failed-<uuid>/`). They hold what a failed migration left in the live files,
///   which is never newer than the snapshot that was put back: a migration and its put-back run
///   inside an open (the put-back possibly at the next one), before anything can write. Only the
///   latest is kept for diagnosis; all are removed once a guarded migration succeeds.
/// * **Pre-restore copies** (`pre-restore-<id>/`) hold the library a confirmed restore replaced, which
///   may be the only copy of that data. They are never removed automatically; the product shows
///   them with their size and lets the user remove them.
/// * A snapshot or failed copy named by a put-back intent that moved into a pre-restore copy is
///   kept, because rolling that restore back would need it. If such an intent cannot be read, no
///   snapshot or failed copy is removed.
/// * Anything else in `Recovery/` is never removed: only names of exactly the two generated forms
///   above are candidates.
///
/// Removal is best effort and runs only after the put-back intent is gone: an error leaves the
/// copies for the next prune and never fails the open or hides the migration's own result.
public enum RecoveryRetention {
    static let snapshotPrefix = "pre-migration-"
    static let failedPrefix = "failed-"
    static let preRestorePrefix = "pre-restore-"

    /// Exactly `failed-<lowercase UUID>`, the name `MigrationPutBack` gives a failed copy.
    static func isFailedCopyName(_ name: String) -> Bool {
        name.hasPrefix(failedPrefix) && EntityID.isValid(String(name.dropFirst(failedPrefix.count)))
    }

    /// Names of the pre-migration snapshots in `Recovery/`, newest first (by the time in the name).
    static func snapshotNames(_ layout: LibraryLayout) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: layout.recoveryDirectory.path)
            .filter { PutBackIntent.isSnapshotName($0) }
            .sorted { snapshotTime($0) > snapshotTime($1) || (snapshotTime($0) == snapshotTime($1) && $0 > $1) }
    }

    static func snapshotTime(_ name: String) -> Int64 {
        Int64(name.dropFirst(snapshotPrefix.count).prefix { $0 != "-" }) ?? 0
    }

    /// The name of an existing pre-migration snapshot that is intact and whose logical content
    /// equals `pool`'s, or nil. Snapshots that cannot be opened or checked are skipped, never reused.
    static func reusableSnapshot(matching pool: DatabasePool, layout: LibraryLayout) throws -> String? {
        let candidates = try snapshotNames(layout)
        guard !candidates.isEmpty else { return nil }
        let live = try pool.read { try LibraryChecks.contentDigest($0) }
        for name in candidates {
            let url = layout.recoveryDirectory.appending(path: name, directoryHint: .notDirectory)
            guard let queue = try? RecoveryAccess.openReadOnly(url) else { continue }
            defer { try? queue.close() }
            // The digest first: a snapshot of another state is skipped without an integrity check.
            let matches = (try? queue.read { db in
                try LibraryChecks.contentDigest(db) == live && LibraryChecks.isIntact(db)
            }) ?? false
            if matches { return name }
        }
        return nil
    }

    /// What `prune` removed, and anything it could not remove (left for the next prune).
    public struct PruneReport: Sendable, Equatable {
        public var removed: [String] = []
        public var kept: [String] = []
        public var errors: [String] = []
    }

    /// Applies the retention rule after a put-back completed (`keepFailed` is its failed copy) or a
    /// guarded migration succeeded (`keepFailed` nil). `keepSnapshot` is the snapshot that operation
    /// used. Pre-restore copies are never touched.
    @discardableResult
    static func prune(_ layout: LibraryLayout, keepSnapshot: String, keepFailed: String?) -> PruneReport {
        var report = PruneReport()
        let fm = FileManager.default
        let names: [String]
        do { names = try fm.contentsOfDirectory(atPath: layout.recoveryDirectory.path).sorted() } catch {
            report.errors.append("cannot list Recovery: \(error.localizedDescription)")
            return report
        }
        var protected: Set<String> = [keepSnapshot]
        if let keepFailed { protected.insert(keepFailed) }
        // Put-back intents that moved with a library into a pre-restore copy (and the live one, which
        // should not exist when this runs).
        var intents = names.filter { $0.hasPrefix(preRestorePrefix) }.map {
            layout.recoveryDirectory.appending(path: "\($0)/Library/migration-putback.json", directoryHint: .notDirectory)
        }
        intents.append(layout.migrationPutBackIntentURL)
        for url in intents where fm.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let intent = try? JSONDecoder().decode(PutBackIntent.self, from: data), intent.isValid else {
                report.errors.append("a put-back intent in \(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent) cannot be read; nothing was removed")
                return report
            }
            protected.insert(String(intent.snapshot.dropFirst("Recovery/".count)))
            protected.insert("\(failedPrefix)\(intent.id)")
        }
        for name in names {
            let isSnapshot = PutBackIntent.isSnapshotName(name)
            let isFailed = isFailedCopyName(name)
            guard isSnapshot || isFailed else { continue }
            if protected.contains(name) { report.kept.append(name); continue }
            do {
                try fm.removeItem(at: layout.recoveryDirectory.appending(path: name, directoryHint: isFailed ? .isDirectory : .notDirectory))
                report.removed.append(name)
            } catch {
                report.errors.append("\(name): \(error.localizedDescription)")
            }
        }
        if !report.removed.isEmpty { try? DurableFile.syncDirectory(layout.recoveryDirectory) }
        return report
    }
}
