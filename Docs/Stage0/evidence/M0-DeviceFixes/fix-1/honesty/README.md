# M0 device fixes, fix-1: the honesty review of `m0-device-fixes`, round 1

For the product owner. The honesty review of branch `m0-device-fixes` (26 October 2026) reported six findings: HON-1
(major) and HON-2 to HON-6 (minor). Its line numbers are those of `fdce7cd5`, the commit the correctness and security
reviews also read. This fix starts from `ee9c196c`, after fix-1 of the correctness review ([`../README.md`](../README.md))
and the security fix ([`../security/README.md`](../security/README.md)). fix-1 had already corrected HON-1 (its finding
F2) and the 7.4 part of HON-3 (its F4). This folder records how each finding was checked before anything changed, what
changed, and the checks.

All of it is an agent's work on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) on 26 October
2026, from about 11:55 UTC (27 October on the Mac's clock, NZDT, UTC+13). No simulator was used. The Mac's screen was
locked at every reading (ioreg, read only; each log records it), so the host-facts probe's sections 3 and 4, which would
save finding F-1's evidence on the Mac, could not run here. **Nothing here ran on a phone.** This is not a device
result, a role sign-off, an ADR approval (decision D-6) or the M0 exit.

**No code changed.** This fix changes only the Markdown records of `Docs/Stage0/evidence/M0-DeviceFixes`
([`../../README.md`](../../README.md), [`../../recovery/README.md`](../../recovery/README.md),
[`../../ats/README.md`](../../ats/README.md) and [`../security/README.md`](../security/README.md)) and adds this folder.
Unchanged: your records on `m0-decisions`, Codex's `DeviceTests` files, everything under `Spikes/`, `Scripts/`, `Apps/`
and `Packages/`, the runbook, the device checklists, the gate reports, the gate summary, the integration log and the
Stage 0 README. Section 9 lists what the records run needs.

Commits on `m0-device-fixes`: `f394e0fc` the commands that check the findings; `1480c7e1` the checks before any
correction, and the stand-in probe of the drop-in's exit status; `ccc47d7b` this record, with the corrections; then the
logs of the checks after the corrections and of the shared checks, which ran on `ccc47d7b`.

**What to test on the Mac** is still the owner's README, [Section 7.2](../../README.md#72-what-to-test-on-the-mac-screen-unlocked),
with the screen unlocked: (1) the class-B tests of failure 1, which have never run; (2) runbook 0.8, whose last line on
a repeat failure of the quiet-tone test now reads `drop-in exit 65` (HON-2); (3) the optional host-facts probe, which
would save F-1's evidence on the Mac (HON-4).

## 1. In short

| Finding | Checked first | What changed | Evidence |
| --- | --- | --- | --- |
| HON-1, major: 7.3 expected no `NSFileProtectionNone` anywhere, but a passing test prints it | Confirmed for `fdce7cd5` (its README line 295): the first run's log line 2364, from `DataProtectionTests.mismatchDetected` (unchanged, lines 249-250), which passed (line 2366). Already corrected by fix-1 (`29afe758`, its F2): 7.3 expects no `protection: library.sqlite has NSFileProtectionNone` and names that line as expected | The recovery README's list for the re-run (its Section 6) now names that line as expected too | [`check-findings-before.log`](check-findings-before.log): the old wording is in no README; the first run's only line naming the class outside the failing tests' refusals and their details is line 2364 |
| HON-2: 7.2, item 2, says a repeat tone-test failure ends 0.8 with `drop-in exit 1` | Confirmed: the harness's script ended with 65 on that failure in all four runs on 26 October; both scripts run with `set -euo pipefail`, and the drop-in calls the harness's script as a plain command with no EXIT trap set; caffeinate passes the status on (Section 3) | 7.2, item 2, now says `drop-in exit 65` and why, and that a stop at the row-10 guard ends with `drop-in exit 1` | [`exit-status-probe.log`](exit-status-probe.log): a stand-in of the chain prints `drop-in exit 65`, and `drop-in exit 0` in its control |
| HON-3: that 10.71.x.x was not phone B's Wi-Fi address was presented as confirmed | Confirmed: no line of either ATS log holds the Wi-Fi address; en0 is named only as the relay flow's interface, with no address; the only address in the probe's private ranges in the logs is 10.71.x.x; the session log names no Wi-Fi network; your own record says "whether it is the intended Wi-Fi interface needs diagnosis" | Marked as inferred, with what supports it, in the owner's README (Section 1's table and its heading, Sections 4 and 6, 7.4, request 8), the ATS README (sections 2, 5 and 6) and the security record (S8); 7.4 and the ATS README now say what in the re-run would refute it: en0 holding 10.71.x.x | Both check logs, section HON-3 |
| HON-4: two claims rest on Mac readings that no committed log holds | Confirmed: every saved run of the host-facts probe skipped sections 3 and 4 (screen locked), and no log under `M0-DeviceFixes` holds a reading of the audio devices. The screen was locked here too, so neither could be saved now | F-1's evidence on the Mac is now pending until 7.2, item 3, runs (owner's README: Section 2, 7.2 item 3, request 5, Section 9; recovery README: 2.1, 2.4, 7 and 8); the reading of the audio output is marked as not saved (recovery README Section 4) | Both check logs, section HON-4 |
| HON-5: the cited locked pass of the quiet-tone test ran an older version of it, and its name was wrong | Confirmed: xcodebuild names it `ToneTests.playsQuietly()`; the 08:09 UTC run (`9aee51b8`, which lacks `84e599b1`) ran its earlier version; the current version passed with the screen locked at 11:07 UTC and in the controls' baseline at 11:15 UTC (22 October), and the lock harness has not changed since `84e599b1` | Request 12 and the recovery README's Section 4 give the name and the runs of the current version, with dates in UTC and the Mac's clock's dates marked as such | Both check logs, section HON-5 |
| HON-6: the part READMEs' re-run instructions would overwrite the first runs' logs | Confirmed: runbook 1.2's command writes `step-1-tests.log` (session log row 3b's blocked attempt) and 1.3's `step-01-ats.log` (row 3d) | The recovery README's Section 6 and the ATS README's Section 5 send the re-runs to 7.3 and 7.4, which name the new logs apart; the recovery README's Section 7 points to 7.2 | Both check logs, section HON-6 |

