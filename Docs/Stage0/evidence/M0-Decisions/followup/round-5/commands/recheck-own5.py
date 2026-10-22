#!/usr/bin/env python3
"""Checks the answers to the owner-readability findings of the review of the follow-up's three fixes (the fifth agent
review of the M0 decisions round; integration log section 24): the workflow relayed that lens's six findings, OWN5-01
to OWN5-06, to the follow-up's fourth fix of 23 October 2026, with the product owner's answers of that day again. Each
check reads the texts its finding named and asserts what the fourth fix's answer (integration log 24.1) says is there
now: the text the finding faulted gone from where the owner reads it (a history note may keep it, in the gate summary's
Section 6.2 or 6.3), and the answer's text present. Where the answer rests on a fact of the repository, the check reads
that fact as well: which Section 23.1 decisions plan 23.1 still has waiting for a sign-off, and whose (OWN5-01); that
the runbook's `linkage.sh` paragraph puts the run before ADR-0014's security items (OWN5-03); which open questions the
reports and the amendments' Section 5 give the technical lead (OWN5-06). What changed in the repeat rule's folders
since pull request #5 (OWN5-04) is a fact of the repository's history, which the gate checks of this round read with
git (part 1d); the history this fix moved (OWN5-05) is checked word for word by moved-notes.py beside this file. It
also reads each of the product owner's answers of 23 October 2026 where the records give it, and asserts that no record
the answers settle still lists it as open. HON-11 is reported as it stands.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-5/commands/recheck-own5.py <repository root>

Run on the third fix's own tree (git archive 660c2b3a, the commit the review read and where this fix starts), it must
report all six findings as not answered; the gate checks of this round (gate-checks.sh beside this file) run that
control. Read-only; standard library only; host only. Prints one line per finding and exits 1 if any of the six is not
answered, or if any answer of 23 October 2026 is no longer recorded.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def line_with(path, start):
    found = [line for line in read(path).splitlines() if line.startswith(start)]
    return found[0] if len(found) == 1 else ""


def block(text, start, end):
    """The text from the line that starts with `start` to the next line that starts with `end` (empty if not found)."""
    lines = text.splitlines()
    first = [i for i, l in enumerate(lines) if l.startswith(start)]
    if len(first) != 1:
        return ""
    rest = [i for i in range(first[0] + 1, len(lines)) if lines[i].startswith(end)]
    return "\n".join(lines[first[0]:rest[0] if rest else len(lines)])


def report(finding, missing, what):
    global problems
    if missing:
        problems += 1
    print(f"{'answered' if not missing else 'PROBLEM '} {finding}: {what}" + (f" ({'; '.join(missing)})" if missing else ""))


def need(text, phrases, where):
    return [f"{where} lacks: {p}" for p in phrases if p not in text]


def gone(text, phrases, where):
    return [f"{where} still says: {p}" for p in phrases if p in text]


GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
AMEND = "Docs/Stage0/M0-plan-amendments.md"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
A03 = "Docs/ADRs/0003-persistence.md"
A09 = "Docs/ADRs/0009-transfer-protocol.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
A15 = "Docs/ADRs/0015-threat-model.md"

gate, runbook, plan = read(GATE), read(RUNBOOK), read(PLAN)
opening = line_with(GATE, "**Recommendation** (Section 7)")
state = line_with(GATE, "- **State:**")
item1 = block(gate, "**1. Before the first session**", "**2. The device sessions**")
item2 = line_with(GATE, "**2. The device sessions**")
item3 = block(gate, "**3. Then", "**4. ")
item4 = block(gate, "**4. ", "**The drop-in run.**")
section3 = block(gate, "## 3. Section 23.1 decisions", "## 4. ")
section54 = block(gate, "### 5.4 ", "## 6. ")
section7 = block(gate, "## 7. Recommendation", "## 8. ")
item76 = block(gate, "76. **The rule for repeating a session**", "77. ")
session10 = block(runbook, "## 6. Session 10", "## 7. What blocks the M0 gate")
security = block(session10, "**Security reviewer: you**", "**Before this review:")
linkage = block(session10, "**Before the reviews of ADR-0014: `linkage.sh` under Xcode 27.1**", "**Designer: you**")
owner = block(session10, "**You, the product owner: the decisions", "- **D-1**")
d03 = block(session10, "**D03's outcome, yours as product owner**", "**Technical lead: you**")
tech = block(session10, "**Technical lead: you**", "**QA: you**")
qa = block(session10, "**QA: you**", "**The iOS lead: you")
persistence = block(session10, "**D17's persistence owner: you, as this runbook assumes**", "**Release owner: you")
table231 = block(session10, "**The Section 23.1 decisions: the sign-offs they still wait for.**",
                 "**The ADR approvals (D-6), yours as product owner**")
approvals = block(session10, "**The ADR approvals (D-6), yours as product owner**", "**The M0 exit review**")
step03 = block(runbook, "**0.3 Commit**", "**0.4 Devices.**")
run1 = line_with(RUNBOOK, "| 1 | Before the sessions |")
run12 = line_with(RUNBOOK, "| 12 | 10 Sign-offs and the exit review |")
row1 = line_with(SESSIONS, "| 1 | Before the sessions")
row12 = line_with(SESSIONS, "| 12 | 10 Sign-offs")

# OWN5-01: the Section 23.1 sign-offs still pending are in Session 10 and item 3, each with what it reads, after which
# run, and where it is recorded; QA has a reading list and a record. Plan 23.1 is read for the decisions whose
# "Pending:" text still names a sign-off, and for whose.
m = []
ROLE_WORDS = {"technical lead": "technical lead", "QA": "QA", "security": "security", "design": "design",
              "persistence owner": "persistence owner"}
pending = {}
for line in plan.split("## 23.1 Decisions to approve before execution", 1)[-1].split("## 23.2 ", 1)[0].splitlines():
    match = re.match(r"^\| (D\d\d) - ", line)
    if match and "Pending:" in line:
        text = line.split("Pending:", 1)[1]
        if "sign-off" in text or "persistence owner's" in text:
            pending[match.group(1)] = [role for role, word in ROLE_WORDS.items() if word in text]
if sorted(pending) != ["D01", "D02", "D03", "D05", "D07", "D08", "D10", "D15", "D16", "D17"]:
    m.append(f"plan 23.1's decisions still waiting for a sign-off are {', '.join(sorted(pending))}: correct the records")
rows = {}
for line in table231.splitlines():
    for decision in re.findall(r"\b(D\d\d) [A-Z]", line.split(" | ")[0]) if line.startswith("| D") else []:
        rows[decision] = line
for decision, roles in sorted(pending.items()):
    if decision not in rows:
        m.append(f"Session 10's table of the Section 23.1 sign-offs lacks {decision}")
        continue
    cell = rows[decision].split(" | ")[1]
    for role in roles:
        if role == "persistence owner" and "persistence owner" not in cell:
            m.append(f"the table's {decision} row lacks the persistence owner's sign-off")
        elif role in ("technical lead", "QA") and role not in cell:
            m.append(f"the table's {decision} row lacks the {role}'s sign-off")
        elif role in ("security", "design") and role not in cell:
            m.append(f"the table's {decision} row lacks the {role} sign-off")
    if len(rows[decision].split(" | ")) < 5:
        m.append(f"the table's {decision} row lacks a column")
if "D03" in rows and "its outcome, yours as product owner" not in rows["D03"]:
    m.append("the table's D03 row lacks D03's outcome")
m += need(tech, ["| D02, the core stack (plan 23.1)", "its lock (section 1:", "ADR-0014 sections 1, 2, 3 and 6",
                 "D02's sign-off in plan 23.1's D02 row"], "the technical lead's part")
m += need(approvals, ["the technical lead's review of its lock (section 1) and item 7"], "the table of approvals")
m += need(qa, ["| D05, the release codec list (plan 23.1", "| Fixture coverage |", "| The device matrix |",
               "| The failure tests |", "| Review | Read | After | Time |",
               "`Docs/Stage0/evidence/M0-runbook/qa-sign-off.md`", "D05's also in plan 23.1's D05 row"],
          "QA's part")
m += need(d03, ["Read:", "After: runs 8 and 9.", "Record: whether quick capture can be advertised"],
          "D03's outcome")
m += need(persistence, ["Read:", "After: runs 3, 6 and 8.", "Record: plan 23.1's D17 row", "say if not"],
          "D17's persistence owner")
m += need(owner, ["Beside them, as product owner, D03's outcome after runs 8 and 9"], "the product owner's paragraph")
m += gone(runbook, ["**QA: you** (about 2 h;"], "the runbook")
m += need(item3, ["D02's sign-off, the core stack, which reads ADR-0014's lock (plan 23.1)",
                  "D05's sign-off of the release codec list (plan 23.1), after run 3's 1.4",
                  "recorded in ADR-0007 and plan 23.1's D03 row", "- **As D17's persistence owner**",
                  "Row 67 also waits for the sign-offs plan 23.1 still names"], "M0-gate.md item 3")
m += gone(item3, ["- **As QA** (about 2 h)"], "M0-gate.md item 3")
d_rows = {d: line_with(GATE, f"| {d} ") for d in ("D02", "D03", "D05", "D17")}
m += need(d_rows["D02"], ["reading ADR-0014's lock (section 1)"], "Section 3's D02 row")
m += need(d_rows["D03"], ["whether it can be is your outcome as product owner, after runs 8 and 9"], "Section 3's D03 row")
m += need(d_rows["D05"], ["with the QA sign-off of the codec list, yours, after run 3's 1.4"], "Section 3's D05 row")
m += need(d_rows["D17"], ["and the persistence owner's, a role your instruction does not name, assumed yours"],
          "Section 3's D17 row")
m += need(line_with(GATE, "| 67 | "), ["the sign-offs plan 23.1 still names for D01, D02, D03, D05, D07, D08, D10, D15, "
                                      "D16 and D17"], "row 67")
# Run 12's estimate of Session 10 grew with the sign-offs added: OWN4-01's answer, whose old estimate ("about 6-6.5
# days of your time") the third fix's recheck still asserts, is asserted here with the new one.
m += need(run12, ["QA (with D05's codec list)", "D02's core stack", "as D17's persistence owner", "ADR-0014's item 6",
                  "`linkage.sh` under Xcode 27.1", "about 6.5-7 days of your time"], "the runbook's run 12")
m += need(item3, ["about 6.5-7 days of your time in all", "(about 1.75 days;", "- **As QA** (about 3 h)"],
          "M0-gate.md item 3")
m += need(tech, ["(about 1.75 days in all; estimates)"], "the technical lead's part")
m += need(row12, ["and D02's sign-off; QA's sign-off, with D05's codec list; D03's outcome; D17's persistence owner's "
                  "sign-off"], "the session log's row 12")
m += need(read(A14), ["with it, the lock of section 1, which the Deciders give the technical lead too"],
          "ADR-0014's technical-lead open item")
m += need(read(A03), ["plan 23.1's D17 also waits for the persistence owner's sign-off"], "ADR-0003's open items")
report("OWN5-01", m, f"Session 10 and item 3 give the sign-offs plan 23.1 still waits for ({', '.join(sorted(pending))}), "
       "D02's with ADR-0014's lock, D05's after run 3, D03's outcome after runs 8 and 9 and D17's persistence owner "
       "assumed the owner's, each with what it reads, when and where it is recorded; QA has a reading list and a record")

# OWN5-02: the owner's session records and evidence are committed on m0-decisions, before an agent works from them;
# nothing reaches main before the exit except the covered merge; step 5's ordering rule covers the owner's own edits.
m = need(item1, ["6. **Commit your session records on `m0-decisions`.**", "before you ask an agent to work from them",
                 "If you build from `main`, check out `m0-decisions` to commit them",
                 "Nothing reaches `main` before the M0 exit except the merge of step 3",
                 "The same holds between your own edits of the records (the session log, a report row, an ADR's "
                 "Deciders line) and an agent's"], "M0-gate.md item 1")
m += need(gate, ["the runbook's 0.3 gives the commands of steps 1-6, under the same numbers",
                 "(runbook 0.3, step 7)", "commit the folder on `m0-decisions` (item 1, step 6)"], "M0-gate.md")
m += need(step03, ["its steps 1-6 are run 1's", "6. **Your session records, on `m0-decisions`.**",
                   "first `git checkout m0-decisions`", "7. **When a session already run is repeated:**",
                   "8. Which sessions can start before that review",
                   "The same holds between your own edits of the records (the session log, a report row, an ADR's "
                   "Deciders line) and an agent's"], "the runbook's 0.3")
m += need(runbook, ["commit its records and evidence on `m0-decisions` (0.3, step 6)",
                    "Record: commit the regenerated log on `m0-decisions` (0.3, step 6)",
                    "committed on `m0-decisions` (0.3, step 6); update row 10 to cite it",
                    "Then commit the folder on `m0-decisions` (0.3, step 6), so that an agent can read it"],
          "the runbook")
m += gone(runbook, ["Record: commit the regenerated log; update the G0.2 row."], "the runbook")
m += need(row1, ["(6) after each sitting, its records and evidence committed on `m0-decisions`"], "the session log's row 1")
for n in range(1, 12):
    if not re.search(rf"(?m)^{n}\. \*\*", item1):
        m.append(f"item 1 lacks its step {n}")
for n in range(1, 9):
    if not re.search(rf"(?m)^{n}\. ", step03):
        m.append(f"the runbook's 0.3 lacks its step {n}")
report("OWN5-02", m, "item 1 and the runbook's 0.3 have the owner commit each session's records and evidence on "
       "m0-decisions before an agent works from them, with nothing on main before the exit but the covered merge; "
       "step 5's rule covers the owner's own edits; 0.7, 0.8, Section 2, the linkage.sh paragraph and the drop-in run "
       "name the branch")

# OWN5-03: linkage.sh is in the security sign-off's three timing lines and in the opening; the D17 cell reads after runs
# 3-6 and 8-11, with 8.10; the class-C row reads 8.10. The runbook still puts the run before the security items.
m = need(security, ["and after the run of `linkage.sh` under Xcode 27.1 (the paragraph after it), which ADR-0014's "
                    "items 4, 5 and 9 wait for", "and 8.10's (G0.5 recovery steps 1 and 2 on device A"],
         "the runbook's security part")
m += gone(security, ["ADR-0012; Session 0.8, 1.2 and 6.1-6.3 results, with 4.16"], "the runbook's class-C row")
m += need(item3, ["and after the run of `linkage.sh` under Xcode 27.1, which ADR-0014's items 4, 5 and 9 wait for"],
          "M0-gate.md item 3")
m += need(run12, ["and after `linkage.sh`'s run, which its ADR-0014 items 4, 5 and 9 wait for"], "the runbook's run 12")
m += need(opening, ["the run of `linkage.sh` under Xcode 27.1 with ADR-0014's section 4 brought up to date from it"],
          "the opening")
m += need(d_rows["D17"], ["after runs 3-6 and 8-11", "8.10"], "Section 3's D17 row")
m += gone(d_rows["D17"], ["(runbook 0.8, 1.2, 6.1, 6.3), before M1"], "Section 3's D17 row")
m += need(line_with(A15, "- Security reviewer: review and sign this model"),
          ["and after the run of `linkage.sh` under Xcode 27.1"], "ADR-0015's security reviewer item")
if "(the security reviewer's items 4, 5 and 9, the release owner's item 6 and the technical lead's item 7)" not in linkage:
    m.append("the runbook's linkage.sh paragraph no longer puts the run before the security reviewer's items: correct "
             "the records")
report("OWN5-03", m, "the security sign-off's timing in item 3, the runbook's security part and run 12, and ADR-0015, "
       "adds linkage.sh's run, which the runbook puts before ADR-0014's items 4, 5 and 9; the opening names it; D17's "
       "cell and the class-C row read 8.10")

# OWN5-04: item 2 says that the checklists changed too; item 76 has its dated note. (The facts: gate checks, part 1d.)
m = need(item2, ["the code in the folders the rule below names changed only in the lock harness",
                 "the device checklists, which the rule names too, changed in all eight"], "M0-gate.md item 2")
m += gone(item2, ["the only change in the folders the rule below names is the lock harness"], "M0-gate.md item 2")
m += need(item76, ["(Dated note, 23 October 2026: the device checklists, which the rule's command lists too, changed in "
                   "all eight since `4c73da57`"], "M0-gate.md item 76")
report("OWN5-04", m, "item 2 says that the code changed only in the lock harness and the drop-in and the checklists in "
       "all eight; item 76 has its dated note (the history itself: the gate checks, part 1d)")

# OWN5-05: the opening and the State line without the review history and notes, each with its pointer; run 1 points to
# item 1. (The moved texts, word for word: moved-notes.py.)
m = []
for where, text, limit, pointer, history in (
        ("the opening", opening, 600, "(This paragraph's history: Section 6.3, item 88.)",
         "an agent review of the assembled decisions round raised 46 findings"),
        ("the State line", state, 200, "(This line's history: Section 6.2, and Section 6.3, item 88.)",
         "the records of your decisions and their first fix were read by two agent reviews"),
        ("the runbook's run 1", run1, 200, "(This run's history: `M0-gate.md` Section 6.3, items 74 and 88.)",
         "(1) `m0-decisions` checked out")):
    words = len(text.split())
    if not text or words > limit:
        m.append(f"{where} has {words} words (at most {limit})")
    m += need(text, [pointer], where)
    m += gone(text, [history], where)
m += need(run1, ["The checklist of `M0-gate.md` Section 1, item 1, in its order, is this run"], "the runbook's run 1")
m += need(gate, ["**The reviews, as the summary's opening told them until the follow-up's fourth fix.**",
                 "88. **The opening, the State line and run 1** (OWN5-05)"], "M0-gate.md Sections 6.2 and 6.3")
# The finding's measure: the State line and the opening, which the owner reads before "What is left for you" (1,269
# words at 660c2b3a).
together = len(state.split()) + len(opening.split())
m += [f"the State line and the opening have {together} words together (at most 800)"] if together > 800 else []
report("OWN5-05", m, f"the opening ({len(opening.split())} words), the State line ({len(state.split())}; {together} "
       f"together) and run 1 ({len(run1.split())}) without the review history and notes, each pointing to where they "
       "are")

# OWN5-06: the technical lead's table has G0.2's open question 12 and G0.1 EPUB's open question 4; item 3 lists ADR-0002's
# amendments apart; item 4 and 5.4 list the report to Readium. The reports and the amendments are read for which open
# questions are the technical lead's.
m = need(tech, ["| G0.1 EPUB's open question 4: who reports Readium findings F1, F4, F6 and F14 upstream",
                "| G0.2's open question 12: whether assembly, the launch re-hash and the receipts run inside",
                "the G0.2 report's open questions 5-7", "| G0.4's question for M2"], "the technical lead's part")
m += need(item3, ["the G0.2 report's 5-7 and 12, G0.1 EPUB's 4 and G0.4's question for M2",
                  "of ADR-0002's amendments, whose record names no role"], "M0-gate.md item 3")
m += gone(item3, ["ADR-0001 (the platform floor and the pin), ADR-0002's amendments, ADR-0003"], "M0-gate.md item 3")
m += need(opening, ["the G0.2 report's open questions 5-7 and 12, G0.1 EPUB's open question 4"], "the opening")
m += need(item4, ["**Four requests to maintainers, a possible fifth, and a measurement, yours**",
                  "A fifth may follow from your answer, as technical lead in Session 10, to G0.1 EPUB's open question 4"],
          "M0-gate.md item 4")
m += need(section54, ["(G0.1 EPUB open question 4, which `M0-plan-amendments.md` Section 5 gives the technical lead); in "
                      "Session 10, after run 5", "ADR-0009's M1 item); in Session 10, after run 4"], "M0-gate.md 5.4")
reports_tl = []
for report_path in sorted((ROOT / "Docs/Stage0").glob("G0*.md")):
    for line in report_path.read_text(encoding="utf-8").splitlines():
        hit = re.match(r"^(\d+)\. Technical lead\b|^- Technical lead \((M\d)\)", line)
        if hit:
            reports_tl.append(f"{report_path.name} {hit.group(1) or hit.group(2)}")
if reports_tl != ["G02-Transfer.md 5", "G02-Transfer.md 6", "G02-Transfer.md 7", "G02-Transfer.md 12",
                  "G04-Audio.md M2"]:
    m.append(f"the reports' questions for the technical lead are now {', '.join(reports_tl)}: correct the records")
tl_line = [l for l in read(AMEND).splitlines() if l.startswith("- **Technical lead:**")]
for ref in ("G0.1 EPUB open question 4", "G0.2 open question 5", "G0.2 open question 6", "G0.2 open question 7",
            "G0.2 open question 12", "G0.4 open questions, for M2"):
    if not tl_line or ref not in tl_line[0]:
        m.append(f"the amendments' Section 5 no longer gives the technical lead {ref}: correct the records")
report("OWN5-06", m, "the technical lead's table has every report question the amendments' Section 5 and the reports "
       f"give the technical lead ({', '.join(reports_tl)} and G01-EPUB.md 4); item 3 lists ADR-0002's amendments apart; "
       "the report to Readium is a possible fifth request")

# The product owner's answers of 23 October 2026, relayed again with the findings: each where the records give it, and
# no record they settle still listing it as open.
answers = 0
a02, a09, a14 = read(A02), read(A09), read(A14)
checks = {
    "1, H-1": [(a02, "ADR-0002", ["*Decided on 23 October 2026: it does.*",
                                  "before the M0 exit review the exception covers pull request #4, pull request #5 and "
                                  "this merge, and no other merge into `main`"]),
               (item4, "M0-gate.md item 4", ["**Merges: decided on 23 October 2026.**"]),
               (line_with(GATE, "1. **ADR-0002's branch rule and the merge.**"), "M0-gate.md item 1 of 6.3",
                ["*(Decided on 23 October 2026: H-1's one-off exception also covers pull request #5"])],
    "2, PO-12": [(item4, "M0-gate.md item 4", ["**PO-12's sources file and import ledger: decided on 23 October 2026, "
                                               "set aside and recover.**"]),
                 (line_with(GATE, "| PO-12 |"), "M0-gate.md 4.1", ["**Decided on 23 October 2026: set aside and "
                                                                    "recover**"]),
                 (a09, "ADR-0009", ["PO-12's sources file and import ledger, decided 2026-10-23"])],
    "3, PO-41 to PO-44": [(item4, "M0-gate.md item 4", ["**PO-41 to PO-44, the questions left for counsel: yours for "
                                                        "now, since 23 October 2026.**"]),
                          (a14, "ADR-0014", ["On 23 October 2026 the product owner took on counsel's part of items 1, "
                                             "2, 3 and 8 for now"]),
                          (line_with(GATE, "| PO-42 |"), "M0-gate.md 4.1's PO-42",
                           ["**23 October 2026: yours for now**, with PO-41, PO-43 and PO-44, but not decided"])],
    "4, the iPad": [(item1, "M0-gate.md item 1", ["**Check your iPad**, with its keyboard and trackpad or mouse (your "
                                                  "answer of 23 October 2026)"]),
                    (line_with(GATE, "| D-1 |"), "M0-gate.md 4.3's D-1",
                     ["On 23 October 2026 you said you have an iPad with a keyboard and a trackpad or mouse"])],
    "5, the readings": [(gate, "M0-gate.md", ["**Three readings of your decisions, confirmed by you on 23 October 2026:**",
                                              "*(23 October 2026: you confirmed the reading: every Stage 0 ADR stays "
                                              "Proposed until Session 10's review of it is recorded"]),
                        (runbook, "the runbook", ["*(23 October 2026: you confirmed this reading of D-6",
                                                  "*(23 October 2026: you confirmed that D-7 keeps the two wordings",
                                                  "*(23 October 2026: you confirmed the reading that D-9 (b) fixes the "
                                                  "App Transport Security key as `NSAllowsLocalNetworking`.)*"])],
}
still_open = [(gate, "M0-gate.md", ["it listed your five open points as still to say", "Five points to answer"]),
              (item4, "M0-gate.md item 4", ["yours to say", "say whether H-1 covers pull request #5"])]
for answer, places in checks.items():
    m = []
    for text, where, phrases in places:
        m += need(text, phrases, where)
    if answer == "1, H-1":
        m += [f"{where} still lists it as open: {p}" for text, where, phrases in still_open for p in phrases
              if p in text and where != "M0-gate.md"]
    answers += not m
    print(f"{'recorded' if not m else 'PROBLEM '} answer {answer}" + (f" ({'; '.join(m)})" if m else ""))
    if m:
        problems += 1

# HON-11: reported as it stands (left for the owner; no agent changes CLAUDE.md on a workflow's request).
stale = "are combined on `m0-integrate`" in read("CLAUDE.md")
print(f"{'open    ' if stale else 'changed '} HON-11: CLAUDE.md's milestone paragraph "
      + ("still says the M0 work is combined on `m0-integrate`: left for the product owner, who commits the change on "
         "m0-decisions (M0-gate.md Section 1, item 1, step 2)" if stale else
         "no longer says the M0 work is combined on `m0-integrate`"))

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of the six findings and five answers not answered "
      f"or not recorded; {answers} of five answers recorded)")
sys.exit(1 if problems else 0)
