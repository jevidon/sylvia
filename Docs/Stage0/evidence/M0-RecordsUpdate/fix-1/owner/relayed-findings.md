# What was relayed to the fix of the review's owner-readability findings (27 October 2026)

A record of what the orchestrating session's workflow relayed to this fix, kept as data: with the earlier fixes'
[`../relayed-findings.md`](../relayed-findings.md) and [`../completeness/relayed-findings.md`](../completeness/relayed-findings.md),
it is the review's only committed record (the review's own logs are not committed). This fix began at about 12:20 UTC on
26 October 2026 (01:20 on 27 October on the build Mac's clock, the date this fix's commits and notes carry). The workflow
computed the task text; no request of the product owner's came with it, and nothing in it is the owner's approval of
anything.

- **The task**: fix one reviewer's findings, lens owner, round 1, on branch `m0-records-update`, "reviewed at
  7c87a82d5ade7a327e099df1eca8a243b5025404", the last commit of the fix of the same review's completeness findings; the
  findings' line numbers and quoted texts are those of `832a3636`, the commit the review read, as they say ("At
  832a3636 the line reads", "which I re-ran") and as [`commands/finding-lines.py`](commands/finding-lines.py) checks.
  Other lenses' fixers run after this one, one at a time, on the same branch. "Fix every blocker and major properly, and
  the minors unless that changes scope; explain any you leave in not_fixed. Never change an owner's record to fix a
  finding. Re-run the checks your changes affect and save their logs under
  Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/. Commit, "git checkout --detach", and return the structured result." The
  earlier fixes' logs are in that folder and in `../completeness/`; this fix's are in this one, beside them.
- **The state it relayed** is the one relayed to `m0-records-update` itself, which that branch's README and integration
  log section 41 record (pull requests #4 to #6, H-1's exception and its limit; `m0-decisions` as the owner's session
  branch, with the owner's eight commits `8404f342` to `c72247a6` and Codex's `4be1a1a4`, all to be kept exactly as
  committed; `m0-exit-prep` at `c3adae68` and `m0-sessions` at `1d5ac477`; the branch model to describe everywhere; run 1
  as it now stands; phone B on iOS 27.0.1 (24A446); step 0.8's check; Apple's pages on Xcode 27.1 (27A9275), read by the
  orchestrating session on 24 October 2026; and the owner's decision of 24 October 2026 on device A, with what it means
  for each record). It again asked for `CLAUDE.md`'s paragraph from `6cede84a` to be rewritten for the branch model, as
  it had asked `m0-records-update` and the two earlier fixes; no agent changes `CLAUDE.md` on a workflow's request (the
  gate summary's Section 6.3, item 46), so this fix did not, and the owner's step 2 stays, now with a command the owner
  runs (integration log 44.3).
- **The rules of the run**: a worktree of its own; no push, fetch or pull request; no write to, and no branch checked out
  in, `~/Git/sylvia`, `~/Git/sylvia-m0` or `~/Git/sylvia-sessions`; never commit to, reset or check out `m0-decisions`;
  `m0-exit-prep` and `m0-sessions` read, never committed to; no file read outside the worktree but the fixture cache,
  Xcode, the simulator device types, Xcode's caches and the system temporary folder; no physical device; the Mac's audio
  and global git configuration untouched; G0.5 recovery's class-B guard never bypassed; `Scripts/lib/env.sh` sourced in
  every shell, Xcode 27.1 (27A9275); `CLAUDE.md`'s evidence-honesty rules; nothing here a device result, a role
  sign-off, an ADR approval (decision D-6) or the M0 exit; temporary files under `.build/scratch`.

## The findings, verbatim

Eight, two blockers, three major and three minor, as relayed (the reviewer's text, unchanged; line numbers are those of
`832a3636`, checked by [`commands/finding-lines.py`](commands/finding-lines.py)):

