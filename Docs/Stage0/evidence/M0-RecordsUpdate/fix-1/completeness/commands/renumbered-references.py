#!/usr/bin/env python3
"""Is every reference that m0-records-update's merges brought numbered as the merged records number it? (The fix of the
completeness findings of the review of m0-records-update, 27 October 2026; integration log section 43; its finding
CMP-03: two lines of the gate summary's Section 8 kept four of m0-sessions's numbers, though integration log 41.2 and
the gate summary's item 184 said that the lines both branches changed were renumbered by hand.)

m0-exit-prep (c3adae68) and m0-sessions (1d5ac477) each continued the integration log after section 27 and the gate
summary's Section 6.3 after item 103. Merged, m0-exit-prep's keep their numbers (sections 28-35, items 104-130) and
m0-sessions's are shifted (its sections 28-32 are 36-40, its items 104-150 are 131-177). So every reference to an item
or a section in a text that came from m0-sessions must be shifted, and every one in a text from m0-exit-prep must not.

For every reference this reads ("item(s) N", "section(s) N", "integration log N", with lists and ranges, a number
followed by ".N" being a sub-section and no part of a list) to an item of 100 or more or a section of 28 or more, in the
records both branches wrote (the gate summary, the runbook, the Stage 0 README, the ADR index, the amendments and the
integration log), it takes the text before the reference on its line and looks for that text, digits read as any
number, followed by the same kind of reference, in the same paragraph on each of the two branches (the lines that begin
as this one does, digits read as any number), from the longest context to the shortest (100, 70, 45 and 25
characters) until one matches; a paragraph found on neither branch is looked for in the whole file, with a context of
45 characters at least:
  sessions  found on m0-sessions alone: the numbers it had there, shifted, must be the numbers here;
  exit-prep found on m0-exit-prep alone: the numbers it had there must be the numbers here;
  both      found on both with the same numbers, which no shift changes: nothing to check; with numbers the shift
            would change, or different numbers: AMBIGUOUS, listed for a reader;
  new       found on neither: a text written after the merges (the integration, its fixes), listed with what each
            number names here, for a reader (with --list-new).
A list that the integration combined from both branches' texts (more numbers here than on the branch its context came
from) is MIXED: it passes if it holds every number its origin requires, and is listed. A reference on m0-sessions to an
item it never wrote (151-158) or to its never-written section 33 is RE-POINTED, as integration log 41.2 says, and is
listed. A reference whose numbers differ from what its origin requires is WRONG, unless it is one of the texts ALLOWED
below, each a text that gives what a finding cited at a past commit, which keeps that commit's numbers by design
(integration log 41.2). Every reference whose context was found on m0-sessions is listed with its verdict, so the
reading can be audited. Read-only (git show); standard library only. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/commands/renumbered-references.py [<root>] [--list-new]
<root> is the tree whose records are read (by default the current directory); the runner beside this file runs it on
this tree, on the tree of 832a3636, the commit the review read, and on a copy of this tree with CMP-03's four references
put back, each of which must fail on exactly its wrong references.
Exit status 1 if a reference is WRONG.
"""
import re
import subprocess
import sys

SESSIONS, EXIT_PREP = "1d5ac477", "c3adae68"
FILES = ["Docs/Stage0/M0-gate.md", "Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/README.md", "Docs/ADRs/README.md",
         "Docs/Stage0/M0-plan-amendments.md", "Docs/Stage0/integration-log.md"]
LIST_NEW = "--list-new" in sys.argv[1:]
ARGS = [a for a in sys.argv[1:] if a != "--list-new"]
ROOT = ARGS[0] if ARGS else "."  # the tree whose records are read; git show reads the two branches
# Texts that quote what a finding cited at a past commit, with that commit's numbers (integration log 41.2): the text
# before the reference, as it reads here, and why.
ALLOWED = {
    "(`M0-gate.md:714` is ": "integration log 38.1 gives the gate summary's item at 8082bdb6, the commit the accuracy "
                             "findings cite, as numbered there",
    "(`M0-gate.md:714` is item 115 there, and ": "the same parenthesis of integration log 38.1: the item at "
                                                 "d6315ad3, the commit the task named, as numbered there",
    "(OWN-DA-01 cites ": "integration log 40.1 gives the item OWN-DA-01 cites at 8082bdb6, as numbered there",
}
NUM = r"\d+(?![.\d])"
REF = re.compile(r"\b(items?|sections?|integration log)( )(" + NUM + r")((?:(?:, | and |-)" + NUM + r")*)")


