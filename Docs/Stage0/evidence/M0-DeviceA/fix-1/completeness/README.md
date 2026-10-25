# The fix of the review's completeness findings (26 October 2026)

**What this is.** The agent review that read `m0-sessions` at `8082bdb6`, the update of 24 October 2026 (`../../README.md`,
`../../instructions/`) with its assembly (`../../assembly/`), had a completeness lens too, and the orchestrating
session's workflow relayed its findings, DA-01 to DA-09, to this fix, with the product owner's request "keep going"
([`relayed-findings.md`](relayed-findings.md), verbatim). The fixes of the same review's fidelity findings
([`../README.md`](../README.md), integration log section 29) and accuracy findings ([`../accuracy/README.md`](../accuracy/README.md),
section 30) came first; this one was made after them, by an agent on `m0-sessions`, from `ec91f66a`, the second fix's
last commit, in a worktree of its own, on 26 October 2026 on the build Mac's clock (25 October UTC). The task named
`ec91f66a` as the commit reviewed; the findings' line numbers and quoted texts are those of `8082bdb6`
([`checks/finding-lines.log`](checks/finding-lines.log)), and the first two fixes had answered several of them, wholly
or in part, before this one began. Integration log section 31 is its record; the gate summary records it in Section
6.2 and Section 6.3, items 131-140. Agent-written; not reviewed; human sign-off pending. Nothing here is a device
result, a role sign-off, an ADR approval (decision D-6) or the M0 exit: no device was used. To judge the merge and the
commands DA-01 names, this fix read the changes `m0-decisions` makes to the runbook, the G0.5 recovery checklist, the
session log and `Spikes/G05-Recovery`, and its logs print, of the session log there, only the first six cells of its
dated rows (when, by whom, from which commit, on which device); it records none of the owner's sittings' results here
and infers none.

## The findings, and what was done

