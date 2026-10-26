# M0 device fixes: G0.5 recovery (runbook step 1.2)

Branch `m0-device-fixes-recovery`, made from `m0-decisions` at `c72247a6` (the owner's session branch, which this work
does not change). An agent's work on the build Mac on 26 October 2026; times are UTC (the Mac's clock is NZDT, UTC+13).
**Nothing here ran on a phone.** The fixes are shown on the Mac where the Mac can show them, and step 1.2 must be run
again on phone B for the device result (section 6). This is not a device result, a role sign-off, an ADR approval
(decision D-6) or the M0 exit.

Environment of every run here: the build Mac, macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275), Swift 6.4; the
simulator Sylvia-M0-devfix-recovery (iPhone 17, iOS 26.5), made for this job and deleted at its end. The Mac's screen
was unlocked for the baseline run (02:22 UTC) and locked from before 05:21 UTC on; each log records the lock state
(ioreg, read only) at its start and end, and [`lock-wait.log`](lock-wait.log) every reading of the wait for an unlock.
Load is recorded with each run (other jobs shared the Mac; no timing here is a budget result).

Commits: `a65cdc3e` the tests that reproduce both failures on the Mac (they fail on the unchanged code), `c778cd63` the
fixes, then this record.

## 1. What failed on the phone (the owner's records, unchanged)

Runbook Session 1, step 1.2, phone B (iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446)), Codex with the owner, 25 October
2026 UTC: the recovery suite in Codex's app host (`Spikes/G05-Recovery/DeviceTests`, `4be1a1a4`) ran 68 tests in 11
suites with 4 expected skips and failed with 108 issues
([`step-1-hosted-results.md`](../../G05-Recovery/device/step-1-hosted-results.md),
[`step-1-hosted-tests.log`](../../G05-Recovery/device/step-1-hosted-tests.log) line 3038; the session log's rows 3a-3d).
Three suites failed: Restore (1 issue), Migrations (6) and Migration put-back (101).

## 2. Diagnosis

### 2.1 Library files with no protection class: confirmed, with one correction

- The migration and put-back tests install their v1 library with `MigrationTests.installV1`, which copied the fixture
  out of the test bundle with `FileManager.copyItem` (`MigrationTests.swift` line 33 at `c72247a6`). `copyItem` keeps the
  source file's class; the recovery code says so itself and never uses it for files it keeps (`FileProtection.swift`
  lines 17-19 and 122-128). On the phone the test bundle is inside the app (`DeviceTests/project.yml` copies `Fixtures`
  into the test bundle, and `DeviceTests/Support/Bundle+Module.swift` makes `Bundle.module` that bundle), and the copy
  had no protection class: the first open of each of the 34 failing test cases that install the fixture refused
  `library.sqlite` as `NSFileProtectionNone` (33 issue lines name it, the first at line 2411; the 34th shows it in its
  detail, line 2841). That the fixture in the app bundle itself has no class follows (the copy keeps it); it was not
  read directly.
- Every open sets and checks the class of the database files (`LibraryStore.open` calls `protectDatabaseFiles`,
  `LibraryStore.swift` lines 97 and 157-165; `FileProtector.protect` and `verify`, `FileProtection.swift` lines 96-105
  and 174-181). Its refusal is the error every failing migration and put-back test reports first.
- The Mac and the simulator could not show it: on the Mac the copy reads back class C, the platform default, so the
  suite passed there ([`baseline-host-tests.log`](baseline-host-tests.log): 73 tests in 11 suites, unchanged code), and
  the simulator reports class C for every file. macOS has no unprotected class (a request for it reads back C:
  `DataProtectionTests.mismatchDetected`'s host line), so the Mac's reproduction installs the v1 library from a class-B
  source instead: `ProtectedCopyTests.v1LibraryFromAnotherClass`. It needs class-B keys, so it was skipped in every run
  here, the screen being locked (section 5).
- **Correction.** The class the refusal reports is the one the file had before the open tried to set it, not a class the
  open could not change: see finding F-1 (section 2.4). The tests' setup was wrong, as diagnosed; the check failed
  closed, but the reason it gave is a stale reading.

The other copies in the spike's Sources and Tests (all five `copyItem` calls; [`before-fix-host-tests.log`](before-fix-host-tests.log)
lists them):

