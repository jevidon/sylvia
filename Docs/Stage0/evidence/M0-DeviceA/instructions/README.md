# The owner's instructions, brought up to date (24 October 2026)

**What this is.** On 24 October 2026 the product owner asked to have what was out of date updated. That day pull
request #6 had merged `m0-decisions` into `main` (`96bdc7e9`); the orchestrating session had corrected `CLAUDE.md` at the
owner's request (`5aec2518`) and made the branch `m0-sessions` from that commit (`6cede84a`), which the sessions now
build from in `~/Git/sylvia-sessions`; an agent run had started on `m0-exit-prep` for run 1's step 5 and `linkage.sh`;
and the owner had decided D-1 again: the iPhone 11 Pro no longer charges, and device A is the owner's iPhone 13 mini.
An agent brought the owner's instructions up to date on branch `m0-sessions-instructions`, made from `6cede84a`: the
device runbook, the gate summary, the Stage 0 README and the eight device checklists. Another workstream of the same
update changes the plan, the amendments, the ADRs, the gate reports and the integration log, on another branch, and
keeps its own evidence in `Docs/Stage0/evidence/M0-DeviceA/` outside this folder.

**Finished on 26 October 2026.** The agent's first attempt stopped at a usage limit on 24 October 2026 with its last
changes uncommitted; the workflow committed them as they stood (`e7f3b066`: "unreviewed and possibly incomplete"),
after the attempt's own commit `6a72ce8c`. A second attempt, relayed the owner's request "keep going"
([`relayed-2026-10-24.md`](relayed-2026-10-24.md), last section), read that work against the task and the sources,
checked again what it relies on, finished it and ran every check on its last commits. It found the state unchanged
(`m0-sessions` still at `6cede84a`, `main` at `96bdc7e9`: [`checks/gate-checks.log`](checks/gate-checks.log), part 1g),
and changed, beyond what the first attempt left:

