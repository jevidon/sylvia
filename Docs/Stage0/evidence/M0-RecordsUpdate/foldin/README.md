# The device fixes folded into `m0-records-update` (27 October 2026)

For the product owner. `m0-device-fixes`, the fixes of the three failures of your first runs of Session 1 on phone B,
is merged into `m0-records-update`, and the record requests of its README are applied to these records, so that one
merge into `m0-decisions` brings it all (integration log section 45). Agent-written; not reviewed; human sign-off
pending. Nothing here is a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit.

An agent's work on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)), in a worktree of its own,
from about 15:59 UTC on 26 October 2026 (04:59 on 27 October on the build Mac's clock, the date of the fold-in's commits
and notes). No simulator was created or used, no device was contacted, nothing played audio, and nothing was pushed or
fetched from a remote. No ref of this repository was written but this branch's commits: `m0-decisions` (at `c72247a6`,
read only), `m0-device-fixes` and its two fix branches were read, never committed to, reset or checked out, and
`~/Git/sylvia-sessions` was not touched; the simulation of your merge (Section 6) ran in a local clone under
`.build/scratch`, with branches of its own, and deleted it. The worktree's 777 Git LFS files were filled from the
repository's local LFS store with `git lfs checkout`, with no download.

**What you do next: Section 5.** In short: merge `m0-records-update` into `m0-decisions` between sittings, as a
fast-forward; then, at the Mac with the screen unlocked, the device fixes' two class-B tests and runbook 0.8; then 1.2
and 1.3 again on phone B, under new log names; then the rest of Session 1 and the other sessions in the runbook's order.

## 1. What was folded in

| Branch | Commit | What it brings | How it came here |
| --- | --- | --- | --- |
| `m0-device-fixes` | `a60aa922` | The fixes of the three failures of your first runs of 1.2 and 1.3 on phone B, made from `m0-decisions` at `c72247a6`: the recovery tests' fixture copies (`FileManager.copyItem` kept the app bundle's lack of a class; now `FileProtector`'s protected copy, with a guard test against class-keeping copies), the backup containment check's `/private` mismatch for a missing file (`Container.resolve`, `copyTree` and the bundle walk, with a Mac reproduction under `/private/var/folders`), and the ATS probe's address (now only the phone's Wi-Fi, en0, address); its README gives the diagnoses, the checks, what only the phone can show, your next steps (its Section 7) and fifteen record requests (its Section 8). As relayed: reviewed in two rounds to accept-with-minor by its correctness, security and honesty lenses; the first round's findings and fixes are in its records, the second round's minor findings were not relayed, and no record of that round is committed | Merged with `--no-ff`: `cbdb63bc` |

