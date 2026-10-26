#!/usr/bin/env python3
"""Does a live text name `m0-sessions` as a branch to build from, commit to or merge into? (The fix of the fidelity
findings of the review of m0-records-update, 26 October 2026; integration log section 42; its finding FID-RU-01: at
832a3636 the runbook's 0.7 had the owner commit a session record on m0-sessions, the gate summary's Section 5.4 had the
owner commit the session records on it and build from it, and no check of the branch read those texts.)

Since m0-records-update (integration log section 41) m0-decisions is the product owner's session branch and m0-sessions
is retired: nothing is built from it, nothing is committed or merged into it, and its work reaches the owner through
m0-records-update. So no live text may give m0-sessions as the branch to build from, to commit to, to merge into, to
start agent work from, to check out, or as the branch the M0 work is on. A text may still name it in its history: what
a text said until a date, what a round did on that branch, what a record of 24 October 2026 said, once a later note says
the branch is retired.

The live texts: CLAUDE.md, the repository README, the plan, and every Markdown file in Docs/ADRs, Docs/Stage0 and
Docs/Stage0/device-checklists, with this branch's own evidence READMEs (every .md under
Docs/Stage0/evidence/M0-RecordsUpdate/ but the findings as relayed, which are quoted verbatim). The other evidence
folders record earlier runs and rounds and are not edited. Two kinds of record inside the live files are history by
design and are read as such: the gate summary's Section 6.3 groups that record what an earlier round corrected (from the
first "Corrected in" or "Recorded" group to the group recorded when m0-records-update brought the branches together,
which is read, with every later group), and the integration log's sections before 41, each the record of a round as
it was done.

For every mention of `m0-sessions` (in code marks, as the records write branch names) and of `git checkout m0-sessions`,
the check takes its clause: the text between the nearest sentence end, semicolon or opening parenthesis before it and
the next after it, the parentheticals inside it left out (they are clauses of their own). A clause is a branch use when
it matches one of USES (build from, commit on, merge into, made from, start or work from, check out or switch to, is or
continues on, plays the part of, is the session branch, holds the session records, use). A branch use is:
  history     when its clause has a mark of history (HISTORY): "until" with a date or a round, "from 24 to 26 October",
              "this <text> said/had/named/...", "as written on", a past passive ("was merged"), a past event with its
              date, "retired", "no longer", or a report of what a text says or said;
  superseded  when it is in a note or a bullet dated 24 October 2026 and a later note of 26 October 2026 in the same
              paragraph says that m0-sessions is retired (the convention the review's finding FID-RU-04 asks for);
  live        otherwise: the check fails, naming the file, the line and the clause.
Every branch use is listed with its kind and the mark that made it history, so that the reading can be audited.
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/commands/retired-branch-texts.py [<root>]
Run on the tree of 832a3636 (git archive), the commit the review read, it must fail on the runbook's 0.7, the gate
summary's Section 5.4 and its three notes of 24 October 2026 without a follow-up (lines 122, 471 and 556 there), and
CLAUDE.md (the runner beside this file runs that control and a mutation). Standard library only; read-only.
Exit status 1 if a live branch use is found.
"""
import re
import sys
from pathlib import Path

ARGS = [a for a in sys.argv[1:] if a != "--all"]
ALL = "--all" in sys.argv[1:]  # also list the mentions that are no branch use, and those read as history by design
ROOT = Path(ARGS[0]).resolve() if ARGS else Path.cwd()
NAME = "`m0-sessions`"
M = "\x00M\x00"  # the mention being judged, inside its clause

