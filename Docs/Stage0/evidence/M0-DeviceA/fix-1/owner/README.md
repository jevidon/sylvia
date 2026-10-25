# The fix of the review's owner-readability findings (26 October 2026)

**What this is.** The agent review that read `m0-sessions` at `8082bdb6`, the update of 24 October 2026 (`../../README.md`,
`../../instructions/`) with its assembly (`../../assembly/`), had an owner-readability lens too, and the orchestrating
session's workflow relayed its findings, OWN-DA-01 to OWN-DA-09, to this fix, with the product owner's request "keep
going" ([`relayed-findings.md`](relayed-findings.md), verbatim). The fixes of the same review's fidelity findings
([`../README.md`](../README.md), integration log section 29), accuracy findings ([`../accuracy/README.md`](../accuracy/README.md),
section 30) and completeness findings ([`../completeness/README.md`](../completeness/README.md), section 31) came first;
this one was made after them, by an agent on `m0-sessions`, from `caf75a84`, the third fix's last commit, in a worktree
of its own, on 26 October 2026 on the build Mac's clock (25 October UTC). The task named `caf75a84` as the commit
reviewed; the findings' line numbers and quoted texts are those of `8082bdb6` ([`checks/finding-lines.log`](checks/finding-lines.log)),
and the first three fixes had answered parts of OWN-DA-01, OWN-DA-02, OWN-DA-04 and OWN-DA-05 before this one began.
Integration log section 32 is its record; the gate summary records it in Section 6.2 and Section 6.3, items 141-150.
Agent-written; not reviewed; human sign-off pending. Nothing here is a device result, a role sign-off, an ADR approval
(decision D-6) or the M0 exit: no device was used. To check the findings' claims and the Xcode message the runbook's 1.5
now quotes, this fix read, on `m0-decisions`, the first six cells of the session log's dated rows (when, by whom, from
which commit, on which device), the setup record's line on phone B, the log of the recovery suite's first device
attempt and the texts OWN-DA-03 quotes from that attempt's record, and the files `DeviceTests` adds; it records none of
the owner's sittings' results here and infers none.

## The findings, and what was done

