# The thirteen M0 items' review records

The author results, reviews and fixes of the thirteen M0 items that M0 assembly squash-merged into `m0-integrate` on 14 October 2026 (integration log section 7.1): the contracts, the dependency lock, the threat model, the device runbook, the plan amendments and the eight gates' remaining review findings. The gate summary waits for them before the M0 exit review (`M0-gate.md` Section 1, items 3 and 4; Section 6.2, last row; Section 7): until now only each item's final verdict and its serious findings were in the repository, and its "minor findings stay with the gate" (`Docs/Stage0/README.md`) without the findings or their count. They are handed over here, on 24 October 2026, on branch `m0-exit-reviews` from `5aec2518` (`main` after pull request #6, with the `CLAUDE.md` correction). **These are agent reviews, not a person's**, and this hand-over is agent-written and not reviewed; human sign-off pending. Nothing here is a device result, a role sign-off or the M0 exit: the owner's security sign-off, the ADR approvals (decision D-6) and the exit review stay pending.

## Where they came from

- **Source:** the journals of the workflow runs that made them, which Claude Code keeps on the build Mac outside the repository, in the folder of the session that orchestrated M0 (`~/.claude/projects/-Users-jevidon-Git-sylvia/5bdb0d98-f700-47fd-ab1d-8b1a7a65cdbb/subagents/workflows/`; `M0-gate.md` Section 1, item 4).
- **Extraction:** on 24 October 2026 (the build Mac's clock; the files' modification time is 2026-10-23T15:38:42Z), by the orchestrating session, into one JSON file per item and `SUMMARY.json`, in that session's scratchpad folder (`/private/tmp/claude-501/-Users-jevidon-Git-sylvia/5bdb0d98-f700-47fd-ab1d-8b1a7a65cdbb/scratchpad/item-reviews/`), from which this hand-over copied them byte for byte. The agent that made this hand-over did not read the journals, which are outside its file access: every check below compares the extraction with the repository and with itself, not with the journals, so that the extraction holds every record the journals hold rests on the extraction.
- **A record** is one workflow agent's structured result: `run` (the workflow run), `seq` (its place among that run's records), `label` and `result`. The label is `<item>:author` (the item's implementer), `<item>:review-N` (the N-th review round), `<item>:review-Nb` (a second, independent review of the same commit through another lens) or `<item>:fix-N` (the fix after review round N). An author's result gives its branch, commit, summary, criteria (each with a status and its evidence), CI run, plan findings, shared changes requested, dependencies, committed fixtures and open questions; a review's, its verdict, the commit it reviewed, its own re-run, its findings (ID, severity, title, location, detail), the claims it verified, the gate gaps and the status of earlier findings; a fix's, its commit, what it fixed, what it did not and why, and its re-run. `SUMMARY.json` gives each item's counts, runs, final review, verdict and commit.

## The files

| Path | What it is |
| --- | --- |
| `extracted/<file>.json.txt` (14) | The extraction's fourteen files, byte for byte (SHA-256 below). Each is named with `.txt` after `.json` because `Scripts/audit-hard-rules.sh` reads every `.json` file as configuration, and the reviews' prose names App Transport Security, file-protection and Keychain keys, `NSAllowsArbitraryLoads` and `kSecAttrAccessibleAlways` among them, under rules that can never be allowlisted: named `.json`, five of the files give 23 findings; named `.json.txt`, none (`commands/audit-probe.sh`; log below). They are JSON: `python3 -I -m json.tool extracted/deps.json.txt` prints one. |
| `<item>.md` (13) | Each item's record, generated from its file by `commands/item-reviews.py render`: every author, review and fix round in order, with its run, commit and verdict; each review's findings (ID, severity, title) with what became of each, by the later records; each fix's lists of what it fixed and did not fix, as the fixer gave them; and the final verdict and the findings that stayed open. The full texts are in the JSON. |
| `commands/item-reviews.py` | `render` writes the Markdown records, `render --check` compares them with what it writes, and `check [--extraction DIR]` runs the checks below. Reads only the records, the repository's git objects and the documents it names. |
| `commands/audit-probe.sh` | The hard-rule audit, unchanged, on copies of `extracted/` named `.json` (it must fail) and `.json.txt` (it must pass). |
| `commands/compare-gate-checks.py`, `commands/run-checks.sh` | The comparison of the latest gate summary checks' run on this hand-over with their run on `5aec2518`, and the runner of every check, whose logs are in `Docs/Stage0/evidence/M0-ExitPrep/reviews/` (its README lists them). |

| File as extracted | SHA-256 |
| --- | --- |
| `SUMMARY.json` | `263c6aa5852e563c6f60d78f879a5e062888da5dd5e5cfcb2a5258148aed29a2` |
| `amendments.json` | `5fe1568bae95cca10765ebc31e26bf7ca3d0c1a432a27f82056bb88d3276ff0a` |
| `contracts.json` | `cb1773d2a21c96f48e8d5a95f94a82cd6a873dd0bbedb14214c1a971018b7c3a` |
| `deps.json` | `474a341b6c759adabd6eb58d9a52911dc988c89d6c3fc54ff916c30a918d73f0` |
| `minors-g01-epub.json` | `6ca04f0e73eaf9f7869477261ab958aa699ec8810bae67ed35ae7e2cf5d91371` |
| `minors-g01-pdf.json` | `538928a3122c92c6d7e8c95a178430699003360610afc626b9a0103196d17cdb` |
| `minors-g02-transfer.json` | `e5285ee87cab9a6b3c379236473ce64497c594eacaef3d7010e83a73bef58ee4` |
| `minors-g03-intake.json` | `c64d3f4c5198f7c755e755d54f9eec0a25b1590835a7d5fca180de9a348d93e2` |
| `minors-g04-audio.json` | `18875feef4fd00bbd9d73ceab3ee2cd06216d3dc04ca7775c63391d4467fdae3` |
| `minors-g05-ai.json` | `66be74695e9686c60cabad478e850c3fab9b19837efa89b76cb596be6227b31d` |
| `minors-g05-recovery.json` | `cdbb66f87047b697854303feb37344260a7b97755a91f46f5375a53867c6bcf5` |
| `minors-g06-design.json` | `5f452e918011d533195a014995e09c5cf9a6ee28387c24a37287a439804797cb` |
| `runbook.json` | `cc2e3d7fd84adde85bcbf7c320bf3d1625c82e3b749323347003200b3f18c1ba` |
| `threat.json` | `607827b588470f7f531c8d6bb855be535e8c40bae2609dc061e6142e6765ac2c` |

## How they were checked

`commands/item-reviews.py check --extraction <the extraction's folder>` (log: `Docs/Stage0/evidence/M0-ExitPrep/reviews/check-item-reviews.log`), host only, read-only. Each part reports each fact it checks:

1. **The files.** The fourteen files are byte for byte the extraction's (compared with the extraction's own folder, and by SHA-256), and each parses as JSON.
2. **`SUMMARY.json` against the item files:** each item's record and review counts, runs, final review, verdict and commit.
3. **Labels and timeline.** Each item has one author, review rounds 1 to N and a fix between each two rounds; every record's run and seq run forward in the order of its rounds, which places the six runs the records come from in one order: `wf_5ce13c9e-6bf`, `wf_5552ba19-d21`, `wf_744b95c1-309`, `wf_3f1b0c6a-cad`, `wf_9ea3b4d5-f4f`, `wf_eaa493fa-c4f`.
4. **Every commit** of the 63 records (the author's, each fix's and each review's `commit_reviewed`, read from the start of the field where a review wrote more) is a commit of this repository (`git rev-parse --verify` and `git cat-file -e`) and on the item's branch, which still exists here; each review read the commit of the author or of the fix before it; each fix's commit comes after the commit its round reviewed; and every lens of each final round reviewed the same commit. The log gives each commit's date.
5. **The merge.** For each item, the commit its final round reviewed is the final commit integration log 7.1 records and the head of its branch; 7.1's verdict is the final round's; the squash commit names the branch and that commit; every path the branch changes is identical in the squash commit, except, for the deps item, ADR-0014, the wording conflict 7.1 records; and 7.1's open serious findings are the final round's blocker and major findings (deps: R4-01 and R4-02; the others: none).
6. **What the records say happened, against what the repository says.** Integration log section 2's account of each `m0-int-minors-*` branch (the commits it names, the rounds' finding IDs and severities, the gate findings each branch closed), 7.2's citation of the deps item's R3-05, section 6's account of the deps merge, the gate summary's statements that each final review accepted with minor findings, deps rejecting, and that the twelve other items' final reviews left no serious finding open (Sections 6.1 and 6.2), and the round counts `G03-Intake.md` and `G05-AI.md` give, each read again in the records.
7. **What stayed open**, item by item, as the Markdown records give it.
8. **The Markdown records** are what `render` writes from the JSON.
9. **The pointers:** each gate report, and each record an item made, has one line linking to its item's record (the deps item's is requested of ADR-0014's owner: below).