- `PutBackTests.swift` line 136 (`plantWALAndSHM`) copies `library.sqlite` and moves the copy back into `Library/`. On
  the phone it was never reached: each test that uses it failed at the open before it. Its source is the installed
  library, class C once the installer is fixed; changed all the same, with the planted `-wal` and `-shm` now written with
  the class (`FileProtector.write`).
- `Support.swift` line 84 (`copyTree`, the bundle variants of `RestoreTests.rejections`): **not a cause.** A restore
  copies a bundle's files into its work library with `FileProtector.copyFile` (`Restore.swift` line 95), so the class of
  a bundle's files does not matter, and on the phone every variant made with it was rejected as expected except
  missing-blob-file (cause 2; log lines 2140-2302). Changed anyway, so that no copy in the spike keeps its source's class
  and the guard below needs no exception.
- `MigrationCrashDrill.swift` line 114 and `RestoreCrashDrill.swift` line 114: the SIGKILL drills (macOS only) copy a
  template installation over the library root before each iteration. The template is made by `LibraryStore` in a
  class-C folder, so its copies were class C and the drills never failed; they copy into a library, so they now use the
  new `FileProtector.copyTree`.
- No other copy: `Media.swift`, `Exporter.swift`, `Restore.swift` and `MigrationPutBack.swift` already create their
  copies with `FileProtector.copyFile`.

### 2.2 A missing blob file reported as an unsafe path: confirmed

