import Foundation
import GRDB

/// SQLite durability settings for the single writer connection (plan 7.4, I-03).
///
/// GRDB's `DatabasePool` puts the database in WAL mode and then runs `PRAGMA synchronous = NORMAL`
/// on the writer *after* `Configuration.prepareDatabase` has run, so a `synchronous` pragma placed in
/// `prepareDatabase` is silently overridden. `LibraryStore` therefore applies this policy on the
/// writer after the pool is open and reads every value back (see `DurabilityTests`).
public struct DurabilityPolicy: Sendable, Hashable, CustomStringConvertible {
    public enum Synchronous: Int, Sendable, CaseIterable {
        case off = 0, normal = 1, full = 2, extra = 3
        public var name: String { ["OFF", "NORMAL", "FULL", "EXTRA"][rawValue] }
    }

    public var synchronous: Synchronous
    /// `PRAGMA fullfsync`: use `F_FULLFSYNC` (flush the drive cache) instead of `fsync` on Apple
    /// platforms. Apple's SQLite build already defaults `checkpoint_fullfsync` on.
    public var fullfsync: Bool

    public init(synchronous: Synchronous, fullfsync: Bool) {
        self.synchronous = synchronous
        self.fullfsync = fullfsync
    }

    /// The chosen setting for acknowledged saves (ADR-0003): WAL + `synchronous=FULL` + `fullfsync`.
    /// FULL syncs the WAL on every commit, so a commit that has returned survives power loss as well as
    /// process death (SQLite documentation, "WAL mode" / "PRAGMA synchronous"); `fullfsync` makes that
    /// sync reach stable storage on Apple hardware. NORMAL in WAL mode is durable against process
    /// death but may roll back the most recent commits after power loss, which would break I-03.
    public static let acknowledgedSaves = DurabilityPolicy(synchronous: .full, fullfsync: true)

    /// GRDB's default, kept only so the latency benchmark and crash drill can compare against it.
    public static let grdbDefault = DurabilityPolicy(synchronous: .normal, fullfsync: false)

    /// Never used by the library; exists to show what the SIGKILL drill can and cannot distinguish.
    public static let unsafeOff = DurabilityPolicy(synchronous: .off, fullfsync: false)

    public var description: String { "synchronous=\(synchronous.name) fullfsync=\(fullfsync ? "ON" : "OFF")" }

    /// Applies the policy on a connection and verifies it took effect.
    func apply(_ db: Database) throws {
        try db.execute(sql: "PRAGMA synchronous = \(synchronous.rawValue)")
        try db.execute(sql: "PRAGMA fullfsync = \(fullfsync ? 1 : 0)")
        try db.execute(sql: "PRAGMA checkpoint_fullfsync = 1")
        let observed = try DurabilityPolicy.observe(db)
        guard observed.synchronous == synchronous, observed.fullfsync == fullfsync,
              observed.checkpointFullfsync else {
            throw StoreError.durabilityNotApplied(expected: description, observed: observed.description)
        }
    }

    public struct Observed: Sendable, CustomStringConvertible {
        public let journalMode: String
        public let synchronous: Synchronous?
        public let fullfsync: Bool
        public let checkpointFullfsync: Bool
        public var description: String {
            "journal_mode=\(journalMode) synchronous=\(synchronous?.name ?? "?") "
                + "fullfsync=\(fullfsync ? 1 : 0) checkpoint_fullfsync=\(checkpointFullfsync ? 1 : 0)"
        }
    }

    public static func observe(_ db: Database) throws -> Observed {
        Observed(
            journalMode: try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "?",
            synchronous: Synchronous(rawValue: try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? -1),
            fullfsync: (try Int.fetchOne(db, sql: "PRAGMA fullfsync") ?? 0) == 1,
            checkpointFullfsync: (try Int.fetchOne(db, sql: "PRAGMA checkpoint_fullfsync") ?? 0) == 1)
    }
}