The drop-ins and document checks these files feed ran too, on this hand-over's last documents commit: `Docs/Stage0/evidence/M0-ExitPrep/reviews/README.md`.

## What they show

63 records (13 authors, 35 reviews, 15 fixes) in six workflow runs, with 247 findings in all.

| Item | Records | Final round | Final verdict, at | Raised by the final round | Earlier, unresolved | Earlier, named by no later record | Merged as |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [`contracts`](contracts.md) | 9 | 3 (review-3 and review-3b) | accept-with-minor, `ef0d5de6` | 16 (16 minor) | 2 | 19 | `5670e3a` |
| [`deps`](deps.md) | 8 | 4 (review-4) | reject, `67682c23` | 7 (2 major, 5 minor) | 0 | 0 | `358a5bc` |
| [`threat`](threat.md) | 3 | 1 (review-1b and review-1) | accept-with-minor, `6bb2b9e8` | 16 (16 minor) | 0 | 0 | `10d758f` |
| [`minors-g06-design`](minors-g06-design.md) | 2 | 1 (review-1) | accept-with-minor, `98125421` | 5 (5 minor) | 0 | 0 | `8a59a16` |
| [`minors-g05-recovery`](minors-g05-recovery.md) | 4 | 2 (review-2) | accept-with-minor, `cd3e42b0` | 2 (2 minor) | 0 | 0 | `740aa46` |
| [`minors-g01-epub`](minors-g01-epub.md) | 2 | 1 (review-1) | accept-with-minor, `d3170541` | 5 (5 minor) | 0 | 0 | `b7b3ae9` |
| [`minors-g01-pdf`](minors-g01-pdf.md) | 6 | 3 (review-3) | accept-with-minor, `a44b746c` | 3 (3 minor) | 0 | 0 | `483ca01` |
| [`minors-g03-intake`](minors-g03-intake.md) | 6 | 3 (review-3) | accept-with-minor, `77ceaf3f` | 5 (5 minor) | 0 | 0 | `932d08c` |
| [`minors-g02-transfer`](minors-g02-transfer.md) | 2 | 1 (review-1) | accept-with-minor, `c83a3b9f` | 5 (5 minor) | 0 | 0 | `41e918a` |
| [`minors-g05-ai`](minors-g05-ai.md) | 4 | 2 (review-2) | accept-with-minor, `4090d590` | 4 (4 minor) | 1 | 0 | `7060c10` |
| [`runbook`](runbook.md) | 6 | 3 (review-3) | accept-with-minor, `6f339473` | 4 (4 minor) | 0 | 0 | `6be1cb7` |
| [`amendments`](amendments.md) | 9 | 3 (review-3 and review-3b) | accept-with-minor, `694518f2` | 13 (13 minor) | 2 | 6 | `8d34e8c` |
| [`minors-g04-audio`](minors-g04-audio.md) | 2 | 1 (review-1) | accept-with-minor, `d0c61203` | 6 (6 minor) | 0 | 0 | `70f6f54` |