- `BackupValidator.resolve` (`Container.swift` lines 170-182 at `c72247a6`) compared `resolvingSymlinksInPath()` of the
  bundle root with that of the joined path. Apple: "If the name of the receiving path begins with `/private`, this
  property strips off the `/private` designator, provided the result is the name of an existing file."
  ([NSURL `resolvingSymlinksInPath`](https://developer.apple.com/documentation/foundation/nsurl/resolvingsymlinksinpath),
  read 26 October 2026.) On the phone the test's folders are under `/private/var/mobile/Containers/Data/Application/…/tmp/`
  (log line 2145): the existing root lost its `/private`, the missing file kept it, and the prefix check threw
  `unsafePath` before `requireRegularFile` could report the file missing (log lines 2261-2265).
- On the Mac the tests' temporary folder is `/var/folders/…`, which hides it: there both paths keep the `/var` form.
  Named through `/private`, the same folder shows it. `PrivatePathTests.missingFileUnderPrivateVar`, on the unchanged
  code ([`before-fix-host-tests.log`](before-fix-host-tests.log), at `a65cdc3e`), rejects the bundle named through
  `/private` with the phone's error for the same blob ("unsafe path in manifest:
  blobs/excerpts/7cd18…f.mp3") and the same bundle named under `/var` with "missing file", and `resolve` throws
  `unsafePath` for each missing path it is given through `/private`.
- It was a small bug with a safe outcome: the bundle was still rejected, only with the wrong reason.

### 2.3 Every failing test of `step-1-hosted-tests.log` and its cause

Cause 1 is the installer's `copyItem` (2.1), cause 2 the containment check (2.2). "The next open passed" means a later
open of the same library got past the class check (finding F-1).

| Suite (issues) | Test (cases) | Issues | Cause, and what followed from it | Log lines |
| --- | --- | --- | --- | --- |
| Restore (1) | `rejections` (T46) | 1 | 2: missing-blob-file rejected as `unsafePath`, not `missingFile` (`BackupTests.swift:248`); every other variant rejected as expected | 2139-2303 |
| Migrations (6) | `upgradeFixture` | 1 | 1: the open refused the library; the test stopped there | 2410-2412 |
| | `insufficientSpace` | 1 | 1: the refusal comes before the space check | 2413-2423 |
| | `failedMigration` | 2 | 1: refusal instead of the migration's failure, so `Recovery/` had no snapshot or failed copy (`:121`); the retry open passed | 2424-2435 |
| | `lossyMigration` | 1 | 1 | 2436-2446 |
| | `unconvertibleValue` | 1 | 1 | 2447-2457 |
| Migration put-back (101) | `crashAfterStep` (9) | 33 | 1: refusal instead of the simulated crash (`:54`, 9); so no intent (`:58`, 8); the next open passed and migrated, so no put-back was pending (`:26`, 8) and the library was not v1 (`:30`, 8) | 2462-2621 |
| | `ioErrorDuringPutBack` (4) | 17 | 1: refusal (`:87`, 4); no intent (`:95`, 4); at `snapshotMovedIn` the database was still there (`:98`, 1); the next open migrated (`:26`, `:30`, 4 each) | 2622-2729 |
| | `putBackStillFailingAtNextOpen` (4) | 21 | 1: refusal (`:111`, 4); the second open, still "full", passed and migrated instead of failing (`:115`, 4); no intent (`:122`, 4); `:123` (1); `:26`, `:30` (4 each) | 2730-2835 |
| | `ioErrorAtEveryOperation` (3) | 6 | 1: in the failing open, refusal and no put-back operation recorded (`:205`, `:247`); at the next open (2 cases), refusal instead of the simulated crash (`:183`), then no intent to read (`:162`, test stopped) | 2836-2884 |
| | `abandonedStagingIsCleared` | 4 | 1: its first half passed; the second library was refused (`:355`), so nothing was staged (`:357`) and the resuming open passed and migrated (`:364`, `:368`) | 2885-2902 |
| | `repeatedFailuresKeepRecoveryBounded` | 4 | 1: attempt 1 refused with `Recovery/` empty (`:394`, `:402`); attempts 2-4 passed the check, so 3 failed copies, not 4 (`:410`), and sizes 0 / 774344 / 774344 / 774344 (`:411`) | 2903-2926 |
| | `changedPreStateTakesNewSnapshot` | 1 | 1: the first open's refusal is not the `StoreError` expected (`:430`); the second open passed | 2927-2933 |
| | `preStateDifferingAfterNULTakesNewSnapshot` | 1 | 1: the same (`:484`) | 2937-2943 |
| | `pruneKeepsWhatAPreRestoreIntentNeeds` | 6 | 1: refusal (`:518`), so no intent or snapshot was made and the restore moved a library without one aside (`:523`); `chmod` of the intent that does not exist returned -1 (`:530`, `:533`; `chmod` itself works on the phone: line 2342); the prune results follow (`:532`, `:536`) | 2944-2970 |
| | `badPutBackIntent` (3) | 6 | 1: refusal (`:584`); then no intent file to change (`:575`, test stopped) | 2979-2998 |
| | `restoreOverPendingPutBack` | 2 | 1: refusal (`:632`), so the pre-restore copy has no intent (`:639`) | 2999-3008 |

1 + 6 + 101 = 108, the log's count. All 16 tests that install the v1 fixture with `installV1` failed, and every failing
test is one of them or the rejections test; the tests of those suites that do not use `installV1` passed. Nothing in the
log is left unexplained by the two causes, apart from what finding F-1 explains: why the later opens passed.

### 2.4 Finding F-1, for the owner: the protection check reads a stale class after it changes one

`FileProtector.protect(url)` reads the class through `url`, calls `setAttributes` when it differs, then
`verify(url)` reads it again through the same `URL` value (`FileProtection.swift` lines 96-105 and 174-181). A `URL`
caches resource values: "This method first checks if the URL instance already caches the specified resource values. If
so, it returns the cached resource values to the caller." ([`URL.resourceValues(forKeys:)`](https://developer.apple.com/documentation/foundation/url/resourcevalues(forkeys:)),
read 26 October 2026; it adds that, called from the main thread, the URL removes cached values "the next time the
thread’s run loop runs", and that `removeAllCachedResourceValues()` removes them explicitly.) So `verify` sees the class from
before `setAttributes`, and `protect` reports a mismatch whether or not the change was made.

- **On the phone (inferred from the log):** in 8 failing tests (22 test cases) the same library was opened again after
  the refusal, and that open passed the class check and migrated (table above). Nothing between the two opens changes the
  file's class except the first open's own `setAttributes`. So on iOS 27.0.1 `setAttributes` did change `library.sqlite`
  from no class to class C, and the first open refused it on a stale reading. Apple documents changing an existing
  file's class: "To change the data protection level of an existing file, use the setResourceValue(_:forKey:) method of
  NSURL." ([Encrypting your app's files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files),
  read 26 October 2026.) Only a device run can confirm it by a direct reading.
