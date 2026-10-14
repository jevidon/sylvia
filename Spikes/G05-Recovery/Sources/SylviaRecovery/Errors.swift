import Foundation

/// Errors from opening, migrating and mutating the library.
public enum StoreError: Error, Equatable, CustomStringConvertible {
    case durabilityNotApplied(expected: String, observed: String)
    /// The database was written by a newer build. Nothing was changed.
    case newerSchema(unknownMigrations: [String])
    /// Not enough free space to take the recovery snapshot and run the migration. Nothing was changed.
    case insufficientSpace(required: Int64, available: Int64)
    /// A migration threw. The pre-migration recovery snapshot was put back as the library.
    case migrationFailed(identifier: String?, reason: String, restoredFromSnapshot: Bool)
    /// Migrations completed but a post-migration check failed. The snapshot was put back.
    case postMigrationCheckFailed(reason: String, restoredFromSnapshot: Bool)
    /// A snapshot-guarded migration was interrupted (process death, or an error while putting the
    /// snapshot back). This open finished putting the pre-migration snapshot back; the library is
    /// complete and readable, and the next open retries `pending`.
    case migrationInterrupted(pending: [String])
    /// A failed migration's put-back is pending (its intent is on disk) and could not be finished at
    /// this open, for example because the disk is still full. The library was not opened; the intent
    /// stays, so the next open resumes the put-back from the step that failed. `reason` is the
    /// underlying error. While the pre-migration snapshot exists it holds the whole library, and the
    /// recovery screen can offer read-only access to it meanwhile.
    case migrationPutBackPending(reason: String)
    /// `Library/library.sqlite` is missing from an installation that already had a library (its
    /// installation record exists, or `Recovery/` holds copies). No empty library was created; the
    /// copies in `Recovery/` are listed for the recovery screen.
    case libraryMissing(recoveryItems: [String])
    /// Test hook: the operation stopped after the named step, leaving files as a crash would.
    case simulatedCrash(String)
    case integrityCheckFailed([String])
    case foreignKeyViolations([String])
    case unknownTable(String)
    case staleRevision(noteID: String, expected: Int, current: Int)
    case notFound(entity: String, id: String)
    case excerptsPending(count: Int)
    case invalid(String)

    public var description: String {
        switch self {
        case .durabilityNotApplied(let e, let o): return "durability not applied: expected \(e), observed \(o)"
        case .newerSchema(let ids): return "library was written by a newer version (unknown migrations: \(ids.joined(separator: ", ")))"
        case .insufficientSpace(let r, let a): return "insufficient space: need \(r) bytes, \(a) available"
        case .migrationFailed(let id, let why, let restored):
            return "migration \(id ?? "?") failed: \(why); restored from snapshot: \(restored)"
        case .postMigrationCheckFailed(let why, let restored):
            return "post-migration check failed: \(why); restored from snapshot: \(restored)"
        case .migrationInterrupted(let pending):
            return "migration (\(pending.joined(separator: ", "))) was interrupted; the pre-migration snapshot was put back and the next open retries it"
        case .migrationPutBackPending(let why):
            return "putting the pre-migration snapshot back could not finish (\(why)); the library was not opened and the put-back intent was kept, so the next open resumes it"
        case .libraryMissing(let items):
            return "the library database is missing; no empty library was created; recovery copies: \(items.isEmpty ? "none" : items.joined(separator: ", "))"
        case .simulatedCrash(let step): return "simulated crash after \(step)"
        case .integrityCheckFailed(let m): return "integrity_check: \(m.prefix(5).joined(separator: "; "))"
        case .foreignKeyViolations(let v): return "foreign_key_check: \(v.count) violations, first: \(v.first ?? "")"
        case .unknownTable(let t): return "unknown table \(t)"
        case .staleRevision(let id, let e, let c): return "note \(id): editor has revision \(e), store has \(c)"
        case .notFound(let e, let id): return "\(e) \(id) not found"
        case .excerptsPending(let n): return "\(n) audio excerpt(s) are still being preserved"
        case .invalid(let why): return "invalid: \(why)"
        }
    }

    var isSimulatedCrash: Bool {
        if case .simulatedCrash = self { return true }
        return false
    }

    /// The same migration failure, reported when putting the snapshot back did not finish in this
    /// run. The put-back intent is still on disk, so the next open finishes it before using the library.
    func puttingBackFailed(_ why: String) -> StoreError {
        let suffix = "; putting the pre-migration snapshot back did not finish (\(why)); the next open finishes it"
        switch self {
        case .migrationFailed(let id, let reason, _): return .migrationFailed(identifier: id, reason: reason + suffix, restoredFromSnapshot: false)
        case .postMigrationCheckFailed(let reason, _): return .postMigrationCheckFailed(reason: reason + suffix, restoredFromSnapshot: false)
        default: return self
        }
    }
}
