# The fix of the review's fidelity findings (26 October 2026)

**What this is.** An agent review read `m0-sessions` at `8082bdb6`, the update of 24 October 2026 (`../README.md`,
`../instructions/`) with its assembly (`../assembly/`), and the orchestrating session's workflow relayed its fidelity
findings, FID-DA-01 to FID-DA-07, to this fix, with the product owner's request "keep going"
([`relayed-findings.md`](relayed-findings.md), verbatim). The review's other lenses' findings go to fixes that follow on
the same branch, one at a time; none was relayed here. The fix was made by an agent on `m0-sessions`, from `8082bdb6`,
in a worktree of its own, on 26 October 2026 on the build Mac's clock (25 October UTC). Integration log section 29 is
its record; the gate summary records it in Section 6.2 and Section 6.3, items 116-123. Agent-written; not reviewed;
human sign-off pending. Nothing here is a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit:
no device was used, and the owner's sittings recorded on `m0-decisions` are not read beyond the first six cells of the
session log's dated rows there (when, by whom, from which commit, on which device).

*(26 October 2026: the same review's accuracy findings, ACC-01 to ACC-06, were relayed to a second fix that followed on
the same branch, from `d6315ad3`, this fix's last commit; its record is [`accuracy/`](accuracy/README.md) and integration
log section 30. That fix read more of `m0-decisions` than this one did, to judge the merge ACC-01 asks for, and records
none of the sittings' results either.)*

*(26 October 2026: the same review's completeness findings, DA-01 to DA-09, were relayed to a third fix that followed on
the same branch, from `ec91f66a`, the second fix's last commit; its record is [`completeness/`](completeness/README.md)
and integration log section 31. It changed what this fix had the owner's instructions say of 0.8 after the merge of
`m0-decisions` (FID-DA-03): neither the drop-in nor the lock harness's checks builds, copies or runs `DeviceTests`, so
the drop-in's run on `9cdb0a02` stands for it.)*

*(26 October 2026: the same review's owner-readability findings, OWN-DA-01 to OWN-DA-09, were relayed to a fourth fix
that followed on the same branch, from `caf75a84`, the third fix's last commit; its record is [`owner/`](owner/README.md)
and integration log section 32. It too left the merge of `m0-decisions` into `m0-sessions` to the orchestrating session,
with the owner, between sittings, and records none of the sittings' results.)*

## The findings, and what was done

| Finding | What was done |
| --- | --- |
| FID-DA-01 (major): the run-1 checkout steps, the runbook's header, the repository README and integration log 28.1 described `~/Git/sylvia-sessions` as on `main` at `96bdc7e9`, while the assembly had found it on `m0-decisions` at `c72247a6`, where the owner's first sittings are recorded | The branches read again ([`checks/branch-state.log`](checks/branch-state.log)): the same state; the session log there records sittings on phone B on 25 October 2026 UTC, built from `96bdc7e9` and later commits of `m0-decisions`, phone B on iOS 27.0.1 (24A446); the runbook at `96bdc7e9` told the owner to check out `m0-decisions` and commit the records there; a merge into this branch computed without a conflict. The gate summary's item 1, step 1, and the runbook's 0.3, step 1, now say what to do when the checkout reads another branch (no switch by the owner; the orchestrating session switches it once the update is reviewed and that branch's commits are merged into `m0-sessions`, after which 0.8 runs again; until then steps 4 and 6 apply to the branch the checkout is on), what it held when read, and no longer that `m0-decisions` is behind `main` (nor do the setup lines of the G0.4, G0.5 AI and G0.5 recovery checklists). The runbook's header no longer says that nothing in it has been run on a device, and the gate summary (its opening, Section 2's introduction, Section 7) and the Stage 0 README no longer say that no device step has run; the repository README and 28.1 give the state as found; ADR-0002's Branches has a dated note. Each text changed keeps a dated note of what it said. **Not done here: the reconciliation itself**, the merge of `m0-decisions` into `m0-sessions` the finding asks before the checkout moves (below) |
| FID-DA-02 (major): four texts gave the lack of an A13 phone in M0 as a fact | The G0.2 checklist's note on step 22.5, the runbook's 2.12 and the G0.1 EPUB and G0.6 checklists' device-A lines now give the owner's decision (the A13 floor left for M8, so no A13 phone measured in M0), each with a dated note; step 22.5's repeat on the oldest supported iPhone waits for M8 with the floor |
| FID-DA-03: runbook 0.8's check of 26 October 2026 named no commit | 0.8 names `5e455f70`, the assembly's, and this fix's check on `6cede84a`, `5e455f70`, `8082bdb6` and the fix's head ([`checks/dropin-paths.log`](checks/dropin-paths.log)), and that the merge of `m0-decisions` adds `DeviceTests` under its paths; the gate summary's item 2 says the same |
| FID-DA-04: work that ran to 26 October 2026 dated 24 October; the ADR index's row of ADR-0013 dated the 13 mini choice 22 October | The Stage 0 README's heading and sentence, the gate summary's bullet on pull request #6 and its line over items 104-110, and the runbook's Who wrote it give both days; the index row dates each decision |
| FID-DA-05: ADR-0001 said the narrower exception applies to no G0.6 step on device A | ADR-0001 limits that to the M0 steps and applies it to G0.6 step 12's repeat on A in M3; ADR-0013's open item on devices has a dated note on step 12; `../README.md` a dated note |
| FID-DA-06: ADR-0001 and the ADR index said that Apple's release notes were unread | ADR-0001's Status and technical lead's open item, and the index's row, say that Apple's pages were read on 24 October 2026 and that the technical lead's one-line confirmation remains; the record of the evidence in ADR-0001 stays the `m0-exit-prep` run's (its merge will conflict on those two lines of ADR-0001: keep that run's record) |
| FID-DA-07: two texts made `m0-sessions` from `6cede84a` | The gate summary's bullet and `../instructions/README.md` say it was made from `5aec2518`, `6cede84a` committed on it |

With the review, the records that gave the update and its assembly as not reviewed now say that an agent review read them
at `8082bdb6`, and that this fix has not been reviewed (integration log 29.1, its last paragraph, lists them). The ADR
index's status column, whose cells now give the review of 26 October 2026, is dated 26 October 2026.

## Not done here: the reconciliation of `m0-decisions` with `m0-sessions`

FID-DA-01 asks that `m0-decisions` be reconciled with `m0-sessions` before the sessions' checkout moves. This fix did not
merge it (integration log 29.2): the owner's sittings may still be running (the last commit there, at 17:33 UTC on 25
October 2026, is titled "Record setup checks and the audio device run in progress"), and the runbook merges into the
sessions' branch only between sittings; the merge brings the owner's own records and results into these records (the
session log, device evidence, changed rows of the G0.2, G0.5 AI and G0.5 recovery reports, which the gate summary's
Section 2 copies), which the owner, or an agent the owner asks, records (runbook 0.3, step 6); after it 0.8, last run on
`9cdb0a02`, runs again on the build Mac with its screen unlocked, which no agent arranges, and the license inventory's new lock goes through
`12-dependency-lock`; and phone B's iOS there, 27.0.1 (24A446), is to be settled against the 26.7 (23H24) these records
give. Read-only, the merge of `c72247a6` into this fix's head gives no conflict ([`checks/branch-state.log`](checks/branch-state.log)).
It stays the orchestrating session's, with the owner, between sittings; until then the owner's instructions say to leave
the checkout on `m0-decisions` and keep each sitting's records there.

Also left as they were: the session log (the owner's record; its rows 1 and 8 are still asked of the owner); `CLAUDE.md`,
which still says never to build on `m0-decisions` because it is behind `main`, and still gives the release notes as
unchecked (the owner's or the orchestrating session's to change); the plan, the amendments and the gate reports, whose
notes of 24 October 2026 still give the update as not reviewed (a change within plan draft 0.8 for that alone would need a
new version of the amendments' checker and its mutations); ADR-0014's dated note and the record of the Xcode 27.1
evidence in ADR-0001 (the `m0-exit-prep` run's).

## Files

| Path | What it is |
| --- | --- |
| [`relayed-findings.md`](relayed-findings.md) | What was relayed to this fix: the request, the task, and the seven findings verbatim |
| [`commands/finding-lines.py`](commands/finding-lines.py) → [`checks/finding-lines.log`](checks/finding-lines.log) | Every line the findings cite, read at `8082bdb6` with `git show`, holds the text they name, and their five claims about other commits hold |
| [`commands/branch-state.sh`](commands/branch-state.sh) → [`checks/branch-state.log`](checks/branch-state.log) | The branches and the sessions' checkout, read-only: the successor of `../assembly/commands/branch-state.sh`, with the parent of the first commit after `044ed3cf`, the first six cells of the dated rows of the session log on `m0-decisions`, runbook 0.3's steps 1 and 6 at `96bdc7e9`, and a merge computed and not made |
| [`commands/dropin-paths.sh`](commands/dropin-paths.sh) → [`checks/dropin-paths.log`](checks/dropin-paths.log) | Runbook 0.8: the drop-in's paths, unchanged from `9cdb0a02` to `6cede84a`, `5e455f70`, `8082bdb6` and HEAD, each named in full; what `m0-decisions` would add under them; neither file `m0-exit-prep` changes named by the drop-in |
| [`commands/recheck-fix1.py`](commands/recheck-fix1.py) → [`checks/recheck-fix1.log`](checks/recheck-fix1.log) | This fix's recheck: one item per finding and one for the review status; its control, on `8082bdb6`'s tree, must report all eight |
| [`commands/expected-rechecks.txt`](commands/expected-rechecks.txt) | What each earlier recheck that reads a text the update or this fix changed must report on this tree, exactly, and why |
| [`commands/gate-checks.sh`](commands/gate-checks.sh) → [`checks/gate-checks.log`](checks/gate-checks.log) | The gate checks of this fix, the successor of the assembly's; run last, on the commit that adds every other log |
| [`checks/assembly-gate-checks.log`](checks/assembly-gate-checks.log) | The assembly's gate checks, unchanged, on this fix: they fail by design (below) |
| [`checks/ci-contracts.log`](checks/ci-contracts.log), [`checks/13-hard-rules.log`](checks/13-hard-rules.log) | `Scripts/ci.sh contracts` and `Scripts/ci.d/13-hard-rules.sh`, through `Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh` |
| [`checks/lfs-checkout.log`](checks/lfs-checkout.log) | This worktree's 777 Git LFS files were pointer files; the follow-up's `commands/lfs-checkout.sh`, unchanged, filled them from the local store, with no download |

## Checks

Each ran on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) on the commit its log's header
names: `lfs-checkout.log` on `8082bdb6`, before any change; the others on the fix's last documents commit, with no
uncommitted file (`assembly-gate-checks.log`, `finding-lines.log` and `ci-contracts.log` first), except that
`dropin-paths.log` ran with `branch-state.log` in place, `recheck-fix1.log` with both, and `13-hard-rules.log` last,
with every other log in place and not yet committed, so that the audit read them too (each header counts its uncommitted
paths); and the gate checks on the commit that adds every other log. Dry runs on the
uncommitted tree came first. Other jobs shared the Mac (the load averages in the logs), so no timing here is a result. No
simulator was created or used, nothing played audio, no device was contacted, nothing was fetched from or pushed to a git
remote, and no page was read over the network.

| Check | Result | Log |
| --- | --- | --- |
| The review's cited lines and claims | All 39 citations hold their text at `8082bdb6`, and the 5 claims hold | `checks/finding-lines.log` |
| The branches, read-only | The checkout on `m0-decisions` at `c72247a6`, 8 commits past `044ed3cf`, the first of them made on it; the session log there: 6 dated rows, the 4 of 25 October 2026 sittings on phone B (iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446)) by "Codex with Justin Evidon"; runbook 0.3 at `96bdc7e9` sending the owner to `m0-decisions` (steps 1 and 6); a merge of `m0-decisions` into this fix's head without a conflict | `checks/branch-state.log` |
| The drop-in's paths | No change from `9cdb0a02` to `6cede84a`, `5e455f70`, `8082bdb6` or HEAD; `m0-decisions` would add `Spikes/G05-Recovery/DeviceTests` (4 files), which neither the drop-in nor the harness checks name; neither file `m0-exit-prep` changes is named by a file the drop-in runs | `checks/dropin-paths.log` |
| This fix's recheck | Pass, 0 of 8 not as stated; the gate checks run its control on `8082bdb6`'s tree, where it reports all eight | `checks/recheck-fix1.log` |
| `Scripts/ci.sh contracts` (`run-logged.sh`) | Passed: `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts` | `checks/ci-contracts.log` |
| `Scripts/ci.d/13-hard-rules.sh` (`run-logged.sh`) | Passed: the self-test and the audit of every committed and new file, these logs and this fix's scripts among them, 0 findings, 0 stale allowlist entries | `checks/13-hard-rules.log` |
| The gate checks (`commands/gate-checks.sh`) | Exit 0. Part 1: since `8082bdb6` only the files this fix names and its own folder, nothing outside `Docs/` but `README.md`, `CLAUDE.md`, the session log, the license inventory, the plan, the amendments and the gate reports unchanged, under `Docs/Stage0/evidence` only this fix's new files and the dated notes in the update's three READMEs; since `6cede84a` the same as the assembly had it; the drop-in's paths, the checklists, the session log (no sitting of the owner's on this branch), the dependency logs, and the branches as found. Part 2: no LFS file added. Part 3: the gate summary's paths and 92 rows agree, and its negative control. Part 4: the records part's amendments checker, 0 failed checks, its 66 mutations caught and the tree restored, the follow-up's fix's checker failing on exactly its three; the records check failing on exactly its ADR index check, by design, and its control; the instructions part's content check passing and the decisions round's version reporting exactly its three; the step coverage; the correction texts (from `4c73da57` the nine, from `8082bdb6` nothing); the earlier rechecks that must pass passing, with their controls; the six others reporting exactly the 17 lines of `commands/expected-rechecks.txt`; the instructions part's recheck reporting exactly its floor item; the assembly's recheck reporting exactly agree and state, by design, with its two controls; this fix's two checks, each with its control. Part 5: `Scripts/ci.sh contracts dependency-lock hard-rules` passing | `checks/gate-checks.log` |
| The assembly's gate checks, unchanged | Fail by design (below) | `checks/assembly-gate-checks.log` |

**The earlier checks that now report what this fix changed, by design, and why.** Each asserts a text this fix changed
for a finding or for the review's record; this fix's checks assert the new text, and its gate checks require exactly
these reports:

- **The records part's check** (`../commands/check-records.py`): its check of the ADR index requires the status column
  dated 24 October 2026. FID4-04 had the column's date follow its cells, and the cells now give the review of 26 October
  2026 and this fix (FID-DA-06's release notes, FID-DA-04's and FID-DA-05's row of ADR-0013), so the column reads
  "Status (26 October 2026)", with a line of history; `commands/recheck-fix1.py` (release-notes) asserts it.
- **The assembly's recheck** (`../assembly/commands/recheck-assembly.py`): its item agree requires ADR-0001's clause
  "ADR-0013 (it does not apply to G0.6's steps on device A, which depend on the screen)", which FID-DA-05 asked to narrow
  to the M0 steps; its item state requires the repository README's sentence that the device sessions use `m0-sessions`
  since 24 October 2026, which FID-DA-01 asked to bring in line with the sittings recorded on `m0-decisions`, and the
  runbook's Who wrote it saying that the update and its assembly were not reviewed, which the review made untrue. Every
  other text of those two items is unchanged: the gate checks require each item's list of missing texts to be exactly
  those. `commands/recheck-fix1.py` asserts the new texts (step-12, checkout, review).
- **The drop-in record's recheck** (`../../M0-Decisions/unlocked-record/commands/recheck-unlocked.py`): it finds the
  runbook's header line by its first words, which FID-DA-01 asked to change; the two texts it reads in that line are
  kept, and `commands/recheck-fix1.py` reads them under the new first words. **The fix's recheck of that record**
  (`../../M0-Decisions/unlocked-record/round-2/commands/recheck-unl.py`): its UNL-02 line gives the State line's word
  count, now 199 (198 before; at most 200), the State line's last clause now giving the update's fix, not the update, as
  not reviewed. Both are in `commands/expected-rechecks.txt`, with the assembly's 16 lines otherwise unchanged.
- **The assembly's gate checks** (`checks/assembly-gate-checks.log`, run on the fix's last documents commit, with no
  uncommitted file): part 1a, which allows only the two parts' files and the assembly's since `6cede84a`, so not this
  fix's folder; part 3, on the four logs of this fix that the gate summary cites and that the documents commit does not
  hold yet (`branch-state.log`, `dropin-paths.log`, `finding-lines.log` and `gate-checks.log`; this fix's gate checks,
  on the commit that adds them, find every path); and part 4, for the three reports above (the records check, the six
  rechecks' 17 lines against its 16, and its own recheck's agree and state). Their other parts pass.

What still passes unchanged: the records part's amendments checker and its 66 mutations, the instructions part's runbook
content check, the step coverage, the correction-text check (no line differs from `8082bdb6`), the follow-up's recheck,
the moved-notes checks, both checks of the run's facts, both finding-lines checks of the drop-in record's rounds, the
second fix's recheck of that record (its sweep reads this fix's Markdown files too), the instructions part's recheck
(exactly its floor item, as before), and the gate summary's paths and statuses.
