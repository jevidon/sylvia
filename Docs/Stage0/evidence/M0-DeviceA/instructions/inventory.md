# Inventory: the owner's instructions that the state of 24 October 2026 put out of date

What was read, and what was done with each text, in the files this update owns: the device runbook
(`Docs/Stage0/M0-device-runbook.md`), the gate summary (`Docs/Stage0/M0-gate.md`), the Stage 0 README
(`Docs/Stage0/README.md`) and the eight device checklists (`Docs/Stage0/device-checklists/`). Line numbers are those of
`6cede84a`, the head of `m0-sessions`, where the update starts (branch `m0-sessions-instructions`).

**What was looked for** (the task's list): every live mention of device A, of the iPhone 11 Pro, of iPhone12,3, of the
iPhone 11 as a second A13 phone, of the A13 tied to device A, and of "the oldest supported iPhone" where it means device
A; every live instruction to the owner that names `m0-decisions` (or `m0-integrate`) as the branch to check out, build
from, commit to or start agents from; and every live instruction that gives a step of run 1 as still to do which the
state of 24 October 2026 says is done or changed (`relayed-2026-10-24.md`). The search used the terms `11 Pro`,
`iPhone12,`, `iPhone 11`, `A13`, `oldest supported iPhone`, `oldest iPhone`, `baseline`, `m0-decisions`, `m0-integrate`
and `release notes`, then each hit was read in its paragraph. Amendment tags that read like chips (A13, A14, A15 in the
gate summary's Sections 1, 2 and 3 are amendments M0-A13, M0-A14 and M0-A15) and typography ("the baseline side of the
text") are not device texts and are left out below.

**Dispositions.** *Changed*: rewritten to the state of 24 October 2026, with a dated note ("until 24 October 2026 ...")
saying what it said, in each document's style. *Note added*: the text is a record that stays as written, and a dated
note after it says what changed. *Stays*: a record of what happened (a history note, a decision's record as taken, a
correction's text, a review's finding), or a text that is still true (a generic "device A", "on A"), left as it is.
`recheck-instructions.py` (in `commands/`) checks the changed texts, and its sweep lists, with a reason, each line that
still names the iPhone 11 Pro or `m0-decisions` without a mark of this update.

**The second attempt (26 October 2026)** read the first attempt's work against this list and swept the same files
again for the same terms, reading each hit on a line that carries no mark of this update ("24 October 2026", "13
mini", "m0-sessions"): each is a record, a quoted name, a question as it was asked or a correction's text, as below.
The dispositions it changed or added are marked *(26 October 2026)*; what each changed is in `README.md`, "Finished on
26 October 2026".

## The device runbook

| Line | What it says (at `6cede84a`) | Disposition |
| --- | --- | --- |
| 6 | Header: 0.8 runs again only if what the drop-in builds changes after `9cdb0a02` | Changed: adds the check of 24 October 2026 (nothing changed at `6cede84a`), pointing to 0.8 |
| 7 | Header: "Device A, the oldest supported iPhone, is your iPhone 11 Pro (D-1 (b))"; "agent work goes into `m0-decisions`" | Changed: device A was the 11 Pro until 24 October 2026; pull request #6 made the covered merge, nothing else reaches `main` before the exit; dated note. A new bullet after it gives the decision of 24 October 2026 and the branch `m0-sessions` |
| 11 | Who wrote it | Changed: names this update and that it has not been reviewed (the anchors of the earlier rechecks kept) |
| 13 | Contents: "Sessions 8-9 (oldest supported iPhone, iPad)" | Changed: device A, the small-screen baseline |
| 22 | 1.1, row A: the iPhone 11 Pro (iPhone12,3 expected; A13), plan 19.1's sentence on it quoted, the iPhone 11 a second A13 phone, the check of iOS 26 before Session 0 | Changed: the iPhone 13 mini (iPhone14,4 expected; A15; 375 × 812 pt), its screen (same points, about 8% smaller) and its chip (the 13 mini's figures, never the A13's; M8 measures the A13 floor), the iPhone 11 not device A, Lightning and no Action button, the iOS 26 check for the 13 mini; dated note with the old text's substance |
| 24 | Row D: "your iPhone 11 will do if it can place a call" | Stays: the iPhone 11 stays what the runbook says for phone D |
| 27, 29 | "With phone B and device A ..."; OS versions ("device A if Software Update offers only iOS 27") | Stay: generic device A, true of the 13 mini |
| 33 | 1.2: "Lightning for device A, the iPhone 11 Pro" | Changed: the iPhone 13 mini, Lightning (unchanged) |
| 57, 76, 82 | 1.4's storage row A; 1.5's registration and timings | Stay: generic device A |
| 104 | Section 2: commit the records on `m0-decisions`; "every agent starts from `m0-decisions`" | Changed: `m0-sessions`, by the owner or an agent the owner asks; dated note |
| 123 | Section 3, run 1: step 2 (correct `CLAUDE.md` on `m0-decisions`) still to do | Changed: steps 2 and 3 done, step 1 checks `~/Git/sylvia-sessions`, step 5 in an agent's run (pending), step 7 one line; 162 words (at most 200, the OWN5-05 limit); points to the gate summary's Section 6.3, item 104 |
| 124 | Run 2: 0.8 only if what the drop-in builds changed after `9cdb0a02` | Changed: adds the check of 24 October 2026 at `6cede84a` |
| 130 | Run 8: "Device A, your iPhone 11 Pro"; "G0.6's criterion on the oldest iPhone" | Changed: the iPhone 13 mini, its Lightning cable, the criterion on device A (the 11 Pro's points), its speed and memory figures the 13 mini's; dated note |
| 134 | Run 12: the technical lead's check of the release notes comes first, in run 1 | Changed: since 24 October 2026 a one-line confirmation |
| 154 | Session 0's order | Changed: only 0.3's steps 1 and 4 left before the first sitting; 0.8 needed nothing on 24 October 2026 |
| 158 | 0.2: at the root of "the checkout 0.3 made"; the release notes not mentioned | Changed: `~/Git/sylvia-sessions`; Apple's evidence that 27A9275 is the release build (read on 24 October 2026; `checks/apple-pages.log`); the owner's confirmation still to be recorded |
| 160-171 | 0.3 steps 1-8: `git checkout m0-decisions`; correct `CLAUDE.md` on `m0-decisions`; merge `m0-decisions` into `main` if building from `main`; agent work merged into `m0-decisions`; records committed on `m0-decisions` | Changed: step 1 `git branch --show-current` reads `m0-sessions` in `~/Git/sylvia-sessions`; steps 2 and 3 done; step 4 `m0-sessions`'s head; step 5 the agent run on `m0-exit-prep` (pending), agent work merged into `m0-sessions`; step 6 records committed on `m0-sessions` by the owner or an agent asked; step 7 adds which merged changes need no repeat (*(26 October 2026)*: the checklists' lines rewritten when the session log recorded no sitting of the owner's, not "before any session ran"); history line points to item 104 |
| 173 | 0.4: "device A, your iPhone 11 Pro" | Changed: the iPhone 13 mini by its Lightning cable, iPhone14,4 expected; dated note |
| 207 | 0.7: commit the log on `m0-decisions` | Changed: `m0-sessions`; dated note |
| 209 | 0.8: run again only if what the drop-in builds changes after `9cdb0a02` | Changed: the check of 24 October 2026 (the paths read from the drop-in, `6cede84a`, no change, the command after a merge, the two files of `m0-exit-prep` not used); `checks/dropin-paths.log` |
| 218 | 0.8: the folder committed on `m0-decisions` | Changed: `m0-sessions`; dated note |
| 382 | 2.12: the repeat "on the oldest supported iPhone, device A, your iPhone 11 Pro, the phone the 20 s budget must hold on" | Changed: on device A, the 13 mini, whose times do not show the budget on an A13; dated note |
| 425 | 2.20: phone B "a newer device than the baseline" | Stays: true of device A and of the A13 floor |
| 646 | 4.18: "The checklist's repeat on the oldest supported iPhone can wait" | Changed: if one is available; on device A it times the 13 mini |
| 913, 915 | Section 5 and Session 8 headings: the oldest supported iPhone, the iPhone 11 Pro | Changed: device A, the small-screen baseline, the iPhone 13 mini (time unchanged) |
| 917 | Session 8's opening: the iPhone 11 Pro, iPhone12,3 expected; budgets harder on its A13 | Changed: the 13 mini, iPhone14,4 expected, Lightning; which steps depend on the screen and which on the chip; a pass does not show a budget on an A13; dated note |
| 921 | 8.1: "Type roles on the oldest supported iPhone" | Changed: on device A, the criterion checked on the 11 Pro's points, the SE (2nd generation) a simulator check; dated note |
| 922-929 | 8.2-8.5: A's screen, 375 × 812 pt | Stay: true of the 13 mini |
| 931 | 8.6: the redraw "on the baseline device" | Changed (record): the result is the 13 mini's, not an A13 phone's |
| 933 | 8.7: the report's row and ADR-0009's item on "the oldest supported iPhone" | Changed (record): the figures are the 13 mini's; the quoted names of the report's row and ADR-0009's item kept as their own |
| 945 | 8.8 | Stays: generic A |
| 947 | 8.9: "A has no Action button" | Changed: like the 11 Pro; the steps record what iOS does |
| 949 | 8.10: ADR-0003 asks it "on the baseline" | Changed (record): step 1 does not depend on the chip, step 2's latencies are the 13 mini's |
| 951, 955, 961 | Repeats: intro; G0.3 "on the oldest iPhone in M2"; G0.2 22 "if available" | Changed: the timed repeats give the 13 mini's figures (*(26 October 2026)* with G0.3's memory limit and times, steps 14-16, and G0.4 3's battery figures); Setup 1 repeats on device A; on A it times the 13 mini |
| 966 | Session 9: "15 and 27 are the oldest iPhone's by their own text" | Changed: device A's; dated note |
| 995 | Section 6: ask for R4-01 and R4-02 at run 1, base and merge `m0-decisions` | Changed: asked; the agent run on `m0-exit-prep`, merged into `m0-sessions` once reviewed; pending; dated note |
| 997, 1005 | `linkage.sh`: you run it; the checkout 0.3 made; commit and merge on `m0-decisions` | Changed: the agent run makes it (pending); the checkout 0.3 checks; `m0-sessions`; dated note |
| 1016 | The decisions, taken on 22 October 2026 | Changed: adds the decision of 24 October 2026 |
| 1018-1021 | D-1's question, options and recommendation | Stay: the question as asked on 22 October 2026 |
| 1022 | D-1 decided on 22 October 2026: the iPhone 11 Pro, the iPhone 11 a second A13 phone | Stays (record), with the addendum after it: decided again on 24 October 2026, the owner's words and choice quoted from `relayed-2026-10-24.md`; *(26 October 2026)* note added at its end, in the convention of its note of 23 October 2026: device A is no longer the 11 Pro, the bullet kept as decided |
| 1023 | D-2 decided (a): "You have device A, your iPhone 11 Pro" | Note added: (a) stands, with a narrower form of (b)'s exception for the results that depend on the chip |
| 1024 | D-3: the release notes still to be read by the technical lead | Note added: read on 24 October 2026; the owner's confirmation left |
| 1029 | D-8: "Your first push of `m0-integrate` ..."; "`m0-decisions` adds no Git LFS file" | Stays: D-8's record and its note of 22 October 2026 |
| 1035, 1039 | The technical lead: read the release notes first; the ADR-0001 review row | Changed: the one-line confirmation; dated note |
| 1062 | QA's device matrix row | Changed: adds the A13 floor that M8 measures |
| 1067 | The iOS lead: the redraw on the baseline device | Changed: on the 13 mini, which says nothing of an A13 phone |
| 1077 | 23.1 table: D01 "with Apple's release notes" | Stays: the confirmation is that check |
| 1111 | The exit review: ask for the final-review records at run 1 | Note added: asked; pending |
| 1121-1127 | Section 7's rows for G0.1, G0.2, G0.3, G0.4 and G0.5 recovery, naming the baseline or the oldest iPhone in their reasons | Stay, with one dated note after the table: the steps on A stay; their chip-dependent results are the 13 mini's. G0.4's row changed: the checklist asked for its repeats "when one is available", and asks for them on device A since |
| 1128 | Section 7, G0.6: type roles "on the oldest supported iPhone"; "15 and 27 are the oldest iPhone's" | Changed: on device A, as plan 21.1 asks them of the oldest supported iPhone, A's points the 11 Pro's; device A's |
| 1139 | Section 8, 22 October 2026: the texts applied name the iPhone 11 Pro | Note added: the texts applied in the checklists now name device A, the 13 mini |
| 1149-1253 | Corrections C4, C6, C28, C29, C30, C48, C50, C51, C52, C56, with their notes of 22 October 2026 | Stay: the corrections' texts as written and their records |
| 1283 | Section 9, the content check's versions | Note added: the new version of 24 October 2026 and its log |

## The gate summary

| Line | What it says (at `6cede84a`) | Disposition |
| --- | --- | --- |
| 4 | State: the decisions of 22 October and answers of 23 October 2026 are the only things decided | Changed: adds the decision of 24 October 2026 and this update among the unreviewed work; 198 words (at most 200) |
| 10 | Recommendation (the opening): the answers of 23 October 2026; R4-01, R4-02, `linkage.sh`, the final reviews as remaining | Changed: pull request #6, `m0-sessions`, D-1 decided again; the three in an agent's run; 592 words (at most 600; 790 with the State line, at most 800) |
| 14 | Item 1's opening | Changed: steps 2 and 3 done, 5 in progress, 7 one line; the old texts in Section 6.3, item 104 |
| 16 | Step 1: "Check out `m0-decisions`" | Changed: check that `~/Git/sylvia-sessions` is on `m0-sessions` |
| 17 | Step 2: correct `CLAUDE.md` on `m0-decisions` | Changed: done (`5aec2518`, `6cede84a`) |
| 18 | Step 3: merge `m0-decisions` into `main` only if building from `main` | Changed: done (pull request #6, `96bdc7e9`) |
| 19 | Step 4: record the commit | Changed: `m0-sessions`'s head |
| 20 | Step 5: ask for the two requests, base and merge `m0-decisions` | Changed: asked and in progress on `m0-exit-prep`, merged into `m0-sessions` once reviewed, pending; agent work and the ordering rule on `m0-sessions` |
| 21 | Step 6: commit the records on `m0-decisions` | Changed: committed on `m0-sessions`, by the owner or an agent asked |
| 22 | Step 7: read Apple's release notes | Changed: a one-line confirmation, with Apple's evidence and `checks/apple-pages.log` |
| 23 | Step 8: "your iPhone 11 Pro (device A)" | Changed: the iPhone 13 mini, iPhone14,4 expected, Lightning |
| 28 | `linkage.sh` at any time you choose | Changed: the agent run of step 5 makes it, pending |
| 30 | Item 2: when 0.8 is repeated; the checklists changed | Changed: the check of 24 October 2026, the files of `m0-exit-prep` not used; the checklists' device-A and branch lines changed again (*(26 October 2026)*: when the session log recorded no sitting of the owner's; it said "before any session ran", which no record shows) |
| 40 | Item 2, run 8: iPhone 11 Pro, "on the oldest supported iPhone" | Changed: iPhone 13 mini, device A (the 11 Pro's points), its speed and memory figures the 13 mini's |
| 52 | Item 3, technical lead: the release notes come first | Changed: as a one-line confirmation |
| 64 | Item 4, R4-01 and R4-02: ask, base and merge `m0-decisions` | Changed: asked, `m0-exit-prep`, merged into `m0-sessions`; dated note |
| 65 | Item 4, the final-review records: at run 1 | Note added: asked, pending |
| 66 | Item 4, merges: otherwise build from `m0-decisions` | Changed: from `m0-sessions`; note on pull request #6 |
| 69 | Item 4, `linkage.sh`, yours or an agent's you allow | Note added: the agent run makes it, pending |
| 74 | The drop-in run: commit the folder on `m0-decisions` | Changed: the check of 24 October 2026; `m0-sessions`; dated note |
| 86 | Your choices: D-1 (b), the iPhone 11 Pro | Note added (the choice of 22 October 2026 stays as recorded) |
| 109 | PO-35: awaits a check of the release notes | Note added |
| 118, 122 | The M0 work on `main`; pull request #5 | Notes added: pull request #6 made the merge; the work continues on `m0-sessions` |
| 124-127 | What happened, 22 and 23 October 2026 | Stay; a bullet for 24 October 2026 added after them |
| 225 | Row 62: "on your iPhone 11 Pro (decision D-1 (b))" | Changed: device A, the 13 mini (status unchanged) |
| 247 | Row 74: "the oldest iPhone is your iPhone 11 Pro" | Changed: the steps on the oldest iPhone run on device A, the 13 mini (status unchanged) |
| 260 | Row 82: ADR-0001 records the 11 Pro | Note added: D-1 decided again, which ADR-0001's owner records; the release notes read (status unchanged) |
| 234, 291 | Row 66 and Section 2.10's bullet on Xcode 27.1: the technical lead's confirmation, with the release notes, pending | Stay: they summarize ADR-0001 as it stands on this branch, and the confirmation is still pending; *(26 October 2026)* note added to each: Apple's pages read on 24 October 2026, the confirmation the owner's, one line |
| 270, 292 | Row 92; Section 2.10's bullet on the lock harness | Stay: records |
| 302 | Section 3, D01: the oldest supported iPhone is the iPhone 11 Pro; the release notes | Note added |
| 370 | 4.1, PO-35: the release notes still to be read | Note added |
| 404 | 4.3, D-1: decided (b), the iPhone 11 Pro | Changed: decided again on 24 October 2026, with what it means (cell kept, the addition marked) |
| 405 | 4.3, D-2: (a), you have device A | Note added: (a) stands, the narrower exception |
| 406 | 4.3, D-3: the release notes still to be checked | Note added |
| 410, 451 | D-7; pushing and LFS | Stay: records |
| 419 | 5.1: the content check's versions | Note added: the new version and its log |
| 421 | 5.1: "A the oldest supported iPhone, your iPhone 11 Pro" | Changed |
| 442 | 5.2: the release notes, the technical lead's check | Note added |
| 456 | 5.4: the request names `m0-decisions`; `linkage.sh` yours | Changed: asked, `m0-exit-prep`, `m0-sessions`; the agent run makes `linkage.sh`; dated note |
| 459 | 5.4: agent work on `main`; commit on `m0-decisions`; build from `m0-decisions` | Changed: `m0-sessions`; dated note |
| 464 | 5.4: the release notes, "which no agent has checked" | Note added: read on 24 October 2026; the confirmation left |
| 468 | 5.4: done on 22 October 2026 by the owners | Stays: record |
| 534 | 6.3, item 1: the merge of `m0-decisions` that item 1 asks for | Note added: made by pull request #6 |
| 535-666 | 6.3, items 2-103 | Stay: records of earlier rounds and findings |
| 703 | 7, item 1: built from `m0-decisions` or `main`; your iPhone 11 Pro; records on `m0-decisions` | Changed; dated note |
| 704 | 7, item 2: the release notes come before Session 0 | Note added: a one-line confirmation |
| 707 | 7, item 5: `CLAUDE.md` out of date, change it on `m0-decisions` | Changed: corrected on 24 October 2026; the two commits join the recommended review; dated note |
| 718 | 8, Branch | Changed: pull request #6, `m0-sessions`, this branch |
| 720-730 | 8, the rounds of 22 and 23 October 2026 | Stay; a bullet for this update added; Written by notes it unreviewed |

New in Section 6.3: items 104-110 (the old texts of run 1 and the branch, device A, step 0.8, the release notes, the
checks, the requests to other owners, not reviewed).

## The Stage 0 README

| Line | What it says (at `6cede84a`) | Disposition |
| --- | --- | --- |
| 5 | Where M0 stands (23 October 2026): build from `m0-decisions` or `main`; agent work and records on `m0-decisions`; the iPhone 11 Pro (device A) | Changed (24 October 2026): pull request #6, `m0-sessions` in `~/Git/sylvia-sessions`, device A the iPhone 13 mini, the three requests in an agent's run; dated note |
| 28 | The integration log's sections | Stays: history |
| 39 | The gate summary's updates | Changed: adds 24 October 2026 |
| 41 | The M0 work on `main` | Note added: pull request #6; `m0-sessions` |

## The device checklists

| File, line | What it says (at `6cede84a`) | Disposition |
| --- | --- | --- |
| G01-EPUB 6 | Repeats on the oldest supported iPhone (the iPhone 11 Pro since 22 October 2026) | Changed: on device A, the small-screen baseline ("once they are available" kept, which runbook Section 7 quotes); dated note: the 13 mini, its times not an A13's, M8 |
| G01-EPUB 65 | Step 11: repeat on "the oldest supported iPhone, device A ... the phone the 20 s budget must hold on" | Changed: on device A; its nine times do not show the budget on an A13; dated note |
| G01-PDF 10 | Repeat steps 1 and 10 on the oldest supported iPhone | Changed: on device A; dated note: the 13 mini's results |
| G01-PDF 51 | Step 10's record: whether it is the oldest supported iPhone (the iPhone 11 Pro since 22 October 2026) | Changed: the oldest supported iPhone is an A13 phone; device A's result on the 13 mini does not stand in for it; dated note |
| G01-PDF 26 | "the baseline side of the text" | Stays: typography |
| G02-Transfer 8 | Step 11 on the oldest supported iPhone when available | Changed: on device A; dated note: the 13 mini's figures, M8 |
| G02-Transfer 107, 109, 112 | Step 11's title and item 1: the oldest supported iPhone; its record | Changed: device A; the record names the model and says the figures are the 13 mini's; dated note |
| G02-Transfer 199 | Step 22.5: repeat on the oldest supported iPhone "if available" | Note added: no A13 phone in M0; a repeat on the 13 mini times the 13 mini ("if available" kept, which the runbook quotes) |
| G03-Intake 7 | The oldest supported iPhone is the iPhone 11 Pro; steps 6-32 repeated on it in M2 | Changed: device A, the 13 mini; repeats on device A in M2; its memory figures not the A13's (*(26 October 2026)*: its memory limit and times, steps 14-16, too; "until then" after the new date now names 22 October 2026); dated note |
| G04-Audio 5 | Repeats on the oldest supported iPhone when one is available | Changed: on device A; dated note: the 13 mini (no Action button), steps 8-13 record iOS behaviour, step 1's timings the 13 mini's (*(26 October 2026)*: and step 3's battery figures) |
| G04-Audio 11 | Setup: `m0-decisions`, or `main` once it holds it | Changed: `m0-sessions` in `~/Git/sylvia-sessions`; dated note |
| G05-AI 7 | Setup: `m0-decisions`, or `main` once it holds it | Changed: as G0.4's |
| G05-AI 23 | Step 1.1: if the oldest supported iPhone has an earlier iOS 26.x | Changed: if device A has one; the dated note at line 40 says what it said |
| G05-AI 40 | Note of 22 October 2026: a run on the oldest supported iPhone, the iPhone 11 Pro, is a record | Note added: device A, the 13 mini, a record too |
| G05-Recovery 5 | Repeat steps 1-4 on device A, the oldest supported iPhone: the iPhone 11 Pro (iPhone12,3 expected; A13), the iPhone 11 a second A13 phone | Changed: device A, the 13 mini (iPhone14,4 expected; A15); step 1 chip-independent, step 2's latencies the 13 mini's; dated note |
| G05-Recovery 11 | Setup: check out `m0-decisions`, or `main` once it holds it | Changed: as G0.4's |
| G06-Design 3 | Note of 22 October 2026: the oldest supported iPhone is the iPhone 11 Pro | Note added: device A, the 13 mini, its steps cover what they covered on the 11 Pro |
| G06-Design 9 | "on the oldest iPhone, 15 with 25 and 26" | Changed: on device A; dated note |
| G06-Design 11 | Step 4 on the oldest supported iPhone; steps on the oldest iPhone in M3 | Changed: on device A, its points the 11 Pro's; dated note |
| G06-Design 36 | Step 15: on the oldest supported iPhone (the iPhone 11 Pro since 22 October 2026) | Changed: on device A, the 13 mini (points the 11 Pro's); the history kept in the parenthesis (*(26 October 2026)*: its "until then" after the new date now names 22 October 2026) |
| G06-Design 48 | Line A: "Oldest supported iPhone"; note of 22 October 2026: the iPhone 11 Pro (iPhone12,3 expected; A13) | Changed: titled Device A, the small-screen baseline; dated note: the 13 mini (iPhone14,4 expected; A15), not the oldest supported iPhone |
| G06-Design 63 | Step 27 "on device A" | Stays: generic device A |

## Outside this update's files

Each is asked of its owner in the update's result (shared changes requested), not changed here:

- `Docs/Stage0/evidence/M0-runbook/sessions.md`, the session log (no owner named in the task): row 1's run-1 checklist,
  which names `m0-decisions` in its items (1), (2), (3), (5) and (6), asks for the release notes in (7) and device A's iOS
  in (8); and row 8's title, "8 Device A, your iPhone 11 Pro (after Session 4)".
- `README.md` (the repository's): "the records of the product owner's M0 decisions ... are on the branch `m0-decisions`,
  which reaches main by pull request".
- The plan, `Docs/Stage0/M0-plan-amendments.md`, the ADRs, the gate reports and the integration log: the other
  workstream of the same update, on another branch.