- the runbook's 0.3, step 7, and the gate summary's item 2, which said the checklists' lines were rewritten "before any
  session ran", which no record shows: they now say the session log then recorded no sitting of the owner's, which
  the gate checks assert (part 1e reads every dated row of the session log: each is an agent's run of 0.8);
- the runbook's record of D-1 of 22 October 2026, which still read "Device A is your iPhone 11 Pro" with no mark of the
  new decision: it keeps its text and gains a dated note pointing to the decision of 24 October 2026, in the
  convention of its note of 23 October 2026 (and this update's recheck asserts it);
- in the G0.3 checklist's Setup 1 and the G0.6 checklist's step 15, an "until then" that followed the new date of 24
  October 2026 while it meant 22 October 2026: each now names 22 October 2026;
- the figures on device A that are the 13 mini's own: G0.3's memory limit and times (steps 14-16) and the battery
  figures of G0.4 step 3, in repeats that can wait, join the timed repeats and the share extension's memory in the
  runbook's Session 8 and in the G0.3 and G0.4 checklists' device lines (the checklists' own texts were read for every
  step on A: G0.4 steps 8-13 record what iOS does, their only times
  procedural; G0.1 PDF step 1 asks whether the highlight appears at once; G0.5 recovery step 1's readbacks, SQLite
  version and pragmas do not depend on the chip, and its log holds the first of step 2's six save latencies; G0.6's
  steps on A judge layout, contrast and wording, and step 29's five seconds of "Saving…" are the prototype's own delay);
- the gate summary's row 66 and Section 2.10's bullet on Xcode 27.1, which still gave the release notes as unread, with
  no note: each has a dated note that Apple's pages were read on 24 October 2026 and the confirmation is the owner's, one
  line (and Section 6.3, item 107, and Section 8 list them);
- the gate summary's Section 8, which now says the update was finished on 26 October 2026 and when its checks ran;
- in this README, the time of the reading of Apple's pages, 17:49 UTC on 23 October 2026, as its log has it (it said
  17:10, the time of the drop-in paths' log).

Nothing here is a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit. No 13 mini has been
registered or run: Session 0.4 records its model identifier, iOS version and build. The update is agent-written and has
not been reviewed.

## Files

| File | What it is |
| --- | --- |
| [`relayed-2026-10-24.md`](relayed-2026-10-24.md) | What was relayed to the agent: the owner's request, the owner's decision on device A with the options and the choice, the state of the branches and of run 1, the Xcode 27.1 evidence and the device facts, each marked with what the agent checked again; and what was relayed to the second attempt on 26 October 2026 |
| [`inventory.md`](inventory.md) | Every text of the four documents and the checklists that named device A, the iPhone 11 Pro, the A13 floor, `m0-decisions` as the branch to use, or a step of run 1 the state changed, at `6cede84a`, with what was done with it (the second attempt's changes marked) |
| [`commands/screen-facts.sh`](commands/screen-facts.sh) → [`checks/screen-facts.log`](checks/screen-facts.log) | Xcode 27.1's simulator device types (the 13 mini is iPhone14,4), their display profiles, and a probe app on an iPhone 13 mini and an iPhone 11 Pro simulator (iOS 26.5, created and deleted by the script): both lay out at 375 × 812 pt at scale 3; the 13 mini at a native scale of 2.88 over 1080 × 2340 pixels; a 375-pt line is 2.2689 in on it and 2.4563 in on the 11 Pro, a ratio of 0.9237, 7.6% smaller (24 October 2026; on 26 October 2026 the two profiles' model identifiers were read again, iPhone14,4 and iPhone12,3) |
| [`commands/apple-pages.sh`](commands/apple-pages.sh), [`commands/apple-pages.py`](commands/apple-pages.py) → [`checks/apple-pages.log`](checks/apple-pages.log) | Apple's pages read again on 24 October 2026 (23 October 17:49 UTC): the 13 mini's and the 11 Pro's specifications, the iPhones iOS 26 supports, and Xcode 27.1's release entry (27A9275, 15 October 2026, no beta or release-candidate label), its beta's entry (27A9269) and its release notes; every quote present, every absent text absent |
| [`commands/dropin-paths.sh`](commands/dropin-paths.sh) → [`checks/dropin-paths.log`](checks/dropin-paths.log) | Runbook 0.8: the paths G0.5 recovery's drop-in builds, copies or runs, read from the drop-in itself, unchanged between `9cdb0a02` and `6cede84a` (and HEAD); neither `Scripts/check-dependency-lock.py` nor `Scripts/ci.d/12-dependency-lock.sh`, which `m0-exit-prep` changes, is named by any file the drop-in runs (24 October 2026; the gate checks run it again on their commit, part 1d) |
| [`commands/runbook-content-check.py`](commands/runbook-content-check.py), [`commands/runbook-content-check.sh`](commands/runbook-content-check.sh) → [`checks/runbook-content-check.log`](checks/runbook-content-check.log) | The runbook's content check, a new version of the assembly's with the same comparison and its list of the runbook's own texts changed for the three texts this update changed; its runner's controls and limits, and the step coverage check |
| [`commands/recheck-instructions.py`](commands/recheck-instructions.py), run by [`commands/recheck-instructions.sh`](commands/recheck-instructions.sh) → [`checks/recheck-instructions.log`](checks/recheck-instructions.log) | This update's recheck: device A, what the change means, the branch, run 1, step 0.8, and a sweep that lists, with a reason, each line that still names the iPhone 11 Pro or `m0-decisions` without a mark of this update; the runner adds its control, on the tree of `6cede84a`, where it must report all six items (the runner since 26 October 2026: the first attempt's log had neither the control nor the commit and time) |
| [`commands/expected-rechecks.txt`](commands/expected-rechecks.txt) | What each earlier recheck that reads a text this update changed must report on this tree, exactly, and why |
| [`commands/gate-checks.sh`](commands/gate-checks.sh) → [`checks/gate-checks.log`](checks/gate-checks.log) | The gate checks of this update, the successor of `M0-Decisions/unlocked-record/round-3/commands/gate-checks.sh`: what changed, the session log's dated rows, Git LFS, the gate summary's paths and statuses, the documents' checks (old and new), the drop-ins that read documents; run last, on the commit that adds every other log |
| [`checks/old-round-3-gate-checks-2.log`](checks/old-round-3-gate-checks-2.log), [`checks/old-round-3-gate-checks.log`](checks/old-round-3-gate-checks.log) | The previous round's gate checks, run on this update: they fail by design, as below. The first log is the second attempt's, on `ab03fe2f` (26 October 2026), after this update's own logs were written; the second, the first attempt's, on `6a72ce8c` (24 October 2026), before they were |
| [`checks/lfs-checkout.log`](checks/lfs-checkout.log), [`checks/lfs-checkout-2.log`](checks/lfs-checkout-2.log) | Each attempt found this worktree's Git LFS files as pointer files; `M0-Decisions/followup/commands/lfs-checkout.sh` filled them from the local LFS store (`git lfs checkout`, nothing downloaded, the configuration untouched), so that `00-git-lfs` can run: on 24 October 2026 and again on 26 October 2026 |

Environment: the build Mac, macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275); the simulators of
`screen-facts.sh` on the iOS 26.5 runtime; the network only for Apple's pages. Every log names its commit and time.

