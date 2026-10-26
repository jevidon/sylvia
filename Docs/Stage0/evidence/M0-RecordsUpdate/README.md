# `m0-records-update`: the M0 records brought onto the owner's session branch line (26 October 2026)

What this branch does, how the product owner merges it into `m0-decisions` between sittings, and the checks behind it
(integration log section 41). Agent-written; not reviewed; human sign-off pending. Nothing here is a device result, a
role sign-off, an ADR approval (decision D-6) or the M0 exit: no iPhone 13 mini has been registered or run, and no step
of the device runbook was run for this branch.

*(26 October 2026: an agent review read this branch at `832a3636`, and the workflow relayed its fidelity findings,
FID-RU-01 to FID-RU-11, to a fix on the same branch; its record is [`fix-1/`](fix-1/README.md) and integration log
section 42, and it has not been reviewed. The review's other lenses' findings go to fixes that follow, one at a time.
The fix changed what items 2 and "Left for the owner" below say, each with a note.)* *(27 October 2026: the workflow
relayed the same review's completeness findings, CMP-01 to CMP-07, to a second fix on the same branch; its record is
[`fix-1/completeness/`](fix-1/completeness/README.md) and integration log section 43, and it has not been reviewed. It
changed what item 6, "Left for the owner", the merge commands and their bullets, the paragraph before the table and the
table's last row say, each with a note.)* *(27 October 2026: the workflow then relayed the same review's
owner-readability findings, OWN-RU-01 to OWN-RU-08, to a third fix on the same branch; its record is
[`fix-1/owner/`](fix-1/owner/README.md) and integration log section 44, and it has not been reviewed. It changed what
items 1 and 5, "Left for the owner" and the merge section say, each with a note: your merge is a fast-forward or
nothing, an agent first bringing this branch up to date if `m0-decisions` has moved on; a command, which the merge
brings, puts `CLAUDE.md`'s two texts in; and after the merge you run the checks of runbook 0.8 and 0.3, step 7, which
this README no longer answers for you.)*

*(27 October 2026: two more changes reached this branch that day. `CLAUDE.md`'s two texts are in: the orchestrating
session put them in on this branch, in `6a510880`, with the command named below, at your request of 24 October 2026, as
that commit's message records, so your merge brings them and you put nothing in by hand ("Left for the owner" and the
merge section have notes). And `m0-device-fixes`, the fixes of the three failures of your first runs on phone B, made
from `m0-decisions` at `c72247a6` and reviewed in two rounds to accept-with-minor by its correctness, security and
honesty lenses, as relayed, is folded in (`cbdb63bc`), with the record requests of its README applied, but for two
decisions left to you as technical lead and one optional request ([`foldin/`](foldin/README.md); integration log
section 45). So your merge of this branch also brings the device fixes, after which runbook 0.8 runs again on the Mac
and 1.2 and 1.3 run again on phone B: the merge section gives the order. Agent-written; the fold-in has not been
reviewed.)*

## What it does

`m0-decisions` is the product owner's session branch: since 25 October 2026 UTC the owner, with Codex running the
commands, builds the device sessions from it in `~/Git/sylvia-sessions` and commits the session records on it (eight
commits, `8404f342` to `c72247a6`, when this branch was made). Two agent branches held work for that line, made before
the branch rule was restated, from `5aec2518` (`main` after pull request #6, with the first correction of `CLAUDE.md`'s
milestone paragraph; its code is that of `044ed3cf`, the commit of `m0-decisions` before the sessions):

| Branch | Commit merged | What it brings | Merge commit |
| --- | --- | --- | --- |
| `m0-exit-prep` | `c3adae68` | ADR-0014's R4-01 and R4-02 closed in the Zip guard, with the routes of the same kind its reviews found; the thirteen M0 items' review records handed over; `linkage.sh` under Xcode 27.1, offline; the Xcode 27.1 evidence for the technical lead's confirmation; the `CLAUDE.md` correction `5aec2518`. Reviewed, as relayed: the security lens accepted in its third round, at `c3adae68`, and the honesty lens accepted with minor findings | `cd27b60b` |
| `m0-sessions` | `1d5ac477` | The owner's decision of 24 October 2026 on device A (the iPhone 13 mini in place of the iPhone 11 Pro, which no longer charges), recorded in the plan, the amendments, the ADRs, the reports, the checklists and the runbook. Reviewed in two rounds, as relayed: accepted with minor findings by the fidelity, accuracy and completeness lenses; its owner-readability lens rejected the branch's move of the sessions to `m0-sessions`, the owner's sittings having begun on `m0-decisions`, and the run was stopped, its last fixer's work saved unreviewed as `1d5ac477` | `4c0fa815` |