USES = [(k, re.compile(p, re.I)) for k, p in [
    ("build from", r"\bbuil(?:d|ds|t|ding)\b[^;]{0,100}?\bfrom\s+" + M),
    ("the branch the sessions build from", M + r"[^;]{0,60}?\bthe branch (?:the|your) (?:device )?sessions build from"),
    ("commit on", r"\bcommit(?:s|ted|ting)?\b[^;]{0,120}?\bon\s+" + M),
    ("holds the session records", M + r"[^;]{0,80}?\bholds?\b[^;]{0,60}?\bsession records"),
    ("merge into", r"\bmerg(?:e|es|ed|ing)\b[^;]{0,120}?\binto\s+" + M),
    ("go into or reach", r"\b(?:go|goes|going|land|lands|come|comes|reach|reaches|arrive|arrives)\s+(?:into\s+|in\s+)?" + M),
    ("move to", r"(?<!its )(?<!the )(?<!a )(?<!that )\b(?:move|moves|moving|moved)\b[^;]{0,60}?\bto\s+" + M),
    ("made from", r"\bmade\s+from\s+" + M),
    ("start or work from", r"\b(?:start|starts|started|starting|work|works|working)\b[^;]{0,80}?\bfrom\s+" + M),
    ("check out or switch to", r"\b(?:check(?:ed|s)?\s+out|checkout|switch(?:es|ed|ing)?)\b[^;]{0,80}?" + M),
    ("is or continues on", r"\b(?:is|are|continues|continue|stays|stay|goes|go|lands|land|happens|runs)\s+on\s+" + M),
    ("plays the part", M + r"[^;]{0,60}?\bplays the part\b"),
    ("is the session branch", M + r"[^;]{0,40}?\b(?:is|stays|remains|becomes)\s+(?:the|your)\s+(?:session|sessions'|M0)\b"),
    ("use", r"\b(?:use|uses)\s+" + M),
]]
HISTORY = [(k, re.compile(p, re.I)) for k, p in [
    ("until a date or a round", r"\buntil\s+(?:\d{1,2}\s+October\s+2026|the\s+(?:integration|fix|review|follow-up|merge|"
                                r"assembly|update|second|third|fourth|fifth|M0)\b|`m0-records-update`|then,\s+on\b)"),
    ("from a date to a date", r"\bfrom\s+(?:\d{1,2}|then)\b[^;]{0,40}?\b(?:to|until)\s+(?:\d{1,2}\b|the\s+integration)"),
    ("a text said", r"\b(?:this|that|these|those|its|their|the|item\s+\d+'s)\s+(?:[\w'.-]+\s+){0,3}?(?:step|steps|sentence|"
                    r"note|notes|bullet|paragraph|item|items|line|lines|cell|parenthesis|row|text|texts|section|header|"
                    r"instruction|instructions|record|records|summary|runbook|checklist|checklists|title|table)\b"
                    r"[^;]{0,100}?\b(?:said|had|named|gave|kept|left|called|sent|listed|asked|pointed|described|wrote|"
                    r"put|offered|let|counted|read)\b"),
    ("as written or read then", r"\bas\s+(?:written|it\s+read|they\s+read|read)\s+(?:on|at)\b"),
    ("a past passive", r"\b(?:was|were|had\s+been)\s+(?:made|merged|built|committed|recorded|stopped|retired|switched|"
                       r"saved|moved|written|to\s+be|then\s+to)\b"),
    ("retired or dropped", r"\bretired\b|\bno\s+longer\b|\bnothing\s+is\s+built\s+from\b|\bdropped\b|\bwas\s+stopped\b"),
    ("rejected or moved then", r"\brejected\b|\bmoved\b"),
    ("a past event with its date", r"\b(?:merged|made|committed|switched|moved|began|wrote|saved|read|brought|asked)\b"
                                   r"[^;]{0,160}?\bon\s+\d{1,2}\s+October\s+2026\b"),
    ("a dated past event", r"\bon\s+\d{1,2}\s+October\s+2026\b[^;]{0,80}?\b(?:merged|made|committed|switched|moved)\b"),
    ("the branch then", M + r"\s+then\b"),
    ("a report of a text", r"\b(?:said|saying|says\s+that|reads\s+that|quoted|quoting|names\s+" + M + r"\s+as)\b"),
    ("a finding's words", r"\b(?:[A-Z]+\d*-)+\d{2}\b[^:;]{0,24}:\s"),
    ("a past merge by its maker", r"\b(?:an?|the|that|this|its)\s+(?:[\w'-]+\s+){0,3}?(?:merged|committed|switched)\s+"
                                  r"(?:it|them|both|[\w`'-]+)\s+(?:into|on|to)\s+" + M),
]]
# A later note of 26 October 2026 in the same paragraph that says the branch is retired, or that m0-decisions is the
# session branch again.
NOTE_26 = re.compile(r"^\(\s*(?:Dated note,\s*)?26 October 2026\b")
DROPPED = re.compile(r"\bretired\b|`m0-decisions`[^()]{0,60}?\bsession branch|session branch again")


