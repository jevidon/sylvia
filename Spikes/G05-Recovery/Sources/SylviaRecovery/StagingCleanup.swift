import Foundation

/// Launch-time cleanup of this layer's own staging directory, `Staging/Persistence/` (plan 17.1:
/// staging data is kept for live operations, with a cleanup policy for abandoned ones).
///
/// Scope. Only `LibraryLayout.stagingDirectory` (`Staging/Persistence/`) is cleaned. The rest of
/// `Staging/` belongs to intake: ADR-0010 keeps its durable import journal (`journal.json`) and
/// its jobs (`Staged/`, `Rejected/`, `Abandoned/`, `Extracting/`) there, and a staged job can be
/// the only copy of an item the share extension already reported as received. Those entries are
/// recovered or expired by intake's own journal and rules (plan 8.2), never by this cleanup
/// (review round 4 found that the first version emptied all of `Staging/`).
///
/// Everything this layer writes into `Staging/Persistence/` is a temporary copy that its operation
/// renames into place or removes when it ends: a media import's copy (as large as the imported
/// file, an audiobook included), a pre-migration snapshot being written, a blob or intent being
/// written durably, a put-back's staged snapshot. A crash, or an error between the copy and its
/// rename, leaves the copy behind, and nothing else ever removes it, so repeated failures would
/// fill the device the way review round 3 found for `Recovery/`.
///
/// `LibraryStore.open` runs before the library is used, and one store uses an installation at a
/// time, so when the open reaches this cleanup no operation of this layer is live: every entry is
/// abandoned, except the files of a put-back whose intent is still pending
/// (`MigrationPutBack.reconcile` keeps its staged copy and its partial copy, which the put-back
/// itself replaces or removes). Removal is best effort: an entry that cannot be removed is
/// reported and left for the next launch, and never fails the open.
enum StagingCleanup {
    struct Report: Sendable, Equatable {
        var removed: [String] = []
        var errors: [String] = []
    }

    /// Removes every entry of `Staging/Persistence/` whose name is not in `kept`. Nothing outside
    /// that directory is read or changed.
    @discardableResult
    static func removeAbandoned(_ layout: LibraryLayout, keeping kept: Set<String> = []) -> Report {
        var report = Report()
        let fm = FileManager.default
        let names: [String]
        do { names = try fm.contentsOfDirectory(atPath: layout.stagingDirectory.path).sorted() } catch {
            report.errors.append("cannot list Staging/Persistence: \(error.localizedDescription)")
            return report
        }
        for name in names where !kept.contains(name) {
            do {
                try fm.removeItem(at: layout.stagingDirectory.appending(path: name, directoryHint: .notDirectory))
                report.removed.append(name)
            } catch {
                report.errors.append("\(name): \(error.localizedDescription)")
            }
        }
        if !report.removed.isEmpty { try? DurableFile.syncDirectory(layout.stagingDirectory) }
        return report
    }
}