The re-runs' expected results are unchanged: the re-run of step 1.2 still expects `73 tests in 13 suites passed`, and
1.3 still expects the default variant to fail at `ATSProbeTests.swift:164` as the device finding. One expectation was
added: in 7.4, en0 holding 10.71.x.x would refute the diagnosis of failure 3.

## 2. HON-1: the unprotected class in 7.3

**What the review found** (at `fdce7cd5`): 7.3 listed "No `NSFileProtectionNone` anywhere." as an expected outcome of
the phone's re-run, but `DataProtectionTests.mismatchDetected` writes a file with `.noFileProtection` on purpose and
prints `file written with .noFileProtection into the test's temporary directory reports: NSFileProtectionNone`.

**Checked** ([`check-findings-before.log`](check-findings-before.log), section HON-1):

- The first hosted run on phone B printed it at line 2364 of
  [`step-1-hosted-tests.log`](../../../G05-Recovery/device/step-1-hosted-tests.log), and the test passed (line 2366).
  The test (`DataProtectionTests.swift` lines 249-250) is the same on this branch as at `c72247a6`: `git diff c72247a6
  HEAD` lists no change to that file.
- 81 lines of that log name the class: 66 hold the library's refusal (`protection: library.sqlite has …`), 40 are issue
  details (`↳`), some of them holding the refusal too, and the only line that is neither is line 2364. So in a passing
  re-run that line is expected, and the library's refusal is not.
- fix-1 had already corrected 7.3 (`29afe758`, its F2; [`../README.md`](../README.md) Section 4): it now expects no
  `protection: library.sqlite has NSFileProtectionNone` anywhere and names line 2364's line as expected. The old wording
  is in no README of the branch.

**Changed here.** The recovery README's list for the re-run (its Section 6) had the right scope but did not name the
expected line; it now does.