`m0-records-update` was made from `m0-decisions` at `c72247a6` and merged both, in that order, with `--no-ff`. Then:

1. **The owner's records stay exactly as committed.** Every file the eight commits added or changed under
   `Docs/Stage0/evidence/`, `Spikes/` and `Docs/Licenses/inventory.json` is byte for byte as at `c72247a6`, and every
   line they added or removed in the records an agent also edits is kept (`commands/owner-records-intact.py`;
   `checks/owner-records-intact.log`). The one conflict of the first merge, the session log, was resolved by keeping the
   owner's log; this branch adds nothing to it. *(27 October 2026: that check reads the owner's commits up to
   `c72247a6` alone, a commit it names in its text; its new version,
   [`fix-1/owner/commands/owner-records-intact.py`](fix-1/owner/commands/owner-records-intact.py), takes the owner's
   head as `--owner-head`, so that, after an agent's merge of a `m0-decisions` that has moved on, it checks the owner's
   later commits too (the merge section; the review's finding OWN-RU-03).)*
2. **The branch model, restated everywhere the records give it:** `m0-decisions` is the owner's session branch; agent
   work goes on a branch of its own made from `m0-decisions` and reaches the owner's build only when merged into
   `m0-decisions` between sittings, by the owner or by an agent the owner asks; `m0-sessions` is retired (its work arrives
   through this branch; nothing is built from it); nothing reaches `main` before the M0 exit unless the owner decides
   otherwise. Run 1 is given as it now stands (the gate summary's Section 1, item 1; the runbook's 0.3 and Section 3).
   *(26 October 2026: not everywhere, as the review of this branch found: the runbook's 0.7 and the gate summary's
   bullet on H-1 in Section 5.4 still had the owner commit session records on `m0-sessions`, and the bullet build from
   it, and five notes of 24 and 26 October 2026, three in the gate summary and two in ADR-0002, gave its model with no
   later note. The fix of its fidelity findings changed them, and its check
   ([`fix-1/commands/retired-branch-texts.py`](fix-1/commands/retired-branch-texts.py)) fails on any live text that
   names `m0-sessions` as a branch to build from, commit to or merge into: [`fix-1/`](fix-1/README.md).)*
3. **The owner's first sittings:** the texts that said that no device step had run, or that `m0-decisions` held runs
   these records had not reconciled, now cite the owner's results as committed, with dated notes; no report status
   changed. Phone B is on iOS 27.0.1 (24A446), as the owner's setup record gives it, under the runbook's rule for a device
   on 27.x.
4. **R4-01 and R4-02 closed**, the change accepted by the review of `m0-exit-prep`; the gate summary's row 76 is
   passed-host, ADR-0014 says why, and the owner's security sign-off is still pending.
5. **Runbook 0.8 checked again** on this branch: nothing G0.5 recovery's drop-in builds, copies or runs changed since
   `9cdb0a02` but `Spikes/G05-Recovery/DeviceTests`, which it does not use, so report row 10's class-B evidence stands
   and 0.8 needs nothing (`checks/step-0.8-paths.log`). *(27 October 2026: on this branch; on `m0-decisions` after your
   merge, 0.8's command, which the merge section has you run, says whether it still holds, since a branch merged there
   before this one, such as a fix of the recovery suite, can change those paths: the review's finding OWN-RU-03.)*
   *(27 October 2026: no longer on this branch either: the device fixes, folded in since, changed the recovery package
   after `9cdb0a02`, so 0.8's command prints its `Sources` and `Tests`, and 0.8 runs again after your merge
   ([`foldin/`](foldin/README.md); the merge section).)*
6. **What both branches numbered alike** was renumbered: `m0-sessions`'s integration log sections 28-32 are 36-40 and
   its gate summary items 104-150 are 131-177 (`commands/renumber-sessions.py`; its dry run on the merge's records:
   `checks/renumber-sessions-dry-run.log`). *(27 October 2026: not every reference was: four in two lines of the gate
   summary's Section 8 that both branches changed, and one in its item 150, which the script rewrote in part, kept
   `m0-sessions`'s numbers; the fix of the review's completeness findings renumbered them, and its check reads every
   such reference against the two branches: [`fix-1/completeness/`](fix-1/completeness/README.md).)*
7. **The device fixes folded in** (27 October 2026): `m0-device-fixes` at `a60aa922`, made from `m0-decisions` at
   `c72247a6`, merged with `--no-ff` (`cbdb63bc`), with no conflict, since the two branches changed different files; its
   code (the recovery package's `Sources` and `Tests`, the ATS probe's test file) and its evidence folder are as that
   branch has them, but for dated notes added to its README; and the record requests of its README's Section 8 are
   applied to these records, requests 5 and 15 recorded as decisions pending for you as technical lead, not applied, and
   the optional request 10 not applied ([`foldin/`](foldin/README.md); integration log section 45).

**Left for the owner:** `CLAUDE.md`. On `m0-decisions` its milestone paragraph is still that of 22 October 2026, which
says that the gate branches and the M0 items are combined on `m0-integrate`, and this branch leaves the file exactly as
`m0-decisions` has it (`c72247a6`), so the merge changes nothing in it; no agent changes `CLAUDE.md` on a workflow's
request, so the text for the restated model is in [`claude-md-paragraph.md`](claude-md-paragraph.md), with a second
text for the toolchain line, which still says that whether 27A9275 is the release build awaits a check of Apple's
release notes, for the owner to apply on `m0-decisions`, or to have applied at the owner's request, before asking an
agent for anything, and at the latest in the same pause between sittings as the merge, right after it: the merge brings
that file, and the commands below apply it with the merge's. *(Until the fix of this branch's review, 26 October 2026,
this branch held the paragraph `6cede84a` wrote, which the merge of `m0-sessions` had brought: it names `m0-sessions` as
the branch of the M0 work and the sessions and says never to build on `m0-decisions`, and a merge into `m0-decisions`
would have put it there, for every agent asked to work from that branch to read until the owner replaced it. The fix
took `m0-decisions`'s file back, writing nothing in it: its finding FID-RU-03; [`fix-1/`](fix-1/README.md).)* *(Until
the fix of the same review's completeness findings, 27 October 2026, this paragraph set the texts no time but before the
owner's first request to an agent, apart from the merge, and named the paragraph alone: its finding CMP-01;
[`fix-1/completeness/`](fix-1/completeness/README.md). The message of the merge of `m0-sessions`, `4c0fa815`, says that
the next commit rewrites `CLAUDE.md`'s paragraph; no commit of this branch did, `d1fb3dd4` leaving it as merged until
that fix took `m0-decisions`'s file back, and a commit message is not rewritten: integration log 41.2.)* *(27 October
2026: the order is now fixed, in one pause between sittings, before Codex or any agent works in the checkout again:
your fast-forward merge of this branch; then
[`fix-1/owner/commands/apply-claude-md-texts.py`](fix-1/owner/commands/apply-claude-md-texts.py), which the merge
brings and you run, puts both texts in, changing nothing else in the file and refusing if either place is not found
exactly once; then the lock check and your commit (the merge section). Applied before the merge, by hand, they would
move `m0-decisions` on, and your merge would then wait for an agent's merge the other way. Until the fix of the
owner-readability findings of this branch's review, the texts were to be put in by hand, a paragraph of 2,893
characters, before or after the merge: its finding OWN-RU-04; [`fix-1/owner/`](fix-1/owner/README.md).)* *(27 October
2026, later: no longer left for you. The orchestrating session ran that command on this branch, in `6a510880`, "at the
owner's request of 24 October 2026 to update what was out of date, as 5aec2518 and 6cede84a were", as the commit's
message says, and the dependency lock check passed after it, so `CLAUDE.md` here holds both texts and your merge brings
them; the merge commands below no longer run the command, check its diff, run the lock check for it or commit it. The
texts' file and the command stay as the record of how it was done ([`foldin/`](foldin/README.md); integration log
section 45).)*

