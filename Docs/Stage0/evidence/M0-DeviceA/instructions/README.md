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

Nothing here is a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit. No 13 mini has been
registered or run: Session 0.4 records its model identifier, iOS version and build. The update is agent-written and has
not been reviewed.

## Files

| File | What it is |
| --- | --- |
| [`relayed-2026-10-24.md`](relayed-2026-10-24.md) | What was relayed to the agent: the owner's request, the owner's decision on device A with the options and the choice, the state of the branches and of run 1, the Xcode 27.1 evidence and the device facts, each marked with what the agent checked again |
| [`inventory.md`](inventory.md) | Every text of the four documents and the checklists that named device A, the iPhone 11 Pro, the A13 floor, `m0-decisions` as the branch to use, or a step of run 1 the state changed, at `6cede84a`, with what was done with it |
| [`commands/screen-facts.sh`](commands/screen-facts.sh) → [`checks/screen-facts.log`](checks/screen-facts.log) | Xcode 27.1's simulator device types (the 13 mini is iPhone14,4), their display profiles, and a probe app on an iPhone 13 mini and an iPhone 11 Pro simulator (iOS 26.5, created and deleted by the script): both lay out at 375 × 812 pt at scale 3; the 13 mini at a native scale of 2.88 over 1080 × 2340 pixels; a 375-pt line is 2.2689 in on it and 2.4563 in on the 11 Pro, a ratio of 0.9237, 7.6% smaller |
| [`commands/apple-pages.sh`](commands/apple-pages.sh), [`commands/apple-pages.py`](commands/apple-pages.py) → [`checks/apple-pages.log`](checks/apple-pages.log) | Apple's pages read again on 24 October 2026 (23 October 17:10 UTC): the 13 mini's and the 11 Pro's specifications, the iPhones iOS 26 supports, and Xcode 27.1's release entry (27A9275, 15 October 2026, no beta or release-candidate label), its beta's entry (27A9269) and its release notes; every quote present, every absent text absent |
| [`commands/dropin-paths.sh`](commands/dropin-paths.sh) → [`checks/dropin-paths.log`](checks/dropin-paths.log) | Runbook 0.8: the paths G0.5 recovery's drop-in builds, copies or runs, read from the drop-in itself, unchanged between `9cdb0a02` and `6cede84a` (and HEAD); neither `Scripts/check-dependency-lock.py` nor `Scripts/ci.d/12-dependency-lock.sh`, which `m0-exit-prep` changes, is named by any file the drop-in runs |
| [`commands/runbook-content-check.py`](commands/runbook-content-check.py), [`commands/runbook-content-check.sh`](commands/runbook-content-check.sh) → [`checks/runbook-content-check.log`](checks/runbook-content-check.log) | The runbook's content check, a new version of the assembly's with the same comparison and its list of the runbook's own texts changed for the three texts this update changed; its runner's controls and limits, and the step coverage check |
| [`commands/recheck-instructions.py`](commands/recheck-instructions.py) → [`checks/recheck-instructions.log`](checks/recheck-instructions.log) | This update's recheck: device A, what the change means, the branch, run 1, step 0.8, and a sweep that lists, with a reason, each line that still names the iPhone 11 Pro or `m0-decisions` without a mark of this update |
| [`commands/expected-rechecks.txt`](commands/expected-rechecks.txt) | What each earlier recheck that reads a text this update changed must report on this tree, exactly, and why |
| [`commands/gate-checks.sh`](commands/gate-checks.sh) → [`checks/gate-checks.log`](checks/gate-checks.log) | The gate checks of this update, the successor of `M0-Decisions/unlocked-record/round-3/commands/gate-checks.sh`: what changed, Git LFS, the gate summary's paths and statuses, the documents' checks (old and new), the drop-ins that read documents |
| [`checks/old-round-3-gate-checks.log`](checks/old-round-3-gate-checks.log) | The previous round's gate checks, run on this update: they fail by design, as below |
| [`checks/lfs-checkout.log`](checks/lfs-checkout.log) | This worktree's Git LFS files were pointer files; `M0-Decisions/followup/commands/lfs-checkout.sh` filled them from the local LFS store (`git lfs checkout`, nothing downloaded, the configuration untouched), so that `00-git-lfs` can run |

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
  [`checks/old-round-3-gate-checks.log`](checks/old-round-3-gate-checks.log)): part 1b and 1c (`CLAUDE.md` changed
  outside `Docs/` since `26530d49`, by `5aec2518` and `6cede84a`, the orchestrating session's correction at the owner's
  request, before this update); part 1e (the checklists changed since `9cdb0a02`, by this update, before any session
  ran); and part 4 (the content check and the rechecks above, whose expected reports it fixes as they were).

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
