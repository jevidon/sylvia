# The assembly of the update of 24 October 2026 (26 October 2026)

**What this is.** The update of 24 October 2026 (`../README.md`; integration log section 28) was made in two parts, each
on a branch of its own from `m0-sessions` at `6cede84a`: the owner's instructions (`m0-sessions-instructions`, at
`1c69da4c`; [`../instructions/`](../instructions/README.md)) and the records of the device-A change
(`m0-sessions-records`, at `9a4c9810`; [`../README.md`](../README.md)). On 26 October 2026 (the build Mac's clock; 25
October UTC) an agent of the orchestrating session's workflow assembled them on `m0-sessions`, in a worktree of its own:
it merged both, applied what each part asked of the other's files or passed it to the file's owner, made the two say
the same where they did not, and ran the checks of the merged tree. Agent-written; not reviewed; human sign-off pending.
Nothing here is a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit; no device was used.
*(26 October 2026: an agent review read the update and this assembly at `8082bdb6`; a fix answered its fidelity findings
the same day, which has not been reviewed: [`../fix-1/`](../fix-1/README.md).)*

## The merges

`git merge --no-ff`, in this order, each without a conflict: `m0-sessions-instructions` at `1c69da4c` (merge commit
`25186d65`), then `m0-sessions-records` at `9a4c9810` (`5e455f70`). The two parts changed 34 and 42 files and none in
common, and each merge commit adds exactly its part's files ([`checks/gate-checks.log`](checks/gate-checks.log), part 1d).

## What each part asked, and what became of it

| Asked by | What | Outcome |
| --- | --- | --- |
| The instructions part | The session log (`Docs/Stage0/evidence/M0-runbook/sessions.md`): row 8 to read `\| 8 \| 8 Device A, your iPhone 13 mini (after Session 4; your iPhone 11 Pro until 24 October 2026) \|`, and row 1's items (1)-(3) and (5)-(8) replaced for `m0-sessions` and the state of run 1 (the text below) | **Not applied.** The session log is the owner's record, filled in by whoever runs each sitting, and this assembly kept every file under `Docs/Stage0/evidence/` but this update's new folder as it was (its gate checks require it, part 1c). Asked again of the owner, or of the orchestrating session at the owner's request, with the text below. Since then the session log has changed on `m0-decisions` (below, "Seen at the assembly") |
| The instructions part | The repository README's sentence that the records of the decisions "are on the branch `m0-decisions`, which reaches main by pull request" | **Applied** as asked (`README.md`, Project status), with "that merge" in the next clause made "the merge of `m0-decisions`", so that it still names the merge after the new clause |
| The instructions part and the records part | `CLAUDE.md`'s toolchain line, which says that "whether 27A9275 is the non-beta release awaits a check of Apple's release notes" (two wordings, below) | **Not applied.** An agent does not change `CLAUDE.md` on a workflow's request: it is the owner's or the orchestrating session's to change. The pin in that line stays as it is either way (`Scripts/ci.d/12-dependency-lock.sh` compares it with the inventory's), and the `m0-exit-prep` run may change the same line |
| The instructions part | Of the records part: keep the texts its records cite (plan 19.1 and 21.2's M8 row for the A13 floor; ADR-0001, ADR-0013, the device-A items of ADR-0003, ADR-0005, ADR-0007, ADR-0009 and ADR-0010, and the G0.2 report's row T38 for D-2's narrower exception), and add an integration log section for the update citing `instructions/` | **Both hold.** The records part kept those texts (the assembly's recheck reads them: item agree), and section 28 now describes both parts (28.3) and this assembly (28.8) |
| The records part | M8's A13 phone: in the runbook's 1.1 row A, "or a borrowed or bought one" to read "or one borrowed or bought if you want one", as the owner's chosen option had it ("with a borrowed or bought A13 phone if wanted") and as plan 19.1 and 21.2's M8 row say; the same wherever the gate summary states the M8 measurement | **Applied** in the runbook's 1.1 and its Section 6 (D-1 of 24 October 2026), and in the gate summary's Section 4.3 (D-1) and Section 6.3, item 105: the four places with the earlier wording |
| The records part | For the tree that merges both parts, two lines more in what the instructions part's gate checks expect of the earlier rechecks: FID4-04 and HON4-06, both on the ADR index's status column, which the records part dated 24 October 2026 | **Applied** in this assembly's successor of that list, [`commands/expected-rechecks.txt`](commands/expected-rechecks.txt): the instructions part's 14 lines, unchanged, and these two, verbatim as the rechecks print them; the assembly's gate checks require exactly those 16. The instructions part's list stays as the record of its part's run on its own tree |