## Merging it into `m0-decisions`, between sittings

Between two sittings, once the sitting in progress is done and its records are committed on `m0-decisions` (runbook 0.3,
step 6), and before Codex or any agent works in `~/Git/sylvia-sessions` again (1.4's audio run was under way at
`c72247a6`, your last commit this branch holds). The merge is a fast-forward or nothing: `git merge --ff-only` moves
`m0-decisions` to this branch's head only when that head already holds every commit of `m0-decisions`, and otherwise
stops and changes nothing ("abort if fast-forward is not possible": `git merge -h`, git 2.55.0). So you never resolve a
conflict, and none of these records reaches `m0-decisions` beside a later record of yours that it no longer agrees with.
It brings everything this branch holds: the M0 exit preparation, the device-A change, these records as they now read,
`CLAUDE.md` with its two texts in (`6a510880`) and the device fixes of your first runs (`m0-device-fixes`, folded in:
[`foldin/`](foldin/README.md)), so you merge nothing else and put nothing in by hand. In a terminal:

```sh
cd ~/Git/sylvia-sessions
git status --short                                  # nothing uncommitted: commit the sitting's records first
git branch --show-current                           # m0-decisions
git log --oneline m0-records-update..m0-decisions   # must print nothing; if it prints a commit, stop here (below)
git merge --ff-only m0-records-update               # "Fast-forward"; if it refuses, nothing has changed (below)
git rev-parse HEAD                                  # note it in the session log, in a row for the merge
```