## 3. HON-2: the last line of runbook 0.8 when the quiet-tone test fails again

**What the review found.** 7.2, item 2, said that if the lock harness's quiet-tone test fails again, "the drop-in stops
at its step 14 and the last line reads `drop-in exit 1`".

**Checked** ([`check-findings-before.log`](check-findings-before.log), section HON-2):

- Runbook 0.8 runs `G05_LOG_DIR=… G05_SIM_NAME=… caffeinate -d -i Scripts/ci.d/71-g05-recovery.sh 2>&1 | tee …;
  echo "drop-in exit ${pipestatus[1]}"` (`M0-device-runbook.md` lines 212-214).
- The drop-in runs with `set -euo pipefail` (line 30), removes step 11's EXIT trap (line 124) and calls the harness's
  script as a plain command (line 136). The harness's script runs with `set -euo pipefail` (line 28), sets an EXIT trap
  that shuts its simulator down and ignores a failure of that (line 74; `Scripts/lib/sim.sh` lines 40-46), and runs
  `xcodebuild test … 2>&1 | tee -a …` (lines 81-82).
- In all four runs of the harness's script on 26 October, xcodebuild listed `Failing tests: ToneTests.playsQuietly()`
  and the script ended with 65: [`../../recovery/dropin-run-1-steps-4-15/console.log`](../../recovery/dropin-run-1-steps-4-15/console.log)
  line 7085, [`../../recovery/harness-checks-repeat-1/console.log`](../../recovery/harness-checks-repeat-1/console.log)
  line 378, [`../../recovery/harness-checks-control-c72247a6/console.log`](../../recovery/harness-checks-control-c72247a6/console.log)
  line 2619 and [`../../assembly/dropin-steps-4-15/console.log`](../../assembly/dropin-steps-4-15/console.log) line
  7087. The two hand runs of steps 4-15 report the script's own status (`recovery/commands/run-dropin-steps-4-15.sh`
  line 74, `assembly/commands/run-checks.sh` line 175).
- caffeinate passes on the status of the command it runs: the runbook's own probe
  ([`../../../M0-runbook/tool-help.txt`](../../../M0-runbook/tool-help.txt) lines 442-445).
- Neither run of the whole drop-in on this branch reached step 14: both stopped at the row-10 guard, which exits with 1
  (`Scripts/ci.d/71-g05-recovery.sh` lines 85-86; [`../../recovery/dropin-run-1/console.log`](../../recovery/dropin-run-1/console.log),
  [`../../assembly/dropin/console.log`](../../assembly/dropin/console.log)). So the chain was checked with a stand-in.

**The stand-in** ([`commands/exit-status-probe.zsh`](commands/exit-status-probe.zsh), run on `f394e0fc`;
[`exit-status-probe.log`](exit-status-probe.log)). Two stand-ins with the same shell constructs as the two scripts (the
log prints both), with a command that exits 65 in place of `xcodebuild test`, run by runbook 0.8's line in zsh: the
harness stand-in exits 65, the drop-in stand-in stops before its closing line, and the line reads `drop-in exit 65`.
In the control, with the command exiting 0, every closing line is printed and the line reads `drop-in exit 0`. Limits:
it used `caffeinate -i` only, as the runbook's own probe did (0.8 adds `-d`, a display assertion); and its bash was
`/bin/bash` 3.2.57, which `#!/usr/bin/env bash`, the two real scripts' first line, finds on this Mac's `PATH` here.
Which bash the owner's `PATH` finds was not checked.

**Changed.** 7.2, item 2, now says `drop-in exit 65`, why, and that a stop at the row-10 guard ends with `drop-in exit
1` instead. The owner's next step is the same either way: record it and ask an agent.

## 4. HON-3: whether 10.71.x.x was phone B's Wi-Fi address

**What the review found.** The owner's README (Section 1's table, under a heading "confirmed from the code and the
phone's own logs", and Section 4) and the ATS README (its section 2) said that 10.71.x.x was not phone B's Wi-Fi
address, but no log shows the Wi-Fi address.