**The session log's rows, as the instructions part asked** (to apply at the owner's request; the assembly did not):

- Row 8: `| 8 | 8 Device A, your iPhone 11 Pro (after Session 4) |` becomes `| 8 | 8 Device A, your iPhone 13 mini (after
  Session 4; your iPhone 11 Pro until 24 October 2026) |`.
- Row 1: (1) "`m0-decisions` checked out" becomes "`~/Git/sylvia-sessions` on `m0-sessions` (`git branch
  --show-current`)"; (2) the `CLAUDE.md` item becomes "done: `CLAUDE.md` corrected on 24 October 2026 (`5aec2518`,
  `6cede84a`)"; (3) the merge item becomes "done: pull request #6 merged `m0-decisions` into `main` (`96bdc7e9`); you
  build from `m0-sessions`"; (5) the R4 item becomes "R4-01 and R4-02 and the final-review records asked: the agent run
  on `m0-exit-prep` since 24 October 2026, merged into `m0-sessions` once reviewed; pending (Session 10 waits for
  both)"; (6) "... committed on `m0-decisions` ..." becomes "... committed on `m0-sessions`, by you or an agent you ask,
  before any agent works from them; nothing reaches `main` before the exit unless you decide otherwise"; (7) becomes
  "your one-line confirmation, as technical lead, that Xcode 27.1 (27A9275) is the release build, which Apple's pages
  read on 24 October 2026 show, recorded in ADR-0001"; (8) becomes "device A, your iPhone 13 mini, on iOS 26 (or 27)
  with a Lightning cable"; and the row ends with "(Until 24 October 2026 items (1)-(3) and (5)-(8) named `m0-decisions`
  as the branch to check out, correct `CLAUDE.md` on, merge into `main`, base agents on and commit records on; asked you
  to read the release notes; and named no model for device A.)".

**`CLAUDE.md`'s toolchain line, the two wordings asked** (for "whether 27A9275 is the non-beta release awaits a check of
Apple's release notes"): the instructions part's, "Apple's pages, read on 24 October 2026, show that 27A9275 is the
release build; the technical lead's one-line confirmation is pending"; the records part's, "Apple's release entry "Xcode
27.1 (27A9275)" (15 October 2026, no beta or release-candidate label) and its "Xcode 27.1 Release Notes", read by the
orchestrating session on 24 October 2026, await the technical lead's one-line confirmation", with
`Scripts/ci.d/12-dependency-lock.sh` run again afterwards.

## What the assembly changed to make the two parts agree

The two parts said the same of device A (the iPhone 13 mini, iPhone14,4 expected, A15, 375 × 812 pt drawn about 8%
smaller), of the dated addendum to D-1, of the narrower form of D-2 (b)'s exception and the records it goes in, of the A13
floor in M8 and of the branch, but for these three, which the assembly settled:

- **Which figures on device A are the 13 mini's in the repeats that can wait.** The runbook's Session 8 named the timed
  repeats (G0.4 1, G0.1 EPUB 11 and 12, G0.1 PDF 10, G0.2 22), G0.3's share-extension memory, limit and times (steps
  14-16) and G0.4 step 3's battery figures; the records' evidence README named G0.4 15 and G0.6 step 12's stall but not
  G0.1 EPUB step 12. The checklists' own text: G0.1 EPUB step 12 times the opening of each book (plan 19.2's 2 s); G0.4
  step 15 records how long the other app's audio takes to resume; and G0.6 step 12's stated limit, for the accessibility
  reviewer, is that a press can toggle twice "if the device stalls for more than 150 ms between a touch lift and the
  Button's action", which depends on the phone's speed. Both lists now name all of them, and the G0.4 checklist's
  device-A note names step 15's resume time with steps 1 and 3's figures.
- **The side of 8.9's start-up race.** The runbook's D-2 note of 24 October 2026 called 8.9 not affected, while ADR-0007
  records that the narrower exception changes one observation there, which side of G0.4 step 12.2's start-up race the
  capture falls on, as the runbook's 8.9 itself says. The note now names it.
- **M8's wording**, as above.

With the merge, the assembly also brought up to date what describes the update: the runbook's 0.8 (the check of the
drop-in's paths on the merged tree: [`checks/dropin-paths.log`](checks/dropin-paths.log)) and its Who wrote it line; the
gate summary (the bullet on pull request #6, Section 6.3's item 109 and items 111-115, Section 7's item 5, and Section
8's Branch bullet and its bullet on the update); the Stage 0 README; integration log section 28 (its opening, 28.1's
row on `m0-sessions`, 28.3, 28.4, 28.5, 28.6, 28.7 and 28.8); and the two parts' evidence READMEs. No status, budget,
scope or decision changed, and nothing outside `Docs/` changed but `README.md`.

## Seen at the assembly: the sessions' checkout on `m0-decisions`

When the assembly read the branches, read-only ([`checks/branch-state.log`](checks/branch-state.log), whose header gives
the time; the gate checks' part 1i read them again later), `git worktree list` showed `~/Git/sylvia-sessions` on
`m0-decisions`, not on `main` at `96bdc7e9`, as this update's records have it for 24 October 2026 and as integration log
28.1 had it earlier on 26 October. `m0-decisions` then had commits after `044ed3cf`, the commit pull request #6 merged,
made from 06:12 that morning on the build Mac's clock, and more were added while the assembly ran; their messages record
device runs and the sessions' setup (the first, "Record the first physical iPhone Keychain test result"). Among other
files they change the session log, the runbook, the G0.5 recovery checklist, the G0.2, G0.5 AI and G0.5 recovery
reports and the license inventory; add device evidence under `Docs/Stage0/evidence/` (G0.2's, G0.4's, G0.5 AI's, G0.5
recovery's and the runbook's folders); and add `Spikes/G05-Recovery/DeviceTests`, which lies in the paths runbook 0.8
checks. Four of their files are files this update also changes: the runbook, the G0.5 recovery checklist and the G0.2
and G0.5 recovery reports. The log lists the commits and files as they stood when it was written. The assembly read only the commits' metadata and file list: it read, recorded and inferred
none of their results, and changed no record for them. So the update's instructions (the device sessions built from
`m0-sessions` in that checkout; `m0-decisions` behind `main`, never to build from; the session log with no sitting of
the owner's, on 24 October 2026) do not describe that checkout as it now is. Reconciling `m0-decisions` with
`m0-sessions` before `~/Git/sylvia-sessions` moves is the orchestrating session's, with the owner; a merge of those
commits into `m0-sessions` would change `Spikes/G05-Recovery`, so 0.8's check would then call for 0.8 to run again.
*(26 October 2026: the fix of the review's fidelity findings brought the owner's instructions in line with that state,
read again ([`../fix-1/checks/branch-state.log`](../fix-1/checks/branch-state.log)), and left the reconciliation to the
orchestrating session, with the owner: [`../fix-1/README.md`](../fix-1/README.md); integration log 29.2.)*

## Files

| Path | What it is |
| --- | --- |
| [`commands/gate-checks.sh`](commands/gate-checks.sh) → [`checks/gate-checks.log`](checks/gate-checks.log) | The gate checks of the merged tree, the successor of the instructions part's gate checks and of the records part's runner, whose parts it runs with the merged tree's expectations; run last, on the commit that adds every other log |
| [`commands/recheck-assembly.py`](commands/recheck-assembly.py) | The successor of the instructions part's recheck: its six items (the floor item with M8's new wording, the step-0.8 item with the assembly's check) and three more: agree (the two parts say the same), state (the branch state the same everywhere it appears) and log (section 28 describes both parts and the assembly). The gate checks run it on HEAD, and as its controls on the trees of `6cede84a` (all nine reported) and `5e455f70` (exactly the five the assembly changed) |
| [`commands/expected-rechecks.txt`](commands/expected-rechecks.txt) | What each earlier recheck that reads a changed text must report on the merged tree, exactly, and why |
| [`commands/branch-state.sh`](commands/branch-state.sh) → [`checks/branch-state.log`](checks/branch-state.log) | The branches and the sessions' checkout, read-only (above) |
| [`checks/dropin-paths.log`](checks/dropin-paths.log) | The instructions part's `commands/dropin-paths.sh`, unchanged, on the merged tree |
| [`checks/apple-device-pages.log`](checks/apple-device-pages.log), [`checks/apple-pages.log`](checks/apple-pages.log) | Apple's pages read again with the two parts' readers, unchanged (`../commands/apple-device-pages.sh`, `../instructions/commands/apple-pages.sh`) |
| [`checks/device-type-profiles.log`](checks/device-type-profiles.log) | Xcode 27.1's simulator device types, read-only, with the records part's `../simulator/device-type-profiles.sh`, unchanged |
| [`checks/ci-contracts.log`](checks/ci-contracts.log), [`checks/13-hard-rules.log`](checks/13-hard-rules.log) | `Scripts/ci.sh contracts` and `Scripts/ci.d/13-hard-rules.sh`, through `Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh` |
| [`checks/instructions-gate-checks.log`](checks/instructions-gate-checks.log), [`checks/records-run-checks.log`](checks/records-run-checks.log) | The two parts' own runners on the merged tree, which fail by design (below) |
| [`checks/lfs-checkout.log`](checks/lfs-checkout.log) | This worktree's 777 Git LFS files were pointer files; the follow-up's `commands/lfs-checkout.sh`, unchanged, filled them from the local store, with no download (`git lfs checkout`; the configuration untouched) |

## Checks

Each ran on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) on the commit its log's header
names: `lfs-checkout.log` on `5e455f70` before any change; `dropin-paths.log` and `branch-state.log` on `5e455f70`, the
merged tree, just before the documents commit, with the assembly's changes to the documents uncommitted
(`branch-state.log`'s header counts them; none touches a path either reads); the gate checks on the commit that adds every other log; and the others
on the documents commit, with no uncommitted file, except `13-hard-rules.log`, which ran last with the other logs in
place and not yet committed, so that the audit read them too. Other jobs shared the Mac (the load averages in the
logs), so no timing here is a result. No simulator was created or used, nothing played audio, no device was contacted,
and nothing was pushed to or fetched from a git remote; Apple's pages were read over the network.

| Check | Result | Log |
| --- | --- | --- |
| The drop-in's paths | None changed from `9cdb0a02` to `6cede84a` or to the merged tree; no file the drop-in runs names `Scripts/check-dependency-lock.py` or `Scripts/ci.d/12-dependency-lock.sh` | `checks/dropin-paths.log` |
| The branches, read-only | As above | `checks/branch-state.log` |
| Apple's pages, both readers | Every quote present, every absent text absent, on all nine pages: pass | `checks/apple-device-pages.log`, `checks/apple-pages.log` |
| The simulator device types | As facts 3 and 4 of `../README.md` give them: the iPhone 13 mini iPhone14,4, 1080 by 2340 pixels at 476 ppi, scale 3.0 | `checks/device-type-profiles.log` |
| The gate checks | Exit 0: part 1 as above (since `6cede84a` only the two parts' files and the assembly's, nothing outside `Docs/` but `README.md`, `CLAUDE.md`, the session log and the license inventory unchanged, the historical evidence untouched, the merges as made); the LFS state; the gate summary's paths and 92 rows, with its negative control; the records part's amendments checker and its 66 mutations, its control failing on exactly its three; the records check and its control; the instructions part's content check, and the decisions round's version reporting exactly its three; the step coverage; the correction texts; the earlier rechecks, the six reporting exactly the 16 expected lines; the instructions part's recheck reporting exactly its floor item; the assembly's recheck passing, with both controls; `Scripts/ci.sh contracts dependency-lock hard-rules` passing | `checks/gate-checks.log` |
| `Scripts/ci.sh contracts`; `Scripts/ci.d/13-hard-rules.sh` | Passed: `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts`; the audit of every committed and new file, these logs among them, 0 findings, 0 stale allowlist entries | `checks/ci-contracts.log`, `checks/13-hard-rules.log` |

**The earlier checks that fail on the merged tree by design, and why.** Each part's checks were written for its own
tree; on the tree that merges both they report the other part's changes, and the assembly's checks above replace them.

- **The instructions part's gate checks** ([`checks/instructions-gate-checks.log`](checks/instructions-gate-checks.log)):
  parts 1a and 1b (since `6cede84a` they allowed its own files only and required the plan, the ADRs, the reports, the
  integration log and `README.md` unchanged; the records part and the assembly changed them); part 3 (one cited path,
  the log of the assembly's own gate checks, which run last); and part 4: the follow-up's fix's amendments checker, which
  they required to pass unchanged and which fails on the three checks whose anchors the records part replaced (the
  records part's successor passes); the earlier rechecks, which also report FID4-04 and HON4-06 (the records part's);
  and their recheck's floor item (M8's wording, changed as the records part asked).
- **The records part's runner** ([`checks/records-run-checks.log`](checks/records-run-checks.log)): its step 5 (it
  required the earlier rechecks to report what they report on `6cede84a`'s tree, but for FID4-04 and HON4-06; they also
  report what the instructions part changed: FID4-02, HON4-01, OWN4-03, OWN4-06, OWN5-02 and the drop-in record's two
  texts, and recheck-unl's UNL-02 line now gives the State line as 198 words) and its step 6 (it required the decisions
  round's runbook content check to pass, which reports the three texts the instructions part changed; that part's
  successor passes).
- **The instructions part's recheck** (run by both): its floor item, on M8's wording. Its successor, the assembly's
  recheck, asserts the new wording.

## Not done here, and why

- **The session log's rows and `CLAUDE.md`'s toolchain line**: asked of their owners (above).
- **ADR-0014's dated note of 23 October 2026**, which names `m0-decisions` as the base and the destination of R4-01 and
  R4-02, and **the Xcode 27.1 evidence in ADR-0001**: left to the `m0-exit-prep` run, which rewrites that item and
  records that evidence, so as not to make its merge conflict there. Its merge will conflict on ADR-0001's Status line,
  which this update changed too: keep both changes. ADR-0001's Status still says that 27A9275 has not been checked
  against Apple's release notes until then (the gate summary's item 1, step 7, says that the evidence reaches ADR-0001
  with that merge).
- **What `m0-decisions` gained after pull request #6** (above): for the orchestrating session to reconcile, with the
  owner.
- **The complete CI**: not run. Nothing outside `Docs/` changed but `README.md`; every drop-in that reads a document the
  update changed ran.
- **Review**: none; the orchestrating session switches `~/Git/sylvia-sessions` to `m0-sessions` once the update is
  reviewed, and after the reconciliation above. *(26 October 2026: an agent review read the update and this assembly at
  `8082bdb6`; the fix of its fidelity findings is in [`../fix-1/`](../fix-1/README.md).)*