| Finding | What was done |
| --- | --- |
| OWN-DA-01 (blocker): run 1's step 1 and the runbook's 0.3 had the sessions' checkout switched to `m0-sessions` on the review, or by the owner, while it is on `m0-decisions` with the owner's first sittings, and left out the reconciliation that must come first | The first three fixes had answered the texts (the case for a checkout on another branch, waiting for the merge; the header; the checklists' setup lines; 1.2's note on the commands). Left, and done here: the runbook's 0.3, step 1, now says that the merge is made between sittings, once the owner says the sitting in progress is done, that the switch waits for it, not only for the review, and that until then an agent the owner asks starts from `m0-sessions` without the sittings' records, so to ask for the merge first if one is to work from them; the gate summary's item 1, step 1, says it in short (its history note moved to item 141, so that the step stays within the 400 words the follow-up's check of OWN4-09 allows); the Stage 0 README says when the merge is made. The branches read again ([`checks/branch-state.log`](checks/branch-state.log)); the merges computed and not made ([`checks/merges.log`](checks/merges.log)). **Not done here: the merge itself** (below) |
| OWN-DA-02 (major): texts said that no device step had run | Answered but for the session log by the first two fixes. Left, and done here: the gate summary's opening says where the sittings are recorded and that they are unreviewed (within the 600 words the follow-up's check of OWN5-05 allows), and it, Section 5.1, Section 7, the runbook's header and the Stage 0 README say that their records have not been reviewed. The session log is left to the merge, which brings `m0-decisions`'s log, whose opening records the sittings |
| OWN-DA-03 (major): 1.2, 6.3, 8.10 and the G0.5 recovery checklist give a device command the owner's run found cannot run on a phone, and 1.5 said that is only known when Session 1 runs it | The runbook's 1.5 now says what Session 1 found, Xcode's message quoted as the log on `m0-decisions` has it (`commands/recheck-own.py` compares them), with that log, the commit that added `DeviceTests` there (`4be1a1a4`), that it has not been reviewed, and that until the merge 1.2, 6.3 and 8.10 run with the commands of the checkout's branch; the G0.5 recovery checklist's setup has a note that says the same of its steps 1, 2.4 and 4 (one added line, wording only; the runbook's 0.3, step 7, lists it among the changes that need no repeat). **Not done here: a reviewed device host on this branch**, which comes with the merge (below) |
| OWN-DA-04 (major): no usable place for the owner's one-line Xcode confirmation, and ADR-0001 still said the notes were unread | Answered but for ADR-0001's open item and D-3's note by the first and third fixes. Left, and done here: ADR-0001's open item for the technical lead and the runbook's D-3 note now say that until `m0-exit-prep` is merged into `m0-sessions` the line is written in the session log's row for run 1 and copied into ADR-0001 with or after that merge; that run's merge, computed, conflicts in the same files as before this fix, ADR-0001 among them already ([`checks/merges.log`](checks/merges.log)) |
| OWN-DA-05 (major): the session log's rows 1 and 8 predate 24 October 2026, and Section 1 listed no edit left to the owner | The third fix had item 1 and the runbook's Section 2 say that item 1 and Session 8 supersede the two rows. Left, and done here: the gate summary's item 4 now lists the edits of the records left to the owner (the session log, with the merge; `CLAUDE.md`'s milestone paragraph and toolchain line, with the texts the third fix's README gives), and item 1's opening and the runbook's Section 2 point to it. **Not done here: the log's change itself**, with the merge (below) |
| OWN-DA-06: pull request #6's merge, and the second reading of Apple's pages, dated against the records' UTC convention | `git log -1 --format=%ad --date=iso 96bdc7e9` gives 2026-10-24 04:34:37 +1300, 23 October 2026 at 15:34 UTC; the reading's log, 2026-10-23T17:49:55Z. Each text the finding names, and those beside them, now gives the UTC date, with its time but in the gate summary's opening (kept within its 600 words), and the build Mac's date beside it, with dated notes; the gate summary's item 107 keeps its words, with a dated note |
| OWN-DA-07: the runbook's 1.1 row A said that iOS 27 support of the 13 mini was not checked | Apple's iPhone User Guide page "iPhone models compatible with iOS 27", read on 25 October 2026 UTC, lists the iPhone 13 mini ([`checks/apple-ios27-page.log`](checks/apple-ios27-page.log)); the row cites it, and its first cell allows 27.x |
| OWN-DA-08: an agent cannot merge into `m0-sessions` from its own worktree once the owner's checkout has it | The runbook's 0.3, step 5, and the gate summary's item 1, step 5, say that the merge is then made in `~/Git/sylvia-sessions` itself, by the owner or an agent the owner asks to work there; the command the assembly's recheck reads kept |
| OWN-DA-09: the gate summary's D01 row called device A the baseline, unqualified | The row's note now says the small-screen baseline, in the past tense, citing the plan's wording |

## Not done here: the reconciliation of `m0-decisions` with `m0-sessions`