| Finding | What was done |
| --- | --- |
| DA-01 (blocker): the owner's branch and checkout instructions described a state the update's own evidence showed false; following them would have moved the sittings in progress to a branch without their records or `DeviceTests`, and the runbook's 8.10 sends device A to 1.2's commands, which `m0-decisions` changed during the sittings | The first two fixes had brought run 1's step 1 (both places, with the case for a checkout on another branch, which waits for the merge), the runbook's header, the three checklists' setup lines and integration log 28.1 in line, with a check that judges the branch state (FID-DA-01, ACC-01). Left, and done here: the runbook's 1.2 has a dated note that on `m0-decisions` its two commands, 6.3's item 1 and correction C41's text run the recovery suite on the phone through `Spikes/G05-Recovery/DeviceTests` (commit `4be1a1a4` there), while this branch keeps the earlier commands until the merge; its 6.3 and 8.10, its 0.3, step 1, and the gate summary's item 1, step 1, point to the note (until the merge, the commands of the runbook on the checkout's branch). The branches read again ([`checks/branch-state.log`](checks/branch-state.log)); the merge computed and not made ([`checks/merges.log`](checks/merges.log)). **Not done here: the merge itself** (below). `CLAUDE.md`'s milestone paragraph still calls `m0-decisions` behind `main`: not changed here (below, with the text asked) |
| DA-02 (major): texts said that no device step had run; and the records give phone B's iOS as 26.7 (23H24) where the sittings on `m0-decisions` give 27.0.1 (24A446) | The texts were answered by the first two fixes (FID-DA-01, ACC-01), and the judged branch check fails on any live text that says so without saying where: checked again ([`checks/branch-texts.log`](checks/branch-texts.log)). Left, and done here: the runbook's 1.1 row B has a dated note on phone B's build as the sittings record it, which is settled with the owner at the merge; plan 19.1 ("on iOS 26.7"), ADR-0001's Test devices and the G0.4 and G0.5 recovery checklists, which give the earlier build, are left until then |
| DA-03 (major): the session log's rows 1 and 8 predate 24 October 2026, and its opening says that no device step has been run, and the owner's steps did not say so | The runbook's Section 2 and the gate summary's item 1 now say that item 1 and the runbook's Session 8 supersede rows 1 and 8 until their new text (`../../assembly/README.md`) is applied, and that the sittings are logged on `m0-decisions`, whose log the merge brings here. The log itself is left as it is: the owner's record, changed on `m0-decisions` since |
| DA-04: the release-notes check called awaited in the ADR index, plan D01, ADR-0001's Status and `CLAUDE.md` | Answered by the first two fixes but for `CLAUDE.md` (FID-DA-06, ACC-06): checked again ([`checks/recheck-da.log`](checks/recheck-da.log), item release-notes, which passes on `ec91f66a`'s tree too); nothing changed. `CLAUDE.md`'s toolchain line: not changed here (below, with the text asked) |
| DA-05: ADR-0014's dated note routes R4-01 and R4-02 through `m0-decisions` | ADR-0014's open items now open with a dated note on `m0-sessions` (agent work starts from it and is merged into it between sittings; the work on R4-01 and R4-02 runs on `m0-exit-prep` and is merged into `m0-sessions` once reviewed), standing apart from the item, which the `m0-exit-prep` run changes: computed and not made, that run's merge conflicts in the same files with or without this note, ADR-0014 not among them ([`checks/merges.log`](checks/merges.log)) |
| DA-06: step 1 of 8.10 called independent of the chip, though its pass includes the save-latency test's 200 ms expectation | Session 8's opening, 8.10 and the D-2 note now say that the lines of 8.10's step 1 (the classes, the SQLite version, the pragmas) do not depend on the chip and that its pass rests in part on the 13 mini's speed (`Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DurabilityTests.swift`, `latency()`); no outcome changes |
| DA-07: 0.8's note named no commit, and its folder-wide check would call for a run for `DeviceTests`, which the drop-in does not build | The commits were named by the first fix (FID-DA-03). Left, and done here: 0.8's rule sets `DeviceTests` apart (output under it alone needs nothing; the same command with `':(exclude)Spikes/G05-Recovery/DeviceTests'` leaves it out), its command kept; 0.8's note, the runbook's 0.3, step 1, and the gate summary's item 1, step 1, and item 2 no longer say that 0.8 runs again after the merge. Read from the drop-in and the lock harness's checks: they build and test the package from its manifest (its targets in SwiftPM's default folders under `Sources` and `Tests`, no path named), its lock, its manifest checker and the lock harness, and name no `DeviceTests`, which is a project of its own that compiles the package's tests into an app for the phone ([`checks/dropin-paths.log`](checks/dropin-paths.log), part 1b). The check that sets it apart prints nothing for this fix's head and for the merge of `m0-decisions` into it, computed and not made |
| DA-08: ADR-0013's open item without the note on G0.6 step 12 on device A in M3 | Answered by the first fix (FID-DA-05): checked again (`checks/recheck-da.log`, item step-12, which passes on `ec91f66a`'s tree too); nothing changed |
| DA-09: nowhere to put the owner's one-line Xcode confirmation while ADR-0001 is the open `m0-exit-prep` run's | The gate summary's item 1, step 7, the runbook's 0.2 and its technical-lead part: the line goes in the session log's row for run 1, on the branch the checkout is on, and is copied into ADR-0001's open item for the technical lead once `m0-exit-prep` is merged into `m0-sessions` |

## Not done here: the reconciliation of `m0-decisions` with `m0-sessions`

DA-01 offers the reconciliation or a record of why not; the first two fixes recorded why not (integration log 29.2 and
30.2), and so does this one (31.2). As read here, `m0-decisions` is still at `c72247a6` and the checkout still on it;
its last commit, at 17:33 UTC on 25 October 2026, is titled "Record setup checks and the audio device run in progress",
so a sitting may still be running; the merge brings the sittings' results into these records, which would then have to
record them, committing and recording a sitting's results being the owner's or an agent's the owner asks; and phone B's
build is to be settled with the owner (DA-02). One reason of 29.2 no longer holds: the drop-in's run on `9cdb0a02`
stands for `DeviceTests` (DA-07). Computed and not made, the merge gives no conflict with this fix's documents commit.
It stays the orchestrating session's, with the owner, between sittings.

