# ADR-0003: Persistence

- **Status:** Proposed
- **Date:** 2026-10-06 (evidence refreshed 2026-10-07 after review rounds 1 and 2)
- **Deciders:** pending (product owner; technical lead at the M0 gate)
- **Plan references:** Sections 6.3, 7.1-7.5, 11.1, 11.4, 12, 19.2; invariants I-02, I-03; tests T02, T44, T45; gate G0.5 (persistence dependency and toolchain confirmation)

## Context

The plan asks for GRDB over SQLite, one serialized writer, foreign keys, WAL and "a durability configuration tested for acknowledged saves" (7.4), migrations with fixture upgrades, integrity checks and a recovery path (7.4), a transactional ChangeJournal (7.4), and identity rules where removing bytes never removes knowledge (I-02, 7.3). "Saved" may appear only after a durable commit (I-03). The G0.5 recovery spike (`Spikes/G05-Recovery`) built the subset of Section 7.2 the restore drill needs and tested these rules. The evidence report is `Docs/Stage0/G05-Recovery.md`.

## Decision

**Library and dependency.** GRDB.swift 7.11.1 (exact pin, revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`, MIT licence) over the system SQLite. No other persistence dependency. Store the database at `Application Support/Sylvia/Library/library.sqlite`, never in Documents.

**Connections.** One `DatabasePool` per process: one writer connection (all mutations are serialized through it) and concurrent read-only readers. `foreignKeysEnabled = true`, `busyMode = .timeout(10 s)`.

**Durability for acknowledged saves.** WAL, `PRAGMA synchronous = FULL`, `PRAGMA fullfsync = ON`, `PRAGMA checkpoint_fullfsync = ON`, applied on the writer **after** the pool is open and read back on every open; a mismatch is an open failure. Reasons:

- WAL with `synchronous = NORMAL` (GRDB's default) is durable against process death but, per SQLite's documentation, may roll back the last commits after power loss or an OS crash, which would break I-03.
- `FULL` syncs the WAL at every commit; on Apple platforms `fsync` does not flush the drive cache, so `fullfsync` makes that sync reach stable storage.
- The measured cost is small: on the host, p95 1.71 ms for a capture save with this setting versus 1.33 ms with GRDB's default (2,000 saves each), against a 200 ms budget. Device numbers are pending.
- GRDB 7.11.1 runs `PRAGMA synchronous = NORMAL` on the writer after `Configuration.prepareDatabase`, so setting `synchronous` in `prepareDatabase` is silently overridden. The post-open apply and readback are therefore required, not optional (test `DurabilityTests.grdbOverridesPrepareDatabase`).

**Schema rules.** `STRICT` tables. IDs are lowercase UUID text generated on device. Sizes, durations and positions are 64-bit `INTEGER` (bytes, milliseconds). Event timestamps are UTC integer milliseconds (`*_at_ms`). User-effective dates are separate text columns (`YYYY`, `YYYY-MM`, `YYYY-MM-DD`) with a `*_precision` column. `CHECK` enforces only the precision value (`year`, `month`, `day`) and that the date and its precision are null together; the date text itself (its format, its agreement with the precision, and that the day exists) is validated in code: by `EffectiveDate` when the app builds a date, and by `RowCheck` for every date of a backup's database before it is restored (ADR-0012). Adding the format to the schema would need a table rebuild of four tables; the spike did not, so the schema alone accepts `banana` with precision `day` (`SchemaTests.typing`). Ratings are `INTEGER 1-10` half-stars with `NULL` meaning cleared, plus an explicit `scale` column. Digests are checked lowercase hex SHA-256. JSON is used only for versioned locator payloads, source snapshots, provider identity and retrieval metadata (`json_valid` checked).

**Media never cascades into knowledge.** Removing media changes `asset_location.availability` (`on_device` → `at_source` or `unavailable`) and deletes files; it never deletes `asset`, `edition` or `work` rows. Every knowledge table references media and works with `ON DELETE RESTRICT`, so even a mistaken `DELETE FROM asset` fails instead of cascading. `ON DELETE CASCADE` is used only for subordinate rows: a capture's anchors, a note's revisions, a conversation's messages, a context pack's evidence, an asset's locations and membership joins. Availability is resolved as on device (file present with the recorded size), "Not on this device · from {source}", or "Record only"; a missing file is never an error or a corrupt record.

**Commands.** A capture save is one write transaction containing the capture, its anchors, the optional comment note and first revision, the ledger event and ChangeJournal entries, keyed by an idempotency key (`UNIQUE`); a retry returns "already saved" instead of a duplicate. The method returns only after the commit, and only then may the UI say "Saved". Note edits are revision-checked: an editor holding a stale revision gets `staleRevision`, never a silent overwrite.

**ChangeJournal.** Every mutation appends `(seq AUTOINCREMENT, entity, entity_id, revision, operation, recorded_at_ms)` in the same transaction. It is a local diagnostic and export-boundary record, not a sync protocol. The backup manifest records the highest sequence in each snapshot.

**Migrations.** `DatabaseMigrator` with `eraseDatabaseOnSchemaChange = false`, one identifier per migration, each flagged destructive or not. On open:

1. Read **all** applied identifiers with `appliedIdentifiers(_:)`. GRDB's `appliedMigrations(_:)` returns only registered identifiers and so cannot see that a newer build touched the file; any unknown identifier refuses the open without changes (`newerSchema`).
2. If a pending migration is destructive and the library is not new: check free space for a snapshot plus a rebuild plus a reserve (stop with `insufficientSpace` otherwise), then take a recovery snapshot with SQLite's online backup API into `Recovery/pre-migration-<ms>-<id8>.sqlite`, integrity-checked and flushed. Then write the put-back intent `Library/migration-putback.json` (the snapshot's path and the pending migrations) durably, before the first migration runs.
3. Migrate. GRDB runs each migration in its own transaction with deferred foreign-key checks.
4. After migrating, run `integrity_check`, `foreign_key_check` and compare every table's row count with the count before migrating. If all pass, remove the intent.
5. On any failure in 3 or 4, close the pool and put the snapshot back, resumably: copy the snapshot into `Staging/putback-<id>.sqlite.partial`, flush it and rename it to `putback-<id>.sqlite`; only then move `library.sqlite`, `-wal` and `-shm` to `Recovery/failed-<id>/`, rename the staged copy to `Library/library.sqlite`, and remove the intent, flushing the directory after each rename. Then report the failure (`migrationFailed` or `postMigrationCheckFailed`). If the put-back itself fails (for example a full disk), the failure is reported with `restoredFromSnapshot: false` and the intent stays.
6. Every open first reconciles an intent left by a crash or by a failed put-back, before SQLite opens anything: which files exist tells how far it got (staged copy present: move the live files aside and move it in; staged copy gone and the failed database already aside: it was moved in; neither: stage again from the snapshot). The open then reports `migrationInterrupted`, so the user sees the recovery screen once, and the next open retries the migration. An intent that exists but cannot be read (for example before first unlock) or is not valid fails the open with nothing changed. The intent lives inside `Library/`, so a restore swap moves it with the library it describes.
7. The open never lets SQLite create a new database where one should be: if `library.sqlite` is missing and the installation record exists or `Recovery/` holds copies, it fails with `libraryMissing` (listing the copies) instead. The database is created before the installation record on a new installation, so a crash between the two cannot trigger this.

In every failure the app opens a recovery screen with read-only access (`RecoveryAccess.openReadOnly`), from which the user can export. It never creates an empty replacement library.

A migration that cannot convert a value fails (`CHECK` constraint) rather than dropping the row.

**Files.** Directories are created with the data-protection class before files are written in them (see ADR-0012 for the class and its readback). All renames that publish data are same-volume `rename(2)` followed by a directory sync; file contents are synced with `F_FULLFSYNC` (falling back to `fsync`) before the rename.

## Evidence

All results are from `Scripts/ci.d/71-g05-recovery.sh`; logs are in `Docs/Stage0/evidence/G05-Recovery/logs/` and the full clean run is `Docs/Stage0/evidence/G05-Recovery/ci-clean-run.log`.

- **host** (macOS 26.6.2, Apple M5 Max, Xcode 27.0 27A266a, Swift 6.4): 63 tests in 11 suites, 59 passed, 4 skipped with stated reasons: the device lock probe and the device persistence probe, which need a phone, and the class-B protection run and inheritance probe, which skip while the Mac's screen is locked, as it was for the whole clean run (ADR-0012) (`logs/host-tests.log`).
- **host**, SIGKILL crash drill with the chosen setting: 900 kills (300 immediately after reading an acknowledgement, 300 while a write transaction was open, 300 at random times up to 40 ms after spawn). 6,468 acknowledged captures, all present exactly once with byte-exact quote and note text. No capture without all its anchors, note, revision, ledger event and journal entry, and no ledger event, note or journal entry without its capture. In all 300 in-transaction kills the in-flight capture was wholly absent after reopening. 144 times a capture that had committed just before a kill without being acknowledged was retried and got "already saved", with no duplicate; none was left unacknowledged at the end (a committed but unacknowledged capture would be allowed: the UI never said "Saved" for it). 0 failures (`logs/crash-drill-full.log`).
- **host**, the same drill with `synchronous = OFF`: 150 kills, 2,725 acknowledged captures, 0 failures (`logs/crash-drill-sync-off.log`). This is the expected result: a process kill leaves committed pages in the OS page cache whatever the setting, so it cannot tell the settings apart. The choice of `FULL` rests on SQLite's documented power-loss behaviour, not on this drill.
- **host**, capture-save latency, 2,000 saves into a library preloaded with 500: chosen setting p50 0.92 ms, p95 1.71 ms, p99 3.40 ms, max 8.90 ms. `FULL` without `fullfsync`: p95 1.82 ms. GRDB default: p95 1.33 ms (`logs/latency.log`). The same measurement inside the host test suite, which runs tests (including SIGKILL drills) in parallel, 400 saves: p95 29.56 ms, max 74.2 ms (`logs/host-tests.log`). Indicative only: other workstreams were building on the same Mac during these runs, and host numbers say nothing about a phone.
- **simulator** (iOS 26.5 23F77, iPhone 17): the same test suite without the five macOS-only tests: 58 tests, 54 passed and 4 skipped with stated reasons (the lock and persistence probes, and the protection-mismatch and class-B tests, which the simulator's readback cannot exercise). The writer reads back `journal_mode=wal synchronous=FULL fullfsync=1 checkpoint_fullfsync=1`. Save latency p95 5.86 ms (p50 1.18 ms, p99 11.25 ms, max 17.7 ms) over 400 saves (`logs/simulator-tests.log`). The simulator uses the host's disk, so this says nothing about a phone.
- **host and simulator**: SQLite 3.51.0, compiled with `DEFAULT_WAL_SYNCHRONOUS=1`, `DEFAULT_CKPTFULLFSYNC` and `ENABLE_FTS5` (`logs/env-report.log`, `logs/simulator-tests.log`).
- **host and simulator**, migrations: the committed v1 fixture upgrades to v2 (three migrations, the last adding the canonical cover thumbnail columns) with a snapshot, a clean integrity check and foreign-key check, and identical rows. Insufficient space refuses the migration without changes. An injected failure, a migration that silently drops rows and a value that cannot be converted each put the snapshot back with every row intact. A file with an unknown migration identifier is refused (`MigrationTests`).
- **host and simulator**, put-back interrupted (review round 2): a simulated crash after each of the 9 steps of a guarded migration (`intentWritten` through `intentRemoved`, including `migrationChecked` on the success path), and a full-disk error at each of the 3 put-back steps that can fail (`staged`, `databaseMovedAside`, `snapshotMovedIn`), each end with the next open finishing the put-back and reporting `migrationInterrupted` (unless it had finished), the read-only library equal to the v1 library, and the following open migrating it with every row intact. An unreadable intent (mode 000, standing in for before first unlock), a non-JSON intent and one with a traversal path each fail the open with no file changed. With `library.sqlite` moved aside and no intent (the review's probe state), the open fails with `libraryMissing` instead of creating an empty library, whether the installation record or only `Recovery/` copies remain. A restore over a library with a pending put-back replaces it, and the intent moves with the old library into the pre-restore copy (`PutBackTests`).
- **host**, SIGKILL drill over the put-back: 240 child processes each opened a v1 golden-corpus library whose destructive migration threw or silently dropped rows; each was killed while paused right after one of the 8 failure-path steps, 0-3 ms after one, or at a random time within an unkilled run (102 ms). 215 were killed (25 finished first). The first reopen through the launch path finished the put-back 175 times (the read-only library was then exactly the v1 library) and found the put-back complete or not started 65 times; in every case the library then migrated with knowledge rows equal to a clean migration's, clean integrity and foreign-key checks, the same device identity, and no intent or staged copy left. 0 failures (`logs/migration-crash-drill.log`).
- **host**, storage full on a real volume: the library on a 64 MiB APFS disk image filled by another file to 761,856 free bytes; a capture with an 8 MB note fails with `SQLITE_FULL` when the OS refuses the write. After the filler is removed and the library reopened, integrity and foreign keys are clean, the 20 earlier saves are intact with exact content, the failed capture is absent, and the retry saves once (`DurabilityTests.storageFullRealVolume`).
- **host and simulator**, storage full simulated with `PRAGMA max_page_count`: the same result through SQLite's own page limit (`DurabilityTests.storageFull`).
- **pending (device):** save latency, SQLite version and pragma readback on the iPhone (device checklist steps 1-2).

## Consequences

- Acknowledged saves cost one WAL sync each. That is affordable at capture rates but rules out "Saved" on uncommitted batches. Bulk imports should batch rows into fewer transactions.
- Every migration must preserve row counts unless it states otherwise; a migration that deletes rows on purpose must say so, and the post-check must be extended for it.
- `appliedMigrations` must not be used for version checks anywhere in the product.
- Any operation that replaces the library's files (the put-back here, the restore swap in ADR-0012, and any later one) writes an intent first and is finished or rolled back by the next open before SQLite opens anything. Copies are staged and flushed before the live files are touched.
- A destructive migration's open shows the recovery screen once after an interrupted put-back (`migrationInterrupted`); the next open retries. A migration that crashes the process every time therefore alternates between the recovery screen and a retry instead of looping silently.
- Not proven, and cannot be proven by a process-kill drill: durability across power loss, kernel panics or storage firmware that ignores flushes. These rest on SQLite's and APFS's documented guarantees with `FULL` and `F_FULLFSYNC`.
- Re-check on GRDB upgrades: whether `DatabasePool` still overrides `synchronous` after `prepareDatabase` (the readback fails the open if it changes behaviour in either direction).

## Alternatives considered

- **WAL + `synchronous = NORMAL` (GRDB default).** Slightly faster, but may lose the last acknowledged commits on power loss, which conflicts with I-03.
- **Rollback journal (`DELETE`) + `FULL`.** Durable, but readers block the writer during commits and it gives up GRDB's `DatabasePool` concurrency.
- **Core Data / SwiftData.** No direct control over pragmas, migrations as rows-preserving checks, or the online-backup snapshot the backup format needs. The plan already names GRDB (6.3).
- **Setting pragmas in `prepareDatabase` only.** Silently overridden for `synchronous` by GRDB 7.11.1 (tested).

## Open items

- Device measurements: latency, SQLite version and pragma readback on the iPhone 17 Pro, and on the iPhone 12-class baseline when available (owner: M0 device run).
- Product owner: approve WAL + `FULL` + `fullfsync` as the I-03 setting.
