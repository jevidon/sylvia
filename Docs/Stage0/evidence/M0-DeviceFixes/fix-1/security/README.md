# M0 device fixes, fix-1: the security review of `m0-device-fixes`, round 1

For the product owner. The security review of branch `m0-device-fixes` (26 October 2026) reported eight findings: S1
(major) and S2-S8 (minor). Its line numbers are those of `fdce7cd5`, the commit the correctness review also read. This
fix starts from `31e460e6`, after the correctness review's fix-1 ([`../README.md`](../README.md)), which had already
fixed S1, S3 and the code of S2. This folder records how each finding was checked before anything changed, what
changed, and the checks.

All of it is an agent's work on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) and its own
simulator (Sylvia-M0-devfix-fix1-sec, iPhone 17, iOS 26.5, made for this job and deleted at 11:38 UTC, once its checks
had ended) on 26 October 2026, from 11:00 UTC (the Mac's clock reads NZDT, UTC+13). The Mac's screen was locked
throughout: each log records ioreg's reading, read only. Other jobs shared the Mac, so no timing here is a budget
result. **Nothing here ran on a phone.** This is not a device result, a role sign-off, an ADR approval (decision D-6) or
the M0 exit. Unchanged: your records on `m0-decisions`, Codex's `DeviceTests` files, the runbook, the device
checklists, the gate reports, the gate summary, the integration log and the Stage 0 README. Section 9 lists what the
records run and the technical lead need.

Commits on `m0-device-fixes`: `e022cea7` the fix; `a6c705e4` the commands that check it; `87a2154a` the logs; then this
record, with its corrections to [`../../README.md`](../../README.md) (7.4, the guard's description and the requests,
among others), [`../../recovery/README.md`](../../recovery/README.md) and [`../../ats/README.md`](../../ats/README.md),
and the redaction check widened to all four of the first run's ATS records; then the logs of the shared checks.

## 1. In short

| Finding | Checked first | What changed | Shown on the Mac | Left for the phone or for others |
| --- | --- | --- | --- | --- |
| S1, major: the owner's README 7.3 expects no `NSFileProtectionNone` anywhere, but a passing test prints it | Confirmed at `fdce7cd5` (README line 295) against the first run's log, line 2364. Already corrected by fix-1 (`29afe758`, its finding F2) | Nothing more: [`../../README.md`](../../README.md) 7.3 (its third bullet) has the wording the review asked for, and no other text on the branch keeps the old one | Not applicable: instructions | None |
| S2: `isInside` on its own counted a `..` below a missing folder as inside | Confirmed on the reviewed code: `missing/../../Outside/b.md` and `missing/..` were inside, under `/var` and through `/private` ([`before-fix-isinside-fdce7cd5.log`](before-fix-isinside-fdce7cd5.log)). Already fixed in the code by fix-1 (`546a8219`): the same checks pass on `31e460e6` ([`fix-1-isinside-31e460e6.log`](fix-1-isinside-31e460e6.log)) | `PrivatePathTests.containmentFollowsLinks` checks `isInside` itself on those paths, and `isInside`'s comment states the rule | The test passes on the Mac in both namings, and on the simulator (Section 8) | The same checks run on the phone in the re-run of step 1.2, in its `/private/var/mobile` form; no test is added |
| S3: `copyTree`'s refusal of a destination inside its source depended on the path's spelling | Already fixed by fix-1 (`546a8219`, its finding F1): both paths are compared after realpath(3), and `copyTreeRefusals` covers `/private` and a linked parent | Nothing | This fix's host run: `copy Copy is inside Template` under `/var` and through `/private` ([`host-tests.log`](host-tests.log)) | As fix-1 says |
| S4: the copy guard missed some spellings, so "anywhere" was overstated | Confirmed: three files planted in a scratch copy held six class-keeping calls; the guard as reviewed reported none of them and passed ([`before-fix-guard-planted.log`](before-fix-guard-planted.log)) | The guard strips `//` comments outside string literals only, matches across line breaks, and also finds `linkItem`, link(2), linkat(2) and the Objective-C `copyItemAt…:` and `linkItemAt…:` forms. Its descriptions say what it reads and what a text check cannot see | The widened guard reports the six planted calls and nothing else ([`after-fix-guard-planted.log`](after-fix-guard-planted.log)); on the branch it passes: `61 source files …; calls that keep the source's class: 0` | Nothing: the guard is built for the Mac only |
| S5, older than this branch: a folder above a bundle file, swapped for a link between the checks and `copyFile`'s open, is followed | Confirmed from the code and Apple's open(2) page: `O_NOFOLLOW` covers the last component only (Section 5). The review's swap test is in its own scratch copy and was not run again here | `copyFile`'s comment, which claimed more, now says what `O_NOFOLLOW` covers. The hardening itself is **not done here** | Not applicable: a comment | The technical lead: request 2 in Section 9 |
| S6: 7.4's re-run writes the raw log, with the phone's whole Wi-Fi address, into the evidence folder | Confirmed: the runbook's Section 2 rule; and none of the first run's four records holds a whole IPv4 address, so they were cut before their commit ([`redaction-check.log`](redaction-check.log), section 1) | [`../../README.md`](../../README.md) 7.4 cuts every address with the runbook's own command right after the run, then checks it; the ATS README points there | The command gives back the first run's masked form exactly on its 49 address lines, and the check then prints nothing ([`redaction-check.log`](redaction-check.log)) | Your re-run applies it; request 1 asks the runbook to say it in 1.3 |
| S7: the host-facts probe leaves its folder behind when the screen is locked | Confirmed: the probe as committed left `g05-devicefix-probe-4F3AF1C6` ([`before-fix-probe-locked.log`](before-fix-probe-locked.log)), and the folder the review found, `g05-devicefix-probe-2BEBD5E8`, was still there | The probe no longer ends with `exit()` before its removal: it removes its folder on every path and says so in its last line. The two folders were removed ([`probe-leftovers-removed.log`](probe-leftovers-removed.log)) | `its folder was removed`, and no folder of the probe's left ([`after-fix-probe-locked.log`](after-fix-probe-locked.log)) | Its unlocked path (sections 3 and 4): your optional run of 7.2, item 3 |
| S8: the ATS probe's comment stated as fact that the Wi-Fi load "goes nowhere else" | Confirmed: the first run's load to a private address, 10.71.x.x (most likely not the Wi-Fi address; inferred, as the honesty review's HON-3 asked to say), went to iCloud Private Relay (`step-01-ats.log` lines 393-394) | The comment says the local refusal is expected, seen on the simulator and not yet on a phone. Two comment lines; `ATSProbeTests.swift:164` does not move | Only comment lines changed, and the probe builds for a device ([`atsprobe-ios-build.log`](atsprobe-ios-build.log)) | What the phone does with its Wi-Fi address: the re-run of 1.3 |

The re-run of step 1.2 still expects `73 tests in 13 suites passed`, and the Mac's host suite 79 in 13: this fix adds no
test, and no expected line of 7.3 changes.

## 2. S4: the copy guard

**What the review found.** `ProtectedCopyTests.noCopyKeepsTheSourceClass` read each line only up to its first `//`, so a
call after a string literal such as `"file://"` was cut off; its pattern needed a `(` right after the name, so the
Objective-C `[fm copyItemAtURL:…]` did not match; and it did not look for `FileManager.linkItem`, whose hard link is the
source file itself and so keeps its class. No such call is in the spike (the review's search, and this fix's run).

**Checked before any change** ([`commands/run-scratch-guard.sh`](commands/run-scratch-guard.sh)). In a scratch copy of
the spike at `31e460e6` (a `git archive` under `.build/scratch`, never the working tree), three files were written into
`LockHarness/Core`, which the guard reads and the package never compiles: a Swift file with a `copyItem` call after
`let scheme = "file://";`, a `linkItem` call and a `link(a, b)` call; an Objective-C file with `copyItemAtURL:` and
`linkItemAtPath:`; and a C file with `copyfile` and its `(` on the next line. The guard as reviewed passed:
`copy guard: 64 source files …; calls that keep the source's class: 0`
([`before-fix-guard-planted.log`](before-fix-guard-planted.log)).

**The fix** (`e022cea7`, `ProtectedCopyTests.swift`):

- `code(of:)` removes each line's `//` comment, but a `//` inside a string literal starts none. Block comments stay as
  text: they can add a hit, never hide one.
- The pattern also matches `linkItem`, `link` and `linkat` before a `(`, and the selectors `copyItemAtURL:`,
  `copyItemAtPath:`, `linkItemAtURL:` and `linkItemAtPath:`. It runs over a whole file's code, so `\s` spans line
  breaks, and each hit names its line. `.mm` files are read too (there are none).
- Its samples, checked first, grew from 6 to 15: one for each new spelling, and the cases that must not match
  (`unlink`, `symlink`, `createSymbolicLink`, a call in a `//` comment after a string, a call in a `///` comment).
- What it is: a text check of the Swift, C and Objective-C files of `Sources`, `Tests`, `DeviceTests` and
  `LockHarness`. A call made another way (a selector built at run time, a function value) is not found; its comment and
  the READMEs now say so instead of "anywhere".

**Shown on the Mac.** With the same planted files, the widened guard failed with one issue that listed exactly the six
planted calls, `PlantedS4.swift` lines 7, 11 and 15, `PlantedS4.m` lines 6 and 10 and `PlantedS4.c` line 6, and no
sample failed ([`after-fix-guard-planted.log`](after-fix-guard-planted.log)). On the branch it passes and prints the
same line as before: `copy guard: 61 source files in Sources, Tests, DeviceTests and LockHarness; calls that keep the
source's class: 0` ([`host-tests.log`](host-tests.log)).

## 3. S2: `isInside` and a `..` below a missing folder

**What the review found.** `BackupValidator.isInside`, on its own, kept a missing component as text, `..` included, so
`root/missing/../../Outside/b.md` counted as inside. `resolve`, its only caller, refuses any `..`, `.` or empty
component first (`Container.swift`, the `isSafeRelativePath` guard), so no bundle path was affected.

**Checked before any change** ([`commands/run-scratch-isinside.sh`](commands/run-scratch-isinside.sh)). The new
expectations, taken from this fix's `PrivatePathTests.swift`, were run on their own in scratch copies:

- on the reviewed code (`fdce7cd5`) they failed with 4 issues: under `/var` and through `/private`,
  `missing/../../Outside/b.md -> true` and `missing/.. -> true`
  ([`before-fix-isinside-fdce7cd5.log`](before-fix-isinside-fdce7cd5.log));
- on `31e460e6` they passed: fix-1's `CanonicalPath.of` (`FileSystem.swift`) returns nil when a missing component is
  `.` or `..`, so `isInside` is false ([`fix-1-isinside-31e460e6.log`](fix-1-isinside-31e460e6.log)).

In both, the two controls held: `export/../export/markdown/a.md` (a `..` in the part that exists) is inside, and
`export/../../Outside/b.md` is not.

**The fix** (`e022cea7`). `PrivatePathTests.containmentFollowsLinks` now checks `isInside` itself on those four paths,
in every form of its folder, so the rule cannot come undone unseen. `isInside`'s comment (`Container.swift`) states that
a `.` or `..` below a component that does not exist is never inside, whoever calls it. The test count is unchanged.

## 4. S7: the host-facts probe's folder

**Checked before any change.** The probe (`../../recovery/commands/probe-host-facts.swift`) removed its folder with a
top-level `defer`, and with the screen locked it ended with `exit(0)`, which skips it. Run as committed, with the
screen locked, it left `g05-devicefix-probe-4F3AF1C6`, and the review's leftover from 07:59:21 UTC,
`g05-devicefix-probe-2BEBD5E8`, was still in the temporary folder
([`before-fix-probe-locked.log`](before-fix-probe-locked.log)).

**The fix** (`e022cea7`). Sections 1-4 are now a function that returns early when the screen is locked. The probe
catches an error from it, removes its folder, prints `its folder was removed: …` (or `NOT removed`, with exit status
1), and only then exits. Nothing it measures changed.

**Shown on the Mac.** [`probe-leftovers-removed.log`](probe-leftovers-removed.log) lists both leftover folders (each
held only `bundle/export/escape`, a link to the folder's own `outside`, and two empty folders) and removes them with
`rm -R`, which does not follow a link. [`after-fix-probe-locked.log`](after-fix-probe-locked.log): sections 1 and 2 as
before, then `its folder was removed: g05-devicefix-probe-6E43E07A`, and no folder of the probe's left after the run.
Its unlocked path, sections 3 and 4, did not run here (screen locked); it runs in your optional 7.2, item 3.

## 5. S5: a folder swapped for a link after the checks (not changed here)

**What the review found.** `BackupRestorer.prepare`'s `copyVerified` checks a listed file with
`BackupValidator.resolve` and `requireRegularFile`, then `FileProtector.copyFile` opens it with `O_NOFOLLOW`
(`Restore.swift` lines 93-95; `FileProtection.swift`, `copyFile`). A folder above the file that is swapped for a link
between those checks and the open is followed.

**Checked.** Apple's open(2) page in the Xcode 27.1 macOS SDK (`MacOSX.sdk/usr/share/man/man2/open.2`, read 26 October
2026) says of the two flags: "If O_NOFOLLOW is used in the mask and the target file passed to open() is a symbolic link
then the open() will fail." and "If O_NOFOLLOW_ANY is used in the mask and any component of the path passed to open()
is a symbolic link then the open() will fail." So `O_NOFOLLOW` covers the last component only, as the review says. Its
swap test is in the review's own scratch copy; it was not run again here. The bound the review gives holds: the copy
must still match the manifest's size and digest (`Restore.swift` lines 98-99), or the restore fails.

**Changed: the comment only.** `copyFile`'s comment said that "a bundle changed after validation cannot substitute a
link"; it now says that this holds for the file itself, that a folder above it swapped for a link is followed, and that
a restore keeps only a copy with the manifest's digest. **Not changed: the open.** The finding is older than this
branch, and every restore and export copies through `copyFile`: changing how it opens files would change what the
re-run of step 1.2 is about to check on the phone, for a gain that the digest check already bounds. It is request 2.

## 6. S6: the ATS re-run's log and the phone's address

**Checked.** 7.4 sent the raw `xcodebuild` output into `Docs/Stage0/evidence/G05-AI/device/step-01-ats-run2.log`. That
output holds the phone's Wi-Fi address whole: in CFNetwork's lines and in the expected failure at
`ATSProbeTests.swift:164`, whose `got \(result)` prints the `URLError` with its URL (the first run's log has the same
fields, masked: `NSErrorFailingURLStringKey=http://10.71.x.x:58688/v1/models`, line 397). The runbook's Section 2
forbids recording an address beyond its first two octets (`M0-device-runbook.md` line 103), G0.5 AI's checklist asks
the same ("IP addresses beyond the first two octets … removed", its Recording paragraph), and the runbook's Session 4
gives the command (line 542). The first run's records were cut before their commit: the check below prints nothing for
any of the four files in `Docs/Stage0/evidence/G05-AI/device/`, and in `step-01-ats.log` even the public `192.0.2.1`
reads `192.0.x.x`.

**The fix.** [`../../README.md`](../../README.md) 7.4 now has, right after the run and before anything is copied from
the log or committed:

```sh
perl -pi -e 's/\b(\d{1,3}\.\d{1,3})\.\d{1,3}\.\d{1,3}\b/$1.x.x/g; s/\.[A-Za-z0-9-]+\.ts\.net\b/.[tailnet].ts.net/g' Docs/Stage0/evidence/G05-AI/device/step-01-ats-run2.log
perl -ne 'print if /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/' Docs/Stage0/evidence/G05-AI/device/step-01-ats-run2.log
```

The first is the runbook's own command; the second must print nothing. 7.4 also says that the `public-ip=` lines then
read `192.0.x.x`, as in the first run's record, and that the `.txt` files are written from the cut log. The ATS
README's Section 5 points to 7.4.

**Shown on the Mac** ([`commands/check-redaction.sh`](commands/check-redaction.sh),
[`redaction-check.log`](redaction-check.log)). The first run's 49 address lines, each masked address given two made-up
octets in a scratch file (77 whole addresses, not written to the log), came back from the command identical to the
committed lines, and the check then printed nothing. On sample lines with documentation addresses only (RFC 5737), it
cut a URL, a CFNetwork endpoint, the `public-ip=` line, an IPv4-mapped IPv6 address and a MagicDNS name, and left
`Version 27.0.1 (Build 24A446)` as it was.

## 7. S8: the ATS probe's comment

`probeAddress`'s comment said that a load ATS lets through "is refused by the machine itself (URLError -1004, as on the
simulator) and goes nowhere else". On a phone that is not established: the first run's load to a private address,
10.71.x.x (most likely not the Wi-Fi address; inferred, as the honesty review's HON-3 asked to say), went to iCloud
Private Relay (`step-01-ats.log` lines 393-394), and the ATS README's Section 5 lists the relay carrying
even the load to the phone's own address as a possible result. The comment now reads: "A load ATS lets through is
expected to be refused there by the machine itself (URLError -1004): seen on the simulator; not yet seen on a phone,
where the first run's load went to iCloud Private Relay (below)." It stays three lines, so the default variant's device
expectation is still at `ATSProbeTests.swift:164`, the line that 7.4, the ATS README and requests 6 and 7 of the
owner's README name ([`atsprobe-ios-build.log`](atsprobe-ios-build.log) checks it).

## 8. Checks

Commands: [`commands/run-probe.sh`](commands/run-probe.sh) and
[`commands/remove-probe-leftovers.sh`](commands/remove-probe-leftovers.sh) (S7),
[`commands/run-scratch-guard.sh`](commands/run-scratch-guard.sh) (S4),
[`commands/run-scratch-isinside.sh`](commands/run-scratch-isinside.sh) (S2),
[`commands/check-redaction.sh`](commands/check-redaction.sh) (S6), [`commands/run-checks.sh`](commands/run-checks.sh)
(checks 9-12; each log states its expectation before the run) and
[`commands/run-shared-checks.sh`](commands/run-shared-checks.sh) (check 13). The screen was locked in every run, so the
class-B tests were skipped. `G05_ALLOW_MISSING_CLASS_B` was never set, and the drop-in itself was not run.

| # | Check | Log | Result |
| --- | --- | --- | --- |
| 1 | The probe as committed, screen locked (`31e460e6`) | [`before-fix-probe-locked.log`](before-fix-probe-locked.log) | Left `g05-devicefix-probe-4F3AF1C6` behind, as the review found |
| 2 | Removal of the probe's two leftover folders | [`probe-leftovers-removed.log`](probe-leftovers-removed.log) | Both listed, then removed; none left |
| 3 | The fixed probe, screen locked (`a6c705e4`) | [`after-fix-probe-locked.log`](after-fix-probe-locked.log) | `its folder was removed`; none left; exit 0 |
| 4 | The guard as reviewed over six planted calls, in a scratch copy of `31e460e6` | [`before-fix-guard-planted.log`](before-fix-guard-planted.log) | As expected: passed, 0 of 6 reported |
| 5 | The widened guard (`a6c705e4`'s test file) over the same planted calls | [`after-fix-guard-planted.log`](after-fix-guard-planted.log) | As expected: failed with 1 issue listing the 6 planted calls and nothing else; no sample failed |
| 6 | The new `isInside` expectations on the reviewed code, in a scratch copy of `fdce7cd5` | [`before-fix-isinside-fdce7cd5.log`](before-fix-isinside-fdce7cd5.log) | As expected: failed with 4 issues (2 paths, 2 namings) |
| 7 | The same on fix-1's code, in a scratch copy of `31e460e6` | [`fix-1-isinside-31e460e6.log`](fix-1-isinside-31e460e6.log) | As expected: passed |
| 8 | The check on the first run's four records; the runbook's redaction command and the check on the first run's line shapes and on sample lines (run on `87a2154a` with the script as this record's commit has it: its first section read one record before, four now) | [`redaction-check.log`](redaction-check.log) | As expected: exit 0; no whole IPv4 address in any of the four records |
| 9 | The recovery host suite from clean, `xcrun swift test --force-resolved-versions` after deleting the spike's `.build` (`a6c705e4`) | [`host-tests.log`](host-tests.log) | As expected: `Test run with 79 tests in 13 suites passed`, no compiler warning in the spike. 6 skipped: the 2 device probes and the 4 class-B tests (screen locked). The guard and `containmentFollowsLinks` passed; fix-1's evidence lines as before (`missing file` both ways, `copy Copy is inside Template` both ways, the dangling link refused as a link) |
| 10 | The package's tests on this job's simulator, the drop-in's step 11 command | [`simulator-tests.log`](simulator-tests.log) | As expected: `Test run with 73 tests in 13 suites passed`, `** TEST SUCCEEDED **`; `containmentFollowsLinks` passed in its one form there, `as given (no /private form)`. The load average reached 24 while it ran (other jobs and the simulator's boot) |
| 11 | The recovery suite's app host (Codex's `DeviceTests`, unchanged) for a generic iOS device: `sylvia_generate`, then `xcodebuild build-for-testing`, unsigned | [`devicetests-ios-build.log`](devicetests-ios-build.log) | As expected: `** TEST BUILD SUCCEEDED **`; `PrivatePathTests.swift` and `ProtectedCopyTests.swift` compiled for arm64 in `SylviaRecoveryTests`, `FileProtection.swift` and `Container.swift` in `SylviaRecovery`; no warning in the spike. Xcode's 3 warnings are two App Intents metadata notes and Codex's app-host orientation setting, as before |
| 12 | The ATS probe for a generic iOS device, unsigned, and the extent of the change to `ATSProbeTests.swift` | [`atsprobe-ios-build.log`](atsprobe-ios-build.log) | As expected: 0 changed lines that are not comments; 289 lines before and after; line 164 unchanged; `** TEST BUILD SUCCEEDED **`, `ATSProbeTests.swift` compiled for arm64 in all three test targets, no warning in `Spikes/G05-AI` code |
| 13 | `Scripts/ci.sh contracts`, `Scripts/ci.d/13-hard-rules.sh`, `Scripts/ci.d/12-dependency-lock.sh`, on the commit of this record (`31b09186`, no uncommitted file) | [`shared-checks/`](shared-checks/) | All passed: `all 3 steps passed` for the contracts; the hard-rules audit `PASS (0 finding(s), 49 allowed, 0 stale allowlist entries, 0 allowlist error(s))`, which read this folder too; the dependency lock with `0 failure(s), 0 warning(s)` |

