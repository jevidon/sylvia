# The fix of the fidelity findings of the review of `m0-records-update` (26 October 2026)

**What this is.** An agent review read `m0-records-update` at `832a3636`, its last commit (`../README.md`), and the
orchestrating session's workflow relayed its fidelity findings, FID-RU-01 to FID-RU-11, to this fix
([`relayed-findings.md`](relayed-findings.md), verbatim). The review's other lenses' findings go to fixes that follow on
the same branch, one at a time; none was relayed here. The fix was made by an agent on `m0-records-update`, from
`832a3636`, in a worktree of its own, on 26 October 2026 (from 07:55 UTC; 20:55 on the build Mac's clock). Integration
log section 42 is its record; the gate summary records it in Section 6.2 and Section 6.3, items 187-198. Agent-written;
not reviewed; human sign-off pending. Nothing here is a device result, a role sign-off, an ADR approval (decision D-6)
or the M0 exit: no device was used, and the owner's records are kept exactly as committed
([`checks/owner-records-intact.log`](checks/owner-records-intact.log)).

## The findings, and what was done

| Finding | What was done |
| --- | --- |
| FID-RU-01 (blocker): the runbook's 0.7 had the owner commit the Mac identity probe's log on `m0-sessions` (from `1d5ac477`, through the merge `4c0fa815`); no check read the branch texts | 0.7 says `m0-decisions` again, as at `c72247a6`, with a history clause. [`commands/retired-branch-texts.py`](commands/retired-branch-texts.py) fails on any live text that names `m0-sessions` as a branch to build from, commit to or merge into (below) |
| FID-RU-02 (major): the gate summary's Section 5.4 bullet on H-1 had the session records committed on `m0-sessions`, and building from it | Restored to `c72247a6`'s wording, with a history clause |
| FID-RU-03 (major): `CLAUDE.md`, as `m0-records-update` would bring it to `m0-decisions`, held `6cede84a`'s paragraph, which says that the M0 work is on `m0-sessions` and that no one should build on `m0-decisions` | `CLAUDE.md` is `m0-decisions`'s, byte for byte as at `c72247a6`: the merge changes nothing in it, and this fix wrote nothing in it (the second of the review's two fixes; integration log 42.2). The owner's step 2, with the texts of [`../claude-md-paragraph.md`](../claude-md-paragraph.md), stays, for the paragraph of 22 October 2026 that `m0-decisions` holds |
| FID-RU-04: three notes of 24 October 2026 in the gate summary gave the `m0-sessions` model with no later note | Each has a later note; the new check found three more clauses of the kind in ADR-0002's Branches, each with a later note now |
| FID-RU-05: five ADRs gave the device-A record as accepted by no review, and ADR-0013 and the index's row of it its fix as not reviewed | Dated notes: the second review of that update, at `c2fd9ece`, accepted its device-A records in three lenses, as relayed |
| FID-RU-06: integration log 41.1 said that `4be1a1a4` changed the G0.5 recovery report | 41.1 names what `git show --stat 4be1a1a4` lists, and `38f9604e` and `d5336111` for the report |
| FID-RU-07: notes on R4-01 and R4-02 read as current after later ones (the gate summary's Section 7, item 1; ADR-0002's Branches) | Section 7's older note is a history clause of the current one; ADR-0002's has a later note |
| FID-RU-08: the gate summary's opening gave G0.4 step 1 as still running | "not finished when last recorded"; 596 words, within the opening's 600 |
| FID-RU-09: the plan's Status line and the gate summary's Section 7 counted four results over Session 1's steps 1.1 to 1.3 | Both name the four checklist steps, with history clauses; the plan within draft 0.8, with a Revised entry |
| FID-RU-10: the G0.6 checklist's step 1 could be read as phone B's OS history | Worded as the checklist's device line B; wording only |
| FID-RU-11: the amendments named the accuracy fix's checker, which fails by design, as the latest | [`commands/check-amendments.py`](commands/check-amendments.py), a new version, with [`commands/mutation-checks.py`](commands/mutation-checks.py); Applied as names it |

With the review, the texts that gave `m0-records-update` as read by no review now say that an agent review read it at
`832a3636` and that this fix has not been reviewed (integration log 42.1 lists them).

## The new check

[`commands/retired-branch-texts.py`](commands/retired-branch-texts.py) reads every live text (`CLAUDE.md`, the
repository README, the plan, the ADRs, the Stage 0 records and checklists, and `m0-records-update`'s evidence READMEs)
and, for every mention of `m0-sessions`, judges its clause: a branch use (build from, commit on, merge into, and the
other forms it lists) is history when the clause is a quotation or carries a mark of history, superseded when a later
note of 26 October 2026 in the same paragraph says that `m0-sessions` is retired, and live otherwise, which fails the
check. The gate summary's Section 6.3 groups and Section 8 bullets of the rounds before `m0-records-update`, and the
integration log's sections 1-40, are read as history by design: each records a round as it was done. Every branch use is
listed with how it was read; with `--all`, every mention. It reads words, not meaning, so a live use phrased in none of
its forms would pass; the listings let a reader look for one. Integration log 42.3 describes it in full.

## Files

| Path | What it is |
| --- | --- |
| [`relayed-findings.md`](relayed-findings.md) | What was relayed to this fix: the task, the state, the rules, and the eleven findings verbatim |
| [`commands/finding-lines.py`](commands/finding-lines.py) → [`checks/finding-lines.log`](checks/finding-lines.log) | Every line the findings cite, read at `832a3636` with `git show`, holds the text they quote, and their claims about other commits hold |
| [`commands/retired-branch-texts.py`](commands/retired-branch-texts.py) → [`checks/retired-branch-texts.log`](checks/retired-branch-texts.log), [`checks/retired-branch-texts-all.log`](checks/retired-branch-texts-all.log) | FID-RU-01's check, on this tree and on its two controls; and every mention it reads |
| [`commands/check-amendments.py`](commands/check-amendments.py), [`commands/mutation-checks.py`](commands/mutation-checks.py) → [`checks/check-amendments.log`](checks/check-amendments.log), [`checks/mutation-checks.log`](checks/mutation-checks.log) | The amendments' checker, `m0-records-update`'s with its check 10k requiring Applied as to name this version (FID-RU-11) and the plan's Status line to name the four results (FID-RU-09); its 70 mutations and three more |
| [`commands/run-checks.sh`](commands/run-checks.sh) | Runs every check below on the documents commit and writes the logs |
| [`checks/`](checks/) | The logs, each headed with its commit, uncommitted paths, time and load |

## Checks

`commands/run-checks.sh` ran every check on this fix's documents commit, with no uncommitted file; the commit after it
adds the logs and nothing else. Host only: the build Mac, macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275). No
simulator was created or used, no device was contacted, nothing played audio and nothing was fetched or pushed. Other
jobs may have shared the Mac (the load averages in the logs), so no timing here is a result. Dry runs on the uncommitted
tree came first.

| Log | What ran | What it must show |
| --- | --- | --- |
| `finding-lines.log` | `commands/finding-lines.py` | All 50 citations and claims hold |
| `retired-branch-texts.log`, `retired-branch-texts-all.log` | `commands/retired-branch-texts.py`: this tree; the controls on `832a3636`'s tree and on a copy of this tree with 0.7's old record | This tree passes; `832a3636`'s fails on exactly the eleven clauses this fix changed (`CLAUDE.md` 2, ADR-0002 3, the runbook's 0.7, the gate summary 5); the copy on 0.7 alone |
| `owner-records-intact.log`, `step-0.8-paths.log` | `../commands/owner-records-intact.py`, `../commands/step-08-paths.sh` | The owner's eight commits as committed; the drop-in's paths unchanged since `9cdb0a02` at `4c0fa815` and at this commit, `DeviceTests` set apart |
| `ci-contracts.log`, `12-dependency-lock.log`, `13-hard-rules.log` | `Scripts/ci.sh contracts`, `Scripts/ci.d/12-dependency-lock.sh`, `Scripts/ci.d/13-hard-rules.sh`, through the re-pin round's `run-logged.sh` | Each passes; the lock check compares `CLAUDE.md`'s toolchain line, now `m0-decisions`'s, with the pin |
| `runbook-content-check.log`, `runbook-coverage.log` | The device-A update's content check, with its controls and limits, and the step coverage | Both pass |
| `correction-texts.log` | `../commands/correction-texts-compare.sh` | HEAD's lines equal those of `c72247a6`, `c3adae68` and `1d5ac477` |
| `check-amendments.log`, `mutation-checks.log` | This fix's checker and its mutations | 0 failed checks; 73 mutations, each caught; the plan and the amendments as committed afterwards |
| `check-amendments-records-update.log` | `../commands/check-amendments.py`, unchanged | Fails exactly its check 10k, on Applied as's pointer to the latest checker, which this fix changed (FID-RU-11), by design |
| `check-amendments-accuracy.log` | `../../M0-DeviceA/fix-1/accuracy/commands/check-amendments.py`, unchanged | Fails exactly its check 10k, as at `m0-records-update` |
| `check-records.log`, `check-records-devicea.log` | `../commands/check-records.py` and `../../M0-DeviceA/commands/check-records.py`, unchanged | The first passes; the second fails exactly its two checks, as at `m0-records-update` |
| `recheck-hon-ep.log`, `decisions-branch.log`, `recheck-own.log`, `gate-checks-exit-prep.log`, `gate-checks-devicea.log` (with their console logs) | The two branches' latest rechecks and gate checks, unchanged | Recorded as they report: each pins texts and states of the branch it was written on; what this fix changed in what they report is in integration log 42.7 (`CLAUDE.md` back to `m0-decisions`'s; the opening's 596 words; this fix's new texts and files) |
| `gate-refresh-check.log` | `../commands/gate-refresh-check.py`, unchanged, run last | Passes: every path the gate summary cites exists, every Section 2 status agrees with its records (passed-host 12, failed 4) |

Not run, and why: the complete CI (outside `Docs/` this fix changed only `CLAUDE.md`, back to `m0-decisions`'s, which
`12-dependency-lock` reads); G0.5 recovery's drop-in (0.8's check finds nothing it uses changed); `resolve-locks.sh` and
`linkage.sh` (they resolve packages, which can reach git remotes); anything on a device.

## What stays pending

As `../README.md` says, with a review of this fix; the review's other lenses' findings go to the fixes that follow.
