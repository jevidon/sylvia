#!/usr/bin/env python3
"""Are the history notes the follow-up's third fix moved kept word for word? (OWN4-09; integration log section 23.) The
fix made the gate summary's Section 1, item 1 and the runbook's 0.3 numbered checklists, item 3 a list by role, and
took the history notes of those texts, of item 2, of the runbook's run 1 and of the bullet on the M0 work on `main` out
of them, into the gate summary's Section 6.3, item 74. This reads the seven notes at the commit the fix starts from
(11f41be5, the follow-up's second fix), with `git show` in the repository, and checks the tree given: each note must
be in item 74 word for word, and no longer in the text it came from.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-4/commands/moved-notes.py <repository root> [<tree>]

The tree defaults to the repository's working tree. Run on the starting commit's own tree (git archive 11f41be5), it
must fail, since the notes are still where they were and there is no item 74: the gate checks of this round run that
control. Read-only; standard library only. Exit status 1 unless every note is moved whole.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
TREE = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT
START = "11f41be59083493109290cc7542cb91f00804981"
GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"


def at_start(path):
    out = subprocess.run(["git", "-C", str(ROOT), "show", f"{START}:{path}"], capture_output=True, text=True, check=True)
    return out.stdout.splitlines()


def one(lines, prefix):
    found = [line for line in lines if line.startswith(prefix)]
    if len(found) != 1:
        sys.exit(f"{prefix!r}: {len(found)} lines at {START[:8]}")
    return found[0]


def cut(line, start, end=None):
    if line.count(start) != 1:
        sys.exit(f"{start[:60]!r} occurs {line.count(start)} times at {START[:8]}")
    a = line.index(start)
    return line[a:line.index(end, a) + len(end)] if end else line[a:]


def block(lines, start, end):
    first = [i for i, l in enumerate(lines) if l.startswith(start)]
    if len(first) != 1:
        return ""
    rest = [i for i in range(first[0] + 1, len(lines)) if lines[i].startswith(end)]
    return "\n".join(lines[first[0]:rest[0] if rest else len(lines)])


gate0, runbook0 = at_start(GATE), at_start(RUNBOOK)
step03 = one(runbook0, "**0.3 Commit** (before 0.2).")
NOTES = {
    "item 1": cut(one(gate0, "**1. Before the first session**"),
                  "(Until 22 October 2026, after the review of the decisions round, this item asked for the iPad only"),
    "item 2": cut(one(gate0, "**2. The device sessions**"),
                  "(Added on 23 October 2026, after the review of the second fix, its finding OWN3-06.)",
                  "(Added on 23 October 2026, after the review of the second fix, its finding OWN3-06.)"),
    "item 3": cut(one(gate0, "**3. Then your sign-offs**"),
                  "(Until 22 October 2026, after the review of the decisions round, this item started the design"),
    "run 1": cut(one(runbook0, "| 1 | Before the sessions |"),
                 "until then this run asked for decisions D-1, D-2 and D-10",
                 "(the same review, its findings HON4-01 and HON4-03)"),
    "0.3, first note": cut(step03, "(Until 22 October 2026, after the review of the decisions round, this step named "
                           "`m0-integrate`", "its findings OWN2-02 and OWN2-03.)"),
    "0.3, second note": cut(step03, "(Added on 23 October 2026, after the review of the second fix, its finding OWN3-06: "
                            "until then", "the same review's finding HON4-01.)"),
    "the bullet on main": cut(one(gate0, "- **The M0 work is on `main`, and the M0 gate is still pending.**"),
                              "*(22 October 2026: that follow-up was pull request #5", "its finding HON-3.)*"),
}

gate = (TREE / GATE).read_text(encoding="utf-8").splitlines()
runbook = (TREE / RUNBOOK).read_text(encoding="utf-8").splitlines()
item74 = block(gate, "74. **The owner's lists, as checklists** (OWN4-09)", "75. ")
sources = {
    "item 1": block(gate, "**1. Before the first session**", "**2. The device sessions**"),
    "item 2": "\n".join(l for l in gate if l.startswith("**2. The device sessions**")),
    "item 3": block(gate, "**3. Then", "**4. "),
    "run 1": "\n".join(l for l in runbook if l.startswith("| 1 | Before the sessions |")),
    "0.3, first note": block(runbook, "**0.3 Commit**", "**0.4 Devices.**"),
    "0.3, second note": block(runbook, "**0.3 Commit**", "**0.4 Devices.**"),
    "the bullet on main": "\n".join(l for l in gate if l.startswith("- **The M0 work is on `main`, and the M0 gate")),
}
misses = 0
print(f"the history notes at {START[:8]}, looked for in {TREE}")
for name, text in NOTES.items():
    kept = bool(item74) and text in item74
    left = text in sources[name]
    ok = kept and not left
    misses += not ok
    print(f"{'moved   ' if ok else 'NOT MOVED'} {name} ({len(text.split())} words): "
          f"{'in item 74 word for word' if kept else 'not in item 74 word for word'}; "
          f"{'still in the text it came from' if left else 'gone from the text it came from'}")
print(f"result: {len(NOTES) - misses} of {len(NOTES)} notes moved whole")
sys.exit(1 if misses else 0)