Not run again, and why:

- The crash drills, the latency run and the restore drill: this fix changes no code they run (two comments in the
  spike's sources; the rest is tests).
- The ATS probe's tests on the simulator: only two comment lines changed (check 12 shows the diff). The probe was built
  for a device, which compiles the changed file in all three test targets.
- The lock harness: not changed.

## 9. Requests (open items)

The records are updated by another run on `m0-records-update`; this fix changes none of them.

1. **Runbook 1.3, and its repeat (request 2 of [`../../README.md`](../../README.md)).** After the command block, add:
   "Before you copy any line from the log or commit it, cut every IPv4 address in it to its first two octets (Section
   2; G0.5 AI checklist, Recording) with Session 4's command: `perl -pi -e
   's/\b(\d{1,3}\.\d{1,3})\.\d{1,3}\.\d{1,3}\b/$1.x.x/g; s/\.[A-Za-z0-9-]+\.ts\.net\b/.[tailnet].ts.net/g'
   Docs/Stage0/evidence/G05-AI/device/step-01-ats.log`. Then `perl -ne 'print if
   /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/' Docs/Stage0/evidence/G05-AI/device/step-01-ats.log` must print nothing.
   The `public-ip=` lines then read `192.0.x.x`." The probe's own lines mask the private address, but CFNetwork's lines
   and the failure messages print it whole (finding S6).
