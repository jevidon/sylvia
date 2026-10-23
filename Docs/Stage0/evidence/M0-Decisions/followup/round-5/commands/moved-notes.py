#!/usr/bin/env python3
"""Are the history texts the follow-up's fourth fix moved kept word for word? (OWN5-05; integration log section 24.)
The fix took the review history out of the gate summary's State line and opening paragraph, into its Section 6.2 (the
paragraph that starts "The reviews, as the summary's opening told them until the follow-up's fourth fix"), and their dated notes
into Section 6.3, item 88. This reads the four texts at the commit the fix starts from (660c2b3a, the third fix's last
commit), with `git show` in the repository, and checks the tree given: each text must be in its new place word for
word, and no longer in the line it came from.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-5/commands/moved-notes.py <repository root> [<tree>]

The tree defaults to the repository's working tree. Run on the starting commit's own tree (git archive 660c2b3a), it
must fail, since the texts are still where they were and neither new place exists: the gate checks of this round run
that control. Read-only; standard library only. Exit status 1 unless every text is moved whole.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
TREE = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT
START = "660c2b3a89a15a86de0352e2f66709a322a40a5e"
GATE = "Docs/Stage0/M0-gate.md"


def at_start(path):
    out = subprocess.run(["git", "-C", str(ROOT), "show", f"{START}:{path}"], capture_output=True, text=True, check=True)
    return out.stdout.splitlines()


def one(lines, prefix):
    found = [line for line in lines if line.startswith(prefix)]
    if len(found) != 1:
        sys.exit(f"{prefix!r}: {len(found)} lines at {START[:8]}")
    return found[0]


def cut(line, start, end):
    if line.count(start) != 1:
        sys.exit(f"{start[:60]!r} occurs {line.count(start)} times at {START[:8]}")
    a = line.index(start)
    return line[a:line.index(end, a) + len(end)]


def block(lines, start, end):
    first = [i for i, l in enumerate(lines) if l.startswith(start)]
    if len(first) != 1:
        return ""
    rest = [i for i in range(first[0] + 1, len(lines)) if lines[i].startswith(end)]
    return "\n".join(lines[first[0]:rest[0] if rest else len(lines)])


gate0 = at_start(GATE)
state0 = one(gate0, "- **State:**")
opening0 = one(gate0, "**Recommendation** (Section 7)")
# (name, text at 660c2b3a, the line it came from (its start), where it goes: "6.2" or "88")
TEXTS = [
    ("the State line's review history",
     cut(state0, "the M0 final fix's edits to them (19 and 20 October 2026)",
         "and none of the three fixes has been reviewed at all (Section 7, item 5)."), "- **State:**", "6.2"),
    ("the State line's note",
     cut(state0, "(Until 23 October 2026 this line said the last fixes had not been reviewed at all",
         "and until the follow-up's fix, that the follow-up had not been.)"), "- **State:**", "88"),
    ("the opening's review history",
     cut(opening0, "an agent review of the assembled decisions round raised 46 findings",
         "none of the three fixes has been reviewed (Section 6.2)."), "**Recommendation** (Section 7)", "6.2"),
    ("the opening's notes",
     cut(opening0, "(Until 23 October 2026 this paragraph said M0 no longer waits on any decision",
         "the same review's finding OWN4-08.)"), "**Recommendation** (Section 7)", "88"),
]

gate = (TREE / GATE).read_text(encoding="utf-8").splitlines()
places = {
    "6.2": block(gate, "**The reviews, as the summary's opening told them until the follow-up's fourth fix.**",
                 "Still open and recorded in the repository besides these"),
    "88": block(gate, "88. **The opening, the State line and run 1** (OWN5-05)", "89. "),
}
misses = 0
print(f"the history texts at {START[:8]}, looked for in {TREE}")
for name, text, source, place in TEXTS:
    kept = bool(places[place]) and text in places[place]
    lines = [l for l in gate if l.startswith(source)]
    left = any(text in l for l in lines)
    ok = kept and not left and len(lines) == 1
    misses += not ok
    where = "Section 6.2" if place == "6.2" else "Section 6.3, item 88"
    print(f"{'moved   ' if ok else 'NOT MOVED'} {name} ({len(text.split())} words): "
          f"{'in ' + where + ' word for word' if kept else 'not in ' + where + ' word for word'}; "
          f"{'still in the line it came from' if left else 'gone from the line it came from'}")
print(f"result: {len(TEXTS) - misses} of {len(TEXTS)} texts moved whole")
sys.exit(1 if misses else 0)