- **On the Mac:** `commands/probe-host-facts.swift`, section 4, shows it with the screen unlocked: `setAttributes`
  changes a class-B file and a class-B directory to class C without error, the same `URL` value still reports class B,
  and the same value after `removeAllCachedResourceValues()`, a new `URL` and `attributesOfItem` report class C. This job
  saw exactly that at about 02:15 UTC, with the screen unlocked, in a scratch run of the same checks whose output was
  not kept; the saved run, [`probe-host-facts-locked.log`](probe-host-facts-locked.log), was made with the screen
  locked, so its sections 3 and 4 were skipped and the host evidence for F-1 is still to be saved (section 5).
- **What rests on the stale reading:** `DataProtectionTests.mismatchDetected`'s evidence line "changing an existing
  file's class with setAttributes: refused (…); the class is fixed at creation here", on the host
  ([`baseline-host-tests.log`](baseline-host-tests.log)) and on the phone (`step-1-hosted-results.md`), and the records
  that say an existing file's class cannot be changed: `Docs/Stage0/G05-Recovery.md` row 10 and finding F3,
  `Docs/ADRs/0012-retention-backup-restore.md` (the paragraph on copied files and the class-B evidence list),
  `FileProtection.swift` lines 35-37 and the `freshDirectory` comment of `g05-recovery-tool/main.swift`. (With the screen
  locked, `setAttributes` on a class-B file fails with "Operation not permitted", and the test then reports
  `cannotApply`: [`after-fix-host-tests-full.log`](after-fix-host-tests-full.log).)
- **What it does not change:** a library file of the wrong class still fails the open (fail closed); the protected
  copies of this branch create every file with its class, so the check passes at its first reading and never calls
  `setAttributes` in the migration and put-back tests. This branch leaves `protect`, `verify` and those records as they
  are: the change is outside the two failures, and it changes recorded evidence. The proposed change is in section 8.

## 3. The fixes (`c778cd63`)

**Fix 1: every copy into a library is created with the library's class.**

- `MigrationTests.installV1` creates `library.sqlite` with `FileProtector.library.copyFile` (it takes an optional
  source, for the reproduction test).
- `PutBackTests.plantWALAndSHM` copies the database with `copyFile` and writes the planted `-wal` and `-shm` with
  `FileProtector.write`.
- New `FileProtector.copyTree(from:to:)` (`FileProtection.swift`): a new destination tree whose directories are made by
  `ensureDirectory` and whose regular files are copied by `copyFile`, so each item gets the protector's class whatever
  its source's; a link or any other kind of item fails the copy, and a failed copy is removed; it refuses an existing
  destination, a destination inside the source and a class with no protected writing option (TM-F1). The two crash
  drills' `reset()` and the tests' `copyTree` (bundle variants) use it.
- **The guard:** `ProtectedCopyTests.noCopyKeepsTheSourceClass` fails if any `FileManager.copyItem`, `clonefile`,
  `clonefileat`, `fclonefileat`, `copyfile` or `fcopyfile` call comes back anywhere in the spike's code (`Sources`,
  `Tests`, `DeviceTests`, `LockHarness`; whole-line comments and the rest of a line after `//` are not code), and checks
  its own pattern against sample lines first. A test rather than a check in `Scripts/ci.d/71-g05-recovery.sh`: it runs in
  every `swift test` as well as in the drop-in's step 3, needs no unlocked screen (the behavioural check below needs
  class-B keys), and needs no change to a shared script. It reads the sources from the checkout, so it is built for the
  Mac only (not for the simulator or the phone). Its first version used Swift's `Regex`, whose `\b` follows Unicode word
  boundaries, where `default.copyItem` is one word, and found nothing
  ([`before-fix-host-tests-first-guard.log`](before-fix-host-tests-first-guard.log)); the committed version uses
  `NSRegularExpression` and found all five calls on the unchanged code.
- **The behavioural tests:** `ProtectedCopyTests.v1LibraryFromAnotherClass` (the phone's failure, with a class-B source
  standing in for the app bundle's file) and `copyTreeGivesTheClass` (a class-B tree copied comes out class C on every
  file and directory, with the same bytes) need a faithful readback and class-B keys: they run on the phone and on an
  unlocked Mac, and skip in the simulator and on a locked Mac. `copyTreeRefusals` runs everywhere.

**Fix 2: the containment check resolves both paths with realpath(3).** `BackupValidator.resolve` now asks
`isInside(url, root)`, which compares `canonicalPath` of both: realpath(3) of the deepest part of the path that exists,
followed by the components below it that do not exist, as they are. realpath(3) gives `/private/var/…` for a folder
named either way, so the root and a missing file inside it agree. Nothing is weaker:

