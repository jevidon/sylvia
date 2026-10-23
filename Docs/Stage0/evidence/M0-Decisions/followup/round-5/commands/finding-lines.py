#!/usr/bin/env python3
"""Which commit did the review of the follow-up's three fixes read? (The follow-up's fourth fix, 23 October 2026;
integration log section 24.) The workflow relayed the six findings of that review's owner-readability lens, OWN5-01 to
OWN5-06, with the files and line numbers each cites and the word counts OWN5-05 gives, but not the commit the review
read. This reads each cited line at a commit (by default 660c2b3a, the third fix's last commit) and at the follow-up's
last commit (19489f10, which the fourth review read), and reports whether the line holds the text the finding quotes or
names there; and it counts the words of the three texts OWN5-05 measures, at the commit and at the two earlier commits
whose counts the finding gives (a1ea66d2 and 19489f10). Read-only: it reads git objects with `git show <commit>:<path>`
and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-5/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line holds its text, and every count is the finding's, at the commit given. The gate
checks of this round run it at 19489f10 as its control, where it must fail.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
REVIEWED = sys.argv[2] if len(sys.argv) > 2 else "660c2b3a89a15a86de0352e2f66709a322a40a5e"
EARLIER = "19489f10033e6b79d7509d9041c76850b0006703"

GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
LOG4 = "Docs/Stage0/evidence/M0-Decisions/followup/round-4/gate-checks.log"
G02 = "Docs/Stage0/G02-Transfer.md"
G01E = "Docs/Stage0/G01-EPUB.md"
AMEND = "Docs/Stage0/M0-plan-amendments.md"
# (finding, path, cited line, text the finding quotes or names on that line)
CITED = [
    ("OWN5-01", RUNBOOK, 1015, "What remains of them is D-6's ADR approvals"),
    ("OWN5-01", RUNBOOK, 1032, "**Technical lead: you**"),
    ("OWN5-01", RUNBOOK, 1043, "| ADR-0014's item 7: the roles of its section 2, the CI rules of its section 3"),
    ("OWN5-01", RUNBOOK, 1050, "**QA: you** (about 2 h; plan 23.3: QA approves fixture coverage, the device matrix and "
                               "failure tests"),
    ("OWN5-01", RUNBOOK, 1072, "the technical lead's item 7"),
    ("OWN5-01", RUNBOOK, 134, "| 12 | 10 Sign-offs and the exit review |"),
    ("OWN5-01", GATE, 51, "- **As technical lead**"),
    ("OWN5-01", GATE, 52, "- **As QA** (about 2 h): fixture coverage, the device matrix and the failure tests, and G0.1 "
                          "PDF's open question 5."),
    ("OWN5-01", GATE, 53, "the outcome of D03, whether quick capture can be advertised"),
    ("OWN5-01", GATE, 233, "| 67 | Exit gate: review decisions in Section 23 signed |"),
    ("OWN5-01", GATE, 301, "the technical lead's sign-off, yours, after the device sessions"),
    ("OWN5-01", GATE, 304, "with the QA sign-off, yours"),
    ("OWN5-01", GATE, 316, "| D17 Data protection and durability (new) |"),
    ("OWN5-01", PLAN, 1160, "Pending: the technical lead's sign-off"),
    ("OWN5-01", PLAN, 1163, "Pending: the device run (G0.4 step 1) and the QA sign-off of the codec list"),
    ("OWN5-01", PLAN, 1175, "and the persistence owner's, after G0.5 recovery device steps 1-4 on phone B and steps 1 "
                            "and 2 on device A"),
    ("OWN5-02", RUNBOOK, 104, "(or leave that to an agent working from your records)"),
    ("OWN5-02", RUNBOOK, 160, "**0.3 Commit**"),
    ("OWN5-02", RUNBOOK, 166, "lands on a branch of its own, made from `m0-decisions`"),
    ("OWN5-02", RUNBOOK, 206, "Record: commit the regenerated log"),
    ("OWN5-02", RUNBOOK, 217, "an agent can do it from the folder"),
    ("OWN5-02", RUNBOOK, 1004, "Then ask ADR-0014's owner, an agent"),
    ("OWN5-02", GATE, 14, "**1. Before the first session**"),
    ("OWN5-02", GATE, 17, "every agent you ask starts from that branch"),
    ("OWN5-02", GATE, 20, "made from `m0-decisions`"),
    ("OWN5-02", GATE, 72, "an agent can then update the records that call the run pending"),
    ("OWN5-02", A02, 37, "One branch and one pull request per milestone"),
    ("OWN5-03", RUNBOOK, 134, "and once ADR-0014's R4-01 and R4-02 are closed (run 1)"),
    ("OWN5-03", RUNBOOK, 987, "| Class C protection and the unencrypted backup format"),
    ("OWN5-03", RUNBOOK, 987, "Session 0.8, 1.2 and 6.1-6.3 results"),
    ("OWN5-03", RUNBOOK, 992, "record this sign-off only after runs 3-6 and 8-11 (Section 3)"),
    ("OWN5-03", RUNBOOK, 996, "the security reviewer's items 4, 5 and 9"),
    ("OWN5-03", GATE, 10, "the closing of ADR-0014's R4-01 and R4-02 and the final reviews' records, which need no "
                          "device (item 4)"),
    ("OWN5-03", GATE, 48, "after runs 3-6 and 8-11 and once ADR-0014's R4-01 and R4-02 are closed (item 4)"),
    ("OWN5-03", GATE, 316, "(runbook 0.8, 1.2, 6.1, 6.3)"),
    ("OWN5-04", GATE, 29, "Since `4c73da57` (pull request #5) the only change in the folders the rule below names is "
                          "the lock harness"),
    ("OWN5-04", GATE, 641, "since `4c73da57` those folders changed only in the lock harness and the G0.5 recovery "
                           "drop-in"),
    ("OWN5-04", LOG4, 23, "only the lock harness and the G0.5 recovery drop-in, as M0-gate.md item 2 says"),
    ("OWN5-05", GATE, 4, "- **State:** agent-written."),
    ("OWN5-05", GATE, 10, "**Recommendation** (Section 7)"),
    ("OWN5-05", RUNBOOK, 123, "| 1 | Before the sessions |"),
    ("OWN5-06", RUNBOOK, 1032, "the reports' open questions for the technical lead"),
    ("OWN5-06", RUNBOOK, 1037, "the record names no role for them"),
    ("OWN5-06", GATE, 51, "the G0.2 report's 5-7 and G0.4's question for M2"),
    ("OWN5-06", GATE, 51, "ADR-0002's amendments"),
    ("OWN5-06", GATE, 67, "**Four requests to maintainers, and a measurement, yours**"),
    ("OWN5-06", GATE, 459, "(G0.2 open question 12"),
    ("OWN5-06", G02, 178, "12. Technical lead (round 3, finding R3-04)"),
    ("OWN5-06", G01E, 112, "4. Who reports F1, F4, F6 and F14 to Readium"),
    ("OWN5-06", AMEND, 368, "who reports Readium findings F1, F4, F6 and F14 upstream"),
]
# OWN5-05's word counts: (path, the line's start, commit, words the finding gives)
COUNTS = [
    (GATE, "**Recommendation** (Section 7)", None, 867),
    (GATE, "**Recommendation** (Section 7)", "a1ea66d2", 288),
    (GATE, "**Recommendation** (Section 7)", EARLIER, 423),
    (GATE, "- **State:**", None, 402),
    (RUNBOOK, "| 1 | Before the sessions |", None, 578),
]


def lines_at(commit, path):
    out = subprocess.run(["git", "-C", str(ROOT), "show", f"{commit}:{path}"], capture_output=True, text=True)
    return out.stdout.splitlines() if out.returncode == 0 else None


def line_at(commit, path, number):
    lines = lines_at(commit, path)
    if lines is None:
        return None
    return lines[number - 1] if 0 < number <= len(lines) else ""


misses = 0
print(f"cited lines read at {REVIEWED} (the commit tested) and at {EARLIER} (the follow-up, which the fourth review read)")
for finding, path, number, text in CITED:
    here = line_at(REVIEWED, path, number)
    there = line_at(EARLIER, path, number)
    ok = here is not None and text in here
    misses += not ok
    earlier = "absent" if there is None else ("holds it" if text in there else "does not")
    print(f"{'match   ' if ok else 'NO MATCH'} {finding} {path}:{number}: {text[:90]!r}; at {EARLIER[:8]} that line "
          f"{earlier}")
print(f"OWN5-05's word counts (words split on white space):")
for path, start, commit, words in COUNTS:
    lines = lines_at(commit or REVIEWED, path) or []
    found = [l for l in lines if l.startswith(start)]
    count = len(found[0].split()) if len(found) == 1 else None
    ok = count == words
    misses += not ok
    print(f"{'match   ' if ok else 'NO MATCH'} {path} {start!r} at {(commit or REVIEWED)[:8]}: {count} words; the "
          f"finding gives {words}")
total = len(CITED) + len(COUNTS)
print(f"result: {total - misses} of {total} cited lines and counts hold at {REVIEWED[:8]}")
sys.exit(1 if misses else 0)