- **Every final round reviewed the commit that was merged**, and the verdicts are the ones the repository records: twelve accept-with-minor, the deps item reject (part 5).
- **When the items were merged, these were open:** the 91 findings the final rounds raised (two major, the deps item's R4-01 and R4-02; 89 minor); five earlier findings the records leave unresolved (the contracts item's R1-11, carried into R2-05 and L2-R2-07, and R2-05; the G0.5 AI item's R7-04, carried into R8-04; the amendments item's L2-06 and L2-07); 25 earlier findings that no later record names, so these records give them no outcome (contracts 19, among them one major, round 1's L2-03; amendments 6); and five items of the gates' own earlier rounds or gaps that a final round still marks not resolved (G0.6's three device and design gaps; G0.5 recovery's R2-07 and G0.1 PDF's R1-04, each a request for `Fixtures/LICENSES.md` rows, which integration log 7.3 records as applied at assembly, rows 63 and 66). "Earlier" means raised by a round before the final one; "carried" means that a later review found it unresolved and named, in its note, the finding of its own that took over the remainder.
- **Not counted as open:** twelve earlier findings that a fix lists as fixed and that no later review names (the runbook item's R1-07, R1-08, R2-10 and R2-11; the amendments item's L2-01 to L2-05 and L2-08 to L2-10, four of them major).
- **None of the final rounds' findings was in the repository** except the deps item's R4-01 and R4-02: at assembly, integration log 7.1 recorded each item's verdict and serious findings only, and searched by ID in each item's report or record (the check log's part 7 prints every hit with its context), the others appear only where those documents cite other reviews' findings under the same IDs (the gates' own review rounds, the M0 final review). Whether later work (the assembly, the M0 final fix or the rounds since) answered any of them was not checked for this hand-over.

## Gaps, recorded as found

1. **Runs.** The gate summary named six runs from a listing of the journals' folder. The records come from five of them and from `wf_5ce13c9e-6bf`, which it did not name and which holds four records (`threat:author`, `minors-g01-epub:author` and `:review-1`, `minors-g05-ai:author`); `wf_84f4e4ba-f4a`, which it named, holds no extracted record. Whether that run holds any record of these items was not checked here.
2. **Lists handed over incomplete.** The records themselves say that some fixers and reviewers did not receive the findings in full: the contracts item's fix-2 (review-2b's list ended partway through L2-R2-01) and fix-1 (R1-10 reconstructed from its title), the amendments item's fix-1 (review-1b's list cut off partway through L2-01, so L2-06 and L2-07 were not addressed), and reviews that inferred earlier findings from commits or from the fixer's cross-references. The 25 findings no later record names are of those two items' second lenses. Several look like the defect the first lens raised in the same round and saw resolved (the contracts item's L2-03 and R1-03, for example), but the records do not say so, so they are listed as having no outcome.
3. **IDs reused within an item:** the contracts item's L2-01 to L2-09 (review-1b and review-3b) and the amendments item's L2-12 to L2-17 (review-2b and review-3b) are different findings under the same IDs; the Markdown records give each with its round.
4. **The G0.5 recovery item's final review** says that the author result supplied with it was the round-3 result for `ce535e0`, not fix-1's, and that it reviewed the branch head, `cd3e42b`.
5. **No times.** The records carry no timestamps: their order comes from their runs and seqs, and the check log gives each commit's date.
6. **Finding IDs continue the gates' own review rounds** (the G0.5 AI item's review-1 is `G05-AI.md`'s Review round 7, its review-2 round 8), so the same ID can name different findings in a gate report and in an item record; each Markdown record says which rounds it holds.

## What needs attention, and whose it is

- **The deps item's R4-01 and R4-02** are the two serious findings the gate summary tracks (Section 6.1). A parallel agent's task of 24 October 2026 is to close them, on a branch of its own; that work is not part of this record.
- **The G0.5 AI item's R8-04:** the 1,664 leftover directories that `G05-AI.md` (Review round 6, last paragraph) and the gate summary (Section 5.2; Section 1, item 4) give the owner to delete include G0.5 recovery's test root `g05-tests`, which the cleanup command given there would delete too, and 4 reviewer probe directories: by R8-04's read-only count of 13 October 2026, 1,659 of them match `g05-<UUID>`. The command is still there (the check log's part 6 notes it), and `Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Support.swift` still makes its scratch directories under `g05-tests/` in the temporary folder; correcting the command is the G0.5 AI report's owner's.
- **Final-round findings on steps the owner will run,** for an agent to check against the current checklists and runbook before the session that runs each: G0.1 EPUB R4-03 and R4-04 (checklist step 11), G0.2 R4-01 to R4-03 (steps 22 and 23), G0.3 R5-03 (step 9), G0.5 AI R8-02 (step 9.2's wording review), G0.6 R4-05 (step 12), and the runbook's R3-01 to R3-03 (the run order around device A's G0.3 repeat, Session 10's Section 23.1 sign-offs, and 2.11's fixtures). Later rounds may have answered some (correction C56 moved device A's G0.3 repeats to M2; the follow-up's fourth fix added the 23.1 sign-offs to Session 10); this hand-over did not check.
- **The deps item's pointer** belongs in ADR-0014, another workstream's file in this round: requested of its owner.
