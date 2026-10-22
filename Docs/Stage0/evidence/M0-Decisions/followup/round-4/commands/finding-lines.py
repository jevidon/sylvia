#!/usr/bin/env python3
"""Which commit did the owner-readability lens of the review of the follow-up read? (The follow-up's third fix, 23
October 2026; integration log section 23.) The workflow relayed the lens's nine findings, OWN4-01 to OWN4-09, with the
files and line numbers each cites, but not the commit the review read. This reads each cited line at a commit (by
default 19489f10, the follow-up's last commit, whose line numbers the same review's fidelity and honesty findings
matched, sections 21 and 22) and at the fix's starting commit (11f41be5, the follow-up's second fix), and reports
whether the line holds the text the finding quotes or names there. Read-only: it reads git objects with
`git show <commit>:<path>` and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-4/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line holds its text at the first commit.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
REVIEWED = sys.argv[2] if len(sys.argv) > 2 else "19489f10033e6b79d7509d9041c76850b0006703"
START = "11f41be59083493109290cc7542cb91f00804981"

GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
A15 = "Docs/ADRs/0015-threat-model.md"
# (finding, path, cited line, text the finding quotes or names on that line)
CITED = [
    ("OWN4-01", GATE, 41, "release owner (item 6) and technical lead (item 7)"),
    ("OWN4-01", GATE, 223, "6 (release owner) and 7 (technical lead) wait for your sign-offs in Session 10"),
    ("OWN4-01", GATE, 42, "under Xcode 27.1"),
    ("OWN4-01", GATE, 42, "ask Readium to drop marmelroy/Zip or move to a fixed fork (item 4)"),
    ("OWN4-01", GATE, 429, "And run `linkage.sh` under Xcode 27.1"),
    ("OWN4-01", RUNBOOK, 980, "(its section 7, items 4, 5 and 9)"),
    ("OWN4-01", RUNBOOK, 1012, "**Technical lead and QA: you** (about 2 h each)"),
    ("OWN4-01", RUNBOOK, 1014, "design, and the release owner."),
    ("OWN4-01", GATE, 33, "as release owner (distribution and privacy declarations)"),
    ("OWN4-02", RUNBOOK, 160, "(its harness, spike or drop-in)"),
    ("OWN4-02", RUNBOOK, 160, "HEAD -- Docs/Stage0/device-checklists Spikes Scripts/ci.d`"),
    ("OWN4-02", GATE, 16, "(its harness, spike or drop-in)"),
    ("OWN4-02", GATE, 16, "<the new one> -- Docs/Stage0/device-checklists Spikes Scripts/ci.d`"),
    ("OWN4-03", RUNBOOK, 160, "or by pull request for `main`), between sessions"),
    ("OWN4-03", GATE, 37, "merge that branch into the branch you build from"),
    ("OWN4-03", A02, 41, "The rule stays for every other milestone branch"),
    ("OWN4-04", A15, 301, "Sessions 0.7, 0.8, 1.1-1.3, 4 and 6.1-6.5, and G0.1 EPUB steps 11 and 13)"),
    ("OWN4-04", A15, 304, "before the M1 app target is created, or before any product target links Readium if that comes first"),
    ("OWN4-05", RUNBOOK, 974, "Session 2's steps 11 and 13"),
    ("OWN4-06", GATE, 14, "change its milestone paragraph, or ask for the change"),
    ("OWN4-06", GATE, 590, "for example to \"were combined on `m0-integrate`"),
    ("OWN4-06", RUNBOOK, 123, "change its milestone paragraph, or ask for the change"),
    ("OWN4-07", GATE, 42, "run `evidence/M0-dependencies/commands/linkage.sh` under Xcode 27.1"),
    ("OWN4-07", GATE, 429, "And run `linkage.sh` under Xcode 27.1"),
    ("OWN4-07", GATE, 584, "**What remains, in order:**"),
    ("OWN4-08", GATE, 33, "**3. Then your sign-offs**"),
    ("OWN4-08", GATE, 403, "| G0.5 AI | 1-4, 5-7, 9.2, 9.3 on B"),
    ("OWN4-08", RUNBOOK, 993, "Also yours: G0.5 AI step 9.2, the wording review"),
    ("OWN4-08", GATE, 10, "It waits on no decision of yours"),
    ("OWN4-08", GATE, 582, "It waits on no decision of yours"),
    ("OWN4-09", GATE, 14, "**1. Before the first session**"),
    ("OWN4-09", GATE, 33, "**3. Then your sign-offs**"),
    ("OWN4-09", GATE, 91, "after the exit review, as ADR-0002's rule has it, unless you decide"),
    ("OWN4-09", GATE, 91, "and since your answer of the same day, before the exit review too"),
    ("OWN4-09", RUNBOOK, 160, "**0.3 Commit**"),
]


def line_at(commit, path, number):
    out = subprocess.run(["git", "-C", str(ROOT), "show", f"{commit}:{path}"], capture_output=True, text=True)
    if out.returncode != 0:
        return None
    lines = out.stdout.splitlines()
    return lines[number - 1] if 0 < number <= len(lines) else ""


misses = 0
print(f"cited lines read at {REVIEWED} (the commit tested) and at {START} (the fix's starting commit)")
for finding, path, number, text in CITED:
    here = line_at(REVIEWED, path, number)
    there = line_at(START, path, number)
    ok = here is not None and text in here
    misses += not ok
    later = "holds it" if there is not None and text in there else "does not"
    print(f"{'match   ' if ok else 'NO MATCH'} {finding} {path}:{number}: {text!r}; at {START[:8]} that line {later}")
print(f"result: {len(CITED) - misses} of {len(CITED)} cited lines hold their text at {REVIEWED[:8]}")
sys.exit(1 if misses else 0)