- every component is still checked for a symbolic link first, as before (`symlinkInBundle`);
- links in the path are now followed even above a missing leaf (before, a missing leaf left the whole path unresolved,
  so a link above it was not followed: `PrivatePathTests.containmentFollowsLinks` checks that a missing file below a link
  to a folder outside the bundle is outside);
- `resolve` now refuses, itself, every path the manifest stage refuses (`BundlePath.isSafeRelativePath`), so the
  appended components can never be `..`, `.` or empty; the manifest stage's own traversal, absolute, backslash, hidden
  and Unicode rejections are unchanged, and both callers (`validate`, `Restore.copyVerified`) only pass paths it accepted.

## 4. Checks run

| Check | Command | Log | Result |
| --- | --- | --- | --- |
| Host suite, unchanged code (`c72247a6`) | `xcrun swift test --force-resolved-versions` | [`baseline-host-tests.log`](baseline-host-tests.log) | 73 tests in 11 suites passed (screen unlocked) |
| Reproduction tests, unchanged code (`a65cdc3e`) | `commands/run-host-tests.sh before-fix-host-tests 'ProtectedCopyTests\|PrivatePathTests'` | [`before-fix-host-tests.log`](before-fix-host-tests.log) | failed as intended: 3 tests, 5 issues (the guard lists the five `copyItem` calls; through `/private` the missing file is an unsafe path); the class-B reproduction skipped (screen locked) |
| The same tests, fixed code (`c778cd63`) | `commands/run-host-tests.sh after-fix-host-tests '…'` | [`after-fix-host-tests.log`](after-fix-host-tests.log) | 6 tests in 2 suites passed; the 2 class-B tests skipped (screen locked) |
| Host suite, fixed code (`c778cd63`) | `commands/run-host-tests.sh after-fix-host-tests-full` | [`after-fix-host-tests-full.log`](after-fix-host-tests-full.log) | 79 tests in 13 suites passed; 6 skipped: the 2 device probes, and the 4 class-B tests (screen locked); the locked-host observation ran and passed |
| The drop-in, from clean (`345dc9c3`, the fixed code) | `commands/run-dropin-clean.sh dropin-run-1` | [`dropin-run-1/console.log`](dropin-run-1/console.log) | steps 1-3 passed (no warning; 79 host tests in 13 suites, the short SIGKILL drills included), then **stopped at its row-10 guard: the screen was locked**, so the class-B lines were missing. `G05_ALLOW_MISSING_CLASS_B` was not set |
| The drop-in's steps 4-15, by hand, after that run (each with the drop-in's own command; not a run of the drop-in, and no evidence for row 10) | `commands/run-dropin-steps-4-15.sh dropin-run-1-steps-4-15` | [`dropin-run-1-steps-4-15/console.log`](dropin-run-1-steps-4-15/console.log), step logs in [`logs/`](dropin-run-1-steps-4-15/logs/) | steps 4-12 passed: the crash drill (900 iterations, 7016 acknowledged saves, 0 failures) and its synchronous=OFF run (150, 0 failures); latency p95 1.133 ms over 2000 saves (indicative; load in the log); the restore drill (49 checks); **the restore crash drill (300 iterations: old library kept 190, restored 110, 0 failures) and the migration put-back crash drill (240 iterations: 66 migrated, 174 put back then migrated, 0 failures), both resetting with the new `copyTree`**; the manifest contract; **73 tests in 13 suites passed on the simulator**; the package and its tests built for a generic iOS device with no warning. Steps 13-15: 13 passed; **14 failed** on the lock harness's quiet-tone test, so the script stopped before its smoke-log check and step 15 (below) |
| Device host for a generic iOS device | `commands/build-devicetests.sh` | [`devicetests-ios-build.log`](devicetests-ios-build.log) | `** TEST BUILD SUCCEEDED **` (unsigned build-for-testing of the app host and the test bundle); 0 warnings in the spike's sources and tests; Xcode's own warning that the app host does not support every orientation is Codex's project setting, left unchanged |
| Contracts | `Scripts/ci.sh contracts` | [`shared-checks/ci-contracts.log`](shared-checks/ci-contracts.log) | 00-git-lfs, 10-contracts and 11-capture-anchor-contracts passed |
| Hard rules | `Scripts/ci.d/13-hard-rules.sh` | [`shared-checks/13-hard-rules.log`](shared-checks/13-hard-rules.log) | passed: 0 findings, 0 stale allowlist entries |
| Dependency lock | `Scripts/ci.d/12-dependency-lock.sh` | [`shared-checks/12-dependency-lock.log`](shared-checks/12-dependency-lock.log) | passed: 0 failures, 0 warnings |
| Host facts, screen locked | `commands/run-probe.sh probe-host-facts-locked` | [`probe-host-facts-locked.log`](probe-host-facts-locked.log) | section 2: under `/var` the root and a missing file keep the same form (the check holds); through `/private` the root loses `/private` and the missing file keeps it (the check fails, as on the phone); realpath(3) gives `/private/var/…` for the root named either way; a missing file below a link is left unresolved by `resolvingSymlinksInPath` (the link not followed), while realpath(3) follows the link outside. Sections 3-4 skipped: no class-B keys |
| Lock harness, step 14 repeated once | `commands/run-harness-checks.sh harness-checks-repeat-1` | [`harness-checks-repeat-1/console.log`](harness-checks-repeat-1/console.log) | the same failure |
| Lock harness on the unchanged code, as a control | `commands/run-harness-checks-control.sh harness-checks-control-c72247a6` | [`harness-checks-control-c72247a6/console.log`](harness-checks-control-c72247a6/console.log) | the same failure on `c72247a6` (Scripts/lib and Spikes/G05-Recovery taken with `git archive` into `.build/scratch`) |

