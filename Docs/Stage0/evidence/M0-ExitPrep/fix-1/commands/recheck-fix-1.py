#!/usr/bin/env python3
"""Recheck of the fix of the review of the M0 exit preparation (26 October 2026; integration log section 31): each
finding the workflow relayed from that review, which read `m0-exit-prep` at 609ed492, answered where the fix says it
is, and the review's status given wherever the records give the exit preparation's.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands/recheck-fix-1.py <tree>

<tree> is a repository root or an extracted tree (git archive). One line per group:
  F1  SEC-ZIPGUARD-01, the guard: the check's rule for a product manifest's local package inside the product roots,
      its docstring, the self-test's five mutations and its allowed change, and the reproductions' verdicts (every
      route as expected, read in fix-1/reproductions.log);
  F2  SEC-ZIPGUARD-01, the records: ADR-0014's rule 5, section 3, self-test counts, status, evidence, consequence and
      open item, the ADR index's row, the gate summary's row 76, Sections 1, 2.10 and 6.1, item 4, the Branch line,
      item 111 and its checker's row 76, the integration log's section 31, and the Stage 0 README;
  F3  SEC-ZIPGUARD-02: item 22's counts in the past tense, and row 76's and item 105's, which gave 278 in the present
      tense too, with item 112;
  R   the review's status: the State line (within 200 words), Section 6.2's row for the review, placed before the
      hand-over's row, which stays the table's last, and its paragraph, items 109 and 113, Section 7's item 5, Section
      8's bullets and its Written by line, the integration log's 30.6, and the runbook's Who wrote it.
Most checks are an anchor with the start of the dated note that must follow it at once, so that a note in the wrong
place fails; a text that must be gone is checked as gone. On HEAD every group must pass; on the tree of 609ed492, the
reviewed commit, which the gate checks beside this file run as its control, every group must be reported. The checks
read files only and do not judge the notes' wording beyond the texts given here. Standard library only; read-only.
Exits 1 if any group is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
CHECK = "Scripts/check-dependency-lock.py"
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
README = "Docs/Stage0/README.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
INDEX = "Docs/ADRs/README.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
CHECKER = "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
REPRO = "Docs/Stage0/evidence/M0-ExitPrep/fix-1/reproductions.log"
CACHE = {}


def read(rel):
    if rel not in CACHE:
        p = ROOT / rel
        CACHE[rel] = p.read_text(encoding="utf-8") if p.exists() else ""
    return CACHE[rel]


problems = 0


def group(name, checks, what):
    """checks: (file, text) pairs that must stand; (file, anchor, note start) triples that must stand together;
    ('gone', file, text) triples that must not stand; and (label, bool) pairs computed below."""
    global problems
    missing = []
    for c in checks:
        if c[0] == "gone":
            _, f, text = c
            if text in read(f):
                missing.append(f"{f} still has: {text[:90]}")
        elif isinstance(c[1], bool):
            if not c[1]:
                missing.append(c[0])
        elif len(c) == 2:
            f, text = c
            if text not in read(f):
                missing.append(f"{f} lacks: {text[:90]}")
        else:
            f, anchor, note = c
            if anchor + note not in read(f):
                missing.append(f"{f}: {('anchor missing: ' + anchor[:70]) if anchor not in read(f) else ('no note after: ' + anchor[-70:])}")
    if missing:
        problems += 1
        print(f"PROBLEM  {name}: {what} ({len(missing)} of {len(checks)} not as stated; first: {missing[0]})")
    else:
        print(f"ok       {name}: {what} ({len(checks)} texts)")


# F1: the guard, and the reproductions' verdicts.
repro = read(REPRO)
routes = re.findall(r"^--- route (\d+): (.*): (ok \(|UNEXPECTED)", repro, re.M)
group("F1", [
    (CHECK, "            elif self.tracked_file(os.path.join(local['path'], 'Package.swift')) is None:\n"),
    (CHECK, "whose Package.swift is not a file git tracks: a local package inside {' or '.join(product_roots)} must be "
            "one git tracks there"),
    (CHECK, "package inside them must be one git tracks there, its Package.swift a tracked file, which the check"),
    (CHECK, "(\"SEC-ZIPGUARD-01 (b00): a product project depends on a local package in a package's checkouts under .build"),
    (CHECK, "('SEC-ZIPGUARD-01 (b02): a product Package.swift depends on a local package under its own .build'"),
    (CHECK, "('SEC-ZIPGUARD-01 (b03): a product Package.swift depends on a directory under Packages/ that holds only "
            "build products'"),
    (CHECK, "(\"SEC-ZIPGUARD-01: XcodeGen's localPackages list names a package checkout under .build\""),
    (CHECK, "('SEC-ZIPGUARD-01: a local package path names a tracked directory under Apps/ that holds no Package.swift"),
    (CHECK, "('a product package depends on another product package by a path inside the product roots, whose "
            "Package.swift git tracks'"),
    ("the reproductions log has seven routes, each ok", len(routes) == 7 and all(v == "ok (" for _, _, v in routes)),
    (REPRO, "  the unplanted copy, check after the fix: exit 0 -> dependency lock check: 0 failure(s), 0 warning(s)\n"),
    (REPRO, "\nresult: every route as expected\n"),
], "the rule for a local package inside the product roots, its docstring, five mutations and an allowed change, and "
   "the reproductions' seven routes as expected")

# F2: the records of SEC-ZIPGUARD-01.
FIX_NOTE = " *(26 October 2026: the review of the M0 exit preparation"
group("F2", [
    (A14, "*(Since 26 October 2026, the review of the M0 exit preparation, SEC-ZIPGUARD-01:)* a local package a product "
          "manifest depends on inside them must be a package git tracks there, its `Package.swift` a tracked file"),
    (A14, "Or a product manifest depends on a local package inside the product roots whose `Package.swift` git does not "
          "track"),
    (A14, "- 283 mutated copies, each of which must be reported with its own category and message (278 until 26 October "
          "2026"),
    (A14, "- 36 allowed changes (35 until 26 October 2026"),
    (A14, "every one of the check's 120 failure branches (119 until 26 October 2026,"),
    (A14, "**Amended on 26 October 2026 (25 October UTC) by an agent, at the fix of that review, on `m0-exit-prep`: a "
          "local package inside the product roots must be one git tracks there"),
    (A14, "- The fix of the review of the M0 exit preparation (26 October 2026, SEC-ZIPGUARD-01), in "
          "`Docs/Stage0/evidence/M0-ExitPrep/fix-1/`"),
    (A14, "Nor can a product manifest depend on a local package under the product roots that git does not track"),
    (A14, "the sign-off stays pending, with the device sessions it rests on.)*",
     " *(26 October 2026: the review of the M0 exit preparation found one more route of the same kind"),
    (INDEX, "Its header gained a line pointing to the deps item's review record, the same day; agent-written, not "
            "reviewed.)*", " *(26 October 2026: the review of the M0 exit preparation read that change, at `609ed492`"),
    (GATE, "The drop-in passed again on the assembly of the M0 exit preparation, "
           "`evidence/M0-ExitPrep/assembly/12-dependency-lock.log`.)*",
     FIX_NOTE + ", at `609ed492`, found one more route of the same kind"),
    (GATE, "and the drop-in passes from a clean tree with a self-test of 283 mutations "
           "(`evidence/M0-ExitPrep/fix-1/12-dependency-lock.log`)"),
    (GATE, "111. **A local package that git does not track** (SEC-ZIPGUARD-01, major)"),
    (GATE, "which Readium 3.11.0 depends on, out of product code. *(24 October 2026: both closed by that change, "
           "reviewed next.)*", FIX_NOTE + " read that change, at `609ed492`"),
    (GATE, "on the assembly's last documents commit (`evidence/M0-ExitPrep/assembly/`).)*",
     " *(26 October 2026: and on the last documents commit of the fix of that preparation's review"),
    (GATE, "no other code, script, contract, fixture or workflow: integration log section 30.)*",
     " *(26 October 2026: the fix of the review of the M0 exit preparation, on `m0-exit-prep`, changed "
     "`Scripts/check-dependency-lock.py` again"),
    (GATE, "ADR-0014 status and section 3; `evidence/M0-ExitPrep/zipguard/`.)*",
     " *(26 October 2026: that review read it at `609ed492` and found one more route of the same kind"),
    (GATE, "it approves nothing, and the exit still waits for the device sessions.",
     " *(26 October 2026: an agent review read it at `609ed492` and raised two findings"),
    (CHECKER, '+ adr_says(14, "a local package inside the product roots must be one git tracks there")'),
    (CHECKER, '"self-test: 283 mutations")'),
    (LOG, "## 31. The review of the M0 exit preparation, and its fix (26 October 2026)"),
    (LOG, "### 31.1 The findings, and what was done"), (LOG, "### 31.2 What this fix left as it was"),
    (LOG, "### 31.3 Commits"), (LOG, "### 31.4 Checks"), (LOG, "### 31.5 Not done here, and why"),
    (README, "and named `CLAUDE.md`'s paragraph as the product owner's to correct.)",
     " *(26 October 2026: an agent review read the M0 exit preparation at `609ed492` and raised two findings"),
    (README, "at the M0 exit preparation, sections 28-30, and on 26 October 2026 by the fix of that preparation's "
             "review, section 31)*"),
], "ADR-0014 (rule 5, section 3, counts, status, evidence, consequence, open item), the ADR index, the gate summary "
   "(row 76, item 111, Sections 1, 2.10 and 6.1, item 4, the Branch line), its checker, integration log section 31, "
   "the Stage 0 README")

# F3: SEC-ZIPGUARD-02.
group("F3", [
    (GATE, "its self-test then had 239 mutations (228 before), each new rule's among them, and reached all 111 of its "
           "failure branches *(26 October 2026: until the review of the M0 exit preparation, SEC-ZIPGUARD-02,"),
    ("gone", GATE, "its self-test has 239 mutations (228 before), each new rule's among them, and reaches all 111"),
    (GATE, "its self-test then planted each one (278 mutations; 283 since the fix of the exit preparation's review, item "
           "111)"),
    ("gone", GATE, "its self-test plants each one (278 mutations)"),
    (GATE, "passed from a clean tree with a self-test that planted each route (278 mutations then)"),
    ("gone", GATE, "passes from a clean tree with a self-test that plants each route (278 mutations)"),
    (GATE, "112. **Item 22's counts** (SEC-ZIPGUARD-02)"),
], "item 22, row 76 and item 105 give the earlier counts in the past tense; item 112")

# R: the review's status.
gate = read(GATE)
state = next((line for line in gate.splitlines() if line.startswith("- **State:**")), "")
words = len(state.split())
review_row = gate.find("| The review of the M0 exit preparation (26 October 2026, at `609ed492`, the assembly's last commit) |")
handover_row = gate.find("| The thirteen M0 items' own final reviews |")
section62 = gate[gate.find("### 6.2 Minor findings"):gate.find("### 6.3 ")]
rows = [line for line in section62.splitlines() if line.startswith("| ")]
group("R", [
    (GATE, "have not been reviewed, nor has the fix of the review of the M0 exit preparation (Sections 6.2 and 8)."),
    ("gone", GATE, "nor has the M0 exit preparation of 24 October 2026 (Sections 6.2 and 8)."),
    (f"the State line has {words} words (at most 200)", 0 < words <= 200),
    ("Section 6.2's row for the review stands before the hand-over's row",
     0 <= review_row < handover_row),
    ("the hand-over's row stays Section 6.2's last row",
     bool(rows) and rows[-1].startswith("| The thirteen M0 items' own final reviews |")),
    (GATE, "which no review has read yet: Section 8.)*",
     " *(26 October 2026: an agent review has read it since, at `609ed492`"),
    (GATE, "and the assembly's in `evidence/M0-ExitPrep/assembly/` (integration log section 30).",
     " *(Dated note, 26 October 2026: reviewed by an agent, at `609ed492`, items 111-113.)*"),
    (GATE, "113. **Not reviewed**: this fix is agent-written; its checks, on its last commits, are in "
           "`evidence/M0-ExitPrep/fix-1/` (integration log section 31.4)."),
    (GATE, "items 104-110; Section 8), and the fix of its review (items 111-113), and the Git LFS fixes"),
    (GATE, "in `evidence/M0-dependencies/xcode-27.1/`. Not reviewed.",
     " *(26 October 2026: read with the assembly by the review of the M0 exit preparation, at `609ed492`"),
    (GATE, "with a pointer line in each gate report and item record. Agent-written; not reviewed.",
     " *(26 October 2026: the review of the M0 exit preparation read `609ed492`, which holds it"),
    (GATE, "`evidence/M0-ExitPrep/assembly/gate-checks-round-3-compare.log`); not reviewed.",
     " *(26 October 2026: reviewed by an agent at `609ed492`, its last commit: the next bullet.)*"),
    (GATE, "- **The fix of the review of the M0 exit preparation (26 October 2026; integration log section 31).**"),
    (GATE, "nor has the M0 exit preparation of 24 October 2026 (sections 28-30)",
     " *(26 October 2026: an agent review read it at `609ed492`; the fix of that review, section 31, has had none)*"),
    (LOG, "stays on the record until that review says whether R4-01 and R4-02 are answered.",
     " *(Dated note, 26 October 2026: an agent review read `m0-exit-prep` at `609ed492`"),
    (RUNBOOK, "nor have the notes of the M0 exit preparation; human review pending.",
     " *(26 October 2026: an agent review read the M0 exit preparation at `609ed492`"),
], "the State line, Section 6.2 (the review's row and paragraph), items 109 and 113, Section 7's item 5, Section 8, "
   "integration log 30.6 and the runbook's Who wrote it")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 4 groups not as stated)")
sys.exit(1 if problems else 0)
