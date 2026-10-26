# Inventory of the records: device A (24 October 2026)

Every live mention, in the records this part of the update owns, of device A, the iPhone 11 Pro, its identifier iPhone12,3, the iPhone 11 as a second A13 phone, the A13 tied to device A, "the oldest supported iPhone" where it means device A, and every sentence whose truth depends on device A being an A13 phone; with each one's disposition. The records: the plan (`Docs/Sylvia_v1_iOS_Implementation_Plan.md`), the plan amendments (`Docs/Stage0/M0-plan-amendments.md`), the ADRs and their index (`Docs/ADRs/`), the eight gate reports (`Docs/Stage0/G0*.md`) and the integration log (`Docs/Stage0/integration-log.md`). The runbook, the checklists, the gate summary and the Stage 0 README are the other part of this update (`instructions/`).

How it was made: a search of those files at `6cede84a` (the head of `m0-sessions`, which this branch starts from) for "device A", "11 Pro", "iPhone12,", "iPhone 11" (not Pro), "A13" (not the amendment tag A13), "oldest supported", "oldest iPhone", "oldest device", "baseline device", "baseline iPhone", "baseline's" and "12-class", each hit then read in its sentence; and a reading of the plan's front matter, 1.1, 19.1, 21.1, 21.2, 21.4, 23.1 and 23.2 and Appendix D, of ADR-0001, ADR-0002 and the ADR index whole, and of the device items of ADR-0003, ADR-0005, ADR-0007, ADR-0009, ADR-0010 and ADR-0013, for sentences that depend on device A without naming it. Line numbers are those at `6cede84a`. The decision and the facts are in [`README.md`](README.md). When this part was resumed on 26 October 2026 (on the build Mac's clock; [`README.md`](README.md), "Two attempts"), the search was run again over the same files at `6cede84a` with those terms and "A14", "A15", "13 mini", "iPhone14," and "slowest": it found every line below and no other, except the amendment tag A13 at lines 35, 300, 322 and 490 of the plan amendments, now listed, and hits that are not about device A: "slowest" in passages on the slowest test, document, call or codec (ADR-0004, ADR-0006, ADR-0009, ADR-0010, ADR-0015, the G0.1 EPUB, G0.2, G0.3 and G0.4 reports and the integration log), and "iPhone14,6", the iPhone SE (3rd generation) simulator, in the G0.6 report's environment line.

Dispositions: **changed** (the text now states the decision of 24 October 2026, with its earlier wording kept as dated history where the records keep it); **note** (the text is kept, and a dated note after it records the change); **unchanged** (still true for the iPhone 13 mini, with the reason); **history** (a record of what an earlier round did or said, which stays as it is); **not device A** (a hit that is not about the phone).

## The plan