def git_show(rev, path):
    r = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True)
    return r.stdout.decode("utf-8") if r.returncode == 0 else ""


def kind(word):
    return "item" if word.startswith("item") else "section"


def in_range(k, n):
    return n >= 100 if k == "item" else 28 <= n <= 60


def shift(k, n):
    if k == "item" and 104 <= n <= 150:
        return n + 27
    if k == "section" and 28 <= n <= 32:
        return n + 8
    return n


def numbers(first, rest):
    return [int(first)] + [int(x) for x in re.findall(r"\d+", rest)]


def context_regex(context, word):
    parts = re.split(r"(\d+)", context)
    rx = "".join(r"\d+" if p.isdigit() else re.escape(p) for p in parts)
    return re.compile(rx + re.escape(word) + r" (" + NUM + r")((?:(?:, | and |-)" + NUM + r")*)")


def prefix(line):
    """How a paragraph begins, its list number and every digit read as any number."""
    return re.sub(r"\d+", "#", re.sub(r"^\d+\. ", "", line))[:50]


def paragraphs(text):
    by_prefix = {}
    for line in text.split("\n"):
        if line.strip():
            by_prefix.setdefault(prefix(line), []).append(line)
    return by_prefix


def titles(gate, log):
    items, sections = {}, {}
    in63 = False
    for line in gate.split("\n"):
        if line.startswith("### "):
            in63 = line.startswith("### 6.3 ")
        m = re.match(r"^(\d+)\. \*\*(.+?)\*\*", line)
        if in63 and m:
            items[int(m.group(1))] = m.group(2)
    for line in log.split("\n"):
        m = re.match(r"^## (\d+)\. (.*)$", line)
        if m:
            sections[int(m.group(1))] = m.group(2)
    return items, sections


def origin_of(line, m, sess, exitp, sess_paras, exit_paras):
    """(verdict, numbers on the branch, context used, where looked)."""
    key = prefix(line)
    where_s, where_e = sess_paras.get(key), exit_paras.get(key)
    if where_s or where_e:
        scope, s_text, e_text, widths = "paragraph", "\n".join(where_s or []), "\n".join(where_e or []), (100, 70, 45, 25)
    else:
        scope, s_text, e_text, widths = "file", sess, exitp, (100, 70, 45)
    for width in widths:
        ctx = line[max(0, m.start() - width):m.start()]
        if len(ctx) < min(width, m.start()) or not ctx.strip():
            continue
        rx = context_regex(ctx, m.group(1))
        in_s = [numbers(x.group(1), x.group(2)) for x in rx.finditer(s_text)]
        in_e = [numbers(x.group(1), x.group(2)) for x in rx.finditer(e_text)]
        if width == 25:
            # A short context recurs (`M0-gate.md` Section 6.3, ...): it counts only when the paragraph here holds it as
            # often as the branch's does, and then the reference is matched with the one in the same place there.
            here = [x.start() for x in rx.finditer(line)]
            i = here.index(m.start() - len(ctx)) if m.start() - len(ctx) in here else -1
            in_s = [in_s[i]] if i >= 0 and len(in_s) == len(here) else []
            in_e = [in_e[i]] if i >= 0 and len(in_e) == len(here) else []
        if not in_s and not in_e:
            continue
        if in_s and not in_e:
            return ("sessions" if all(v == in_s[0] for v in in_s) else "AMBIGUOUS"), in_s[0], ctx, scope
        if in_e and not in_s:
            return ("exit-prep" if all(v == in_e[0] for v in in_e) else "AMBIGUOUS"), in_e[0], ctx, scope
        k = kind(m.group(1))
        same = all(v == in_s[0] for v in in_s + in_e)
        if same and [shift(k, x) for x in in_s[0]] == in_s[0]:
            return "both", in_s[0], ctx, scope
        return "AMBIGUOUS", None, ctx, scope
    return "new", None, "", scope


