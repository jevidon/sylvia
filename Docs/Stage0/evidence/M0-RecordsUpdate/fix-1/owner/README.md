# The fix of the owner-readability findings of the review of `m0-records-update` (27 October 2026)

**What this is.** An agent review read `m0-records-update` at `832a3636` (`../../README.md`), and the orchestrating
session's workflow relayed its fidelity findings to a first fix ([`../README.md`](../README.md)), its completeness
findings to a second ([`../completeness/README.md`](../completeness/README.md)) and then its owner-readability findings,
OWN-RU-01 to OWN-RU-08, to this one ([`relayed-findings.md`](relayed-findings.md), verbatim). This fix was made by an
agent on `m0-records-update`, from `7c87a82d`, the second fix's last commit, in a worktree of its own, from about 12:20
UTC on 26 October 2026 (01:20 on 27 October on the build Mac's clock, the date its commits and notes carry). Integration
log section 44 is its record; the gate summary records it in Section 6.2 and Section 6.3, items 207-214. Agent-written;
not reviewed; human sign-off pending. Nothing here is a device result, a role sign-off, an ADR approval (decision D-6)
or the M0 exit: no device was used, `CLAUDE.md` is `m0-decisions`'s byte for byte, no ref of this repository was written
but this branch's commits, `~/Git/sylvia-sessions` was not touched, and the owner's records are kept exactly as
committed ([`checks/owner-records-intact.log`](checks/owner-records-intact.log)).

## The findings, and what was done

| Finding | What was done |
| --- | --- |
| OWN-RU-01 (blocker): the runbook's 0.7 had the owner commit the Mac identity log on `m0-sessions`; no check read for it | Answered by the first fix (FID-RU-01), with the check the finding asks for; on this tree 0.7 says `m0-decisions` and that check passes ([`checks/retired-branch-texts.log`](checks/retired-branch-texts.log)) |
| OWN-RU-02 (blocker): the gate summary's Section 5.4 had the owner build from `m0-sessions` and commit the records there | Answered by the first fix (FID-RU-02); on this tree both clauses say `m0-decisions` |
| OWN-RU-03 (major): once `m0-decisions` has moved on, the merge procedure could leave these records contradicting the owner's, it checked no owner commit after `c72247a6`, and it asserted that nothing repeats and that 0.8 needs nothing | The owner's merge is `git merge --ff-only`, a fast-forward or nothing; if `m0-decisions` has moved on, an agent first merges it into this branch, brings the account of the sittings up to date and runs [`commands/owner-records-intact.py`](commands/owner-records-intact.py), a new version that takes the owner's head; after the merge the owner runs 0.8's and 0.3, step 7's checks ([`../../README.md`](../../README.md), "Merging it into `m0-decisions`"). Every merge into `m0-decisions` is a fast-forward too (the runbook's 0.3, step 5; the gate summary's item 1, step 5; the paragraph for `CLAUDE.md`) |
| OWN-RU-04 (major): `CLAUDE.md` as the merge would bring it, and the texts a paste by hand with inconsistent timing | The first fix had kept `m0-decisions`'s `CLAUDE.md`; the order is fixed (the fast-forward merge, then the texts, in the same pause, before Codex or any agent works in the checkout again), and [`commands/apply-claude-md-texts.py`](commands/apply-claude-md-texts.py), which the merge brings and the owner runs, puts both texts in, changing nothing else ([`../../claude-md-paragraph.md`](../../claude-md-paragraph.md) states the order). No agent ran it on a checkout of the owner's |
| OWN-RU-05 (major): 1.2 or 1.3 run again as written would write over the owner's committed evidence | The runbook's Section 2 gives the rule (new names, with the commit, never over a committed file); 1.2 and 1.3 have notes with the new names, the owner's command lines unchanged; 0.3, step 7, and the gate summary's rule on repeats say so |
| OWN-RU-06 (minor): Session 0's order line and the gate summary's item 1, step 8, written before the sittings | The order line points to the owner's setup record and gives 0.3 as it stands; step 8 says before Session 0.4 records A |
| OWN-RU-07 (minor): the runbook's 0.3, step 7, on what its check lists against the first sittings' commits | Answered by the second fix (CMP-06) |
| OWN-RU-08 (minor): texts still current on `m0-sessions` and on `linkage.sh` | Answered by the first two fixes (FID-RU-04, CMP-05); on this tree each has its later note |

## Files

| Path | What it is |
| --- | --- |
| [`relayed-findings.md`](relayed-findings.md) | What was relayed to this fix: the task, the state, the rules, and the eight findings verbatim |
| [`commands/finding-lines.py`](commands/finding-lines.py) → [`checks/finding-lines.log`](checks/finding-lines.log) | Every line the findings cite, read at `832a3636` with `git show`, holds the text they quote, two of them a line off, and their claims about other commits and branches hold |
| [`commands/owner-checks.py`](commands/owner-checks.py) → [`checks/owner-checks.log`](checks/owner-checks.log) | What this fix changed, one part per finding, and the earlier fixes' answers it relies on |
| [`commands/merge-simulation.sh`](commands/merge-simulation.sh), [`commands/merge-simulation-helpers.py`](commands/merge-simulation-helpers.py) → [`checks/merge-simulation.log`](checks/merge-simulation.log) | The owner's merge as the README gives it, in a scratch clone with branches of its own: not moved (the fast-forward, the apply command, the lock check, the commit, and 0.8's and 0.3, step 7's checks) and moved on (the refusal, the new check failing and then passing after an agent's merge, the fast-forward after it); and the apply command's refusals |
| [`commands/owner-records-intact.py`](commands/owner-records-intact.py) → [`checks/owner-records-intact.log`](checks/owner-records-intact.log) | The owner-records check that takes `--owner-head`; run with its defaults and with the commit `m0-decisions` is at, beside the version it replaces |
| [`commands/apply-claude-md-texts.py`](commands/apply-claude-md-texts.py) | The owner's command for run 1's step 2 (not a check; the simulation runs it in its clone) |
| [`commands/completeness-checks.py`](commands/completeness-checks.py) → [`checks/completeness-checks.log`](checks/completeness-checks.log) | The second fix's check of its texts, in a new version for the three of its checks that read the merge section this fix rewrote; the version it replaces → [`checks/completeness-checks-completeness.log`](checks/completeness-checks-completeness.log) |
| [`commands/run-checks.sh`](commands/run-checks.sh) → [`checks/run-checks.console.log`](checks/run-checks.console.log) | Runs every check below on the documents commit and writes the logs, each headed with the commit, the uncommitted paths, the host and Xcode, the time and the load, and ended with its exit status; and its console |