**Checked** ([`check-findings-before.log`](check-findings-before.log), section HON-3):

- Every line of [`step-01-ats.log`](../../../G05-AI/device/step-01-ats.log) and
  [`step-01-ats-initial.log`](../../../G05-AI/device/step-01-ats-initial.log) that names en0 is the relay flow's
  interface field (`interface: en0[802.11], ipv4, dns, uses wifi, …`; 3 lines in each), with no address.
- The only address in the probe's private ranges in those logs is 10.71.x.x (20 times in each); the others are the
  loopback's 127.0.x.x and the public IP literal's 192.0.x.x. Neither log holds a whole IPv4 address.
- Your record of 1.3 says: "The selected private address was 10.71.x.x; whether it is the intended Wi-Fi interface needs
  diagnosis." ([`step-01-ats.txt`](../../../G05-AI/device/step-01-ats.txt) line 4.) The session log's rows 3a-3d name no
  Wi-Fi network. So nothing records that the phone was on the Mac's network; the Mac's only private address,
  192.168.x.x on en0, was read by this branch's simulator runs on 26 October.
- At `c72247a6` the probe took the first up, non-loopback private IPv4 address of any interface, in `getifaddrs` order
  (`ATSProbeTests.swift` lines 45-61, printed in the log).

So the reviewer is right: the conclusion is a strong inference, not a reading. It rests on the probe's choice (which
could take a non-Wi-Fi address), on the cellular interface being there (the relay's flow names `pdp_ip0` as its
fallback, `step-01-ats-initial.log` line 2571), and on the expectation that a phone refuses a load to its own address
itself rather than send it to the relay (seen on the simulator, not on a phone; the security fix's S8 says the same of
the probe's comment). The fix, to load en0's address only on a device, is right either way.

**Changed.** Each place now marks it as inferred and says what supports it: the owner's README (Section 1's table, whose
heading now reads "what is inferred is marked"; Section 4's bullets; Section 6; 7.4's last paragraph; request 8, which
would have carried "a non-Wi-Fi private address" into G0.5 AI row D1), the ATS README (sections 2, 5 and 6) and the
security record (its S8 row and Section 7, "another private address"). 7.4 and the ATS README's section 5 no longer say
that the re-run's interface line "settles" which interface the first run used: it lists the interfaces at the time of
the re-run, the records keep two octets, and an address can change. They now say what would refute the diagnosis: en0
itself holding 10.71.x.x. The review's related point, that 7.4 showed en0 first in the interface list, had already been
corrected by fix-1 (its F4).

## 5. HON-4: Mac readings that no committed log holds

**What the review found.** F-1's evidence on the Mac comes from a probe run whose output was not saved, and 7.2, item
3, predicted its output from that run; the recovery README cited a `system_profiler SPAudioDataType` reading of the
Mac's default output that no log holds.

**Checked** ([`check-findings-before.log`](check-findings-before.log), section HON-4): every saved run of the host-facts
probe on this branch skipped sections 3 and 4 (`== 3, 4. skipped: class B keys unavailable (screen locked)`:
[`../../recovery/probe-host-facts-locked.log`](../../recovery/probe-host-facts-locked.log) line 25, and the security
fix's two runs); no log or command under `M0-DeviceFixes` names `SPAudioDataType` or a default output device (the
check leaves out Markdown files and this folder). The screen was locked at every reading of this job, so the probe's
sections 3 and 4 could not be saved now; and reading the audio devices again would show only today's output, not that
of the runs of 26 October.

**Changed.**

- The owner's README: F-1's evidence on the Mac is pending until 7.2, item 3, runs (7.2 item 3, which now presents the
  section-4 lines it expects as taken from the unsaved run; request 5; Section 9); Section 2 says that no reading
  shows the change directly yet; request 5 says "most likely" of the records that rest on the stale reading.
- The recovery README: section 2.4's Mac bullet is headed "pending"; section 2.1's correction and request 3 say "most
  likely"; section 7, item 3, says "should show"; section 4 says that the audio reading was not saved.

## 6. HON-5: the quiet-tone test's name and the runs cited for its earlier passes

