#!/usr/bin/env python3
"""Checks the fix of the accuracy findings of the review of the update of 24 October 2026 and its assembly (26 October
2026 on the build Mac's clock; integration log section 30), which cite m0-sessions at 8082bdb6; the fix was made from
d6315ad3, the last commit of the fix of the same review's fidelity findings. One item per finding, and one for the
review status:
  branch        ACC-01: the gate summary's State line says that no device result is recorded here yet, and its Section
                5.1 that no result of a device step is recorded here yet and where the first sittings are, each with its
                history; the runbook header's paragraph on the branch says what a sitting builds from and commits to
                until the checkout moves; the first fix's texts for a checkout on another branch kept (run 1's step 1 in
                both places);
                items 124-130 recorded; the judged branch check and this fix's read of the branches committed, the read
                showing the checkout on m0-decisions, m0-decisions not behind main, and a merge without a conflict;
  phones        ACC-02: the G0.5 AI checklist's note on step 1 no longer calls device A the phone on hand besides the
                iPhone 17 Pro, with a dated note; the G0.2 checklist's note on step 22.5 says how a result on the iPhone
                11 is recorded; the four texts the first fix reworded keep their wording; and no live record gives the
                lack of an A13 phone, or device A as the only phone at hand, as a fact;
  step-12       ACC-03: the first fix's answer (FID-DA-05) in ADR-0001, ADR-0013 and the records' evidence README, which
                this fix did not change: this item passes on the tree of d6315ad3 too;
  g03-times     ACC-04: the runbook's repeats on A, the G0.3 checklist's Setup 1, ADR-0010's open item, ADR-0001's clause
                on it and the records' evidence README name G0.3's other times on A (steps 6, 9, 18, 20 and 32);
  g04-17        ACC-05: the runbook's Section 7 no longer says that the G0.4 checklist asks for step 17 on A;
  release-notes ACC-06: plan D01's row has the dated note on Apple's release notes, the Revised line and Appendix D's
                item of 24 October 2026 record it, that item and the draft 0.8 entry's review note give the review at
                8082bdb6, and the amendments' State line and dated note the same; the ADR index's row of ADR-0001 keeps
                the first fix's answer;
  review        this fix, not reviewed, where the records give the review status of the update's fixes: the gate summary
                (the State line within 200 words, Section 6.2's row and paragraph, Section 7's item 5, Section 8), the
                runbook's Who wrote it, the Stage 0 README, integration log section 30, the Status lines of ADR-0001 and
                ADR-0010, the records' evidence README and the first fix's README; the findings as relayed committed.
    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/accuracy/commands/recheck-acc.py <repository root>
Run on the tree of d6315ad3 (git archive), the commit this fix started from, it must report every item but step-12: the
gate checks beside this file run that control. Read-only; standard library only; host only. Prints one line per item and
exits 1 if any is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
STAGE0 = "Docs/Stage0/README.md"
LOG = "Docs/Stage0/integration-log.md"
INDEX = "Docs/ADRs/README.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
DOC = "Docs/Stage0/M0-plan-amendments.md"
CL = "Docs/Stage0/device-checklists/"
EV = "Docs/Stage0/evidence/M0-DeviceA/"
HERE = EV + "fix-1/accuracy/"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
ADR10 = "Docs/ADRs/0010-intake-handoff-and-wired-bundles.md"
ADR13 = "Docs/ADRs/0013-design-language.md"


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


def report(item, missing, what):
    global problems
    if missing:
        problems += 1
    print(f"{'as stated' if not missing else 'PROBLEM  '} {item}: {what}" + (f" ({'; '.join(missing)})" if missing else ""))


runbook, gate, stage0, log, index, plan, doc = (read(p) for p in (RUNBOOK, GATE, STAGE0, LOG, INDEX, PLAN, DOC))
adr01, adr10, adr13 = read(ADR01), read(ADR10), read(ADR13)
devicea = read(EV + "README.md")
state = line_with(gate, "- **State:**")
s51 = block(gate, "### 5.1 Device and human steps", "**Blocking the M0 gate**")
item11 = line_with(gate, "1. **Check that `~/Git/sylvia-sessions` is on `m0-sessions`**")
step031 = line_with(runbook, "1. `git branch --show-current` reads `m0-sessions`")
s30 = block(log, "## 30. ", "## 31. ")
branch_log = read(HERE + "checks/branch-state.log")

# branch: ACC-01.
m = need(state, ["no sign-off of a plan 23.3 role and no device result is recorded here yet"], "the State line")
m += gone(state, ["no device result is recorded yet"], "the State line")
m += need(s51, ["No result of a device step in it is recorded here yet (your first sittings, on phone B from 25 October "
                "2026 UTC, are recorded on `m0-decisions`, and reach these records when merged into `m0-sessions`: "
                "Section 1, item 1, step 1)", "and until 26 October 2026 it said that nothing in the runbook had been run "
                "on a device: item 124)"], "M0-gate.md Section 5.1")
m += gone(s51, ["Nothing in it has been run on a device;"], "M0-gate.md Section 5.1")
for where, text in (("M0-gate.md item 1, step 1", item11), ("the runbook's 0.3, step 1", step031)):
    m += need(text, ["If it reads another branch, do not switch it yourself"], where)
m += need(line_with(runbook, "- **Your decision of 24 October 2026, and the branch you build from since then.**"),
          ["they are merged into `m0-sessions` before your checkout moves to it, and until it moves each sitting builds "
           "from the branch the checkout is on and commits its records there", "its finding ACC-01)"],
          "the runbook's paragraph on the branch")
m += need(gate, ["124. **The branch state, as your instructions give it, and a check that judges it** (ACC-01, blocker)",
                 "Not done here, again: the merge of `m0-decisions` into `m0-sessions` that ACC-01 asks for first, as "
                 "item 115 says"], "M0-gate.md Section 6.3")
if not (ROOT / HERE / "commands/branch-texts.py").is_file():
    m.append("the judged branch check is not committed")
if ("branch refs/heads/m0-decisions" not in branch_log or "m0-decisions behind main (an ancestor of it): no" not in
        branch_log or "merge-tree exit: 0" not in branch_log or "exit: 0" not in branch_log):
    m.append("this fix's branch-state.log is missing, or does not show the checkout on m0-decisions, m0-decisions not "
             "behind main and a merge without a conflict")
report("branch", m, "the State line and Section 5.1 say where no device result is recorded; the runbook header says what a sitting builds from until the checkout moves; run 1's case for a checkout "
       "on another branch kept; items 124-130; the judged branch check and this fix's read of the branches committed")

# phones: ACC-02.
g05ai = read(CL + "G05-AI.md")
g02 = read(CL + "G02-Transfer.md")
m = need(g05ai, ["*(24 October 2026: the other phone item 1 runs this step on, besides the iPhone 17 Pro, is device A, "
                 "now the product owner's iPhone 13 mini", "*(26 October 2026: until then the note above called device A "
                 "the phone on hand besides the iPhone 17 Pro, which no record establishes"], "the G0.5 AI checklist")
m += gone(g05ai, ["*(24 October 2026: the phone on hand besides the iPhone 17 Pro is device A"], "the G0.5 AI checklist")
m += need(g02, ["whether the owner's iPhone 11, an A13 phone, still works was not asked, and a result ever taken on it is "
                "recorded under its own model, never as device A's", "and until the fix of the same review's accuracy "
                "findings, that day, it did not say how a result on the iPhone 11 is recorded: its finding ACC-02.)*"],
          "the G0.2 checklist's step 22.5")
m += need(runbook, ["which no device measures in M0: on 24 October 2026 you left the A13 floor for M8"], "the runbook's 2.12")
m += need(read(CL + "G01-EPUB.md"), ["which no device measures in M0: the product owner left the A13 floor for M8"],
          "the G0.1 EPUB checklist")
m += need(read(CL + "G06-Design.md"), ["whose A13 no device measures in M0"], "the G0.6 checklist")
# The sweep: no live record gives the lack of an A13 phone, or device A as the only phone at hand, as a fact; an
# occurrence after a record of what a text said ("said that ...", "gave as a fact", "called ...") is that record.
LACK = re.compile(r"A13 phone is at hand|no device (?:of|in) M0 has|whose A13 no device in M0|no A13 phone is available"
                  r"|(?:phone|device) on hand besides|the only phone at hand|only phone on hand")
RECORD = re.compile(r"said that|saying that|gave as a fact|\bcalled\b|said\b|\bgave\b")
live = ([RUNBOOK, GATE, STAGE0, LOG, INDEX, PLAN, DOC, "README.md"]
        + sorted(str(q.relative_to(ROOT)) for q in (ROOT / "Docs/ADRs").glob("*.md"))
        + sorted(str(q.relative_to(ROOT)) for q in (ROOT / "Docs/Stage0").glob("G0*.md"))
        + sorted(str(q.relative_to(ROOT)) for q in (ROOT / CL).glob("*.md")))
seen = 0
for path in dict.fromkeys(live):
    text = read(path)
    for hit in LACK.finditer(text):
        seen += 1
        before = text[max(0, hit.start() - 100):hit.start()]
        if not RECORD.search(before):
            m.append(f"{path}: gives it as a fact: ...{text[max(0, hit.start() - 50):hit.end()]}")
report("phones", m, f"the G0.5 AI note no longer calls device A the phone on hand besides phone B; step 22.5 says how a "
       f"result on the iPhone 11 is recorded; the first fix's four texts kept; no live record gives the lack of an A13 "
       f"phone, or device A as the only phone at hand, as a fact ({seen} occurrences, each the record of what a text "
       "said)")

# step-12: ACC-03, the first fix's answer (FID-DA-05), unchanged here.
m = need(adr01, ["ADR-0013 (it does not apply to G0.6's steps on device A in M0, which depend on the screen; it applies "
                 "to G0.6 step 12's repeat on device A in M3"], "ADR-0001")
m += need(adr13, ["*(26 October 2026: of the M3 steps on device A, step 12 records, for the accessibility reviewer, "
                  "section 10's stated limit (b)", "so the narrower exception ADR-0001 records applies to it"],
          "ADR-0013's open item on devices")
m += need(devicea, ["*(26 October 2026: for ADR-0013, it does not apply to G0.6's steps on A in M0"],
          "the records' evidence README")
report("step-12", m, "the first fix's answer to FID-DA-05, which is ACC-03's: ADR-0001 limits the exception's absence to "
       "the M0 steps on A and applies it to step 12's repeat in M3; ADR-0013 and the README say so")

# g03-times: ACC-04.
repeats = line_with(runbook, "The repeats on A. None blocks M0:")
m = need(repeats, ["G0.3's share-extension memory, memory limit and times (steps 14-16) and the other times G0.3's "
                   "repeats record (steps 6, 9, 18, 20 and 32", "and G0.3's other times, steps 6, 9, 18, 20 and 32, after "
                   "the review of that update, its finding ACC-04"], "the runbook's repeats on A")
m += need(read(CL + "G03-Intake.md"), ["and the other times these steps record on it (step 6's time from the extension's "
                                       "receipt to the harness's scan line, step 9's and step 18's provider and cancel "
                                       "times, step 20's elapsed time to copy in and import the large pack, and step "
                                       "32's download time), are its own", "its finding ACC-04"],
          "the G0.3 checklist's Setup 1")
m += need(adr10, ["and so are the times the checklist records there (steps 6, 9, 14, 18, 20 and 32",
                  "*(26 October 2026: until then this item named the memory figures alone: the review of the update of "
                  "24 October 2026, its finding ACC-04.)*"], "ADR-0010's open item")
m += need(adr01, ["ADR-0010 (the share extension's memory limit and peak in G0.3's repeats, in M2, and the times those "
                  "repeats record on device A; until 26 October 2026 this clause named the memory figures alone"],
          "ADR-0001's clause on ADR-0010")
m += need(devicea, ["*(26 October 2026: G0.3's repeats on A, steps 6-32 in M2, record times in steps 6, 9, 18, 20 and 32 "
                    "too"], "the records' evidence README")
report("g03-times", m, "the runbook's repeats, the G0.3 checklist's Setup 1, ADR-0010's open item, ADR-0001's clause on it "
       "and the records' evidence README name G0.3's times in steps 6, 9, 18, 20 and 32 on A")

# g04-17: ACC-05.
row = line_with(runbook, "| G0.4 | 1-17 (2 is the harness setup); 8-10, 12, 13 on A |")
m = need(row, ["(the checklist asked for 1, 3 and 15 \"when one is available\", and since 24 October 2026 asks for them on "
               "device A; it has never asked for 17 on A", "so 17 on A is this runbook's own repeat, which the checklist "
               "does not ask for", "its finding ACC-05)", "| 1, 3, 15 and 17 on A | M4 |"], "the runbook's Section 7")
m += gone(row, ["(the checklist asked for them \"when one is available\", and since 24 October 2026 asks for them on "
                "device A)"], "the runbook's Section 7")
m += need(read(CL + "G04-Audio.md"), ["Repeat steps 1, 3, 8-13 and 15 on device A"], "the G0.4 checklist")
report("g04-17", m, "Section 7's reason for G0.4 on A says that the checklist asks for 1, 3 and 15 there, never for 17, the "
       "runbook's own repeat; the checklist's device line as it was")

# release-notes: ACC-06.
d01 = line_with(plan, "| D01 - Platform floor |")
item24 = line_with(plan, "- *Recorded on 24 October 2026, within draft 0.8:")
m = need(d01, ["Pending: the technical lead's sign-off, with the check of Apple's release notes for Xcode 27.1 (ADR-0001; "
               "24 October 2026: Apple's pages were read that day, and they list Xcode 27.1 (27A9275) as released, with "
               "no beta or release-candidate label, so what remains of that check is the technical lead's confirmation "
               "of them, one line"], "plan D01's row")
m += need(line_with(plan, "**Prepared:**"), ["The same day, after an agent review of that record, a dated note on Apple's "
                                             "release notes for Xcode 27.1 added to D01's row"], "the plan's Revised line")
m += need(item24, ["An agent review read the record the same day, at `8082bdb6`, and found more to fix", "(its finding "
                   "ACC-06; `Docs/Stage0/integration-log.md` section 30)", "Agent-written; read by that review, which did "
                   "not accept it, and not reviewed since.*"], "plan Appendix D's item of 24 October 2026")
m += gone(item24, ["Agent-written; not reviewed.*"], "plan Appendix D's item of 24 October 2026")
m += need(plan, ["which an agent review read on 26 October 2026, at `8082bdb6`, and no review has accepted"],
          "the plan's draft 0.8 entry")
m += need(line_with(doc, "- **State:**"), ["an agent review read it with the rest of that update on 26 October 2026, at "
                                           "`8082bdb6`"], "the amendments' State line")
m += need(doc, ["*(Dated note, 26 October 2026: an agent review read that record with the rest of the update that day"],
          "the amendments")
m += need(line_with(index, "| [0001](0001-platform-baseline-and-toolchain.md) |"),
          ["awaits the technical lead's confirmation of Apple's pages, read on 24 October 2026"],
          "the ADR index's row of ADR-0001")
if not (ROOT / HERE / "commands/check-amendments.py").is_file() or not (ROOT / HERE / "commands/mutation-checks.py").is_file():
    m.append("this fix's version of the amendments checker, or its mutations, is not committed")
report("release-notes", m, "plan D01's row has the dated note on Apple's release notes, recorded in the Revised line and "
       "Appendix D; the plan's and the amendments' record of 24 October 2026 give the review at 8082bdb6; the ADR index "
       "keeps the first fix's answer")

# review: this fix, not reviewed.
words = len(state.split())
m = need(state, ["nor have the update's fixes (Section 6.2)", "(This line's history: Section 6.2, and Section 6.3, item "
                 "88.)"], "the State line")
m += [f"the State line has {words} words (at most 200)"] if words > 200 else []
m += need(gate, ["Then 6 more, as relayed to a second fix: accuracy ACC-01 to ACC-06", "The same review's six accuracy "
                 "findings, one of them a blocker and one major, a second fix answers (items 124-130)",
                 "130. **Not reviewed**: this fix is agent-written", "and the fix of its accuracy findings (items 124-130; "
                 "integration log section 30)", "- **The fix of the accuracy findings of the update's review (26 October "
                 "2026; integration log section 30).**", "`evidence/M0-DeviceA/fix-1/accuracy/checks/gate-checks.log`, "
                 "written by `evidence/M0-DeviceA/fix-1/accuracy/commands/gate-checks.sh`", "nor the second fix of that "
                 "review, of its accuracy findings (section 30)"], "M0-gate.md")
for n in range(124, 131):
    if not re.search(rf"^{n}\. \*\*", gate, re.M):
        m.append(f"M0-gate.md Section 6.3 lacks item {n}")
m += need(line_with(runbook, "- **Who wrote it.**"), ["and then, the same day, to answer the same review's accuracy "
                                                      "findings", "nor its second fix, of that review's accuracy findings"],
          "the runbook's Who wrote it")
m += need(stage0, ["and a second fix its accuracy findings (integration log section 30; "
                   "`evidence/M0-DeviceA/fix-1/accuracy/`), which has not been reviewed either"], "the Stage 0 README")
for heading in ("## 30. ", "### 30.1 ", "### 30.2 ", "### 30.3 ", "### 30.4 ", "### 30.5 ", "### 30.6 "):
    if heading not in log:
        m.append(f"the integration log lacks {heading.strip()}")
m += need(line_with(adr01, "- **Status:**"), ["so did the fix of its accuracy findings"], "ADR-0001's Status")
m += need(line_with(adr10, "- **Status:**"), ["that review's accuracy findings name its open item on the device runs on "
                                              "device A"], "ADR-0010's Status")
m += need(devicea, ["*(26 October 2026: a second fix answered the same review's accuracy findings the same day"],
          "the records' evidence README")
m += need(read(EV + "fix-1/README.md"), ["*(26 October 2026: the same review's accuracy findings, ACC-01 to ACC-06, were "
                                         "relayed to a second fix"], "the first fix's README")
if not (ROOT / HERE / "relayed-findings.md").is_file():
    m.append("the findings as relayed are not committed")
report("review", m, f"this fix, not reviewed, in the gate summary (the State line: {words} words), the runbook, the Stage 0 "
       "README, integration log 30, ADR-0001's and ADR-0010's Status, and the evidence READMEs")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 7 not as stated)")
sys.exit(1 if problems else 0)