## Checks

`commands/run-checks.sh` ran every check on this fix's last documents commit, with no uncommitted file; the commit after
it adds the logs and nothing else. A dry run on the uncommitted tree came first (`--dry`), its logs set aside. Host only:
the build Mac, macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275). No simulator was created or used, no device was
contacted, nothing played audio and nothing was fetched from a remote or pushed; the simulation's local clone, under
`.build/scratch`, was deleted after it. Other jobs may have shared the Mac (the load averages in the logs), so no timing
here is a result.

| Log | What ran | What it must show |
| --- | --- | --- |
| `finding-lines.log` | `commands/finding-lines.py` | All 65 citations and claims hold |
| `owner-checks.log` | `commands/owner-checks.py` | Every part passes; its note says whether `m0-decisions`, read only, is in HEAD's history |
| `merge-simulation.log` | `commands/merge-simulation.sh` | Passes: every expectation of its three parts |
| `owner-records-intact.log` | `commands/owner-records-intact.py` (its defaults; `--owner-head m0-decisions --rev HEAD`) and `../../commands/owner-records-intact.py` | All three pass |
| `retired-branch-texts.log` | `../commands/retired-branch-texts.py`, the first fix's | Passes |
| `completeness-checks.log`, `completeness-checks-completeness.log`, `renumbered-references.log` | `commands/completeness-checks.py`; the second fix's version it replaces; the second fix's `renumbered-references.py` | The first passes; the second fails exactly its three checks of the merge section, by design; the third passes |
| `step-0.8-paths.log` | `../../commands/step-08-paths.sh` | The drop-in's paths unchanged since `9cdb0a02` at `4c0fa815` and at this commit, `DeviceTests` set apart |
| `ci-contracts.log`, `12-dependency-lock.log`, `13-hard-rules.log` | `Scripts/ci.sh contracts`, `Scripts/ci.d/12-dependency-lock.sh`, `Scripts/ci.d/13-hard-rules.sh` | Each passes; the audit reads this fix's scripts |
| `runbook-content-check.log`, `runbook-coverage.log` | The device-A update's content check, with its controls and limits, and the step coverage | Both pass |
| `correction-texts.log` | `../../commands/correction-texts-compare.sh` | HEAD's lines equal those of `c72247a6`, `c3adae68` and `1d5ac477` |
| `check-amendments.log`, `mutation-checks.log` | The first fix's checker and its mutations, unchanged: this fix changed neither the plan nor the amendments | 0 failed checks; 73 mutations, each caught; the plan and the amendments as committed afterwards |
| `check-amendments-records-update.log`, `check-amendments-accuracy.log` | `m0-records-update`'s checker and the accuracy fix's, unchanged | Each fails exactly its check 10k, as before |
| `check-records.log`, `check-records-records-update.log`, `check-records-devicea.log` | The second fix's `check-records.py`; `m0-records-update`'s and the records part's, unchanged | The first passes; `m0-records-update`'s fails exactly its check of the ADR index, and the records part's exactly its two checks, as before |
| `recheck-hon-ep.log`, `decisions-branch.log`, `recheck-own.log`, `gate-checks-exit-prep.log`, `gate-checks-devicea.log` (with their console logs) | The two branches' latest rechecks and gate checks, unchanged | Recorded as they report: each pins texts and states of the branch it was written on; what this fix changed in what they report is in integration log 44.8 |
| `gate-refresh-check.log` | `../../commands/gate-refresh-check.py`, unchanged, run last | Passes: every path the gate summary cites exists, every Section 2 status agrees with its records (passed-host 12, failed 4) |

Not run, and why: the complete CI (nothing outside `Docs/` changed; the drop-ins that read the documents ran); G0.5
recovery's drop-in (0.8's check finds nothing it uses changed on this branch); `resolve-locks.sh` and `linkage.sh` (they
resolve packages, which can reach git remotes); anything on a device; and the merge into `m0-decisions` itself, which
is the owner's.

## What stays pending

As `../../README.md` says: the device sessions that block the M0 exit, the owner's one-line confirmation of Xcode 27.1,
the owner's sign-offs, the ADR approvals (D-6), the M0 exit review, `CLAUDE.md`'s two texts, which are the owner's to put
in with the command above, the owner's merge of this branch, and a review of this fix and of the first two.
