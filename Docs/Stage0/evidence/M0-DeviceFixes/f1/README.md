# F-1 fixed: protection classes read afresh (27 October 2026)

The product owner, as technical lead, decided on 27 October 2026 to fix finding F-1 before re-running Session 1.2.

**Change.** `FileProtector.protectionClass(of:)` (`Spikes/G05-Recovery/Sources/SylviaRecovery/FileProtection.swift`) drops
the URL's cached `fileProtectionKey` before reading, so `protect`, `verify` and every readback see the file's class as it
is on disk. A `URL` caches the resource values it has read, so before this a reading through the URL that had read the
class before `setAttributes` returned the old class. Two comments that said an existing file's class cannot be changed,
and the refused-branch evidence line of `DataProtectionTests.mismatchDetected`, no longer assert that.

**Result on the Mac** ([`host-tests.log`](host-tests.log), `xcrun swift test --force-resolved-versions` in
`Spikes/G05-Recovery`, screen unlocked): 79 tests in 13 suites passed; 3 skipped (the two device probes, and the
locked-screen observation, the screen being unlocked). The mismatch test now prints `changing an existing file's class
with setAttributes: applied and verified`: on macOS 26.6.2, with the screen unlocked, `setAttributes` does change an
existing file's class. The earlier unlocked runs' "refused" lines (for example `G05-Recovery/ci-clean-run.log`) were the
cached reading; the locked runs' "cannot apply class ... Operation not permitted" lines were real refusals, class-B keys
being unavailable. A library file of the wrong class is now set to the class and verified where `setAttributes` works,
instead of failing the open (`FileProtection.swift`: "sets and verifies"). An independent review (one round) accepted
the fix with four minor findings, all applied.

The same run is the first run of the two class-B tests of the device fixes' failure 1, which had never run (they need
the screen unlocked): `v1 library installed from a class-B source: ... opened and migrated` and `class-B tree (4 files,
5 directories) copied with FileProtector.copyTree: ["NSFileProtectionCompleteUntilFirstUserAuthentication": 9]`, with
the class-B readback on 53 items and the SQLite class-B inheritance line.

The phone's behaviour is shown by the owner's re-run of 1.2. Made by the orchestrating session in lean mode (the
owner's choice of 27 October 2026); not independently reviewed.

**Runbook 0.8 on the fixed code** ([`dropin-unlocked/`](dropin-unlocked/console.log), 27 October 2026, the orchestrating
session, on `26f1d017`, screen unlocked, `Scripts/ci.d/71-g05-recovery.sh` with `G05_LOG_DIR` set to that folder):
`drop-in exit 0`; `row 10 evidence present: class-B readback and inheritance lines found in host-tests.log`; 79 host
tests and 73 simulator tests, each in 13 suites, passed; the lock harness passed 49 tests in 4 suites, its quiet-tone
test included, and `G0.5 recovery lock harness: steps 13-15 passed`; then `G0.5 recovery: all steps passed`. This is
row 10's class-B evidence on the recovery code as fixed; the owner runs 0.8 again only if that code changes.
