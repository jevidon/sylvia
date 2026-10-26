#!/usr/bin/env python3
"""Two helpers of merge-simulation.sh (the fix of the owner-readability findings of the review of m0-records-update;
integration log section 44), kept apart because the build Mac's /bin/bash 3.2 does not parse a here-document inside a
command substitution that holds backquotes. Standard library only; it reads and writes only the files it is given.
    merge-simulation-helpers.py texts-in <root>     prints "yes" when <root>/CLAUDE.md's line 5 is the paragraph of
                                                   claude-md-paragraph.md, its toolchain words are the new ones and not
                                                   the old, and one line begins "Current milestone:"; "no" otherwise
    merge-simulation-helpers.py break <file> <case> changes a copy of CLAUDE.md for one of the apply command's refusals:
                                                   none (no "Current milestone:" line), two (a second one) or
                                                   old-words (the toolchain line without its old words)
"""
import sys
from pathlib import Path


def texts_in(root):
    lines = (root / "Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md").read_text(encoding="utf-8").split("\n")
    paragraph = lines[lines.index("```markdown") + 1]
    quotes = [l[2:] for l in lines[lines.index("## 2. The toolchain line"):] if l.startswith("> ")]
    claude = (root / "CLAUDE.md").read_text(encoding="utf-8")
    ok = (claude.split("\n")[4] == paragraph and quotes[1] in claude and quotes[0] not in claude
          and sum(1 for l in claude.split("\n") if l.startswith("Current milestone:")) == 1)
    print("yes" if ok else "no")


def break_copy(path, case):
    text = path.read_text(encoding="utf-8")
    if case == "none":
        new = text.replace("Current milestone:", "Milestone:")
    elif case == "two":
        new = text.replace("## Setup", "Current milestone: a second line\n\n## Setup", 1)
    elif case == "old-words":
        new = text.replace("awaits a check of Apple's release notes", "awaits something else")
    else:
        raise SystemExit(f"unknown case {case}")
    if new == text:
        raise SystemExit(f"case {case}: the copy did not change")
    path.write_text(new, encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "texts-in":
        texts_in(Path(sys.argv[2]))
    elif len(sys.argv) == 4 and sys.argv[1] == "break":
        break_copy(Path(sys.argv[2]), sys.argv[3])
    else:
        raise SystemExit(__doc__)
