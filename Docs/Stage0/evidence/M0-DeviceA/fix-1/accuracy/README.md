# The fix of the review's accuracy findings (26 October 2026)

**What this is.** The agent review that read `m0-sessions` at `8082bdb6`, the update of 24 October 2026 (`../../README.md`,
`../../instructions/`) with its assembly (`../../assembly/`), had an accuracy lens too, and the orchestrating session's
workflow relayed its findings, ACC-01 to ACC-06, to this fix, with the product owner's request "keep going"
([`relayed-findings.md`](relayed-findings.md), verbatim). The fix of the same review's fidelity findings came first
([`../README.md`](../README.md), integration log section 29); this one was made after it, by an agent on `m0-sessions`,
from `d6315ad3`, that fix's last commit, in a worktree of its own, on 26 October 2026 on the build Mac's clock (25 October
UTC). The task named `d6315ad3` as the commit reviewed; the findings' line numbers and quoted texts are those of
`8082bdb6` ([`checks/finding-lines.log`](checks/finding-lines.log)). Integration log section 30 is its record; the gate
summary records it in Section 6.2 and Section 6.3, items 124-130. Agent-written; not reviewed; human sign-off pending.
Nothing here is a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit: no device was used. To
judge the merge ACC-01 asks for, this fix read the diff of `m0-decisions` against `main`, the session log's rows
included; it records none of the owner's sittings' results here and infers none (its logs print only the first six
cells of the session log's dated rows there: when, by whom, from which commit, on which device).

## The findings, and what was done

| Finding | What was done |
| --- | --- |
| ACC-01 (blocker): at `8082bdb6` the owner's instructions described a branch state the assembly's own logs contradicted (`m0-decisions` behind `main`, the checkout to be switched from `main` at `96bdc7e9`, nothing run on a device), and the assembly's gate checks printed "behind main: NO" and passed | The first fix had brought run 1's step 1 (the gate summary's item 1 and the runbook's 0.3), the runbook's header and the setup lines of the G0.4, G0.5 AI and G0.5 recovery checklists in line (FID-DA-01). This fix brought in the texts left: in the gate summary, the State line ("no device result is recorded here yet", 200 words, the limit) and Section 5.1, which still said that nothing in the runbook had been run on a device (now: no result of a device step in it is recorded here yet, and where the sittings are recorded, with a dated note); and in the runbook's header, the paragraph on the branch the owner builds from, which now also says that until the checkout moves each sitting builds from the branch it is on and commits its records there, as 0.3, step 1, says. Its gate checks now judge the branch state instead of printing it: [`commands/branch-texts.py`](commands/branch-texts.py) (below). The branches read again: as the first fix found them ([`checks/branch-state.log`](checks/branch-state.log)). **Not done here: the merge of `m0-decisions` into `m0-sessions`** (below) |
| ACC-02 (major): five texts said that no A13 phone is at hand in M0, or that device A is the only phone at hand besides phone B, which nobody checked | The first fix had reworded four (FID-DA-02). The fifth, the G0.5 AI checklist's note on step 1, now says that device A is the other phone that step runs on, with a dated note; the G0.2 checklist's note on step 22.5 now also says that a result ever taken on the iPhone 11 is recorded under its own model, as the runbook's 1.1 says. Both wording only; the runbook's 0.3, step 7, lists them as repeating no step on phone B |
| ACC-03: ADR-0001 and the records' evidence README said that the narrower exception applies to no G0.6 step on device A | Answered by the first fix (FID-DA-05): ADR-0001's clause, ADR-0013's dated note on step 12 and the README's note. Checked again ([`checks/recheck-acc.log`](checks/recheck-acc.log), item step-12); nothing changed |
| ACC-04: the lists of the figures on device A that are the 13 mini's named G0.3's steps 14-16 only | The runbook's repeats on A, the G0.3 checklist's Setup 1 (wording only), ADR-0010's open item (with a dated note) and ADR-0001's clause on ADR-0010 now also name the times G0.3's repeats record on A in steps 6, 9, 18, 20 and 32; the records' evidence README has a dated note. No outcome changed |
| ACC-05: the runbook's Section 7 said that the G0.4 checklist asks for steps 1, 3, 15 and 17 on device A | Its reason now says that the checklist asks for 1, 3 and 15 on A, never for 17, which the runbook added to its repeats on A on 19 October 2026 (`1befcf72`): 17 on A is the runbook's own repeat |
| ACC-06: the ADR index's row of ADR-0001 and plan D01's row gave Apple's release notes for Xcode 27.1 as still to check | The index's row was answered by the first fix (FID-DA-06). Plan D01's row now has a dated note (Apple's pages, read on 24 October 2026, list 27A9275 as released; the technical lead's confirmation remains), recorded within draft 0.8 in the Revised line and Appendix D's item of 24 October 2026; that item, the draft 0.8 entry's review note and the amendments' State line, with a dated note, now give the review at `8082bdb6` (the review status the first fix left to the next fix to change the plan). A new version of the amendments checker and its mutations asserts the new texts (below) |

## Not done here: the reconciliation of `m0-decisions` with `m0-sessions`

ACC-01 asks, as FID-DA-01 did, that `m0-decisions` be reconciled into `m0-sessions` first, "as item 115 says"; item 115
gives the reconciliation to the orchestrating session, with the owner, before the checkout moves. This fix did not
make the merge either, for the first fix's reasons (integration log 29.2), which hold as read here: `m0-decisions` is
still at `c72247a6` and the checkout on it; its last commit, at 17:33 UTC on 25 October 2026, is titled "Record setup
checks and the audio device run in progress", so a sitting may still be running; the merge brings the owner's sittings'
results into these records, which would then have to record them, committing a sitting's records being the owner's or
an agent's the owner asks; after it 0.8, last run on `9cdb0a02`, runs again, on the build Mac with its screen unlocked; and phone B's iOS build
recorded there is to be settled with the owner. Computed and not made, the merge gives no conflict with this fix's
documents commit ([`checks/branch-state.log`](checks/branch-state.log)). What this fix added instead is the check that
fails whenever a live text of the owner's instructions contradicts the branch state as git shows it, so that the
records cannot drift from the branches again unnoticed.

Also left as they were: `CLAUDE.md`, which still calls `m0-decisions` behind `main` and gives the release notes as
unchecked (the owner's or the orchestrating session's to change; the judged check reports its line and does not judge
it); the session log (the owner's record; on this branch it still says that no device step has been run, and the merge
brings the owner's version); the plan's device-evidence risk row and Status line, which describe these records; plan
6.3, which gives the release-notes check as the technical lead's, still pending; ADR-0001's own record of the Xcode 27.1
evidence and ADR-0014's dated note (the `m0-exit-prep` run's); runbook 0.8 (none of its paths changed:
[`checks/dropin-paths.log`](checks/dropin-paths.log)).

## Files

| Path | What it is |
| --- | --- |
| [`relayed-findings.md`](relayed-findings.md) | What was relayed to this fix: the request, the task, and the six findings verbatim |
| [`commands/finding-lines.py`](commands/finding-lines.py) → [`checks/finding-lines.log`](checks/finding-lines.log) | Every line the findings cite, read at `8082bdb6` with `git show`, holds the text they quote (on the line, or within three lines of it, the line found printed), every text they name without a line is in its file, and their five claims about refs and other commits hold |
| [`commands/branch-texts.py`](commands/branch-texts.py) → [`checks/branch-texts.log`](checks/branch-texts.log) | The judged branch check (ACC-01): the branches and the sessions' checkout read with git, read-only, against the live texts of the owner's instructions; four rules (behind, merged, checkout, sittings); `CLAUDE.md` reported, not judged |
| `../commands/branch-state.sh` → [`checks/branch-state.log`](checks/branch-state.log) | The first fix's read of the branches, unchanged, run again on this fix's documents commit |
| `../commands/dropin-paths.sh` → [`checks/dropin-paths.log`](checks/dropin-paths.log) | The first fix's check of runbook 0.8's paths, unchanged, run again on this fix's documents commit |
| [`commands/recheck-acc.py`](commands/recheck-acc.py) → [`checks/recheck-acc.log`](checks/recheck-acc.log) | This fix's recheck: one item per finding and one for the review status; its control, on `d6315ad3`'s tree, must report every item but step-12 |
| [`commands/check-amendments.py`](commands/check-amendments.py) → [`checks/check-amendments.log`](checks/check-amendments.log); [`commands/mutation-checks.py`](commands/mutation-checks.py) → [`checks/mutation-checks.log`](checks/mutation-checks.log) | The amendments checker for draft 0.8 as this fix left it (its check 10k asserts the new texts of D01's row, the Revised line, Appendix D and the amendments' review status) and its 70 mutations, the records part's 66 and four more |
| [`commands/expected-rechecks.txt`](commands/expected-rechecks.txt) | What each earlier recheck that reads a text the update or the two fixes changed must report on this tree, exactly, and why |
| [`commands/gate-checks.sh`](commands/gate-checks.sh) → [`checks/gate-checks.log`](checks/gate-checks.log) | The gate checks of this fix, the successor of the first fix's; run last, on the commit that adds every other log |
| [`checks/fix1-gate-checks.log`](checks/fix1-gate-checks.log) | The first fix's gate checks, unchanged, on this fix: they fail by design (below) |
| [`checks/ci-contracts.log`](checks/ci-contracts.log), [`checks/13-hard-rules.log`](checks/13-hard-rules.log) | `Scripts/ci.sh contracts` and `Scripts/ci.d/13-hard-rules.sh`, through `Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh` |
| [`checks/lfs-checkout.log`](checks/lfs-checkout.log) | This worktree's 777 Git LFS files were pointer files; the follow-up's `commands/lfs-checkout.sh`, unchanged, filled them from the local store, with no download |

## Checks

Each ran on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) on the commit its log's header
names: `lfs-checkout.log` on `d6315ad3`, before any change; the others on the fix's last documents commit, with no
uncommitted file, except that `dropin-paths.log` ran with `branch-state.log` in place, `recheck-acc.log` with both, and
`13-hard-rules.log` last, with every other log in place and not yet committed, so that the audit read them too (each
header counts its uncommitted paths); and the gate checks on the commit that adds every other log. Dry runs on the
uncommitted tree came first. Other jobs shared the Mac (the load averages in the logs), so no timing here is a result. No
simulator was created or used, nothing played audio, no device was contacted, nothing was fetched from or pushed to a git
remote, and no page was read over the network.

