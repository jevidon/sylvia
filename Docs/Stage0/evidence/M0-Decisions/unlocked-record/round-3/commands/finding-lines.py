#!/usr/bin/env python3
"""Do the lines the review of the fix of the record of G0.5 recovery's drop-in run cites hold what it says, at the commit
it names? (The second fix of that record, 23 October 2026; integration log section 27.) The workflow relayed the
review's three findings, UNL2-01 to UNL2-03, with the files and line numbers each cites; the review says it ran the fix's
checks again on 26530d49, the fix's last commit, and does not otherwise name the commit it read. This reads each cited
line with `git show` at a commit (by default 26530d49) and at the record's last commit (91c3b46a, before the fix), and
reports whether the line holds the text the finding quotes or names. It also checks the finding's three claims about
other commits and code: that the fix's sweep patterns (STALE, lines 161-169 of round-2/commands/recheck-unl.py) match
neither of the two rows UNL2-01 names and that neither row names 9cdb0a02; that the pointer UNL2-03 names was written
at e3af4842 (absent at its parent, present there twice) when the lock harness's bullet of Section 2.10 already had two
bullets after it; and that the notes of the fix name what remains for the owner where the two UNL2-02 names do not.
Read-only: it reads git objects and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-3/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line and every claim holds at the commit given. The gate checks of this round run it
at 91c3b46a as its control, where it must fail.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
REVIEWED = sys.argv[2] if len(sys.argv) > 2 else "26530d4933c070c2c154a9116ef6f7fdd0415363"
EARLIER = "91c3b46a1e034563ca9a6df9a77d5c736d202303"
POINTER_COMMIT = "e3af4842"

GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
DEC = "Docs/Stage0/evidence/M0-Decisions"
RECORD = f"{DEC}/unlocked-record/README.md"
ROUND2 = f"{DEC}/unlocked-record/round-2/README.md"
RECHECK = f"{DEC}/unlocked-record/round-2/commands/recheck-unl.py"
ROUND5 = f"{DEC}/followup/round-5/README.md"
OWNER_AGAIN = "0.8 is the owner's again only if what the drop-in builds, copies or runs changes after that commit"
# (finding, path, cited line, text the finding quotes or names on that line)
CITED = [
    ("UNL2-01", LOG, 979, "Both say what changed on 22 October 2026 (the lock harness's steps 13-15, which no run of the "
                          "whole drop-in has passed) |"),
    ("UNL2-01", LOG, 1003, "Section 1 no longer says the assembly ran every check or that G0.5 recovery's drop-in passed "
                           "on its current steps |"),
    ("UNL2-01", LOG, 986, "| HON-6, CHK-07:"),
    ("UNL2-01", LOG, 986, "*(dated note, 23 October 2026: that run was made by a waiter of the orchestrating session on "
                          "`9cdb0a02`"),
    ("UNL2-01", LOG, 1146, "| OWN3-06:"),
    ("UNL2-01", LOG, 1146, "*(dated note, 23 October 2026: 0.8's run was made by a waiter of the orchestrating session on "
                           "`9cdb0a02`"),
    ("UNL2-01", LOG, 1419, "said that no run of the whole drop-in had passed since 22 October 2026"),
    ("UNL2-01", LOG, 1419, "Each of the fifteen now has its dated note, and the fix's recheck sweeps this log and every "
                           "evidence README too"),
    ("UNL2-01", LOG, 1470, "its sweep finds 23 texts in the records that give the run as pending, still to run or the "
                           "owner's"),
    ("UNL2-01", GATE, 677, "*(Dated note, 23 October 2026: not every record."),
    ("UNL2-01", GATE, 677, "each now has its dated note: item 94.)*"),
    ("UNL2-01", GATE, 682, "for any text that still gives the run as pending, still to run or yours with no dated note "
                           "after it"),
    ("UNL2-01", RECORD, 3, "a recheck that sweeps the integration log and every evidence README for any text left without "
                           "one"),
    ("UNL2-01", ROUND2, 14, "for any text that gives the run as pending, still to run or the owner's with no dated note "
                            "naming `9cdb0a02` after it"),
    ("UNL2-01", RECHECK, 161, "STALE = re.compile("),
    ("UNL2-01", RECHECK, 168, "no run of the whole drop-in has passed since|"),
    ("UNL2-01", RECHECK, 169, 'has it run once more")'),
    ("UNL2-02", LOG, 1389, "it stays the runbook's 0.8, for the owner, in Session 0. *(Dated note, 23 October 2026: a "
                           "waiter of the orchestrating session ran it after this fix, on `9cdb0a02`, the fix's last "
                           "commit, with the screen unlocked, and it passed: section 25.)*"),
    ("UNL2-02", ROUND5, 18, "it stays the runbook's 0.8, for the owner; *dated note, 23 October 2026: a waiter of the "
                            "orchestrating session ran it after this fix, on `9cdb0a02`, this fix's last commit, with the "
                            "screen unlocked, and it passed: `../../assembly/unlocked-run-1/`"),
    ("UNL2-03", GATE, 279, "(the last bullet of this section, where that run, on `9cdb0a02`, passed)"),
    ("UNL2-03", GATE, 291, "on `9cdb0a02` (22 October 2026, 22:36-22:44 UTC; the last bullet of this section)"),
    ("UNL2-03", GATE, 292, "- **G0.5 recovery with the lock harness (22 October 2026).**"),
    ("UNL2-03", GATE, 292, "**With the screen unlocked, the whole drop-in passed"),
    ("UNL2-03", GATE, 293, "- **Not run anywhere by agents:**"),
    ("UNL2-03", GATE, 294, "- **The evidence folder's name.**"),
]


def text_at(commit, path):
    out = subprocess.run(["git", "-C", str(ROOT), "show", f"{commit}:{path}"], capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else None


def line_at(commit, path, number):
    text = text_at(commit, path)
    if text is None:
        return None
    lines = text.splitlines()
    return lines[number - 1] if 0 < number <= len(lines) else ""


misses = 0


def report(ok, finding, what):
    global misses
    misses += not ok
    print(f"{'match   ' if ok else 'NO MATCH'} {finding} {what}")


print(f"cited lines read at {REVIEWED} (the commit tested) and at {EARLIER} (the record's last commit, before its fix)")
for finding, path, number, text in CITED:
    here = line_at(REVIEWED, path, number)
    there = line_at(EARLIER, path, number)
    earlier = "absent" if there is None else ("holds it" if text in there else "does not")
    report(here is not None and text in here, finding,
           f"{path}:{number}: {text[:90]!r}; at {EARLIER[:8]} that line {earlier}")

# UNL2-01: the fix's patterns, as committed at the commit tested, match neither row, and neither row names 9cdb0a02.
recheck = text_at(REVIEWED, RECHECK) or ""
found = re.search(r"^STALE = re\.compile\(\n(.*?)\)\n", recheck, re.S | re.M)
stale = None
if found:
    source = "".join(re.findall(r'r"((?:[^"\\]|\\.)*)"', found.group(1)))
    stale = re.compile(source)
for number in (979, 1003):
    row = line_at(REVIEWED, LOG, number) or ""
    hit = stale.search(row) if stale else None
    report(stale is not None and row and not hit and "9cdb0a02" not in row, "UNL2-01",
           f"{LOG}:{number}: the fix's STALE patterns ({len(stale.pattern.split('|')) if stale else 0} alternatives) "
           f"{'match it: ' + hit.group(0) if hit else 'do not match it'}; it names 9cdb0a02: {'9cdb0a02' in row}")

# UNL2-02: the fifteen notes of the fix say what remains for the owner (thirteen in the words the finding quotes, in the
# integration log's lists of what was not done and the five Not run lines; the rows of HON-6 and OWN3-06, which described
# 0.8's request for the run, in their own words); the two notes the finding names do not.
log = (text_at(REVIEWED, LOG) or "").splitlines()
in_log = [n for n, l in enumerate(log, 1) if "section 26, UNL-01" in l and OWNER_AGAIN in l]
readmes = [p for p in (f"{DEC}/fix-2/README.md", f"{DEC}/followup/README.md", f"{DEC}/followup/round-2/README.md",
                       f"{DEC}/followup/round-3/README.md", f"{DEC}/followup/round-4/README.md")
           if f"so {OWNER_AGAIN}: `" in (text_at(REVIEWED, p) or "")]
rows = [n for n, words in ((986, "0.8 now asks for it again only if what the drop-in builds, copies or runs changes after "
                                 "that commit"),
                           (1146, "item 2 now repeats 0.8 if a fix, or another commit the owner builds from, changes what "
                                  "the drop-in builds, copies or runs after that commit"))
        if words in (line_at(REVIEWED, LOG, n) or "")]
report(len(in_log) == 8 and len(readmes) == 5 and rows == [986, 1146], "UNL2-02",
       f"the fifteen notes: {len(in_log)} in the integration log's lists (lines {', '.join(map(str, in_log))}) and "
       f"{len(readmes)} in the evidence READMEs' Not run lines say {OWNER_AGAIN!r}; the rows of HON-6 and OWN3-06 (lines "
       f"{', '.join(map(str, rows))}) say when 0.8 asks for the run again")
for path, number in ((LOG, 1389), (ROUND5, 18)):
    row = line_at(REVIEWED, path, number) or ""
    report(bool(row) and "only if" not in row, "UNL2-02", f"{path}:{number}: its note says what remains for the owner: "
           f"{'only if' in row}")

# UNL2-03: the pointer was written at e3af4842, when the lock harness's bullet already had two bullets after it.
before = text_at(f"{POINTER_COMMIT}^", GATE) or ""
at = text_at(POINTER_COMMIT, GATE) or ""
section = at.split("### 2.10 ", 1)[-1].split("\n## 3. ", 1)[0]
bullets = [l for l in section.splitlines() if l.startswith("- **")]
heads = [re.match(r"- \*\*([^*]+)\*\*", b).group(1) for b in bullets]
lock = [i for i, h in enumerate(heads) if h.startswith("G0.5 recovery with the lock harness")]
after = heads[lock[0] + 1:] if lock else []
report(before.count("the last bullet of this section") == 0 and section.count("the last bullet of this section") == 2
       and len(after) == 2, "UNL2-03",
       f"at {POINTER_COMMIT}: the pointer {section.count('the last bullet of this section')} times in Section 2.10 (at its "
       f"parent {before.count('the last bullet of this section')}); the bullets after the lock harness's: {after}")

total = len(CITED) + 6
print(f"result: {total - misses} of {total} cited lines and claims hold at {REVIEWED[:8]}")
sys.exit(1 if misses else 0)
