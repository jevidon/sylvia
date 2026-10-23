#!/usr/bin/env python3
"""Which commit did the review of the record of G0.5 recovery's whole drop-in run with the screen unlocked read? (The
fix of that review, 23 October 2026; integration log section 26.) The workflow relayed the review's five findings,
UNL-01 to UNL-05, with the files and line numbers each cites, but not the commit the review read. This reads each cited
line at a commit (by default 91c3b46a, the record's last commit) and at the commit the record started from (35543102,
the run's evidence commit), and reports whether the line holds the text the finding quotes or names there; and it
counts the places UNL-01 counts in the record's recheck (its check() calls on lines 77-210, and the five records its
closing sweep reads, lines 212-224). Read-only: it reads git objects with `git show <commit>:<path>` and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-2/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line holds its text, and every count is the finding's, at the commit given. The gate
checks of this round run it at 35543102 as its control, where it must fail.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
REVIEWED = sys.argv[2] if len(sys.argv) > 2 else "91c3b46a1e034563ca9a6df9a77d5c736d202303"
EARLIER = "35543102e4c0f550c7bdd59ca013c788f048e8e3"

GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
LOG = "Docs/Stage0/integration-log.md"
STAGE0 = "Docs/Stage0/README.md"
DEC = "Docs/Stage0/evidence/M0-Decisions"
RECHECK = f"{DEC}/unlocked-record/commands/recheck-unlocked.py"
CHECKRUN = f"{DEC}/unlocked-record/commands/check-run.py"
OWNER = "it stays the runbook's 0.8, for the owner"
# (finding, path, cited line, text the finding quotes or names on that line)
CITED = [
    ("UNL-01", LOG, 1389, "Not run: no code changed since `660c2b3a`, and it stays the runbook's 0.8, for the owner, in "
                          "Session 0. *(Dated note, 23 October 2026"),
    ("UNL-01", f"{DEC}/followup/round-5/README.md", 18, f"(no code changed; {OWNER}; *dated note, 23 October 2026"),
    ("UNL-01", GATE, 590, "35. **The lock harness**"),
    ("UNL-01", GATE, 590, "*(Dated note, 23 October 2026: it ran, and passed, on `9cdb0a02`: item 92.)*"),
    ("UNL-01", GATE, 600, "42. **The lock harness**"),
    ("UNL-01", GATE, 600, "*(Dated note, 23 October 2026: it ran, and passed, on `9cdb0a02`: item 92.)*"),
    ("UNL-01", LOG, 962, "A run with the screen unlocked is pending."),
    ("UNL-01", LOG, 1045, "It is now the runbook's 0.8, for the owner, in Session 0, before Session 6."),
    ("UNL-01", LOG, 1116, "It is the runbook's 0.8, for the owner, in Session 0, before Session 6."),
    ("UNL-01", LOG, 1174, "Not run: no code changed since `a1ea66d2`, and it stays the runbook's 0.8, for the owner, in "
                          "Session 0."),
    ("UNL-01", LOG, 1226, "Not run: no code changed since `19489f10`, and it stays the runbook's 0.8, for the owner, in "
                          "Session 0."),
    ("UNL-01", LOG, 1277, "Not run: no code changed since `13d2b4c7`, and it stays the runbook's 0.8, for the owner, in "
                          "Session 0."),
    ("UNL-01", LOG, 1333, "Not run: no code changed since `11f41be5`, and it stays the runbook's 0.8, for the owner, in "
                          "Session 0."),
    ("UNL-01", f"{DEC}/fix-2/README.md", 20, "runbook 0.8 asks the owner to run it in Session 0"),
    ("UNL-01", f"{DEC}/followup/README.md", 17, OWNER),
    ("UNL-01", f"{DEC}/followup/round-2/README.md", 16, OWNER),
    ("UNL-01", f"{DEC}/followup/round-3/README.md", 17, OWNER),
    ("UNL-01", f"{DEC}/followup/round-4/README.md", 18, OWNER),
    ("UNL-01", GATE, 671, "90. **The records of earlier rounds**"),
    ("UNL-01", LOG, 1419, "Each record that called the run pending, still to run or the owner's to make"),
    ("UNL-01", LOG, 1419, "where a dated text asked for the run, a dated note after it records the run"),
    ("UNL-01", f"{DEC}/unlocked-record/README.md", 3, "The record puts the run wherever the records called it pending"),
    ("UNL-01", f"{DEC}/unlocked-record/README.md", 3, "and checks that it did"),
    ("UNL-01", GATE, 676, "with dated notes where they asked for the run"),
    ("UNL-01", RECHECK, 77, 'check("M0-gate.md item 2 (repeat 0.8 after a fix of the harness)"'),
    ("UNL-01", RECHECK, 205, 'check("the integration log, section 25 and 24.5\'s note", log,'),
    ("UNL-01", RECHECK, 212, "# No record left that still tells the owner to run the whole drop-in once more"),
    ("UNL-01", RECHECK, 216, 'for name, text in (("M0-gate.md", gate), ("the runbook", runbook), ("the session log", '
                             'sessions),'),
    ("UNL-01", RECHECK, 217, '("ADR-0012", a12), ("the Stage 0 README", stage0)):'),
    ("UNL-02", GATE, 4, "the follow-up that records your answers and its four fixes, and this summary's own updates"),
    ("UNL-02", GATE, 4, "the last fix, the follow-up's fourth (23 October 2026), has not been reviewed"),
    ("UNL-02", STAGE0, 5, "the follow-up's fourth fix has not been reviewed"),
    ("UNL-02", LOG, 1423, "already counts this summary's own updates"),
    ("UNL-02", GATE, 677, "93. **Not reviewed**: this record is agent-written"),
    ("UNL-02", RUNBOOK, 11, "- **Who wrote it.**"),
    ("UNL-03", RUNBOOK, 150, "about 1.5 h of your time, 2 h elapsed"),
    ("UNL-03", RUNBOOK, 152, "with three devices to register and the drop-in of 0.8 to run"),
    ("UNL-03", RUNBOOK, 124, "| 1.5 h / 2 h (three devices to register, 0.4) |"),
    ("UNL-03", GATE, 34, "| 1.5 h (2 h) |"),
    ("UNL-03", RUNBOOK, 209, "**So 0.8 needs nothing from you now."),
    ("UNL-04", GATE, 30, "if a fix changes the harness or the drop-in after `9cdb0a02`"),
    ("UNL-04", GATE, 74, "(the recovery package and its lock harness, the drop-in, `Scripts/lib` or the contracts;"),
    ("UNL-04", RUNBOOK, 209, "the recovery package or its lock harness (`Spikes/G05-Recovery`), the drop-in, `Scripts/lib` "
                             "or `Contracts/`"),
    ("UNL-05", LOG, 1397, "everything below is read in the run's committed evidence, except who started it"),
    ("UNL-05", LOG, 1406, "`G05_ALLOW_MISSING_CLASS_B` was not set, as relayed."),
    ("UNL-05", CHECKRUN, 5, "Nothing is inferred."),
    ("UNL-05", CHECKRUN, 153, 'fact("after the run: one git status line (this folder, untracked)",'),
    ("UNL-05", CHECKRUN, 154, 'line(console, "git status --porcelain lines after the run: ") == "git status --porcelain '
                              'lines after the run: 1",'),
]


def lines_at(commit, path):
    out = subprocess.run(["git", "-C", str(ROOT), "show", f"{commit}:{path}"], capture_output=True, text=True)
    return out.stdout.splitlines() if out.returncode == 0 else None


def line_at(commit, path, number):
    lines = lines_at(commit, path)
    if lines is None:
        return None
    return lines[number - 1] if 0 < number <= len(lines) else ""


misses = 0
print(f"cited lines read at {REVIEWED} (the commit tested) and at {EARLIER} (the run's evidence commit, where the record "
      "started)")
for finding, path, number, text in CITED:
    here = line_at(REVIEWED, path, number)
    there = line_at(EARLIER, path, number)
    ok = here is not None and text in here
    misses += not ok
    earlier = "absent" if there is None else ("holds it" if text in there else "does not")
    print(f"{'match   ' if ok else 'NO MATCH'} {finding} {path}:{number}: {text[:90]!r}; at {EARLIER[:8]} that line "
          f"{earlier}")

# UNL-01's counts: the recheck tests a fixed list of 33 places (its check() calls on lines 77-210), and its closing sweep
# (lines 212-224) reads five records only.
recheck = lines_at(REVIEWED, RECHECK) or []
calls = [n for n, l in enumerate(recheck, 1) if l.startswith("check(")]
in_range = [n for n in calls if 77 <= n <= 210]
ok = len(calls) == 33 and len(in_range) == 33
misses += not ok
print(f"{'match   ' if ok else 'NO MATCH'} UNL-01 {RECHECK}: {len(calls)} check() calls, {len(in_range)} of them on "
      "lines 77-210; the finding gives 33")
sweep = "\n".join(recheck[211:224])
names = re.findall(r'\("([^"]+)", (?:gate|runbook|sessions|a12|stage0)\)', sweep)
ok = names == ["M0-gate.md", "the runbook", "the session log", "ADR-0012", "the Stage 0 README"]
misses += not ok
print(f"{'match   ' if ok else 'NO MATCH'} UNL-01 {RECHECK}:212-224: the sweep reads {names}; the finding names the gate "
      "summary, the runbook, the session log, ADR-0012 and the Stage 0 README")
total = len(CITED) + 2
print(f"result: {total - misses} of {total} cited lines and counts hold at {REVIEWED[:8]}")
sys.exit(1 if misses else 0)
