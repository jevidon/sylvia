#!/usr/bin/env python3
"""Compare two logs of the latest gate summary checks, unchanged
(Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-3/commands/gate-checks.sh): one made on the commit this hand-over
starts from and one on its last documents commit. That script was written for the second fix of the record of the drop-in
run (integration log section 27) and fails, by design, on any change of CLAUDE.md since 26530d49; the commit this
hand-over starts from, 5aec2518, is the CLAUDE.md correction the gate summary asks for (Section 1, item 1, step 2), so
both runs fail on exactly that. What must hold: the lines that report a problem, a failed control or a failed recheck
(PROBLEM, NOT as required, result: FAIL, exit: 1 and above) are the same in both logs, so this hand-over adds none, and the
base log's only failing parts are 1b's and 1c's lines on CLAUDE.md, every other part saying it passed or failed as
required.

  python3 -I Docs/Stage0/evidence/M0-Integration/item-reviews/commands/compare-gate-checks.py <base log> <head log>
"""
import collections
import re
import sys

PROBLEM = re.compile(r"PROBLEM|NOT as required|result: FAIL|^\s*exit: [1-9]")


def lines(path):
    with open(path, encoding="utf-8") as fh:
        return [line.rstrip("\n") for line in fh]


def problems(text):
    return collections.Counter(line.strip() for line in text if PROBLEM.search(line))


def head_line(text):
    return next((line for line in text if line.startswith("commit:")), "commit: ?")


base, head = lines(sys.argv[1]), lines(sys.argv[2])
print(f"base: {sys.argv[1]}: {head_line(base)}")
print(f"head: {sys.argv[2]}: {head_line(head)}")
pb, ph = problems(base), problems(head)
print(f"lines reporting a problem, a failed control or a failed recheck: {sum(pb.values())} in the base log, "
      f"{sum(ph.values())} in the head log")
only_head = ph - pb
only_base = pb - ph
status = 0
for line, n in sorted(only_head.items()):
    print(f"PROBLEM only in the head log ({n}x): {line}")
    status = 1
for line, n in sorted(only_base.items()):
    print(f"note    only in the base log ({n}x): {line}")
claude = [line.strip() for line in base if "CLAUDE.md" in line and PROBLEM.search(line)]
print("the base log's lines on CLAUDE.md that report a problem:")
for line in claude:
    print(f"        {line}")
if len(claude) != 2:
    print("PROBLEM: expected exactly 1b's and 1c's lines on CLAUDE.md")
    status = 1
# Every other failing line of the base log must sit inside a part that ends "as required" (a recheck or control that
# must fail and did), so that the only part failing for real is 1b/1c.
last_exit = max((i for i, l in enumerate(base) if l.startswith("exit:")), default=-1)  # the script's own exit line
parts, current = [], []
for i, line in enumerate(base):
    if i == last_exit:
        continue
    if line.startswith("-- ") or line.startswith("== "):
        if current:
            parts.append(current)
        current = [line]
    else:
        current.append(line)
if current:
    parts.append(current)
unexplained = []
for part in parts:
    failing = [l for l in part if PROBLEM.search(l) and "CLAUDE.md" not in l]
    if failing and not any(re.search(r"^\s*as required", l) for l in part):
        unexplained.append(part[0])
for p in unexplained:
    print(f"PROBLEM: a part of the base log fails without saying 'as required': {p}")
    status = 1
end = [l for l in head if l.startswith("exit:")]
print(f"the head log's last exit line: {end[-1] if end else '?'} (1, from 1b and 1c, as in the base log)")
print(f"result: {'pass' if status == 0 else 'FAIL'}")
sys.exit(status)