- **If the `log` line printed a commit, or the merge refused** (`fatal: Not possible to fast-forward, aborting.`, with
  `m0-decisions` left as it was): `m0-decisions` has commits this branch lacks, your records of a later sitting, a fix
  made with Codex, or another agent branch you merged first. Do not merge another way. Ask an agent to bring this branch
  up to date first, in a worktree of its own, never in `~/Git/sylvia-sessions`: to merge `m0-decisions` into
  `m0-records-update`, keeping every file and line `m0-decisions` holds exactly as committed (a conflict can come only
  where both changed the same lines of a file this branch changes, which `git diff --name-status c72247a6
  m0-records-update` lists: the ADRs and their index, the gate reports, the checklists, the runbook, the gate summary,
  the plan, the amendments, the integration log, the Stage 0 README, `M0-contracts.md`, the repository `README.md`,
  `CLAUDE.md`, `Docs/Licenses/third-party-inventory.md`, the Zip guard's two scripts, `Scripts/ci.d/70-g05-ai.sh`, the
  device fixes' code (the recovery package's `Sources` and `Tests` and the ATS probe's test file) and one evidence file,
  `M0-Integration/commands/gate-refresh-check.py` (the table below), and it is resolved by keeping your text); to bring
  the account of your sittings in these records up to date with your new commits, wherever a text of these records no
  longer agrees with your records, these records changing, never yours (the texts that give it: the gate summary's
  State line, Section 1's recommendation and item 2, Section 5.1 and Section 7's opening; the runbook's header; the
  plan's Status line; the reports' and checklists' notes on the steps your sittings ran, G0.4's status lines among them;
  the Stage 0 README; `grep -rln "first sittings" Docs README.md` lists more); to run
  [`fix-1/owner/commands/owner-records-intact.py`](fix-1/owner/commands/owner-records-intact.py) with `--owner-head`
  set to the commit `m0-decisions` is at, which checks every commit of `m0-decisions` since `044ed3cf`, and this
  branch's other checks, recording what they report; and to commit. Then run the commands above again: the merge is
  now a fast-forward. If you have already merged `m0-device-fixes` on its own, as its README's 7.1 asked before the
  fold-in, nothing changes: if that merge was a fast-forward, the `log` line prints nothing and this merge
  fast-forwards; if it made a merge commit, the `log` line prints it, and the agent's merge above takes it in.
- **If a merge ever stops on a conflict** (only a plain `git merge`, which these commands never use, can stop so):
  `git merge --abort` puts `m0-decisions` back as it was, with nothing changed; then ask an agent as the bullet above
  says.
