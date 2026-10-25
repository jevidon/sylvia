# What was relayed to the fix of the review's accuracy findings (26 October 2026)

A record of what the orchestrating session's workflow relayed to this fix, kept as data: with the first fix's
`../relayed-findings.md`, it is the review's only committed record (the review's own logs are not committed). Relayed on
26 October 2026 on the build Mac's clock (25 October UTC).

- **The product owner's request**, as the workflow relayed it: "keep going".
- **The task**: fix one reviewer's findings, lens accuracy, round 1, on branch `m0-sessions`, "reviewed at
  d6315ad3f3a69f28258bfa54581c6ab6c005dcc8"; other lenses' fixers run after this one, one at a time, on the same branch;
  set up on `m0-sessions`, continuing from any work after `d6315ad3`. "Fix every blocker and major properly, and the
  minors unless that changes scope; explain any you leave in not_fixed. Re-run the checks your changes affect and save
  their logs under Docs/Stage0/evidence/M0-DeviceA/fix-1/." With it came the state of 24 October 2026 and the device-A
  change that the update had to describe, as the update's instructions part recorded them
  (`../../instructions/relayed-2026-10-24.md`), and the rules of the run: no push, fetch or pull request; no write to,
  and no branch checked out in, `~/Git/sylvia`, `~/Git/sylvia-m0` or `~/Git/sylvia-sessions`; `m0-exit-prep` and its
  `m0-exit-*` branches not touched; no physical device; the class-B guard of G0.5 recovery's drop-in never bypassed;
  nothing here a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit.
