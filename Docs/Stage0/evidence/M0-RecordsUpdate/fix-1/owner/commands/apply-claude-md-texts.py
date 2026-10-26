#!/usr/bin/env python3
"""Run 1's step 2, for the product owner to run: put the two texts of claude-md-paragraph.md into CLAUDE.md.

Written by an agent on 27 October 2026 (the fix of the owner-readability findings of the review of m0-records-update,
its finding OWN-RU-04; integration log section 44). No agent runs it on the owner's checkout: the product owner runs it,
or has it run at the owner's request, in ~/Git/sylvia-sessions on m0-decisions, right after the fast-forward merge of
m0-records-update and before Codex or any agent works in that checkout again
(Docs/Stage0/evidence/M0-RecordsUpdate/README.md, "Merging it into m0-decisions"). That merge brings this file.

It reads the two texts from Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md and, in CLAUDE.md:
  1. replaces the one line that begins "Current milestone:" (the milestone paragraph, a single line) with the text of
     that file's section 1, the single line of its ```markdown block;
  2. in the toolchain line (the one line that begins "- Xcode " under "## Toolchain"), replaces the words of the first
     quotation of that file's section 2 with the words of its second.
Every other byte of CLAUDE.md stays as it is. It writes nothing unless each place is found exactly once, or already holds
its new text (then it leaves it and says so). It commits nothing: look at `git diff --stat` (CLAUDE.md alone, two lines
changed), run the lock check (Scripts/ci.d/12-dependency-lock.sh, which compares the toolchain line's Xcode pin), then
commit, as the README says; `git checkout -- CLAUDE.md` undoes it before the commit.

    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/apply-claude-md-texts.py [--check] [<root>]

<root> is the checkout's root (default: the current directory). With --check it says what it would do and writes
nothing. Exit status: 0 when both texts are in place afterwards (or would be, with --check); 1 when a place is not found
exactly once or the texts file is not as expected, and then nothing is written.
"""
import sys
from pathlib import Path

TEXTS = "Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md"


def fail(message):
    print(f"apply-claude-md-texts: {message}; nothing written")
    sys.exit(1)


def texts(path):
    """The paragraph (one line) and the toolchain line's old and new words, as claude-md-paragraph.md gives them."""
    lines = path.read_text(encoding="utf-8").split("\n")
    try:
        one = lines.index("## 1. The milestone paragraph")
        two = lines.index("## 2. The toolchain line")
    except ValueError:
        fail(f"{TEXTS} has no sections 1 and 2")
    fences = [n for n in range(one, two) if lines[n].startswith("```")]
    if len(fences) != 2 or lines[fences[0]] != "```markdown" or fences[1] != fences[0] + 2:
        fail(f"{TEXTS}: section 1 must hold one ```markdown block of one line")
    paragraph = lines[fences[0] + 1]
    if not paragraph.startswith("Current milestone: ") or "\n" in paragraph:
        fail(f"{TEXTS}: the paragraph must be one line that begins \"Current milestone: \"")
    quotes = [l[2:] for l in lines[two:] if l.startswith("> ")]
    if len(quotes) != 2 or not all(quotes):
        fail(f"{TEXTS}: section 2 must hold two quotations, the old words and the new")
    return paragraph, quotes[0], quotes[1]


def main(argv):
    check_only = "--check" in argv
    args = [a for a in argv if a != "--check"]
    root = Path(args[0]) if args else Path(".")
    claude, source = root / "CLAUDE.md", root / TEXTS
    if not claude.is_file() or not source.is_file():
        fail(f"run it at the checkout's root: {claude} or {source} is missing")
    paragraph, old_words, new_words = texts(source)
    raw = claude.read_bytes()
    text = raw.decode("utf-8")
    lines = text.split("\n")
    done = []

    milestone = [n for n, l in enumerate(lines) if l.startswith("Current milestone:")]
    if len(milestone) != 1:
        fail(f"CLAUDE.md has {len(milestone)} lines that begin \"Current milestone:\" (one expected)")
    if lines[milestone[0]] == paragraph:
        done.append("the milestone paragraph: already the new text, left as it is")
    else:
        lines[milestone[0]] = paragraph
        done.append(f"the milestone paragraph (line {milestone[0] + 1}): replaced by the text of section 1")

    try:
        start = lines.index("## Toolchain")
    except ValueError:
        fail("CLAUDE.md has no \"## Toolchain\" section")
    xcode = [n for n in range(start, len(lines)) if lines[n].startswith("- Xcode ")]
    if not xcode:
        fail("CLAUDE.md's Toolchain section has no line that begins \"- Xcode \"")
    n = xcode[0]
    old_count, new_count = lines[n].count(old_words), lines[n].count(new_words)
    whole_old = text.count(old_words)
    if old_count == 0 and new_count == 1:
        done.append("the toolchain line: already the new words, left as it is")
    elif old_count == 1 and whole_old == 1 and new_count == 0:
        lines[n] = lines[n].replace(old_words, new_words)
        done.append(f"the toolchain line (line {n + 1}): its old words replaced by the new ones of section 2")
    else:
        fail(f"the toolchain line holds the old words {old_count} time(s) (CLAUDE.md {whole_old}) and the new "
             f"{new_count} time(s): one of either expected")

    new_text = "\n".join(lines)
    changed = new_text != text
    for d in done:
        print(f"apply-claude-md-texts: {d}")
    if not changed:
        print("apply-claude-md-texts: CLAUDE.md already holds both texts; nothing written")
        return 0
    if check_only:
        print("apply-claude-md-texts: --check: CLAUDE.md would change on those lines alone; nothing written")
        return 0
    claude.write_bytes(new_text.encode("utf-8"))
    print("apply-claude-md-texts: CLAUDE.md written; next: git diff --stat, the lock check, then your commit")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