## Asked of the owner, or the orchestrating session: `CLAUDE.md`

No agent changes `CLAUDE.md` on a workflow's request (integration log 29.3). Its pin is unchanged by either text; after
a change, `Scripts/ci.d/12-dependency-lock.sh`, which compares the toolchain line's pin with the inventory's, runs again.

- **The milestone paragraph** (DA-01): replace "Never build on `m0-integrate` or `m0-decisions`: both are behind `main`."
  with "Never build on `m0-integrate`, which is behind `main`, nor on `m0-decisions` once its commits after `044ed3cf`
  are merged into `m0-sessions`: until that merge, the product owner's first sittings, from 25 October 2026 (UTC), are
  recorded on `m0-decisions`, and the sessions' checkout stays on it (`Docs/Stage0/M0-device-runbook.md` 0.3, step 1)."
- **The toolchain line** (DA-04): replace "whether 27A9275 is the non-beta release awaits a check of Apple's release
  notes" with "whether 27A9275 is the non-beta release awaits the technical lead's one-line confirmation of Apple's
  pages, which the orchestrating session read on 24 October 2026 and which list Xcode 27.1 (27A9275) as released, with
  no beta or release-candidate label (`Docs/Stage0/M0-device-runbook.md` 0.2)".

Also left as they were: the session log (DA-03); plan 19.1, ADR-0001's Test devices and the G0.4 and G0.5 recovery
checklists, on phone B's build (DA-02); the G0.5 recovery checklist's commands for steps 1, 2.4 and 4, which the merge of
`m0-decisions` changes with the runbook's; ADR-0014's item on R4-01 and R4-02 and ADR-0001's own record of the Xcode 27.1
evidence (the `m0-exit-prep` run's); the plan, the amendments and the gate reports, so the second fix's amendments
checker and its mutations apply unchanged.

## Files

| Path | What it is |
| --- | --- |
| [`relayed-findings.md`](relayed-findings.md) | What was relayed to this fix: the request, the task, and the nine findings verbatim |
| [`commands/finding-lines.py`](commands/finding-lines.py) → [`checks/finding-lines.log`](checks/finding-lines.log) | Every line the findings cite, read at `8082bdb6` with `git show`, holds the text they quote (two quotations read as the texts they paraphrase), every text they name without a line is in its file, and their seven claims about refs and other commits hold |
| `../commands/branch-state.sh` → [`checks/branch-state.log`](checks/branch-state.log) | The first fix's read of the branches, unchanged, run again on this fix's documents commit |
| `../accuracy/commands/branch-texts.py` → [`checks/branch-texts.log`](checks/branch-texts.log) | The second fix's judged branch check, unchanged, run again |
| [`commands/dropin-paths.sh`](commands/dropin-paths.sh) → [`checks/dropin-paths.log`](checks/dropin-paths.log) | Runbook 0.8: the drop-in's paths, unchanged from `9cdb0a02` to `6cede84a`, `5e455f70`, `8082bdb6`, `ec91f66a` and HEAD; what in `Spikes/G05-Recovery` the drop-in uses; what `m0-decisions`, and its merge into HEAD, computed and not made, bring under those paths, with and without the setting apart of `DeviceTests`; neither file `m0-exit-prep` changes named by the drop-in. The successor of the first fix's |
| [`commands/merges.sh`](commands/merges.sh) → [`checks/merges.log`](checks/merges.log) | The two merges `m0-sessions` waits for, computed and not made: `m0-decisions` into HEAD, and `m0-exit-prep`, as it stood when read, into HEAD and into `ec91f66a` |
| [`commands/recheck-da.py`](commands/recheck-da.py) → [`checks/recheck-da.log`](checks/recheck-da.log) | This fix's recheck: one item per finding and one for the review status; its control, on `ec91f66a`'s tree, must report every item but release-notes and step-12 |
| [`commands/gate-checks.sh`](commands/gate-checks.sh) → [`checks/gate-checks.log`](checks/gate-checks.log) | The gate checks of this fix, the successor of the second fix's; run last, on the commit that adds every other log |
| [`checks/acc-gate-checks.log`](checks/acc-gate-checks.log) | The second fix's gate checks, unchanged, on this fix: they fail by design (below) |
| [`checks/ci-contracts.log`](checks/ci-contracts.log), [`checks/13-hard-rules.log`](checks/13-hard-rules.log) | `Scripts/ci.sh contracts` and `Scripts/ci.d/13-hard-rules.sh`, through `Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh` |
| [`checks/lfs-checkout.log`](checks/lfs-checkout.log) | This worktree's 777 Git LFS files were pointer files; the follow-up's `commands/lfs-checkout.sh`, unchanged, filled them from the local store, with no download |

## Checks

Each ran on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) on the commit its log's header
names: `lfs-checkout.log` on `ec91f66a`, before any change; the others on the fix's last documents commit, with no
uncommitted file (`acc-gate-checks.log`, `finding-lines.log`, `branch-state.log` and `ci-contracts.log` first), except
that `branch-texts.log`, `dropin-paths.log` and `merges.log` ran with `branch-state.log` in place, `recheck-da.log` with
those four, and `13-hard-rules.log` last, with every other log in place and not yet committed, so that the audit read
them too (each header counts its uncommitted paths); and the gate checks on the commit that adds every other log. Dry
runs on the uncommitted tree came first. Other jobs shared the Mac (the load averages in the logs), so no timing here is
a result. No simulator was created or used, nothing played audio, no device was contacted, nothing was fetched from or
pushed to a git remote, and no page was read over the network.

