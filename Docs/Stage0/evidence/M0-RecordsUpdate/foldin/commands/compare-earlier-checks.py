#!/usr/bin/env python3
"""What the earlier rechecks and gate checks report after the fold-in of m0-device-fixes into m0-records-update, beside
what they reported at the fix of the owner-readability findings of the review of m0-records-update (27 October 2026;
integration log section 45). Each pins texts and states of the branch it was written on, and is recorded as it reports;
this prints, for each, the lines that name a problem or a result (PROBLEM, FAIL, result, exit, missing) that are in one
run and not in the other, after replacing commit hashes, times and load averages, which change with every run, so that
what changed is read off this log rather than from two logs of thousands of lines.
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands/compare-earlier-checks.py [<new checks dir>]
The old logs: Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/checks/; the new: the fold-in's checks folder (or the
folder given). Read-only; standard library only; exits 0 (it compares, it judges nothing).
"""
import re
import sys
from pathlib import Path

OLD = Path("Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/checks")
NEW = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Docs/Stage0/evidence/M0-RecordsUpdate/foldin/checks")
LOGS = ["recheck-hon-ep.log", "decisions-branch.log", "recheck-own.log", "gate-checks-exit-prep.log",
        "gate-checks-devicea.log"]
KEEP = re.compile(r"PROBLEM|^\s*FAIL\b|^\s*result:|^\s*exit:|missing|^\s*== |^-- \d+[a-z]\.")


def norm(line):
    line = re.sub(r"\b[0-9a-f]{40}\b", "<commit>", line)
    line = re.sub(r"\b\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\b", "<time>", line)
    line = re.sub(r"load averages?: [\d. ]+", "load <l>", line)
    line = re.sub(r"\d+:\d\d\s+up [^,]+, \d+ users?,", "<uptime>", line)
    return line.rstrip()


def lines(path):
    if not path.is_file():
        return None
    out = []
    for raw in path.read_text(encoding="utf-8", errors="replace").split("\n"):
        if KEEP.search(raw):
            out.append(norm(raw)[:400])
    return out


for name in LOGS:
    old, new = lines(OLD / name), lines(NEW / name)
    print(f"== {name}")
    if old is None or new is None:
        print(f"   {'old' if old is None else 'new'} log missing")
        continue
    sold, snew = set(old), set(new)
    gone = [l for l in old if l not in snew]
    added = [l for l in new if l not in sold]
    print(f"   lines naming a problem or a result: {len(old)} at the owner-readability fix, {len(new)} now; "
          f"{len(gone)} only then, {len(added)} only now")
    for l in gone:
        print(f"   - {l.strip()}")
    for l in added:
        print(f"   + {l.strip()}")
    print()