OWN-DA-01 asks for the reconciliation, and OWN-DA-03 and OWN-DA-05 for a reviewed device host and the session log's new
rows with it. This fix did not merge `m0-decisions` either (integration log 32.2). As read here, `m0-decisions` is still
at `c72247a6`, with nothing committed on it since 17:33 UTC on 25 October 2026, its last commit titled "Record setup
checks and the audio device run in progress", and the checkout still on it ([`checks/branch-state.log`](checks/branch-state.log)).
The sitting those commits record is the runbook's Session 1, about 6-8 h elapsed by the runbook's estimate, begun at
17:12 UTC by the session log's date cell there; nothing tells an agent that it is done, and the owner's own rule has an
agent commit a sitting's records only once the owner says so (the runbook's 0.3, step 6), which this fix's 0.3, step 1,
now applies to this merge too. The merge also brings the sittings' results into these records, which would then have to
record them (the gate summary's Section 2 copies the report rows they changed), brings `DeviceTests`, which has not been
reviewed, and leaves phone B's build to settle with the owner. Computed and not made, it gives no conflict with this
fix's documents commit ([`checks/merges.log`](checks/merges.log)). It stays the orchestrating session's, with the owner,
between sittings, once the owner says the sitting in progress is done; a review of `m0-sessions` after it reads
`DeviceTests` and the records it brings, and the session log's rows 1 and 8 then take the new text the assembly's README
gives.

Also left as they were: `CLAUDE.md` (the owner's or the orchestrating session's to change; the texts asked are in the
third fix's README, and the gate summary's item 4 now lists them); the session log; plan 19.1, ADR-0001's Test devices and
the G0.4 and G0.5 recovery checklists, on phone B's build; the runbook's and the checklist's device commands for the
recovery suite, which the merge changes; ADR-0014's item on R4-01 and R4-02 and ADR-0001's own record of the Xcode 27.1
evidence (the `m0-exit-prep` run's); the plan, the amendments and the gate reports, so the second fix's amendments checker
and its mutations apply unchanged.

**Within the owner's word limits.** Two of the follow-up's checks keep what the owner reads first short: the gate
summary's opening at most 600 words, 800 with the State line (OWN5-05), and each step of its item 1 at most 400 (OWN4-09).
The opening was at 592 words and item 1's step 1 at 383 before this fix. So the opening gives the date of pull request
#6's merge without its time and the sittings in a short parenthesis, its last parenthesis shortened from "(the State line
above; each review and what it found: Section 6.2)" to "(the State line; Section 6.2)"; and item 1's step 1 gives the
merge's timing in one sentence, pointing to the runbook's 0.3, step 1, which gives it in full, with its history note
pointing to items 116 and 141, which hold what it said. Both now stand at their limits: 600 words, 800 with the State
line, and 399.

## Files

| Path | What it is |
| --- | --- |
| [`relayed-findings.md`](relayed-findings.md) | What was relayed to this fix: the request, the task, and the nine findings verbatim |
| [`commands/finding-lines.py`](commands/finding-lines.py) → [`checks/finding-lines.log`](checks/finding-lines.log) | Every line the findings cite, read at `8082bdb6` with `git show`, holds the text they quote, every text they name without a line is in its file, and their claims about refs and other commits hold |
| `../commands/branch-state.sh` → [`checks/branch-state.log`](checks/branch-state.log) | The first fix's read of the branches, unchanged, run again on this fix's documents commit |
| `../accuracy/commands/branch-texts.py` → [`checks/branch-texts.log`](checks/branch-texts.log) | The second fix's judged branch check, unchanged, run again |
| `../completeness/commands/dropin-paths.sh` → [`checks/dropin-paths.log`](checks/dropin-paths.log) | The third fix's check of runbook 0.8's paths, unchanged, run again |
| [`commands/merges.sh`](commands/merges.sh) → [`checks/merges.log`](checks/merges.log) | The two merges `m0-sessions` waits for, computed and not made: `m0-decisions`, which must still be at `c72247a6`, into HEAD, and `m0-exit-prep`, as it stood when read, into HEAD and into `caf75a84`. The successor of the third fix's |
| [`commands/apple-ios27-page.sh`](commands/apple-ios27-page.sh), [`commands/apple-ios27-page.py`](commands/apple-ios27-page.py) → [`checks/apple-ios27-page.log`](checks/apple-ios27-page.log) | Apple's page "iPhone models compatible with iOS 27", fetched into `.build/scratch` and read as text: its title and the list the runbook's 1.1 row A now cites |
| [`commands/recheck-own.py`](commands/recheck-own.py) → [`checks/recheck-own.log`](checks/recheck-own.log) | This fix's recheck: one item per finding and one for the review status; its control, on `caf75a84`'s tree, must report all ten |
| [`commands/gate-checks.sh`](commands/gate-checks.sh) → [`checks/gate-checks.log`](checks/gate-checks.log) | The gate checks of this fix, the successor of the third fix's; run last, on the commit that adds every other log |
| [`checks/da-gate-checks.log`](checks/da-gate-checks.log) | The third fix's gate checks, unchanged, on this fix: they fail by design (below) |
| [`checks/ci-contracts.log`](checks/ci-contracts.log), [`checks/13-hard-rules.log`](checks/13-hard-rules.log) | `Scripts/ci.sh contracts` and `Scripts/ci.d/13-hard-rules.sh`, through `Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh` |
| [`checks/lfs-checkout.log`](checks/lfs-checkout.log) | This worktree's 777 Git LFS files were pointer files; the follow-up's `commands/lfs-checkout.sh`, unchanged, filled them from the local store, with no download |

## Checks

Each ran on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) on the commit its log's header
names: `lfs-checkout.log` on `caf75a84`, before any change; the others on the fix's last documents commit, with no
uncommitted file (`da-gate-checks.log`, `finding-lines.log`, `branch-state.log` and `ci-contracts.log` first), except
that `branch-texts.log`, `dropin-paths.log`, `merges.log` and `apple-ios27-page.log` ran with `branch-state.log` in
place, `recheck-own.log` with those five, and `13-hard-rules.log` last, with every other log in place and not yet
committed, so that the audit read them too (each header counts its uncommitted paths); and the gate checks on the commit
that adds every other log. Dry runs on the uncommitted tree came first. Other jobs shared the Mac (the load averages in
the logs), so no timing here is a result. No simulator was created or used, nothing played audio, no device was
contacted, and nothing was fetched from or pushed to a git remote; one page of Apple's was read over the network.