| Check | Result | Log |
| --- | --- | --- |
| The findings' cited lines and claims | All 61 citations hold their text at `8082bdb6`, each on the line cited; the 6 texts named without a line are there; the 7 claims hold | `checks/finding-lines.log` |
| The branches, read-only | The checkout on `m0-decisions` at `c72247a6`, 8 commits past `044ed3cf` and `main`, not behind `main`; the session log there with four sittings of the owner's, on phone B, iOS 27.0.1 (24A446); a merge of `m0-decisions` into this fix's documents commit without a conflict | `checks/branch-state.log` |
| The judged branch check | Passes: no live text calls `m0-decisions` behind `main`; it is not merged into `m0-sessions`, and run 1's step 1 has the case for a checkout on another branch, which the checkout is; no live text says, without saying where, that no device step has run or no device result is recorded | `checks/branch-texts.log` |
| The drop-in's paths | No change from `9cdb0a02` to `6cede84a`, `5e455f70`, `8082bdb6`, `ec91f66a` or this fix's documents commit; neither the drop-in nor the harness checks names `DeviceTests`, and the package's manifest names no path; `m0-decisions`, and its merge into this fix's documents commit, add the four files of `DeviceTests` under those paths and nothing else, and the check that sets it apart prints nothing for both; neither file `m0-exit-prep` changes is named by a file the drop-in runs | `checks/dropin-paths.log` |
| The two merges | `m0-decisions` into this fix's documents commit without a conflict; `m0-exit-prep`, as it stood when read, conflicting in exactly the files it conflicts in into `ec91f66a`, ADR-0014 not among them | `checks/merges.log` |
| This fix's recheck | Pass, 0 of 10 not as stated; the gate checks run its control on `ec91f66a`'s tree, where it reports every item but release-notes and step-12 | `checks/recheck-da.log` |
| `Scripts/ci.sh contracts` (`run-logged.sh`) | Passed: `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts` | `checks/ci-contracts.log` |
| `Scripts/ci.d/13-hard-rules.sh` (`run-logged.sh`) | Passed: the self-test and the audit of every committed and new file, these logs and this fix's scripts among them, 0 findings, 0 stale allowlist entries | `checks/13-hard-rules.log` |
| The gate checks (`commands/gate-checks.sh`) | Exit 0, as below | `checks/gate-checks.log` |
| The second fix's gate checks, unchanged | Fail by design (below) | `checks/acc-gate-checks.log` |

