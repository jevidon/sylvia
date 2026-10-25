# What was relayed to the fix of the review's owner-readability findings (26 October 2026)

A record of what the orchestrating session's workflow relayed to this fix, kept as data: with the first fix's
`../relayed-findings.md`, the second fix's `../accuracy/relayed-findings.md` and the third fix's
`../completeness/relayed-findings.md`, it is the review's only committed record (the review's own logs are not
committed). Relayed on 26 October 2026 on the build Mac's clock (25 October UTC).

- **The product owner's request**, as the workflow relayed it: "keep going".
- **The task**: fix one reviewer's findings, lens owner, round 1, on branch `m0-sessions`, "reviewed at
  caf75a8447597efa5076b53b9a0d36be0fdcc901"; other lenses' fixers run after this one, one at a time, on the same branch;
  set up on `m0-sessions`, continuing from any work after `caf75a84`. "Fix every blocker and major properly, and the
  minors unless that changes scope; explain any you leave in not_fixed. Re-run the checks your changes affect and save
  their logs under Docs/Stage0/evidence/M0-DeviceA/fix-1/." With it came the state of 24 October 2026 and the device-A
  change that the update had to describe, as the update's instructions part recorded them
  (`../../instructions/relayed-2026-10-24.md`), and the rules of the run: no push, fetch or pull request; no write to,
  and no branch checked out in, `~/Git/sylvia`, `~/Git/sylvia-m0` or `~/Git/sylvia-sessions`; `m0-exit-prep` and its
  `m0-exit-*` branches not touched; no physical device; the class-B guard of G0.5 recovery's drop-in never bypassed;
  Apple's own pages may be read to check a fact, and are quoted exactly; nothing here a device result, a role sign-off,
  an ADR approval (decision D-6) or the M0 exit.
- **The commit the findings cite.** The task names `caf75a84`, the third fix's last commit, as the commit reviewed; the
  findings' line numbers and quoted texts are those of `8082bdb6`, the commit the first three fixes' findings cite (for
  example, `M0-device-runbook.md:6` reads "Nothing in this runbook has been run on a device." at `8082bdb6` only, and
  item 115, which OWN-DA-01 cites at line 714 of the gate summary, is at that line there): [`commands/finding-lines.py`](commands/finding-lines.py)
  checks them at `8082bdb6`. Several of them the first three fixes had already answered, wholly or in part, before this
  fix began (`README.md`, The findings, and what was done).

## The findings, verbatim