- **The commit the findings cite.** The task names `d6315ad3`, the first fix's last commit, as the commit reviewed; the
  findings' line numbers and quoted texts are those of `8082bdb6`, the commit the first fix's findings cite (for example,
  `M0-gate.md:714` is item 115 at `8082bdb6` and item 114 at `d6315ad3`, and `M0-device-runbook.md:6` reads "Nothing in
  this runbook has been run on a device" at `8082bdb6` only): [`commands/finding-lines.py`](commands/finding-lines.py)
  checks them at `8082bdb6`.

## The findings, verbatim

Six, one blocker, one major and four minor, as relayed (the reviewer's text, unchanged):

```json
[
 {
  "id": "ACC-01",
  "severity": "blocker",
  "title": "The owner's instructions describe a branch state that the assembly's own logs show is false: m0-decisions 'behind main', the sessions checkout to be switched 'from main at 96bdc7e9', nothing run on a device",
  "detail": "At 8082bdb6, `git rev-list --left-right --count main...m0-decisions` gives `1 8`. m0-decisions (c72247a6) has 8 commits that main lacks (8404f342..c72247a6, 26 Oct 2026 06:12-06:33 NZDT), so it is not behind main. Its session log rows 3a-3d record sittings on phone B from 2026-10-25 17:12 UTC: Session 1.1 passed-device, and 1.2 'blocked before tests: Xcode requires a host app for SylviaRecoveryTests', then run hosted. It also adds Spikes/G05-Recovery/DeviceTests (38f9604e 'Record the recovery suite device-host blocker', 4be1a1a4 'Host the recovery suite in an iOS test app'). None of this is on m0-sessions.\n\nThe assembly recorded all of it. assembly/checks/branch-state.log (2026-10-25T17:46:45Z) shows ~/Git/sylvia-sessions on refs/heads/m0-decisions at c72247a6 and 'm0-decisions behind main (an ancestor of it): no'. Its gate-checks.log part 1i prints 'm0-decisions: c72247a6...; behind main: NO', and the run still exits 0.\n\nThe owner-facing texts still say otherwise:\n- Runbook 0.3 step 1: 'Never build from m0-integrate or m0-decisions, both behind main'; the orchestrating session 'switches this checkout to it, from main at 96bdc7e9'. The step covers only 'if it still reads main ... run git checkout m0-sessions there yourself', not a checkout on m0-decisions.\n- Gate summary Section 1, item 1, step 1: the same text.\n- The setup lines of the G0.4, G0.5 AI and G0.5 recovery checklists: 'm0-integrate and m0-decisions are behind main'.\n- Runbook header: 'Nothing in this runbook has been run on a device' (line 6) and 'the sessions now build from m0-sessions' (line 8).\n- Gate summary State line: 'no device result is recorded yet'.\n\nOnly M0-gate.md:714 (item 115, deep in the Section 6.3 history list) and integration-log.md:1682 (28.8.6) say these instructions 'do not describe that checkout as it now is'.\n\nAt the next sitting, an owner who follows 0.3 step 1 finds m0-decisions checked out and is told it is stale and must never be built from. Switching to m0-sessions would take out of the build the recorded sittings and the DeviceTests host that G0.5 recovery step 1 on a phone needed. The session log there would also say no sitting ran.\n\nFix: reconcile m0-decisions into m0-sessions first, as item 115 says. Then state the real branch relationship, and give 0.3 step 1 and run 1 step 1 a case for a checkout on m0-decisions, or move item 115's warning to those steps. Make the gate check fail when it prints 'behind main: NO' while the text says the opposite.",
  "location": "Docs/Stage0/M0-device-runbook.md:163 (also :6, :8); Docs/Stage0/M0-gate.md:16 (also :4, :714); Docs/Stage0/device-checklists/G04-Audio.md:11; Docs/Stage0/device-checklists/G05-AI.md:7; Docs/Stage0/device-checklists/G05-Recovery.md:11; evidence: Docs/Stage0/evidence/M0-DeviceA/assembly/checks/branch-state.log:5-8,19 and gate-checks.log:103"
 },
 {
  "id": "ACC-02",
  "severity": "major",
  "title": "Unsupported claims that no A13 phone is at hand in M0 contradict the runbook's phone D and the relayed fact that the iPhone 11's state was not asked",
  "detail": "The owner's choice and the relayed record say two things: the A13 floor is not measured on a device in M0, and whether the iPhone 11 still works was not asked. See relayed-2026-10-24.md, and gate summary Section 4.3's D-1 row, 'your iPhone 11, whose state was not asked'. The runbook still offers the iPhone 11 as phone D for Session 3 (1.1 row D: 'your iPhone 11 will do if it can place a call'; row A: 'it can be phone D'). The decision also allows a result on it, 'recorded under its own model'.\n\nThe records nevertheless state as fact:\n- G02-Transfer.md:199, in step 22.5, which itself says 'Repeat once on the oldest supported iPhone if available': 'no A13 phone is at hand in M0'.\n- G01-EPUB.md:65 and M0-device-runbook.md:383: 'the A13 of the oldest supported iPhones, which no device in/of M0 has'.\n- G06-Design.md:48: 'whose A13 no device in M0 has'.\n- G05-AI.md:40: 'the phone on hand besides the iPhone 17 Pro is device A'.\n\nNo one checked any of this. The note on 22.5 also rules out a repeat that the step asks for 'if available'.\n\nFix: reword each to what was decided, for example 'no A13 iPhone is measured in M0 (the owner's decision of 24 October 2026); a result taken on the iPhone 11, if it is used, is recorded under its own model'.",
  "location": "Docs/Stage0/device-checklists/G02-Transfer.md:199; Docs/Stage0/device-checklists/G01-EPUB.md:65; Docs/Stage0/M0-device-runbook.md:383 (cf. :23, :25); Docs/Stage0/device-checklists/G06-Design.md:48; Docs/Stage0/device-checklists/G05-AI.md:40"
 },
 {
  "id": "ACC-03",
  "severity": "minor",
  "title": "ADR-0001 and the evidence README say the narrower exception does not apply to any of G0.6's steps on device A; the assembly found G0.6 step 12 on A speed-dependent",
  "detail": "ADR-0001 (D-2 bullet) and the M0-DeviceA README (D-2 bullet) read: 'ADR-0013 (it does not apply to G0.6's steps on device A, which depend on the screen)'. ADR-0013's open item lists steps 1-3, 5-9, 12 and 16-19 on device A in M3 with no note.\n\nThe runbook's Session 8 repeats paragraph (added at the assembly) and the README's own chip bullet say the opposite for step 12. That step's stated limit is 'if the device stalls for more than 150 ms between a touch lift and the Button's action ... that press can toggle twice'. It depends on the phone's speed, so on A it is the 13 mini's result.\n\nADR-0013 section 4 is correct for the type-role steps (4, 15, 26, 27); only the general claim and the M3 item are wrong. No M0 outcome changes. ADR-0013's M3 item should carry the exception for step 12, and ADR-0001 and the README should limit 'does not apply' to the M0 steps on A.",
  "location": "Docs/ADRs/0001-platform-baseline-and-toolchain.md:57; Docs/Stage0/evidence/M0-DeviceA/README.md:63 (vs :62); Docs/ADRs/0013-design-language.md:290; Docs/Stage0/M0-device-runbook.md:952"
 },
 {
  "id": "ACC-04",
  "severity": "minor",
  "title": "The lists of figures on A that are the 13 mini's own name only G0.3 steps 14-16, but the G0.3 checklist also times steps 6 and 20 on A",
  "detail": "The README's chip bullet ('G0.3's repeats (steps 14-16)'), the runbook's Session 8 repeats paragraph, G0.3 Setup 1 and ADR-0010's note give only steps 14-16 (memory, memory limit and times). All of them say the list was taken from the checklists' own text.\n\nThe G0.3 checklist, repeated on A in M2 (steps 6-32), also records:\n- step 6: 'the time from \"Received by Sylvia\" to the harness's scan line with accepted=1' (report F11);\n- step 20: 'the elapsed time' of copying in and importing the 4.6 GB bundle, which depends on the CPU and storage;\n- steps 9, 18 and 32: provider and download times.\n\nThe general rule ('a result taken on A is the 13 mini's') still covers these steps, so no outcome changes, but the explicit lists are incomplete.",
  "location": "Docs/Stage0/device-checklists/G03-Intake.md:7 (steps at :21, :48); Docs/Stage0/evidence/M0-DeviceA/README.md:62; Docs/Stage0/M0-device-runbook.md:952; Docs/ADRs/0010-intake-handoff-and-wired-bundles.md:139"
 },
 {
  "id": "ACC-05",
  "severity": "minor",
  "title": "Runbook Section 7 says the G0.4 checklist now asks for steps 1, 3, 15 and 17 on device A; it does not list 17",
  "detail": "The runbook's Section 7 G0.4 row lists '1, 3, 15 and 17 on A' as able to wait. Its reason now reads 'the checklist asked for them \"when one is available\", and since 24 October 2026 asks for them on device A'.\n\nThe G0.4 checklist's device line asks for steps 1, 3, 8-13 and 15 on device A, as it did at 6cede84a. Step 17 is not among them. The mismatch predates this update; the new clause repeats it as a fact about the checklist.",
  "location": "Docs/Stage0/M0-device-runbook.md:1127; Docs/Stage0/device-checklists/G04-Audio.md:5"
 },
 {
  "id": "ACC-06",
  "severity": "minor",
  "title": "The ADR index (re-dated 24 October 2026) and plan D01's row still say the Xcode 27.1 release-notes check is awaited",
  "detail": "The ADR index's status column now reads 'Status (24 October 2026)'. Its ADR-0001 cell still says 'whether 27A9275 is the non-beta release still awaits a check of Apple's release notes', with no note. Plan D01's row, also changed in this update, ends 'Pending: the technical lead's sign-off, with the check of Apple's release notes for Xcode 27.1 (ADR-0001)'.\n\nOn the same branch, runbook 0.2 and gate summary item 1 step 7 record that Apple's pages were read on 24 October 2026. I verified this today: 'Xcode 27.1 (27A9275)', October 15, 2026, no beta or RC label; the beta 27A9269 dated September 18, 2026; the 'Xcode 27.1 Release Notes', not beta notes. Those two records also say only the technical lead's one-line confirmation remains. The gate summary's row 82 and D01 row carry dated notes saying so; the index and plan D01 do not.\n\nLeaving ADR-0001's own text to m0-exit-prep is by design. The index and plan cells this update dated and changed should carry the same dated note.",
  "location": "Docs/ADRs/README.md:17; Docs/Sylvia_v1_iOS_Implementation_Plan.md:1159 (cf. Docs/Stage0/M0-device-runbook.md:159; Docs/Stage0/M0-gate.md Section 1 item 1 step 7)"
 }
]
```
