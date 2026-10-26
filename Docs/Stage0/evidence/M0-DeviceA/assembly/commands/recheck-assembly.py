#!/usr/bin/env python3
"""Checks the assembly of the update of 24 October 2026 (26 October 2026 on the build Mac's clock), which merged its two
parts into m0-sessions: the owner's instructions (m0-sessions-instructions at 1c69da4c) and the records of the device-A
change (m0-sessions-records at 9a4c9810), each made from m0-sessions at 6cede84a. The successor, for the merged tree, of
Docs/Stage0/evidence/M0-DeviceA/instructions/commands/recheck-instructions.py: its six items, two of them changed for
what the assembly changed (the floor item asserts M8's new wording; the step-0.8 item the assembly's check of the
drop-in's paths), and three more for what the assembly is for:
  device-A    as before: device A is the iPhone 13 mini (iPhone14,4 expected; A15; 375 x 812 pt) wherever the owner's
              instructions name it, the iPhone 11 Pro kept only in dated notes;
  floor       as before, with M8's A13 phone worded as the owner's choice had it ("or one borrowed or bought if you want
              one", the records part's request), the earlier wording gone;
  branch      as before: m0-sessions, in ~/Git/sylvia-sessions;
  run-1       as before: steps 2 and 3 done, step 5 asked and pending, step 7 a one-line confirmation;
  step-0.8    as before, and the assembly's check of the drop-in's paths on the merged tree, with its log recording no
              change;
  sweep       as before: every line of the owner's instructions that names the iPhone 11 Pro, iPhone12,3 or m0-decisions
              without a mark of the update is a record of what happened, listed with its reason;
  agree       the two parts say the same: M8's wording in the runbook, the gate summary, the plan, ADR-0001 and the
              records' evidence README, the old wording gone from every live record; the owner's words and chosen option
              quoted alike; the repeats on device A that give the 13 mini's figures listed alike in the runbook and the
              records' evidence README, with G0.4 step 15's resume time in the G0.4 checklist; the side of 8.9's start-up
              race in the runbook's D-2 note as in ADR-0007; the records the narrower exception goes in named alike in
              the runbook's D-2 note and ADR-0001; the 13 mini's facts (iPhone14,4, the native scale of 2.88, about 8%
              smaller, the Lightning connector, no memory figure) where each part states them;
  state       the branch state the same everywhere it appears: the repository README (changed as the instructions part
              asked), ADR-0002, the ADR index, the Stage 0 README, the gate summary, the runbook and the integration log,
              with the assembly named where the update is described;
              The gate summary's item 115 records what the assembly saw of the sessions' checkout, on m0-decisions;
  log         the integration log's section 28 describes both parts and the assembly: 28.3 the instructions part (its
              branch, attempts, commits, changes and checks), 28.4 the merge commits, and 28.8 the assembly, with what it
              saw of the sessions' checkout (28.8.6) and a note on 28.1's row that gave that checkout on main.
    python3 -I Docs/Stage0/evidence/M0-DeviceA/assembly/commands/recheck-assembly.py <repository root>
Run on the tree of 6cede84a it must report every item; on the tree of 5e455f70, the second merge, before the assembly's
own changes, exactly floor, step-0.8, agree, state and log. The assembly's gate checks run both controls. Read-only;
standard library only; host only. Prints one line per item and exits 1 if any is not as stated.
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
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
ADR02 = "Docs/ADRs/0002-repository-build-and-ci.md"
ADR07 = "Docs/ADRs/0007-quick-capture-evaluation.md"
INDEX = "Docs/ADRs/README.md"
LOG = "Docs/Stage0/integration-log.md"
DEVICEA = "Docs/Stage0/evidence/M0-DeviceA/README.md"
README = "README.md"


def read(path):
    p = ROOT / path
    return p.read_text(encoding="utf-8") if p.is_file() else ""


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


def gone_unquoted(text, phrases, where):
    """As gone(), but an occurrence that opens a quotation (the record of what a text said) does not count."""
    out = []
    for p in phrases:
        starts = [m.start() for m in re.finditer(re.escape(p), text)]
        if any(i == 0 or text[i - 1] != '"' for i in starts):
            out.append(f"{where} still says: {p}")
    return out


def report(item, missing, what):
    global problems
    if missing:
        problems += 1
    print(f"{'as stated' if not missing else 'PROBLEM  '} {item}: {what}" + (f" ({'; '.join(missing)})" if missing else ""))


runbook, gate, stage0 = read(RUNBOOK), read(GATE), read(STAGE0)
plan, adr01, adr02, adr07, index, log, devicea, readme = (read(p) for p in (PLAN, ADR01, ADR02, ADR07, INDEX, LOG,
                                                                             DEVICEA, README))
checklists = {name: read(CL + name) for name in ("G01-EPUB.md", "G01-PDF.md", "G02-Transfer.md", "G03-Intake.md",
                                                  "G04-Audio.md", "G05-AI.md", "G05-Recovery.md", "G06-Design.md")}
row_a = line_with(runbook, "| **A. ")
session8 = block(runbook, "### Session 8 ", "### Session 9 ")
step03 = block(runbook, "**0.3 Commit**", "**0.4 Devices.**")
step08 = block(runbook, "**0.8 G0.5 recovery report row 10", "**0.9 ")
run1 = line_with(runbook, "| 1 | Before the sessions |")
section6 = block(runbook, "## 6. Session 10", "## 7. ")
d1_again = line_with(runbook, "  - **Decided again on 24 October 2026: device A is your iPhone 13 mini.**")
d2 = line_with(runbook, "- **D-2** If device A cannot be had before the M0 exit")
item1 = block(gate, "**1. Before the first session**", "**2. The device sessions**")
item2 = line_with(gate, "**2. The device sessions**")
item4 = block(gate, "**4. Two requests the exit waits for", "**Three readings of your decisions")
section7 = block(gate, "## 7. Recommendation", "## 8. ")
gate_d1 = line_with(gate, "| D-1 | (i) Which phone is device A")
item105 = line_with(gate, "105. **Device A, your iPhone 13 mini**")
plan_191 = line_with(plan, "Use at least one older supported physical iPhone")
plan_m8 = line_with(plan, "| M8 - Release hardening and pilot |")
plan_item = line_with(plan, "- *Recorded on 24 October 2026, within draft 0.8: the product owner's decision of that day on "
                            "device A")
repeats = line_with(runbook, "The repeats on A. None blocks M0")
section28 = block(log, "## 28. ", "## 29. ")

# device-A: as the instructions part's recheck has it.
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
d1_record = line_with(runbook, "  - **Decided on 22 October 2026: (b) and (c).**")
m += need(d1_record, ["Device A is your iPhone 11 Pro (A13, 375 × 812 pt, the narrower of your two A13 phones)",
                      "*(24 October 2026: your iPhone 11 Pro no longer charges, and you decided D-1 again: device A is "
                      "your iPhone 13 mini", "This bullet keeps your decision of 22 October 2026 as it was"],
          "the runbook's D-1 record of 22 October 2026, kept with its dated note")
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

# floor: what the change means for the steps on A, with M8's A13 phone worded as the owner's choice had it.
OLD_M8 = "or a borrowed or bought one"
m = need(row_a, ["draws each point about 8% smaller", "a native scale of 2.88", "screen-facts.log",
                 "two generations newer than the A13", "never as the A13's", "a pass does not show that a budget holds "
                 "on an A13 phone", "in M8, the Section 19.2 budgets are measured on an A13 iPhone, your iPhone 11 if it "
                 "still works then, or one borrowed or bought if you want one", "Apple publishes neither phone's memory "
                 "size", "a Ring/Silent switch but no Action button"], "the runbook's 1.1")
m += need(section6, ["This is a new decision, not a new reading of the one of 22 October 2026",
                     "13 mini only (Recommended)", "a narrower form of option (b)'s exception, for those results only",
                     "stay unknown until M8 (D-1, above)"], "the runbook's Section 6")
m += need(runbook, ["*(24 October 2026: device A is your iPhone 13 mini: Section 1.1; Section 6, D-1. Every step this "
                    "table puts on A stays where it was"], "the runbook's Section 7")
m += need(gate, ["a narrower form of option (b)'s exception, which the records option (b) names record by their owners",
                 "M8 measures the Section 19.2 budgets on an A13 iPhone"], "M0-gate.md Section 4.3")
m += gone(runbook, [OLD_M8], "the runbook") + gone(gate, [OLD_M8], "M0-gate.md")
for name in ("G01-EPUB.md", "G01-PDF.md", "G02-Transfer.md", "G03-Intake.md", "G04-Audio.md", "G05-Recovery.md"):
    m += need(checklists[name], ["M8"], f"the {name[:-3]} checklist's chip note")
report("floor", m, "the 13 mini lays out at the 11 Pro's 375 × 812 pt drawn about 8% smaller; its figures that depend on "
       "the chip are its own, never the A13's; no budget changes; M8 measures the A13 floor on an A13 iPhone, the owner's "
       "iPhone 11 or one borrowed or bought if the owner wants one; D-2 (a) stands with a narrower form of (b)'s exception")

# branch: as the instructions part's recheck has it.
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

# run-1: as the instructions part's recheck has it.
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

# step-0.8: the check of 24 October 2026, and the assembly's on the merged tree.
paths = ("Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery "
         "Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1")
m = need(step08, ["**Checked on 24 October 2026:**", "None of them changed between `9cdb0a02` and `6cede84a`, the head "
                  "of `m0-sessions` that day", "dropin-paths.log", f"`git diff --stat 9cdb0a02 HEAD -- {paths}`",
                  "The drop-in uses neither `Scripts/check-dependency-lock.py` nor `Scripts/ci.d/12-dependency-lock.sh`",
                  "*(26 October 2026: the assembly that merged the update of 24 October 2026 into `m0-sessions` ran that "
                  "check again on the merged tree: none of those paths changed since `9cdb0a02`",
                  "(evidence/M0-DeviceA/assembly/checks/dropin-paths.log)"], "the runbook's 0.8")
m += need(item2, ["On 24 October 2026 none of that had changed between `9cdb0a02` and `6cede84a`"], "M0-gate.md item 2")
for folder in ("instructions", "assembly"):
    path = ROOT / f"Docs/Stage0/evidence/M0-DeviceA/{folder}/checks/dropin-paths.log"
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    if "no change: the run of" not in text or "CHANGED" in text or "NAMED:" in text:
        m.append(f"the {folder} part's dropin-paths.log is missing or records a change")
report("step-0.8", m, "0.8 gives the paths read from the drop-in, the commit checked, the result, the command for after a "
       "merge, that the drop-in uses neither file m0-exit-prep changes, and the assembly's check on the merged tree; both "
       "dropin-paths.log record no change")

# sweep: lines of the owner's instructions that name the old device or branch without a mark of the update.
MARKS = ("24 October 2026", "13 mini", "m0-sessions")
TERMS = re.compile(r"11 Pro|iPhone12,3|m0-decisions")
HISTORY = {  # (file, the line's first words): why it stays as it is
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
    (GATE, "108. **The checks**"): "the update's own record of the earlier checks that report the texts it replaced",
    (GATE, "109. **Asked of other owners, not done here**"): "the update's own record of what it asked of other owners",
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
            m.append(f"{path}: unlisted, with no mark of the update: {line[:100]}")
m += [f"{path}: listed, but no such line: {start}" for path, start in sorted(set(HISTORY) - seen)]
report("sweep", m, f"every line that names the iPhone 11 Pro, iPhone12,3 or m0-decisions without a mark of the update "
       f"is a record of what happened ({len(seen)} lines listed, each with its reason)")

# agree: the two parts say the same of device A, the narrower exception, the A13 floor in M8 and the 13 mini's facts.
OWNER = ("iphone 11 pro seems to be no longer charging. i do have a 13 mini that is still working, so update the plan. "
         "even better from a screen size.")
OPTION = "with a borrowed or bought A13 phone if wanted"
m = need(d1_again, ["or one borrowed or bought if you want one", OWNER, "13 mini only (Recommended)"],
         "the runbook's D-1 of 24 October 2026")
m += need(gate_d1, ["or one borrowed or bought if you want one", "13 mini only (Recommended)"], "M0-gate.md's D-1 row")
m += need(item105, ["or one borrowed or bought if you want one"], "M0-gate.md item 105")
m += need(plan_191, ["or one borrowed or bought if the owner wants one"], "plan 19.1")
m += need(plan_m8, ["or one borrowed or bought if the owner wants one"], "plan 21.2's M8 row")
m += need(plan_item, ["or one borrowed or bought if the owner wants one", OPTION], "plan Appendix D's item of 24 October "
                                                                                  "2026")
m += need(adr01, ["or one borrowed or bought if the owner wants one", OWNER, "13 mini only (Recommended)", OPTION],
          "ADR-0001")
m += need(devicea, ["or one borrowed or bought if the owner wants one", OWNER, OPTION], "the records' evidence README")
m += need(section28, [OWNER, OPTION], "integration log section 28")
for where, text in (("the plan", plan), ("ADR-0001", adr01), ("the integration log", log),
                    ("the records' evidence README", devicea), ("the Stage 0 README", stage0)):
    m += gone_unquoted(text, [OLD_M8], where)
# The repeats on device A that give the 13 mini's figures, listed alike.
m += need(repeats, ["The timed ones (G0.4 1, G0.1 EPUB 11 and 12, G0.1 PDF 10 and G0.2 22)", "steps 14-16",
                    "the battery figures of G0.4 3", "the time G0.4 15 records for the other app's audio to resume",
                    "in G0.6 step 12, whether a stall of the phone of more than 150 ms makes a press toggle twice"],
          "the runbook's repeats on A")
m += need(devicea, ["(G0.1 EPUB 11 and 12, G0.1 PDF 10, G0.2 22, G0.3's repeats (steps 14-16), G0.4 1, 3 and 15, and, in "
                    "M3, G0.6 step 12, whose stated limit is a stall of the phone of more than 150 ms)"],
          "the records' evidence README")
m += gone(devicea, ["(G0.1 EPUB 11 and PDF 10, G0.2 22, G0.3's repeats, G0.4 1, 3 and 15, and G0.6 step 12's stall in M3)"],
          "the records' evidence README")
m += need(checklists["G04-Audio.md"], ["the time step 15 records for the other app's audio to resume on it are the 13 "
                                       "mini's (A15)"], "the G0.4 checklist")
m += need(checklists["G06-Design.md"], ["if the device stalls for more than 150 ms between a touch lift and the Button's "
                                        "action"], "the G0.6 checklist's step 12 (the stated limit the lists name)")
# The side of 8.9's start-up race, as ADR-0007 records it.
m += need(d2, ["but for which side of the start-up race of G0.4 step 12.2 the intent arrives on in 8.9, which may depend "
               "on the phone's speed and is allowed either way (ADR-0007)"], "the runbook's D-2 note")
m += need(adr07, ["changes nothing here but one observation", "which side of the start-up race the capture line falls on"],
          "ADR-0007")
m += need(line_with(runbook, "**8.9 Quick capture on A**"), ["only which side of the start-up race of step 12.2 the intent "
                                                             "arrives on may depend on the phone's speed"], "the runbook's 8.9")
# The records the narrower exception goes in, named alike.
for rec in ("ADR-0001 and ADR-0013", "ADR-0003, ADR-0005, ADR-0007, ADR-0009 and ADR-0010", "T38"):
    m += need(d2, [rec], "the runbook's D-2 note")
m += need(adr01, ["*D-2 and the narrower exception.* D-2 (a) stands", "ADR-0013 (it does not apply to G0.6's steps on "
                  "device A, which depend on the screen)", "and the G0.2 report's row T38"], "ADR-0001")
# The 13 mini's facts where each part states them.
m += need(row_a, ["iPhone14,4 expected", "a native scale of 2.88", "about 8% smaller", "Lightning connector",
                  "Apple publishes neither phone's memory size"], "the runbook's 1.1")
m += need(plan_191, ["a native scale of 2.88", "about 8% smaller"], "plan 19.1")
m += need(adr01, ["iPhone14,4 expected", "a native scale of 2.88", "about 8% smaller", "a Lightning connector",
                  "Apple publishes neither phone's memory"], "ADR-0001")
m += need(devicea, ["iPhone14,4", "a native scale of 2.88 (1080 / 375)", "about 7.6% smaller", "\"Lightning connector\"",
                    "Apple does not publish either phone's memory"], "the records' evidence README")
for where, text in (("the runbook", runbook), ("M0-gate.md", gate), ("the plan", plan), ("ADR-0001", adr01),
                    ("the records' evidence README", devicea)):
    if re.search(r"\b\d+ ?GB of (RAM|memory)\b|\b\d+ ?GB RAM\b", text):
        m.append(f"{where} gives a phone's memory size")
report("agree", m, "the two parts say the same: M8's A13 phone as the owner's choice had it, the old wording gone; the "
       "owner's words and option quoted alike; the repeats on A that give the 13 mini's figures listed alike; the side of "
       "8.9's start-up race as ADR-0007 has it; the narrower exception's records named alike; the 13 mini's facts alike, "
       "with no memory size")

# state: the branch state the same everywhere it appears, with the assembly named where the update is described.
m = need(readme, ["were made on the branch `m0-decisions`, which pull request #6 merged into main on 24 October 2026 "
                  "(`96bdc7e9`); since then the M0 work and the device sessions use the branch `m0-sessions`, made from "
                  "main that day, and nothing else reaches main before the M0 exit unless the product owner decides "
                  "otherwise", "the rule stays, and neither merge approves anything",
                  "M0 decisions of 22 October 2026 and of the owner's answers of 23 October 2026"], "README.md")
m += gone(readme, ["are on the branch `m0-decisions`, which reaches main by pull request"], "README.md")
m += need(adr02, ["- *Since 24 October 2026: `m0-sessions`.* Pull request #6 merged `m0-decisions` into `main`",
                  "Nothing reaches `main` before the M0 exit unless the product owner decides otherwise"], "ADR-0002")
m += need(index, ["since 24 October 2026 the M0 work, the session records and the agent work merged between sessions are "
                  "on `m0-sessions`"], "the ADR index")
m += need(stage0, ["and on 26 October 2026 an assembly merged both into `m0-sessions` (integration log section 28; "
                   "`evidence/M0-DeviceA/assembly/`)", "an update merged into `m0-sessions` on 26 October 2026, section 28"],
          "the Stage 0 README")
m += need(gate, ["Recorded on 26 October 2026 (the build Mac's date), when an assembly merged the two parts of that update "
                 "into `m0-sessions`", "111. **The two parts merged.**", "112. **What each part asked of the other.**",
                 "113. **The two parts made to agree.**", "114. **Not reviewed**: the assembly is agent-written",
                 "115. **Seen at the assembly, and not in these records**: when the assembly read the branches "
                 "(`evidence/M0-DeviceA/assembly/checks/branch-state.log`, whose header gives the time), `git worktree "
                 "list` showed `~/Git/sylvia-sessions` on `m0-decisions`, not on `main` at `96bdc7e9`",
                 "which an assembly merged into `m0-sessions` on 26 October 2026 with the same update's records of the "
                 "device-A change, `m0-sessions-records`", "(items 111-115; integration log section 28)",
                 "`evidence/M0-DeviceA/assembly/checks/gate-checks.log`, written by "
                 "`evidence/M0-DeviceA/assembly/commands/gate-checks.sh`"], "M0-gate.md")
m += need(line_with(runbook, "- **Who wrote it.**"), ["which an assembly merged into `m0-sessions` on 26 October 2026",
                                                      "nor has the update of 24 October 2026, nor its assembly"],
          "the runbook's Who wrote it")
m += need(section28, ["On 26 October 2026 an assembly merged both into `m0-sessions`, before any review",
                      "the orchestrating session switches `~/Git/sylvia-sessions` to `m0-sessions` once the update is "
                      "reviewed"], "integration log section 28")
m += need(devicea, ["merged into `m0-sessions` on 26 October 2026 by an assembly"], "the records' evidence README")
report("state", m, "the branch state the same in the repository README, ADR-0002, the ADR index, the Stage 0 README, the "
       "gate summary, the runbook and the integration log, with the assembly named where the update is described")

# log: section 28 describes both parts and the assembly.
m = need(block(log, "### 28.3 ", "### 28.4 "), ["It was made on `m0-sessions-instructions`, from `6cede84a`, in two "
                                                "attempts.", "`6a72ce8c`", "`e7f3b066`", "`fbf8aae3`", "`1c69da4c`",
                                                "- **The runbook**:", "- **The gate summary**:",
                                                "- **The eight checklists**:", "- **The Stage 0 README**:",
                                                "`screen-facts.log`", "`apple-pages.log`", "`dropin-paths.log`",
                                                "`recheck-instructions.log`", "`gate-checks.log`",
                                                "`evidence/M0-DeviceA/instructions/`"], "integration log 28.3")
m += need(block(log, "### 28.4 ", "### 28.5 "), ["`25186d65`, the merge of `m0-sessions-instructions` at `1c69da4c`",
                                                "`5e455f70`, the merge of `m0-sessions-records` at `9a4c9810`"],
          "integration log 28.4")
s288 = block(log, "### 28.8 ", "## 29. ")
m += need(s288, ["### 28.8 The assembly (26 October 2026)", "`evidence/M0-DeviceA/assembly/`",
                 "`commands/gate-checks.sh`", "`commands/recheck-assembly.py`", "`commands/expected-rechecks.txt`",
                 "`git worktree list` showed `~/Git/sylvia-sessions` on `m0-decisions`, not on `main` at `96bdc7e9`",
                 "it read, recorded and inferred none of their results, and changed no record for them"],
          "integration log 28.8")
for heading in ("#### 28.8.1 ", "#### 28.8.2 ", "#### 28.8.3 ", "#### 28.8.4 ", "#### 28.8.5 ", "#### 28.8.6 ",
                "#### 28.8.7 "):
    if heading not in s288:
        m.append(f"integration log 28.8 lacks its subsection {heading.strip()}")
m += need(block(log, "### 28.1 ", "### 28.2 "), ["*(Later on 26 October 2026, at the assembly, `git worktree list` showed "
                                                "`~/Git/sylvia-sessions` on `m0-decisions`"], "integration log 28.1")
report("log", m, "the integration log's section 28 describes both parts (28.3 the instructions part, as its record has "
       "it) and the assembly (28.4's merge commits, 28.8, with what it saw of the sessions' checkout, and 28.1's note)")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 9 not as stated)")
sys.exit(1 if problems else 0)
