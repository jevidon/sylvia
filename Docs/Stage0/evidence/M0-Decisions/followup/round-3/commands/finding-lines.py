#!/usr/bin/env python3
"""Which commit did the honesty lens of the review of the follow-up read? (The follow-up's second fix, 23 October 2026;
integration log section 22.) The workflow relayed the lens's six findings, HON4-01 to HON4-06, with the files and line
numbers each cites, but not the commit the review read. This reads each cited line at a commit (by default 19489f10,
the follow-up's last commit, whose line numbers the fidelity lens's findings matched, section 21) and at the fix's
starting commit (13d2b4c7, the follow-up's fix), and reports whether the line holds the text the finding quotes or
names there. Read-only: it reads git objects with `git show <commit>:<path>` and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-3/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line holds its text at the first commit.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
REVIEWED = sys.argv[2] if len(sys.argv) > 2 else "19489f10033e6b79d7509d9041c76850b0006703"
START = "13d2b4c795994d5b85531ab60f758ce753aa06c7"

GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
# (finding, path, cited line, text the finding quotes or names on that line)
CITED = [
    ("HON4-01", RUNBOOK, 160, "or by pull request for `main`), between sessions"),
    ("HON4-01", GATE, 37, "merge that branch into the branch you build from, between sessions"),
    ("HON4-01", "Docs/ADRs/0002-repository-build-and-ci.md", 41, "The rule stays for every other milestone branch"),
    ("HON4-02", GATE, 41, "the exit review approves ADR-0014"),
    ("HON4-02", GATE, 41, "as items for the public-release gate"),
    ("HON4-02", RUNBOOK, 1014, "the exit review approves ADR-0014"),
    ("HON4-02", "Docs/ADRs/0014-dependency-lock-and-license-inventory.md", 233, "the exit review approves this record"),
    ("HON4-02", "Docs/Stage0/integration-log.md", 1142, "the exit review approves ADR-0014"),
    ("HON4-03", "Docs/ADRs/0001-platform-baseline-and-toolchain.md", 53, "on iPadOS 26.x or 27.x as it has"),
    ("HON4-03", "Docs/Stage0/device-checklists/G06-Design.md", 50, "on iPadOS 26.x or 27.x, as it has"),
    ("HON4-03", "Docs/Sylvia_v1_iOS_Implementation_Plan.md", 1045, "so no device has to be acquired"),
    ("HON4-03", RUNBOOK, 23, "**C. An iPad**"),
    ("HON4-03", RUNBOOK, 123, "on the OS they have"),
    ("HON4-03", GATE, 14, "Your iPad, with its keyboard and trackpad or mouse"),
    ("HON4-04", GATE, 10, "M0 cannot be approved yet. It waits on no decision of yours"),
    ("HON4-04", GATE, 560, "Section 1 no longer says M0 waits on no decision at all"),
    ("HON4-04", GATE, 582, "M0 cannot be approved yet. It waits on no decision of yours"),
    ("HON4-05", "Docs/Stage0/integration-log.md", 832, "the owner decided all three that day"),
    ("HON4-05", "Docs/Stage0/M0-plan-amendments.md", 4, "You decided them on 23 October 2026"),
    ("HON4-05", "Docs/Stage0/M0-plan-amendments.md", 357, "the recommended default applies"),
    ("HON4-05", GATE, 41, "which bind only advertising material that mentions the companion's features"),
    ("HON4-05", GATE, 61, "stayed open until you decided them"),
    ("HON4-05", "Docs/ADRs/0014-dependency-lock-and-license-inventory.md", 177,
     "which bind only advertising material that mentions the companion's features"),
    ("HON4-06", "README.md", 49, "this merge before the M0 exit review, which approves nothing"),
    ("HON4-06", "Docs/Stage0/README.md", 5, "raised six more"),
    ("HON4-06", "Docs/ADRs/README.md", 15, "Status (22 October 2026)"),
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