| Line | What it said | Disposition |
| --- | --- | --- |
| 5 | The Status line: draft 0.8 with the decisions of 22 and the answers of 23 October 2026 | changed: also records the decision of 24 October 2026 (D-1 taken again, the iPhone 13 mini; the A13 floor left for M8's release device matrix) within draft 0.8 |
| 7 | **Revised:** 23 October 2026, with the history of the drafts | changed: 26 October 2026, with an entry for 24 October (the decision recorded) and one for 26 October (the record completed, two of its wordings corrected) |
| 33 | 1.1: the decisions not as recommended, among them D-1 (Section 19.1), "where the text now says what the owner chose and what it replaced" | unchanged: still true, 19.1 now saying what the owner chose on 22 and on 24 October 2026 and what each replaced |
| 900 | 19.1: the baseline, the oldest supported iPhone, is an iPhone 11 Pro; the iPhone 11 a second A13 phone; every budget measured on them stricter to meet; the iPhone 11 Pro's 375 × 812 pt the layout floor on a device | changed: device A, the baseline for small-screen layout, is the iPhone 13 mini; its screen as the iPhone 11 Pro's, drawn about 8% smaller; its A15 two generations newer than the A13, its chip-dependent figures its own and a pass not shown to hold on an A13 phone; no budget changes; the A13 floor left for M8's release device matrix; the iPhone 11 not device A. The wording of 22 October 2026 kept in the section's dated history |
| 1041 | 21.1, G0.6's criterion: the type roles "on the oldest supported iPhone" | unchanged: the gate's own words, which the runbook quotes and its content check reads; 21.1's status paragraph now says that the check is made on device A, whose screen in points is the iPhone 11 Pro's |
| 1045 | 21.1's status paragraph: "on the baseline iPhone (device A, an iPhone 11 Pro; Section 19.1)"; the owner "has access to device A (22 October 2026)" | changed: device A an iPhone 13 mini since 24 October 2026, the iPhone 11 Pro until then; and a sentence on how G0.6's check of the type roles on the oldest supported iPhone is made |
| 1059 | 21.2's M8 row: Full matrix, accessibility, performance, ... | changed: adds the A13 floor, the Section 19.2 budgets on an A13 iPhone (the owner's iPhone 11 if it still works then, or one borrowed or bought if the owner wants one), left to M8 by the owner on 24 October 2026 |
| 1092 | 21.4's inputs to the re-estimate: "an older baseline iPhone (D-1)" | changed: device A, an older baseline iPhone until 24 October 2026, an iPhone 13 mini since, the A13 floor left for M8 |
| 1155 | 23.1's introduction: every decision as recommended except PO-13, PO-23, PO-33, PO-39 and D-1 (22 October 2026) | unchanged: the record of 22 October 2026; D01's row carries the decision of 24 October 2026 |
| 1159 | D01: "The oldest supported iPhone, the baseline device, is an iPhone 11 Pro (A13; Section 19.1)"; its approval with D-1 (b) | changed: device A an iPhone 13 mini (A15, 375 × 812 pt), the A13 left for M8; the approval of 22 October 2026 kept, with the decision of 24 October 2026 after it |
| 1161 | D03: G0.4 steps 8-10, 12 and 13 "on device A, which has no Action button" | unchanged: true of the iPhone 13 mini, which has a Ring/Silent switch and no Action button (Apple's specifications); the steps record no timing or memory figure |
| 1173 | D15: the design sign-off after G0.6 on phone B, device A and the iPad | unchanged: names device A, not its model |
| 1175 | D17: G0.5 recovery steps 1 and 2 on device A | unchanged: names device A; the save latency's narrower exception is in ADR-0003 and 19.1 |
| 1198 | The Literata risk row: G0.6 on the oldest supported iPhone, an iPhone 11 Pro (A13, 375 × 812 pt); "the oldest-device check" | changed: G0.6 on device A, the iPhone 13 mini, its 375 × 812 pt the iPhone 11 Pro's drawn about 8% smaller; "the device-A check". The risk's name, "fails on the oldest device", kept: it is the risk |
| 1208 | The device-evidence risk row: "the baseline's A13 makes the budgets stricter to meet"; "the baseline device is the iPhone 11 Pro" | changed: the baseline's A15 is two generations newer than the A13, so a budget met on it is not shown to hold there; the baseline device the iPhone 13 mini, its chip-dependent figures its own, the A13 floor left for M8 |
| 1458 | Appendix D, the draft 0.8 entry's review note: the correction "in the last item of this entry" | note: since 24 October 2026 the item before the last; the new last item not reviewed |
| 1462 | Appendix D, the D-1 item (22 October 2026): the iPhone 11 Pro and the iPhone 11, both A13; the budgets stricter on them | note: the decision of 24 October 2026, and a new last item of the entry that records it, what it changed and that it is not reviewed |
| 1490, 1566 | Appendix D, the draft 0.7 entry's note (D-1 not as recommended) and the draft 0.5 entry's A46 ("the baseline iPhone") | history |
| 1519, 1533 | "A13" in the draft 0.5 entry | not device A: the amendment tag A13 (the Tailscale route) |
| 1583 | Appendix D, the draft 0.3 entry's D01: the iPhone 12-class baseline, with a note of 22 October 2026 (device A an iPhone 11 Pro) | note: device A an iPhone 13 mini since 24 October 2026, the A13 floor left for M8 |

## The plan amendments

| Line | What it said | Disposition |
| --- | --- | --- |
| 4 | The header: D-1 (b) "makes your iPhone 11 Pro the oldest supported iPhone" | note: the decision of 24 October 2026 and where the plan and this document record it |
| 5 | The State line: the review history | changed: the record of 24 October 2026 is agent-written and not reviewed |
| 242 | Section 2.9, A46: the finding (the iPhone 12-class baseline unavailable, draft 0.5) and its notes of 22 and 23 October 2026 | note: the decision of 24 October 2026 in the row's dated notes; the finding's draft 0.5 wording is history |
| 293 | Section 3.2, ADR-0001's item (2): the oldest supported iPhone, the iPhone 11 Pro, every budget on its A13 stricter | changed, as ADR-0001's consequence 2 changed, with its earlier wordings as history; still one item, so the checker's count of ADR-0001's Consequences holds |
| 349 | PO-34: the repeats on "the baseline iPhone"; its note of 23 October 2026 ("the baseline iPhone, device A, and an iPad are at hand") | unchanged: names no model, and is true of the iPhone 13 mini |
| 370 | Section 5, iOS lead: the redraw "on the baseline device" | changed: device A, the iPhone 13 mini since 24 October 2026, and a redraw without a flash on its A15 shows none on an A13 phone |
| 374 | Section 5, serialized device run: the G0.6 review "on the baseline device, the iPhone 11 Pro" | changed: device A, the iPhone 13 mini since 24 October 2026, the iPhone 11 Pro until then |
| 383 | Section 6's introduction: D-1 (b) changes the baseline 19.1 states (A46) | note: since 24 October 2026 19.1's device A is the iPhone 13 mini |
| (new) | Section 7 | a row for the fact the decision changed, where the plan states it, and the check that reads it |
| 510 | Section 8: 19.1's baseline becomes the iPhone 11 Pro (22 October 2026) | note: the changes of 24 October 2026; the list of 22 October 2026 is history |
| 524, 526 | Section 9: the review history; the latest checker | note, and the new checker named |
| 10, 35, 107, 300, 322, 399, 433, 490 | "A13" | not device A: the amendment tag A13 (the Tailscale route), in the text and as `[M0-A13]` (until 26 October 2026, when this part was resumed and its search run again, this row listed 10, 107, 399 and 433 only) |

## The ADRs and their index

| Record, line | What it said | Disposition |
| --- | --- | --- |
| ADR-0001, 3 | Status: device A, the oldest supported iPhone, is the iPhone 11 Pro (A13) | changed: the iPhone 13 mini since 24 October 2026, the iPhone 11 Pro's period as history, the A13 floor left for M8; the record of 24 October 2026 not reviewed |
| ADR-0001, 4 and 5 | Date and Deciders | changed: the decision of 24 October 2026 added |
| ADR-0001, 45 | The decisions of 22 October 2026, D-1 (i): the iPhone 11 Pro, the iPhone 11 a second A13 phone, every budget stricter | note; and a new block, "The decision of 24 October 2026: D-1 taken again", with the owner's words, the facts, what device A covers and does not, the narrower exception and G0.6's criterion |
| ADR-0001, 47 | D-2 (a): "No exception is recorded here or in the other records D-2's option (b) named." | note: D-2 (a) stands, and the narrower exception is recorded here and in those records |
| ADR-0001, 53 | Test devices: device A, the oldest supported iPhone, is the iPhone 11 Pro; the iPhone 11 a second phone of the same chip | changed: device A the iPhone 13 mini (iPhone14,4 expected), not the oldest supported iPhone; the iPhone 11 Pro's period as history; the iPhone 11 not device A; no A13 iPhone a test device in M0. The iPad's sentences unchanged (two rechecks of earlier rounds read them) |
| ADR-0001, 77 | Evidence of 22 October 2026: device A's model the owner's statement | history; a new Evidence block for 24 October 2026 |
| ADR-0001, 82 | Consequences, bullet 2: the iPhone 11 Pro supported, every budget on its A13 stricter | changed, its earlier wordings as history; still bullet 2 of 5 |
| ADR-0001, 92 | Alternatives: an iPhone 12-class phone as device A, not chosen, the A13 stricter | note; and the two options of 24 October 2026 the owner did not choose |
| ADR-0001, 93 | Alternatives: the iPhone SE (2nd generation) as device A, not available | unchanged |
| ADR-0001, 100 | Open items: "an iPhone 12-class device and an iPad", with notes of 22 and 23 October 2026 | note (its first words kept: the device runbook's correction C51, not applied, quotes them and its text check reads them); and a new open item for M8, the A13 floor |
| ADR-0002 | Not about device A. Its Branches gave `m0-decisions` as the branch the sessions build from | changed for the state of 24 October 2026: pull request #6 merged `m0-decisions` (`96bdc7e9`); `m0-sessions` plays its part; nothing else reaches `main` before the exit unless the owner decides otherwise (a new bullet; notes on the bullet of `m0-decisions`, the Status, the Date and the third open item; the texts the earlier rounds' rechecks read kept) |
| ADR-0003, 3 and 104 | Status and the device-measurements item: device A, the oldest supported iPhone, the iPhone 11 Pro (A13) | changed: the iPhone 13 mini; the narrower exception: its save latency, the durability setting's cost, is its own, while the SQLite version, pragmas and protection classes depend on the iOS build and are covered |
| ADR-0003, 105 | D17's persistence owner after steps 1 and 2 on device A | unchanged: names device A |
| ADR-0005, 3 and 152 | Status and the iOS lead's item: the redraw on the baseline device, device A, the iPhone 11 Pro | changed: the iPhone 13 mini; the narrower exception: a redraw at once on its A15 shows none on an A13 phone. The text a recheck of the second fix reads kept |
| ADR-0007, 3, 38 and 74 | Status, the Action button row, the device-run item: device A the iPhone 11 Pro, the oldest supported iPhone, no Action button | changed (3, 38) and note (74): the iPhone 13 mini, which has a Ring/Silent switch and no Action button; the exception changes nothing but step 12's start-up race, the steps recording no timing or memory figure |
| ADR-0009, 3, 107, 141 and 172 | Status; the part commits on an old phone; the pending "memory on the oldest supported iPhone (device A: the iPhone 11 Pro ...)"; the open item on the part commit | changed or note: step 11 on the iPhone 13 mini, its memory, times, `commit_ms` and hangs its own, an A13 phone's waiting for M8; the item's words "memory on the oldest supported iPhone" kept (the runbook's 8.7 quotes them, and its content check reads them), and the item now says that the iPhone 13 mini is not the oldest supported iPhone |
| ADR-0010, 3, 139 and 140 | Status (the G0.3 repeats on the oldest supported iPhone); the item "Device runs in" (device A, the iPhone 11 Pro); C56's note | changed or note: device A, the iPhone 13 mini since 24 October 2026; its memory limit and peak its own. The item's first words kept (the runbook's content check reads them) |
| ADR-0013, 3, 136, 205, 260, 290 and 291 | Status, section 4 "On devices", section 9 item 5, Evidence, the open item on devices and its C50 note: the oldest supported iPhone, device A, the iPhone 11 Pro | changed or note: G0.6's steps for the oldest supported iPhone made on device A, the iPhone 13 mini, at the iPhone 11 Pro's 375 × 812 pt, drawn about 8% smaller; the narrower exception does not apply to them, which depend on the screen |
| ADR-0015, 301 | The security sign-off's inputs: on device A, 8.9, G0.4 steps 8-13, for B11 | unchanged: names device A; quick capture's outcome does not depend on the chip |
| ADR-0002, ADR-0008 | "device a" in "device and" | not device A |
| README.md (the index), 13, 17-19, 21, 23, 25, 26, 29 and its history | The departed decisions (D-1 (b): the iPhone 11 Pro); the status column dated 23 October 2026; rows 0001, 0002, 0003, 0005, 0007, 0009, 0010 and 0013 | changed: D-1 decided again, the narrower exception; the column dated 24 October 2026 (two rechecks of earlier rounds read the old date: [`README.md`](README.md), Checks); each row's device A, and row 0002's `m0-sessions`; the history paragraph |

## The gate reports

| Report, line | What it said | Disposition |
| --- | --- | --- |
| G01-EPUB.md, 116 | Open question 8: the baseline device and an iPad unavailable; notes of 22 and 23 October 2026 (the iPhone 11 Pro) | note: if the repeats run on device A in M3, their times and memory are the iPhone 13 mini's |
| G01-PDF.md, 124 | Open question 3: the redraw on the baseline device, the iPhone 11 Pro | note: the iPhone 13 mini; the narrower exception |
| G02-Transfer.md, 66 | Row "T38 on a device (Wi-Fi, oldest supported iPhone)": the oldest supported iPhone is the iPhone 11 Pro | changed: step 11 on device A, the iPhone 13 mini, its results its own under the narrower exception, an A13 phone's left for M8. The row's name kept: it is the criterion, which the runbook's 8.7 quotes and its content check reads |
| G02-Transfer.md, 173 | Open question 7: measure on the oldest supported iPhone, the iPhone 11 Pro | changed: step 11 on the iPhone 13 mini, its re-hash time its own |
| G03-Intake.md, 219 | Open item 5: the extension's memory limit on the oldest supported iPhone, the iPhone 11 Pro (M2) | changed: device A, the iPhone 13 mini, its limit and peak its own |
| G04-Audio.md | Row 19: checklist steps 8-13, no device named | unchanged |
| G05-AI.md | No mention of device A; row D1 (the minimum OS) unaffected | unchanged |
| G05-Recovery.md, 6, 50, 63 and 100 | The decisions paragraph, row 13 (save latency on device A, the iPhone 11 Pro, A13), row 26 (the lock harness on device A in M1), open question 6 | changed or note: the iPhone 13 mini; its save latency its own; row statuses unchanged |
| G05-Recovery.md, 95 | Open question 1: the save latency on phone B and on device A | unchanged: names device A |
| G06-Design.md, 27, 28 and 125 | Rows on the type roles, grayscale and Increase Contrast, and the device review "on the oldest supported iPhone", with notes of 22 and 23 October 2026 | note: the steps made on device A, the iPhone 13 mini. The words correction C51 (not applied) quotes kept: "Checklist steps 13, 14, 23, 24 and 27 on the oldest supported iPhone (no hardware yet), the iPhone 17 Pro and an iPad (no hardware yet)." and "oldest supported iPhone, iPhone 17 Pro, iPad". Statuses unchanged |
| G06-Design.md, 246 | Review round 3's gate gaps (the oldest supported iPhone) | history |

## The integration log

| Lines | What they say | Disposition |
| --- | --- | --- |
| 706, 829, 842-844, 872, 873, 883, 887, 908, 910, 922, 932, 989, 998, 1146, 1190, 1242, 1349 and 1350 | The records of earlier rounds (the decisions round, its fixes, the follow-up and its fixes) that named device A, the iPhone 11 Pro or the oldest supported iPhone as they then stood | history |
| 3 | The log's opening paragraph, which ends with section 15 | note: a sentence for section 28 |
| (new) | Section 28 | records both parts of this update, what was checked and what stays pending |

## Sentences that depended on device A being an A13 phone

Each is above; together: plan 19.1 (every budget stricter to meet on them), D01 (A13), the device-evidence risk row (the baseline's A13 makes the budgets stricter), Appendix D's D-1 item (on A13 phones the budgets are stricter: history, with a note); ADR-0001's D-1 (i) bullet (each budget stricter: history, with a note), its consequence 2 (changed) and its alternative (an A13 rather than an A14: history, with a note); the amendments' Section 3.2 item (2) (changed); ADR-0003's device item (A13: changed); ADR-0013's section 4 (A13: changed); the G0.5 recovery report's row 13 and open question 6 (A13: changed and note). After the change, no live sentence of these records says that a figure measured on device A is an A13 result, or that a budget met on device A holds on an A13 phone; the plan's checker for this update checks the plan's and the amendments' (`commands/check-amendments.py`, checks 10c and 10k).
