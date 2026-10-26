# What was relayed to the fix of the review's completeness findings (26 October 2026)

A record of what the orchestrating session's workflow relayed to this fix, kept as data: with the first fix's
`../relayed-findings.md` and the second fix's `../accuracy/relayed-findings.md`, it is the review's only committed record
(the review's own logs are not committed). Relayed on 26 October 2026 on the build Mac's clock (25 October UTC).

- **The product owner's request**, as the workflow relayed it: "keep going".
- **The task**: fix one reviewer's findings, lens completeness, round 1, on branch `m0-sessions`, "reviewed at
  ec91f66a863c70980533f27f53d8e6b44f234485"; other lenses' fixers run after this one, one at a time, on the same branch;
  set up on `m0-sessions`, continuing from any work after `ec91f66a`. "Fix every blocker and major properly, and the
  minors unless that changes scope; explain any you leave in not_fixed. Re-run the checks your changes affect and save
  their logs under Docs/Stage0/evidence/M0-DeviceA/fix-1/." With it came the state of 24 October 2026 and the device-A
  change that the update had to describe, as the update's instructions part recorded them
  (`../../instructions/relayed-2026-10-24.md`), and the rules of the run: no push, fetch or pull request; no write to,
  and no branch checked out in, `~/Git/sylvia`, `~/Git/sylvia-m0` or `~/Git/sylvia-sessions`; `m0-exit-prep` and its
  `m0-exit-*` branches not touched; no physical device; the class-B guard of G0.5 recovery's drop-in never bypassed;
  nothing here a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit.
- **The commit the findings cite.** The task names `ec91f66a`, the second fix's last commit, as the commit reviewed; the
  findings' line numbers and quoted texts are those of `8082bdb6`, the commit the first and second fixes' findings cite
  (for example, `M0-device-runbook.md:6` reads "Nothing in this runbook has been run on a device" at `8082bdb6` only, and
  the finding DA-01 says "At 8082bdb6, m0-sessions still tells the owner otherwise"):
  [`commands/finding-lines.py`](commands/finding-lines.py) checks them at `8082bdb6`. Several of them the first two
  fixes had already answered, wholly or in part, before this fix began (`README.md`, The findings, and what was done).

## The findings, verbatim

Nine, one blocker, two major and six minor, as relayed (the reviewer's text, unchanged):

```json
[
 {
  "id": "DA-01",
  "severity": "blocker",
  "title": "The owner's branch and checkout instructions describe a state the update's own evidence shows is false; following them would strand the owner's in-progress sittings",
  "detail": "Checked read-only on 26 October 2026 (NZDT). `git for-each-ref --format='%(refname:short) %(worktreepath)' refs/heads/m0-decisions` shows /Users/jevidon/Git/sylvia-sessions on m0-decisions at c72247a6. `git rev-list --count main..m0-decisions` gives 8 (8404f342..c72247a6, 06:12-06:33 NZDT on 26 Oct), so m0-decisions is not behind main. Those commits record the owner's device sittings: rows 3a-3d of m0-decisions's Docs/Stage0/evidence/M0-runbook/sessions.md. They are Session 1.1 passed-device on phone B; 1.2 blocked ('Xcode requires a host app for SylviaRecoveryTests'); then a hosted run that failed; and 1.3. They also add Spikes/G05-Recovery/DeviceTests and rewrite runbook 1.2's xcodebuild commands to use it.\n\nAt 8082bdb6, m0-sessions still tells the owner otherwise:\n- Runbook 0.3 step 1 (M0-device-runbook.md:163): 'The orchestrating session switches this checkout to it, from `main` at `96bdc7e9` ... if it still reads `main` ... run `git checkout m0-sessions` there yourself. Never build from `m0-integrate` or `m0-decisions`, both behind `main`'.\n- Gate summary item 1 step 1 (M0-gate.md:16) says the same.\n- The setup lines of device-checklists/G04-Audio.md:11, G05-AI.md:7 and G05-Recovery.md:11 say '`m0-integrate` and `m0-decisions` are behind `main`'.\n- Integration log 28.1 (integration-log.md:1570) says 'on `main` at `96bdc7e9`'.\n- CLAUDE.md:5 says 'both are behind `main`'.\n\nThe update knew this. Its branch-state.log and the gate checks' part 1i print 'm0-decisions ... behind main: NO', but the check does not fail on it. Item 115 (M0-gate.md:714) and integration log 28.8.6 say these steps 'do not describe that checkout as it now is'. Yet no owner-facing step changed. 0.3 step 1 does not cover a checkout that reads m0-decisions, and it does not say that the switch waits for the reconciliation; only item 115 and the assembly README say so.\n\nFollowed as written, these steps would move the in-progress sittings to a branch that lacks their session-log rows, their device evidence and the DeviceTests host. Runbook 8.10 ('the commands of 1.2 with A's DEVICE_ID', M0-device-runbook.md:950) would also send device A to the 1.2 commands that the owner's row 3b found Xcode refuses.\n\nFix: reconcile m0-decisions into m0-sessions, or record why not. Then correct 0.3 step 1, item 1 step 1, the three checklist setup lines and 28.1. Have 0.3 step 1 say that the switch waits for the reconciliation.\n\nEvery other check I ran reproduces:\n- The assembly's gate-checks.sh exits 0 on 8082bdb6; its log matches the committed one except for the commit and timings.\n- The records part's runner and the instructions part's gate checks fail exactly as assembly/README.md says.\n- unlocked-record/round-3 gate checks on ab03fe2f reproduce old-round-3-gate-checks-2.log.\n- The runbook content-check runner passes.\n- Both Apple-page readers pass (read 25 Oct 2026 18:10 UTC).\n- The device-type profiles are identical to the committed log.\n- A copy of screen-probe.sh with unique simulator names gives 375 × 812 pt at nativeScale 2.88 for the 13 mini, 375 × 812 at 3.0 for the 11 Pro, and 375 × 667 for the SE (2nd generation).\n- `git diff --stat 9cdb0a02 HEAD -- <0.8's paths>` is empty, and no file the drop-in runs names either lock file.\n- `git diff --name-status 6cede84a -- Docs/Stage0/evidence` lists only added files under M0-DeviceA/.",
  "location": "Docs/Stage0/M0-device-runbook.md:163; Docs/Stage0/M0-gate.md:16, 714; Docs/Stage0/device-checklists/G04-Audio.md:11, G05-AI.md:7, G05-Recovery.md:11; Docs/Stage0/integration-log.md:1570; CLAUDE.md:5; Docs/Stage0/evidence/M0-DeviceA/assembly/checks/branch-state.log"
 },
 {
  "id": "DA-02",
  "severity": "major",
  "title": "'No device step has run' still stands unqualified, after the assembly saw commits recording device runs",
  "detail": "These statements remain as written:\n- M0-gate.md:10: 'None of the gates' device or human steps has run'.\n- M0-gate.md:132: 'no device step has run'.\n- M0-gate.md:718: 'not one device or human step has run'.\n- Docs/Stage0/README.md:5: 'no device step has run, so every gate stays pending'. This is a paragraph the assembly edited.\n- M0-device-runbook.md:6: 'Nothing in this runbook has been run on a device'.\n\nThe same assembly recorded commits 'whose messages record device runs' (M0-gate.md:714, item 115; integration-log.md:1684). m0-decisions's session log at c72247a6 (rows 3a-3d) records Session 1.1 passed-device on phone B. It also records phone B as iOS 27.0.1 (24A446), while the m0-sessions records give iOS 26.7 (23H24): runbook 1.1 row B, plan 19.1 and ADR-0001's Test devices.\n\nUnder CLAUDE.md's evidence-honesty rules these are now claims that evidence the update holds contradicts. Until the reconciliation, state instead that no device result is recorded on m0-sessions, and that sittings recorded on m0-decisions since 25 October 2026 UTC await reconciliation (item 115).",
  "location": "Docs/Stage0/M0-gate.md:10, 132, 718; Docs/Stage0/README.md:5; Docs/Stage0/M0-device-runbook.md:6"
 },
 {
  "id": "DA-03",
  "severity": "major",
  "title": "Session log rows 1 and 8 still send run 1 to m0-decisions and name the iPhone 11 Pro, and the owner's steps do not say so",
  "detail": "Docs/Stage0/evidence/M0-runbook/sessions.md:40 (row 1) still lists run 1 as written before 24 October:\n- '(1) `m0-decisions` checked out';\n- '(2) `CLAUDE.md`'s milestone paragraph corrected on `m0-decisions`';\n- '(5) ... base `m0-decisions` ... merged into `m0-decisions`';\n- '(6) ... committed on `m0-decisions`';\n- '(7) Apple's release notes ... read as technical lead'.\n\nLine 49 still titles row 8 'Device A, your iPhone 11 Pro', and line 7 still says 'No device step has been run.'\n\nThe owner fills in this log at every sitting: runbook Section 2 (M0-device-runbook.md:105) has them add a row per sitting, and 0.4 has them record device A there. Neither run 1, 0.3 nor Section 2 says that rows 1 and 8 predate 24 October 2026. The deferral and the replacement text are only in gate summary items 109 and 112 (M0-gate.md:705, 711) and in assembly/README.md.\n\nThe gate checks keep this file unchanged (part 1b), so the warning belongs in the owner's own steps: a pointer in run 1 / 0.3, or in Section 2, saying that item 1 supersedes rows 1 and 8 until the owner applies the assembly's text.\n\nThe stale run-1 wording on main is what the owner's checkout followed on 26 October: it moved to m0-decisions (DA-01).",
  "location": "Docs/Stage0/evidence/M0-runbook/sessions.md:7, 40, 49; Docs/Stage0/M0-device-runbook.md:105, 163-172"
 },
 {
  "id": "DA-04",
  "severity": "minor",
  "title": "The release-notes check is still called 'awaited' in records the update edited, against run 1 step 7 and 0.2",
  "detail": "These still say the check of Apple's release notes is awaited:\n- Docs/ADRs/README.md:17, ADR-0001's cell, under the column this update dated 'Status (24 October 2026)': 'whether 27A9275 is the non-beta release still awaits a check of Apple's release notes'.\n- Plan 23.1 D01 (Sylvia_v1_iOS_Implementation_Plan.md:1159), a row this update edited: 'Pending: the technical lead's sign-off, with the check of Apple's release notes for Xcode 27.1 (ADR-0001)'.\n- ADR-0001's Status: 'has not been checked against Apple's release notes'.\n- CLAUDE.md's toolchain line.\n\nGate summary item 1 step 7 (M0-gate.md:22) and runbook 0.2 (M0-device-runbook.md:159) say Apple's pages were read on 24 October 2026 and only the one-line confirmation is pending.\n\nAssembly README 'Not done here' and integration log 28.8.7 acknowledge only ADR-0001's Status line and CLAUDE.md. Give the index cell and D01 a dated note (Apple's pages read on 24 October 2026, the confirmation pending), or list them with ADR-0001 as left to the m0-exit-prep merge.",
  "location": "Docs/ADRs/README.md:17; Docs/Sylvia_v1_iOS_Implementation_Plan.md:1159; Docs/ADRs/0001-platform-baseline-and-toolchain.md:3; CLAUDE.md (Toolchain)"
 },
 {
  "id": "DA-05",
  "severity": "minor",
  "title": "ADR-0014 still routes R4-01/R4-02 work through m0-decisions",
  "detail": "Docs/ADRs/0014-dependency-lock-and-license-inventory.md:247, the dated note of 23 October 2026, still reads: 'the request names `m0-decisions` as the agent's base and a branch of its own for the result, which reaches the device sessions' build only when the product owner merges it into `m0-decisions`'.\n\nThe update leaves this to the m0-exit-prep run, to avoid a merge conflict (M0-DeviceA/README.md, 'Not done here'; assembly README). On m0-sessions, though, it is a live instruction that an agent reading ADR-0014 would follow. Nothing points such an agent to ADR-0002 Branches or to m0-sessions until m0-exit-prep merges.",
  "location": "Docs/ADRs/0014-dependency-lock-and-license-inventory.md:247"
 },
 {
  "id": "DA-06",
  "severity": "minor",
  "title": "Step 1 of 8.10 is called chip-independent, but its pass includes the 200 ms p95 latency expectation",
  "detail": "Session 8's opening (M0-device-runbook.md:918) says '8.8 and 8.9 record what iOS does, not a speed or memory figure, and so does step 1 of 8.10'. The D-2 note (M0-device-runbook.md:1025) counts step 1 of 8.10 among the steps 'not affected'.\n\nStep 1's expected result is the whole suite passing ('Test run with 68 tests in 11 suites passed'). That suite includes `latency()`, with `#expect(result.p95Ms <= 200)` (Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DurabilityTests.swift:168-173). Step 1's log also holds the first of step 2's p95 values (device-checklists/G05-Recovery.md:46). So a pass of step 1 on the 13 mini rests partly on an A15 timing. The figure itself is covered as step 2's, so no outcome changes.\n\nSay that only step 1's readbacks, SQLite version and pragmas are independent of the chip, and that its pass includes the latency expectation, which is the 13 mini's.",
  "location": "Docs/Stage0/M0-device-runbook.md:918, 1025; Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DurabilityTests.swift:173"
 },
 {
  "id": "DA-07",
  "severity": "minor",
  "title": "0.8's note of 26 October names no commit, and its folder-wide path check will flag DeviceTests, which the drop-in does not build",
  "detail": "Runbook 0.8's dated note of 26 October 2026 (M0-device-runbook.md:210) says the assembly ran the check 'on the merged tree'. It names no commit; the log ran on 5e455f70 (assembly/checks/dropin-paths.log, header). The task asked 0.8 to state the commit checked.\n\nThe check also covers all of `Spikes/G05-Recovery`. The DeviceTests folder that m0-decisions adds (project.yml, App/TestHost.swift, Support/Bundle+Module.swift, Package.resolved) is not built, copied or run by Scripts/ci.d/71-g05-recovery.sh or LockHarness/Scripts/harness-checks.sh. Those build the package's Sources and Tests targets and the LockHarness. After the reconciliation, 0.8's rule 'any output means 0.8 runs again' would therefore call for a 10-15 min unlocked-screen run that nothing the drop-in uses requires (M0-gate.md:714 already predicts it).\n\nName the commit. Either narrow the paths, or say how to treat a change the drop-in does not build.",
  "location": "Docs/Stage0/M0-device-runbook.md:210"
 },
 {
  "id": "DA-08",
  "severity": "minor",
  "title": "ADR-0013 lacks the note the assembly added: G0.6 step 12 on device A gives the 13 mini's result",
  "detail": "The assembly added to runbook Session 8's repeats (M0-device-runbook.md:952) and to Docs/Stage0/evidence/M0-DeviceA/README.md:61 that G0.6 step 12 on device A, in M3, depends on the phone's speed: its stated limit is a stall of more than 150 ms. So on device A it gives the 13 mini's result.\n\nADR-0013 is one of the records D-2 (b) names. It records the narrower exception as not applying to G0.6's steps (0013-design-language.md:136, which covers the M0 type-role steps). Its open item lists 'steps 1-3, 5-9, 12 and 16-19 on device A' in M3 (line 290) without that note, although its section 10 (line 220) states limit (b) as a main-thread stall of more than 150 ms.\n\nAdd the qualification for step 12 in M3 to ADR-0013's open item, so it agrees with the runbook, as the task asked of each record that D-2 (b) names.",
  "location": "Docs/ADRs/0013-design-language.md:136, 290"
 },
 {
  "id": "DA-09",
  "severity": "minor",
  "title": "Nothing says where the owner's one-line Xcode confirmation goes while ADR-0001 is on the open m0-exit-prep branch",
  "detail": "Gate summary item 1 step 7 (M0-gate.md:22) says the confirmation 'is recorded in ADR-0001 as your check', and that ADR-0001 records the same evidence on m0-exit-prep until its merge. Runbook 0.2 (M0-device-runbook.md:159) says the one line 'is still to be recorded'.\n\nThe confirmation is due in run 1, before Session 0: 'if you do not confirm it, PO-35 comes back to you before any device result rests on it'. But the open m0-exit-prep run changes ADR-0001, and 0.3 step 5 (M0-device-runbook.md:167) tells the owner to leave a record that an open agent branch changes alone until that branch is merged.\n\nNeither text says where the owner's line goes in the meantime, for example in session log row 1, copied into ADR-0001 after the merge.",
  "location": "Docs/Stage0/M0-gate.md:22; Docs/Stage0/M0-device-runbook.md:159, 167"
 }
]
```
