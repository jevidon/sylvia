# M0 device fixes: phone B's first runs of Session 1, steps 1.2 and 1.3

For the product owner. Branch `m0-device-fixes`, made from `m0-decisions` at `c72247a6`: the commit that holds your
records of 26 October 2026 NZDT (session log rows 3a-3d). It merges two fix branches, both made from the same commit:

- `m0-device-fixes-recovery` at `fd2a2624`, merged at `37cb53b8`: the two failures of step 1.2, the recovery suite.
  Its full record is [`recovery/README.md`](recovery/README.md).
- `m0-device-fixes-ats` at `e4586a83`, merged at `eebbb457`: the failure of step 1.3, the ATS probe. Its full record is
  [`ats/README.md`](ats/README.md).

`2d188e06` then added the commands that check the merged tree and `eacc8ddb` their logs ([`assembly/`](assembly/));
`163d76b8` and `fdce7cd5` add this README and the logs of the shared checks. After the correctness review of
`fdce7cd5`, fix-1 (from `346716ed`) fixed the same `/private` mismatch in two more checks and corrected Sections 7.3
and 7.4. Its record is [`fix-1/README.md`](fix-1/README.md).

All of this is agents' work on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) and its
simulators (iPhone 17, iOS 26.5) on 26 October 2026. Times are UTC; the Mac's clock reads NZDT, UTC+13. **Nothing
here ran on a phone.** This is not a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit.
Your records on `m0-decisions` are unchanged. The runbook, checklists and reports are left to the records run;
Section 8 lists what they need.

**What to test on the Mac: Section 7.2. What to run again on phone B: Sections 7.3 and 7.4, after the merge of
Section 7.1.**

## 1. In short

| What failed on phone B | Cause, confirmed from the code and the phone's own logs | Fix | Shown on the Mac | Only the phone can show |
| --- | --- | --- | --- | --- |
| Step 1.2: the migration and put-back tests refused `library.sqlite` as `NSFileProtectionNone` (107 of the 108 issues) | The tests' setup, not D17. They copied the v1 fixture out of the app bundle with `FileManager.copyItem`, which keeps the source file's protection class, and the copy came out with none. The recovery code's own class check then refused it, as it should | Every copy into a library is now created with the library's class. A guard test fails if a class-keeping copy comes back | The guard found all 5 class-keeping copies before the fix and finds none now. The class-B reproduction needs the screen unlocked and **has not run yet** (Section 2) | That the copy gets class C on iOS and that the 16 migration and put-back tests pass |
| Step 1.2: the missing-blob-file backup was rejected as "unsafe path" instead of "missing file" (1 issue) | A small bug with a safe outcome. The path check compared `/private/var/…` with `/var/…` for a file that does not exist | The containment check now uses realpath(3) | Reproduced and fixed: "unsafe path" before the fix, "missing file" after | That iOS 27 resolves the app's folders the same way |
| Step 1.3: the private-address load timed out in all three variants | The probe took the phone's first private IPv4 address, 10.71.x.x, which is not Wi-Fi's. The phone sent the load to iCloud Private Relay, which could not reach it | On a device the probe loads only the Wi-Fi (en0) address, and it logs every interface's private address | The simulator's choice and every expectation are unchanged, and the device code builds | What the phone does with its Wi-Fi address |

**After review (fix-1).** The same `/private` mismatch as in failure 2 was in two more checks. One is
`FileProtector.copyTree`'s refusal of a destination inside its source: the re-run of 1.2 would have failed
`copyTreeRefusals`. The other is the bundle walk's naming of a dangling link. Both now use realpath(3) too, and on the
Mac `copyTreeRefusals` now also runs with its folder named through `/private`
([`fix-1/README.md`](fix-1/README.md)).

The first run already answered step 1.3's main question: on iOS 27.0.1, ATS did **not** block cleartext HTTP to a
private IP literal (Section 4). The fix keeps the default variant's expectation of Apple's documented block. So in the
re-run, the default variant is expected to fail at `ATSProbeTests.swift:164`, and that failure is the device finding.

## 2. Failure 1 (step 1.2): library files with no protection class

**What the phone showed.** The app-hosted recovery suite ran 68 tests in 11 suites, with 4 expected skips, and failed
with 108 issues ([`step-1-hosted-tests.log`](../G05-Recovery/device/step-1-hosted-tests.log) line 3038). In each
failing migration and put-back test case, the first open of the library refused it: `protection: library.sqlite has
NSFileProtectionNone, expected NSFileProtectionCompleteUntilFirstUserAuthentication` (the first at line 2411).
Recovery README Section 2.3 traces each of the 108 issues to its cause.

**Why.**

- `MigrationTests.installV1` installed the v1 library with `FileManager.default.copyItem(at: Self.fixture, to:
  layout.databaseURL)` (`MigrationTests.swift` line 33 at `c72247a6`). All 16 tests that use it failed, and nothing
  else in the migration and put-back suites failed.
- `copyItem` keeps the source file's class. The recovery code says so itself: files Sylvia copies "are created the
  same way by `copyFile`, never with `FileManager.copyItem`, which keeps the source file's class"
  (`Spikes/G05-Recovery/Sources/SylviaRecovery/FileProtection.swift` lines 17-19 at `c72247a6`).
- On the phone the fixture is inside the app (Codex's `DeviceTests/project.yml` copies `Fixtures` into the test
  bundle). The copy came out with no class, so the fixture in the app has none. That is inferred; it was not read
  directly.