- **After the merge,** in the same pause, look at what it brought rather than take it from this README, which cannot
  know what else will have reached `m0-decisions` by then (a branch merged before this one changes both answers):

  ```sh
  git diff --stat 9cdb0a02 HEAD -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery \
    Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1 \
    ':(exclude)Spikes/G05-Recovery/DeviceTests'                            # runbook 0.8
  git diff --stat <the commit your last sitting built from> HEAD -- Apps Packages Spikes Fixtures Scripts Contracts \
    Docs/Stage0/device-checklists                                           # runbook 0.3, step 7
  ```

  The first prints nothing when 0.8 still needs nothing; if it prints anything, 0.8 runs again before Session 6
  (runbook 0.8). The second lists every change since your last sitting that can call for a repeat: judge each under
  step 7's rule, which names the changes of this branch that need none (the checklists' wording, the Zip guard's two
  scripts, `Scripts/ci.d/70-g05-ai.sh` and, against a commit before `4be1a1a4`, your own `DeviceTests`) and those that
  call for one, and ask an agent, before the next sitting, what anything else it lists repeats; a repeat writes its
  logs under new names (runbook Section 2). What this branch itself brings is known: in a simulation of these commands
  in a scratch clone at the fold-in's documents commit, with `m0-decisions` at `c72247a6`, the first listed the eleven
  files of the recovery package's `Sources` and `Tests` that the device fixes changed, so 0.8 runs again, and the
  second, against `d5336111`, listed those, the ATS probe's test file, `Scripts/ci.d/70-g05-ai.sh`, the eight
  checklists and the Zip guard's two scripts, so 1.2 and 1.3 run again, with 0.8, and nothing else repeats for this
  merge ([`foldin/checks/merge-simulation.log`](foldin/checks/merge-simulation.log); at the fix of the owner-readability
  findings, before the fold-in, the first printed nothing and the second listed the checklists and the Zip guard's two
  scripts alone: [`fix-1/owner/checks/merge-simulation.log`](fix-1/owner/checks/merge-simulation.log)). Nothing goes to
  `main`.
- **Then, in order** (the runbook's header and the gate summary's Section 1, item 2, give the same steps): at the Mac,
  with the screen unlocked for each whole run, the device fixes' two class-B tests, which have never run, then runbook
  0.8, and, if you like, their host-facts probe for finding F-1
  ([`../M0-DeviceFixes/README.md`](../M0-DeviceFixes/README.md) 7.2, items 1-3; if a class-B test fails, ask an agent
  before 1.2); on phone B, 1.2 and then 1.3 again, as its 7.3 and 7.4 give them, under new log names, so that your first
  runs' records stay as you committed them; then the rest of Session 1, from where your records leave 1.4, and the other
  sessions in the runbook's order. Each run, and each step run again, gets a row in the session log, as before.

