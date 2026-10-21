#!/usr/bin/env python3
"""Does the device runbook hold every step of the eight device checklists? (M0 final review R1-01.)

    python3 -I runbook-coverage.py <repository root> [<runbook file to check instead of Docs/Stage0/M0-device-runbook.md>]

1. The steps of each checklist (Docs/Stage0/device-checklists/), read by each file's own numbering: a numbered step
   heading (G0.2 "### N.", G0.4, G0.5 AI and G0.5 recovery "## N."), a numbered item whose title is bold (G0.1 EPUB
   and PDF "N. **Title**"), every numbered item after G0.3's five setup items, and G0.6's table rows "| N |".
2. Classified: the runbook's Section 7 table names the step in its gate's "Blocks M0" or "Can wait" cell, for some
   device. Only those two cells are read; report row numbers ("row 10"), iOS versions and test IDs in them are not
   step numbers.
3. In a session: every step that blocks M0 (for some device) is named by a step of Sections 4-6, either in its
   heading's source (for example "(G0.2 step 22", "(PDF steps 1-3)", "(G0.3 steps 28-30", "(G0.4 Setup 1-5 and
   step 1") or, inside a step whose heading names that gate, as "(step N)" or "Step N." (the runbook's way of walking
   through several checklist steps in one sitting). A step that only "can wait" needs no session (G0.5 recovery step
   5 can never run on an unmodified iPhone, and G0.6 step 10 waits for a Mac build); whether it has one is printed.
A step missing from 2, or a blocking one missing from 3, is printed. Exit status 1 if any is. Standard library only;
reads files only.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
RUNBOOK = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "Docs/Stage0/M0-device-runbook.md"
CHECKLISTS = ROOT / "Docs/Stage0/device-checklists"

# gate key: (checklist file, the runbook's labels for it, the first-column name of its Section 7 row)
GATES = {
    "G0.1 EPUB": ("G01-EPUB.md", [r"G0\.1 EPUB", r"EPUB"], "G0.1 EPUB"),
    "G0.1 PDF": ("G01-PDF.md", [r"G0\.1 PDF", r"PDF"], "G0.1 PDF"),
    "G0.2": ("G02-Transfer.md", [r"G0\.2"], "G0.2"),
    "G0.3": ("G03-Intake.md", [r"G0\.3"], "G0.3"),
    "G0.4": ("G04-Audio.md", [r"G0\.4"], "G0.4"),
    "G0.5 AI": ("G05-AI.md", [r"G0\.5 AI"], "G0.5 AI"),
    "G0.5 recovery": ("G05-Recovery.md", [r"G0\.5 recovery"], "G0.5 recovery"),
    "G0.6": ("G06-Design.md", [r"G0\.6"], "G0.6"),
}


def checklist_steps(name):
    text = (CHECKLISTS / name).read_text(encoding="utf-8")
    if name in ("G02-Transfer.md",):
        found = re.findall(r"^### (\d+)\. ", text, re.M)
    elif name in ("G04-Audio.md", "G05-AI.md", "G05-Recovery.md"):
        found = re.findall(r"^## (\d+)\. ", text, re.M)
    elif name in ("G01-EPUB.md", "G01-PDF.md"):
        found = re.findall(r"^(\d+)\. \*\*", text, re.M)
    elif name == "G03-Intake.md":
        found = [n for n in re.findall(r"^(\d+)\. ", text, re.M) if int(n) >= 6]
    else:  # G0.6: table rows
        found = re.findall(r"^\| (\d+) \| ", text, re.M)
    steps = sorted({int(n) for n in found})
    return steps


def numbers(cell):
    """Step numbers in a list such as "1-10, 12-20, 22, 23; 11 on A" (ranges expanded; 9.2 counts as step 9)."""
    cell = re.sub(r"\([^)]*\)", " ", cell)                          # remarks
    cell = re.sub(r"\b(?:row|rows|iOS|C|T|R|D|M)\s?\d+(?:\.\w+)?", " ", cell)  # rows, versions, IDs, milestones
    out = set()
    for a, b in re.findall(r"(?<![\w.])(\d+)(?:\.\d+|[ab])?(?:-(\d+))?(?![\w])", cell):
        lo = int(a)
        hi = int(b) if b else lo
        out.update(range(lo, hi + 1))
    return out


def section(text, start, end):
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


def classified(text):
    table = section(text, "## 7. What blocks the M0 gate", "**In short.**")
    rows = {}
    for line in table.splitlines():
        if not line.startswith("| ") or line.startswith("| Gate") or line.startswith("| ---"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
        if len(cells) >= 4:
            rows[cells[0]] = (numbers(cells[1]), numbers(cells[3]))
    return rows


LIST = r"((?:\d+(?:\.\d+|[ab])?(?:-\d+)?)(?:(?:,? and |, )\d+(?:\.\d+|[ab])?(?:-\d+)?)*)"


def in_sessions(text):
    body = section(text, "## 4. Sessions on the iPhone 17 Pro and the Mac", "## 7. What blocks the M0 gate")
    found = {g: set() for g in GATES}
    # Headings' and the whole text's labelled references: "<label> step(s) <list>".
    for gate, (_, labels, _) in GATES.items():
        for label in labels:
            pattern = rf"(?<![\w.]){label} (?:[Ss]etup \d+(?:-\d+)? and )?(?:[Ss]etup )?steps? {LIST}"
            if label in (r"EPUB", r"PDF"):
                pattern = rf"(?<![\w.]){label} steps? {LIST}"
            for m in re.finditer(pattern, body):
                found[gate] |= numbers(m.group(1))
    # Inside a step whose heading names one gate: "(step N)" and "Step N." walk-throughs.
    chunks = re.split(r"(?m)^(?=\*\*\d+\.\d+ )", body)
    for chunk in chunks:
        heading = chunk.split("\n", 1)[0]
        gates = [g for g, (_, labels, _) in GATES.items() if any(re.search(rf"(?<![\w.]){l} (?:[Ss]etup )?steps? \d", heading) for l in labels)]
        if len(gates) != 1:
            continue
        for m in re.finditer(r"(?m)\(step (\d+)\)|^- Step (\d+)\.|\bStep (\d+)[:.] ", chunk):
            found[gates[0]].add(int(next(g for g in m.groups() if g)))
    return found


def main():
    text = RUNBOOK.read_text(encoding="utf-8")
    table = classified(text)
    sessions = in_sessions(text)
    problems = 0
    print(f"runbook: {RUNBOOK.relative_to(ROOT) if RUNBOOK.is_relative_to(ROOT) else RUNBOOK}")
    for gate, (name, _, row) in GATES.items():
        steps = checklist_steps(name)
        blocks, can_wait = table.get(row, (set(), set()))
        not_classified = [s for s in steps if s not in blocks | can_wait]
        blocking_not_in_session = [s for s in steps if s in blocks and s not in sessions[gate]]
        waiting_without_session = [s for s in steps if s in can_wait and s not in blocks and s not in sessions[gate]]
        print(f"{gate} ({name}): checklist steps {steps[0]}-{steps[-1]} ({len(steps)}); "
              f"not classified in Section 7: {not_classified or 'none'}; blocking but in no session: "
              f"{blocking_not_in_session or 'none'}; can wait, no session (allowed): {waiting_without_session or 'none'}")
        problems += len(not_classified) + len(blocking_not_in_session)
    print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} missing)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