2. **For the technical lead (finding S5, older than this branch; not changed here).** Make `FileProtector.copyFile`
   refuse a link anywhere in the source's path below the bundle, not only in its last component. The review proposes
   `O_NOFOLLOW_ANY`, which it gives as available from macOS 11 and iOS 14 (not checked here: the Xcode 27.1 SDKs define
   it in `sys/fcntl.h`, "no symlinks allowed in path", without an availability note). Opened with a full path, it would
   also refuse the `/var` link above the Mac's temporary folder and an iPhone's container folders. One way:
   `copyVerified` opens the validated bundle root once with `open(root, O_RDONLY | O_DIRECTORY | O_CLOEXEC)` and each
   listed file with `openat(rootFD, entry.path, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)`, so the flag
   applies to the bundle's own components only; the copy then goes on as now. A test like the review's `swapAfterChecks`
   (a folder swapped for a link after the checks) should then see `ELOOP` (errno 62), as the review saw with
   `O_NOFOLLOW_ANY`. It changes how every restore opens files, so it needs the host suite, the restore drills and a
   device run of step 1.2 after it.
3. **`Docs/Stage0/integration-log.md` and `Docs/Stage0/M0-gate.md` (with request 11 of
   [`../../README.md`](../../README.md)):** record the security review of `fdce7cd5` (26 October 2026, findings S1-S8)
   and this fix: commits `e022cea7`, `a6c705e4` and `87a2154a`, this record and Section 8's checks. S1 and S3 were
   fixed by fix-1 of the correctness review; S5's hardening is open (request 2).