*(This section's history. Until the fix of the owner-readability findings of this branch's review, 27 October 2026, its
commands merged with `git merge m0-records-update`, which makes a merge commit when `m0-decisions` has moved on, and
had `CLAUDE.md`'s two texts put in by hand; its bullet on a moved-on `m0-decisions` had you merge all the same, said that
the files this branch does not change merge cleanly and left an agent only a textual conflict to resolve, so a clean
merge could leave these records saying what your later records contradict (the review's case: G0.4 step 1 not finished,
beside your own result for it), and checked no commit of yours after `c72247a6`; and "After the merge" stated that
nothing repeats and that 0.8 needs nothing, where it now runs the two checks: its findings OWN-RU-03 and OWN-RU-04;
[`fix-1/owner/`](fix-1/owner/README.md). Until the fix of the same review's completeness findings, the same day, that
bullet named only the gate reports, the checklists, the runbook, the gate summary and the ADRs as where a conflict could
come, and called the evidence folders untouched (its finding CMP-07), and `CLAUDE.md`'s texts had no latest time
(CMP-01); and until the fix of its fidelity findings, 26 October 2026, they were to be applied after the merge, which
then brought `6cede84a`'s paragraph to `m0-decisions` (FID-RU-03).)* *(27 October 2026: until the fold-in of the device
fixes, the commands also ran, in the same pause right after the merge, the command that puts `CLAUDE.md`'s two texts in,
checked its diff, ran the lock check and committed `CLAUDE.md`, which `6a510880` has since done on this branch; the
bullet on a moved-on `m0-decisions` named the files this branch changed before the fold-in and said nothing of
`m0-device-fixes` merged on its own; there was no bullet on a conflict, nor on the steps after the merge; and "After the
merge" gave as this branch's own result the first check printing nothing and the second listing the checklists and the
Zip guard's two scripts alone: [`foldin/`](foldin/README.md); integration log section 45.)*

## The checks

`commands/run-checks.sh` ran every check on this branch's last documents commit, with no uncommitted file, and wrote
the logs below; the commit after it adds them and nothing else. The logs of the checks run through the re-pin round's
`run-logged.sh` (`ci-contracts.log`, `12-dependency-lock.log`, `13-hard-rules.log`, `recheck-hon-ep.log`,
`decisions-branch.log`, `recheck-own.log`) and of the two gate checks open with a header that names the commit, the
uncommitted paths, the host and Xcode, the time and the load; `runbook-content-check.log`, `step-0.8-paths.log` and
`correction-texts.log` name the commit, the number of uncommitted paths and the time, without the host or the load; the
nine others start with their results, with no header: `owner-records-intact.log`, `check-records.log`,
`check-records-devicea.log`, `check-amendments.log`, `check-amendments-accuracy.log`, `mutation-checks.log`,
`runbook-coverage.log`, `gate-refresh-check.log` and `gate-refresh-check-old.log`. They ran in the same run, on
`1b852c2d`, the commit the headers name; `run-checks.sh` printed HEAD, the host and Xcode, the start, the load and the
overall result to its console, which was not committed. *(Until the fix of the completeness findings of this branch's
review, 27 October 2026, this paragraph said that each log's header names its commit, the uncommitted paths, the host
and Xcode, the time and the load: its finding CMP-07; [`fix-1/completeness/`](fix-1/completeness/README.md), whose
runner commits its console log.)* Host only: the build Mac, macOS 26.6.2 (25G83), Apple M5 Max, Xcode
27.1 (27A9275). No simulator was created or used, no device was contacted, nothing played audio and nothing was
fetched or pushed. Other jobs may have shared the Mac, so no timing here is a result. *(27 October 2026: the checks of
the fold-in of the device fixes, with what the earlier checks report since, by design, are in
[`foldin/`](foldin/README.md).)*

| Log | What ran | What it must show |
| --- | --- | --- |
| `owner-records-intact.log` | `commands/owner-records-intact.py` | The owner's eight commits as committed (above) |
| `step-0.8-paths.log` | `commands/step-08-paths.sh` | The drop-in's paths unchanged since `9cdb0a02` at `4c0fa815` and at this branch's head, `DeviceTests` set apart; the spike's folder changed only there; no file the drop-in uses names `DeviceTests` |
| `ci-contracts.log`, `12-dependency-lock.log`, `13-hard-rules.log` | `Scripts/ci.sh contracts`, `Scripts/ci.d/12-dependency-lock.sh`, `Scripts/ci.d/13-hard-rules.sh`, through the re-pin round's `run-logged.sh` | Each passes; the lock check reads the owner's `DeviceTests` lock and inventory entry (17 locks committed, 17 registered) with the Zip guard of `m0-exit-prep` (291 mutations), 0 failures and 0 warnings |
| `runbook-content-check.log`, `runbook-coverage.log` | The device-A update's content check (`../M0-DeviceA/instructions/commands/runbook-content-check.sh`, with its controls and limits) and `../M0-Integration/final-fix/commands/runbook-coverage.py` | Both pass |
| `check-amendments.log`, `mutation-checks.log` | This branch's amendments checker and its mutations (`commands/check-amendments.py`, `commands/mutation-checks.py`) | 0 failed checks; every mutation caught; the plan and the amendments as committed afterwards |
| `check-amendments-accuracy.log` | The accuracy fix's checker, unchanged (`../M0-DeviceA/fix-1/accuracy/commands/check-amendments.py`) | Fails exactly its check 10k, by design: four of the texts it pins were renumbered or replaced here (Appendix D's item of 24 October 2026 and this document's dated note now cite sections 38 and 37-38, and Section 9 names the newest checker) |
| `check-records.log`, `check-records-devicea.log` | This branch's check of the device-A records (`commands/check-records.py`) and the records part's (`../M0-DeviceA/commands/check-records.py`) | The first passes; the second fails exactly its checks of the ADR index's date (26 October 2026 since the device-A update's fixes, as on `m0-sessions`) and of the integration log's section 28 (36 since the renumbering), by design |
| `correction-texts.log` | `../M0-runbook/commands/check-correction-texts.py`, unchanged | Recorded as it reads: the corrections already applied report their old texts missing, as on both branches |
| `recheck-hon-ep.log`, `decisions-branch.log`, `recheck-own.log` | The two branches' latest rechecks: `m0-exit-prep`'s `recheck-hon-ep.py` and `decisions-branch.py` (`../M0-ExitPrep/fix-2/round-2/commands/`), `m0-sessions`'s `recheck-own.py` (`../M0-DeviceA/fix-1/owner/commands/`) | Recorded as they report: each pins texts and a state of the branch it was written on, which this integration changed on purpose (integration log 41.7 lists what each reports) |
| `gate-checks-exit-prep.log`, `gate-checks-devicea.log` (with their console logs) | The two branches' latest gate checks, unchanged (`../M0-ExitPrep/fix-2/round-2/commands/gate-checks.sh`, `../M0-DeviceA/fix-1/owner/commands/gate-checks.sh`) | Recorded as they report: each checks what changed since its own fix's start, a tree that held neither the other branch nor the owner's commits, so their parts on what changed fail by design; their parts that read the documents are as the rows above give them (integration log 41.7) |
| `gate-refresh-check.log`, `gate-refresh-check-old.log` | The gate summary's checker: this branch's version (`commands/gate-refresh-check.py`) and the version it replaces (`../M0-Integration/commands/gate-refresh-check.py`), run last, since the summary cites this folder's logs | The first passes: every cited path exists and every Section 2 status agrees with its records (passed-host 12, failed 4). The second reports exactly row 76, by design: it expects failed, with ADR-0014 saying no review accepted the Zip guard's change *(27 October 2026: the second is the text `m0-exit-prep` left, which of the earlier rounds only that branch's fourth and fifth fixes ran: that branch rewrote its row 76 entry in place, in `83ed5ff3`, `944a6302`, `f95de709` and `9f5edab1`, as the file's comment on that row says, from the text of 20 October 2026 (`05bdea4d`) that `m0-decisions` holds and that the gate checks of the M0 decisions round and of the device-A update ran; the rounds before it, from the refresh of 19 October 2026, ran earlier texts (`bee34069` to `10c881ce`), each the one at its commit. It is the one existing evidence file this branch changes, so the merge brings that text to `m0-decisions`: `git diff --name-status c72247a6 HEAD -- Docs/Stage0/evidence/` lists it alone besides the added files. The review's finding CMP-04; [`fix-1/completeness/`](fix-1/completeness/README.md).)* |

Not run, and why: the complete CI (outside `Docs/` this branch changed only the root `README.md`'s sentence on the
branches; the code it brings is the Zip guard, which `12-dependency-lock` runs, and the owner's `DeviceTests`, which no
drop-in builds); G0.5 recovery's drop-in (0.8's check finds nothing it uses changed); `resolve-locks.sh` and `linkage.sh`
(they resolve packages, which can reach git remotes); the review records' check against their extraction (the
extraction is in the orchestrating session's folder, outside this worktree); anything on a device.

