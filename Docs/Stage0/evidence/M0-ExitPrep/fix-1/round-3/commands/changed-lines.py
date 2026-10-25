#!/usr/bin/env python3
"""Where a file changed between two commits, read from git diff -U0: the line numbers each hunk touches, on the old side
and the new side, and, with --block, whether every hunk lies inside the block of lines that starts at the first line
matching START and ends before the next line matching END, on each side.

    python3 -I changed-lines.py <old commit> <new commit> <path> [--block START END]

Prints "lines: <new-side line numbers>" (a range a-b where a hunk changes several), and with --block "block: ok" or
"block: PROBLEM ..."; exits 1 if a hunk lies outside the block. <new commit> may be "worktree", the uncommitted tree,
for a dry run. Read-only; git only. Used by this fix's gate checks (gate-checks.sh beside this file, part 1k).
"""
import re
import subprocess
import sys

old, new, path = sys.argv[1:4]
block = sys.argv[5:7] if len(sys.argv) >= 7 and sys.argv[4] == "--block" else None


def git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True, text=True, check=True).stdout


hunks = []
for line in git("diff", "-U0", old, *([] if new == "worktree" else [new]), "--", path).splitlines():
    m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
    if m:
        a, b, c, d = (int(m.group(1)), int(m.group(2) or 1), int(m.group(3)), int(m.group(4) or 1))
        hunks.append(((a, a + b - 1) if b else (a, a - 1), (c, c + d - 1) if d else (c, c - 1)))


def show(r):
    return str(r[0]) if r[0] == r[1] else f"{r[0]}-{r[1]}"


print("lines: " + (", ".join(show(n) for _, n in hunks if n[1] >= n[0]) or "none"))
status = 0
if block:
    def span(commit):
        if commit == "worktree":
            with open(path, encoding="utf-8") as fh:
                lines = fh.read().split("\n")
        else:
            lines = git("show", f"{commit}:{path}").split("\n")
        start = next((i for i, l in enumerate(lines, 1) if re.search(block[0], l)), None)
        if start is None:
            return None
        end = next((i - 1 for i, l in enumerate(lines, 1) if i > start and re.search(block[1], l)), len(lines))
        return start, end

    so, sn = span(old), span(new)
    outside = [h for h in hunks if not so or not sn
               or (h[0][1] >= h[0][0] and not (so[0] <= h[0][0] and h[0][1] <= so[1]))
               or (h[1][1] >= h[1][0] and not (sn[0] <= h[1][0] and h[1][1] <= sn[1]))]
    if outside or not hunks:
        status = 1
        print(f"block: PROBLEM: {len(outside)} of {len(hunks)} hunks outside the block (old {so}, new {sn})")
    else:
        print(f"block: ok: {len(hunks)} hunk(s), all inside the block (old lines {show(so)}, new lines {show(sn)})")
sys.exit(status)
