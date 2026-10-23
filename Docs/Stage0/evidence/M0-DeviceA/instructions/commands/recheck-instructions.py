#!/usr/bin/env python3
"""Checks the update of the product owner's instructions of 24 October 2026 (branch m0-sessions-instructions, made from
m0-sessions at 6cede84a): after pull request #6 (96bdc7e9), the making of m0-sessions and the owner's decision of that
day on device A, as relayed (Docs/Stage0/evidence/M0-DeviceA/instructions/relayed-2026-10-24.md). It reads only the
files this update owns (the device runbook, the gate summary, the Stage 0 README and the eight device checklists) and
asserts, item by item, that each says what the update says it does now, and that the texts it replaced are gone or
kept only inside a dated note that says what they were:
  device-A    device A is the iPhone 13 mini (iPhone14,4 expected; A15; 375 x 812 pt) wherever the records name it:
              the runbook's header, 1.1, 1.2, run 8, 0.4, Session 8 and its 8.1, Sections 6 and 7; the gate summary's
              opening, item 1's step 8, item 2's run 8, Section 2's rows 62, 74 and 82, Sections 3, 4.3 and 5.1; the
              Stage 0 README; each checklist's device-A line;
  floor       what the change means: the 11 Pro's 375 x 812 pt drawn about 8% smaller; the A15's figures the 13
              mini's, never the A13's; no budget changed; the A13 floor measured in M8; D-2's narrower exception;
  branch      m0-sessions, in ~/Git/sylvia-sessions, wherever the records tell the owner what to check out, build from,
              commit to or start agents from: the runbook's 0.3 (steps 1-6), Section 2, run 1, 0.2, 0.7, 0.8 and
              Section 6; the gate summary's item 1 (steps 1-6), item 4, the drop-in run, Sections 5.4 and 7; the
              checklists' setup lines of G0.4, G0.5 AI and G0.5 recovery; the Stage 0 README;
  run-1       steps 2 and 3 done, step 5 asked and in progress (pending), step 7 a one-line confirmation, with
              Apple's evidence recorded in item 1's step 7 and the runbook's 0.2;
  step-0.8    0.8 states the check of 24 October 2026: the paths read from the drop-in, the commit, the result, how to
              check again after a merge into m0-sessions, and that the drop-in uses neither file the m0-exit-prep run
              changes;
  sweep       every line of those files that names the iPhone 11 Pro, iPhone12,3 or m0-decisions and carries no mark
              of this update ("24 October 2026", "13 mini", "m0-sessions") is a record of what happened, listed below
              with its reason; an unlisted one, or a listed one no longer there, is reported.
    python3 -I Docs/Stage0/evidence/M0-DeviceA/instructions/commands/recheck-instructions.py <repository root>
Run on the tree of 6cede84a (git archive), where this update starts, it must report every item: the gate checks
beside this file run that control. Read-only; standard library only; host only. Prints one line per item and exits 1
if any is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
STAGE0 = "Docs/Stage0/README.md"
CL = "Docs/Stage0/device-checklists/"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


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


runbook, gate, stage0 = read(RUNBOOK), read(GATE), read(STAGE0)
checklists = {name: read(CL + name) for name in ("G01-EPUB.md", "G01-PDF.md", "G02-Transfer.md", "G03-Intake.md",
                                                  "G04-Audio.md", "G05-AI.md", "G05-Recovery.md", "G06-Design.md")}
row_a = line_with(runbook, "| **A. ")
session8 = block(runbook, "### Session 8 ", "### Session 9 ")
step03 = block(runbook, "**0.3 Commit**", "**0.4 Devices.**")
step08 = block(runbook, "**0.8 G0.5 recovery report row 10", "**0.9 ")
run1 = line_with(runbook, "| 1 | Before the sessions |")
section6 = block(runbook, "## 6. Session 10", "## 7. ")
item1 = block(gate, "**1. Before the first session**", "**2. The device sessions**")
item2 = line_with(gate, "**2. The device sessions**")
item4 = block(gate, "**4. Two requests the exit waits for", "**Three readings of your decisions")
section7 = block(gate, "## 7. Recommendation", "## 8. ")

# device-A: the iPhone 13 mini wherever the records name device A.
m = need(row_a, ["| **A. Device A, the small-screen baseline: your iPhone 13 mini** (model identifier iPhone14,4 expected; "
                 "A15 Bionic; 375 × 812 pt)", "Your decision of 24 October 2026 (D-1, decided again: Section 6): your "
                 "iPhone 11 Pro, device A under D-1 (b) of 22 October 2026, no longer charges and is not used",
                 "whether iOS 27 supports the iPhone 13 mini was not checked",
                 "Your iPhone 11 is not device A", "Until 24 October 2026 it named your iPhone 11 Pro"], "the runbook's 1.1")
m += gone(row_a, ["**A. The oldest supported iPhone: your iPhone 11 Pro**",
                  "is an iPhone 11 Pro: the product owner chose the iPhone 11 family on 22 October 2026"], "the runbook's 1.1")
m += need(runbook, ["- **Your decision of 24 October 2026, and the branch you build from since then.**",
                    "Lightning for device A, the iPhone 13 mini since 24 October 2026",
                    "| 8 | 8 Device A, your iPhone 13 mini (you judge the design steps 8.1-8.5) | A (Lightning cable, Mac) |",
                    "for device A, an iPhone 13 mini, iPhone14,4 is expected",
                    "## 5. Sessions on device A, the small-screen baseline, and an iPad",
                    "**8.1 Type roles on device A, the small-screen baseline**",
                    "  - **Decided again on 24 October 2026: device A is your iPhone 13 mini.**"], "the runbook")
m += need(session8, ["### Session 8 · Device A, the small-screen baseline: your iPhone 13 mini (about 6.75 h",
                     "iPhone14,4 is expected for an iPhone 13 mini"], "the runbook's Session 8")
m += gone(runbook, ["Device A, the oldest supported iPhone, is your iPhone 11 Pro (D-1 (b))",
                    "### Session 8 · Device A, the oldest supported iPhone: your iPhone 11 Pro",
                    "iPhone12,3 is expected for an iPhone 11 Pro", "**8.1 Type roles on the oldest supported iPhone**",
                    "| 8 | 8 Device A, your iPhone 11 Pro", "Lightning for device A, the iPhone 11 Pro;"], "the runbook")
m += need(item1, ["8. **Check that your iPhone 13 mini (device A) runs iOS 26**", "iPhone14,4"], "M0-gate.md item 1")
m += gone(item1, ["8. **Check that your iPhone 11 Pro (device A) runs iOS 26**"], "M0-gate.md item 1")
m += need(gate, ["| 8 | 8 · Device A | iPhone 13 mini (your iPhone 11 Pro until 24 October 2026: Section 4.3, D-1) |",
                 "you decided D-1 again: device A is your iPhone 13 mini",
                 "on device A, your iPhone 13 mini since 24 October 2026 (decision D-1, decided again;",
                 "**Decided again on 24 October 2026, the iPhone 11 Pro no longer charging:**",
                 "A the small-screen baseline, your iPhone 13 mini since 24 October 2026"], "M0-gate.md")
m += need(stage0, ["on the iPhone 17 Pro, the iPhone 13 mini (device A) and an iPad"], "the Stage 0 README")
m += gone(stage0, ["the iPhone 11 Pro (device A)"], "the Stage 0 README")
for name, phrase in (("G01-EPUB.md", "Repeat steps 1, 6, 11 and 12 on device A, the small-screen baseline"),
                     ("G01-PDF.md", "repeat steps 1 and 10 on device A, the small-screen baseline"),
                     ("G02-Transfer.md", "### 11. Memory and time on device A, the small-screen baseline (T38, plan 19.1)"),
                     ("G03-Intake.md", "device A, the small-screen baseline, is the product owner's iPhone 13 mini"),
                     ("G04-Audio.md", "Repeat steps 1, 3, 8-13 and 15 on device A, the small-screen baseline"),
                     ("G05-AI.md", "if device A, the small-screen baseline, has an earlier iOS 26.x"),
                     ("G05-Recovery.md", "Repeat steps 1-4 on device A, the small-screen baseline: the product owner's "
                                         "iPhone 13 mini (iPhone14,4 expected"),
                     ("G06-Design.md", "- **A. Device A, the small-screen baseline**")):
    m += need(checklists[name], [phrase, "iPhone 13 mini"], f"the {name[:-3]} checklist")
report("device-A", m, "device A is the iPhone 13 mini (iPhone14,4 expected; A15; 375 × 812 pt) in the runbook, the gate "
       "summary, the Stage 0 README and each checklist's device-A line, the iPhone 11 Pro kept only in dated notes")

# floor: what the change means for the steps on A.
m = need(row_a, ["draws each point about 8% smaller", "a native scale of 2.88", "screen-facts.log",
                 "two generations newer than the A13", "never as the A13's", "a pass does not show that a budget holds "
                 "on an A13 phone", "in M8, the Section 19.2 budgets are measured on an A13 iPhone, your iPhone 11 if it "
                 "still works then, or a borrowed or bought one", "Apple publishes neither phone's memory size",
                 "a Ring/Silent switch but no Action button"], "the runbook's 1.1")
m += need(section6, ["This is a new decision, not a new reading of the one of 22 October 2026",
                     "13 mini only (Recommended)", "a narrower form of option (b)'s exception, for those results only",
                     "stay unknown until M8 (D-1, above)"], "the runbook's Section 6")
m += need(runbook, ["*(24 October 2026: device A is your iPhone 13 mini: Section 1.1; Section 6, D-1. Every step this "
                    "table puts on A stays where it was"], "the runbook's Section 7")
m += need(gate, ["a narrower form of option (b)'s exception, which the records option (b) names record by their owners",
                 "M8 measures the Section 19.2 budgets on an A13 iPhone"], "M0-gate.md Section 4.3")
for name in ("G01-EPUB.md", "G01-PDF.md", "G02-Transfer.md", "G03-Intake.md", "G04-Audio.md", "G05-Recovery.md"):
    m += need(checklists[name], ["M8"], f"the {name[:-3]} checklist's chip note")
report("floor", m, "the 13 mini lays out at the 11 Pro's 375 × 812 pt drawn about 8% smaller; its figures that depend on "
       "the chip are its own, never the A13's; no budget changes; M8 measures the A13 floor; D-2 (a) stands with a "
       "narrower form of (b)'s exception")

# branch: m0-sessions wherever the records tell the owner what to check out, build from, commit to or start agents from.
m = need(step03, ["Do, in `~/Git/sylvia-sessions`, the checkout of your repository prepared for the sessions",
                  "1. `git branch --show-current` reads `m0-sessions`", "6. **Your session records, on `m0-sessions`.**",
                  "only once the other's branch is merged into `m0-sessions`", "(`git checkout m0-sessions`, then "
                  "`git merge <its branch>`, by you or by an agent you ask)", "Never merge it into `main`, or open a pull "
                  "request of it into `main`, before the M0 exit"], "the runbook's 0.3")
m += gone(step03, ["1. `git checkout m0-decisions`", "first `git checkout m0-decisions`", "6. **Your session records, on "
                   "`m0-decisions`.**", "here on `m0-decisions`"], "the runbook's 0.3")
m += need(runbook, ["have its records and evidence committed on `m0-sessions` (0.3, step 6)",
                    "Record: commit the regenerated log on `m0-sessions` (0.3, step 6;",
                    "committed on `m0-sessions` (0.3, step 6; until 24 October 2026 this said `m0-decisions`); update "
                    "row 10 to cite it", "Then commit the folder on `m0-sessions` (0.3, step 6), so that an agent can "
                    "read it"], "the runbook")
m += gone(runbook, ["commit its records and evidence on `m0-decisions` (0.3, step 6)", "every agent starts from "
                    "`m0-decisions`", "change its milestone paragraph on `m0-decisions` and commit it there"], "the runbook")
m += need(item1, ["1. **Check that `~/Git/sylvia-sessions` is on `m0-sessions`**", "6. **Your session records, "
                  "committed on `m0-sessions`.**", "only once the other's branch is merged into `m0-sessions`"],
          "M0-gate.md item 1")
m += gone(item1, ["1. **Check out `m0-decisions`**", "6. **Commit your session records on `m0-decisions`.**",
                  "If you build from `main`, check out `m0-decisions` to commit them"], "M0-gate.md item 1")
m += need(item4, ["that branch is merged into `m0-sessions`, never straight into `main` (item 1)", "otherwise build from "
                  "`m0-sessions` until the exit (item 1)", "commit the folder on `m0-sessions` (item 1, step 6;"],
          "M0-gate.md item 4")
m += gone(item4, ["merge that branch into `m0-decisions`, never straight into `main` (item 1)", "otherwise build from "
                  "`m0-decisions` until the exit (item 1)."], "M0-gate.md item 4")
m += need(section7, ["built from one recorded commit of `m0-sessions`, in `~/Git/sylvia-sessions`", "committed on "
                     "`m0-sessions` before an agent works from them"], "M0-gate.md Section 7")
for name in ("G04-Audio.md", "G05-AI.md", "G05-Recovery.md"):
    m += need(checklists[name], ["`m0-sessions`, in the checkout `~/Git/sylvia-sessions`, as runbook 0.3 says"],
              f"the {name[:-3]} checklist's setup line")
    m += gone(checklists[name], ["`m0-decisions`, or `main` only once it holds `m0-decisions` and the checkout's `main` "
                                 "is brought up to date, as runbook 0.3 says"], f"the {name[:-3]} checklist's setup line")
m += need(stage0, ["the device sessions build from one recorded commit of it, in the checkout `~/Git/sylvia-sessions`"],
          "the Stage 0 README")
report("branch", m, "the runbook, the gate summary, the checklists' setup lines and the Stage 0 README send the owner "
       "to m0-sessions in ~/Git/sylvia-sessions, with records and agent work merged into it between sittings")

# run-1: the state of run 1's steps.
m = need(item1, ["2. **Done: `CLAUDE.md` corrected.**", "3. **Done: `m0-decisions` merged into `main`** by pull request "
                 "#6 on 24 October 2026 (`96bdc7e9`)", "5. **The two requests of item 4: asked, and in progress.**",
                 "Until then each stays pending", "7. **As technical lead, confirm that Xcode 27.1 (27A9275) is the "
                 "release build: one line**", "`evidence/M0-DeviceA/instructions/checks/apple-pages.log`",
                 "what the steps said until then is in Section 6.3, item 104"], "M0-gate.md item 1")
m += gone(item1, ["7. **As technical lead, read Apple's release notes for Xcode 27.1**", "3. **Only if you want to build "
                  "from `main`: merge `m0-decisions` into it now**"], "M0-gate.md item 1")
m += need(step03, ["2. Done: `CLAUDE.md`'s milestone paragraph no longer says", "3. Done: pull request #6 merged "
                   "`m0-decisions` into `main` on 24 October 2026 (`96bdc7e9`)", "Run 1's two requests are asked and "
                   "in progress"], "the runbook's 0.3")
m += need(run1, ["Since 24 October 2026 its steps 2 and 3 are done", "its step 7 is a one-line confirmation (0.2)",
                 "(This run's history: `M0-gate.md` Section 6.3, items 74 and 88.)"], "the runbook's run 1")
m += [f"the runbook's run 1 has {len(run1.split())} words (at most 200)"] if len(run1.split()) > 200 else []
m += need(block(runbook, "**0.2 Xcode account", "**0.3 Commit**"), ["Apple's pages show that 27A9275 is Xcode 27.1's "
          "release build", "apple-pages.log", "your confirmation of that reading, as technical lead, is still to be "
          "recorded: one line (run 1, step 7)"], "the runbook's 0.2")
m += need(gate, ["104. **Run 1 and the branch you build from**", "107. **Apple's release notes for Xcode 27.1**"],
          "M0-gate.md Section 6.3")
report("run-1", m, "steps 2 and 3 done, step 5 asked and pending, step 7 a one-line confirmation with Apple's evidence in "
       "item 1 and the runbook's 0.2; run 1 within 200 words; the old texts in Section 6.3, item 104")

# step-0.8: the check of 24 October 2026.
paths = ("Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery "
         "Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1")
m = need(step08, ["**Checked on 24 October 2026:**", "None of them changed between `9cdb0a02` and `6cede84a`, the head "
                  "of `m0-sessions` that day", "dropin-paths.log", f"`git diff --stat 9cdb0a02 HEAD -- {paths}`",
                  "The drop-in uses neither `Scripts/check-dependency-lock.py` nor `Scripts/ci.d/12-dependency-lock.sh`"],
         "the runbook's 0.8")
m += need(item2, ["On 24 October 2026 none of that had changed between `9cdb0a02` and `6cede84a`"], "M0-gate.md item 2")
log = ROOT / "Docs/Stage0/evidence/M0-DeviceA/instructions/checks/dropin-paths.log"
if not log.is_file() or "no change: the run of" not in log.read_text(encoding="utf-8"):
    m.append("the log dropin-paths.log is missing or records a change")
report("step-0.8", m, "0.8 gives the paths read from the drop-in, the commit checked, the result, the command for after a "
       "merge, and that the drop-in uses neither file m0-exit-prep changes; dropin-paths.log records no change")

# sweep: lines that name the old device or branch without a mark of this update are records of what happened.
MARKS = ("24 October 2026", "13 mini", "m0-sessions")
TERMS = re.compile(r"11 Pro|iPhone12,3|m0-decisions")
HISTORY = {  # (file, the line's first words): why it stays as it is
    (RUNBOOK, "  - **Decided on 22 October 2026: (b) and (c).**"): "D-1's record of 22 October 2026, kept; the "
        "addendum after it records the decision of 24 October 2026",
    (RUNBOOK, "- **D-8** Git LFS:"): "D-8's record; its note of 22 October 2026 on what m0-decisions added to LFS",
    (RUNBOOK, "**C50 · ADR-0013's open item on devices"): "a correction's text and its note of 22 October 2026",
    (RUNBOOK, "**C56 · G03 Setup 1, ADR-0010's open item"): "a correction's text and its note of 22 October 2026",
    (GATE, "- **The decisions round assembled (22 October 2026).**"): "what happened on 22 October 2026",
    (GATE, "- **The review of the decisions round, and its fix (22 October 2026).**"): "what happened",
    (GATE, "- **The review of that fix, and the second fix (22 and 23 October 2026).**"): "what happened",
    (GATE, "- **The review of the second fix, your answers, and the follow-up (23 October 2026).**"): "what happened",
    (GATE, "| 92 | The other Stage 0 ADRs"): "ADR-0002's record of H-1 as it stands, a status row",
    (GATE, "- **G0.5 recovery with the lock harness (22 October 2026).**"): "Section 2.10's record of the runs",
    (GATE, "| The assembly of the decisions round on `m0-decisions`"): "Section 6.2's record of a review",
    (GATE, "| The review of the follow-up (23 October 2026, at `19489f10`)"): "Section 6.2's record of a review",
    (GATE, "27. **The decisions in the records.**"): "Section 6.3's record of 22 October 2026",
    (GATE, "34. **The commit to build from**"): "Section 6.3's record of a finding",
    (GATE, "41. **The commit to build from, and the devices' OS builds**"): "Section 6.3's record of a finding",
    (GATE, "46. **Not fixed: `CLAUDE.md`'s milestone paragraph**"): "Section 6.3's record of a finding",
    (GATE, "48. **Your answers of 23 October 2026**"): "Section 6.3's record of the answers",
    (GATE, "51. **`CLAUDE.md` before the run-1 requests"): "Section 6.3's record of a finding",
    (GATE, "54. **The commit to build from, agent work and repeats**"): "Section 6.3's record of a finding",
    (GATE, "58. **Agent work and `main`**"): "Section 6.3's record of a finding",
    (GATE, "66. **H-1's exception and agent work**"): "Section 6.3's record of a finding",
    (GATE, "71. **Summary lines**"): "Section 6.3's record of a finding",
    (GATE, "74. **The owner's lists, as checklists**"): "Section 6.3's record of a finding",
    (GATE, "    - **Item 1:**"): "a history note moved to Section 6.3, item 74",
    (GATE, "    - **The runbook's run 1**"): "a history note moved to Section 6.3, item 74",
    (GATE, "    - **The runbook's 0.3:**"): "a history note moved to Section 6.3, item 74",
    (GATE, "    - **The bullet on the M0 work on `main`**"): "a history note moved to Section 6.3, item 74",
    (GATE, "77. **Agent work and `main`, when you build from `main`**"): "Section 6.3's record of a finding",
    (GATE, "80. **The branch for `CLAUDE.md`**"): "Section 6.3's record of a finding",
    (GATE, "85. **Where your session records go**"): "Section 6.3's record of a finding",
    (GATE, "109. **Asked of other owners, not done here**"): "this update's own record of what it asks of other owners",
    (GATE, "- **The fix of the review of the decisions round (22 October 2026;"): "Section 8's record of a round",
    (GATE, "- **The second fix, after the review of the first"): "Section 8's record of a round",
    (GATE, "- **The follow-up: your answers of 23 October 2026"): "Section 8's record of a round",
    (GATE, "- **The follow-up's fix, after the review of the follow-up"): "Section 8's record of a round",
    (GATE, "- **The follow-up's second fix, after the honesty findings"): "Section 8's record of a round",
    (GATE, "- **The follow-up's fourth fix, after the owner-readability findings"): "Section 8's record of a round",
    (GATE, "- **The record of G0.5 recovery's whole drop-in run"): "Section 8's record of a round",
    (GATE, "- **The assembly of the decisions round (22 October 2026; integration log section 17).**"): "Section 8's record",
    (STAGE0, "[integration-log.md](integration-log.md) records how"): "the README's account of the integration log",
}
m, seen = [], set()
for path in [RUNBOOK, GATE, STAGE0] + [CL + n for n in checklists]:
    for line in read(path).splitlines():
        if not TERMS.search(line) or any(mark in line for mark in MARKS):
            continue
        keys = [k for k in HISTORY if k[0] == path and line.startswith(k[1])]
        if keys:
            seen.update(keys)
        else:
            m.append(f"{path}: unlisted, with no mark of this update: {line[:100]}")
m += [f"{path}: listed, but no such line: {start}" for path, start in sorted(set(HISTORY) - seen)]
report("sweep", m, f"every line that names the iPhone 11 Pro, iPhone12,3 or m0-decisions without a mark of this update "
       f"is a record of what happened ({len(seen)} lines listed, each with its reason)")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 6 not as stated)")
sys.exit(1 if problems else 0)
