# The fix of the completeness findings of the review of `m0-records-update` (27 October 2026)

**What this is.** An agent review read `m0-records-update` at `832a3636` (`../../README.md`), and the orchestrating
session's workflow relayed its fidelity findings to a first fix ([`../README.md`](../README.md)) and then its
completeness findings, CMP-01 to CMP-07, to this one ([`relayed-findings.md`](relayed-findings.md), verbatim). This fix
was made by an agent on `m0-records-update`, from `7f7eae88`, the first fix's last commit, in a worktree of its own,
from 10:52 UTC on 26 October 2026 (23:52 on the build Mac's clock, which read 27 October from 11:00 UTC: its commits and
notes carry 27 October 2026). Integration log section 43 is its record; the gate summary records it in Section 6.2 and
Section 6.3, items 199-206. Agent-written; not reviewed; human sign-off pending. Nothing here is a device result, a role
sign-off, an ADR approval (decision D-6) or the M0 exit: no device was used, `CLAUDE.md` is `m0-decisions`'s byte for
byte, and the owner's records are kept exactly as committed ([`checks/owner-records-intact.log`](checks/owner-records-intact.log)).

## The findings, and what was done

| Finding | What was done |
| --- | --- |
| CMP-01 (blocker): `CLAUDE.md` at `832a3636` held `6cede84a`'s paragraph, which a merge would put on `m0-decisions`, with a toolchain line that gives Apple's release notes as unchecked; the texts for the owner were left to after the merge; merge `4c0fa815`'s message says the next commit rewrites the paragraph; the Stage 0 README called the paragraph corrected | Of the finding's two fixes, the second, which the first fix had begun by taking `m0-decisions`'s file back: the owner's step 2 now has its latest time, right after the merge of `m0-records-update`, in the same pause between sittings, and names both texts (the gate summary's item 1, step 2; the runbook's 0.3, step 2, and run 1; `../../claude-md-paragraph.md`); the merge commands of `../../README.md` apply both texts, commit them and run `12-dependency-lock`; the Stage 0 README opens with a caveat that `CLAUDE.md` is out of date on `m0-decisions`; the notes that gave the paragraph as corrected have later notes; integration log 41.2 records the merge's message. The first fix, the texts applied on this branch, is not made: no agent changes `CLAUDE.md` on a workflow's request (integration log 43.2) |
| CMP-02 (blocker): the runbook's 0.7 and the gate summary's Section 5.4 still on `m0-sessions` | Answered by the first fix (FID-RU-01, FID-RU-02, FID-RU-04); on this tree they name `m0-decisions` and its check of every live text passes ([`checks/retired-branch-texts.log`](checks/retired-branch-texts.log)) |
| CMP-03: four references in two lines of the gate summary's Section 8 kept `m0-sessions`'s numbers | Renumbered; [`commands/renumbered-references.py`](commands/renumbered-references.py) reads every reference the merges brought against the two branches, and found a fifth, in item 150, renumbered too; item 184 and integration log 41.2 have notes |
| CMP-04: the gate summary's old checker, an evidence file `m0-exit-prep` edited in place, called the version this branch's replaces without saying so | The evidence README's row, integration log 41.7 and the gate summary's item 180 say which text it is, from which commits, and that the merge brings it to `m0-decisions`; the file stays as it is |
| CMP-05: notes on `linkage.sh` "reviewed next", and Section 5.4's first bullet, still read as current | Later notes there and wherever the sweep of [`commands/completeness-checks.py`](commands/completeness-checks.py), part 5, or a reading found a note of the kind: in the gate summary, the runbook, ADR-0004, ADR-0014, ADR-0015, the ADR index (its column dated 27 October 2026 since) and the Stage 0 README (integration log 43.4) |
| CMP-06: the runbook's 0.3, step 7, said what its check lists against all the first sittings' commits, which holds from `4be1a1a4` on | The step gives what it lists against each, and why no repeat follows |
| CMP-07: the evidence README said that each log is headed, and named five kinds of file where a merge conflict can come | Both statements say what holds, with notes; the first fix's README, which said the same of its logs, has a note; this runner heads every log and commits its console |

## Files

| Path | What it is |
| --- | --- |
| [`relayed-findings.md`](relayed-findings.md) | What was relayed to this fix: the task, the state, the rules, and the seven findings verbatim |
| [`commands/finding-lines.py`](commands/finding-lines.py) → [`checks/finding-lines.log`](checks/finding-lines.log) | Every line the findings cite, read at `832a3636` with `git show`, holds the text they quote, and their claims about other commits hold |
| [`commands/renumbered-references.py`](commands/renumbered-references.py) → [`checks/renumbered-references.log`](checks/renumbered-references.log), [`checks/renumbered-references-new.log`](checks/renumbered-references-new.log) | CMP-03's check, on this tree and on its two controls; and every reference written after the merges, with what it names |
| [`commands/completeness-checks.py`](commands/completeness-checks.py) → [`checks/completeness-checks.log`](checks/completeness-checks.log), [`checks/completeness-sweep-control.log`](checks/completeness-sweep-control.log) | What this fix changed, one part per finding, with the sweep of part 5; and that sweep alone on `7f7eae88`'s tree |
| [`commands/check-records.py`](commands/check-records.py) → [`checks/check-records.log`](checks/check-records.log) | `m0-records-update`'s check of the device-A records, with its check of the ADR index for the column dated 27 October 2026 |
| [`commands/run-checks.sh`](commands/run-checks.sh) → [`checks/run-checks.console.log`](checks/run-checks.console.log) | Runs every check below on the documents commit and writes the logs, each headed with the commit, the uncommitted paths, the host and Xcode, the time and the load, and ended with its exit status; and its console |