def live_files():
    files = [ROOT / "CLAUDE.md", ROOT / "README.md", ROOT / "Docs" / "Sylvia_v1_iOS_Implementation_Plan.md"]
    for folder in ("Docs/ADRs", "Docs/Stage0", "Docs/Stage0/device-checklists"):
        files += sorted((ROOT / folder).glob("*.md"))
    own = ROOT / "Docs/Stage0/evidence/M0-RecordsUpdate"
    files += sorted(p for p in own.rglob("*.md") if p.name != "relayed-findings.md")
    return [p for p in files if p.is_file()]


def history_lines(path, lines):
    """Line numbers (1-based) read as history by design: the gate summary's Section 6.3 groups of earlier rounds and
    the integration log's sections before 41."""
    skip = set()
    rel = path.relative_to(ROOT).as_posix()
    if rel == "Docs/Stage0/M0-gate.md":
        in63 = in8 = skipping = reached = False
        for n, line in enumerate(lines, 1):
            if line.startswith("#"):
                in63 = line.startswith("### 6.3 ")
                in8 = line.startswith("## 8. ")
                skipping = False
            if in63 and not reached and re.match(r"^(?:Corrected|Recorded) ", line):
                # The group recorded when m0-records-update brought the branches together, and every later one, are
                # read; every group of an earlier round before it is a record of that round.
                reached = line.startswith("Recorded on 26 October 2026, when `m0-records-update`")
                skipping = not reached
            if skipping:
                skip.add(n)
            # Section 8's bullets that record an earlier round, as their headings name it (an integration log
            # section before 41).
            heading = re.match(r"^- \*\*([^*]*)\*\*", line)
            if in8 and heading:
                numbers = [int(x) for x in re.findall(r"integration log sections? (\d+)", heading.group(1))]
                if numbers and max(numbers) < 41:
                    skip.add(n)
    elif rel == "Docs/Stage0/integration-log.md":
        on = False
        for n, line in enumerate(lines, 1):
            m = re.match(r"^## (\d+)\. ", line)
            if m:
                on = int(m.group(1)) < 41
            if on:
                skip.add(n)
    return skip


def structure(line):
    """Which characters are inside code marks, and the matching parentheses outside them."""
    code = [False] * len(line)
    inside = False
    for i, ch in enumerate(line):
        if ch == "`":
            inside = not inside
            code[i] = True
        else:
            code[i] = inside
    pair = {}
    stack = []
    for i, ch in enumerate(line):
        if code[i]:
            continue
        if ch == "(":
            stack.append(i)
        elif ch == ")" and stack:
            j = stack.pop()
            pair[j], pair[i] = i, j
    return code, pair


def sentence_end(line, i):
    """A full stop at i that ends a sentence: followed by a space and a character that is not a lower-case letter."""
    if line[i] != ".":
        return False
    rest = line[i + 1:]
    if not rest or rest[0] in ")*":
        return True
    return rest[0] == " " and (len(rest) == 1 or not rest[1].islower())


def clause(line, s, e, code, pair):
    """The clause around line[s:e], its own parentheticals left out, and the enclosing parentheses."""
    parts_left, i = [], s - 1
    left_stop = 0
    while i >= 0:
        ch = line[i]
        if code[i]:
            i -= 1
            continue
        if ch == ")" and i in pair and pair[i] < i:
            parts_left.append(line[pair[i]:i + 1])
            i = pair[i] - 1
            continue
        if ch in "(;" or sentence_end(line, i):
            left_stop = i + 1
            break
        i -= 1
    j, right_stop = e, len(line)
    while j < len(line):
        ch = line[j]
        if code[j]:
            j += 1
            continue
        if ch == "(" and j in pair and pair[j] > j:
            j = pair[j] + 1
            continue
        if ch in ");" or sentence_end(line, j):
            right_stop = j
            break
        j += 1
    text = line[left_stop:right_stop]
    # Leave out the parentheticals wholly inside the clause.
    out, k = [], left_stop
    while k < right_stop:
        if not code[k] and line[k] == "(" and k in pair and pair[k] > k and pair[k] < right_stop:
            k = pair[k] + 1
            continue
        out.append(line[k])
        k += 1
    reduced = "".join(out)
    enclosing = sorted(a for a, b in pair.items() if a < s and b > e and line[a] == "(")
    return reduced, (left_stop, right_stop), enclosing


