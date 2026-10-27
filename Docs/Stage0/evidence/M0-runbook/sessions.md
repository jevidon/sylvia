# M0 device and review sessions: log

One row per sitting of [the M0 device runbook](../../M0-device-runbook.md). The step results themselves go where each
gate's checklist says (runbook Section 2); this log only records what was run, when, on which device and from which
commit, so the M0 gate summary can tell what is still pending.

Device testing began on 2026-10-25 UTC: Session 1.1 passed on phone B; see the appended row. Other device steps remain pending. One Mac-only step has had agents' runs: runbook step 0.8, the class-B run of G0.5
recovery's drop-in. An agent ran it on 19 October 2026 at 15:14-15:20 UTC (20 October on the build Mac's clock), in the
M0 final fix's second round, when the Mac's screen was found unlocked; and, after the drop-in gained steps 13-15, for
the lock harness, on 22 October 2026, a waiter of the orchestrating session ran the whole drop-in from clean on
`9cdb0a02` with the screen unlocked, at 22:36-22:44 UTC that day (23 October on the build Mac's clock). Both passed (the
rows marked "agent" below). The class-B evidence stands for the recovery code, which has not changed since, and 0.8 is
to be run again only if what the drop-in builds, copies or runs changes after `9cdb0a02` (runbook 0.8, and 0.3, step
7). Every other row is to be filled in by the person who runs the session. (Until 20 October 2026 this paragraph said
nothing had been run, and row 2 named Xcode 27.0: M0 final review round 3, R7-04. Until 22 October 2026, after the
review of the decisions round, it called 0.8 done for the current code, and rows 1, 8 and 12 still had the tasks and
titles from before the decisions: its findings OWN-09 and HON-6. Until 23 October 2026, after the review of the
decisions round's fix, rows 1 and 12 led with the merge of `m0-decisions` and left out R4-01, R4-02 and the final-review
records, and row 11 did not mark the iPad's design steps: its findings OWN2-01, OWN2-02 and OWN2-05. Until the
follow-up of the same day, row 1 asked for the iPad if needed and allowed the merge only if H-1 covered it, and
row 12 started the security sign-off without its dependence on runs 8-11: the review of the second fix, its
findings OWN3-01, OWN3-03 and OWN3-06, and the product owner's answers of 23 October 2026. Until the follow-up's fix,
the same day, row 1 neither had the agent's branch merged into `m0-decisions` nor asked for the iPad's iPadOS: the
review of the follow-up, its findings FID4-02 and FID4-03. Until its second fix, the same day, row 1 said neither that
the agent's work goes on to `main` before the exit only if the product owner first says H-1's exception covers that, nor
that the iPad's fitness is unverified until it is checked: the same review's findings HON4-01 and HON4-03. Until its
third fix, the same day, row 1 named no branch for the correction of `CLAUDE.md`, and row 12 named neither the
technical lead's reviews of the records, the release owner's ADR-0014 item 6 nor `linkage.sh`: the same review's
findings OWN4-06, OWN4-01 and OWN4-07. Until its fourth fix, the same day, row 1 had no step for committing the
session records on `m0-decisions`, and row 12 named neither the Section 23.1 sign-offs of D02, D05 and D17's
persistence owner, nor `linkage.sh` in the security sign-off's timing: the review of the follow-up's fixes, its
findings OWN5-02, OWN5-01 and OWN5-03. Until 23 October 2026, after the run of the whole drop-in on `9cdb0a02`, it
said that no run of the whole drop-in had passed since 22 October 2026, and that 0.8 was to be run once more, in
Session 0: `M0-gate.md` Section 6.3, item 92.)

The rows are in the runbook's run order (its Section 3); session numbers are the runbook's labels. Add a row for each further sitting of a session.