def main():
    gate = open(f"{ROOT}/Docs/Stage0/M0-gate.md", encoding="utf-8").read()
    log = open(f"{ROOT}/Docs/Stage0/integration-log.md", encoding="utf-8").read()
    item_titles, section_titles = titles(gate, log)

    def name(k, n):
        t = item_titles.get(n) if k == "item" else section_titles.get(n)
        return f"{k} {n}: {t[:90] if t else '(none)'}"

    counts = dict.fromkeys(["sessions", "exit-prep", "both", "new", "MIXED", "RE-POINTED", "allowed", "AMBIGUOUS",
                            "WRONG"], 0)
    wrong, listed = [], []
    for path in FILES:
        here = open(f"{ROOT}/{path}", encoding="utf-8").read().split("\n")
        sess, exitp = git_show(SESSIONS, path), git_show(EXIT_PREP, path)
        sess_paras, exit_paras = paragraphs(sess), paragraphs(exitp)
        for n, line in enumerate(here, 1):
            for m in REF.finditer(line):
                k = kind(m.group(1))
                nums = numbers(m.group(3), m.group(4))
                if not any(in_range(k, x) for x in nums):
                    continue
                verdict, origin_nums, ctx, scope = origin_of(line, m, sess, exitp, sess_paras, exit_paras)
                where = f"{path}:{n}: {m.group(0)!r}"
                shown = f"context ({scope}) ...{ctx[-70:]!r}"
                if verdict in ("sessions", "exit-prep"):
                    if verdict == "sessions" and any((k == "item" and 151 <= x <= 158) or (k == "section" and x == 33)
                                                     for x in origin_nums):
                        counts["RE-POINTED"] += 1
                        listed.append(f"RE-POINTED {where}: on m0-sessions {origin_nums}, never written there; names "
                                      + "; ".join(name(k, x) for x in nums))
                        continue
                    expected = [shift(k, x) for x in origin_nums] if verdict == "sessions" else origin_nums
                    if expected == nums:
                        counts[verdict] += 1
                        if verdict == "sessions":
                            listed.append(f"sessions   {where}: {origin_nums} there, shifted: ok")
                        continue
                    if len(nums) > len(expected) and all(x in nums for x in expected):
                        counts["MIXED"] += 1
                        listed.append(f"MIXED      {where}: from {verdict}, where it read {origin_nums}, so it holds "
                                      f"{expected}, with " + "; ".join(name(k, x) for x in nums if x not in expected))
                        continue
                    key = next((a for a in ALLOWED if line[:m.start()].endswith(a)), None)
                    if key:
                        counts["allowed"] += 1
                        listed.append(f"allowed    {where}: as on {verdict}, {origin_nums}: {ALLOWED[key]}")
                        continue
                    counts["WRONG"] += 1
                    wrong.append(f"WRONG      {where}: from {verdict}, where it read {origin_nums}, so it must read "
                                 f"{expected}; {shown}")
                    continue
                counts[verdict] += 1
                if verdict == "AMBIGUOUS":
                    listed.append(f"AMBIGUOUS  {where}: {shown}; names " + "; ".join(name(k, x) for x in nums))
                elif verdict == "new" and LIST_NEW:
                    listed.append(f"new        {where}: names " + "; ".join(name(k, x) for x in nums))
    print(f"references read in {len(FILES)} files, to items of 100 or more and sections of 28 or more")
    print("by origin: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    print()
    for line in wrong + listed:
        print(line)
    print()
    print("result: " + ("pass" if not wrong else f"FAIL ({len(wrong)} wrong)"))
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