def quoted(line, s, code):
    """Is the mention inside a quotation ("..."), outside code marks: the record of what a text said?"""
    return sum(1 for i, ch in enumerate(line[:s]) if ch == '"' and not code[i]) % 2 == 1


def judge(line, s, e, code, pair):
    reduced, (a, b), enclosing = clause(line, s, e, code, pair)
    marked = reduced[: s - a] + M + reduced[s - a + (e - s):] if reduced[s - a: s - a + (e - s)] == line[s:e] else None
    if marked is None:  # a parenthetical before the mention was left out: locate the mention again
        k = reduced.find(line[s:e])
        marked = reduced[:k] + M + reduced[k + (e - s):]
    use = next((k for k, p in USES if p.search(marked)), None)
    if not use:
        return None, None, reduced
    if quoted(line, s, code):
        return "history", f"{use}; a quotation of what a text said", reduced
    hist = next((k for k, p in HISTORY if p.search(marked)), None)
    if hist:
        return "history", f"{use}; {hist}", reduced
    # A later note of 26 October 2026 in the same paragraph, after the note or clause the mention is in, that says the
    # branch is retired (or m0-decisions the session branch again).
    after = max([pair[o] for o in enclosing] + [b])
    for o in sorted(k for k, v in pair.items() if k > after and line[k] == "(" and v > k):
        if NOTE_26.match(line[o:]) and DROPPED.search(line[o:pair[o] + 1]):
            return "superseded", f"{use}; a later note of 26 October 2026 says it is retired", reduced
    return "live", use, reduced


def paragraphs(lines):
    """The file's paragraphs as (first line number, text): the records write most paragraphs on one line, and the
    evidence READMEs wrap theirs; a wrapped line is joined to the one before it, so that a clause is read whole."""
    out, fence = [], False
    marker = re.compile(r"^\s*(?:[-*]|\d+\.)\s")
    for n, line in enumerate(lines, 1):
        if line.startswith("```"):
            fence = not fence
            out.append([n, line])
            continue
        prev = out[-1][1] if out else ""
        joins = (not fence and line.strip() and out and prev.strip() and not prev.startswith(("#", "|", "```"))
                 and not line.startswith(("#", "|")) and not marker.match(line) and not lines[n - 2].startswith("```"))
        if joins:
            out[-1][1] = prev + " " + line.strip()
        else:
            out.append([n, line])
    return [(n, text) for n, text in out]


def main():
    files = live_files()
    live, counts = [], {"live": 0, "history": 0, "superseded": 0, "not a branch use": 0,
                        "read as history by design": 0}
    listed = []
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        skip = history_lines(path, lines)
        for n, line in paragraphs(lines):
            spans = [(m.start(), m.end()) for m in re.finditer(re.escape(NAME), line)]
            spans += [(m.start(), m.end()) for m in re.finditer(r"`git (?:checkout|switch) m0-sessions`", line)]
            if not spans:
                continue
            if n in skip:
                counts["read as history by design"] += len(spans)
                if ALL:
                    listed.append(f"{'BY DESIGN':10} {rel}:{n}: {len(spans)} mentions in a record of an earlier round")
                continue
            code, pair = structure(line)
            for s, e in spans:
                kind, why, text = judge(line, s, e, code, pair)
                if kind is None:
                    counts["not a branch use"] += 1
                    if ALL:
                        listed.append(f"{'NO USE':10} {rel}:{n}: ...{text.strip()[:260]}...")
                    continue
                counts[kind] += 1
                entry = f"{kind.upper():10} {rel}:{n}: [{why}] ...{text.strip()[:260]}..."
                listed.append(entry)
                if kind == "live":
                    live.append(entry)
    print(f"root: {ROOT}")
    print(f"live files read: {len(files)}")
    for k, v in counts.items():
        print(f"mentions {k}: {v}")
    print(f"branch uses live: {len(live)}")
    print()
    print("Every branch use, with its kind and the mark that made it history:")
    for entry in listed:
        print("  " + entry)
    print()
    if live:
        print(f"FAIL {len(live)} live texts name `m0-sessions` as a branch to build from, commit to or merge into:")
        for entry in live:
            print("  " + entry)
        print()
        print("result: FAIL")
        return 1
    print("PASS no live text names `m0-sessions` as a branch to build from, commit to or merge into")
    print("result: pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