| Run | Session | Date (UTC) | Who | Commit (`git rev-parse HEAD`) | Devices (model, identifier, OS build) | Steps run | Steps not run, and why |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Before the sessions (runbook Section 3, run 1; `M0-gate.md` Section 1, item 1, in its order): (1) `m0-decisions` checked out; (2) `CLAUDE.md`'s milestone paragraph corrected on `m0-decisions` and committed there, or that commit asked for, before any agent request and before any merge into `main`; (3) only if you build from `main`: `m0-decisions` merged into it, which H-1's exception covers since 23 October 2026, before any agent work is in `m0-decisions`, and `main` then brought up to date from GitHub; (4) the commit to build from, checked and recorded; (5) R4-01 and R4-02 asked of an agent (base `m0-decisions`, the result on a branch of its own, merged into `m0-decisions`, never straight into `main`, and on to `main` before the exit only if you first say that H-1's exception covers that) and the final-review records asked for (Session 10 waits for both); (6) after each sitting, its records and evidence committed on `m0-decisions` before any agent works from them, never on `main` before the exit; (7) Apple's release notes for Xcode 27.1 read as technical lead and recorded in ADR-0001; (8) device A on iOS 26 (or 27) with a Lightning cable; (9) your iPad, with its keyboard and trackpad or mouse, checked for iPadOS 26 (or 27) before Session 0 (whether it can run Session 9 is not verified until then and 0.4's record); (10) iCloud storage and space on phone B. The decisions were taken on 22 October 2026 and the open points answered on 23 October 2026, and the App Store's automatic updates are off | | | | not applicable | | |
| 2 (0.8 only, ahead of the session) | 0 Mac setup, step 0.8 | 2026-10-19, 15:14-15:20 | agent (M0 final fix, second round) | `c4fbfbd` | build Mac: macOS 26.6.2 (25G83), Xcode 27.1 (27A9275); simulator Sylvia-M0-final-fix (iPhone 17, iOS 26.5) | 0.8: passed (class B read back on 53 files and directories; `evidence/M0-Integration/final-fix-2/ci-71-g05-recovery-locked.log`, named before the run for the locked screen of the earlier runs: `evidence/M0-Integration/final-fix-2/README.md`) | 0.1-0.7 and 0.9: for you, in the session below; 0.8 again, since the drop-in gained the lock harness's steps on 22 October 2026 (done: the next row) |
| 2 (0.8 only, ahead of the session) | 0 Mac setup, step 0.8: the whole drop-in, its steps 13-15 for the lock harness included | 2026-10-22, 22:36-22:44 | agent (a waiter of the orchestrating session, after the follow-up's fourth fix; not the product owner) | `9cdb0a02` | build Mac: macOS 26.6.2 (25G83), Xcode 27.1 (27A9275); simulator Sylvia-M0-dec-assembly (iPhone 17, iOS 26.5) | 0.8: passed, from clean, the screen unlocked at the start and the end, `G05_ALLOW_MISSING_CLASS_B` not set (class B read back on 53 files and directories; 73 host tests, 68 simulator tests and the lock harness's 49 tests passed, with its UI smoke test and the app's signed build; `evidence/M0-Decisions/assembly/unlocked-run-1/console.log`) | 0.1-0.7 and 0.9: for you, in the session below; 0.8 again only if what the drop-in builds, copies or runs changes after `9cdb0a02` (runbook 0.3, step 7) |
| 2 | 0 Mac setup | | | | build Mac: macOS ..., Xcode 27.1 (27A9275), the pin since 20 October 2026 (step 0.2 checks it) | | |
| 3 | 1 Automated suites (iPhone 17 Pro) | | | | | | |
| 4 | 4 Transfer (iPhone 17 Pro and Mac) | | | | | | |
| 5 | 2 Reading (iPhone 17 Pro) | | | | | | |
| 6 | 6 AI and recovery (iPhone 17 Pro and Mac) | | | | | | |
| 7 | 7 Design (iPhone 17 Pro) | | | | | | |
| 8 | 8 Device A, your iPhone 11 Pro (after Session 4) | | | | | | |
| 9 | 3 Audio (iPhone 17 Pro) | | | | | | |
| 10 | 5 Intake (iPhone 17 Pro and Mac) | | | | | | |
| 11 | 9 iPad (you judge the design steps 9.1-9.4) | | | | | | |
| 12 | 10 Sign-offs and the exit review (the security sign-off after runs 3-6 and 8-11, once R4-01 and R4-02 are closed and after `linkage.sh`'s run, with ADR-0014's items 4, 5 and 9 and the request to drop marmelroy/Zip; `linkage.sh` under Xcode 27.1, after `resolve-locks.sh`, before the reviews of ADR-0014; the technical lead's review of each record that names the technical lead, ADR-0014's lock and item 7, and D02's sign-off; QA's sign-off, with D05's codec list; D03's outcome; D17's persistence owner's sign-off; the release owner's ADR-0014 item 6; G0.5 AI step 9.2's wording review and its two decisions; the ADR approvals as runbook Section 6 lists them; the exit review once the final-review records are in or recorded as lost) | | | | not applicable | | |

| 3a | 1 Automated suites, step 1.1 only | 2026-10-25 17:12 UTC | Codex with Justin Evidon | `96bdc7e996f99fcd2571ea983cc32a04076a5a07` | iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446) | 1.1 passed-device: 3 Keychain tests; G02-Transfer/device/01-keychain-class.md | 1.2 onward not run; Session 0 remains incomplete. Developer Mode verified; user confirmed updates off and at least 15 GB free. |

| 3b | 1 Automated suites, step 1.2 | 2026-10-25 17:14 UTC | Codex with Justin Evidon | `8404f342` | iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446) | Attempt blocked before tests: Xcode requires a host app for SylviaRecoveryTests; G05-Recovery/device/step-1-tests.log and step-1-2-results.txt | No recovery tests or latency measurements; remaining Session 1 steps pending. |

| 3c | 1 Automated suites, step 1.2 hosted | 2026-10-25 UTC | Codex with Justin Evidon | `432acc13` plus DeviceTests code committed unchanged as `4be1a1a4` | iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446) | Recovery suite failed: 68 tests, 4 expected skips, 108 issues; G05-Recovery/device/step-1-hosted-results.md | Remaining latency runs pending; host blocker resolved, migration protection and backup error failures need diagnosis. |