**Checked** ([`check-findings-before.log`](check-findings-before.log), section HON-5):

- The test is `func playsQuietly()` in `struct ToneTests` (suite "Lock harness: the quiet tone"), in the file
  `Spikes/G05-Recovery/LockHarness/Tests/LogAndToneTests.swift` (lines 80-81 and 110-112); xcodebuild lists it as
  `ToneTests.playsQuietly()` in every failing run of 26 October. The README had named it after its file.
- The run cited for the pass with the screen locked, `M0-Decisions/assembly/harness-checks-clean/` (22 October 08:09 UTC,
  commit `9aee51b8`), ran the earlier version, "the player plays the tone at the test volume 0.01, unmuted, and stops"
  (its `harness-simulator-tests.log` line 2244). The playback-category check came with `84e599b1`, the last commit to
  `Spikes/G05-Recovery/LockHarness`, which `9aee51b8` does not hold.
- The current version passed with the screen locked in `M0-Decisions/fix-2/harness-checks-clean/` (commit `13d999fc`,
  11:07-11:08 UTC; `harness-simulator-tests.log` line 2458) and in the baseline of `M0-Decisions/fix-2/harness-controls/`
  (commit `52215b13`, 11:15-11:17 UTC; `baseline.log` line 852), both on 22 October UTC with the screen locked at start
  and end (their `console.log` lines 5 and 65, and 5 and 29); and with the screen unlocked in
  `M0-Decisions/assembly/unlocked-run-1/` (commit `9cdb0a02`, 22:36-22:44 UTC; `logs/harness-simulator-tests.log` line
  2460). All three commits hold `84e599b1`, and the lock harness has not changed from `13d999fc` to this branch.
- "22 and 23 October" in the recovery README mixed UTC (08:09 UTC on 22 October) with the Mac's clock (11:07 UTC is
  00:07 on 23 October in NZDT).

**Changed.** Request 12 and the recovery README's Section 4 name `ToneTests.playsQuietly()`, cite the runs of 11:07
and 11:15 UTC, give dates in UTC with the Mac's clock named as such, and say which earlier citation was replaced.

## 7. HON-6: the part READMEs' re-run instructions

**Checked** ([`check-findings-before.log`](check-findings-before.log), section HON-6): runbook 1.2's command writes
`Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log` (`M0-device-runbook.md` line 259), the log of your blocked
attempt of row 3b (`step-1-2-results.txt` line 10); runbook 1.3's writes `Docs/Stage0/evidence/G05-AI/device/step-01-ats.log`
(line 285), your record of row 3d. The recovery README's Section 6 said "with the commands of runbook 1.2", and the ATS
README's Section 5 began "Run runbook 1.3 as written" (the security fix had added a pointer to 7.4 after it).

**Changed.** The recovery README's Section 6 sends the re-run to 7.3, with its log name `step-1-hosted-run2-tests.log`;
the ATS README's Section 5 sends it to 7.4, and says why not to run 1.3 as written; the recovery README's Section 7
points to 7.2, whose commands save their logs.

## 8. Checks

Commands: [`commands/check-findings.sh`](commands/check-findings.sh) (checks 1 and 3: read only; it prints the evidence
each finding rests on and checks 43 phrases of the READMEs, each with what it expects before and after the
corrections), [`commands/exit-status-probe.zsh`](commands/exit-status-probe.zsh) (check 2) and
[`commands/run-shared-checks.sh`](commands/run-shared-checks.sh) (check 4). The screen was locked at every reading.
`G05_ALLOW_MISSING_CLASS_B` was never set, and the drop-in was not run.

