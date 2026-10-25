#!/usr/bin/env python3
"""Recheck of the fix of the fifth review of the M0 exit preparation (26 October 2026; integration log section 35):
each finding the workflow relayed from that review, which read m0-exit-prep at 941ac9a2, answered where the fix says it
is, the review's status given wherever the records gave the fix of the fourth review as not reviewed, and a sweep of the
records for any text left in the phrasings the findings name.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/round-2/commands/recheck-hon-ep.py <tree>

<tree> is a repository root or an extracted tree (git archive). One line per group:
  B  HON-EP-06 (major): what `m0-decisions` holds since 25 October 2026, given where the records said that it and `main`
     have the same tree, that it is behind `main`, or that no device step has run: the gate summary (the State line and
     the opening reworded, item 1's step 1, item 2, the drop-in run, the paragraph on the gates' criteria, Section 2's
     opening, Sections 5.1, 5.4 and 7, item 104, item 127), the Stage 0 README, the runbook (its header and 0.3's step 1),
     the session log's note, and integration log 30.3, 30.5, 30.6 and 31.4-34.4; CLAUDE.md unchanged, its reason listed
     in Section 5.4 (the branch itself is read by decisions-branch.py beside this file, which the gate checks run as
     their part 1g);
  Z  HON-EP-07: SEC-ZIPGUARD-01 answered, review pending, in the five texts that called it closed, each old text gone;
     item 105's note; integration log 28 and 28.4's notes; item 128;
  M  HON-EP-08: ADR-0014's status line and open item and the Zip guard's evidence README no longer place `5aec2518` on
     `main`, each old text gone; item 129;
  R  the review's status: the State line (within 200 words) and Section 6.2 (the fourth review's row, a row for the
     fifth before the hand-over's row, which stays the table's last, and the paragraph after the table); the notes after
     each text that gave the fourth fix as not reviewed (items 109, 113, 118, 124 and 126, Section 7's item 5, Section
     8's bullets, Branch and Written by lines; ADR-0014, the ADR index, the Stage 0 README, the runbook, integration log
     30.6, 31.5, 32-34, and the evidence READMEs); item 130 and integration log section 35;
  S  the sweep: every Markdown file under Docs/, README.md and CLAUDE.md, each line read whole: a text in the phrasings
     of PHRASES (the two branches' trees, `m0-decisions` behind `main`, no device step run, the first fix's route
     closed, a review reading the change next, `5aec2518` on `main`) must have a marker of this fix (its finding IDs,
     items 127-130, section 35) or a history clause ("until ... said") in its context, the sentence that holds it with
     the notes "*( ... )*" inside it and the chain of notes right after it (a text inside a note: that note and the
     chain after it), or be one of ALLOWED, the texts this fix read and found to give no present state of what the
     findings name (another subject, an account of a round, a text a later note corrects), each with its reason; and each
     of ALLOWED must still be there. A text that says the same in other words can escape it.
Most checks are a text that must stand, an anchor with the start of the note that must follow it, or a text that must
be gone. On HEAD every group must pass; on the tree of 941ac9a2, the reviewed commit, which the gate checks beside this
file run as its control, every group must be reported. Standard library only; read-only; reads files only. Exits 1 if
any group is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
README = "Docs/Stage0/README.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
INDEX = "Docs/ADRs/README.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
CLAUDE = "CLAUDE.md"
EXIT = "Docs/Stage0/evidence/M0-ExitPrep"
ZIP = f"{EXIT}/zipguard/README.md"
ASM = f"{EXIT}/assembly/README.md"
FIX1 = f"{EXIT}/fix-1/README.md"
FIX2 = f"{EXIT}/fix-1/round-2/README.md"
FIX3 = f"{EXIT}/fix-1/round-3/README.md"
FIX4 = f"{EXIT}/fix-2/README.md"
HERE = f"{EXIT}/fix-2/round-2"
REVIEWS = f"{EXIT}/reviews/README.md"
IREADME = "Docs/Stage0/evidence/M0-Integration/item-reviews/README.md"
CACHE = {}


def read(rel):
    if rel not in CACHE:
        p = ROOT / rel
        CACHE[rel] = p.read_text(encoding="utf-8") if p.is_file() else ""
    return CACHE[rel]


problems = 0


def group(name, checks, what):
    """checks: (file, text) pairs that must stand; (file, anchor, note start) triples that must stand together;
    ('gone', file, text) triples that must not stand; and (label, bool) pairs."""
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


gate = read(GATE)
lines = gate.splitlines()
state = next((line for line in lines if line.startswith("- **State:**")), "")
opening = next((line for line in lines if line.startswith("**Recommendation** (Section 7)")), "")
G1 =(" *(dated note, 26 October 2026: its part 1g, which printed the refs and checked nothing, logged `m0-decisions` at "
      "`c72247a6`, its tree not `main`'s (`gate-checks.log`, line 62), while these records said that the two have the "
      "same tree; \"passed\" did not cover that part, and nothing here reported it: section 35, HON-EP-06)* | "
      "`gate-checks.log` |")

# B: HON-EP-06.
group("B", [
    ("the State line gives no device result as recorded here, pointing to those on m0-decisions",
     "no sign-off of a plan 23.3 role and no device result is recorded here (those on `m0-decisions`: Section 5.4)."
     in state),
    ("the State line no longer says that no device result is recorded yet",
     "no device result is recorded yet" not in state),
    ("the opening says that none is recorded here as run, m0-decisions holding the first",
     "None of the gates' device or human steps is recorded here as run (`m0-decisions` has recorded the first device "
     "runs since 25 October 2026 UTC, not reconciled with these records: Section 5.4)" in opening),
    ("the opening no longer says that none has run", "None of the gates' device or human steps has run," not in opening),
    (GATE, "which are to be brought into line with `CLAUDE.md` before Session 0 (Section 5.4).)*",
     " *(26 October 2026: nor is `m0-decisions` behind `main` any more, the reason `CLAUDE.md` gives: since 25 October "
     "2026, 17:12 UTC, it holds eight commits that `main` lacks, `8404f342` to `c72247a6`"),
    (GATE, "nor does 0.8's drop-in, so they call for no repeat)*",
     " *(26 October 2026: on `m0-decisions`, since 25 October 2026 UTC, also `DeviceTests` in `Spikes/G05-Recovery`, a "
     "test host for the recovery suite that step 1.2's command builds there"),
    (GATE, "so 0.8 still needs nothing from you: item 2.)*",
     " *(26 October 2026: on `m0-decisions`, since 25 October 2026 UTC, of what the drop-in builds, copies or runs only "
     "`DeviceTests` in `Spikes/G05-Recovery` is new"),
    (GATE, "and nothing run on a phone is recorded here",
     " *(26 October 2026: `m0-decisions` has recorded the first device runs since 25 October 2026 UTC, which these "
     "records have not reconciled (Section 5.4); until 26 October 2026, the fix of the fifth review of the M0 exit "
     "preparation, this sentence said \"nothing has been run on a phone\": HON-EP-06, Section 6.3, item 127)*. "),
    ("gone", GATE, "and nothing has been run on a phone. Four gates"),
    (GATE, "No row is passed on a device: no device result is recorded in the gate reports these rows cite",
     " *(26 October 2026: on this branch; `m0-decisions` has recorded the first device runs since 25 October 2026 UTC"),
    ("gone", GATE, "No row is passed on a device: no device step has run."),
    (GATE, "Nothing in it has been run on a device as these records hold it",
     " *(26 October 2026: on `m0-decisions` its Session 1 has begun since 25 October 2026 UTC, steps 1.1 to 1.3 run "
     "and 1.4's audio run started"),
    (GATE, "The code is no longer the same either way: since 25 October 2026, 17:12 UTC (06:12 on 26 October on the "
           "build Mac's clock), this repository's `m0-decisions` holds eight commits that neither `main` nor "
           "`m0-exit-prep` holds, `8404f342` to `c72247a6`"),
    (GATE, "this branch's copy of the session log keeps its first sentence, that no device step has been run, with a "
           "dated note (Section 6.3, item 127)."),
    ("gone", GATE, "The code is the same either way for now: `main` (`96bdc7e9`) and `m0-decisions` (`044ed3cf`) have "
                   "the same tree. The correction itself"),
    (GATE, "when you settle the branch, have that sentence brought into line with it too, and the reason it gives for "
           "never building on `m0-integrate` or `m0-decisions`, \"both are behind `main`\", which since 25 October 2026 "
           "holds for `m0-integrate` alone."),
    (GATE, "this item said \"The code is the same either way for now: `main` (`96bdc7e9`) and `m0-decisions` "
           "(`044ed3cf`) have the same tree.\", which held until 17:12 UTC on 25 October 2026"),
    (GATE, "not one device or human step has run as these records hold it",
     " *(26 October 2026: on `m0-decisions` the first device runs are recorded since 25 October 2026 UTC"),
    (GATE, "so which of the two the sessions build from is to be settled before Session 0: Section 5.4)*",
     " *(26 October 2026: Session 1 has begun since, on 25 October 2026 UTC, its step 1.1 built from `96bdc7e9`"),
    (GATE, "a third thing for Section 5.4 (item 122).)*",
     " *(Dated note, 26 October 2026: nor is `m0-decisions` behind `main` any more"),
    (GATE, "127. **`m0-decisions` since 25 October 2026, and these records** (HON-EP-06, major)"),
    (README, "no device result is recorded on this branch or on `main`, and every gate stays pending *(26 October 2026: "
             "`m0-decisions` has recorded the first device runs since 25 October 2026 UTC"),
    ("gone", README, "; no device step has run, so every gate stays pending."),
    (RUNBOOK, "- **Nothing in this runbook has been run on a device.**",
     " *(26 October 2026: as these records hold it; on `m0-decisions` Session 1 has begun since 25 October 2026 UTC"),
    (RUNBOOK, "are to be brought into line with it before Session 0: `M0-gate.md` Section 5.4.)*",
     " *(26 October 2026: nor is `m0-decisions` behind `main` since 25 October 2026, 17:12 UTC"),
    (SESSIONS, "Session 0: `M0-gate.md` Section 6.3, item 92.)",
     " *(Dated note, 26 October 2026: this is the copy on `m0-exit-prep`."),
    (LOG, "since `main` and `m0-decisions` have the same tree. *(Dated note, 26 October 2026: and a third beside them"),
    (LOG, "lists it with the branch question: section 33, HON-EP-04.)*",
     " *(Dated note, 26 October 2026: the two trees were the same when this assembly's gate checks read them, at 17:01 "
     "UTC on 25 October 2026"),
    (LOG, "and `m0-decisions` with the same tree", " *(dated note, 26 October 2026: as part 1g read it at 17:01 UTC on 25 "
                                               "October 2026;"),
    (LOG, "section 33, HON-EP-04.)*", " *(Dated note, 26 October 2026: and since 25 October 2026, 17:12 UTC, "
                                    "`m0-decisions` holds eight commits"),
    (f"integration log 31.4-34.4 each have the note on part 1g ({read(LOG).count(G1)} of 4)", read(LOG).count(G1) == 4),
    (CLAUDE, "Never build on `m0-integrate` or `m0-decisions`: both are behind `main`."),
], "the two branches' trees, m0-decisions behind main and the device runs, given as they hold, in the gate summary, the "
   "Stage 0 README, the runbook, the session log and the integration log; CLAUDE.md as it was")

# Z: HON-EP-07.
group("Z", [
    (GATE, "(SEC-ZIPGUARD-01), which an agent's change at the fix of that review answers, review pending (until 26 "
           "October 2026, the fix of the fifth review of the M0 exit preparation, this note said \"closes, not "
           "reviewed\": HON-EP-07, Section 6.3, item 128); what remains yours is the same: Section 6.3, item 111.)*"),
    (GATE, "one more route around the Zip guard, which an agent's change at the fix of that review answers, review "
           "pending: Section 6.3, items 111-113; until 26 October 2026"),
    (GATE, "SEC-ZIPGUARD-01 (major), which an agent's change at the fix of that review answers the same day, review "
           "pending: Section 6.3, item 111; until 26 October 2026"),
    (INDEX, "an agent's change at the fix of that review answers it in the guard, review pending: ADR-0014 status. Until "
            "26 October 2026"),
    (A14, "(SEC-ZIPGUARD-01), which an agent's change at the fix of that review answers, review pending (Status; section "
          "1, rule 5); the sign-off stays pending. Until 26 October 2026"),
    ("gone", GATE, "which the fix of that review closes, not reviewed"),
    ("gone", GATE, "which the fix of that review closes the same day, not reviewed"),
    ("gone", INDEX, "an agent's fix of that review closes it in the guard, not reviewed"),
    ("gone", A14, "which an agent's fix closes, not reviewed"),
    (GATE, "the third review of the M0 exit preparation, its finding HON-EP-01; item 119.)*",
     " *(Dated note, 26 October 2026: and \"the other routes of the same kind fail\" held for the routes that change "
     "planted"),
    (LOG, "its finding HON-EP-01; section 33.)*", " *(Dated note, 26 October 2026: \"not reviewed: an agent review reads "
                                              "it next\" held when it was written."),
    (LOG, "- **Review:** none yet; an agent review reads this change next.",
     " *(Dated note, 26 October 2026: five agent reviews have read the branch that holds it since"),
    (GATE, "128. **The first fix's route, still called closed, and two stale texts on the Zip guard** (HON-EP-07)"),
], "SEC-ZIPGUARD-01 answered, review pending, in the five texts; item 105 and integration log 28 and 28.4 noted; "
   "item 128")

# M: HON-EP-08.
group("M", [
    (A14, "**Amended on 24 October 2026 (23 October UTC) at the M0 exit preparation, on a branch of its own from "
          "`5aec2518`, the commit of `CLAUDE.md`'s correction on top of `main` (`m0-exit-zipguard`), by an agent: R4-01 "
          "and R4-02 are answered in the guard by its change, review pending**"),
    (A14, "on a branch of its own, `m0-exit-zipguard`, from `5aec2518`, the commit of `CLAUDE.md`'s correction on top of "
          "`main`, which `main` does not hold;"),
    (A14, "Until the fix of its fifth review, the same day, it said that the branch was made from `main` at `5aec2518`, "
          "which `main` does not hold: that review's finding HON-EP-08.)*"),
    (ZIP, "on branch `m0-exit-zipguard` from `5aec2518`, the commit of `CLAUDE.md`'s correction on top of `main`, by an "
          "agent."),
    ("gone", A14, "on a branch of its own from `main` at `5aec2518` (`m0-exit-zipguard`)"),
    ("gone", A14, "on a branch of its own from `main` at `5aec2518`, `m0-exit-zipguard`"),
    ("gone", ZIP, "on branch `m0-exit-zipguard` from `main` at `5aec2518`, by an agent."),
    (GATE, "129. **Where `5aec2518` was made** (HON-EP-08)"),
], "ADR-0014's status line and open item and the Zip guard's README give 5aec2518 as the correction's commit on top of "
   "main; item 129")

# R: the review's status.
words = len(state.split())
s62 = section(gate, "### 6.2 Minor findings", "### 6.3 ")
rows = [line for line in s62.splitlines() if line.startswith("| ")]


def row_index(start):
    return next((i for i, r in enumerate(rows) if r.startswith(start)), -1)


fourth = row_index("| The fourth review of the M0 exit preparation (26 October 2026, at `fcbd6c89`")
fifth = row_index("| The fifth review of the M0 exit preparation (26 October 2026, at `941ac9a2`")
handover = row_index("| The thirteen M0 items' own final reviews |")
group("R", [
    (GATE, "have not been reviewed, nor has the fix of the fifth review of the M0 exit preparation (Sections 6.2 and "
           "8)."),
    ("gone", GATE, "nor has the fix of the fourth review of the M0 exit preparation (Sections 6.2 and 8)."),
    (f"the State line has {words} words (at most 200)", 0 < words <= 200),
    ("Section 6.2: the fourth review's row, then the fifth's, then the hand-over's, the table's last",
     0 <= fourth < fifth < handover == len(rows) - 1 and fifth == fourth + 1),
    (GATE, "(Section 6.3, items 125 and 126); that answer read by a fifth agent review the same day, at `941ac9a2` (next "
           "row; until the fix of that review this cell said not reviewed) | integration log section 34 |"),
    (GATE, "answered on 26 October 2026 by the fix of that review, all three (Section 6.3, items 127-130); not reviewed | "
           "integration log section 35 |"),
    (GATE, "with the routes of the same kind it found (Section 6.3, items 125 and 126); that fix has not been reviewed.)*",
     " *(26 October 2026: a fifth agent review has read the branch since, at `941ac9a2`"),
    (GATE, "*(Dated note, 26 October 2026: and a fourth time, with the third fix, at `fcbd6c89`: items 125 and 126.)*",
     " *(Dated note, 26 October 2026: and a fifth time, with the fourth fix, at `941ac9a2`: items 127-130.)*"),
    (GATE, "by an agent's change, review pending: items 125 and 126.)*",
     " *(26 October 2026: a fifth read the branch at `941ac9a2`;"),
    (GATE, "*(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`, with the third fix: items 125 and 126.)*",
     " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`, with the fourth fix: items 127-130.)*"),
    (GATE, "which raised SEC-ZIPGUARD-03: items 125 and 126.)*",
     " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`, with the fourth fix: items 127-130.)*"),
    (GATE, "the Zip guard's fix and the hand-over's two.", " *(Dated note, 26 October 2026: read by a fifth agent review at "
                                                        "`941ac9a2`, which raised HON-EP-06 to HON-EP-08: items "
                                                        "127-130.)*"),
    (GATE, "130. **Not reviewed**: this fix is agent-written; its checks, on its last commits, are in "
           "`evidence/M0-ExitPrep/fix-2/round-2/` (integration log section 35.4)."),
    (GATE, "*(26 October 2026: and the fix of its fourth review, items 125 and 126)*",
     " *(26 October 2026: and the fix of its fifth review, items 127-130)*"),
    (GATE, "`evidence/M0-ExitPrep/fix-2/commands/gate-checks.sh`); not reviewed.",
     " *(26 October 2026: read by the fifth review of the M0 exit preparation, at `941ac9a2`"),
    (GATE, "- **The fix of the fifth review of the M0 exit preparation (26 October 2026; integration log section 35).**"),
    (GATE, "`12-dependency-lock` ran again, from a clean tree: integration log section 34.)*",
     " *(26 October 2026: the fix of the fifth review of the M0 exit preparation, on `m0-exit-prep`, changed nothing "
     "outside `Docs/`: integration log section 35."),
    (GATE, "the fix of the fourth, section 34, has had none)*",
     " *(26 October 2026: a fifth read it at `941ac9a2`, the fourth's fix with it; the fix of the fifth, section 35, "
     "has had none)*"),
    (GATE, "What remains is the same: an agent review that accepts the change, or finds more: Section 6.3, item 125.)*",
     " *(26 October 2026: a fifth agent review read the branch at `941ac9a2`;"),
    (GATE, "not reviewed: Section 6.3, items 125 and 126.)*", " *(26 October 2026: a fifth agent review read it at "
                                                          "`941ac9a2`, with the fourth fix, and raised three findings"),
    (GATE, "both stay open here: Section 6.3, item 125.)*", " *(26 October 2026: a fifth agent review read the branch at "
                                                         "`941ac9a2`;"),
    (A14, "It approves nothing; agent-written, not reviewed. *(26 October 2026: a fifth agent review of the M0 exit "
          "preparation read the branch at `941ac9a2`"),
    (INDEX, "review pending: ADR-0014 status.)* *(26 October 2026: a fifth read the branch at `941ac9a2`;"),
    (README, "*(26 October 2026: a fifth agent review read the branch at `941ac9a2`, with the fourth fix, and raised "
             "three findings, one of them major"),
    (RUNBOOK, "has not been reviewed: integration log section 34.)*",
     " *(26 October 2026: a fifth agent review read the branch at `941ac9a2`;"),
    (LOG, "it did not relay that it accepts the change either: section 34.)*",
     " *(Dated note, 26 October 2026: a fifth read it at `941ac9a2`"),
    (LOG, "which named the route of the bullet before this one: section 34.)*",
     " *(Dated note, 26 October 2026: and a fifth, at `941ac9a2`"),
    (LOG, "*(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`: section 34.)*",
     " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`: section 35.)*"),
    (LOG, "SEC-ZIPGUARD-03 (section 34).)*", " *(Dated note, 26 October 2026: and a fifth, at `941ac9a2`, HON-EP-06 to "
                                            "HON-EP-08 (section 35).)*"),
    (LOG, "at `fcbd6c89`: 33.5 and section 34.)*", " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`: "
                                                  "section 35.)*"),
    (LOG, "from `fcbd6c89`; agent-written, not reviewed, human sign-off pending.",
     " *(Dated note, 26 October 2026: read by a fifth agent review the same day, at `941ac9a2`: 34.5 and section 35.)*"),
    (LOG, "until a review accepts the change; human sign-off pending.",
     " *(Dated note, 26 October 2026: a fifth agent review read it the same day, at `941ac9a2`, and raised HON-EP-06 "
     "to HON-EP-08"),
    (LOG, "## 35. The fifth review of the M0 exit preparation, and its fix (26 October 2026)"),
    (LOG, "### 35.1 The findings, and what was done"), (LOG, "### 35.2 What this fix left as it was"),
    (LOG, "### 35.3 Commits"), (LOG, "### 35.4 Checks"), (LOG, "### 35.5 Not done here, and why"),
    (FIX4, "**It is agent-written and not reviewed.**", " *(Dated note, 26 October 2026: read since by a fifth agent "
                                                       "review of the M0 exit preparation, at `941ac9a2`"),
    (FIX3, "(integration log section 34); the logs here are this fix's, as they ran.)*",
     " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`"),
    (FIX2, "is in [`../../fix-2/`](../../fix-2/README.md) (integration log section 34).)*",
     " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`"),
    (FIX1, "is in [`../fix-2/`](../fix-2/README.md) (integration log section 34).)*",
     " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`"),
    (ASM, "(integration log section 34). The logs here are this assembly's, as they ran.)*",
     " *(Dated note, 26 October 2026: a fifth agent review read the branch at `941ac9a2`;"),
    (REVIEWS, "is in `../fix-2/` (integration log section 34).)*", " *(Dated note, 26 October 2026: and by a fifth, at "
                                                                 "`941ac9a2`"),
    (IREADME, "the fix of that review is not reviewed: integration log section 34.)*",
     " *(Dated note, 26 October 2026: and by a fifth, at `941ac9a2`"),
    (ZIP, "The counts below are this fix's, as it ran.)* *(Dated note, 26 October 2026: a fifth agent review read the "
          "branch at `941ac9a2`;"),
], "the State line, Section 6.2, the notes after each text that gave the fourth fix as not reviewed, item 130, Section "
   "8, integration log section 35 and the evidence READMEs")

# S: the sweep.
PHRASES = [r"same tree", r"code is the same either way", r"behind `main`", r"behind it\b", r"\bboth behind\b",
           r"[Nn]o device step has (?:been )?run", r"[Nn]othing has been run on a (?:physical )?(?:phone|device)",
           r"[Nn]othing in (?:this runbook|it) has been run on a device", r"device or human steps? has run",
           r"no device result is recorded yet", r"not one device or human step has run",
           r"fix of that review closes", r"agent's fix closes", r"closes it in the guard", r"closes, not reviewed",
           r"closes the same day", r"review reads (?:it|this change|the change) next",
           r"`main` at `5aec2518`", r"from `main`[^.;]{0,30}`5aec2518`"]
MARKERS = re.compile(r"HON-EP-0[678]|items? 12[7-9]|item 130|items 127-130|section 35")
HISTORY = re.compile(r"[Uu]ntil (?:then|[0-9]+ October 2026|the [a-z' -]+)[^.]{0,120}\b(?:said|called|gave|named|read|had)\b")
NOTE = re.compile(r"\*\((?:(?!\)\*).)*\)\*")
# The texts this fix read and found to give no present state of what the findings name, each with its reason; each
# must contain the phrase found and be found around it.
ALLOWED = [
    ("Docs/ADRs/0012-retention-backup-restore.md", "present the same tree to `BackupValidator`",
     "another subject: a backup bundle's tree"),
    ("Docs/Stage0/M0-contracts.md", "the same on every run of the same tree", "another subject: a checker's report"),
    (GATE, "G0.5 recovery's passed in a re-run in the same tree", "another subject: the CI run of 14 October 2026"),
    (GATE, "It was re-run alone in the same tree on `6371c88`", "another subject: the CI run of 14 October 2026"),
    (GATE, "G0.5 recovery's passed in a re-run in the same tree), Section 2.10", "an account of an earlier round"),
    (LOG, "made alone in the same tree after that run", "another subject: the CI run of 14 October 2026"),
    (LOG, "it was re-run alone in the same tree", "another subject: the CI run of 14 October 2026"),
    (LOG, "G0.5 recovery's in a re-run in the same tree", "an account of an earlier round"),
    ("Docs/Stage0/G01-EPUB.md", "had only \"the process exited\" behind it", "another subject"),
    (RUNBOOK, "rejecting one means changing the script behind it", "another subject: D-7's CLAUDE.md changes"),
    (GATE, "rejecting a `CLAUDE.md` change means changing the script behind it", "another subject: D-7"),
    ("Docs/Stage0/evidence/M0-Integration/item-reviews/runbook.md", "Section 9's 'checked' tool claim behind it",
     "another subject: a review finding"),
    (CLAUDE, "Never build on `m0-integrate` or `m0-decisions`: both are behind `main`.",
     "CLAUDE.md, the owner's, which no agent changes on a workflow's request; the gate summary's Section 5.4 lists its "
     "reason beside the branch question (item 127)"),
    (GATE, "and never to build on `m0-integrate` or `m0-decisions`, both behind `main`.",
     "item 104's account of the paragraph as written; its last note, dated 26 October 2026, says that this reason no "
     "longer holds for `m0-decisions`"),
    (SESSIONS, "No device step has been run.",
     "this branch's copy of the session log, its first sentence, which m0-decisions has rewritten, left as it was so "
     "that a merge takes that line; its paragraph ends with this fix's note"),
    ("Docs/Stage0/G01-EPUB.md", "Nothing has been run on a physical device yet.",
     "G0.1 EPUB's report: no G0.1 EPUB device step has run on either branch (decisions-branch.log, part 3)"),
    (LOG, "Agent-written and agent-checked; not reviewed: an agent review reads it next.",
     "section 28's opening as written; its last note, dated 26 October 2026, gives the five reviews since (HON-EP-07)"),
    (GATE, "the reason it gives for never building on `m0-integrate` or `m0-decisions`, \"both are behind `main`\", which "
           "since 25 October 2026 holds for `m0-integrate` alone.",
     "Section 5.4's branch question, quoting `CLAUDE.md`'s reason to say that it no longer holds for `m0-decisions`"),
]
# This fix's own account, every text of which is about the findings: the gate summary's items 127-130, integration log
# section 35 and this fix's evidence README.
OWN_ITEMS = re.compile(r"^(?:12[7-9]|130)\. ")
rx = re.compile("|".join(PHRASES))


def context(line, start, end):
    """(own, chain): the sentence that holds [start, end), with the notes inside it, and the same with the chain of
    notes right after it; for a text inside a note, that note, and that note with the chain of notes after it."""
    notes = [(m.start(), m.end()) for m in NOTE.finditer(line)]
    inside = next(((a, b) for a, b in notes if a <= start and end <= b), None)
    if inside:
        a, b = inside
    else:
        masked = list(line)
        for na, nb in notes:
            masked[na:nb] = "#" * (nb - na)
        masked = "".join(masked)
        a = masked.rfind(". ", 0, start)
        a = 0 if a < 0 else a
        b = masked.find(". ", end)
        b = len(line) if b < 0 else b + 1
    own_end = b
    while True:
        nxt = next(((na, nb) for na, nb in notes if na >= b and line[b:na].strip(" .*;,)") == ""), None)
        if not nxt:
            break
        b = nxt[1]
    return line[a:own_end], line[a:b]


files = sorted((ROOT / "Docs").rglob("*.md")) + [ROOT / "README.md", ROOT / "CLAUDE.md"]
found, marked, own, listed, unlisted, used = 0, 0, 0, 0, [], set()
for f in files:
    if not f.is_file():
        continue
    rel = str(f.relative_to(ROOT))
    in35 = False
    for n, line in enumerate(f.read_text(encoding="utf-8").split("\n"), 1):
        if rel == LOG and line.startswith("## "):
            in35 = line.startswith("## 35. ")
        for m in rx.finditer(line):
            found += 1
            if (rel == GATE and OWN_ITEMS.match(line)) or (rel == LOG and in35) or rel == f"{HERE}/README.md":
                own += 1
                continue
            own_text, chain = context(line, m.start(), m.end())
            if MARKERS.search(chain) or HISTORY.search(own_text):
                marked += 1
                continue
            hit = [i for i, (af, text, _) in enumerate(ALLOWED) if af == rel and m.group(0) in text
                   and text in line[max(0, m.start() - len(text)):m.end() + len(text)]]
            if hit:
                listed += 1
                used.update(hit)
            else:
                unlisted.append(f"{rel}:{n}: {line[max(0, m.start() - 60):m.end() + 40]}")
stale = [f"{ALLOWED[i][0]}: {ALLOWED[i][1][:70]}" for i in range(len(ALLOWED)) if i not in used]
group("S", [(f"no unlisted text (unlisted: {len(unlisted)}" + (f"; first: {unlisted[0]}" if unlisted else "") + ")",
             not unlisted),
            (f"every listed text still there ({len(stale)} not found" + (f"; first: {stale[0]}" if stale else "") + ")",
             not stale)],
      f"the sweep over {len(files)} Markdown files: {found} texts in its phrasings, {own} in this fix's own account "
      f"(items 127-130, integration log section 35, its README), {marked} with a marker of this fix or a history clause "
      f"in their context, {listed} in the {len(used)} of the {len(ALLOWED)} listed texts found, {len(unlisted)} "
      f"unlisted")
for u in unlisted[:40]:
    print(f"         unlisted: {u}")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 5 groups not as stated)")
sys.exit(1 if problems else 0)
