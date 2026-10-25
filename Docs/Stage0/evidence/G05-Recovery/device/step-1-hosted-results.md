# Recovery suite — first app-hosted device run

Result: **failed**, xcodebuild exit 65. The missing host-app blocker is resolved.

Device: iPhone 17 Pro (iPhone18,1), iOS 27.0.1 (24A446).
Host: macOS 26.6.2 (25G83), Xcode 27.1 (27A9275).
Operator: Codex with Justin Evidon. Debug, wired, unlocked, Low Power Mode off (user confirmed).
Date: 26 October 2026 NZDT (25 October UTC); exact timestamps in the log.
Code: run from 432acc13 plus the new DeviceTests files subsequently committed unchanged in 4be1a1a4. Existing recovery sources, tests, fixtures and package pins were unchanged. Documentation and inventory changes do not affect the tested code.

68 tests in 11 suites, four expected skips, 108 reported issues. Issue count includes cascading and parameterized failures; it is not a count of failed tests.

- Migration and put-back tests encounter library.sqlite with NSFileProtectionNone instead of the required class C. Many subsequent errors cascade from this initial rejection. Root cause still requires diagnosis.
- BackupTests.rejections rejects the missing-blob-file variant, but reports unsafe path rather than the expected error. The rejection occurs; its error classification fails the check.
- Explicit class C and class B readback each passed on all 53 files/directories, and class-B SQLite inheritance passed.
- One Debug cable latency run: n=400, p95=2.292 ms, below 200 ms. This is not completion of the six-run latency criterion. No repeat was used to erase a result.

The full test log is step-1-hosted-tests.log. The original package attempts remain preserved separately. Further cable repeats, Release and Low Power Mode runs remain pending while the suite failures are diagnosed.

## Evidence lines

```text
[evidence] [device (Version 27.0.1 (Build 24A446))] rejected not-a-database: database snapshot failed checks: SQLite error 26: file is not a database - while executing `SELECT * FROM sqlite_master LIMIT 1`
[evidence] [device (Version 27.0.1 (Build 24A446))] default GRDB connection: SQLITE_DBCONFIG_DEFENSIVE=1 trusted_schema=1; untrusted configuration sets 1 and 0
[evidence] [device (Version 27.0.1 (Build 24A446))] restore intent "not json": open refused: restore intent is not valid; nothing was changed
[evidence] [device (Version 27.0.1 (Build 24A446))] restore intent "{\"id\":\"x\"}": open refused: restore intent is not valid; nothing was changed
[evidence] [device (Version 27.0.1 (Build 24A446))] restore intent "traversal": open refused: restore intent is not valid; nothing was changed
[evidence] [device (Version 27.0.1 (Build 24A446))] unreadable restore intent: open refused: restore intent exists but cannot be read; nothing was changed
[evidence] [device (Version 27.0.1 (Build 24A446))] installation record unreadable: open refused: installation.json exists but cannot be read: The file “installation.json” couldn’t be opened because you don’t have permission to view it.
[evidence] [device (Version 27.0.1 (Build 24A446))] installation record garbage: open refused: installation.json exists but is not a valid installation record
[evidence] [device (Version 27.0.1 (Build 24A446))] class C (chosen; also the platform default) read back on 53 files and directories: ["NSFileProtectionCompleteUntilFirstUserAuthentication": 53]
[evidence] [device (Version 27.0.1 (Build 24A446))] class B (non-default) requested: read back on 53 files and directories: ["NSFileProtectionCompleteUnlessOpen": 53]
[evidence] [device (Version 27.0.1 (Build 24A446))] files SQLite created in a class-B directory: probe.sqlite=NSFileProtectionCompleteUnlessOpen probe.sqlite-wal=NSFileProtectionCompleteUnlessOpen probe.sqlite-shm=NSFileProtectionCompleteUnlessOpen
[evidence] [device (Version 27.0.1 (Build 24A446))] files SQLite created in a class-A directory: probe.sqlite=NSFileProtectionComplete probe.sqlite-wal=NSFileProtectionComplete probe.sqlite-shm=NSFileProtectionCompleteUntilFirstUserAuthentication
[evidence] [device (Version 27.0.1 (Build 24A446))] changing an existing file's class with setAttributes: refused (protection: weak.bin has NSFileProtectionCompleteUnlessOpen, expected NSFileProtectionCompleteUntilFirstUserAuthentication); the class is fixed at creation here
[evidence] [device (Version 27.0.1 (Build 24A446))] TM-F1: classes other than A, B and C (and no protection) are refused by write, copyFile, ensureDirectory and protect, which leave no file and change no class
[evidence] [device (Version 27.0.1 (Build 24A446))] writer pragmas: journal_mode=wal synchronous=FULL fullfsync=1 checkpoint_fullfsync=1
[evidence] [device (Version 27.0.1 (Build 24A446))] SQLite 3.54.0; DEFAULT_CKPTFULLFSYNC DEFAULT_SYNCHRONOUS=2 DEFAULT_WAL_SYNCHRONOUS=1 ENABLE_FTS5
[evidence] [device (Version 27.0.1 (Build 24A446))] capture save latency synchronous=FULL fullfsync=ON: n=400 p50=1.453 ms p95=2.292 ms p99=4.261 ms max=8.446 ms
[evidence] [device (Version 27.0.1 (Build 24A446))] library.sqlite missing (installation record): open refused with libraryMissing; 3 captures readable in Recovery/failed-probe
[evidence] [device (Version 27.0.1 (Build 24A446))] library.sqlite missing (recovery copies only): open refused with libraryMissing; 3 captures readable in Recovery/failed-probe
[evidence] [device (Version 27.0.1 (Build 24A446))] text with U+0000 refused before writing (capture quote, comment, note), nothing written; RowCheck on a library holding a NUL and invalid UTF-8: ["capture.quoted_text rowid 1: text is not valid UTF-8", "note_revision.body rowid 1: text contains a NUL character"]
```
