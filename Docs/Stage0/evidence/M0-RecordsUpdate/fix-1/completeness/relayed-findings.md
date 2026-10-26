# What was relayed to the fix of the review's completeness findings (27 October 2026)

A record of what the orchestrating session's workflow relayed to this fix, kept as data: with the first fix's
[`../relayed-findings.md`](../relayed-findings.md), it is the review's only committed record (the review's own logs are
not committed). This fix began at 10:52 UTC on 26 October 2026 (23:52 on the build Mac's clock, which read 27 October
from 11:00 UTC, the date this fix's commits and notes carry). The workflow computed the task text; no request of the
product owner's came with it, and nothing in it is the owner's approval of anything.

- **The task**: fix one reviewer's findings, lens completeness, round 1, on branch `m0-records-update`, "reviewed at
  7f7eae88212a173f4eb9c6b9851af90100ad8b1d", the last commit of the fix of the same review's fidelity findings; the
  findings' line numbers and quoted texts are those of `832a3636`, the commit the review read
  ([`commands/finding-lines.py`](commands/finding-lines.py)). Other lenses' fixers run after this one, one at a time,
  on the same branch. "Fix every blocker and major properly, and the minors unless that changes scope; explain any you
  leave in not_fixed. Never change an owner's record to fix a finding. Re-run the checks your changes affect and save
  their logs under Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/. Commit, "git checkout --detach", and return the
  structured result." The first fix's logs are in that folder; this fix's are in this one, beside them.
- **The state it relayed** is the one relayed to `m0-records-update` itself, which that branch's README and integration
  log section 41 record (pull requests #4 to #6, H-1's exception and its limit; `m0-decisions` as the owner's session
  branch, with the owner's eight commits `8404f342` to `c72247a6` and Codex's `4be1a1a4`, all to be kept exactly as
  committed; `m0-exit-prep` at `c3adae68` and `m0-sessions` at `1d5ac477`; the branch model to describe everywhere; run 1
  as it now stands; phone B on iOS 27.0.1 (24A446); step 0.8's check; Apple's pages on Xcode 27.1 (27A9275), read by the
  orchestrating session on 24 October 2026; and the owner's decision of 24 October 2026 on device A, with what it means
  for each record). It again asked for `CLAUDE.md`'s paragraph from `6cede84a` to be rewritten for the branch model, as
  it had asked `m0-records-update`; no agent changes `CLAUDE.md` on a workflow's request (the gate summary's Section 6.3,
  item 46), so this fix did not, and the owner's step 2 stays (integration log 43.2).
- **The rules of the run**: a worktree of its own; no push, fetch or pull request; no write to, and no branch checked out
  in, `~/Git/sylvia`, `~/Git/sylvia-m0` or `~/Git/sylvia-sessions`; never commit to, reset or check out `m0-decisions`;
  `m0-exit-prep` and `m0-sessions` read, never committed to; no file read outside the worktree but the fixture cache,
  Xcode, the simulator device types, Xcode's caches and the system temporary folder; no physical device; the Mac's audio
  and global git configuration untouched; G0.5 recovery's class-B guard never bypassed; `Scripts/lib/env.sh` sourced in
  every shell (the agent sandbox refused `source` at the prompt, so every script run here sources it itself), Xcode 27.1
  (27A9275); `CLAUDE.md`'s evidence-honesty rules; nothing here a device result, a role sign-off, an ADR approval
  (decision D-6) or the M0 exit; temporary files under `.build/scratch`.

## The findings, verbatim

Seven, two blockers and five minor, as relayed (the reviewer's text, unchanged; line numbers are those of `832a3636`,
checked by [`commands/finding-lines.py`](commands/finding-lines.py)):