## What stays pending

The device sessions that block the M0 exit, from where the owner's first sittings left them (the gate summary's Section 1,
item 2); the owner's one-line confirmation of Xcode 27.1 as technical lead; the owner's security, design, QA,
technical-lead, persistence-owner and release-owner sign-offs; the ADR approvals (D-6); the M0 exit review; `CLAUDE.md`'s
two texts; and a review of this branch. *(26 October 2026: an agent review read it at `832a3636`; the fix of its
fidelity findings, [`fix-1/`](fix-1/README.md), has not been reviewed, and the review's other lenses' findings go to the
fixes that follow it.)* *(27 October 2026: the fix of its completeness findings,
[`fix-1/completeness/`](fix-1/completeness/README.md), has not been reviewed either.)* *(27 October 2026: nor has the
fix of its owner-readability findings, [`fix-1/owner/`](fix-1/owner/README.md); and your merge of this branch, a
fast-forward, waits for an agent's merge of `m0-decisions` into it first if `m0-decisions` has moved on since
`c72247a6`, as it will have once you commit the records of 1.4's audio run or merge another branch: the merge
section.)* *(27 October 2026: `CLAUDE.md`'s two texts are no longer pending: they are in, on this branch (`6a510880`).
Since the fold-in of the device fixes, also pending: after your merge, their two class-B tests and runbook 0.8 on the
Mac with the screen unlocked, and 1.2 and 1.3 again on phone B (the merge section, "Then, in order"); two decisions for
you as technical lead, neither applied, findings F-1 (`FileProtector.verify` reads a cached class) and S5 (`copyFile`'s
`O_NOFOLLOW` covers the last component only), each with its proposed change in the G0.5 recovery report's decisions
pending for the technical lead, after its open questions; the lock harness's quiet-tone test, which failed in all four runs on the build Mac on 26 October 2026
and which 0.8 runs again (the report's row 25); and a review of the fold-in ([`foldin/`](foldin/README.md)).)*