| 3d | 1 Automated suites, step 1.3 | 2026-10-25 17:24–17:26 UTC | Codex with Justin Evidon | `d5336111` | iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446) | AI step 1 failed: private-address timeouts; step 4 passed-device: streaming interruption. Repeated after owner allowed Local Network prompt. G05-AI/device/step-01-ats.txt and step-04-suspension.txt | AI steps 2–3 and live provider/human checks not run. Audio started separately. |

| 3e | 0 Mac setup, step 0.7 | 2026-10-26 and 27 UTC | Justin Evidon | `c72247a6` (first run), `b0ff53ae` (re-run) | the build Mac, macOS 26.6.2 (25G83) | First signed run failed on the test's own check, which counted the data protection item twice on macOS 26.6.2 (G02-Transfer/probe-fix/README.md); the re-run on the fixed probe passed-device: G02-Transfer/keychain-identity-signed-fixed.log, RESULT: PASS | Row added by the orchestrating session from the owner's committed logs. |

| 3f | 1 Automated suites, step 1.2 again | 2026-10-26 UTC | Justin Evidon | `b0ff53ae` | iPhone 17 Pro, iPhone18,1 | Not run: xcodebuild stopped before any test (the destination's device id was not set), and the phone's storage was then full; G05-Recovery/device/step-1-hosted-run2-tests.log | The fixed recovery suite's phone run stays undone. Row added by the orchestrating session. |

| 3g | 1 Automated suites, step 1.4 | 2026-10-25 UTC | Codex with Justin Evidon | `d5336111` | iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446) | Three attempts: halted at the owner's request (G04-Audio/device/step-01-interrupted.log), stopped for a storage retry (resumed-1/), and a full run that failed: 155 tests in 27 suites, 149 passed, 4 failed, 19 issues including 3 known (resumed-2/) | Failed: the remux mitigation's timing (8 issues), capture export and preview deep in the long formats, cold resume by depth, and the two-hour soak at 3x across a member boundary. Not diagnosed. Row added by the orchestrating session. |

**Device testing ended on 27 October 2026**, at the product owner's decision: "merged. i'm done with testing m0, feel free to do final passes yourself otherwise move forward." Every step not run stays unrun; `Docs/Stage0/M0-gate.md` Section 1 lists them.