Its commits: the two fix branches, made from `c72247a6`, `m0-device-fixes-recovery` (`a65cdc3e` the tests that reproduce
step 1.2's failures on the Mac, `c778cd63` the fixes, up to `fd2a2624`, merged at `37cb53b8`) and `m0-device-fixes-ats`
(`907538f5` the fix, up to `e4586a83`, merged at `eebbb457`); the merged tree's checks (`2d188e06`, `eacc8ddb`) and the
README (`163d76b8`, `fdce7cd5`); fix-1, after the correctness review of `fdce7cd5` (F1-F4), `346716ed` to `31e460e6`;
the security fix (S1-S8), `e022cea7` to `ee9c196c`; and the honesty fix (HON-1 to HON-6), `f394e0fc` to `a60aa922`.

**The merge** ([`checks/merge-check.log`](checks/merge-check.log)). Both branches were made from `c72247a6`; since then
this branch changed 555 files and `m0-device-fixes` 158, none of them in both, so the merge could not conflict, and it
did not. At the merge commit every file is as the side that changed it has it. Since then, of `m0-device-fixes`'s files
only its README differs from `a60aa922`, by three dated notes this fold-in added (at its head, in its 7.1 and in its
Section 8), with no line removed; its code, under `Spikes/`, is `a60aa922`'s. Outside `Docs/` the merge brought the
recovery package's `Sources` and `Tests` (eleven files) and the ATS probe's test file, nothing else. The device fixes'
own checks (their README's Section 5 and the part READMEs) are records of their branch: the merge changes no file they
ran on, so they stand for this tree's code, and this fold-in ran none of the spike suites again (Section 8).

## 2. `CLAUDE.md`: put in on this branch before the fold-in (`6a510880`)

The orchestrating session ran [`../fix-1/owner/commands/apply-claude-md-texts.py`](../fix-1/owner/commands/apply-claude-md-texts.py)
on `m0-records-update` in `6a510880`, before the fold-in: its message says that it was made "at the owner's request of 24
October 2026 to update what was out of date, as 5aec2518 and 6cede84a were", and that the dependency lock check passed
after it. `git show --stat 6a510880` shows `CLAUDE.md` alone, two lines; its fifth line is the paragraph of
[`../claude-md-paragraph.md`](../claude-md-paragraph.md) and its toolchain line has the second text's new words, not the
old ones ([`checks/foldin-checks.log`](checks/foldin-checks.log), part 10c), and the lock check passes on the fold-in's
documents commit ([`checks/12-dependency-lock.log`](checks/12-dependency-lock.log)). So your merge brings both texts, and
you put nothing in by hand. The records that had you run that command, or put the texts in, after your merge now say
so, each with a dated note or a history clause: the evidence README (its opening, Left for the owner, the merge
commands, which no longer run the command, check its diff, run the lock check for it or commit, and its pending list) and
`claude-md-paragraph.md`; the runbook's 0.3, step 2 (rewritten, its earlier text summarised in its history clause), run 1,
its header and Session 0's order line; the gate summary's item 1 (its opening, and step 2, rewritten, its text until then
quoted word for word in Section 6.3, item 221), item 4, Sections 5.4, 6.2, 7 and 8; the Stage 0 README; and the
integration log's 41.8, 42.8, 43.9, 44.3 and 44.9. The texts' file and the command stay, as the record of how it was
done. This fold-in wrote nothing in `CLAUDE.md`.

## 3. The record requests of the device fixes' README, one by one

Applied to these records as they stood after this branch's own update, at `6a510880`. Where a request's text assumed the
records before that update, its intent was applied to the records as they are, as the table says. One constraint shaped
several: the lines your commits added in the records an agent also edits (a report's row, a step's command or Expect
line) are kept verbatim, which the check of your records requires
([`checks/owner-records-intact.log`](checks/owner-records-intact.log)), so a request that asked to change such a line
became a dated note beside it.

| # | Request | What was done |
| --- | --- | --- |
| 1 | The recovery suite's expected count on a phone | The G0.5 recovery checklist's step 1, item 2: `Test run with 73 tests in 13 suites passed`, with what is not built for iOS and the simulator's logs, as the request gives it, and the old count kept in a history clause; a new bullet with the expected lines of the device fixes' 7.3 (no `protection: library.sqlite has NSFileProtectionNone` anywhere, the expected line of the protection-mismatch test, the missing-blob-file and unlisted-dangling-link lines, the five new lines). Runbook 1.2's Expect line is yours (`4be1a1a4`), so the count and lines are in a note after 1.2 that names that line as the code's before the fixes. The report's row 22 has a note. |
| 2 | A repeat's logs named apart | Already the rule of the runbook's Section 2 since the owner-readability fix (`M0-gate.md` item 211), with the commit in each name; Section 2 now also allows a run's number where a record gives the names, as the device fixes' 7.3 and 7.4 do, and the notes after 1.2 and 1.3 name those files (`step-1-hosted-run2-tests.log`; `step-01-ats-run2.log`, `step-01-ats-run2.txt`) and the records 7.3 and 7.4 leave unnamed (`step-1-2-results-run2.txt`, `step-04-suspension-run2.txt`); none is committed yet. |
| 3 | 0.8 runs again; row 10; the session log's paragraph on 0.8 | The runbook's 0.8 (a dated note: the commits, the counts, the stopped runs, the quiet-tone test and its exit 65), its header, Section 3's runs 2 and 3, Session 0's order line and Section 7's G0.5 recovery row; the gate summary's item 2, its run 2 row, item 4's bullet on the build Mac, the drop-in paragraph and Section 5.1; the report's row 10 (a note; passed-host kept, its evidence being of the code before the fixes, and a pointer to F-1). The session log is yours, checked byte for byte, so its paragraph on 0.8 is not changed: it states the rule, which the fixes now meet. |
| 4 | Rows 6 and 7 and the hosted run's section | Those lines and the two sections on the physical-device attempts are yours (`38f9604e`, `d5336111`), kept verbatim, so a new section at the end of the report gives the diagnosis, the fixes (`c778cd63`; `546a8219`, without which the run again would fail `copyTreeRefusals`) and the pending run again, and says that rows 6 and 7 stay failed (device) until a run passes; the report's line on device steps and row 22 point to it. |
| 5 | Finding F-1 | A decision pending for you as technical lead, not applied (Section 4). |
| 6 | G0.5 AI checklist, step 1 | Applied as given, in items 3 and 4, with a dated note; the checklist's opening line has a note on the run again. |
| 7 | Runbook 1.3 | Applied as given, in the same commit as request 6, with one addition: since request 6 puts the line `ATS-PROBE variant=… private-ip=<a.b>.x.x interface=en0 result=…` in the checklist, 1.3 quotes it beside `interface=en0`, so that the runbook content check finds each of the step's markers in both documents ([`checks/runbook-content-check.log`](checks/runbook-content-check.log); [`checks/foldin-checks.log`](checks/foldin-checks.log), part 6). |
| 8 | G0.5 AI row D1 | The row is yours (`1bbca07e`), kept verbatim, so the text is in a dated note after the table of device checks, which says why; Q5 has a note pointing to it. |
| 9 | The probe's minimum count (optional) | Applied: `MIN_PROBE_TESTS=42` in `Scripts/ci.d/70-g05-ai.sh`. The drop-in's own count check, run on committed probe logs, passes the fixed probe's 42 tests and fails 39 and 41, which 39 let through ([`checks/probe-count-check.log`](checks/probe-count-check.log)); no session step and no drop-in 0.8 runs it, so it repeats nothing (runbook 0.3, step 7). |
| 10 | ADR-0011's 39 tests (optional) | Not applied: ADR-0011's Evidence records results of the G0.5 runs, which it takes from that report and its logs, and its 39 tests stay true of that run; it does not describe the current probe. ADR-0011 is unchanged. |
| 11 | The integration log and the gate summary | Integration log section 45; the gate summary's State line, Section 1 (a bullet and a note on your first sittings), Section 6.2 (a row for the device fixes' review), Section 6.3 (items 215-223) and Section 8 (a bullet). |
| 12 | The lock harness's quiet-tone test | An open item in the report's row 25 (its status kept, resting on the runs of 22 October 2026) and in the gate summary's Section 5.4; runbook 0.8's note says what a failure looks like. |
| 13 | The session log's rows | Your next steps ask for a row for the merge's commit and for each step run again; the log itself is yours and untouched. |
| 14 | Runbook 1.3: cut the log's addresses | Applied as given, right after 1.3's command block, with the run again's own log name. |
| 15 | Finding S5 | A decision pending for you as technical lead, not applied (Section 4). |

The device fixes' README has three dated notes: at its head, that it is folded in; in 7.1, that you merge
`m0-records-update` rather than this branch on its own, its steps kept as the record of what it asked; and in Section 8,
how its requests were applied.

## 4. Two decisions pending for you as technical lead, not applied

Recorded, with each proposed change and what it would correct, in the G0.5 recovery report (its decisions pending for
the technical lead, after its open questions and not numbered among them, since the numbered questions are those the plan
amendments go through and whose checker requires each to be referenced there), the gate summary's Section 5.4, the
runbook's technical-lead table and the evidence README's pending list. Neither is applied: the recovery package's
`FileProtection.swift` and `Backup/Restore.swift` are as `m0-device-fixes` has them ([`checks/foldin-checks.log`](checks/foldin-checks.log), part 5).

- **F-1** (request 5): `FileProtector.verify` reads a file's class through the same `URL` value `protect` read before
  `setAttributes`, and a `URL` caches what it has read, so `protect` reports a mismatch even when the change took effect.
  Proposed: in `verify`, `var fresh = url; fresh.removeAllCachedResourceValues(); let actual = try protectionClass(of:
  fresh)`. It would correct `DataProtectionTests.mismatchDetected`'s reading and then the records that say an existing
  file's class cannot be changed, whose lines "refused … the class is fixed at creation here" most likely rest on a stale
  reading until then. On the Mac the observation is pending until the device fixes' 7.2, item 3, runs with the screen
  unlocked.
- **S5** (request 15): `FileProtector.copyFile` opens a bundle's file with `O_NOFOLLOW`, which covers the last component
  only, so a folder above the file swapped for a link after the restore's checks is followed, the copy still having to
  match the manifest's digest. Proposed: open the validated bundle root once and each listed file with
  `openat(rootFD, entry.path, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)`. It would refuse a link anywhere below
  the bundle; it needs the host suite, the restore drills and runbook 1.2 on a phone after it, so if you choose it,
  decide before 1.2 runs again.

## 5. Your next steps, in order

1. **Between sittings, merge `m0-records-update` into `m0-decisions`**, once the sitting in progress is done and its
   records are committed, before Codex or an agent works in `~/Git/sylvia-sessions` again, with `git merge --ff-only
   m0-records-update`: [`../README.md`](../README.md), its merge section, gives the commands, what to do if
   `m0-decisions` has moved on (an agent merges it into this branch first), if a merge ever stops on a conflict (`git
   merge --abort`) and if you have already merged `m0-device-fixes` on its own. Note the new commit in a row of the
   session log.
2. **At the Mac, with the screen unlocked for each whole run**: the device fixes' two class-B tests, then runbook 0.8,
   and, if you like, the host-facts probe for F-1 ([`../../M0-DeviceFixes/README.md`](../../M0-DeviceFixes/README.md)
   7.2). Commit their logs on `m0-decisions`, with a row in the session log.
3. **On phone B, 1.2 and then 1.3 again**, as its 7.3 and 7.4 give them, under new log names, then 1.2's latency runs.
4. **Then the rest of Session 1 and the other sessions in the runbook's order.** 1.1 and 1.4 need no repeat for this
   merge.

The gate summary's Section 1, item 2, the runbook's header, the Stage 0 README and the evidence README's merge section
give these steps in this order ([`checks/foldin-checks.log`](checks/foldin-checks.log), part 11). A simulation of your
merge in a scratch clone ([`checks/merge-simulation.log`](checks/merge-simulation.log)) shows: with `m0-decisions` at
`c72247a6`, the fast-forward, after which `CLAUDE.md` holds both texts; 0.8's check after it listing the eleven files of
the recovery package that the device fixes changed, and 0.3 step 7's, against `d5336111`, listing those, the ATS probe's
test file, `Scripts/ci.d/70-g05-ai.sh`, the eight checklists and the Zip guard's two scripts, nothing else; with a
commit of yours after `c72247a6`, the refusal, then an agent's merge, clean, your records intact, and the fast-forward; with
`m0-device-fixes` merged on its own first, as a fast-forward or as a merge commit after a commit of yours, the same
outcome; and, after a commit of yours that changes a line this branch changes too, `--ff-only` refusing and a plain merge
stopping on the conflict, which `git merge --abort` undoes, leaving nothing changed.

## 6. The checks

[`commands/run-checks.sh`](commands/run-checks.sh) ran every check on the fold-in's last documents commit, with no
uncommitted file, writing the logs in [`checks/`](checks/), each headed with the command, the commit, the uncommitted
paths, the host and Xcode, the time and the load, and its console log; the commit after it adds them and nothing else.
Its comment lists every check and what each must show. Before any record changed, the owner-readability fix's runner ran
on the merge commit, `cbdb63bc`, into [`before/`](before/): it shows what `6a510880` and the merge alone changed in what
the earlier checks report (Section 7).

| Log | What ran | Result |
| --- | --- | --- |
| `merge-check.log` | [`commands/merge-check.sh`](commands/merge-check.sh) | Passes: the merge's parents and base, no file in both sides' lists, each side's files at the merge, only the README's added notes since |
| `owner-records-intact.log` | The owner fix's check, with its defaults and with `--owner-head m0-decisions --rev HEAD`, and the version it replaces | All three pass: your commits' files and lines as you committed them |
| `foldin-checks.log` | [`commands/foldin-checks.py`](commands/foldin-checks.py) | Passes: each request as applied, `CLAUDE.md` and its notes, the next steps in one order in four places, the word limits |
| `merge-simulation.log` | [`commands/merge-simulation.sh`](commands/merge-simulation.sh) | Passes: Section 5's cases |
| `step-0.8-paths.log` | [`commands/step-08-paths.sh`](commands/step-08-paths.sh), the new version of `../commands/step-08-paths.sh` | Passes: nothing changed at `6a510880`; exactly the device fixes' eleven files at `a60aa922` and HEAD, so 0.8 runs again |
| `probe-count-check.log` | [`commands/probe-count-check.sh`](commands/probe-count-check.sh) | Passes: 42 passes, 39 and 41 fail with the new minimum, both passed with the old |
| `retired-branch-texts.log`, `renumbered-references.log` | The fidelity fix's and the completeness fix's checks | Pass |
| `ci-contracts.log`, `12-dependency-lock.log`, `13-hard-rules.log` | `Scripts/ci.sh contracts`, `Scripts/ci.d/12-dependency-lock.sh`, `Scripts/ci.d/13-hard-rules.sh` | Each passes |
| `runbook-content-check.log`, `runbook-coverage.log`, `correction-texts.log` | The device-A update's content check with its controls and limits; the step coverage; the correction texts on the three merged branches' trees and HEAD | Pass |
| `check-amendments.log`, `mutation-checks.log`, `check-amendments-records-update.log`, `check-amendments-accuracy.log` | The amendments' checkers and mutations | The fidelity fix's passes with every mutation caught; the other two fail exactly their check 10k, as before |
| `check-records.log`, `check-records-records-update.log`, `check-records-devicea.log` | The device-A records' checks | As before: the first passes, the others fail exactly their known checks |
| `finding-lines.log` | The owner fix's citations of its findings at `832a3636` | Passes |
| `step-0.8-paths-records-update.log`, `owner-checks.log`, `completeness-checks-owner.log`, `completeness-checks-completeness.log`, `merge-simulation-owner.log` | The earlier versions of these checks | Fail exactly on the lines Section 7 lists, by design; the runner checks each failing line against its list |
| `recheck-hon-ep.log`, `decisions-branch.log`, `recheck-own.log`, `gate-checks-exit-prep.log`, `gate-checks-devicea.log` | The earlier rechecks and the two branches' latest gate checks, unchanged | Recorded as they report (Section 7); `compare-earlier-checks.log` lists what they report now beside what they reported at the owner-readability fix |
| `gate-refresh-check.log` | The gate summary's checker, `m0-records-update`'s version, run last | Passes: every cited path exists and every Section 2 status agrees with its records |

## 7. What the earlier checks report now, by design

Each pins texts or states of the branch it was written on, and `6a510880`, the merge and the fold-in changed some of
them on purpose. On the merge commit, before any record changed ([`before/run-checks.console.log`](before/run-checks.console.log)),
five of the owner-readability fix's checks that passed at that fix failed: its `owner-checks.py` on `CLAUDE.md`, which is
no longer `c72247a6`'s (`6a510880`); its `merge-simulation.sh`, whose apply command found the texts already in, and whose
two checks after the merge now list the device fixes' files; its and the completeness fix's `completeness-checks.py`, on
`CLAUDE.md`, on the files 0.3 step 7's check lists against your sittings' commits and on the files the merge bullet
names; and `m0-records-update`'s `step-08-paths.sh`, which expects nothing the drop-in uses to have changed since
`9cdb0a02`. With the fold-in's records:

- **`step-08-paths.sh`** (`m0-records-update`'s): exactly its two lines on the drop-in's paths, the recovery package's
  files listed; this fold-in's version replaces it.
- **The owner fix's `owner-checks.py`**: exactly five checks: `CLAUDE.md` byte for byte `c72247a6`'s (`6a510880`); the
  evidence README's merge commands, which no longer run the apply command, its diff, the lock check or the commit; the
  runbook's 0.3, step 2, and the gate summary's item 1, step 2, which give `CLAUDE.md` as done; and no checklist changed
  since `7c87a82d` (requests 1 and 6). Its other checks pass, the fold-in having added notes rather than replaced the
  texts they read.
- **The owner fix's and the completeness fix's `completeness-checks.py`**: exactly fourteen checks each: `CLAUDE.md`;
  the latest time for `CLAUDE.md`'s texts in the gate summary's step 2, the runbook's 0.3, step 2, its run 1 and the
  evidence README (two in each version); 0.3 step 7's lists against your six sittings' commits, which now hold the device
  fixes' files and `Scripts/ci.d/70-g05-ai.sh`; and the files this branch changes against `c72247a6`, `CLAUDE.md` and the
  device fixes' code among them, which its grouping does not know.
- **The owner fix's `merge-simulation.sh`**: exactly its seven failing lines: the apply command's diff and the commit
  of `CLAUDE.md` (the texts already in), 0.8's check and 0.3 step 7's against `d5336111` (the device fixes' files), and
  in its case B the three lines of the owner-records check that are meant to fail there, as at that fix.
- **The rechecks and the gate checks**: [`checks/compare-earlier-checks.log`](checks/compare-earlier-checks.log), written
  by [`commands/compare-earlier-checks.py`](commands/compare-earlier-checks.py), lists every line naming a problem or a
  result that differs from their logs at the owner-readability fix, once what changes with every run is set aside (the
  commit each run read, times, loads, and the line numbers cited beside a file name). They report the groups they
  reported then (`recheck-own.py` exactly the same lines). What differs: counts (the files changed since each branch's
  start, the paths the gate summary cites, the checklists' markers, the Markdown files the sweeps read and the texts two
  sweeps find in their phrasings, the device fixes' README's and the fold-in's among them, the State line's words); what
  changed in the repeat rule's folders, which now begins with `Scripts/ci.d/70-g05-ai.sh` and holds the device fixes'
  files under `Spikes/`, and 0.8's paths, which the device-A gate check reads and which now hold them; `CLAUDE.md`,
  changed; the device-A update's sweep, whose first unlisted line
  naming `m0-decisions` is now the runbook's new bullet on your next steps; the text the earlier fixes' citation controls
  read at the lines they cite, which moved with the lines added above them; and the fold-in's seven logs that the gate
  summary cites, committed after the run that writes them, which the checks that read the committed tree report missing,
  as they reported the owner-readability fix's five.

## 8. Not done here, and why

- **The device fixes' code checks** (the recovery host and simulator suites, the crash drills, the device builds, the
  ATS probe on the simulator): not run again. The merge changes no file they ran on (the code under `Spikes/` is
  `a60aa922`'s), so their logs, records of their branch, stand for this tree's code.
- **The class-B tests and runbook 0.8**: not run; they need the build Mac's screen unlocked for their whole run, and
  G0.5 recovery's class-B guard is never bypassed. They are yours, as Section 5 gives them.
- **The G0.5 AI drop-in**: not run whole; its count check ran on committed probe logs, with no device or simulator, and
  the probe's code is `a60aa922`'s.
- **The complete CI**: not run. Outside `Docs/` the fold-in changed only `Scripts/ci.d/70-g05-ai.sh`'s minimum count,
  and the merge brought the device fixes' code, which their own checks ran.
- **`CLAUDE.md`**: not changed by the fold-in (Section 2). **The session log**: not written; it is yours.
- **Requests 5 and 15**: not applied (Section 4). **Request 10**: not applied (Section 3).
- **`resolve-locks.sh` and `linkage.sh`**: not run; they resolve packages, which can reach git remotes.
- **Device steps, sign-offs, approvals and the exit**: none ran or was given. **Nothing was pushed**, and no pull
  request was opened.