| Check | Result | Log |
| --- | --- | --- |
| The findings' cited lines and claims | All 47 citations hold their text at `8082bdb6`, 3 of them within three lines of the line cited; the 9 texts named without a line are there; the 5 claims hold | `checks/finding-lines.log` |
| The branches, read-only | The checkout on `m0-decisions` at `c72247a6`, 8 commits past `044ed3cf` and `main`, not behind `main`; a merge of `m0-decisions` into this fix's documents commit without a conflict | `checks/branch-state.log` |
| The judged branch check | Passes: no live text of the instructions calls `m0-decisions` behind `main`; it is not merged into `m0-sessions`, and run 1's step 1 has the case for a checkout on another branch, which the checkout is; the session log on `m0-decisions` records four sittings of the owner's, and no live text says, without saying where, that no device step has run or no device result is recorded. Its controls, in the gate checks: on the tree of `8082bdb6` all four rules fail (5 texts calling `m0-decisions` behind `main`, run 1's case missing in both places, 7 texts saying that nothing has run); on the tree of `d6315ad3` exactly its rule on the sittings (the State line and Section 5.1) | `checks/branch-texts.log`, `checks/gate-checks.log` |
| The drop-in's paths | No change from `9cdb0a02` to `6cede84a`, `5e455f70`, `8082bdb6` or this fix's documents commit; `m0-decisions` would add `Spikes/G05-Recovery/DeviceTests` (4 files) under them; neither file `m0-exit-prep` changes is named by a file the drop-in runs | `checks/dropin-paths.log` |
| This fix's recheck | Pass, 0 of 7 not as stated; the gate checks run its control on `d6315ad3`'s tree, where it reports every item but step-12 | `checks/recheck-acc.log` |
| The amendments checker and its mutations | 0 failed checks (132 numbered findings, 56 tags, 44 questions); 70 mutations, 70 caught, 0 missed, the tree restored | `checks/check-amendments.log`, `checks/mutation-checks.log` |
| `Scripts/ci.sh contracts` (`run-logged.sh`) | Passed: `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts` | `checks/ci-contracts.log` |
| `Scripts/ci.d/13-hard-rules.sh` (`run-logged.sh`) | Passed: the self-test and the audit of every committed and new file, these logs and this fix's scripts among them, 0 findings, 0 stale allowlist entries | `checks/13-hard-rules.log` |
| The gate checks (`commands/gate-checks.sh`) | Exit 0, as below | `checks/gate-checks.log` |
| The first fix's gate checks, unchanged | Fail by design (below) | `checks/fix1-gate-checks.log` |

**The gate checks.** Part 1: since `d6315ad3` only the files this fix names and its own folder; nothing outside `Docs/`;
`CLAUDE.md`, the session log, the license inventory and the gate reports unchanged; under `Docs/Stage0/evidence` only
this fix's new files and the dated notes in the records part's evidence README and the first fix's README; since
`6cede84a` as before; the drop-in's paths, the checklists (three changed here, wording only), the session log (no sitting
of the owner's on this branch) and the dependency logs; and 1h, the judged branch check passing, with its two controls.
Part 2: no LFS file added. Part 3: the gate summary's paths and 92 rows agree, and its negative control. Part 4: this
fix's amendments checker, 0 failed checks, its 70 mutations caught and the tree restored; the records part's checker
failing on exactly its check 10k, on the two texts below, by design; the follow-up's fix's checker failing on exactly
its three, as before; the records check failing on exactly its ADR index check, as before, and its control; the
instructions part's content check passing and the decisions round's version reporting exactly its three; the step
coverage; the correction texts (from `4c73da57` the nine, from `8082bdb6` and `d6315ad3` nothing); the earlier rechecks
that must pass passing, with their controls; the six others reporting exactly the 17 lines of
`commands/expected-rechecks.txt`; the instructions part's recheck reporting exactly its floor item; the assembly's
recheck reporting exactly agree and state, with its two controls; the first fix's two checks, its recheck reporting
exactly its item review, by design (below), each with its control; this fix's two checks, each with its control. Part 5:
`Scripts/ci.sh contracts dependency-lock hard-rules` passing.

**The earlier checks that now report what this fix changed, by design, and why.** Each asserts a text this fix changed
for a finding or for the review status; this fix's checks assert the new text, and its gate checks require exactly
these reports:

- **The records part's amendments checker** (`../../commands/check-amendments.py`): its check 10k requires Appendix D's
  item of 24 October 2026 to end "Agent-written; not reviewed." and the draft 0.8 entry's review note to say that the
  item "has not been reviewed either". The review read that record at `8082bdb6`, and this fix, which changed the plan
  for ACC-06, made both say so (integration log 29.3 had left that review status to the next fix to change the plan);
  this fix's version, `commands/check-amendments.py`, asserts the new texts, and its four new mutations guard them.
- **The first fix's recheck** (`../commands/recheck-fix1.py`): its item review requires the gate summary's State line to
  say "nor has the update's fix (Section 6.2)"; with two fixes of the update's review unreviewed, it now says "nor have
  the update's fixes (Section 6.2)", within the 200 words the checks keep. `commands/recheck-acc.py` (review) asserts it.
- **The fix's recheck of the drop-in run's record** (`../../../M0-Decisions/unlocked-record/round-2/commands/recheck-unl.py`):
  its UNL-02 line gives the State line's word count, now 200 (199 before; at most 200), the State line now saying that
  no device result is recorded here yet. It is in `commands/expected-rechecks.txt`, with the first fix's other 16 lines
  unchanged.
- **The first fix's gate checks** (`checks/fix1-gate-checks.log`, run on this fix's last documents commit, with no
  uncommitted file): part 1a, which allows only the first fix's files since `8082bdb6`, so not the plan, the amendments
  or the G0.3 checklist (this fix's folder is inside `fix-1/`, which it allows); part 1b, which requires the plan and the
  amendments unchanged; part 3, on the four logs of this fix that the gate summary cites and that the documents commit
  does not hold yet (`branch-state.log`, `finding-lines.log`, `gate-checks.log` and `recheck-acc.log`; this fix's gate
  checks, on the commit that adds them, find every path); and part 4, for the three reports above: the records part's
  amendments checker failing its check 10k, so that its mutations, which need the checker to pass first, do not run;
  the six rechecks' 17 lines against its 17, which differ in UNL-02's word count alone; and the first fix's recheck
  reporting its item review. Their other parts pass, part 5 (`Scripts/ci.sh contracts dependency-lock hard-rules`)
  among them.

What still passes unchanged: the follow-up's recheck, the moved-notes checks, both checks of the run's facts, both
finding-lines checks of the drop-in record's rounds, the second fix's recheck of that record (its sweep reads this fix's
Markdown files too), the first fix's check of the review's cited lines, the instructions part's runbook content check
and the step coverage.
