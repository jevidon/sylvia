# M0 device and review sessions: log

One row per sitting of [the M0 device runbook](../../M0-device-runbook.md). The step results themselves go where each
gate's checklist says (runbook Section 2); this log only records what was run, when, on which device and from which
commit, so the M0 gate summary can tell what is still pending.

No device step has been run. One Mac-only step has had an agent's run: runbook step 0.8, the class-B run of G0.5
recovery's drop-in, by an agent on 19 October 2026 at 15:14-15:20 UTC (20 October on the build Mac's clock), in the M0
final fix's second round, when the Mac's screen was found unlocked (the row marked "agent" below). Its class-B evidence
stands for the recovery code, which has not changed since; on 22 October 2026 the drop-in gained steps 13-15, for the
lock harness, and no run of the whole drop-in has passed since, so 0.8 is to be run once more, in Session 0 (runbook
0.8). Every other row is to be filled in by the person who runs the session. (Until 20 October 2026 this paragraph said
nothing had been run, and row 2 named Xcode 27.0: M0 final review round 3, R7-04. Until 22 October 2026, after the
review of the decisions round, it called 0.8 done for the current code, and rows 1, 8 and 12 still had the tasks and
titles from before the decisions: its findings OWN-09 and HON-6. Until 23 October 2026, after the review of the
decisions round's fix, rows 1 and 12 led with the merge of `m0-decisions` and left out R4-01, R4-02 and the final-review
records, and row 11 did not mark the iPad's design steps: its findings OWN2-01, OWN2-02 and OWN2-05. Until the
follow-up of the same day, row 1 asked for the iPad if needed and allowed the merge only if H-1 covered it, and
row 12 started the security sign-off without its dependence on runs 8-11: the review of the second fix, its
findings OWN3-01, OWN3-03 and OWN3-06, and the product owner's answers of 23 October 2026. Until the follow-up's fix,
the same day, row 1 neither had the agent's branch merged into `m0-decisions` nor asked for the iPad's iPadOS: the
review of the follow-up, its findings FID4-02 and FID4-03.)

The rows are in the runbook's run order (its Section 3); session numbers are the runbook's labels. Add a row for each further sitting of a session.

| Run | Session | Date (UTC) | Who | Commit (`git rev-parse HEAD`) | Devices (model, identifier, OS build) | Steps run | Steps not run, and why |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Before the sessions (runbook Section 3, run 1): the commit to build from, recorded (`m0-decisions` checked out; or merged into `main`, which H-1's exception covers since 23 October 2026, and `main` then brought up to date from GitHub), `CLAUDE.md`'s milestone paragraph corrected or its correction asked for before any agent request, Apple's release notes for Xcode 27.1 read as technical lead and recorded in ADR-0001, R4-01 and R4-02 asked of an agent (base `m0-decisions`, the result on a branch of its own, merged into `m0-decisions`, never straight into `main`) and the final-review records asked for (Session 10 waits for both), device A on iOS 26 (or 27) with a Lightning cable, iCloud storage and space on phone B, and your iPad, on iPadOS 26 (or 27), with its keyboard and trackpad or mouse. The decisions were taken on 22 October 2026 and the open points answered on 23 October 2026, and the App Store's automatic updates are off | | | | not applicable | | |
| 2 (0.8 only, ahead of the session) | 0 Mac setup, step 0.8 | 2026-10-19, 15:14-15:20 | agent (M0 final fix, second round) | `c4fbfbd` | build Mac: macOS 26.6.2 (25G83), Xcode 27.1 (27A9275); simulator Sylvia-M0-final-fix (iPhone 17, iOS 26.5) | 0.8: passed (class B read back on 53 files and directories; `evidence/M0-Integration/final-fix-2/ci-71-g05-recovery-locked.log`, named before the run for the locked screen of the earlier runs: `evidence/M0-Integration/final-fix-2/README.md`) | 0.1-0.7 and 0.9: for you, in the session below; 0.8 again, since the drop-in gained the lock harness's steps on 22 October 2026 |
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
| 12 | 10 Sign-offs and the exit review (the security sign-off after runs 3-6 and 8-11 and once R4-01 and R4-02 are closed; the exit review once the final-review records are in or recorded as lost) | | | | not applicable | | |
