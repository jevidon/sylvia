# What was relayed to the fix of the review's fidelity findings (26 October 2026)

A record of what the orchestrating session's workflow relayed to this fix, kept as data: it is the review's only
committed record (the review's own logs are not committed). Relayed on 26 October 2026 on the build Mac's clock (25
October UTC). The workflow computed the task text; no request of the product owner's came with it, and nothing in it is
the owner's approval of anything.

- **The task**: fix one reviewer's findings, lens fidelity, round 1, on branch `m0-records-update`, reviewed at
  `832a3636`; other lenses' fixers run after this one, one at a time, on the same branch. "Fix every blocker and major
  properly, and the minors unless that changes scope; explain any you leave in not_fixed. Never change an owner's record
  to fix a finding. Re-run the checks your changes affect and save their logs under
  Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/. Commit, "git checkout --detach", and return the structured result."
- **The state it relayed** is the one relayed to `m0-records-update` itself, which that branch's README and integration
  log section 41 record: pull requests #4 to #6, H-1's exception and its limit; `m0-decisions` as the owner's session
  branch, with the owner's eight commits `8404f342` to `c72247a6` and Codex's `4be1a1a4` (`DeviceTests`), all to be kept
  exactly as committed; `m0-exit-prep` at `c3adae68` and `m0-sessions` at `1d5ac477`, the two agent branches this branch
  brings onto that line; the branch model to describe everywhere (`m0-decisions` the owner's session branch, agent work on
  a branch of its own made from it and merged between sittings, `m0-sessions` retired, nothing to `main` before the M0
  exit unless the owner decides otherwise); run 1 as it now stands; phone B on iOS 27.0.1 (24A446), as the owner's setup
  record gives it; step 0.8's check; Apple's pages on Xcode 27.1 (27A9275), read by the orchestrating session on 24
  October 2026; and the owner's decision of 24 October 2026 on device A, with what it means for each record.
- **The rules of the run**: a worktree of its own; no push, fetch or pull request; no write to, and no branch checked out
  in, `~/Git/sylvia`, `~/Git/sylvia-m0` or `~/Git/sylvia-sessions`; never commit to, reset or check out `m0-decisions`;
  `m0-exit-prep` and `m0-sessions` read and merged, never committed to; no file read outside the worktree but the
  fixture cache, Xcode, the simulator device types, Xcode's caches and the system temporary folder; no physical device;
  the Mac's audio and global git configuration untouched; G0.5 recovery's class-B guard never bypassed; `Scripts/lib/env.sh`
  sourced in every shell, Xcode 27.1 (27A9275); `CLAUDE.md`'s evidence-honesty rules; nothing here a device result, a role
  sign-off, an ADR approval (decision D-6) or the M0 exit; temporary files under `.build/scratch`.

## The findings, verbatim

Eleven, one blocker, two major and eight minor, as relayed (the reviewer's text, unchanged; line numbers are those of
`832a3636`, checked by [`commands/finding-lines.py`](commands/finding-lines.py)):

```json
[
 {
  "id": "FID-RU-01",
  "severity": "blocker",
  "title": "Runbook 0.7 tells the owner to commit the Mac identity probe's log on the retired m0-sessions",
  "location": "Docs/Stage0/M0-device-runbook.md:210",
  "detail": "At 832a3636, Session 0.7's Record says: \"commit the regenerated log on `m0-sessions` (0.3, step 6; until 24 October 2026 this said `m0-decisions`)\". The owner's branch had it right: c72247a6 line 207 says \"commit the regenerated log on `m0-decisions` (0.3, step 6)\". The m0-sessions branch changed it (1d5ac477 line 209). The merge 4c0fa815 took that change, and d1fb3dd4 never reverted it, even though d1fb3dd4 reverted the same pattern in 0.8 (line 221: \"committed on `m0-decisions` ... from 24 to 26 October 2026 this said `m0-sessions`\") and in Section 6 (line 1011). Step 0.7 is still to run: the owner's setup record (evidence/M0-runbook/2026-10-26-setup.txt) says \"The Keychain test itself has NOT run; this is not a pass for step 0.7.\" So a fast-forward merge of this branch would replace the owner's correct instruction with one that sends a session record to the retired branch, and the history clause presents the m0-sessions wording as the current one. m0-sessions's own record lists 0.7 among the texts it switched (M0-gate.md:774, item 131: \"the runbook's header, Section 2, 0.7, 0.8 and Section 6 ... now name `m0-sessions`\"). This branch's item 178 (M0-gate.md:839) lists the runbook parts it switched back and leaves out 0.7. The README's claim (item 2, \"The branch model, restated everywhere the records give it\") is therefore untrue, and no check of this branch reads branch texts (the device-A runbook content check pins none). Fix: restore `m0-decisions` here with a dated history clause. Add a check that fails on any live text naming m0-sessions as a branch to build from, commit to or merge into."
 },
 {
  "id": "FID-RU-02",
  "severity": "major",
  "title": "Gate summary 5.4 still has the owner commit session records on, and build from, m0-sessions",
  "location": "Docs/Stage0/M0-gate.md:466",
  "detail": "The 5.4 bullet on H-1 ends: \"The same holds for the records and evidence of your sessions, committed on `m0-sessions` (Section 1, item 1, step 6). Not needed for the exit: until you say so, build from `m0-sessions`.\" The owner's version (c72247a6 line 459) said \"which you commit on `m0-decisions` ... until you say so, build from `m0-decisions`\". m0-sessions changed it (its item 131, M0-gate.md:774, lists Section 5.4). This branch added a new 5.4 bullet, \"The branch the sessions use: `m0-decisions` ... settled on 26 October 2026\" (line 482), and item 178 (line 839) says Section 5.4 was changed to give the model. But it left this sentence. 5.4 now names both branches as the one to build from, and it contradicts Section 1, item 1, steps 1 and 6 (lines 16 and 21), which its own cross-reference cites. It needs the same restoration and dated history clause as FID-RU-01."
 },
 {
  "id": "FID-RU-03",
  "severity": "major",
  "title": "CLAUDE.md, as this branch brings it to m0-decisions, forbids building on the owner's session branch",
  "location": "CLAUDE.md:5",
  "detail": "The workflow asked for 6cede84a's paragraph to be rewritten for the restated model. The branch left it, citing the rule that no agent changes CLAUDE.md on a workflow's request (M0-gate.md items 46 and 185; README, \"Left for the owner\"). It gave the replacement text in evidence/M0-RecordsUpdate/claude-md-paragraph.md. Declining the edit is correct under that rule and is disclosed. The account of the commits is exact: 5aec2518 and 6cede84a are the orchestrating session's, made at the owner's request of 24 October 2026, as their commit messages record. But the merge resolution still makes CLAUDE.md part of what this branch changes on m0-decisions. c72247a6 holds the old paragraph. A fast-forward to 832a3636 replaces it with text that says \"Since 24 October 2026 the M0 work is on `m0-sessions` ... the product owner builds the device sessions from it\" and \"Further M0 work goes on a branch of its own made from `m0-sessions`\". It also says \"Never build on `m0-integrate` or `m0-decisions`: both are behind `main`\". That is the opposite of the model every other record now gives, and every Claude agent the owner asks to work from m0-decisions, or merge into it, would read it. The README's merge procedure applies the fix only \"After the merge\". Fix, before this reaches m0-decisions: either the owner applies the paragraph, or explicitly asks for it to be applied, in the same sitting as the merge and before any agent request; or the merge is resolved so that this branch leaves m0-decisions's CLAUDE.md unchanged."
 },
 {
  "id": "FID-RU-04",
  "severity": "minor",
  "title": "24 October notes that state the m0-sessions model have no 26 October follow-up",
  "location": "Docs/Stage0/M0-gate.md:122, 471, 556",
  "detail": "Line 122 (a Section 1 history bullet) says \"the M0 work continues on `m0-sessions`, made from `main` that day\". Line 471 (5.4, the technical-lead item) says \"ADR-0001 records the same evidence on `m0-exit-prep`, merged into `m0-sessions` once reviewed\". Line 556 (6.3, item 1) says \"the sessions build from `m0-sessions`\". None has a later note saying the model was dropped. The equivalent note in Docs/Stage0/README.md:41 did get a 26 October follow-up."
 },
 {
  "id": "FID-RU-05",
  "severity": "minor",
  "title": "The ADRs give the device-A record's review status inconsistently",
  "location": "Docs/ADRs/0003-persistence.md:3; 0005:3; 0007:3; 0009:3; 0010:3; 0013:3; Docs/ADRs/README.md:29",
  "detail": "ADR-0003, 0005, 0007, 0009 and 0010 say the record of 24 October 2026 was read at 8082bdb6 \"and no review has accepted it\". ADR-0013 and the index's ADR-0013 row say the fix of the fidelity findings \"has not been reviewed\". Other records give the relayed outcome that the second review, at c2fd9ece, accepted the device-A records in its fidelity, accuracy and completeness lenses: the State line (M0-gate.md:4), item 183, ADR-0001:3, the index's ADR-0001 row, M0-plan-amendments.md:5 and Docs/Stage0/README.md:5. The ADRs above should get the same dated note."
 },
 {
  "id": "FID-RU-06",
  "severity": "minor",
  "title": "Integration log 41.1 says 4be1a1a4 changed the G0.5 recovery report",
  "location": "Docs/Stage0/integration-log.md:2385",
  "detail": "The row says \"`4be1a1a4` also changed the runbook's device commands for the recovery suite, the G0.5 recovery checklist and report\". `git show --stat 4be1a1a4` lists only the runbook, the G0.5 recovery checklist and the four DeviceTests files. The owner's report changes are 38f9604e and d5336111."
 },
 {
  "id": "FID-RU-07",
  "severity": "minor",
  "title": "Superseded R4 notes are left reading as current",
  "location": "Docs/Stage0/M0-gate.md:855; Docs/ADRs/0002-repository-build-and-ci.md:41",
  "detail": "In Section 7, item 1, the current note \"(closed: the change of 24 October 2026, accepted by an agent review at `c3adae68` ...)\" is followed by the older \"(answered by an agent's change on 24 October 2026, review pending, so a review that accepts it is still to come ...)\". In ADR-0002's Branches bullet, the 24 October note (\"review pending\") has no follow-up in that bullet. The open item (line 83) and ADR-0014 do say the routes are closed, so the records agree overall. Neither text calls R4-01 or R4-02 signed off."
 },
 {
  "id": "FID-RU-08",
  "severity": "minor",
  "title": "The summary states that G0.4 step 1 is still running",
  "location": "Docs/Stage0/M0-gate.md:10",
  "detail": "The opening says \"G0.4 step 1 still running\". The owner's evidence/G04-Audio/device/step-01-status.txt records only that the run was in progress when written (\"Full suite not complete. No result claimed.\"). The runbook and the reports say \"had not finished when last recorded\", which is the supported form."
 },
 {
  "id": "FID-RU-09",
  "severity": "minor",
  "title": "Four results are counted over three runbook steps",
  "location": "Docs/Sylvia_v1_iOS_Implementation_Plan.md:5; Docs/Stage0/M0-gate.md:851",
  "detail": "Both texts say \"Session 1's steps 1.1 to 1.3, two of which passed on the device and two failed\". The four results are checklist steps (G0.2 step 1 and G0.5 AI step 4 passed; G0.5 AI step 1 and the recovery suite failed), not runbook steps 1.1 to 1.3. Name them as the gate summary's opening does."
 },
 {
  "id": "FID-RU-10",
  "severity": "minor",
  "title": "The G0.6 checklist step 1 can be read as phone B's OS history",
  "location": "Docs/Stage0/device-checklists/G06-Design.md:15",
  "detail": "\"(iOS 27.0.1 (24A446) since 26 October 2026; 26.7 until then: the devices below)\" can be read as saying phone B ran 26.7 until 26 October. The owner's setup record gives only the build on 26 October, and the other records say when the phone was updated is not recorded. Word it as the checklist's own earlier text."
 },
 {
  "id": "FID-RU-11",
  "severity": "minor",
  "title": "The amendments name an older checker as the latest",
  "location": "Docs/Stage0/M0-plan-amendments.md:529",
  "detail": "Applied as names evidence/M0-DeviceA/fix-1/accuracy/commands/check-amendments.py as \"the latest\". This branch made evidence/M0-RecordsUpdate/commands/check-amendments.py, which passes. The accuracy version now fails its check 10k by design (README; checks/check-amendments-accuracy.log)."
 }
]
```