Nine, one blocker, four major and four minor, as relayed (the reviewer's text, unchanged):

```json
[
 {
  "id": "OWN-DA-01",
  "severity": "blocker",
  "title": "Run 1 and 0.3 switch ~/Git/sylvia-sessions to m0-sessions on review, but the checkout is on m0-decisions with the owner's device runs, and the instructions leave that out",
  "detail": "What the owner reads. Runbook 0.3 step 1 (line 163) and gate item 1 step 1 (line 16) say the orchestrating session switches the checkout to m0-sessions \"from `main` at `96bdc7e9`, once this update is reviewed, between your sittings\". The runbook's fallback only covers \"if it still reads `main`\" (\"ask for it, or run `git checkout m0-sessions` there yourself\"). Both say \"Never build from `m0-integrate` or `m0-decisions`, both behind `main`\". The setup lines of the Session 1 checklists say the same (device-checklists/G04-Audio.md:11, G05-Recovery.md:11, G05-AI.md:7), and so does CLAUDE.md line 5, which is not this update's file. The runbook header (line 8), gate line 128 (m0-sessions \"the branch the sessions build from, which holds your session records\") and README.md:49 (\"since then ... the device sessions use the branch `m0-sessions`\") all say the sessions build from m0-sessions.\n\nWhat is actually the case. The assembly's own read-only log, Docs/Stage0/evidence/M0-DeviceA/assembly/checks/branch-state.log (2026-10-25T17:46:45Z), shows:\n- /Users/jevidon/Git/sylvia-sessions on refs/heads/m0-decisions at c72247a6;\n- \"m0-decisions behind main (an ancestor of it): no\";\n- 8 commits after 044ed3cf, from 06:12 NZDT on 26 October 2026, running from \"Record the first physical iPhone Keychain test result\" to \"Record setup checks and the audio device run in progress\". They add Spikes/G05-Recovery/DeviceTests and change the session log, the runbook, the G0.5 recovery checklist and three reports.\n\nI re-checked this read-only at review time:\n- `git rev-parse m0-decisions` = c72247a6;\n- `git rev-list --count main..m0-decisions` = 8 and `m0-decisions..main` = 1 (only the merge 96bdc7e9);\n- `git ls-tree m0-decisions Spikes/G05-Recovery/` lists DeviceTests, which m0-sessions lacks.\n\nThe owner's records on m0-decisions (unreviewed, cited only for what they say):\n- `git show m0-decisions:Docs/Stage0/evidence/M0-runbook/sessions.md` has rows 3a-3d: Session 1.1 built from 96bdc7e9, then 1.2 and 1.3;\n- `.../M0-runbook/2026-10-26-setup.txt` gives phone B as \"iOS 27.0.1 (24A446)\". Runbook 1.1 row B, 1.3, 8.8's condition (\"earlier ... than phone B's 26.7\") and ADR-0001's Test devices all give 26.7 (23H24).\n\nWhere this is recorded. Only gate Section 6.3 item 115 (line 714), the assembly README (\"Seen at the assembly\") and integration log 28.8 record it, with the precondition \"The orchestrating session reconciles the two branches with you before the checkout moves\". Neither 0.3 nor gate item 1 carries that precondition, and item 1 does not mention it.\n\nEffect. Two paths lead to a switch: the switch on review that 0.3 describes, or the owner's own `git checkout m0-sessions` per the fallback. Either moves the build off the commits that hold the owner's Session 0/1 records, and off the DeviceTests host their 1.2 run now uses. Agents told to start from m0-sessions see none of those records, and the instructions describe Sessions 0 and 1 as not started.\n\nFix.\n1. Reconcile m0-decisions's commits after 044ed3cf with m0-sessions. Both branches changed four files: the runbook, the G0.5 recovery checklist, and the G0.2 and G0.5 recovery reports.\n2. Bring these texts to the reconciled state: run 1, 0.3, the header, Section 2, the checklists' setup lines, 1.1 row B and gate item 1.\n3. Make the switch wait on the reconciliation, not on this review.",
  "location": "Docs/Stage0/M0-device-runbook.md:163; Docs/Stage0/M0-gate.md:16, 128, 714; Docs/Stage0/M0-device-runbook.md:8; Docs/Stage0/device-checklists/G04-Audio.md:11, G05-Recovery.md:11, G05-AI.md:7; README.md:49; Docs/Stage0/evidence/M0-DeviceA/assembly/checks/branch-state.log"
 },
 {
  "id": "OWN-DA-02",
  "severity": "major",
  "title": "Owner-facing records say no device step has run, which the update's own item 115 contradicts",
  "detail": "These lines state that nothing has run:\n- runbook line 6: \"Nothing in this runbook has been run on a device.\"\n- gate line 10: \"None of the gates' device or human steps has run\"\n- gate line 718: \"not one device or human step has run\"\n- gate line 128: \"Nothing ran on a device\" (its note of 26 October is silent on this)\n- the m0-sessions session log, line 7: \"No device step has been run.\"\n\nGate item 115 itself says the m0-decisions commits' \"messages record device runs\". On m0-decisions, Docs/Stage0/evidence/G02-Transfer/device/01-keychain-class.md reads \"G0.2 step 1 — passed-device ... Run: 2026-10-25 17:12 UTC ... iPhone 17 Pro (iPhone18,1), iOS 27.0.1 (24A446)\". Its log ends \"✔ Test run with 3 tests in 1 suite passed\" and \"** TEST SUCCEEDED **\". I read these with `git show m0-decisions:...`.\n\nNot taking those unreviewed results into these records is right (CLAUDE.md, Evidence honesty). Stating that nothing ran is not. The records should say that device runs were recorded on m0-decisions from 25 October 2026 UTC, are unreviewed, and are not yet in these records (Section 6.3, item 115).",
  "location": "Docs/Stage0/M0-device-runbook.md:6; Docs/Stage0/M0-gate.md:10, 128, 718; Docs/Stage0/evidence/M0-runbook/sessions.md:7"
 },
 {
  "id": "OWN-DA-03",
  "severity": "major",
  "title": "Sessions 1.2, 6.3 (step-4 probe) and 8.10 give a device command that the owner's own run found cannot run on a phone",
  "detail": "Where the command appears:\n- runbook 1.2, Debug and Release (lines 257, 267);\n- runbook 6.3 (line 795);\n- runbook 8.10 (line 950), which reuses \"the commands of 1.2 with A's DEVICE_ID\";\n- the G0.5 recovery checklist, which wins over the runbook (device-checklists/G05-Recovery.md lines 27, 49, 106, 118).\n\nAll of them run `xcodebuild test -scheme G05Recovery-Package` against a device. Runbook 1.5 (line 76) still says \"Whether `xcodebuild test` signs it for the phone is only known when Session 1 runs it.\"\n\nThat is now known:\n- `git show m0-decisions:Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log` is the owner's run of 2026-10-25 17:14 UTC on phone B. It stops with \"Cannot test target “SylviaRecoveryTests” on ...: Tool-hosted testing is unavailable on device destinations. Select a host application for the test target, or use a simulator destination instead.\" before any test ran.\n- step-1-2-results.txt there reads \"BLOCKED, no device tests executed\" with \"xcodebuild exit: 70\", and records the same error on a retry at 38f9604e.\n- m0-decisions then added an app host, Spikes/G05-Recovery/DeviceTests (4be1a1a4), and changed these commands. That fix is unreviewed.\n\nThese steps block M0: G0.5 recovery steps 1-2 on phone B and on the 13 mini, D17, and ADR-0003's latency, SQLite and pragma items. From m0-sessions the owner would hit the same error in Session 1, and again in Session 8 on device A. The assembly listed the commit \"Record the recovery suite device-host blocker\" in branch-state.log and left the commands as they were.\n\nFix, with the reconciliation of OWN-DA-01: put a reviewed device host in the checklist and in 1.2, 6.3 and 8.10, and have 1.5 say what Session 1 found.",
  "location": "Docs/Stage0/M0-device-runbook.md:257, 267, 795, 950, 76; Docs/Stage0/device-checklists/G05-Recovery.md:27, 49, 106, 118"
 },
 {
  "id": "OWN-DA-04",
  "severity": "major",
  "title": "Run 1 step 7's one-line Xcode confirmation has no usable place to be recorded on m0-sessions, and ADR-0001 there still says the notes were not read",
  "detail": "Where the step is described: gate item 1 step 7 (line 22: \"one line, which is recorded in ADR-0001 as your check\"), runbook 0.2 (line 159), D-3's note (line 1026) and the technical-lead paragraph (line 1037). None of them says where the owner writes the line or who puts it into ADR-0001.\n\nWhat ADR-0001 on m0-sessions still says:\n- Status (line 3): \"That 27A9275 is the non-beta release has not been checked against Apple's release notes\".\n- Open item (line 116): asks the technical lead to \"read Apple's release notes ... and record here whether 27A9275 is the release build ... with the page and the date read\", and says \"no agent has read them\".\n\nThat contradicts 0.2, step 7 and Docs/Stage0/evidence/M0-DeviceA/instructions/checks/apple-pages.log (read 2026-10-23T17:49:55Z).\n\nThe conflict with the records' own rule. Runbook 0.3 step 5 (line 167) and gate item 1 step 5 (line 20) tell the owner to leave records that a running agent changes to that agent until its branch is merged. m0-exit-prep changes ADR-0001; the assembly README says \"Its merge will conflict on ADR-0001's Status line\". So:\n- an owner who writes the line into ADR-0001 on m0-sessions breaks that rule and adds to the conflict;\n- an owner who opens ADR-0001 to write it finds the old instruction to read the notes themselves.\n\nFix: say where the line goes now, for example the session log's run-1 row or a message to the orchestrating session, and that ADR-0001 receives it with or after the m0-exit-prep merge.",
  "location": "Docs/Stage0/M0-gate.md:22; Docs/Stage0/M0-device-runbook.md:159, 1026, 1037; Docs/ADRs/0001-platform-baseline-and-toolchain.md:3, 116"
 },
 {
  "id": "OWN-DA-05",
  "severity": "major",
  "title": "The session log on m0-sessions, which the owner fills in, still describes run 1 for m0-decisions and row 8 for the iPhone 11 Pro",
  "detail": "What the log still says:\n- line 40, row 1: \"(1) `m0-decisions` checked out; (2) `CLAUDE.md`'s milestone paragraph corrected on `m0-decisions` ...; (3) only if you build from `main`: `m0-decisions` merged into it ...; (5) ... (base `m0-decisions` ...); (6) ... committed on `m0-decisions` ...; (7) Apple's release notes for Xcode 27.1 read as technical lead and recorded in ADR-0001\";\n- line 49, row 8: \"8 Device A, your iPhone 11 Pro (after Session 4)\".\n\nRunbook Section 2 (line 105) has the owner add each sitting's row to this file.\n\nWhy it was left. The assembly did not apply the instructions part's text, treating the log as history (assembly README, first table). But the task's history rule covers records of past runs and checks. This log's unfilled rows are instructions, and the log's own notes (lines 7-34) record agent edits of rows 1, 8 and 12 in earlier rounds.\n\nWhere the owner would learn of it. The replacement text is only in the assembly README and gate Section 6.3 items 109 and 112. Gate Section 1 (\"What is left for you\") lists neither it nor the CLAUDE.md toolchain line, which is also \"asked again of\" the owner.\n\nFix. m0-decisions has also changed this file (its opening line and rows 3a-3d), so make the change with the reconciliation of OWN-DA-01, and list any edit left to the owner in Section 1.",
  "location": "Docs/Stage0/evidence/M0-runbook/sessions.md:40, 49; Docs/Stage0/M0-gate.md:705, 711; Docs/Stage0/M0-device-runbook.md:105"
 },
 {
  "id": "OWN-DA-06",
  "severity": "minor",
  "title": "Pull request #6's merge, and the second reading of Apple's pages, are dated against the records' own UTC convention",
  "detail": "`git log -1 --format=%ad --date=iso 96bdc7e9` gives 2026-10-24 04:34:37 +1300, which is 23 October 2026, 15:34 UTC.\n\nThe gate summary's own convention (line 5) dates an event by UTC, with the build Mac's date beside it. ADR-0002 follows it: \"on 23 October 2026 at 15:34 UTC (24 October, 04:34, on the build Mac's clock)\". These give \"24 October 2026\" alone:\n- the runbook (lines 8, 163, 165);\n- the gate summary (lines 10, 18, 128, 460, 737);\n- README.md:49 and the Stage 0 README.\n\nLikewise, runbook 0.2 (line 159) and gate step 7 (line 22) say the instructions agent read Apple's pages \"the same day\" as the orchestrating session (24 October). apple-pages.log gives 2026-10-23T17:49:55Z, which is 24 October on the build Mac. No outcome changes.",
  "location": "Docs/Stage0/M0-gate.md:5, 10, 18, 22, 128, 460, 737; Docs/Stage0/M0-device-runbook.md:8, 159, 163, 165; README.md:49"
 },
 {
  "id": "OWN-DA-07",
  "severity": "minor",
  "title": "Runbook 1.1 row A says iOS 27 support of the 13 mini was not checked; Apple's guide lists it",
  "detail": "Runbook 1.1 row A (line 23) says \"whether iOS 27 supports the iPhone 13 mini was not checked\".\n\nApple's iPhone User Guide page \"iPhone models compatible with iOS 27\" (https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-27-iphe3fa5df43/27/ios/27) lists it. This review fetched the page with curl on 25 October 2026 UTC and extracted its text under .build/scratch. It reads: \"iOS 27, which is compatible with the following models: iPhone 11 iPhone 11 Pro iPhone 11 Pro Max iPhone 12 mini iPhone 12 iPhone 12 Pro iPhone 12 Pro Max iPhone 13 mini iPhone 13 ...\".\n\nSo an out-of-date 13 mini may well be offered iOS 27, which is the case the row allows. The row's first cell, \"on the iOS 26.x it has\" (kept from the 11 Pro's row), contradicts that case. No outcome changes.",
  "location": "Docs/Stage0/M0-device-runbook.md:23"
 },
 {
  "id": "OWN-DA-08",
  "severity": "minor",
  "title": "Merging agent work into m0-sessions once it is checked out in ~/Git/sylvia-sessions: an agent cannot do it from its own worktree",
  "detail": "0.3 step 5 (runbook line 167) has agent work merged with \"`git checkout m0-sessions`, then `git merge <its branch>`, by you or by an agent you ask\".\n\nAfter the switch, m0-sessions is checked out in ~/Git/sylvia-sessions. Git lets a branch be checked out in only one worktree, so an agent in a worktree of its own cannot check it out there. The assembly could merge in its own worktree only because m0-sessions was checked out nowhere at the time; `git branch` shows no \"+\" beside it.\n\nSaying that the merge is made in ~/Git/sylvia-sessions itself, between sittings, would make the step work as written for an agent too.",
  "location": "Docs/Stage0/M0-device-runbook.md:167; Docs/Stage0/M0-gate.md:20"
 },
 {
  "id": "OWN-DA-09",
  "severity": "minor",
  "title": "The gate's D01 row calls device A \"the baseline\" unqualified, the wording the update corrected in the plan",
  "detail": "Gate Section 3, D01 (line 303) reads: \"(24 October 2026: you decided D-1 again: device A, the baseline, is your iPhone 13 mini ...; its owners change plan 19.1 and ADR-0001 with it ...)\".\n\nTwo problems:\n- \"The baseline\", unqualified, is the wording the records part corrected in the plan's D01 row on 26 October 2026: \"the baseline device\" became \"the baseline for small-screen layout on a device\" (evidence/M0-DeviceA/README.md, \"Two attempts\"; plan Appendix D's item of 24 October 2026).\n- \"Change\" reads as still to do, while this update has already made those changes.\n\nSuggested wording: \"device A, the small-screen baseline\", in the past tense.",
  "location": "Docs/Stage0/M0-gate.md:303"
 }
]
```