**The lock harness's quiet-tone test failed in every run here, on the unchanged code too.**
`LogAndToneTests.playsQuietly` ("the player plays the tone at the test volume 0.01, unmuted, in the playback category,
and stops (simulator; …)") failed in all three runs (07:38-07:46, 07:52-07:54 and 07:56-07:58 UTC), each time after
about 30 s with `harness: audio: AVAudioPlayer did not start` (`TonePlayer.swift` line 90: `prepareToPlay()` or `play()`
returned false), on this branch and on `c72247a6` alike; the harness's other 48 unit tests passed, and so did its UI
smoke test, which ran after them in each run (07:46, 07:54 and 07:58 UTC). So it is not caused by
this branch, whose changes the tone does not reach. Its cause is not established: the Mac's default output was its
built-in speakers (`system_profiler SPAudioDataType`, read only; nothing on the Mac's audio was changed), and the screen
was locked, but the same test passed with the screen locked on 22 and 23 October
(`Docs/Stage0/evidence/M0-Decisions/assembly/harness-checks-clean/harness-simulator-tests.log`, whose console log
records the lock). The harness's smoke-log check and its step 15 (the app built for a phone) did not run here; the
owner's run of 0.8 covers them.

## 5. What the Mac shows, and what only the phone can show

- **Shown on the Mac:** cause 2 and its fix, completely, by the same code path the phone took (the folder named through
  `/private`); that the guard finds every copy that keeps its source's class, and that none is left; that the new
  `copyTree` refuses what it must; that the whole suite, the SIGKILL drills with the new template copy (300 restore and
  240 migration iterations) and the simulator suite pass on the fixed code; that the device host builds for iOS.
- **Shown on the Mac only with the screen unlocked, not done here:** the class-B reproduction of cause 1
  (`v1LibraryFromAnotherClass`: a class-B library refused before the fix, created class C and opened after it), the
  class-B tree copy, the probe's sections 3-4 (finding F-1), and **report row 10's class-B evidence on this code:
  runbook step 0.8 must be run again on this branch's code, by the owner or by an agent run with the screen unlocked**,
  because the recovery package changed after `9cdb0a02` and the only drop-in run here stopped at its guard. That run
  also gives the lock harness's steps 14-15 another chance: here its quiet-tone test failed on the unchanged code too
  (section 4).
- **Only the phone can show:** the class a file copied out of the app bundle has (none, inferred), the class
  `FileProtector.copyFile` gives `library.sqlite` there (class C expected), that the migration and put-back tests pass
  there with it, whether `setAttributes` changes an existing file's class on iOS 27.0.1 when read back directly (F-1;
  inferred yes), and the latency and Low Power Mode runs of checklist step 2.

## 6. What the owner's re-run of step 1.2 must show

On this branch's code (or `m0-decisions` once it is merged), with the commands of runbook 1.2 (`sylvia_generate
Spikes/G05-Recovery/DeviceTests` first, so the project picks up the two new test files; `DeviceTests` itself is
unchanged):

- `Test run with 73 tests in 13 suites passed`: the 68 of the first run and 5 new ones in 2 new suites (the copy guard
  is built for the Mac only). Exactly the same four skips as before, with their reasons (the two device probes and the
  two contract-fixture tests); the new class tests **run** on the phone.
- In `RestoreTests.rejections`: `rejected missing-blob-file: missing file: blobs/excerpts/7cd1815453c15fb90551526bdc177afb73581a9c8fdc666cae8f05b7cd33710f.mp3`.
- No `protection: library.sqlite has NSFileProtectionNone` anywhere; the migration and put-back tests pass, with their
  evidence lines (for example `v1 fixture upgraded: v1-initial -> …` and `put-back crash after intentWritten: intent on
  disk true, library.sqlite present true`).
- The new evidence lines: `v1 library installed from a class-B source: library.sqlite
  NSFileProtectionCompleteUntilFirstUserAuthentication when created; opened and migrated`; `class-B tree (4 files, 5
  directories) copied with FileProtector.copyTree: ["NSFileProtectionCompleteUntilFirstUserAuthentication": 9]`;
  `missing listed file, bundle under /private/var, as on an iPhone: missing file: blobs/excerpts/…`; and the containment
  line.
- The class-C and class-B readback lines on 53 files and directories, and the SQLite inheritance lines, as in the first
  run.
- Record which way `a file with the wrong class is detected` reports the change ("refused" or "applied and verified"):
  with F-1 unfixed it is expected to say "refused" again, from the stale reading.

## 7. What to test on the Mac

1. With the screen unlocked, runbook step 0.8 on this code: the class-B evidence of report row 10 must be taken again
   (section 5). Expected as 0.8 says, with 79 host tests in 13 suites and 73 simulator tests in 13 suites.
2. With the screen unlocked, from `Spikes/G05-Recovery`:
   `xcrun swift test --force-resolved-versions --filter 'ProtectedCopyTests|PrivatePathTests'`. Expected: `Test run with
   6 tests in 2 suites passed`, none skipped, with the class-B line `v1 library installed from a class-B source: …
   opened and migrated`. To see cause 1 fail on the Mac first, put `FileManager.default.copyItem(at: source, to:
   layout.databaseURL)` back in `installV1` for one run: the test then fails with `library.sqlite has
   NSFileProtectionCompleteUnlessOpen` (and the guard fails too).
3. `xcrun swift Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/probe-host-facts.swift` with the screen unlocked:
   section 4 shows finding F-1 on the Mac.

## 8. Requests for the records (also the job's open items)

These records are outside this branch (another run updates them on `m0-records-update`); each request gives the change.

1. `Docs/Stage0/device-checklists/G05-Recovery.md` step 1.2, "Expected": `Test run with 68 tests in 11 suites passed (the
   five macOS-only tests, …)` becomes `Test run with 73 tests in 13 suites passed (the six macOS-only tests, the three
   SIGKILL drills, the real full-volume test, the locked-host observation and the copy guard, are not built for iOS)`,
   with the simulator's count on this code (73 in 13; `dropin-run-1-steps-4-15/logs/simulator-tests.log`); the four
   skips stay; add the expected lines of section 6 (the missing-blob-file line and the four new evidence lines).
2. Runbook 0.8 and the session log: the recovery package changed after `9cdb0a02` (commits `a65cdc3e` and `c778cd63`),
   so 0.8 must run again on that code with the screen unlocked; this job's run stopped at the guard
   (`dropin-run-1/console.log`).
3. Finding F-1, for the owner (and the technical lead): decide whether to fix `FileProtector.verify` so that it reads
   through a `URL` whose cached values are removed, for example `var fresh = url; fresh.removeAllCachedResourceValues();
   let actual = try protectionClass(of: fresh)`, and then correct `DataProtectionTests.mismatchDetected`'s reading and
   the records that say an existing file's class cannot be changed (G05-Recovery.md row 10 and F3, ADR-0012, the two
   code comments named in 2.4). Until then those records state a conclusion that rests on a stale reading.
4. The integration log and the gate summary: record this branch, its two fixes and its checks (this README).
