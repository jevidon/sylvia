# M0 device and review sessions: log

One row per sitting of [the M0 device runbook](../../M0-device-runbook.md). The step results themselves go where each
gate's checklist says (runbook Section 2); this log only records what was run, when, on which device and from which
commit, so the M0 gate summary can tell what is still pending.

No device step has been run. One Mac-only step has: runbook step 0.8, the class-B run of G0.5 recovery's drop-in, was
done for the current code by an agent on 19 October 2026 at 15:14-15:20 UTC (20 October on the build Mac's clock), in
the M0 final fix's second round, when the Mac's screen was found unlocked (the row marked "agent" below; runbook 0.8).
Every other row is to be filled in by the person who runs the session. (Until 20 October 2026 this paragraph said
nothing had been run, and row 2 named Xcode 27.0: M0 final review round 3, R7-04.)

The rows are in the runbook's run order (its Section 3); session numbers are the runbook's labels. Add a row for each further sitting of a session.

| Run | Session | Date (UTC) | Who | Commit (`git rev-parse HEAD`) | Devices (model, identifier, OS build) | Steps run | Steps not run, and why |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Before the sessions: decisions D-1, D-2 and D-10 (D-3, the Xcode build, decided on 20 October 2026: 27.1), the App Store's automatic updates turned off on the build Mac, device A, reviewers booked | | | | not applicable | | |
| 2 (0.8 only, ahead of the session) | 0 Mac setup, step 0.8 | 2026-10-19, 15:14-15:20 | agent (M0 final fix, second round) | `c4fbfbd` | build Mac: macOS 26.6.2 (25G83), Xcode 27.1 (27A9275); simulator Sylvia-M0-final-fix (iPhone 17, iOS 26.5) | 0.8: passed (class B read back on 53 files and directories; `evidence/M0-Integration/final-fix-2/ci-71-g05-recovery-locked.log`, named before the run for the locked screen of the earlier runs: `evidence/M0-Integration/final-fix-2/README.md`) | 0.1-0.7 and 0.9: for you, in the session below |
| 2 | 0 Mac setup | | | | build Mac: macOS ..., Xcode 27.1 (27A9275), the pin since 20 October 2026 (step 0.2 checks it) | | |
| 3 | 1 Automated suites (iPhone 17 Pro) | | | | | | |
| 4 | 4 Transfer (iPhone 17 Pro and Mac) | | | | | | |
| 5 | 2 Reading (iPhone 17 Pro) | | | | | | |
| 6 | 6 AI and recovery (iPhone 17 Pro and Mac) | | | | | | |
| 7 | 7 Design (iPhone 17 Pro) | | | | | | |
| 8 | 8 Oldest supported iPhone (device A) | | | | | | |
| 9 | 3 Audio (iPhone 17 Pro) | | | | | | |
| 10 | 5 Intake (iPhone 17 Pro and Mac) | | | | | | |
| 11 | 9 iPad | | | | | | |
| 12 | 10 Reviews and decisions | | | | not applicable | | |