## Checks

`commands/run-checks.sh` ran every check on this fix's last documents commit, with no uncommitted file; the commit after
it adds the logs and nothing else. A dry run on the uncommitted tree came first (`--dry`), its logs set aside. Host only:
the build Mac, macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275). No simulator was created or used, no device
was contacted, nothing played audio and nothing was fetched or pushed. Other jobs may have shared the Mac (the load
averages in the logs), so no timing here is a result.

| Log | What ran | What it must show |
| --- | --- | --- |
| `finding-lines.log` | `commands/finding-lines.py` | All 58 citations and claims hold |
| `renumbered-references.log`, `renumbered-references-new.log` | `commands/renumbered-references.py`: this tree; the controls on `832a3636`'s tree and on a copy of this tree with CMP-03's four references put back | This tree passes; `832a3636`'s fails on exactly CMP-03's four and item 150's; the copy on the four alone |
| `completeness-checks.log`, `completeness-sweep-control.log` | `commands/completeness-checks.py`; its sweep alone on `7f7eae88`'s tree | Every part passes; the sweep on `7f7eae88`'s tree finds exactly the 16 open paragraphs this fix gave later notes |
| `retired-branch-texts.log` | `../commands/retired-branch-texts.py`, the first fix's | Passes |
| `owner-records-intact.log`, `step-0.8-paths.log` | `../../commands/owner-records-intact.py`, `../../commands/step-08-paths.sh` | The owner's eight commits as committed; the drop-in's paths unchanged since `9cdb0a02` at `4c0fa815` and at this commit, `DeviceTests` set apart |
| `ci-contracts.log`, `12-dependency-lock.log`, `13-hard-rules.log` | `Scripts/ci.sh contracts`, `Scripts/ci.d/12-dependency-lock.sh`, `Scripts/ci.d/13-hard-rules.sh` | Each passes; the lock check reads ADR-0014, which this fix gave a note; the audit reads this fix's scripts |
| `runbook-content-check.log`, `runbook-coverage.log` | The device-A update's content check, with its controls and limits, and the step coverage | Both pass |
| `correction-texts.log` | `../../commands/correction-texts-compare.sh` | HEAD's lines equal those of `c72247a6`, `c3adae68` and `1d5ac477` |
| `check-amendments.log`, `mutation-checks.log` | The first fix's checker and its mutations (`../commands/`), unchanged: this fix changed neither the plan nor the amendments | 0 failed checks; 73 mutations, each caught; the plan and the amendments as committed afterwards |
| `check-amendments-records-update.log`, `check-amendments-accuracy.log` | `m0-records-update`'s checker and the accuracy fix's, unchanged | Each fails exactly its check 10k, as at the first fix |
| `check-records.log`, `check-records-records-update.log`, `check-records-devicea.log` | `commands/check-records.py`; `m0-records-update`'s and the records part's, unchanged | The first passes; `m0-records-update`'s fails exactly its check of the ADR index, whose column this fix dated 27 October 2026, by design; the records part's fails exactly its two checks, as before |
| `recheck-hon-ep.log`, `decisions-branch.log`, `recheck-own.log`, `gate-checks-exit-prep.log`, `gate-checks-devicea.log` (with their console logs) | The two branches' latest rechecks and gate checks, unchanged | Recorded as they report: each pins texts and states of the branch it was written on; what this fix changed in what they report is in integration log 43.8 |
| `gate-refresh-check.log` | `../../commands/gate-refresh-check.py`, unchanged, run last | Passes: every path the gate summary cites exists, every Section 2 status agrees with its records (passed-host 12, failed 4) |

Not run, and why: the complete CI (nothing outside `Docs/` changed; the drop-ins that read the documents ran); G0.5
recovery's drop-in (0.8's check finds nothing it uses changed); `resolve-locks.sh` and `linkage.sh` (they resolve
packages, which can reach git remotes); anything on a device.

## What stays pending

As `../../README.md` says: the device sessions that block the M0 exit, the owner's one-line confirmation of Xcode 27.1,
the owner's sign-offs, the ADR approvals (D-6), the M0 exit review, `CLAUDE.md`'s two texts, which are the owner's, and
a review of this fix and of the first.