## The earlier checks that now fail by design, and why

The state of 24 October 2026 changed texts that earlier checks assert, so those checks now report them. Each is run
by `commands/gate-checks.sh`, which requires exactly these reports:

- **The assembly's runbook content check** (`M0-Decisions/assembly/commands/runbook-content-check.py`): three problems.
  Section 1.1 no longer quotes plan 19.1's sentence on the iPhone 11 Pro ("is an iPhone 11 Pro: the product owner chose
  the iPhone 11 family on 22 October 2026"), so its list's entry is stale; and Section 6's D-1 quotes the owner's words
  of 24 October 2026 and the option chosen, which its list does not have. The new version replaces it and passes.
- **The rechecks of the follow-up's rounds**, whose anchors sent the owner to `m0-decisions`:
  `followup/round-2/commands/recheck-review4.py` (FID4-02 now also lacks the runbook's and the gate summary's texts that
  merged agent work into `m0-decisions`; FID4-06 as before), `followup/round-3/commands/recheck-hon4.py` (HON4-01: three
  texts that had agent work go into `m0-decisions` or the owner build from it), `followup/round-4/commands/recheck-own4.py`
  (OWN4-03: "only once the other's branch is merged into `m0-decisions`", now `m0-sessions`; OWN4-06: the texts that had
  `CLAUDE.md` corrected on `m0-decisions`, done on 24 October 2026; OWN4-01 as before), and
  `followup/round-5/commands/recheck-own5.py` (OWN5-02: the texts that had the session records committed on
  `m0-decisions`, now `m0-sessions`).
- **The drop-in record's recheck** (`unlocked-record/commands/recheck-unlocked.py`): the gate summary's and the runbook's
  texts that had the run's folder committed on `m0-decisions` (now `m0-sessions`), besides the three it reported before.
- **The fix's recheck** (`unlocked-record/round-2/commands/recheck-unl.py`): UNL-02 and the review status as before; its
  UNL-02 line gives the State line's word count, now 198 (200 before), since the State line was rewritten, within its
  200-word limit, to record the decision of 24 October 2026.
- **The previous round's gate checks** (`unlocked-record/round-3/commands/gate-checks.sh`;
  [`checks/old-round-3-gate-checks-2.log`](checks/old-round-3-gate-checks-2.log), run on `ab03fe2f` on 26 October 2026,
  after this update's own logs were written): part 1b and 1c (`CLAUDE.md` changed outside `Docs/` since `26530d49`, by `5aec2518` and
  `6cede84a`, the orchestrating session's correction at the owner's request, before this update); part 1e (the
  checklists changed since `9cdb0a02`, by this update, when the session log recorded no sitting of the owner's); and
  part 4 (the content check and the rechecks above, whose expected reports it fixes as they were). Its part 3, the gate
  summary's paths and statuses, passes: in the first attempt's run of it, on `6a72ce8c`, it reported three paths this
  update cites that did not exist yet, its own logs.

What still passes unchanged: the step coverage check, the follow-up's fix's amendments checker, the correction-text
check (from `6cede84a` to this update no line differs), the gate summary's paths and statuses, and the other rechecks
of the earlier rounds.

## Asked of other owners, not done here

- The session log (`Docs/Stage0/evidence/M0-runbook/sessions.md`): its row 1 still lists run 1 as it stood (`m0-decisions`
  checked out, `CLAUDE.md` corrected on it, the merge into `main`, the requests based on it, the records committed on
  it, the release notes to read, device A's iOS), and its row 8 is titled "8 Device A, your iPhone 11 Pro".
- The repository's `README.md`: its sentence that the records of the decisions "are on the branch `m0-decisions`, which
  reaches main by pull request".
- The plan, the amendments, the ADRs, the gate reports and the integration log: the other workstream of this update.

*(26 October 2026: an assembly merged this part and the other workstream's into `m0-sessions`, changed the repository's README as asked, and left the session log as it was; it also changed a few of this part's texts to make the two parts agree, and ran the checks of the merged tree, with new versions of this part's gate checks and recheck: [`../assembly/README.md`](../assembly/README.md).)*