- Every open of the library sets and checks the class of its database files, and refuses a wrong one. So D17's check
  did its job; the tests' setup was wrong.
- The Mac and the simulator could not show it. On the Mac new files get class C by default, so the suite passed there
  ([`recovery/baseline-host-tests.log`](recovery/baseline-host-tests.log): 73 tests in 11 suites on `c72247a6`), and
  the simulator reports class C for every file.

**A correction, finding F-1, for you and the technical lead.** The class named in the refusal is a stale reading.
`FileProtector.protect` reads the class, changes it with `setAttributes`, then reads it again through the same `URL`
value, and a `URL` caches what it has read. Apple: "This method first checks if the URL instance already caches the
specified resource values. If so, it returns the cached resource values to the caller."
([`URL.resourceValues(forKeys:)`](https://developer.apple.com/documentation/foundation/url/resourcevalues(forkeys:)),
read 26 October 2026.) In 8 of the failing tests (22 test cases), a later open of the same library passed the check
and migrated. So `setAttributes` almost certainly did change the class on the phone (recovery README Section 2.4).
The fixes do not depend on this: the copies now have class C from the start, so these tests never change a class.
F-1 itself is left for your decision (Section 8, request 5).

**Not causes, changed anyway.** The tests' helper that copies backup bundles (`Support.swift` line 84; a restore copies
a bundle's files with the library's class whatever theirs is) and the crash drills' template copies
(`MigrationCrashDrill.swift` and `RestoreCrashDrill.swift`, line 114; macOS only). They were changed so that no copy in
the spike keeps its source's class (recovery README Section 2.1).

**The fix** (`c778cd63`):

- `installV1` creates `library.sqlite` with `FileProtector.library.copyFile`. The put-back test's saved database and
  its planted `-wal` and `-shm` files are also created with the library's class.
- A new `FileProtector.copyTree` copies a folder tree and gives every folder and file the protector's class. It refuses
  links and other special files, and leaves nothing behind when it fails. The crash drills and the bundle helper use it.
  As committed in `c778cd63`, its refusal of a destination inside the source compared Foundation's standardized paths.
  Under `/private/var`, as on the phone, that refusal failed, and the copy ran into itself until a name was too long.
  fix-1 (`546a8219`) compares the paths after realpath(3) instead ([`fix-1/README.md`](fix-1/README.md) Section 2).
- A guard, `ProtectedCopyTests.noCopyKeepsTheSourceClass`, fails if `copyItem`, `clonefile` or `copyfile` comes back
  anywhere in the recovery spike. It reads the source files, so it runs on the Mac only.

**Shown on the Mac, and not.**

- The guard listed the five class-keeping copies on the unchanged code
  ([`recovery/before-fix-host-tests.log`](recovery/before-fix-host-tests.log), at `a65cdc3e`). On this branch it finds
  none: `copy guard: 61 source files in Sources, Tests, DeviceTests and LockHarness; calls that keep the source's class:
  0` ([`assembly/host-tests.log`](assembly/host-tests.log)).
- The whole host suite, the simulator suite and the crash drills pass on this branch (Section 5).
- **Not yet run anywhere:** the two tests that reproduce failure 1 itself. `v1LibraryFromAnotherClass` installs the v1
  library from a class-B source and expects a class-C copy that opens; `copyTreeGivesTheClass` copies a class-B tree.
  A Mac can make a file of another class only with its class-B keys, which it has only while its screen is unlocked.
  The tests were written at 07:32 UTC, and every run of them since (the recovery job's and this one's) found the
  Mac's screen locked, so both skipped; the simulator always skips them. They run on the phone, and on the Mac with
  the screen unlocked: Section 7.2, item 1, runs them before the phone does.

## 3. Failure 2 (step 1.2): a missing backup file reported as an unsafe path

**What the phone showed.** `RestoreTests.rejections` rejected the missing-blob-file backup, but as `unsafe path in
manifest: blobs/excerpts/7cd18….mp3` instead of a missing file (`step-1-hosted-tests.log` lines 2261-2265). Every other
damaged backup was rejected with the expected error.