| # | Check | Log | Result |
| --- | --- | --- | --- |
| 1 | `check-findings.sh before`, on `f394e0fc` (the commands' commit; no uncommitted file) | [`check-findings-before.log`](check-findings-before.log) | As expected: 43 of 43. Each flagged phrase was present, except HON-1's, which fix-1 had removed; none of the corrections was |
| 2 | `exit-status-probe.zsh`, on `f394e0fc` (one uncommitted file: check 1's log) | [`exit-status-probe.log`](exit-status-probe.log) | As expected: the harness stand-in exits 65 and 0.8's line reads `drop-in exit 65`; the control reads `drop-in exit 0` |
| 3 | `check-findings.sh after`, on `ccc47d7b`, the commit of this record (no uncommitted file) | [`check-findings-after.log`](check-findings-after.log) | As expected: 43 of 43. Every flagged phrase is gone and every correction is present; the evidence it prints is the same as in check 1 |
| 4 | `Scripts/ci.sh contracts`, `Scripts/ci.d/13-hard-rules.sh`, `Scripts/ci.d/12-dependency-lock.sh`, on `ccc47d7b` (one uncommitted file: check 3's log) | [`shared-checks/`](shared-checks/) | All passed: `all 3 steps passed` for the contracts; the hard-rules audit `PASS (0 finding(s), 49 allowed, 0 stale allowlist entries, 0 allowlist error(s))`, which read this record as `ccc47d7b` has it (the log commit after it changes only its wording and this table), its commands and logs and the corrected READMEs; the dependency lock with `0 failure(s), 0 warning(s)` |

Not run again, and why:

- The recovery host suite, its simulator suite, the crash drills, the device builds, the ATS probe and the lock harness:
  this fix changes no code, script, project, runbook or checklist.
- The runbook content check: neither the runbook nor the device checklists changed.
- The class-B tests of failure 1 and the host-facts probe's sections 3 and 4: they need the screen unlocked, and it was
  locked; they are the owner's 7.2, items 1 and 3.

## 9. Requests for the records (open items)

Another run updates the records on `m0-records-update`; this fix changes none of them. The owner's README, Section 8,
now carries these changes in requests 5, 8, 11 and 12. If the records run applied their earlier text:

1. **Request 8** (`Docs/Stage0/G05-AI.md` row D1): replace "the probe loaded a non-Wi-Fi private address (10.71.x.x),"
   with "the probe loaded the first private address of any interface (10.71.x.x; that it was not the Wi-Fi address is
   inferred, since no log names its interface),", and "now loads the Wi-Fi (en0) address" with "now loads only the
   Wi-Fi (en0) address".
2. **Request 12** (the lock harness's open item): replace `LogAndToneTests.playsQuietly` with `ToneTests.playsQuietly()`,
   and the pass with the screen locked "at 08:09 UTC (`Docs/Stage0/evidence/M0-Decisions/assembly/harness-checks-clean/`)"
   with the runs that started at 11:07 UTC (`Docs/Stage0/evidence/M0-Decisions/fix-2/harness-checks-clean/harness-simulator-tests.log`
   line 2458) and 11:15 UTC (`Docs/Stage0/evidence/M0-Decisions/fix-2/harness-controls/baseline.log` line 852) on 22
   October 2026 UTC; the run of 08:09 UTC ran an earlier version of the test.
3. **Request 5 (F-1):** if a record says F-1 was seen on the Mac, say instead that on the Mac it is pending: the one
   run that showed it was not saved, and the owner's README, 7.2 item 3, saves it. If a record says that the lines
   "refused … the class is fixed at creation here" rest on a stale reading, say "most likely": the phone's change of
   class is inferred from 8 tests' later opens.
4. **Request 11** (`Docs/Stage0/integration-log.md` and `Docs/Stage0/M0-gate.md`): also record the honesty review of
   `fdce7cd5` (26 October 2026, findings HON-1 to HON-6) and this fix: commits `f394e0fc`, `1480c7e1` and `ccc47d7b`
   (this record), the log commit after it, and Section 8's checks. HON-1 was fixed by fix-1 (its F2); the fix changed
   text only.
5. **If a record copied 7.2, item 2's expectation** for a repeat failure of the quiet-tone test, it is `drop-in exit
   65`; a stop at the row-10 guard is `drop-in exit 1`.
6. **If a record says that 10.71.x.x was not phone B's Wi-Fi address**, mark it as inferred, as the owner's README's
   Section 4 now does, and add that the re-run of 1.3 refutes it if en0 itself holds 10.71.x.x.