**The gate checks.** Part 1: since `ec91f66a` only the files this fix names and its own folder; nothing outside `Docs/`;
`CLAUDE.md`, the session log, the license inventory, the gate reports, the plan, the amendments and the checklists
unchanged; under `Docs/Stage0/evidence` only this fix's new files and the dated notes in the records part's evidence
README and the first two fixes' READMEs; since `6cede84a` as before; the drop-in's paths (this fix's `dropin-paths.sh`),
the checklists and the session log (no sitting of the owner's on this branch) and the dependency logs; 1h, the judged
branch check passing, with its two controls; and 1i, the two merges as above. Part 2: no LFS file added. Part 3: the
gate summary's paths and 92 rows agree, and its negative control. Part 4: the second fix's amendments checker, 0 failed
checks, its 70 mutations caught and the tree restored; the records part's checker failing on exactly its check 10k, and
the follow-up's fix's on exactly its three, as before; the records check failing on exactly its ADR index check, as
before, and its control; the instructions part's content check passing and the decisions round's version reporting
exactly its three; the step coverage; the correction texts (from `4c73da57` the nine, from `8082bdb6`, `d6315ad3` and
`ec91f66a` nothing); the earlier rechecks that must pass passing, with their controls; the six others reporting exactly
the 17 lines of the second fix's `../accuracy/commands/expected-rechecks.txt`, unchanged; the instructions part's
recheck reporting exactly its floor item; the assembly's recheck reporting exactly agree and state, with its two
controls; the first fix's two checks, its recheck reporting exactly its items checkout, step-0.8 and review, by design
(below), each with its control; the second fix's two checks, each with its control; this fix's two checks, each with
its control. Part 5: `Scripts/ci.sh contracts dependency-lock hard-rules` passing.

**The earlier checks that now report what this fix changed, by design, and why.** Each asserts a text this fix changed
for a finding; this fix's checks assert the new text, and its gate checks require exactly these reports:

- **The first fix's recheck** (`../commands/recheck-fix1.py`): its item checkout requires the runbook's 0.3, step 1,
  to say "so 0.8's check from `9cdb0a02` then lists it and 0.8 runs again after it", and its item step-0.8 requires 0.8's
  note to say that the merge of `m0-decisions` "adds `Spikes/G05-Recovery/DeviceTests` under those paths: after that
  merge the check from `9cdb0a02` lists it, and 0.8 runs again". DA-07 asked for both to change: neither the drop-in nor
  the lock harness's checks builds, copies or runs `DeviceTests`. Its item review reports the State line's clause, as
  on the second fix. `commands/recheck-da.py` (dropin) asserts the new texts.
- **The second fix's gate checks** ([`checks/acc-gate-checks.log`](checks/acc-gate-checks.log), run on this fix's last
  documents commit, with no uncommitted file): part 1a, which allows only the second fix's files since `d6315ad3`, so
  not ADR-0014 or this fix's folder; part 1c, which allows no change under `Docs/Stage0/evidence` but its own new files
  and the dated notes in two READMEs, so not this fix's new files (the dated note in the second fix's own README passes
  there, since that file is one of its own new files since `d6315ad3`); part 3, on the five logs of this fix that the gate summary cites and that the documents commit does not
  hold yet (`branch-state.log`, `dropin-paths.log`, `finding-lines.log`, `gate-checks.log` and `merges.log`; this fix's
  gate checks, on the commit that adds them, find every path); and part 4, for the first fix's recheck above. Their other
  parts pass, part 5 (`Scripts/ci.sh contracts dependency-lock hard-rules`) among them.

What still passes unchanged: the second fix's amendments checker and its mutations, the instructions part's runbook
content check (no marker added: the new texts hold no double-quoted text and no backticked log field or count), the step
coverage, the correction-text check (no line differs from `ec91f66a`), the six earlier rechecks (exactly the 17 lines of
the second fix's list), the assembly's recheck (exactly agree and state, as before), the second fix's recheck and judged
branch check, the follow-up's recheck, the moved-notes checks, both checks of the run's facts, both finding-lines checks
of the drop-in record's rounds and the second fix's recheck of that record, whose sweeps read this fix's Markdown files
too (each new sentence that names the drop-in or step 0.8 with a word of status names `9cdb0a02`).