**Why.** Before it checks that a listed file exists, the restore checks that the file's path stays inside the backup
folder (`BackupValidator.resolve`, `Container.swift` lines 170-182 at `c72247a6`). It compared both paths after
Foundation's `resolvingSymlinksInPath`. Apple: "If the name of the receiving path begins with /private, this property
strips off the /private designator, provided the result is the name of an existing file."
([NSURL `resolvingSymlinksInPath`](https://developer.apple.com/documentation/foundation/nsurl/resolvingsymlinksinpath),
read 26 October 2026.) On the phone the tests' folders are under `/private/var/mobile/…` (log line 2145). The existing
backup folder lost its `/private`; the missing file kept it. So the comparison failed before the missing-file check
could run. On the Mac the tests' folders are named `/var/folders/…`, which hides the bug. It is a real bug, but small
and safe: the backup was still rejected, only with the wrong reason.

**The fix** (`c778cd63`). The check resolves both paths with realpath(3), which gives `/private/var/…` however the
folder is named. For a file that does not exist, it resolves the deepest part of the path that does and keeps the rest
as it is. Nothing is weaker: links are still refused, and they are now followed even above a missing file; `resolve`
now also refuses, itself, every path the manifest stage refuses. fix-1 moved this realpath(3) helper to
`CanonicalPath` (`FileSystem.swift`) and made `copyTree` and the bundle walk use it as well
([`fix-1/README.md`](fix-1/README.md)).

**Shown on the Mac.** `PrivatePathTests` names the backup's folder through `/private`, as a phone does. On the
unchanged code it gave the phone's exact error for the same file
([`recovery/before-fix-host-tests.log`](recovery/before-fix-host-tests.log)). On this branch it gives "missing file"
both ways: `missing listed file, bundle under /var, as the Mac names its temporary folder: missing file: …; through
/private, as an iPhone's folders are named: missing file: …` ([`assembly/host-tests.log`](assembly/host-tests.log)).
It cannot show how iOS itself resolves the app's folders; the phone's re-run does.

## 4. Failure 3 (step 1.3): the ATS probe's private-address timeouts

**What the phone showed.** In all three variants the load to the private address 10.71.x.x timed out (URLError
-1001). The probe expects an ATS block (-1022) in the default variant and a local refusal (-1004) in
`local_networking` and `cidr_exception`. The public IP literal was blocked by ATS and `localhost` loaded in every
variant ([`step-01-ats.txt`](../G05-AI/device/step-01-ats.txt)).

**Why.**

- The probe's address function was written for the simulator, which shares the Mac's network interfaces. It took the
  first private IPv4 address of any interface (`ATSProbeTests.swift` lines 45-61 at `c72247a6`). On a phone that need
  not be the Wi-Fi address, and 10.71.x.x was not: phone B's Wi-Fi interface is en0
  (`interface: en0[802.11]`, [`step-01-ats.log`](../G05-AI/device/step-01-ats.log) line 394), and the build Mac's only
  address in the probe's private ranges (10/8, 172.16/12 and 192.168/16) is 192.168.x.x on en0.
- The phone's log shows the load going to iCloud Private Relay over Wi-Fi, which answered `Received response code 502
  for 10.71.x.x:58688, unreachable through proxy` (`step-01-ats.log` lines 393-394, and the same in each variant). The
  request then ran to its timeout.
- No log names the interface that held 10.71.x.x. The cellular one is likelier (`pdp_ip0` was up:
  `step-01-ats-initial.log` line 2571); a VPN tunnel is possible. The re-run's new line will name it.

**The default variant's answer: a device finding, recorded as it is.** When ATS blocks a load, the phone logs
`Cannot start load of Task … since it does not conform to ATS policy`. That line appears for the public IP literal and
for the qualified name in every variant (`step-01-ats.log` lines 416 and 424, 515 and 523, 614 and 622), never for the
private address, whose load started a connection instead. So on iOS 27.0.1 (24A446) ATS did not block cleartext HTTP
to a private IP literal, as on the iOS 26.5 simulator (G0.5 AI finding F1). Apple's page on `NSAllowsLocalNetworking`
says both "In iOS 17, iPadOS 17, and macOS 14, ATS no longer allows connections to IP addresses by default." and
"While ATS doesn’t block local loads by default in newer versions of the OS, consider setting NSAllowsLocalNetworking
to YES as a declaration of intent, if appropriate, even if you don’t support older OS versions."
([NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking),
read 26 October 2026.) The phone blocked the public IP literal and let the private one through. That fits both
sentences if "local loads" includes private addresses, but that is a reading; the page does not say so. Either way it
agrees with your decision D-9 (b): Sylvia's own `EndpointPolicy` is the cleartext gate on every OS version.

**The fix** (`907538f5`, in `Spikes/G05-AI/ATSProbe/Tests/ATSProbeTests.swift` only):

- On a device the probe loads only the Wi-Fi interface's (en0) private address, never a cellular, tunnel or other
  interface's. On the simulator it still takes the first private address of any interface.
- Each variant logs `ATS-PROBE variant=… private-ipv4-interfaces=<interface>:<a.b>.x.x,… rule=…`, and the result line
  now names the interface: `private-ip=<a.b>.x.x interface=en0 result=…`.
- With no private address on Wi-Fi, the test loads nothing and stops with `private-ip=none precondition-not-met (ATS
  not probed; not an ATS result)`.
- A new test checks the rule on made-up interface lists, so each variant now runs 14 tests (13 before).
- Unchanged: every variant's expectations, including the default variant's device expectation of Apple's documented
  block (now at `ATSProbeTests.swift:164`, with a comment that records the first run), the probe apps' Info.plists and
  `EndpointPolicy`.

**Shown on the Mac.** The probe builds for a device, and on the simulator every variant passes with the same address
and result as before (Section 5). What a phone does with a load to its own Wi-Fi address, only the re-run shows.

## 5. Checks on this branch (the merged tree)

Commands: [`assembly/commands/run-checks.sh`](assembly/commands/run-checks.sh) (checks 1-6) and
[`assembly/commands/run-shared-checks.sh`](assembly/commands/run-shared-checks.sh) (check 7). Each log states its
expectation before the run, the commit, the screen's lock state (read with ioreg, read only) and the load. Checks 1-6
ran on `2d188e06` from 08:15 to 08:25 UTC with the screen locked throughout; [`assembly/lock-wait.log`](assembly/lock-wait.log)
has the readings taken afterwards, while this job waited for an unlock that did not come. Other jobs shared the Mac, so
no timing here is a budget result. The two device builds' logs are summaries (result, error and warning lines, what
was compiled, the products); their whole xcodebuild output stayed in the job's scratch folder and is not committed.

| # | Check | Log | Result |
| --- | --- | --- | --- |
| 1 | Recovery host suite: `xcrun swift test --force-resolved-versions` in `Spikes/G05-Recovery`, from clean | [`assembly/host-tests.log`](assembly/host-tests.log) | Passed: 79 tests in 13 suites. 6 skipped: the 2 device probes and, with the screen locked, the 4 class-B tests. The copy guard finds no class-keeping copy. The `/private` test: "missing file" both ways |
| 2 | G0.5 recovery's drop-in from clean, `Scripts/ci.sh g05-recovery`, without `G05_ALLOW_MISSING_CLASS_B` | [`assembly/dropin/console.log`](assembly/dropin/console.log) | Steps 1-3 passed (no compiler warning; 79 host tests in 13 suites). Then the drop-in **stopped at its row-10 guard**: the screen was locked, so the class-B lines were missing. Not a passing run, and no class-B evidence for report row 10 |
| 3 | The drop-in's steps 4-15 by hand, each with the drop-in's own command, after that stop (not a run of the drop-in) | [`assembly/dropin-steps-4-15/console.log`](assembly/dropin-steps-4-15/console.log) and its `logs/` | Steps 4-13 passed: the crash drill (900 iterations, 8,494 acknowledged saves, 0 failures) and its synchronous=OFF run (150, 0 failures); latency p95 1.203 ms over 2,000 saves (indicative); the restore drill (49 checks); the restore crash drill (300 iterations: old library kept 189, restored 111, 0 failures) and the migration put-back crash drill (240 iterations: 64 migrated, 176 put back then migrated, 0 failures), both resetting with the new `copyTree`; the manifest contract; the simulator suite, 73 tests in 13 suites; the iOS build, with no warning in the spike; the lock harness's lock. **Step 14 failed**: the lock harness's quiet-tone test stopped with `harness: audio: AVAudioPlayer did not start` after 30 s (its other 48 tests and the app's UI smoke test passed), so step 15 did not run. The same test failed three times on this Mac earlier that day, on the unchanged code too (recovery README Section 4), so these fixes did not cause it; its cause is not established |
| 4 | The recovery suite's app host (`Spikes/G05-Recovery/DeviceTests`) for a generic iOS device: unsigned build-for-testing | [`assembly/devicetests-ios-build.log`](assembly/devicetests-ios-build.log) | `** TEST BUILD SUCCEEDED **`; both new test files compiled for arm64; no warning in the spike's code |
| 5 | The ATS probe for a generic iOS device: unsigned build-for-testing | [`assembly/atsprobe-ios-build.log`](assembly/atsprobe-ios-build.log) | `** TEST BUILD SUCCEEDED **`; `ATSProbeTests.swift` compiled for arm64 in all three test targets; no warning in `Spikes/G05-AI` code |
| 6 | The ATS probe's tests on the simulator, every variant (an extra check of the merged tree) | [`assembly/atsprobe-simulator-tests.log`](assembly/atsprobe-simulator-tests.log) | Each variant: `✔ Test run with 14 tests in 2 suites passed`, `private-ipv4-interfaces=en0:192.168.x.x rule=simulator: the first of any interface` and `private-ip=192.168.x.x interface=en0 result=URLError -1004 classified=host_unreachable`; the public IP literal blocked (-1022) and `localhost` loaded; the suspension UI test passed |
| 7 | `Scripts/ci.sh contracts`, `Scripts/ci.d/13-hard-rules.sh`, `Scripts/ci.d/12-dependency-lock.sh` | [`assembly/shared-checks/`](assembly/shared-checks/) | All passed: the 3 contract steps; the hard-rules audit `PASS (0 finding(s), …)`; the dependency lock with 0 failures and 0 warnings. Run on the commit that added this README, so the audit read it too |

Each fix branch's own checks, before the merge: recovery README Section 4 and ATS README Section 4.

The checks above are records of `2d188e06`. fix-1 changed the recovery spike's code after them and ran again what that
change affects, on `3814a161`: the two suites it touches before and after the fix; the host suite from clean (79 tests
in 13 suites); the restore and migration put-back crash drills, which reset with `copyTree`; the simulator suite (73 in
13); and the app host's iOS build. It ran the shared checks on its record's commit ([`fix-1/README.md`](fix-1/README.md)
Section 5). The screen was again locked throughout.

## 6. What only the phone can show

- Failure 1: that `FileProtector.copyFile` gives the library class C on iOS 27 when its source is in the app, and that
  the 16 migration and put-back tests then pass. Also the first run of the two class-B tests, unless the Mac runs them
  first (Section 7.2).
- Failure 2: that iOS resolves the app's `/private/var/mobile/…` folders as the fix expects, so the missing file is
  reported as missing. With fix-1, the same goes for `copyTree`'s refusal of a destination inside its source (`copy
  Copy is inside Template`) and for the dangling link refused as a link.
- F-1: whether `setAttributes` changes an existing file's class on iOS 27. The first run suggests it does; the
  mismatch test still reads the stale class until F-1 is fixed.
- Failure 3: what the phone does with a load to its own Wi-Fi address in each variant, and which interface held
  10.71.x.x.
- The rest of step 1.2, the latency runs, is still pending, as before.

## 7. What to do next

### 7.1 Merge this branch into `m0-decisions`, between sittings

Do it between sittings, not while a run (such as the audio run of 1.4) or Codex is working in `~/Git/sylvia-sessions`.

1. Commit the last sitting's records on `m0-decisions` first (runbook 0.3, step 6). Then check that nothing is left
   uncommitted: `git -C ~/Git/sylvia-sessions status --short` should print nothing that belongs to the sitting.
2. See where `m0-decisions` is: `git -C ~/Git/sylvia-sessions log --oneline -1`.
   - If the line starts with `c72247a6`, the merge simply moves `m0-decisions` forward to this branch.
   - If `m0-decisions` has moved on, check whether its new commits changed the files this branch changes:
     `git -C ~/Git/sylvia-sessions diff --stat c72247a6 HEAD -- Spikes/G05-Recovery/Sources Spikes/G05-Recovery/Tests
     Spikes/G05-AI/ATSProbe/Tests Docs/Stage0/evidence/M0-DeviceFixes`. If it prints nothing, the merge cannot
     conflict: go on. If it lists files, the merge may stop with a conflict. Then run `git -C ~/Git/sylvia-sessions
     merge --abort`, which puts `m0-decisions` back as it was, and ask an agent to redo this branch from the new
     `m0-decisions`.
3. Merge: `git -C ~/Git/sylvia-sessions merge m0-device-fixes`. If `m0-decisions` has moved on, git opens an editor
   for the merge message; add `--no-edit` to accept git's own.
4. Check, then record: `git -C ~/Git/sylvia-sessions merge-base --is-ancestor m0-device-fixes HEAD && echo merged`
   prints `merged`. Note `git -C ~/Git/sylvia-sessions rev-parse HEAD` in the session log as the commit the next
   sitting builds from (runbook 0.3, steps 4 and 5).

What the merge changes outside its own evidence folder: the recovery spike's `Sources` and `Tests`, and the ATS probe's
test file (`git diff --stat c72247a6 m0-device-fixes -- Apps Packages Spikes Fixtures Scripts Contracts
Docs/Stage0/device-checklists` lists these 12 files and nothing else: 10 before fix-1, which added `FileSystem.swift`
and `BackupTests.swift`). So steps 1.1 and 1.4, which build none of
them, need no repeat (runbook 0.3, step 7). Steps 1.2 and 1.3 run again (7.3, 7.4), and runbook 0.8 must run again
(7.2), because it builds the recovery spike.

### 7.2 What to test on the Mac (screen unlocked)

Each item needs the screen unlocked for its whole run (class-B keys); `caffeinate -d` keeps the display awake. Run
them from the root of `~/Git/sylvia-sessions` after the merge, in zsh. Commit the logs they write on `m0-decisions`
(runbook 0.3, step 6).

1. **First, the class-B tests of failure 1** (a few minutes, most of it building the package; they have never run):

   ```sh
   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-host-tests.sh unlocked-class-b-tests 'ProtectedCopyTests|PrivatePathTests'
   ```

   It writes `Docs/Stage0/evidence/M0-DeviceFixes/recovery/unlocked-class-b-tests.log`, with the commit and the
   screen's state. Expect `✔ Test run with 6 tests in 2 suites passed`, no test skipped, and the lines `v1 library
   installed from a class-B source: library.sqlite NSFileProtectionCompleteUntilFirstUserAuthentication when created;
   opened and migrated` and `class-B tree (4 files, 5 directories) copied with FileProtector.copyTree:
   ["NSFileProtectionCompleteUntilFirstUserAuthentication": 9]`. Also expect, since fix-1, `copyTree, a destination
   inside the source: under /var, as the Mac names its temporary folder: copy Copy is inside Template: Invalid
   argument (errno 22); through /private, as an iPhone's folders are named: copy Copy is inside Template: Invalid
   argument (errno 22)`. `copyTreeRefusals` now also names its folder through `/private`, as the phone does, so this
   run checks the fix of review finding F1 on the Mac before the phone does. If any test fails, ask an agent before
   you run step 1.2 on the phone, which runs the same tests.
2. **Runbook 0.8**, exactly as the runbook gives it (10-15 minutes). It must run again because the recovery spike
   changed after `9cdb0a02`. Expect what 0.8 says, now with 79 host tests in 13 suites and 73 simulator tests in 13
   suites. The lock harness's quiet-tone test failed on this Mac in every run on 26 October 2026. If it fails again
   (`harness: audio: AVAudioPlayer did not start`), the drop-in stops at its step 14 and the last line reads `drop-in
   exit 1`. Report row 10's class-B lines are then still in `row10-unlocked/host-tests.log`, since step 3 writes them
   before the harness runs, but the whole drop-in has not passed: record that and ask an agent.
3. **Optional, for finding F-1** (seconds):

   ```sh
   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-probe.sh probe-host-facts-unlocked
   ```

   It writes `Docs/Stage0/evidence/M0-DeviceFixes/recovery/probe-host-facts-unlocked.log`. Its section 4 should show
   `setAttributes` changing a class-B file and folder to class C while the same `URL` value still reports class B, and a
   new `URL` reporting class C: the stale reading behind F-1, saved on the Mac.
4. Nothing new for the ATS probe: it ran on the simulator here (Section 5, check 6).

### 7.3 Phone B: step 1.2 again (the app-hosted recovery suite)

As Session 1 says: phone B on the cable, unlocked, Auto-Lock Never, not in Low Power Mode; a terminal at the root of
`~/Git/sylvia-sessions`, set up as runbook Section 4 says (its `source` line and `DEVICE_ID`). Use the runbook's 1.2
command, but save the log under a new name, so that the earlier logs stay as recorded. For example:

```sh
mkdir -p Docs/Stage0/evidence/G05-Recovery/device
sylvia_generate Spikes/G05-Recovery/DeviceTests
cd Spikes/G05-Recovery
xcodebuild test -project DeviceTests/G05RecoveryDeviceTests.xcodeproj -scheme G05RecoveryDeviceTests -destination "id=$DEVICE_ID" -derivedDataPath .build/DerivedData \
  -disableAutomaticPackageResolution -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z 2>&1 \
  | tee ../../Docs/Stage0/evidence/G05-Recovery/device/step-1-hosted-run2-tests.log
cd ../..
```

`sylvia_generate` must run first: it adds the two new test files to the generated project. Expected now:

- `✔ Test run with 73 tests in 13 suites passed` and `** TEST SUCCEEDED **`: the first run's 68 tests plus 5 new ones
  in 2 new suites (the copy guard runs on the Mac only). This needs fix-1: on `fdce7cd5`, `copyTreeRefusals` would
  have failed here (review finding F1; [`fix-1/README.md`](fix-1/README.md) Section 2).
- Exactly the same four skipped tests as before, each with its reason: the lock probe, the persistence probe and the
  two contract-fixture tests. The new class-B tests run.
- No `protection: library.sqlite has NSFileProtectionNone` anywhere. One line still names `NSFileProtectionNone`, as
  in the first run (its line 2364), and is expected: `file written with .noFileProtection into the test's temporary
  directory reports: NSFileProtectionNone`. It comes from the unchanged `DataProtectionTests.mismatchDetected`, which
  writes such a file on purpose and passes. The migration and put-back tests pass with their lines, such as `v1
  fixture upgraded: v1-initial -> v2-rating-review-note -> v2-recommendation-date-precision ->
  v2-edition-cover-thumbnail; snapshot …` and `put-back crash after intentWritten: intent on disk true, library.sqlite
  present true`.
- `rejected missing-blob-file: missing file: blobs/excerpts/7cd1815453c15fb90551526bdc177afb73581a9c8fdc666cae8f05b7cd33710f.mp3`.
- `rejected unlisted-dangling-link: symbolic link in bundle: export/markdown/dangling.md`: a damaged-bundle variant
  that fix-1 added to the same test (review finding F3).
- The five new lines:
  - `v1 library installed from a class-B source: library.sqlite NSFileProtectionCompleteUntilFirstUserAuthentication when created; opened and migrated`
  - `class-B tree (4 files, 5 directories) copied with FileProtector.copyTree: ["NSFileProtectionCompleteUntilFirstUserAuthentication": 9]`
  - `copyTree, a destination inside the source: under /private/var, as on an iPhone: copy Copy is inside Template: Invalid argument (errno 22)` (since fix-1)
  - `missing listed file, bundle under /private/var, as on an iPhone: missing file: blobs/excerpts/7cd1815453c15fb90551526bdc177afb73581a9c8fdc666cae8f05b7cd33710f.mp3`
  - `containment check (realpath of the deepest existing part): under /private/var, as on an iPhone: a missing leaf is inside; a missing leaf below a link to outside the root is outside; resolve refuses links and the manifest's unsafe paths`
- As in the first run: class C and class B each read back on 53 files and directories, the class-B SQLite line and the
  writer pragmas line.
- Record whether the line `changing an existing file's class with setAttributes:` says "refused" or "applied and
  verified". "Refused" is expected while F-1 is unfixed.

If a migration or put-back test still names a protection class, the missing file is still an unsafe path, the dangling
link is not refused as a link, or the `copyTree` line names anything but `is inside`, record it as it is and ask an
agent. Then carry on with step 1.2's latency runs as the runbook says. Since the recovery code
changed, this run's p95 replaces the first run's 2.292 ms as the first of the six (runbook 0.3, step 7: the later
result counts).

### 7.4 Phone B: step 1.3 again (the ATS probe)

Before the run:

- Phone B on Wi-Fi with a private IPv4 address (10/8, 172.16/12 or 192.168/16): Settings › Wi-Fi › the network ›
  IP Address. The Mac's network gives one.
- Local Network on for "ATS default", "ATS local" and "ATS CIDR" (Settings › Privacy & Security › Local Network).
- Note, without changing it, whether iCloud Private Relay is on (Settings › your name › iCloud › Private Relay): the
  first run's load went through it.

(These setting names were not checked on a device.)

In the same terminal, use the runbook's 1.3 command with a new log name, for example:

```sh
sylvia_generate Spikes/G05-AI/ATSProbe
cd Spikes/G05-AI/ATSProbe
xcodebuild test -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination "id=$DEVICE_ID" \
  -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution \
  DEVELOPMENT_TEAM=A4KBDX665Z CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  2>&1 | tee ../../../Docs/Stage0/evidence/G05-AI/device/step-01-ats-run2.log
cd ../../..
```

If iOS asks for Local Network access, allow it and run the command again, as 1.3 says. Expected in each variant (the
probe's expectations are unchanged since `d5336111`; ATS README Section 5):

| Variant | Expected `ATS-PROBE` lines | Expected result |
| --- | --- | --- |
| `default` (no ATS key) | `private-ipv4-interfaces=<interface>:<a.b>.x.x,… rule=device: en0 (Wi-Fi) only`, listing every interface that holds a private address in the order the system gives them, `en0:<a.b>.x.x` among them but not necessarily first (for example `pdp_ip0:10.71.x.x,en0:192.168.x.x`); then `private-ip=<a.b>.x.x interface=en0 result=URLError -1004 …` (the phone refuses a load to itself, as the Mac does for the simulator); `public-ip=192.0.2.1 result=URLError -1022 ats-blocked=true`; `localhost=success(200)` | `✘ Test run with 14 tests in 2 suites failed … with 1 issue`: `plainHTTPToAPrivateLANAddress()` fails at `ATSProbeTests.swift:164` ("documented iOS 17+ behaviour: ATS blocks cleartext to an IP literal without an exception"). **That failure is the device finding (ATS did not block), not a fault of the probe.** If this line shows -1022 instead, ATS blocked the Wi-Fi address and the test passes: record it, since it differs from the first run |
| `local_networking` | The same lines, with -1004 for the private address | `✔ Test run with 14 tests in 2 suites passed` |
| `cidr_exception` | The same | `✔ Test run with 14 tests in 2 suites passed` |

Also expected: `plainHTTPToAnotherDeviceOnTheLAN()` skipped in each variant, and the suspension UI test passing again.
Because of the default variant's expected failure, xcodebuild ends with `** TEST FAILED **`. The new
`private-ipv4-interfaces=` lines should name en0 and the interface that held 10.71.x.x, in the order of the system's
interface list (`getifaddrs`), which the probe keeps (`ATSProbeTests.swift`, `privateIPv4Addresses`).

Results that are not ATS results (ATS README Section 5):

| Result | Meaning | What to do |
| --- | --- | --- |
| `private-ip=none precondition-not-met …` | The phone had no private IPv4 address on Wi-Fi | Join a Wi-Fi network that gives one, and run again |
| `classified=local_network_permission_denied` | Local Network was off for that app, or its prompt denied the first load | Turn it on, or allow the prompt, and run again |
| -1001 again, with a `[privacy_proxy] … for <a.b>.x.x:…` line for the Wi-Fi address | Private Relay carried even the load to the phone's own address | Record it and ask an agent |
| Anything else | Not foreseen | Record it and ask an agent |

Record what 1.3 asks (the three `private-ip=` lines, the three `public-ip=` lines, the three `localhost=` lines, the
summary lines and the exact iOS version and build) plus the three `private-ipv4-interfaces=` lines, in a new file
beside the first run's, such as `step-01-ats-run2.txt`; and the suspension test's lines as step 4 asks, also in a new
file. Until then G0.5 AI row D1 stays failed, as you recorded it.

## 8. Record changes this needs (requests)

Another run updates the runbook, checklists and reports on `m0-records-update`; this branch changes none of them. Each
request gives the change; most come from the fix branches' open items. fix-1 changed requests 1, 3, 4 and 11. If the
records run applied their earlier text, [`fix-1/README.md`](fix-1/README.md) Section 6 gives what to add.

1. **Recovery suite's expected count.** In `Docs/Stage0/device-checklists/G05-Recovery.md` step 1, item 2
   ("Expected"), and in runbook 1.2's "Expect", replace `Test run with 68 tests in 11 suites passed (the five
   macOS-only tests, the three SIGKILL drills, the real full-volume test and the locked-host observation, are not
   built for iOS)` with `Test run with 73 tests in 13 suites passed (the six macOS-only tests, the three SIGKILL
   drills, the real full-volume test, the locked-host observation and the copy guard, are not built for iOS)`. Say
   that the simulator's count on this code is 73 in 13
   (`Docs/Stage0/evidence/M0-DeviceFixes/assembly/dropin-steps-4-15/logs/simulator-tests.log`, and after fix-1
   `Docs/Stage0/evidence/M0-DeviceFixes/fix-1/simulator-tests.log`). The four skips stay. Add the expected lines of
   Section 7.3: the missing-blob-file and unlisted-dangling-link lines and the five new lines.
2. **Log names of a repeated run.** Runbook 1.2 and 1.3 write fixed log names (`step-1-tests.log`,
   `step-01-ats.log`), so a repeat would overwrite a first run's record. Name a repeat's files apart, as Sections 7.3
   and 7.4 do (`step-1-hosted-run2-tests.log`, `step-01-ats-run2.log`, `step-01-ats-run2.txt`).
3. **Runbook 0.8, `Docs/Stage0/G05-Recovery.md` row 10 and the session log's paragraph on 0.8.** The recovery
   package changed after `9cdb0a02` (`a65cdc3e`, `c778cd63`, and fix-1's `346716ed` and `546a8219`), so 0.8 must run
   again on this code with the screen unlocked. Both agent runs of the drop-in on this code stopped at its guard, the
   screen being locked (`Docs/Stage0/evidence/M0-DeviceFixes/recovery/dropin-run-1/console.log` and
   `Docs/Stage0/evidence/M0-DeviceFixes/assembly/dropin/console.log`).
4. **`Docs/Stage0/G05-Recovery.md` rows 6 and 7, and its section "App-hosted physical-device result".** Add the
   diagnosis, pointing to this README: row 6's failure was the tests' setup (the `copyItem` of the app-bundle fixture,
   refused by the library's own class check); row 7's was the containment check's `/private` mismatch for a missing
   file (the right rejection with the wrong reason). Add the fixes, on `m0-device-fixes`: `c778cd63`, and `546a8219`
   (fix-1), which fixed the same mismatch in `copyTree` and the bundle walk; without it the re-run would fail
   `copyTreeRefusals`. Add that the re-run of 1.2 is pending. Both rows stay "failed (device)" until it passes.
5. **Finding F-1, your decision with the technical lead; left unfixed here.** `FileProtector.verify` reads the class
   through the same `URL` value that `protect` read before `setAttributes`, so it sees the cached class (Apple's
   `URL.resourceValues(forKeys:)` page). `protect` therefore reports a mismatch even when the change took effect: seen
   on this Mac in an earlier probe run whose output was not saved, and inferred on the phone from 8 tests whose later
   opens passed. Proposed change, for the technical lead to check: in `verify`, `var fresh = url;
   fresh.removeAllCachedResourceValues(); let actual = try protectionClass(of: fresh)`. Then correct the records that
   say an existing file's class cannot be changed: `DataProtectionTests.mismatchDetected`'s reading,
   `Docs/Stage0/G05-Recovery.md` row 10 and F3, `Docs/ADRs/0012-retention-backup-restore.md` (the copied-files
   paragraph and the class-B evidence list), `FileProtection.swift` lines 35-37, and the `freshDirectory` comment in
   `g05-recovery-tool/main.swift`. Until then the device and host lines "refused … the class is fixed at creation
   here" rest on a stale reading.
6. **`Docs/Stage0/device-checklists/G05-AI.md` step 1.** In item 3 ("Expected"), first bullet, after `be refused
   locally (URLError -1004).` append: "On a device the test loads only the phone's Wi-Fi (en0) private address (since
   `907538f5`). Its line reads `ATS-PROBE variant=… private-ip=<a.b>.x.x interface=en0 result=…`, after a
   `private-ipv4-interfaces=` line that lists every interface holding a private address. `private-ip=none
   precondition-not-met` means the phone had no private IPv4 address on Wi-Fi: join such a network and run again; it
   is not an ATS result. The first run (iOS 27.0.1, 26 October 2026 NZDT) was not blocked by ATS in the default
   variant, so a -1004 there fails the test at `ATSProbeTests.swift:164` as that device finding
   (`Docs/Stage0/evidence/M0-DeviceFixes/ats/README.md`). Each variant runs 14 tests." In item 4 ("Record"), after
   "the three `ATS-PROBE variant=… private-ip=…` lines," insert "the three `private-ipv4-interfaces=` lines,".
7. **Runbook 1.3.** In the paragraph starting "When iOS asks for Local Network access for a probe app", after "are
   refused locally (-1004);" insert "since `907538f5` the private address is the phone's Wi-Fi (en0) address, named by
   `interface=en0`; `private-ip=none precondition-not-met` means Wi-Fi had no private IPv4 address (join one and run
   again; not an ATS result); the first run's default variant was not blocked
   (`evidence/M0-DeviceFixes/ats/README.md` section 6), so a -1004 there fails the test at `ATSProbeTests.swift:164`
   as the recorded device finding;". In its Record sentence, after "the three `ATS-PROBE variant=… private-ip=…`
   lines," insert "the three `private-ipv4-interfaces=` lines,". Make this change in the same commit as request 6 and
   re-run the runbook content check (`Docs/Stage0/evidence/M0-Decisions/assembly/commands/runbook-content-check.sh`):
   the backticked `interface=en0` and `private-ipv4-interfaces=` count as markers, so they must appear in both
   documents.
8. **`Docs/Stage0/G05-AI.md` row D1**, results column: after "D-9 exception remains; no minimum-OS claim." append
   "Diagnosed in `evidence/M0-DeviceFixes/ats/README.md`: the probe loaded a non-Wi-Fi private address (10.71.x.x),
   which the phone sent to iCloud Private Relay; ATS did not block it in any variant (no ATS-policy line for it, unlike
   the public IP and the qualified name). On a device the probe now loads the Wi-Fi (en0) address (`907538f5`, on
   `m0-device-fixes`); the re-run of 1.3 is pending."
9. **Optional, `Scripts/ci.d/70-g05-ai.sh` line 31:** `MIN_PROBE_TESTS=39` to `MIN_PROBE_TESTS=42`. The probe now
   reports 42 tests (14 per variant), so with 39 the loss of up to 3 tests would go unnoticed.
10. **Optional, `Docs/ADRs/0011-ai-providers-context-and-privacy.md` line 89**, which records the G0.5 simulator run as
    39 tests: still true of that run. Add "(42 since `907538f5`, which added a test of the device address rule)" only if
    the ADR should describe the current probe.
11. **`Docs/Stage0/integration-log.md` and the gate summary (`Docs/Stage0/M0-gate.md`):** record `m0-device-fixes`,
    its two fix branches, their merges and the checks of Section 5 (this README). Also record the correctness review
    of `fdce7cd5` (26 October 2026: findings F1-F4) and fix-1, with its commits and checks
    ([`fix-1/README.md`](fix-1/README.md) Sections 1 and 5).
12. **The lock harness's quiet-tone test** (`LogAndToneTests.playsQuietly`): record as an open item of the lock
    harness that it failed in all four runs on this Mac on 26 October 2026 (three from 07:38 to 07:58 UTC in the
    recovery job, one of them on the unchanged code `c72247a6`, and one at about 08:23 UTC here), each time with
    `AVAudioPlayer did not start`. It had passed on 22 October 2026 with the screen locked, at 08:09 UTC
    (`Docs/Stage0/evidence/M0-Decisions/assembly/harness-checks-clean/`), and with it unlocked, at 22:36-22:44 UTC
    (`Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1/logs/harness-simulator-tests.log`). Its cause is not
    established; your run of 0.8 shows whether it still fails.
13. **The session log:** rows for the merge's commit and for each repeated step, which you fill in as before.

## 9. Left open here

- Finding F-1: request 5.
- The two class-B tests of failure 1 have never run: Section 7.2, item 1.
- The lock harness's quiet-tone test: request 12.
- Every device result: Section 6.