| Check | Result | Log |
| --- | --- | --- |
| The findings' cited lines and claims | All 73 citations hold their text at `8082bdb6`, each on the line cited; the 12 texts named without a line are there; the 15 claims hold | `checks/finding-lines.log` |
| The branches, read-only | The checkout on `m0-decisions` at `c72247a6`, 8 commits past `044ed3cf` and `main`, not behind `main`; the session log there with four sittings of the owner's, on phone B, iOS 27.0.1 (24A446); a merge of `m0-decisions` into this fix's documents commit without a conflict | `checks/branch-state.log` |
| The judged branch check | Passes: no live text calls `m0-decisions` behind `main`; it is not merged into `m0-sessions`, and run 1's step 1 has the case for a checkout on another branch, which the checkout is; no live text says, without saying where, that no device step has run or no device result is recorded | `checks/branch-texts.log` |
| The drop-in's paths | No change from `9cdb0a02` to this fix's documents commit; neither the drop-in nor the harness checks names `DeviceTests`; `m0-decisions`, and its merge into this fix's documents commit, add the four files of `DeviceTests` under those paths and nothing else, and the check that sets it apart prints nothing for both; neither file `m0-exit-prep` changes is named by a file the drop-in runs | `checks/dropin-paths.log` |
| The two merges | `m0-decisions` still at `c72247a6`, into this fix's documents commit without a conflict; `m0-exit-prep`, as it stood when read, conflicting in exactly the files it conflicts in into `caf75a84`, ADR-0001 among them already | `checks/merges.log` |
| Apple's page on iOS 27 | Its title and the list with the iPhone 13 mini present: pass | `checks/apple-ios27-page.log` |
| This fix's recheck | Pass, 0 of 10 not as stated; the gate checks run its control on `caf75a84`'s tree, where it reports all ten | `checks/recheck-own.log` |
| `Scripts/ci.sh contracts` (`run-logged.sh`) | Passed: `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts` | `checks/ci-contracts.log` |
| `Scripts/ci.d/13-hard-rules.sh` (`run-logged.sh`) | Passed: the self-test and the audit of every committed and new file, these logs and this fix's scripts among them, 0 findings, 0 stale allowlist entries | `checks/13-hard-rules.log` |
| The gate checks (`commands/gate-checks.sh`) | Exit 0, as below | `checks/gate-checks.log` |
| The third fix's gate checks, unchanged | Fail by design (below) | `checks/da-gate-checks.log` |

