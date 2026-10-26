# What was relayed to the fix of the review's fidelity findings (26 October 2026)

A record of what the orchestrating session's workflow relayed to this fix, kept as data: it is the review's only
committed record (the review's own logs are not committed). Relayed on 26 October 2026 on the build Mac's clock (25
October UTC).

- **The product owner's request**, as the workflow relayed it: "keep going".
- **The task**: fix one reviewer's findings, lens fidelity, round 1, on branch `m0-sessions`, reviewed at
  `8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22`; other lenses' fixers run after this one, one at a time, on the same
  branch. "Fix every blocker and major properly, and the minors unless that changes scope; explain any you leave in
  not_fixed. Re-run the checks your changes affect and save their logs under Docs/Stage0/evidence/M0-DeviceA/fix-1/."
  With it came the state of 24 October 2026 and the device-A change that the update had to describe, as the update's
  instructions part recorded them (`../instructions/relayed-2026-10-24.md`), and the rules of the run: no push, fetch or
  pull request; no write to, and no branch checked out in, `~/Git/sylvia`, `~/Git/sylvia-m0` or `~/Git/sylvia-sessions`;
  `m0-exit-prep` and its `m0-exit-*` branches not touched; no physical device; the class-B guard of G0.5 recovery's
  drop-in never bypassed; nothing here a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit.

## The findings, verbatim

Seven, two major and five minor, as relayed (the reviewer's text, unchanged; line numbers are those of `8082bdb6`,
checked by [`commands/finding-lines.py`](commands/finding-lines.py)):

```json
[
 {
  "id": "FID-DA-01",
  "severity": "major",
  "title": "The owner's run-1 checkout steps describe a sessions checkout state that the assembly itself found had changed",
  "detail": "Several records say ~/Git/sylvia-sessions is on main at 96bdc7e9, will be switched from there, and that sessions build from m0-sessions: run 1 step 1 (M0-gate.md:16), runbook 0.3 step 1 (M0-device-runbook.md:163), integration log 28.1 (integration-log.md:1570) and README.md:49. The runbook header (M0-device-runbook.md:6) still says nothing in it has been run on a device.\n\nThe assembly read the branches at 2026-10-25T17:46:45Z (Docs/Stage0/evidence/M0-DeviceA/assembly/checks/branch-state.log) and saw something else: the checkout was on m0-decisions at c72247a6. That branch is 8 commits past 044ed3cf. The commit messages record device runs, and the commits add Spikes/G05-Recovery/DeviceTests. I re-read the ref here: it is unchanged. The update records this only as history (M0-gate.md:714 item 115; integration-log.md:1682, 28.8.6). Its recheck still asserts the 24 October state everywhere.\n\nThose commits' own records say more (git show m0-decisions:Docs/Stage0/evidence/M0-runbook/sessions.md rows 3a-3d and 2026-10-26-setup.txt; not verified here):\n- sittings on phone B since 25 October 2026 UTC, built from 96bdc7e9 and from later m0-decisions commits;\n- phone B on iOS 27.0.1 (24A446), where every m0-sessions record says iOS 26.7 (23H24);\n- a G0.5 recovery step 1.2 run blocked for want of a host app, which DeviceTests answers.\n\nRunbook 0.3 step 1 covers only 'if it still reads main', and offers 'git checkout m0-sessions' yourself. An owner who finds m0-decisions gets no instruction. A switch made as written would build the next sitting from a branch without those records or the host app. Once DeviceTests merges, 0.8 must run again.\n\nIntegration log 28.1 also says the checkout was on main 'as git worktree list showed it on 26 October 2026' (added in fdbec8b8). No committed log backs that reading.\n\nBefore the checkout moves, reconcile m0-decisions with m0-sessions. Then bring run 1 step 1, 0.3 step 1, the runbook header, README.md and 28.1 in line with the state actually observed.",
  "location": "Docs/Stage0/M0-device-runbook.md:163, :6; Docs/Stage0/M0-gate.md:16, :714; Docs/Stage0/integration-log.md:1570, :1682; README.md:49"
 },
 {
  "id": "FID-DA-02",
  "severity": "major",
  "title": "Records say no A13 phone is available in M0; the decision says only that the A13 floor is not measured in M0",
  "detail": "Four places treat 'no A13 phone in M0' as a fact:\n- Docs/Stage0/device-checklists/G02-Transfer.md:199 (step 22.5's note): '(24 October 2026: no A13 phone is at hand in M0. ...)'.\n- Runbook 2.12 (M0-device-runbook.md:383): the A13 'which no device of M0 has (Section 1.1)'.\n- G01-EPUB checklist :65: 'which no device in M0 has'.\n- G06-Design checklist :48: 'whose A13 no device in M0 has'.\n\nThe owner chose '13 mini only (Recommended)', which leaves the A13 floor to M8; that is a choice, not a lack of a phone. 'Whether the iPhone 11 still works was not asked' (instructions/relayed-2026-10-24.md; M0-DeviceA/README.md). Runbook 1.1 row D (M0-device-runbook.md:25), which 2.12 cites, still names the owner's iPhone 11, an A13 phone, as possible phone D for Session 3.\n\nSo whether an A13 phone is at hand is unknown. These clauses state a fact the owner did not give, and they decide step 22.5's 'if available' on that basis.\n\nReword each to the decision, for example: 'the owner left the A13 floor for M8 on 24 October 2026, so no A13 phone is measured in M0'.",
  "location": "Docs/Stage0/device-checklists/G02-Transfer.md:199; Docs/Stage0/M0-device-runbook.md:383; Docs/Stage0/device-checklists/G01-EPUB.md:65; Docs/Stage0/device-checklists/G06-Design.md:48"
 },
 {
  "id": "FID-DA-03",
  "severity": "minor",
  "title": "0.8's latest drop-in path check does not name the commit it checked",
  "detail": "Runbook 0.8 names the commit of the 24 October check (6cede84a). The assembly's note, dated 26 October 2026, says only 'ran that check again on the merged tree'. Its log (assembly/checks/dropin-paths.log) checked 5e455f70, and m0-sessions's head is now 8082bdb6. The task asked 0.8 to state the commit checked.\n\nRe-run here: 'git diff --stat 9cdb0a02 8082bdb6 -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1' prints nothing, so the result holds for the reviewed head. I read the drop-in, harness-checks.sh, env.sh, bootstrap.sh and Package.swift: the path list is complete, and the drop-in does not use check-dependency-lock.py or 12-dependency-lock.sh. I also re-ran the assembly's gate checks on 8082bdb6: exit 0, tree clean afterwards.",
  "location": "Docs/Stage0/M0-device-runbook.md:210"
 },
 {
  "id": "FID-DA-04",
  "severity": "minor",
  "title": "Several lines date work finished on 26 October to 24 October",
  "detail": "Four places put a 24 October date on work that ran to 26 October:\n- The Stage 0 README is headed 'Where M0 stands (24 October 2026)' over a paragraph that reports the assembly of 26 October. This is the kind of date-to-content mismatch FID4-04 had these records correct in the ADR index.\n- 'an agent brought the owner's instructions up to date that day' (Stage 0 README:5), 'The same day an agent brought your instructions up to date' (M0-gate.md:128), the runbook's 'on 24 October 2026 to record your decision' (M0-device-runbook.md:12), and the Section 6.3 heading 'Recorded on 24 October 2026' over items 104-110. Item 108 cites a log run on 26 October, and the instructions README says the work was 'Finished on 26 October 2026'.\n- In the ADR index's 0013 row, 'decided on 22 October 2026' follows the 13 mini clause, so it reads as dating the 13 mini choice (made on 24 October).",
  "location": "Docs/Stage0/README.md:5; Docs/Stage0/M0-gate.md:128, Section 6.3 heading before item 104; Docs/Stage0/M0-device-runbook.md:12; Docs/ADRs/README.md:29"
 },
 {
  "id": "FID-DA-05",
  "severity": "minor",
  "title": "ADR-0001 says the narrower exception does not apply to any G0.6 step on A, but the runbook makes step 12 on A speed-dependent",
  "detail": "ADR-0001's D-2 bullet (ADR-0001:57) and M0-DeviceA/README.md:63 both say the exception 'does not apply to G0.6's steps on device A, which depend on the screen'.\n\nThe assembly added G0.6 step 12 to the runbook's repeats on A (M0-device-runbook.md:952): whether a stall of more than 150 ms makes a press toggle twice 'depends on the phone's speed too, so on A it is the 13 mini's result'. ADR-0013 is one of the records D-2 (b) names. Its open item lists step 12 on device A for M3 (ADR-0013:290) with no such note, and its section 4 rules out only the type-role steps.\n\nAdd a line in ADR-0013 for step 12 on A, and narrow ADR-0001's wording to the M0 steps.",
  "location": "Docs/ADRs/0001-platform-baseline-and-toolchain.md:57; Docs/ADRs/0013-design-language.md:290; Docs/Stage0/M0-device-runbook.md:952"
 },
 {
  "id": "FID-DA-06",
  "severity": "minor",
  "title": "ADR-0001 and the ADR index still say Apple's release notes are unread",
  "detail": "On m0-sessions, ADR-0001 says:\n- Status: 'has not been checked against Apple's release notes';\n- the technical lead's open item (ADR-0001:116): 'no agent has read them';\n- the ADR index's 0001 row: 'still awaits a check of Apple's release notes'.\n\nMeanwhile runbook 0.2 and gate step 7 record that the orchestrating session read the pages on 24 October 2026, and that an agent read them again (instructions/checks/apple-pages.log, 2026-10-23T17:49:55Z). The task deliberately leaves this to the m0-exit-prep run, and 28.8.7 acknowledges the gap. Until that merge, though, the record that Session 10's technical-lead review reads contains a false statement.",
  "location": "Docs/ADRs/0001-platform-baseline-and-toolchain.md:3, :116; Docs/ADRs/README.md (0001 row)"
 },
 {
  "id": "FID-DA-07",
  "severity": "minor",
  "title": "'made m0-sessions from that commit (6cede84a)' names the wrong commit as its base",
  "detail": "Two places read as if m0-sessions was made from 6cede84a:\n- M0-gate.md:128: 'the orchestrating session corrected CLAUDE.md (5aec2518) and made m0-sessions from that commit (6cede84a)';\n- instructions/README.md:5: 'made the branch m0-sessions from that commit (6cede84a)'.\n\nm0-sessions was made from 5aec2518. 6cede84a is the second CLAUDE.md commit, made on it (git log; ADR-0002 Branches and gate item 104 state this correctly). Reword to 'made m0-sessions from that commit and committed 6cede84a on it'.",
  "location": "Docs/Stage0/M0-gate.md:128; Docs/Stage0/evidence/M0-DeviceA/instructions/README.md:5"
 }
]
```