```json
[
 {
  "id": "CMP-01",
  "severity": "blocker",
  "title": "CLAUDE.md still carries 6cede84a's m0-sessions paragraph, and merging puts \"never build on m0-decisions\" onto the owner's session branch",
  "location": "CLAUDE.md:5 and :16; Docs/Stage0/evidence/M0-RecordsUpdate/README.md:46; Docs/Stage0/M0-device-runbook.md:126,166; Docs/Stage0/M0-gate.md:17,846; Docs/Stage0/README.md:5; merge commit 4c0fa815 message",
  "detail": "`git diff 6cede84a 832a3636 -- CLAUDE.md` is empty, so CLAUDE.md:5 still says: \"Since 24 October 2026 the M0 work is on `m0-sessions` ... the product owner builds the device sessions from it\", \"Further M0 work goes on a branch of its own made from `m0-sessions`\" and \"Never build on `m0-integrate` or `m0-decisions`: both are behind `main`.\" The task named CLAUDE.md first in the list of places that must describe the branch model, and said run 1's step 2 \"reaches m0-decisions when this branch is merged\". The branch did not rewrite the paragraph. It made step 2 the owner's instead (runbook run 1 at :126, 0.3 step 2 at :166, gate item 1 step 2 at :17, item 185 at :846) and put the text in claude-md-paragraph.md, to be applied after the merge.\n\nCLAUDE.md on c72247a6 has no such sentence. The merge is a fast-forward, since m0-decisions is still at c72247a6. So it changes the instructions on the owner's own session branch: they would forbid building on that branch and send agents to the retired branch, which is the move the owner lens rejected. Until the text is applied, any agent the owner asks to commit records on m0-decisions, or to merge into it (0.3 steps 5-6), or to resolve a merge conflict (README :67-72), reads the opposite rule. CLAUDE.md:16 also still says the release check \"awaits a check of Apple's release notes\".\n\nSmaller points:\n- The message of merge 4c0fa815 says \"the next commit rewrites it\", but d1fb3dd4 left the file unchanged.\n- The Stage 0 README, which CLAUDE.md sends agents to, says only that the paragraph was \"corrected ... `5aec2518`\" (:5). It never says that the merged paragraph names m0-sessions.\n\nFix: apply the two texts in claude-md-paragraph.md on this branch if the owner authorizes it. If no agent may author the text, do not regress m0-decisions: keep CLAUDE.md as on c72247a6 in this branch, make applying the text part of the same merge step, and add the caveat to the Stage 0 README."
 },
 {
  "id": "CMP-02",
  "severity": "blocker",
  "title": "Live instructions still tell the owner to commit on and build from the retired m0-sessions",
  "location": "Docs/Stage0/M0-device-runbook.md:210 (0.7 Record); Docs/Stage0/M0-gate.md:466 and :471 (Section 5.4)",
  "detail": "Runbook 0.7 (:210) reads: \"Record: commit the regenerated log on `m0-sessions` (0.3, step 6; until 24 October 2026 this said `m0-decisions`)\".\n- On c72247a6 this line read \"on `m0-decisions` (0.3, step 6)\". The text came from m0-sessions (6a72ce8c) and this branch kept it.\n- 0.7 is still to run: the owner's setup record says \"The Keychain test itself has NOT run; this is not a pass for step 0.7\".\n- After the merge, the owner's runbook would send this step's evidence to the retired branch.\n\nGate summary Section 5.4 (:466) still says: \"The same holds for the records and evidence of your sessions, committed on `m0-sessions` (Section 1, item 1, step 6). Not needed for the exit: until you say so, build from `m0-sessions`.\"\n- On c72247a6 it said m0-decisions.\n- It contradicts item 1, steps 1 and 6, and the bullet at :482 in the same section.\n\nOn the same page, :471 still says ADR-0001's evidence is on m0-exit-prep, \"merged into `m0-sessions` once reviewed\".\n\nThe README's item 2 claims \"The branch model, restated everywhere the records give it\". Integration log 41.3 and d1fb3dd4 list the places changed, and 0.7 is not among them. No check catches these lines: check-records.py, gate-refresh-check.py and the content check do not look for live m0-sessions instructions. I found them with a search for commit, build-from and check-out instructions naming a branch, outside history clauses."
 },
 {
  "id": "CMP-03",
  "severity": "minor",
  "title": "Renumbering left m0-sessions's numbers in two gate summary Section 8 lines, against the claim that all 27 mixed lines were renumbered",
  "location": "Docs/Stage0/M0-gate.md:890 and :870; Docs/Stage0/integration-log.md:2396 (41.2)",
  "detail": "Line :890, the bullet \"Your instructions brought up to date (24 October 2026)\", still cites three m0-sessions numbers:\n- \"Section 6.3, items 104-110\": at HEAD these are m0-exit-prep's items on the Zip guard, the review records and Xcode. It should be 131-137.\n- \"the integration log, section 28\": section 28 is now R4-01 and R4-02. It should be 36.\n- \"Section 6.3, items 111-115\": it should be 138-142.\n\nLine :870 cites \"Section 6.3, item 146\" for the dating of pull request #6. Item 146 is now FID-DA-04; the right item is 173.\n\nBoth lines are in the renumbering dry run's \"mixed\" list (852 and 871 at 4c0fa815). I reproduced that dry run at 4c0fa815: 206 lines, 6 dangling, 27 mixed. Integration log 41.2 and Section 6.3 item 184 say those lines \"were renumbered by hand\". An independent scan of HEAD found no other unrenumbered references, only the two intended texts at the past commit 8082bdb6."
 },
 {
  "id": "CMP-04",
  "severity": "minor",
  "title": "One historical evidence file differs from m0-decisions, and the branch calls it the old checker without saying so",
  "location": "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py:144-174; Docs/Stage0/evidence/M0-RecordsUpdate/README.md (gate-refresh-check-old row); integration log 41.7",
  "detail": "`git diff --name-status c72247a6 832a3636 -- Docs/Stage0/evidence/ | grep -v '^A'` lists exactly this file. The owner's session log is identical to c72247a6, and every other evidence change is a new file.\n\nm0-exit-prep rewrote the file's row 76 entry in place, in 83ed5ff3, 944a6302, f95de709 and 9f5edab1. The file is a 19-20 October command whose committed runs (the M0-Integration gate-refresh-checks logs) used an earlier text. The edit is disclosed on m0-exit-prep, in the script's comment and integration log 30, and this branch correctly wrote a new version under M0-RecordsUpdate/commands.\n\nBut this merge brings the edited copy to m0-decisions. The README and 41.7 call it \"the version it replaces\" and \"the old checker\", and do not record that it is no longer the version its historical logs ran."
 },
 {
  "id": "CMP-05",
  "severity": "minor",
  "title": "Some notes on m0-exit-prep's review and on m0-sessions were not brought up to date",
  "location": "Docs/Stage0/M0-device-runbook.md:137; Docs/Stage0/M0-gate.md:855-857, :122, :463",
  "detail": "- \"*(done by an agent on 24 October 2026, reviewed next)*\" on `linkage.sh` remains in run 12 (runbook :137) and in gate Section 7 items 1-3 (:855-857). These records now say the m0-exit-prep review accepted that branch at c3adae68, and runbook :1003 was updated to say so.\n- The last dated note of the gate summary's history bullet at :122 still says \"the M0 work continues on `m0-sessions`\". The bullet has no note of 26 October, while the Stage 0 README's matching bullet got one.\n- Gate Section 7 item 1 (:855) and Section 5.4's first bullet (:463) put the 26 October \"closed\" note before the 24 October note (\"review pending, so a review that accepts it is still to come\" and \"stays open until a review accepts the change\"). Each bullet therefore ends on the superseded state."
 },
 {
  "id": "CMP-06",
  "severity": "minor",
  "title": "Runbook 0.3 step 7 misstates what the repeat check lists against the first sittings' commits",
  "location": "Docs/Stage0/M0-device-runbook.md:171",
  "detail": "Step 7 says that once m0-records-update is merged, the repeat-check diff \"against your first sittings' commits\" lists only the checklists' wording and the Zip guard scripts, \"with nothing under `Apps`, `Packages`, `Spikes`, `Fixtures` or `Contracts`\".\n\nThat holds only for d5336111 and c72247a6. Against 96bdc7e9, 8404f342 or 432acc13 (session log rows 3a-3c), the diff also lists:\n- the four `Spikes/G05-Recovery/DeviceTests` files;\n- the owner's G0.5 recovery checklist command changes (25 lines, against 7).\n\nThis comes from `git diff --stat 96bdc7e9 HEAD -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists`."
 },
 {
  "id": "CMP-07",
  "severity": "minor",
  "title": "Two statements in the branch's evidence README are overstated",
  "location": "Docs/Stage0/evidence/M0-RecordsUpdate/README.md:79 and :67",
  "detail": "Line :79 says \"Each log's header names its commit, the uncommitted paths, the host and Xcode, the time and the load.\" Several logs start with results and have no such header: owner-records-intact.log, check-records.log, check-records-devicea.log, check-amendments.log, check-amendments-accuracy.log, mutation-checks.log, runbook-coverage.log, gate-refresh-check.log and gate-refresh-check-old.log. The console output of run-checks.sh, which names HEAD, host, start and load and gives the overall result, is not committed.\n\nLine :67 says \"A conflict can come only where both changed the same lines: the gate reports, the checklists, the runbook, the gate summary or the ADRs.\" Relative to c72247a6 this branch also changes:\n- CLAUDE.md, which the owner is told to edit on m0-decisions;\n- README.md, the plan, the amendments, the integration log and the Stage 0 README;\n- third-party-inventory.md and M0-contracts.md;\n- the two Zip guard scripts.\n\nAll the results the branch claims are reproduced: I re-ran commands/run-checks.sh at 832a3636 (result: pass, every log matching apart from times, temporary paths and file counts) and the renumbering dry run. Only these two README statements are overstated."
 }
]
```