**The gate checks.** Part 1: since `caf75a84` only the files this fix names and its own folder; outside `Docs/` only
`README.md`; `CLAUDE.md`, the session log, the license inventory, the gate reports, the plan and the amendments
unchanged; of the checklists one line added to the G0.5 recovery checklist and nothing else; under
`Docs/Stage0/evidence` only this fix's new files and the dated notes in the records part's evidence README and the first
three fixes' READMEs; since `6cede84a` as before; the drop-in's paths (the third fix's `dropin-paths.sh`), the
checklists from `9cdb0a02` to `6cede84a`, the session log (no sitting of the owner's on this branch) and the dependency
logs; 1h, the judged branch check passing, with its two controls; and 1i, the two merges as above. Part 2: no LFS file
added. Part 3: the gate summary's paths and 92 rows agree, and its negative control. Part 4: the second fix's amendments
checker, 0 failed checks, its 70 mutations caught and the tree restored; the records part's checker failing on exactly
its check 10k, and the follow-up's fix's on exactly its three, as before; the records check failing on exactly its ADR
index check, as before, and its control; the instructions part's content check passing and the decisions round's
version reporting exactly its three; the step coverage; the correction texts (from `4c73da57` the nine, from
`8082bdb6`, `d6315ad3`, `ec91f66a` and `caf75a84` nothing); the earlier rechecks that must pass passing, with their
controls; the six others reporting exactly the 17 lines of the second fix's `../accuracy/commands/expected-rechecks.txt`,
unchanged; the instructions part's recheck reporting exactly its floor item and its item run-1, and the assembly's
recheck exactly run-1, agree and state, by design (below), with the assembly's two controls; the first fix's two checks,
its recheck reporting exactly its items checkout, step-0.8 and review, as before, each with its control; the second
fix's two checks, each with its control; the third fix's two checks, its recheck reporting exactly its item review, by
design (below), each with its control; this fix's two checks, each with its control. Part 5: `Scripts/ci.sh contracts
dependency-lock hard-rules` passing.

**The earlier checks that now report what this fix changed, by design, and why.** Each asserts a text this fix changed
for a finding; this fix's checks assert the new text, and its gate checks require exactly these reports:

- **The instructions part's recheck** (`../../instructions/commands/recheck-instructions.py`) **and the assembly's**
  (`../../assembly/commands/recheck-assembly.py`): their item run-1 requires the gate summary's item 1, step 3, to read
  "by pull request #6 on 24 October 2026 (`96bdc7e9`)" and the runbook's 0.3, step 3, "on 24 October 2026 (`96bdc7e9`)",
  the build Mac's date alone, which OWN-DA-06 asked to give by UTC with the build Mac's date beside it. Their other
  reports are as before (floor; agree and state). `commands/recheck-own.py` (dates) asserts the new texts.
- **The third fix's recheck** (`../completeness/commands/recheck-da.py`): its item review requires the gate summary's
  Section 6.2 row to end with "| integration log sections 29, 30 and 31 |" and the runbook's Who wrote it to end with "nor
  its third, of its completeness findings; human review pending", which, with this fix, name section 32 and the fourth
  fix too. `commands/recheck-own.py` (review) asserts the new texts.
- **The third fix's gate checks** ([`checks/da-gate-checks.log`](checks/da-gate-checks.log), run on this fix's last
  documents commit, with no uncommitted file): part 1a, which allows only the third fix's files since `ec91f66a`, so not
  `README.md`, ADR-0001, the G0.5 recovery checklist or this fix's folder; part 1b, which requires nothing outside
  `Docs/` and the checklists unchanged since `ec91f66a`; part 1c, which allows no change under `Docs/Stage0/evidence`
  but its own new files and the dated notes in three READMEs, so not this fix's new files or the third fix's README; part
  3, on the five logs of this fix that the gate summary cites and that the documents commit does not hold yet
  (`apple-ios27-page.log`, `branch-state.log`, `finding-lines.log`, `gate-checks.log` and `merges.log`; this fix's gate
  checks, on the commit that adds them, find every path); and part 4, for the three rechecks above. Their other parts pass, part 5 (`Scripts/ci.sh contracts
  dependency-lock hard-rules`) among them.

What still passes unchanged: the second fix's amendments checker and its mutations; the instructions part's runbook
content check (no marker added: the new runbook texts hold no double-quoted text and no backticked log field or count;
Xcode's message in 1.5 is in backticks, with neither); the step coverage; the correction-text check (no line differs from
`caf75a84`); the six earlier rechecks (exactly the 17 lines of the second fix's list: the State line unchanged, the
opening within 600 words, 800 with the State line, and item 1's steps within 400); the second fix's recheck and judged
branch check; the first fix's recheck (exactly its three items, as before); the follow-up's recheck; the moved-notes
checks; both checks of the run's facts; both finding-lines checks of the drop-in record's rounds and the second fix's
recheck of that record, whose sweeps read this fix's Markdown files too.
