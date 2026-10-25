#!/usr/bin/env python3
"""Recheck of the fix of the second review of the M0 exit preparation (26 October 2026; integration log section 32):
each finding the workflow relayed from that review, which read m0-exit-prep at 83030fba, answered where the fix says
it is, and the review's status given wherever the records gave the fix of the first review as not reviewed.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/recheck-ev.py <tree>

<tree> is a repository root or an extracted tree (git archive). One line per group:
  E1  EV-01 (major): the deps item's two notes dated in item-reviews.py and rendered in deps.md, the old present-tense
      texts gone; the check's part 7 checking the records' three statements on the repository as it is now; the
      README's account of the final-round IDs and its bullet on R4-01 and R4-02, integration log 29.2 and 30.3, each
      with its dated note; the README's part 7 described; the gate summary's item 114;
  E2  EV-02: the gate summary's note on the final-review records (item 4) and integration log 29.2, each with a dated
      note on the reason the records give for the 25 findings no later record names; item 115;
  E3  EV-03: the README's pointer to the check log's part 7 for R8-04, part 6 gone; item 116;
  E4  EV-04: the README's note on where the records' commits are kept, citing branch-reach.log; the check's parts 4-6
      reading a branch with check=False and part 5's old call gone; the gate summary's Section 5.4 item and item 117;
  R   the review's status: the State line (within 200 words), Section 6.2 (the first review's row, a row for the
      second before the hand-over's row, which stays the table's last, and the paragraph after the table), the notes
      after each text that gave the first fix as not reviewed (the gate summary's item 4, Section 1, row 76, Section
      6.1, items 109 and 113, Section 7's item 5, Section 8; ADR-0014, the ADR index, the Stage 0 README, the runbook,
      integration log 29, 31 and 31.5, and four evidence READMEs), item 118, Section 8's bullet for this fix, and
      integration log section 32.
Most checks are an anchor with the start of the dated note that must follow it at once, so that a note in the wrong
place fails; a text that must be gone is checked as gone. On HEAD every group must pass; on the tree of 83030fba, the
reviewed commit, which the gate checks beside this file run as its control, every group must be reported. The checks
read files only and do not judge the notes' wording beyond the texts given here. Standard library only; read-only.
Exits 1 if any group is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
README = "Docs/Stage0/README.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
INDEX = "Docs/ADRs/README.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
ITEMS = "Docs/Stage0/evidence/M0-Integration/item-reviews"
SCRIPT = f"{ITEMS}/commands/item-reviews.py"
DEPS = f"{ITEMS}/deps.md"
IREADME = f"{ITEMS}/README.md"
REVIEWS = "Docs/Stage0/evidence/M0-ExitPrep/reviews/README.md"
FIX1 = "Docs/Stage0/evidence/M0-ExitPrep/fix-1/README.md"
ASM = "Docs/Stage0/evidence/M0-ExitPrep/assembly/README.md"
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


def section(text, start, end):
    i = text.find(start)
    if i < 0:
        return ""
    j = text.find(end, i + len(start))
    return text[i:j if j >= 0 else len(text)]


EV = "the second review of the M0 exit preparation"

# E1: EV-01, the deps item's record on ADR-0014 and the texts gone stale with it.
group("E1", [
    (DEPS, "A parallel agent's task of 24 October 2026 was to close them, on a branch of its own; its outcome is not "
           "part of this record.", " *(Dated note, 26 October 2026: that agent closed both in the guard on "
                                   "`m0-exit-zipguard` (`6cd842d3`)"),
    (DEPS, "The final round's minor findings R4-03 to R4-07 were not in ADR-0014, which named R4-01 and R4-02 only "
           "(searched by ID on `m0-exit-reviews`, where this record was made).",
     " *(Dated note, 26 October 2026: until `6cd842d3`, the fix of R4-01 and R4-02 on `m0-exit-zipguard`"),
    (DEPS, "since then it gives all seven, R4-03 and R4-04 closed with that fix and R4-05 to R4-07 left open with its "
           "owner"),
    ("gone", DEPS, "are not in ADR-0014, which names R4-01 and R4-02 only"),
    ("gone", DEPS, "A parallel agent's task of 24 October 2026 is to close them"),
    (SCRIPT, 'ZIP_FIX = "6cd842d3"'),
    (SCRIPT, "report(bool(before) and not named_before and since and named == R4_MINOR"),
    (SCRIPT, "report(said == (still, still),"),
    (SCRIPT, "report(said_root == under,"),
    ("gone", SCRIPT, "print(f\"note    deps: of the final round's minor findings R4-03 to R4-07, ADR-0014 names \""),
    (IREADME, "the others appear only where those documents cite other reviews' findings under the same IDs (the gates' "
              "own review rounds, the M0 final review).",
     " *(Dated note, 26 October 2026: so it was on `m0-exit-reviews`, where this was written."),
    (IREADME, "A parallel agent's task of 24 October 2026 was to close them, on a branch of its own; that work is not "
              "part of this record.", " *(Dated note, 26 October 2026: that agent closed both in the guard"),
    ("gone", IREADME, "A parallel agent's task of 24 October 2026 is to close them"),
    (IREADME, "7. **What stayed open**, item by item, as the Markdown records give it.",
     " *(Since 26 October 2026 it also checks the three statements of these records that rest on the repository"),
    (LOG, "(one of the 25 major: the contracts item's L2-03).",
     " *(Dated note, 26 October 2026: two clauses of this bullet hold only in part"),
    (LOG, "\"None of which but those two was written into any report\" held at the merge and on `m0-exit-reviews`; on "
          "`m0-exit-prep`, since the Zip guard's fix (section 28), ADR-0014 also gives the deps item's R4-03 to R4-07."),
    (LOG, "The item-reviews README's line on that pointer has a dated note.",
     " *(Dated note, 26 October 2026: the deps item's record, whose note said the same"),
    (GATE, "114. **The deps item's record on ADR-0014** (EV-01, major)"),
], "the deps item's notes dated and rendered, the check's part 7 checking the records' statements, the README, "
   "integration log 29.2 and 30.3, and item 114")

# E2: EV-02, the reason given for the 25 findings no later record names.
group("E2", [
    (GATE, "Agent-written, not reviewed; whether later work answered the open findings was not checked.)*",
     " *(Dated note, 26 October 2026: the records give that reason for the contracts item's 19 alone"),
    (GATE, "for the amendments item's six, review-2b's L2-12 to L2-17, they record only that the round-3 reviews' "
           "briefs were cut off at R2-06, not whether fix-2, which names none of them, received them."),
    (LOG, "And the records give the cut-off lists as the reason for the contracts item's 19 of the 25 alone"),
    (LOG, "Nor does the reason reach the five left unresolved:"),
    (GATE, "115. **The reason given for the 25 findings no later record names** (EV-02)"),
], "item 4's note on the final-review records and integration log 29.2, each with its dated note, and item 115")

# E3: EV-03, the check log's part for R8-04.
group("E3", [
    (IREADME, "The command is still there (the check log's part 7, as a note until 26 October 2026 and since then as a "
              "check; until then this said part 6"),
    ("gone", IREADME, "(the check log's part 6 notes it)"),
    (GATE, "116. **The check log's part for R8-04** (EV-03)"),
], "the README's pointer to part 7, and item 116")

# E4: EV-04, where the records' commits are kept.
script = read(SCRIPT)
part5 = section(script, "== 5. The merge", "== 6. ")
part6 = section(script, "== 6. What the integration log", "== 7. ")
call = 'head = git("rev-parse", "--verify", "--quiet", f"refs/heads/{it.branch}", check=False).stdout.strip()'
s54 = section(read(GATE), "### 5.4 ", "## 6. ")
group("E4", [
    (IREADME, "on the item's branch, which still exists here",
     " *(dated note, 26 October 2026: here is the build Mac's repository alone."),
    (IREADME, "(`Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/branch-reach.log`)"),
    (IREADME, "Keeping the branches, pushing them or tagging those commits before `m0-exit-prep` reaches `main` is the "
              "product owner's to decide"),
    ("parts 5 and 6 read the branch with check=False", call in part5 and call in part6),
    ("gone", SCRIPT, 'head = git("rev-parse", f"refs/heads/{it.branch}").stdout.strip()'),
    ("Section 5.4 has the owner's choice on the m0-int-* branches",
     "where the review records' commits are kept.**" in s54 and "Keep the branches, push them, or tag those commits"
     in s54),
    (GATE, "117. **Where the review records' commits are kept** (EV-04)"),
    ("Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/branch-reach.py", 'git("for-each-ref", "--contains", '
                                                                                 'full'),
], "the README's note on the local m0-int-* branches, the check's parts 5 and 6, Section 5.4 and item 117")

# R: the review's status.
gate = read(GATE)
state = next((line for line in gate.splitlines() if line.startswith("- **State:**")), "")
words = len(state.split())
s62 = section(gate, "### 6.2 Minor findings", "### 6.3 ")
rows = [line for line in s62.splitlines() if line.startswith("| ")]
first = next((i for i, r in enumerate(rows) if r.startswith("| The review of the M0 exit preparation (26 October 2026, "
                                                             "at `609ed492`")), -1)
second = next((i for i, r in enumerate(rows) if r.startswith("| The second review of the M0 exit preparation (26 October "
                                                              "2026, at `83030fba`")), -1)
handover = next((i for i, r in enumerate(rows) if r.startswith("| The thirteen M0 items' own final reviews |")), -1)
group("R", [
    (GATE, "have not been reviewed, nor has the fix of the second review of the M0 exit preparation (Sections 6.2 and "
           "8)."),
    ("gone", GATE, "nor has the fix of the review of the M0 exit preparation (Sections 6.2 and 8)."),
    (f"the State line has {words} words (at most 200)", 0 < words <= 200),
    ("Section 6.2: the first review's row, then the second's, then the hand-over's, the table's last",
     0 <= first < second < handover == len(rows) - 1),
    (GATE, "both (Section 6.3, items 111-113); that answer read by a second agent review the same day, at `83030fba` "
           "(next row; until the fix of that review this cell said not reviewed) | integration log section 31 |"),
    (GATE, "answered on 26 October 2026 by the fix of that review, all four (Section 6.3, items 114-118); not reviewed "
           "| integration log section 32 |"),
    (GATE, "that fix has not been reviewed.)*", " *(26 October 2026: a second agent review has read the branch since, at "
                                              "`83030fba`"),
    (GATE, "what remains yours is the same: Section 6.3, item 111.)*",
     " *(26 October 2026: a second agent review read the branch at `83030fba`, with that fix;"),
    (GATE, "which the fix of that review closes, not reviewed: Section 6.3, items 111-113.)*",
     " *(26 October 2026: a second agent review read it at `83030fba`, with that fix,"),
    (GATE, "integration log section 31, Section 6.3, item 111.)*",
     " *(26 October 2026: a second agent review read the branch at `83030fba`, with that change;"),
    (GATE, "which the fix of that review closes the same day, not reviewed: Section 6.3, item 111.)*",
     " *(26 October 2026: a second agent review read that fix at `83030fba`;"),
    (GATE, "*(Dated note, 26 October 2026: reviewed by an agent, at `609ed492`, items 111-113.)*",
     " *(Dated note, 26 October 2026: and again, with the fix of that review, at `83030fba`: items 114-118.)*"),
    (GATE, "it is for ADR-0014's owner and the next review (integration log 31.5).",
     " *(26 October 2026: a second agent review read this fix at `83030fba`;"),
    (GATE, "118. **Not reviewed**: this fix is agent-written; its checks, on its last commits, are in "
           "`evidence/M0-ExitPrep/fix-1/round-2/` (integration log section 32.4)."),
    (GATE, "and the Git LFS fixes (Section 5.3)",
     " *(26 October 2026: and the fix of the second review of the M0 exit preparation, items 114-118)*"),
    (GATE, "`evidence/M0-ExitPrep/fix-1/commands/gate-checks.sh`); not reviewed.",
     " *(26 October 2026: read by the second review of the M0 exit preparation, at `83030fba`"),
    (GATE, "- **The fix of the second review of the M0 exit preparation (26 October 2026; integration log section "
           "32).**"),
    (GATE, "the bullet on the fix of that review, below.)*", " *(26 October 2026: the second review of the M0 exit "
                                                            "preparation, at `83030fba`, raised its four findings"),
    (GATE, "`12-dependency-lock` ran again: integration log section 31.)*",
     " *(26 October 2026: the fix of the second review of the M0 exit preparation, on `m0-exit-prep`, changed nothing "
     "outside `Docs/`: integration log section 32.)*"),
    (GATE, "the fix of that review, section 31, has had none)*",
     " *(26 October 2026: a second read the branch at `83030fba`, that fix with it; the fix of the second, section 32, "
     "has had none)*"),
    (A14, "It approves nothing; agent-written, not reviewed.",
     " *(26 October 2026: a second agent review of the M0 exit preparation read the branch at `83030fba`"),
    (INDEX, "an agent's fix of that review closes it in the guard, not reviewed: ADR-0014 status.)*",
     " *(26 October 2026: a second agent review read that fix at `83030fba`"),
    (README, "that fix has not been reviewed.)*", " *(26 October 2026: a second agent review read the branch at "
                                                 "`83030fba`, with that fix,"),
    (RUNBOOK, "has not been reviewed: integration log section 31.)*",
     " *(26 October 2026: a second agent review read the branch at `83030fba`;"),
    (LOG, "and its checks' README (`evidence/M0-ExitPrep/reviews/README.md`). Agent-written, not reviewed; human "
          "sign-off pending.", " *(Dated note, 26 October 2026: read since by both agent reviews of the M0 exit "
                               "preparation"),
    (LOG, "- **Review:** none; human sign-off pending.",
     " *(Dated note, 26 October 2026: both agent reviews of the M0 exit preparation read it since"),
    (LOG, "from `609ed492`; agent-written, not reviewed, human sign-off pending.",
     " *(Dated note, 26 October 2026: read by a second agent review the same day, at `83030fba`: 31.5 and section 32.)*"),
    (LOG, "until a review says whether R4-01 and R4-02 are answered; human sign-off pending.",
     " *(Dated note, 26 October 2026: an agent review read it the same day, at `83030fba`"),
    (LOG, "## 32. The second review of the M0 exit preparation, and its fix (26 October 2026)"),
    (LOG, "### 32.1 The findings, and what was done"), (LOG, "### 32.2 What this fix left as it was"),
    (LOG, "### 32.3 Commits"), (LOG, "### 32.4 Checks"), (LOG, "### 32.5 Not done here, and why"),
    (FIX1, "**It is agent-written and not reviewed.**",
     " *(Dated note, 26 October 2026: read since by a second agent review of the M0 exit preparation, at `83030fba`"),
    (FIX1, "this fix has not been reviewed.", " *(Dated note, 26 October 2026: read by the second review, at `83030fba`"),
    (ASM, "(integration log section 31).)*", " *(Dated note, 26 October 2026: a second agent review read the branch at "
                                            "`83030fba`"),
    (IREADME, "this hand-over is agent-written and not reviewed; human sign-off pending.",
     " *(Dated note, 26 October 2026: since read by two agent reviews of the M0 exit preparation"),
    (REVIEWS, "Agent-written; not reviewed; human sign-off pending.",
     " *(Dated note, 26 October 2026: since read by two agent reviews of the M0 exit preparation"),
], "the State line, Section 6.2, the notes after each text that gave the first fix as not reviewed, item 118, Section "
   "8's bullet for this fix, and integration log section 32")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 5 groups not as stated)")
sys.exit(1 if problems else 0)
