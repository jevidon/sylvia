# M0 device fixes, fix-1: the correctness review of `m0-device-fixes`, round 1

For the product owner. The correctness review of branch `m0-device-fixes` at `fdce7cd5` (26 October 2026) reported
four findings: F1 (blocker), F2 (major), F3 and F4 (minor). This folder records how each was checked before anything
changed, what changed, and the checks.

All of it is an agent's work on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) and its own
simulator (Sylvia-M0-devfix-fix1, iPhone 17, iOS 26.5, made for this job and deleted once its checks ended) on 26
October 2026, from 10:10 UTC (the Mac's clock reads NZDT, UTC+13). The Mac's screen was locked throughout: each log records ioreg's
reading, read only. Other jobs shared the Mac, so no timing here is a budget result. **Nothing here ran on a phone.**
This is not a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit. Unchanged: your records on
`m0-decisions`, Codex's `DeviceTests` files, the runbook, the device checklists, the gate reports, the gate summary,
the integration log and the Stage 0 README. Section 6 lists what the records run needs.

Commits on `m0-device-fixes`: `346716ed` the tests that show F1 and F3 failing on the unchanged code; `546a8219` the
fix; `3814a161` the commands that check it; `367789e8` the logs; then this record, with its corrections to
[`../README.md`](../README.md) (F2, F4, and what F1 and F3 change there) and [`../recovery/README.md`](../recovery/README.md),
and the logs of the shared checks.

## 1. In short

| Finding | Checked first | What changed | Shown on the Mac | Only the phone can show |
| --- | --- | --- | --- | --- |
| F1, blocker: `FileProtector.copyTree`'s refusal of a destination inside its source fails under `/private/var`, so `copyTreeRefusals` would fail in the re-run of step 1.2 | Confirmed: through `/private` the copy ran into itself and failed with Cocoa error 514 instead of the refusal | `copyTree` compares both paths resolved by realpath(3), with the helper the missing-file fix introduced. `copyTreeRefusals` now runs through `/private` on the Mac and checks each refusal's reason | Fails on the unchanged code, passes on the fix; the whole host suite, the two SIGKILL drills that use `copyTree`, the simulator suite and the iOS build pass | That iOS 27 resolves the app's folders as the Mac does, so the re-run's `copyTree` line reads `is inside` |
| F2, major: [`../README.md`](../README.md) 7.3 expects no `NSFileProtectionNone` anywhere, but a passing test prints it | Confirmed (first run's log line 2364) | 7.3 now expects no `protection: library.sqlite has NSFileProtectionNone`, and names that one line as expected | Not applicable: a correction of the instructions | None |
| F3, minor: an unlisted dangling link in a bundle is refused as an unsafe path, with its absolute path | Confirmed under both namings on the Mac | The bundle walk names each item by its folder's resolved path and its own name, so a link is refused as a link | Fails on the unchanged code, passes on the fix | The same, on iOS 27 |
| F4, minor: [`../README.md`](../README.md) 7.4 shows `en0` first in the interface list | Confirmed: the probe lists interfaces in `getifaddrs` order | 7.4 shows the list in any order, with `en0` in it | Not applicable | Which interfaces the phone lists, and in which order |

The re-run of step 1.2 still expects `73 tests in 13 suites passed`: fix-1 adds no test. It adds two expected lines
([`../README.md`](../README.md) 7.3).

## 2. F1: `copyTree`'s inside check under `/private/var`

**What the review found.** `copyTree` decided whether the destination is inside the source by comparing two
`standardizedFileURL.path` strings (`FileProtection.swift` lines 168-172 at `fdce7cd5`). Foundation drops a leading
`/private` only from a path that exists. Apple's NSURL `standardizingPath` page: "Remove an initial component of
"/private" from the path if the result still indicates an existing file or directory (checked by consulting the file
system)." NSString's `standardizingPath` page says it as "Removing an initial component of “/private/var/automount”,
“/var/automount”, or “/private” from the path, if the result still indicates an existing file or directory (checked by
consulting the file system)." ([NSURL `standardizingPath`](https://developer.apple.com/documentation/foundation/nsurl/standardizingpath)
and [NSString `standardizingPath`](https://developer.apple.com/documentation/foundation/nsstring/standardizingpath),
both read 26 October 2026.) Under `/private/var` the existing source loses `/private` and a destination that does not
exist yet keeps it, so the check misses a destination inside the source.

**Checked before any change.**

- [`probe-paths.log`](probe-paths.log), section F1 ([`commands/probe-paths.swift`](commands/probe-paths.swift), which
  repeats the unchanged code's comparison on folders of its own): with the folder named under `/var`, both paths keep
  `/var` and `the check sees the destination inside the source: true`; named through `/private`, the source becomes
  `/var/folders/…/Template`, the destination stays `/private/var/folders/…/Template/Library/Copy`, and the check gives
  `false`. realpath(3) gives `/private/var/folders/…/Template` for the source either way.
- [`before-fix-host-tests.log`](before-fix-host-tests.log), on `346716ed` (the unchanged code with the new tests):
  through `/private`, the refusal of a destination inside the source was replaced by `Error Domain=NSCocoaErrorDomain
  Code=514 "The item couldn’t be saved because the file name “Library” is invalid."`, with an `NSFilePath` of
  `…/form-2/Template/Library/Copy/Library/Copy/…` (line 57): the copy ran into itself until a name was too long, as
  the review found. Under `/var` the same case was refused (line 137).
- The phone names the tests' folders `/private/var/mobile/…`. For example,
  `layout.migrationPutBackIntentURL.path → "/private/var/mobile/Containers/Data/Application/…/tmp/g05-tests/…"`
  ([`step-1-hosted-tests.log`](../../G05-Recovery/device/step-1-hosted-tests.log) line 2638). `copyTreeRefusals` has
  no enabled-if trait and is not macOS-only. So the re-run of 1.2 on `fdce7cd5` would have failed this test. That is
  inferred from the code and from the Mac's `/private` run; it was not run on a phone.
- The failure was safe for the data. The failed copy was removed and the source was not changed. In the before-fix
  log, the checks `a copy was left inside the source` and `the source tree changed` recorded no issue.

**Found while checking, and fixed with it.**

- The unchanged check never followed links. A destination named through a link to the source's folder was not
  refused under either naming, and that copy too ran into itself (before-fix log, lines 50 and 59).
- A destination named with `..` below a folder that does not exist, such as `…/Missing/../Template/Library/Copy`.
  Under `/var` the unchanged check refused it, because `standardizedFileURL` resolves `..`. Through `/private` it did
  not, and the failed copy left the folder `Missing` behind (lines 130-132).

**The fix** (`546a8219`):

- `CanonicalPath` (`Spikes/G05-Recovery/Sources/SylviaRecovery/FileSystem.swift`) is the realpath(3) helper that the
  missing-file fix gave `BackupValidator` (`canonicalPath`, `c778cd63`). It moved there so that every containment
  check in the package uses it. `of(_:)` returns realpath(3) of the deepest part of a path that exists, followed by
  the parts below it that do not exist. It returns nil when one of those missing parts is `.` or `..`: where such a
  path leads depends on what is created later, so no check may place it. `relative(_:to:)` compares two such paths
  byte by byte. Swift's `String.hasPrefix` compares characters, and a name that begins with a combining mark joins the
  `/` before it into one character: [`probe-paths.log`](probe-paths.log), last section, `String.hasPrefix("/a/b/") of
  "/a/b/" + U+0301 + "x": false`, while its UTF-8 bytes do start with those of `/a/b/`.
- `copyTree` compares the source's and the destination's `CanonicalPath`. A destination inside the source, by any
  name, is refused as `copy Copy is inside Template: Invalid argument (errno 22)`. A destination it cannot place is
  refused as `… a path that cannot be resolved`. Nothing else in `copyTree` changed.
- `copyTreeRefusals` runs in every form of its folder (`PrivatePathTests.forms`): on the Mac under `/var` and through
  `/private`; on the phone in its own `/private/var/mobile/…` form; on the simulator as given, since its folders are in
  the Mac's home folder, which has no `/private` form. It checks each refusal by its reason (`expectRefusal`), not
  only by its error type, adds the link and `..` destinations above, and prints a new evidence line:
  `copyTree, a destination inside the source: <form>: copy Copy is inside Template: Invalid argument (errno 22)`.

**Shown on the Mac** (Section 5):

- [`after-fix-host-tests.log`](after-fix-host-tests.log): the same tests pass, with `copyTree, a destination inside
  the source: under /var, as the Mac names its temporary folder: copy Copy is inside Template: Invalid argument (errno
  22); through /private, as an iPhone's folders are named: copy Copy is inside Template: Invalid argument (errno 22)`.
- [`drills.log`](drills.log): the drop-in's restore crash drill (300 iterations) and migration put-back crash drill
  (240) passed with 0 failures. Each iteration of both resets its library with `copyTree` from a template beside it.
- The whole host suite and the simulator suite pass, and the app host builds for iOS.

**Only the phone can show** that iOS 27's realpath(3) resolves the app's `/private/var/mobile/…` folders as the Mac's
does, so that the re-run's line reads `copy Copy is inside Template`.

## 3. F3: an unlisted dangling link refused as an unsafe path

**Checked before any change.** [`probe-paths.log`](probe-paths.log), section F3: FileManager's enumerator names every
item `/private/var/folders/…`, whether the bundle's folder is named under `/var` or through `/private`. Standardizing
drops `/private` from the items that exist. A dangling link does not exist when its target is followed, so it keeps
`/private`, and its path is not under the root's under either naming (`under the root: false`). In
[`before-fix-host-tests.log`](before-fix-host-tests.log) the new variant was refused as `unsafe path in manifest:
/private/var/folders/…/Variants/unlisted-dangling-link.sylviabackup/export/markdown/dangling.md` (line 282;
`BackupTests.swift:248`, line 278). The bundle was still refused, so this was safe, but the reason was wrong and the
message carried an absolute path, as the review said. No test had an unlisted dangling link before.

**The fix** (`546a8219`): `BackupValidator.checkTree` (`Container.swift`) names each item by its folder's
`CanonicalPath` and its own name, which it never resolves. The folder exists, since it is being walked. So any link,
dangling or not, is refused as a link. Its `cannot read …` message uses the same naming. An item that is not below the
root, which the enumerator should never give, is still refused as an unsafe path, now by its name, not by an
absolute path. `isInside` keeps its behaviour, now through `CanonicalPath`.

**The test:** `RestoreTests.rejections` gets the variant `unlisted-dangling-link`, which expects `symbolic link in
bundle: export/markdown/dangling.md`. It runs everywhere, the phone included. Its new line there is
`rejected unlisted-dangling-link: symbolic link in bundle: export/markdown/dangling.md`. The test count is unchanged.

**Shown on the Mac:** that line in [`after-fix-host-tests.log`](after-fix-host-tests.log),
[`host-tests.log`](host-tests.log) and [`simulator-tests.log`](simulator-tests.log). The simulator could not have
shown the old failure, since its folders have no `/private` form. That is inferred; the unchanged code was not run on
the simulator.

## 4. F2 and F4: corrections to [`../README.md`](../README.md)

- **F2, confirmed.** `DataProtectionTests.mismatchDetected` (unchanged, `DataProtectionTests.swift` lines 249-250)
  writes a file with `.noFileProtection` and prints `file written with .noFileProtection into the test's temporary
  directory reports: NSFileProtectionNone`. It did so on the phone in a test that passed
  ([`step-1-hosted-tests.log`](../../G05-Recovery/device/step-1-hosted-tests.log) line 2364). 7.3 now expects no
  `protection: library.sqlite has NSFileProtectionNone` anywhere, the wording of recovery README Section 6, and
  names that one line as expected.
- **F4, confirmed.** The probe lists every private address in `getifaddrs` order (`ATSProbeTests.swift` line 55, and
  the `private-ipv4-interfaces=` line at line 134). If 10.71.x.x came from an interface listed before `en0`, the re-run's
  line starts with that interface. 7.4's table now shows `private-ipv4-interfaces=<interface>:<a.b>.x.x,…` with
  `en0:<a.b>.x.x` somewhere in it, for example `pdp_ip0:10.71.x.x,en0:192.168.x.x`. No expected outcome changed.

[`../README.md`](../README.md) also now records F1 and F3: Section 2's description of `copyTree`, Section 5, Section 6,
7.2 item 1 (the Mac's run of the two suites, which now catches F1), 7.3's expected lines, and request 1.
[`../recovery/README.md`](../recovery/README.md) gets notes where it described `copyTree`'s refusals and the
re-run's expected lines.

## 5. Checks

Commands: [`commands/run-host-tests.sh`](commands/run-host-tests.sh) (checks 1 and 2),
[`commands/run-checks.sh`](commands/run-checks.sh) (checks 3-6; each log states its expectation before the run),
[`commands/run-probe.sh`](commands/run-probe.sh) (check 7) and
[`commands/run-shared-checks.sh`](commands/run-shared-checks.sh) (check 8). The screen was locked in every run, so
the class-B tests were skipped. `G05_ALLOW_MISSING_CLASS_B` was never set, and the drop-in itself was not run.

| # | Check | Log | Result |
| --- | --- | --- | --- |
| 1 | The two suites the fix touches and the restore suite, on the unchanged code with the new tests (`346716ed`): `run-host-tests.sh before-fix-host-tests 'ProtectedCopyTests\|PrivatePathTests\|RestoreTests'` | [`before-fix-host-tests.log`](before-fix-host-tests.log) | Failed as intended: `Test run with 21 tests in 3 suites failed … with 7 issues`. Six were in `copyTreeRefusals`: through `/private`, the inside, link and `..` cases threw Cocoa error 514 and `Missing` was left behind; under `/var`, the link case threw 514 and the `..` case was refused for another reason. One was in `rejections`: the dangling link was an unsafe path |
| 2 | The same tests on the fix (`3814a161`: `546a8219` plus the check commands): `run-host-tests.sh after-fix-host-tests '…'` | [`after-fix-host-tests.log`](after-fix-host-tests.log) | `Test run with 21 tests in 3 suites passed`. The 2 class-B tests of `ProtectedCopyTests` skipped (screen locked) |
| 3 | The host suite from clean, `xcrun swift test --force-resolved-versions` in `Spikes/G05-Recovery` after deleting its `.build` (on `3814a161`) | [`host-tests.log`](host-tests.log) | As stated: `Test run with 79 tests in 13 suites passed`, no compiler warning in the spike. 6 skipped: the 2 device probes, and the 4 class-B tests (screen locked). `copy guard: 61 source files …; calls that keep the source's class: 0`. The missing file is `missing file` both ways, and the `copyTree` and dangling-link lines are as in check 2 |
| 4 | The drop-in's steps 8 and 9 with its own arguments, on check 3's build | [`drills.log`](drills.log) | As stated: restore crash drill, 300 iterations, `failures: 0`, `RESULT: PASS`; migration put-back crash drill, 240 iterations, `failures: 0`, `RESULT: PASS` |
| 5 | The package's tests on the simulator, the drop-in's step 11 command | [`simulator-tests.log`](simulator-tests.log) | As stated: `Test run with 73 tests in 13 suites passed`, `** TEST SUCCEEDED **`. Its `copyTree` line reads `as given (no /private form): copy Copy is inside Template: …`. The load average reached 49 while it ran (other jobs) |
| 6 | The recovery suite's app host (Codex's `DeviceTests`, unchanged) for a generic iOS device: `sylvia_generate`, then `xcodebuild build-for-testing`, unsigned | [`devicetests-ios-build.log`](devicetests-ios-build.log) | As stated: `** TEST BUILD SUCCEEDED **`. The three changed test files compiled for arm64 in `SylviaRecoveryTests`, and the three changed source files in `SylviaRecovery`. No warning in the spike. Xcode's 3 warnings are two App Intents metadata notes and Codex's app-host orientation setting, as before |
| 7 | The path probe ([`commands/probe-paths.swift`](commands/probe-paths.swift)): independent of the package, it repeats the unchanged code's comparisons on folders of its own. Run on the commit of this record | [`probe-paths.log`](probe-paths.log) | As described in Sections 2 and 3, and in Section 2's note on byte comparison |
| 8 | `Scripts/ci.sh contracts`, `Scripts/ci.d/13-hard-rules.sh`, `Scripts/ci.d/12-dependency-lock.sh`, on the commit of this record | [`shared-checks/`](shared-checks/) | All passed: `all 3 steps passed` for the contracts; the hard-rules audit `PASS (0 finding(s), 49 allowed, 0 stale allowlist entries, 0 allowlist error(s))`, which read this folder too; the dependency lock with `0 failure(s), 0 warning(s)` |

Not run again, and why:

- The ATS probe: fix-1 changes no ATS code. F4 corrects only the instructions.
- The lock harness, the drop-in's steps 13-15: fix-1 does not change it.
- The crash drill, its synchronous=OFF run and the latency run, the drop-in's steps 4-6: they use neither `copyTree`
  nor the bundle walk.
- The restore drill, step 7, exports and validates bundles, so it walks them. It ran in check 3 as the host suite's
  `RestoreTests.drill`, and passed. Every export also validates its staging bundle with the same walk
  (`Exporter.swift` line 129), so every export test of checks 3 and 5 used the changed walk.

## 6. Requests for the records (another run updates them on `m0-records-update`)

fix-1 changed requests 1, 3, 4 and 11 of [`../README.md`](../README.md) Section 8, which now carry these changes. If
the records run has already applied their earlier text, add:

1. **To request 1's change** (`Docs/Stage0/device-checklists/G05-Recovery.md` step 1, item 2, and runbook 1.2's
   "Expect"), two more expected lines: `rejected unlisted-dangling-link: symbolic link in bundle:
   export/markdown/dangling.md` and `copyTree, a destination inside the source: under /private/var, as on an iPhone:
   copy Copy is inside Template: Invalid argument (errno 22)`. Also add the simulator log of this code,
   `Docs/Stage0/evidence/M0-DeviceFixes/fix-1/simulator-tests.log`. The count stays `Test run with 73 tests in 13
   suites passed`.
2. **To request 3's change** (runbook 0.8, `Docs/Stage0/G05-Recovery.md` row 10, the session log): the recovery
   package also changed in `346716ed` and `546a8219`, so 0.8 runs on code that includes them.
3. **To request 4's change** (`Docs/Stage0/G05-Recovery.md` rows 6 and 7): the fixes include `546a8219`, which fixed
   the same `/private` mismatch in `copyTree` and in the bundle walk. Without it the re-run of 1.2 would fail
   `copyTreeRefusals`.
4. **To request 11's change** (`Docs/Stage0/integration-log.md` and `Docs/Stage0/M0-gate.md`): record the correctness
   review of `fdce7cd5` (26 October 2026, findings F1-F4) and fix-1, with the commits above and Section 5's checks.
5. **If any record copies 7.3's expectation about protection classes:** use "no `protection: library.sqlite has
   NSFileProtectionNone` anywhere". The line `file written with .noFileProtection into the test's temporary directory
   reports: NSFileProtectionNone` is expected, as in the first run (F2).

## 7. A stray file in the main checkout, removed

At 10:13 UTC one of this job's commands wrote a scratch test run's output, by a mistyped redirect, to
`/Users/jevidon/Git/sylvia/.build-dummy-never`, which is in the main checkout, outside this job's worktree. About a
minute later it was moved into this job's scratch folder (`.build/scratch/run0-unfixed.log` in its worktree). Nothing
else in that checkout was touched, and no git command ran there. The file was untracked, so nothing of it was
committed anywhere.