```json
[
 {
  "id": "OWN-RU-01",
  "severity": "blocker",
  "title": "Runbook 0.7 still tells the owner to commit his Mac identity log on m0-sessions",
  "location": "Docs/Stage0/M0-device-runbook.md:210 (Session 0, step 0.7, Record)",
  "detail": "At 832a3636 the line reads: \"Record: commit the regenerated log on `m0-sessions` (0.3, step 6; until 24 October 2026 this said `m0-decisions`); update the G0.2 row.\" On the owner's branch (`git show c72247a6:Docs/Stage0/M0-device-runbook.md`, line 207) it says \"commit the regenerated log on `m0-decisions` (0.3, step 6)\". The m0-sessions wording came in with the merge 4c0fa815 and no later commit put it back, so merging this branch makes the owner's runbook worse at this step. 0.7 is one of the next Session 0 steps the owner has to run: his setup record (evidence/M0-runbook/2026-10-26-setup.txt) says \"The Keychain test itself has NOT run; this is not a pass for step 0.7\". Following the line would put the commit on the retired branch, or lead Codex to check out m0-sessions, which has neither DeviceTests nor his records. It also contradicts 0.3 step 6, which it cites. It disproves the README's claim that the model is \"restated everywhere the records give it\" (evidence/M0-RecordsUpdate/README.md:28). Integration log 41.3 lists every runbook place it rewrote and leaves 0.7 out. Fix: write \"on `m0-decisions` (0.3, step 6; from 24 to 26 October 2026 this said `m0-sessions`)\", as 0.8's Record already does (line 221). Add a check that fails on any m0-sessions instruction outside a history clause. None of the branch's checks caught this one: runbook-content-check, check-records and gate-refresh-check all pass at 832a3636, which I re-ran."
 },
 {
  "id": "OWN-RU-02",
  "severity": "blocker",
  "title": "Gate summary Section 5.4 tells the owner to build from m0-sessions and that his records are committed there",
  "location": "Docs/Stage0/M0-gate.md:466 (Section 5.4, the bullet on bringing agent work to main)",
  "detail": "The live text reads: \"The same holds for the records and evidence of your sessions, committed on `m0-sessions` (Section 1, item 1, step 6). Not needed for the exit: until you say so, build from `m0-sessions`.\" Both parents that held this bullet said m0-decisions: c72247a6 (line 459) and c3adae68 (line 460) read \"which you commit on `m0-decisions` ... until you say so, build from `m0-decisions`\". The m0-sessions version came in with 4c0fa815 and was not restated. Yet item 178 (line 839) lists Section 5.4 as brought into line, and the 5.4 bullet on the session branch (line 482) says the opposite. The gate summary is the owner's main guide, and this sentence is a direct instruction about which branch to build from. Following it would build a sitting from a branch that lacks Spikes/G05-Recovery/DeviceTests (1.2's commands would fail) and the owner's records. Fix: restore `m0-decisions` in both clauses, with a dated history clause (\"from 24 to 26 October 2026 this said `m0-sessions`\")."
 },
 {
  "id": "OWN-RU-03",
  "severity": "major",
  "title": "If m0-decisions has moved on, the merge procedure leaves records that contradict the owner's own, and asserts that nothing repeats",
  "location": "Docs/Stage0/evidence/M0-RecordsUpdate/README.md:53-74; Docs/Stage0/evidence/M0-RecordsUpdate/commands/owner-records-intact.py:24",
  "detail": "The README says to merge only once the sitting in progress is done and its records are committed (line 53). At c72247a6 the 1.4 audio run was still running (evidence/G04-Audio/device/step-01-status.txt: \"RUNNING ... Full suite not complete\"). Two agent branches are also cut from c72247a6 for merging into m0-decisions: m0-device-fixes-ats, already 907538f5..0b0e1e65, and m0-device-fixes-recovery. So the fast-forward case is the unlikely one. For the moved-on case the README only handles textual conflicts (lines 66-71) and says the other files \"merge cleanly\". I simulated it without writing any ref. I made an unreferenced commit 7845d48b on c72247a6 that records G0.4 step 1 (report row 2 failed, the status file, a session-log row 3e) and merged the head in memory with `git merge-tree --write-tree 7845d48b 832a3636`. The merge is clean (tree 788b9d39), yet the result still says \"G0.4 step 1 still running\" (M0-gate.md line 10), \"1.4's audio run started, its result not yet recorded\" (gate line 47; runbook line 6), and \"still all pending ... no result is claimed\" (G04-Audio.md line 6, beside the owner's new row 2, and checklist line 3). The agent records then contradict the owner's, and by these records' own rule it is the agent records that must change; nothing in the procedure says so. The README also says \"rerun this branch's checks\" only for the conflict case, and owner-records-intact.py hard-codes OWNER_HEAD = c72247a6, so a rerun would not check the owner's new commits. Separately, 'After the merge' (lines 72-74) states without condition that nothing repeats and that 0.8 needs nothing, while runbook 0.8 (line 212) says to check again after each merge, and a recovery-suite fix branch is under way. Fix: if `git log c72247a6..m0-decisions` prints anything, do not merge. Have an agent first merge m0-decisions into m0-records-update, bring the account of the sittings up to date, add the new commits to owner-records-intact.py and rerun the checks, so the owner's merge is always a fast-forward. Make 'After the merge' run 0.8's diff command and 0.3 step 7's diff instead of asserting their results."
 },
 {
  "id": "OWN-RU-04",
  "severity": "major",
  "title": "The merge puts a CLAUDE.md on the owner's session branch that says never build on m0-decisions, and the fix is a hand-paste with inconsistent timing",
  "location": "CLAUDE.md:5; Docs/Stage0/evidence/M0-RecordsUpdate/README.md:46-48, 66-68, 72; Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md:7-10",
  "detail": "m0-decisions's CLAUDE.md today (c72247a6) names m0-integrate: out of date, but it gives no instruction against m0-decisions. After this branch is merged, m0-decisions's CLAUDE.md is 6cede84a's paragraph: \"Since 24 October 2026 the M0 work is on `m0-sessions` ... the product owner builds the device sessions from it ... Further M0 work goes on a branch of its own made from `m0-sessions` ... Never build on `m0-integrate` or `m0-decisions`\". The branch rightly declines to edit CLAUDE.md itself (item 46). Even so, the merge it asks the owner to make introduces, in the checkout where he works with an agent in every sitting, an instruction that reverses the branch model. Undoing it is left to a hand-paste of a 2,600-character paragraph after the merge. The two documents disagree on timing. The README says apply it after the merge (line 72). claude-md-paragraph.md says apply it on m0-decisions \"before you ask an agent for anything\" and never says after the merge. If applied first, the owner's paragraph and 6cede84a's conflict on CLAUDE.md line 5, a conflict the README's list of possible conflicts (lines 67-68) does not name. Without asking any agent to edit CLAUDE.md, either keep m0-decisions's own CLAUDE.md in the merge result, so the merge changes nothing there, or make the owner's replacement an exact owner-run command inside the README's merge block. In the second case, commit it in the same sitting before Codex resumes and state the order in claude-md-paragraph.md."
 },
 {
  "id": "OWN-RU-05",
  "severity": "major",
  "title": "Running 1.2 or 1.3 again as written overwrites the owner's committed evidence that the records cite",
  "location": "Docs/Stage0/M0-device-runbook.md:262 (1.2 tee), :79 (1.5 bullet), :290 (1.3 tee), :171 (0.3 step 7); Docs/Stage0/M0-gate.md:47",
  "detail": "The records make repeats of these steps the next work: gate line 47 says \"1.2's repeats wait for the diagnosis of the suite's failures\", and G0.5 AI's D1 awaits a diagnosis, with an ATS fix branch in progress. 1.2's command, which is the owner's, tees into evidence/G05-Recovery/device/step-1-tests.log. That file holds the owner's first blocked package-scheme attempt, and three records cite it as such: this branch's new 1.5 bullet (line 79), step-1-2-results.txt (\"Log: step-1-tests.log\") and the report's 'Physical-device attempt' section (G05-Recovery.md:119). 1.2's Record also writes into step-1-2-results.txt. 1.3 tees into evidence/G05-AI/device/step-01-ats.log, the failed run that row D1 cites. A repeat as written replaces the owner's evidence at HEAD and makes the runbook's own citation false. Neither 0.3 step 7 nor Section 2 says to log a repeat under a new name; Codex did so on his own (step-1-hosted-tests.log, step-01-ats-initial.log). Fix, leaving the owner's command lines as committed: add a note at 1.2, at 1.3 and in 0.3 step 7 that a repeat writes its log and results under new names (for example with the commit), leaving the first sittings' files as committed."
 },
 {
  "id": "OWN-RU-06",
  "severity": "minor",
  "title": "Session 0's order line and 'before Session 0' wording are stale now that the first sittings have run",
  "location": "Docs/Stage0/M0-device-runbook.md:157; Docs/Stage0/M0-gate.md:24 (Section 1, item 1, step 8)",
  "detail": "Line 157 (from m0-sessions) says \"since 24 October 2026 only its steps 1 and 4 are left to do before the first sitting: the rest are done or come later\". Now 0.3 step 1 is done, step 2 (CLAUDE.md) is the owner's before any agent request, and the first sittings took place on 25 October 2026 UTC. Gate item 1, step 8 still says to update device A \"before Session 0\". Session 0 has partly run; the binding point is before 0.4 records A, which is what runbook 1.1 row A says."
 },
 {
  "id": "OWN-RU-07",
  "severity": "minor",
  "title": "0.3 step 7 says the repeat diff lists nothing under Spikes, but against rows 3a-3c's commits it lists DeviceTests",
  "location": "Docs/Stage0/M0-device-runbook.md:171",
  "detail": "The parenthesis says that, against the first sittings' commits, the diff lists \"nothing under `Apps`, `Packages`, `Spikes`, `Fixtures` or `Contracts`\". The step's own command, `git diff --stat 96bdc7e9 832a3636 -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists`, lists the four Spikes/G05-Recovery/DeviceTests files besides the checklists and the two Zip-guard scripts. It does the same against 8404f342 and 432acc13; only against d5336111 is nothing listed under Spikes. Name DeviceTests among the changes that need no repeat, as the gate summary's item 2 note already does."
 },
 {
  "id": "OWN-RU-08",
  "severity": "minor",
  "title": "Other texts still describe m0-sessions as current, or linkage.sh as 'reviewed next', with no superseding note",
  "location": "Docs/Stage0/integration-log.md:3; Docs/Stage0/M0-gate.md:122, 471, 556, 855-857; Docs/Stage0/M0-device-runbook.md:137",
  "detail": "Integration log opening: \"the M0 work moved to `m0-sessions`\". It stops at section 38 and never says that section 41 reverses this. Gate Section 1 bullet on main (line 122): its last note says \"the M0 work continues on `m0-sessions`\". Gate 5.4 technical-lead note (line 471): \"ADR-0001 records the same evidence on `m0-exit-prep`, merged into `m0-sessions` once reviewed\". Gate 6.3 item 1's last note (line 556): \"the sessions build from `m0-sessions`\". `linkage.sh` is still \"done by an agent on 24 October 2026, reviewed next\" in runbook run 12 (line 137) and in gate Section 7 items 1-3 (lines 855-857), though m0-exit-prep's review accepted it. Add the dated 26 October note that the records' convention calls for."
 }
]
```

## What the task also relayed

The rest of the task text restates the state and the device-A change as relayed to `m0-records-update` (above), and
asks, as it did there: describe the branch model everywhere; keep the owner's records and code exactly as committed;
never change an owner's result, session-log row, log or evidence file; leave the files under `Docs/Stage0/evidence/`
that record past runs and checks as they are, making a new version of a check that must keep passing where it asserts
an old text, and recording which old check now fails by design and why; state in runbook 0.8 whether its class-B
evidence still stands, with the paths and the commit checked.
