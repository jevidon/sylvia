#!/usr/bin/env python3
"""Checks the fix of the owner-readability findings of the review of the update of 24 October 2026 and its assembly (26
October 2026 on the build Mac's clock; integration log section 32), which cite m0-sessions at 8082bdb6; the fix was made
from caf75a84, the last commit of the fix of the same review's completeness findings. One item per finding, and one for
the review status:
  checkout      OWN-DA-01: run 1's step 1, in the gate summary's item 1 and the runbook's 0.3, says that the merge of the
                checkout's branch into m0-sessions is made between sittings, once the owner says the sitting in progress
                is done, that the switch waits for it, and that until then an agent starts from m0-sessions without the
                sittings' records; the earlier fixes' case for a checkout on another branch kept; the Stage 0 README says
                when the merge is made; item 141; this fix's read of the branches and its computed merges committed, the
                read showing the checkout on m0-decisions at c72247a6, the merges m0-decisions still at c72247a6 and
                merging without a conflict;
  ran           OWN-DA-02: the gate summary's opening says where the sittings are recorded and that their records have
                not been reviewed, and Section 5.1, Section 7, the runbook's header and the Stage 0 README that they have
                not been reviewed, the earlier fixes' texts kept; item 142;
  host          OWN-DA-03: the runbook's 1.5 says what Session 1 found, in a bullet of its own, quoting Xcode's message as
                the log on m0-decisions has it, with the log and the commit that added DeviceTests, and that DeviceTests
                has not been reviewed; the bullet whose question it answers, which m0-decisions changes, kept as it was at
                caf75a84, so that the merge of m0-decisions stays without a conflict; the G0.5 recovery checklist's setup
                note on its device commands; the runbook's 0.3, step 7, lists that note among the changes that need no
                repeat; item 143;
  confirm       OWN-DA-04: ADR-0001's open item for the technical lead and the runbook's D-3 note say where the one-line
                confirmation is written until m0-exit-prep is merged; the third fix's texts in item 1's step 7, 0.2 and
                the technical-lead part kept; item 144; the merge of m0-exit-prep, computed, conflicting in the same files
                into HEAD as into caf75a84;
  edits         OWN-DA-05: item 4 of the gate summary lists the edits of the records left to the owner (the session log,
                CLAUDE.md's two lines with the texts asked); item 1's opening and the runbook's Section 2 point to it;
                the session log left as it was; item 145;
  dates         OWN-DA-06: pull request #6's merge dated 23 October 2026 at 15:34 UTC, with the build Mac's date, in the
                places the finding names and the ones beside them, and the second reading of Apple's pages at 17:49 UTC on
                23 October 2026, the old texts gone; the merge commit's date and the reading's log as the texts give
                them; item 146;
  ios27         OWN-DA-07: the runbook's 1.1 row A cites Apple's list of iPhones compatible with iOS 27, which has the
                iPhone 13 mini, and its first cell allows 27.x, the old texts gone; this fix's read of that page passing;
                item 147;
  merge-where   OWN-DA-08: the runbook's 0.3, step 5, and the gate summary's item 1, step 5, say that once the checkout is
                on m0-sessions agent work is merged in ~/Git/sylvia-sessions itself, the command the assembly's recheck
                reads kept; item 148;
  d01           OWN-DA-09: the gate summary's D01 row calls device A the small-screen baseline, in the past tense, with a
                dated note, its old words gone; the plan's D01 row has the wording the note cites; item 149;
  review        this fix, not reviewed, where the records give the review status of the update's fixes: the gate summary
                (Section 6.2's row and paragraph, items 141-150, Section 7's item 5, Section 8's Branch, bullet and
                Written by), the runbook's Who wrote it, the Stage 0 README, integration log section 32, ADR-0001's
                Status, the evidence READMEs of the records part and of the first three fixes, this fix's README and the
                findings as relayed.
    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/owner/commands/recheck-own.py <repository root> [<tree root>]
The texts are read from the tree root (by default the repository root); m0-decisions's log is read from the repository.
Run on the tree of caf75a84 (git archive), the commit this fix started from, it must report all ten items: the gate
checks beside this file run that control. Read-only; standard library only; host only. Prints one line per item and
exits 1 if any is not as stated.
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
ROOT = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else REPO
problems = 0
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
STAGE0 = "Docs/Stage0/README.md"
LOG = "Docs/Stage0/integration-log.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
EV = "Docs/Stage0/evidence/M0-DeviceA/"
HERE = EV + "fix-1/owner/"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
CL = "Docs/Stage0/device-checklists/"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
XCODE = ("Tool-hosted testing is unavailable on device destinations. Select a host application for the test target, or "
         "use a simulator destination instead.")
PR6 = "on 23 October 2026 at 15:34 UTC"


def read(path):
    p = ROOT / path
    return p.read_text(encoding="utf-8") if p.is_file() else ""


def joined(path):
    """A hard-wrapped Markdown file with its lines joined, for phrases that may cross a line break."""
    return re.sub(r"\s*\n\s*", " ", read(path))


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True)


def line_with(text, start):
    found = [line for line in text.splitlines() if line.startswith(start)]
    return found[0] if len(found) == 1 else ""


def block(text, start, end):
    lines = text.splitlines()
    first = [i for i, l in enumerate(lines) if l.startswith(start)]
    if len(first) != 1:
        return ""
    rest = [i for i in range(first[0] + 1, len(lines)) if lines[i].startswith(end)]
    return "\n".join(lines[first[0]:rest[0] if rest else len(lines)])


def need(text, phrases, where):
    return [f"{where} lacks: {p}" for p in phrases if p not in text]


def gone(text, phrases, where):
    return [f"{where} still says: {p}" for p in phrases if p in text]


def report(item, missing, what):
    global problems
    if missing:
        problems += 1
    print(f"{'as stated' if not missing else 'PROBLEM  '} {item}: {what}" + (f" ({'; '.join(missing)})" if missing else ""))


runbook, gate, stage0, log, plan, adr01 = (read(p) for p in (RUNBOOK, GATE, STAGE0, LOG, PLAN, ADR01))
repo_readme = read("README.md")
readme = joined(HERE + "README.md")
header6 = line_with(runbook, "- **No device result is recorded on this branch yet.**")
header7 = line_with(runbook, "- **Your decisions of 22 October 2026 are in it**")
header8 = line_with(runbook, "- **Your decision of 24 October 2026, and the branch you build from since then.**")
row_a = line_with(runbook, "| **A. Device A, the small-screen baseline: your iPhone 13 mini**")
step15 = line_with(runbook, "- **G0.5 recovery on a phone, as Session 1 found it** (26 October 2026).")
step15_pkg = line_with(runbook, "- **G0.5 recovery** is a Swift package:")
then = line_with(runbook, "- **Then:** in the gate's report, change each row")
step02 = block(runbook, "**0.2 Xcode account", "**0.3 Commit**")
step03 = block(runbook, "**0.3 Commit**", "**0.4 Devices.**")
step031 = line_with(step03, "1. `git branch --show-current` reads `m0-sessions`")
step033 = line_with(step03, "3. Done: pull request #6 merged `m0-decisions` into `main`")
step035 = line_with(step03, "5. **Agent work.**")
step037 = line_with(step03, "7. **When a session already run is repeated:**")
d3 = line_with(runbook, "- **D-3** The Xcode build to pin")
tech = next((line for line in runbook.splitlines()
             if "First, before Session 0, your confirmation that Xcode 27.1 (27A9275) is the release build" in line), "")
who = line_with(runbook, "- **Who wrote it.**")
opening = line_with(gate, "**Recommendation** (Section 7)")
item1 = block(gate, "**1. Before the first session**", "**2. The device sessions**")
item1_open = line_with(gate, "**1. Before the first session**")
item11 = line_with(item1, "1. **Check that `~/Git/sylvia-sessions` is on `m0-sessions`**")
item13 = line_with(item1, "3. **Done: `m0-decisions` merged into `main`**")
item15 = line_with(item1, "5. **The two requests of item 4: asked, and in progress.**")
item17 = line_with(item1, "7. **As technical lead, confirm that Xcode 27.1 (27A9275) is the release build: one line**")
item4 = block(gate, "**4. Two requests the exit waits for", "**The drop-in run.**")
pr5 = line_with(gate, "- **Pull request #5** (merge commit `4c73da57`)")
pr6 = line_with(gate, "- **Pull request #6, `m0-sessions`, and your decision on device A (24 October 2026).**")
d01 = line_with(gate, "| D01 Platform floor (iOS/iPadOS 26+, macOS 26+) |")
s51 = block(gate, "### 5.1 Device and human steps", "**Blocking the M0 gate**")
s54 = block(gate, "### 5.4 ", "## 6. ")
s62_row = line_with(gate, "| The review of the update of 24 October 2026 and its assembly (26 October 2026, at `8082bdb6`) |")
s7 = block(gate, "## 7. Recommendation", "## 8. ")
s8 = block(gate, "## 8. About this summary", "## 9. ")
branch_line = line_with(gate, "- **Branch:**")
s32 = block(log, "## 32. ", "## 33. ")
adr_status = line_with(adr01, "- **Status:**")
adr_tech = next((line for line in adr01.splitlines() if line.startswith("- Technical lead, before or with the pin's "
                                                                          "confirmation at the M0 gate")), "")
checklist = read(CL + "G05-Recovery.md")
branch_log = read(HERE + "checks/branch-state.log")
merges_log = read(HERE + "checks/merges.log")
apple_log = read(HERE + "checks/apple-ios27-page.log")

# checkout: OWN-DA-01.
WHEN = ("That merge, too, is made between your sittings, once you have told the orchestrating session that the sitting "
        "in progress is done (as step 6 has an agent wait for your word before it commits a sitting's records), and the "
        "switch waits for it, not only for this update's review.")
AGENT = ("Until it is made, an agent you ask starts from `m0-sessions`, which holds none of your sittings' records: if you "
         "want one to work from them (a result to diagnose, a report row to change), ask for the merge first.")
KEPT = ["If it reads another branch, do not switch it yourself", "Until the switch, steps 4 and 6 apply to the branch the "
        "checkout is on", "nor, once that merge is made, from `m0-decisions`"]
m = need(step031, [WHEN, AGENT, "its findings OWN-DA-01 and OWN-DA-06.)", "once everything the checkout's branch has that "
                   "`m0-sessions` lacks is merged into `m0-sessions`"] + KEPT, "the runbook's 0.3, step 1")
# Item 1's step 1 says it in short, within the 400 words the follow-up's check of OWN4-09 allows a step of item 1, its
# history note pointing to items 116 and 141, which holds what the note said until this fix.
m += need(item11, ["That merge waits for your word that the sitting in progress is done; until then an agent you ask sees "
                   "none of your sittings' records (runbook 0.3, step 1).", "(This step's history: Section 6.3, items 116 "
                   "and 141; until the fix of the same review's completeness findings, the same day, it said that 0.8 runs "
                   "again after the merge: item 137.)", "once whatever the checkout's branch has that `m0-sessions` lacks "
                   "is merged into `m0-sessions`"] + KEPT, "M0-gate.md item 1, step 1")
pieces = re.split(r"(?m)^(?=\d+\. )", item1)
longest = max((len(p.split()) for p in pieces), default=0)
m += [f"a step of item 1 has {longest} words (at most 400)"] if longest > 400 else []
m += need(gate, ["To keep item 1's step 1 within the 400 words the follow-up's check of its finding OWN4-09 allows a step "
                 "of item 1, its history note now points here, and to item 116, for what it said until this fix: \"(Until "
                 "26 October 2026 this step said that the switch was from `main` at `96bdc7e9`, and that `m0-decisions` "
                 "was behind `main`: item 116;"], "M0-gate.md Section 6.3, item 141")
m += need(stage0, ["before that checkout moves to it, between sittings, once the product owner says the sitting in "
                   "progress is done (runbook 0.3, step 1)"], "the Stage 0 README")
m += need(gate, ["141. **Your checkout, the merge before it moves, and when that merge is made** (OWN-DA-01, blocker)",
                 "Not done here, a fourth time: the merge itself."], "M0-gate.md Section 6.3")
if ("branch refs/heads/m0-decisions" not in branch_log or "m0-decisions behind main (an ancestor of it): no" not in
        branch_log or "merge-tree exit: 0" not in branch_log or "exit: 0" not in branch_log):
    m.append("this fix's branch-state.log is missing, or does not show the checkout on m0-decisions, m0-decisions not "
             "behind main and a merge without a conflict")
if ("m0-decisions is still at c72247a6" not in merges_log or "== 1. m0-decisions into HEAD\n   merge-tree exit: 0" not in
        merges_log or not merges_log.rstrip().endswith("exit: 0")):
    m.append("this fix's merges.log is missing, or does not show m0-decisions still at c72247a6, merging without a conflict")
report("checkout", m, "run 1's step 1 says when the merge before the switch is made, and what an agent sees until then; "
       "the earlier fixes' case for a checkout on another branch kept; the Stage 0 README; item 141; the branches and the "
       "merges logged")

# ran: OWN-DA-02.
# The opening says it in short, within the 600 words (800 with the State line) the follow-up's check of OWN5-05 allows.
m = need(opening, ["No device or human step's result is recorded here yet (your sittings, on `m0-decisions`, unreviewed: "
                   "item 1)", "(This paragraph's history: Section 6.3, item 88.)"], "M0-gate.md's opening")
state = line_with(gate, "- **State:**")
if len(opening.split()) > 600 or len(opening.split()) + len(state.split()) > 800:
    m.append(f"the opening has {len(opening.split())} words (at most 600), {len(opening.split()) + len(state.split())} "
             "with the State line (at most 800)")
m += need(s51, ["No result of a device step in it is recorded here yet (your first sittings, on phone B from 25 October "
                "2026 UTC, are recorded on `m0-decisions`, and reach these records when merged into `m0-sessions`: "
                "Section 1, item 1, step 1), and their records there have not been reviewed;", "this paragraph did not "
                "say that your sittings' records have not been reviewed: item 142.)"], "M0-gate.md Section 5.1")
m += need(s7, ["no device or human step's result is recorded here yet (your first sittings, recorded on `m0-decisions` "
               "and not reviewed, reach these records when merged into `m0-sessions`"], "M0-gate.md Section 7")
m += need(header6, ["Your first sittings, on phone B from 25 October 2026 (UTC), were built from `96bdc7e9` and later "
                    "commits of `m0-decisions` and recorded on `m0-decisions`", "their records there have not been "
                    "reviewed, they reach this branch only when merged into it, before your checkout moves to it (0.3, "
                    "step 1)", "its finding OWN-DA-02)."], "the runbook's header")
m += need(stage0, ["their records there have not been reviewed, and these records read none of their results"],
          "the Stage 0 README")
m += need(gate, ["142. **What these records say has run** (OWN-DA-02, major)"], "M0-gate.md Section 6.3")
report("ran", m, "the gate summary's opening says where the sittings are recorded; it, Section 5.1, Section 7, the "
       "runbook's header and the Stage 0 README say that their records have not been reviewed; item 142")

# host: OWN-DA-03.
attempt = git("show", "m0-decisions:Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log").stdout
m = need(step15, ["Session 1 has answered the bullet above on whether `xcodebuild test` signs the recovery package's "
                  "tests for the phone: a phone cannot run them from the package.", f"`{XCODE}`",
                  "(`Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log` on `m0-decisions`, at `c72247a6`, where "
                  "your first sittings are recorded; not reviewed)", "`Spikes/G05-Recovery/DeviceTests`, an app that hosts "
                  "the suite on the phone (`4be1a1a4` there)", "until then, run 1.2, 6.3 and 8.10 with the commands of the "
                  "runbook on the branch your checkout is on (1.2's note)", "`DeviceTests` has not been reviewed.",
                  "its finding OWN-DA-03; the bullet above keeps its words here, since `m0-decisions` changes that line "
                  "and the merge brings its text"], "the runbook's 1.5, its bullet on what Session 1 found")
if XCODE not in attempt:
    m.append("the message the runbook's 1.5 quotes is not in step-1-tests.log on m0-decisions")
# The bullet that m0-decisions changes is kept as it was at caf75a84, so that the merge of m0-decisions stays without a
# conflict (merges.log, checked under checkout); its question is answered by the bullet above.
kept = subprocess.run(["git", "-C", str(REPO), "show", "caf75a8447597efa5076b53b9a0d36be0fdcc901:" + RUNBOOK],
                      capture_output=True, text=True).stdout
old15 = [l for l in kept.splitlines() if l.startswith("- **G0.5 recovery** is a Swift package:")]
if not old15 or step15_pkg != old15[0]:
    m.append("the runbook's 1.5 bullet on the recovery package, which m0-decisions changes, is not as it was at caf75a84")
m += need(checklist, ["- The device commands of steps 1, 2.4 and 4 below run the package's own scheme, which Xcode refuses "
                      "to run on a phone", "use this checklist on the branch your checkout is on", "its finding OWN-DA-03; "
                      "wording only: no step's action, expected result or rule changes.)"], "the G0.5 recovery checklist")
m += need(step037, ["the G0.5 recovery checklist's setup note on its device commands, which `m0-decisions` changes"],
          "the runbook's 0.3, step 7")
m += need(gate, ["143. **The recovery suite on a phone** (OWN-DA-03, major)", "Not done here: a reviewed device host in "
                 "this branch's checklist and in 1.2, 6.3 and 8.10."], "M0-gate.md Section 6.3")
report("host", m, "the runbook's 1.5 says what Session 1 found, Xcode's message as the log on m0-decisions has it; the "
       "checklist's setup note; 0.3, step 7, lists it; item 143")

# confirm: OWN-DA-04.
m = need(adr_tech, ["Until that run's branch is merged into `m0-sessions`, this record is that run's to change (the "
                    "device runbook's 0.3, step 5): the technical lead writes the line in the session log's row for run 1 "
                    "(the runbook's 0.2), and it is copied here with or after that merge.", "its finding OWN-DA-04.)"],
          "ADR-0001's open item for the technical lead")
m += need(d3, ["written in the session log's row for run 1 until the `m0-exit-prep` run, which changes ADR-0001, is "
               "merged into `m0-sessions`, and copied into ADR-0001 then (0.2; added on 26 October 2026, after the review "
               "of the update of 24 October 2026, its finding OWN-DA-04)"], "the runbook's D-3 note")
m += need(item17, ["write your line in the session log's row for run 1, on the branch your checkout is on (step 1), and "
                   "have it copied into ADR-0001's open item for the technical lead once that merge is made"],
          "M0-gate.md item 1, step 7")
m += need(step02, ["Write it in the session log's row for run 1, on the branch your checkout is on (0.3, step 1)"],
          "the runbook's 0.2")
m += need(tech, ["written in the session log's row for run 1 and copied into ADR-0001 after that merge"],
          "the runbook's technical-lead part")
m += gone(adr01, ["That 27A9275 is the non-beta release has not been checked against Apple's release notes"], "ADR-0001")
m += need(gate, ["144. **Where your one-line Xcode confirmation goes** (OWN-DA-04, major)"], "M0-gate.md Section 6.3")
if "the same files: this fix adds no file that conflicts" not in merges_log:
    m.append("this fix's merges.log does not show the merge of m0-exit-prep conflicting in the same files as before")
report("confirm", m, "ADR-0001's open item and the D-3 note say where the line goes until m0-exit-prep is merged; the "
       "third fix's texts kept; item 144; the merge of m0-exit-prep conflicting in the same files")

# edits: OWN-DA-05.
m = need(item4, ["- **Edits of the records left to you, or to an agent or the orchestrating session you ask** (no agent "
                 "makes them on a workflow's request; Section 6.3, item 145): the session log "
                 "(`evidence/M0-runbook/sessions.md`)", "and rows 1 and 8 then take the new text "
                 "`evidence/M0-DeviceA/assembly/README.md` gives", "`CLAUDE.md`, whose milestone paragraph still calls "
                 "`m0-decisions` behind `main` and whose toolchain line still gives Apple's release notes as unchecked: the "
                 "texts asked for both are in `evidence/M0-DeviceA/fix-1/completeness/README.md`", "and after a change "
                 "`Scripts/ci.d/12-dependency-lock.sh`, which compares that line's pin with the inventory's, runs again."],
          "M0-gate.md item 4")
m += need(item1_open, ["Item 4 lists every edit of the records left to you, these rows and `CLAUDE.md`'s two lines among "
                       "them (Section 6.3, item 145)."], "M0-gate.md item 1's opening")
m += need(then, ["The edits of the records left to you, or to an agent you ask, these two rows and `CLAUDE.md`'s two lines "
                 "among them, are listed in `M0-gate.md` Section 1, item 4. *(Added the same day, after the same review's "
                 "finding OWN-DA-05.)*"], "the runbook's Section 2")
sessions = read(SESSIONS)
m += need(sessions, ["| 8 | 8 Device A, your iPhone 11 Pro (after Session 4) |", "(1) `m0-decisions` checked out",
                     "No device step has been run."], "the session log (left as it was, to change with the merge)")
completeness = joined(EV + "fix-1/completeness/README.md")
m += need(completeness, ["Never build on `m0-integrate`, which is behind `main`, nor on `m0-decisions` once its commits "
                         "after `044ed3cf` are merged into `m0-sessions`", "whether 27A9275 is the non-beta release awaits "
                         "the technical lead's one-line confirmation of Apple's pages"],
          "the third fix's README, the texts item 4 points to")
m += need(gate, ["145. **The edits of the records left to you** (OWN-DA-05, major)"], "M0-gate.md Section 6.3")
report("edits", m, "item 4 lists the edits of the records left to the owner, with the texts asked for CLAUDE.md; item 1's "
       "opening and the runbook's Section 2 point to it; the session log left as it was; item 145")

# dates: OWN-DA-06.
pages = read("Docs/Stage0/evidence/M0-DeviceA/instructions/checks/apple-pages.log")
ad = git("log", "-1", "--format=%ad", "--date=iso", "96bdc7e9").stdout.strip()
m = need(header7, ["pull request #6 made that merge on 23 October 2026 at 15:34 UTC, 24 October on the build Mac's clock",
                   "its finding OWN-DA-06)"], "the runbook's header, on your decisions of 22 October 2026")
m += need(header8, ["Pull request #6 merged `m0-decisions` into `main` (`96bdc7e9`) on 23 October 2026 at 15:34 UTC (24 "
                    "October on the build Mac's clock;", "made from `main` on 24 October 2026 with `CLAUDE.md`'s "
                    "correction"], "the runbook's header, on the branch")
m += need(step031, ["(`96bdc7e9`, merged on 23 October 2026 at 15:34 UTC, 24 October on the build Mac's clock)"],
          "the runbook's 0.3, step 1")
m += need(step033, ["on 23 October 2026 at 15:34 UTC (24 October on the build Mac's clock; `96bdc7e9`)",
                    "its finding OWN-DA-06.)"], "the runbook's 0.3, step 3")
m += need(step02, ["read them again at 17:49 UTC on 23 October 2026, 24 October on the build Mac's clock"],
          "the runbook's 0.2")
m += need(opening, ["On 23 October 2026 UTC (24 October on the build Mac's clock) pull request #6 made that merge "
                    "(`96bdc7e9`), the sessions' branch became `m0-sessions` (item 1)"], "M0-gate.md's opening")
m += need(item13, ["by pull request #6 on 23 October 2026 at 15:34 UTC (24 October on the build Mac's clock; "
                   "`96bdc7e9`)", "Section 6.3, item 146.)"], "M0-gate.md item 1, step 3")
m += need(item17, ["read them again at 17:49 UTC on 23 October 2026, 24 October on the build Mac's clock"],
          "M0-gate.md item 1, step 7")
m += need(pr5, ["which pull request #6 made " + PR6], "M0-gate.md's bullet on pull request #5")
m += need(pr6, ["Pull request #6 merged `m0-decisions` into `main` (`96bdc7e9`) " + PR6 + ", 24 October on the build "
                "Mac's clock", "Section 6.3, item 146.)*"], "M0-gate.md's bullet on pull request #6")
m += need(s54, ["which pull request #6 made " + PR6], "M0-gate.md Section 5.4")
m += need(branch_line, ["pull request #6 merged `m0-decisions` into `main` " + PR6], "M0-gate.md Section 8's Branch line")
m += need(repo_readme, ["which pull request #6 merged into main " + PR6], "README.md")
m += need(stage0, ["On 23 October 2026 at 15:34 UTC (24 October on the build Mac's clock) pull request #6 merged"],
          "the Stage 0 README")
m += need(adr_status, ["and an agent again at 17:49 UTC on 23 October 2026 (24 October on the build Mac's clock)"],
          "ADR-0001's Status")
OLD = ["The same day pull request #6 merged `m0-decisions` into `main` (`96bdc7e9`)",
       "pull request #6 merged `m0-decisions` into `main` on 24 October 2026 (`96bdc7e9`)",
       "On 24 October 2026 pull request #6 made that merge (`96bdc7e9`)",
       "by pull request #6 on 24 October 2026 (`96bdc7e9`)", "which pull request #6 made on 24 October 2026",
       "which pull request #6 merged into main on 24 October 2026", "On 24 October 2026 pull request #6 merged",
       "pull request #6 made that merge on 24 October 2026"]
for where, text in (("the runbook", runbook), ("M0-gate.md", gate), ("README.md", repo_readme),
                    ("the Stage 0 README", stage0), ("ADR-0001", adr01)):
    m += gone(text, OLD, where)
# The second reading of Apple's pages: the live texts that said "the same day" (Section 6.3's item 107, a record of what
# the update did, keeps its words, with a dated note; ADR-0001's dated note quotes the old ones).
m += gone(step02, ["read them again the same day"], "the runbook's 0.2")
m += gone(item17, ["read them again the same day"], "M0-gate.md item 1, step 7")
m += gone(adr_status, ["and an agent again the same day:"], "ADR-0001's Status")
m += need(gate, ["*(26 October 2026: that agent's reading was at 17:49 UTC on 23 October 2026, 24 October on the build "
                 "Mac's clock, and until `m0-exit-prep` is merged into `m0-sessions` your line goes in the session log's "
                 "row for run 1: items 146, 139 and 144.)*"], "M0-gate.md Section 6.3, item 107")
if ad != "2026-10-24 04:34:37 +1300":
    m.append(f"the merge commit 96bdc7e9 is dated {ad}, not 2026-10-24 04:34:37 +1300 (23 October, 15:34 UTC)")
if "read: 2026-10-23T17:49:55Z (UTC; the build Mac's date: 2026-10-24)" not in pages:
    m.append("the instructions part's apple-pages.log does not give the reading as 2026-10-23T17:49:55Z")
m += need(gate, ["146. **Dates of pull request #6's merge and of the second reading of Apple's pages** (OWN-DA-06)"],
          "M0-gate.md Section 6.3")
report("dates", m, "pull request #6's merge dated 23 October 2026 at 15:34 UTC with the build Mac's date, and the second "
       "reading of Apple's pages at 17:49 UTC on 23 October, where the texts gave the build Mac's date alone or the same "
       "day; the old texts gone; the commit's date and the log as given; item 146")

# ios27: OWN-DA-07.
m = need(row_a, ["375 × 812 pt), on the iOS it has, 26.x, or 27.x if that is what it runs or all it is offered | "
                 "Session 8 |", "or Software Update offers only iOS 27, which supports it (Apple's list of iPhones "
                 "compatible with iOS 27 has the iPhone 13 mini: [Apple Support](https://support.apple.com/guide/iphone/"
                 "iphone-models-compatible-with-ios-27-iphe3fa5df43/27/ios/27), read on 25 October 2026 UTC",
                 "[`apple-ios27-page.log`](evidence/M0-DeviceA/fix-1/owner/checks/apple-ios27-page.log)",
                 "its finding OWN-DA-07.)"], "the runbook's 1.1 row A")
m += gone(row_a, ["(whether iOS 27 supports the iPhone 13 mini was not checked)", "375 × 812 pt), on the iOS 26.x it has "
                  "| Session 8 |"], "the runbook's 1.1 row A")
if ("present: \"iOS 27, which is compatible with the following models: iPhone 11 iPhone 11 Pro iPhone 11 Pro Max iPhone "
        "12 mini iPhone 12 iPhone 12 Pro iPhone 12 Pro Max iPhone 13 mini iPhone 13\"" not in apple_log
        or "result: pass (0 problem(s))" not in apple_log):
    m.append("this fix's apple-ios27-page.log is missing, or does not show the list with the iPhone 13 mini, passing")
m += need(gate, ["147. **iOS 27 on the iPhone 13 mini** (OWN-DA-07)"], "M0-gate.md Section 6.3")
report("ios27", m, "the runbook's 1.1 row A cites Apple's iOS 27 list, which has the iPhone 13 mini, and allows 27.x in "
       "its first cell; this fix's read of the page; item 147")

# merge-where: OWN-DA-08.
m = need(step035, ["(`git checkout m0-sessions`, then `git merge <its branch>`, by you or by an agent you ask)",
                   "Once `~/Git/sylvia-sessions` is on `m0-sessions` (step 1), that merge is made in "
                   "`~/Git/sylvia-sessions` itself, where `git checkout m0-sessions` then changes nothing, by you or by an "
                   "agent you ask to work there: git lets a branch be checked out in one worktree only, so an agent in a "
                   "worktree of its own cannot check out `m0-sessions` while your checkout has it", "its finding "
                   "OWN-DA-08)"], "the runbook's 0.3, step 5")
m += need(item15, ["Once `~/Git/sylvia-sessions` is on `m0-sessions`, that merge is made in that checkout itself, by you "
                   "or by an agent you ask to work there", "Section 6.3, item 148)."], "M0-gate.md item 1, step 5")
m += need(gate, ["148. **Where agent work is merged once your checkout is on `m0-sessions`** (OWN-DA-08)"],
          "M0-gate.md Section 6.3")
report("merge-where", m, "0.3, step 5, and item 1's step 5 say that agent work is merged in ~/Git/sylvia-sessions itself "
       "once it is on m0-sessions, the command kept; item 148")

# d01: OWN-DA-09.
m = need(d01, ["device A, the small-screen baseline, is your iPhone 13 mini", "its owners changed plan 19.1 and ADR-0001 "
               "with it", "its D01 row calls A the baseline for small-screen layout on a device", "Until 26 October 2026 "
               "this note called device A the baseline, unqualified, and gave those changes as still to make: Section "
               "6.3, item 149.)*"], "M0-gate.md's D01 row")
m += gone(d01, ["device A, the baseline, is your iPhone 13 mini", "its owners change plan 19.1 and ADR-0001 with it"],
          "M0-gate.md's D01 row")
m += need(line_with(plan, "| D01 - Platform floor |"), ["Device A, the baseline for small-screen layout on a device, is an "
                                                        "iPhone 13 mini"], "the plan's D01 row")
m += need(gate, ["149. **Device A in this summary's D01 row** (OWN-DA-09)"], "M0-gate.md Section 6.3")
report("d01", m, "the gate summary's D01 row calls device A the small-screen baseline, in the past tense, with a dated "
       "note; the plan's wording as the note cites it; item 149")

# review: this fix, not reviewed.
m = need(s62_row, ["Then 9 more, as relayed to a fourth fix: owner readability OWN-DA-01 to OWN-DA-09", "The nine answered "
                   "the same day by the fix of its owner-readability findings (items 141-150)", "| integration log "
                   "sections 29, 30, 31 and 32 |", "`evidence/M0-DeviceA/fix-1/owner/checks/finding-lines.log`",
                   "`evidence/M0-DeviceA/fix-1/owner/relayed-findings.md`"], "M0-gate.md Section 6.2's row")
m += need(gate, ["And its nine owner-readability findings, one of them a blocker and four major, a fourth fix answers "
                 "(items 141-150), which has not been reviewed either.", "150. **Not reviewed**: this fix is agent-written",
                 "and until the fix of its owner-readability findings, the same day, at the fix of its completeness "
                 "findings.)"], "M0-gate.md Sections 6.2 and 6.3")
for n in range(141, 151):
    if not re.search(rf"^{n}\. \*\*", gate, re.M):
        m.append(f"M0-gate.md Section 6.3 lacks item {n}")
m += need(s7, ["and the fix of its owner-readability findings (items 141-150; integration log section 32)"],
          "M0-gate.md Section 7, item 5")
m += need(s8, ["and the fix of its owner-readability findings after that (items 141-150)", "- **The fix of the "
               "owner-readability findings of the update's review (26 October 2026; integration log section 32).**",
               "`evidence/M0-DeviceA/fix-1/owner/checks/gate-checks.log`, written by "
               "`evidence/M0-DeviceA/fix-1/owner/commands/gate-checks.sh`", "nor its fourth, of its owner-readability "
               "findings (section 32)"], "M0-gate.md Section 8")
m += need(who, ["and then, the same day, to answer the same review's owner-readability findings", "(integration log section "
                "32; `evidence/M0-DeviceA/fix-1/owner/`)", "nor its fourth, of its owner-readability findings; human "
                "review pending"], "the runbook's Who wrote it")
m += need(stage0, ["and a fourth fix its owner-readability findings (integration log section 32; "
                   "`evidence/M0-DeviceA/fix-1/owner/`), which has not been reviewed either"], "the Stage 0 README")
for heading in ("## 32. ", "### 32.1 ", "### 32.2 ", "### 32.3 ", "### 32.4 ", "### 32.5 ", "### 32.6 "):
    if heading not in log:
        m.append(f"the integration log lacks {heading.strip()}")
m += need(adr_status, ["and so did the fix of its owner-readability findings"], "ADR-0001's Status")
m += need(read(EV + "README.md"), ["*(26 October 2026: a fourth fix answered the same review's owner-readability findings "
                                   "the same day"], "the records' evidence README")
m += need(joined(EV + "fix-1/README.md"), ["*(26 October 2026: the same review's owner-readability findings, OWN-DA-01 to "
                                          "OWN-DA-09, were relayed to a fourth fix"], "the first fix's README")
m += need(joined(EV + "fix-1/accuracy/README.md"), ["*(26 October 2026: and its owner-readability findings, OWN-DA-01 to "
                                                   "OWN-DA-09, to a fourth fix"], "the second fix's README")
m += need(completeness, ["*(26 October 2026: the same review's owner-readability findings, OWN-DA-01 to OWN-DA-09, were "
                         "relayed to a fourth fix"], "the third fix's README")
if "Agent-written; not reviewed; human sign-off pending." not in readme:
    m.append("this fix's README is missing, or does not give it as not reviewed")
if not (ROOT / HERE / "relayed-findings.md").is_file():
    m.append("the findings as relayed are not committed")
report("review", m, "this fix, not reviewed, in the gate summary (Section 6.2, items 141-150, Section 7, Section 8), the "
       "runbook's Who wrote it, the Stage 0 README, integration log 32, ADR-0001's Status and the evidence READMEs; the "
       "findings as relayed")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 10 not as stated)")
sys.exit(1 if problems else 0)
