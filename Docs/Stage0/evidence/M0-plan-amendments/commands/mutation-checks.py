#!/usr/bin/env python3
"""Mutation checks for check-amendments.py.

Each mutation breaks one claim the amendments make; the checker must then fail
the check that guards that claim. Run from the repository root, on a clean tree:
    python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/mutation-checks.py
Each mutation is written to the working copy, the checker runs, and the file is
restored from memory before the next one. Exits 1 if any mutation is missed.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
CHECKER = "Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py"
DOC = "Docs/Stage0/M0-plan-amendments.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"

# (what the mutation breaks, file, text replaced, replacement, the check that must fail)
MUTATIONS = [
    ("an unforced narrowing left out of Section 1.2", DOC,
     "personal quotation and search without AI text. [M0-A10]",
     "personal quotation and search without AI text.",
     "every scope-narrowing row's tag"),
    ("an unforced narrowing's row labelled a clarification", DOC,
     "stated beside its alternatives (PO-05) | scope narrowing | A10 |",
     "stated beside its alternatives (PO-05) | clarification | A10 |",
     "every Section 1.2 tag has a Section 2 row classified scope narrowing"),
    ("a narrowing missing from plan Appendix D's scope sentence", PLAN,
     "cleartext to a local model server only at an IP literal (A14);",
     "cleartext to a local model server only at an IP literal;",
     "plan Appendix D's draft 0.5 entry names exactly"),
    ("an ADR consequence left unnumbered", DOC,
     " (10) Tasks topped up from background callbacks",
     " Tasks topped up from background callbacks",
     "Section 3.2: ADR-0001 to ADR-0014"),
    ("an ADR consequence with no destination", DOC,
     "Homebrew ffmpeg for the G0.4 fixtures: no change, a repository tooling fact",
     "Homebrew ffmpeg for the G0.4 fixtures: a repository tooling fact",
     "Section 3.2: ADR-0001 to ADR-0014"),
    ("a G0.4 open-question bullet left uncovered", DOC,
     "| G0.4 open questions, the warnings note |",
     "| G0.4 warnings |",
     "G04-Audio.md: 7 open-question bullets"),
    ("a new quoted phrase with no vocabulary entry", PLAN,
     'text features show "No selectable text on this page". No guessed OCR text',
     'text features show "No selectable text on this page" or "Text missing here". No guessed OCR text',
     "plan Sections 1-23"),
    ("a phrase dropped from the vocabulary gaps table", PLAN,
     '"Already imported" (a same-file reimport; Section 7.3); ',
     "",
     "plan Sections 1-23"),
    ("a product-owner question renumbered", DOC,
     "| PO-36 |",
     "| PO-37 |",
     "Section 4 lists PO-01 to PO-36"),
    ("a tag left out of the decision register's list (A47)", DOC,
     "Collects A01, A02, A13, A14, A16, A19, A22, A23, A26, A27, A28, A40, A41, A45",
     "Collects A01, A02, A13, A14, A16, A19, A22, A23, A26, A27, A28, A40, A45",
     "A47 collects exactly"),
    ("a gaps-table section dropped from T54", PLAN,
     "from Sections 7.3, 7.5, 8.1, 8.4, 8.5, 9.1, 9.2, 10.1, 10.4, 12, 13.4 and 16.2 once",
     "from Sections 7.3, 7.5, 8.1, 8.4, 8.5, 9.1, 9.2, 10.4, 12, 13.4 and 16.2 once",
     "T54 names every section"),
    ("M1's earlier exception restored in 21.2", PLAN,
     "| M0; the G0.5 recovery device steps (proposed, Section 21.1) [M0-A46] |",
     "| M0; exits after the G0.5 recovery device steps (proposed, Section 21.1) [M0-A46] |",
     "the milestone gating rule"),
    ("Appendix D's A46 summary without M1", PLAN,
     "each milestone, M1 included, starts after its gates' device steps",
     "each milestone starts after its gates' device steps",
     "the milestone gating rule"),
    ("the narrower uncertain-5xx list restored in 14.4", PLAN,
     "Treat every other 5xx (a 500, 502 or 504 among them), and any 5xx",
     "Treat a 500, 502 or 504, and any 5xx",
     "replaced phrases are absent"),
    ("the EPUB-folder narrowing labelled a clarification", DOC,
     "| scope narrowing | A53 |",
     "| clarification | A53 |",
     "every Section 1.2 tag has a Section 2 row classified scope narrowing"),
]


def run_checker():
    result = subprocess.run([sys.executable, "-I", CHECKER], cwd=ROOT, capture_output=True, text=True)
    return result.returncode, result.stdout.splitlines()


def main():
    status, lines = run_checker()
    failing = [line for line in lines if line.startswith("FAIL ")]
    print("control (no mutation): exit %d, %d failed checks" % (status, len(failing)))
    if status != 0 or failing:
        print("the unmutated files must pass first")
        return 1
    missed = 0
    for name, path, old, new, expected in MUTATIONS:
        target = ROOT / path
        original = target.read_text(encoding="utf-8")
        if original.count(old) != 1:
            print("MISSED %s: the text to replace occurs %d times in %s" % (name, original.count(old), path))
            missed += 1
            continue
        try:
            target.write_text(original.replace(old, new, 1), encoding="utf-8")
            status, lines = run_checker()
        finally:
            target.write_text(original, encoding="utf-8")
        failing = [line[5:] for line in lines if line.startswith("FAIL ")]
        caught = status == 1 and any(line.startswith(expected) for line in failing)
        if not caught:
            missed += 1
        print("%s %s: exit %d; failed: %s" % ("caught" if caught else "MISSED", name, status,
                                             " | ".join(line.split(":")[0] for line in failing) or "nothing"))
    print("summary: %d mutations, %d caught, %d missed" % (len(MUTATIONS), len(MUTATIONS) - missed, missed))
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
