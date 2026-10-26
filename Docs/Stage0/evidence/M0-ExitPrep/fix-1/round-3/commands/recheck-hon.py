#!/usr/bin/env python3
"""Recheck of the fix of the third review of the M0 exit preparation (26 October 2026; integration log section 33):
each finding the workflow relayed from that review, which read m0-exit-prep at 415ae25b, answered where the fix says it
is, the review's status given wherever the records gave the fix of the second review as not reviewed, and a sweep of the
records for any text left that gives R4-01 and R4-02 as closed or done, or row 76 as passed-host.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands/recheck-hon.py <tree>

<tree> is a repository root or an extracted tree (git archive). One line per group:
  H1  HON-EP-01 (major): row 76 failed again, naming the open route of R4-01's kind, with its dated note; the count
      (passed-host 11, failed 5), read in Section 2 as well; the checker's row 76 expecting failed, with ADR-0014's
      status saying that no review has accepted the change and no longer saying that R4-01 and R4-02 are closed in the
      guard; ADR-0014's status line without its contradictory sentence; and every text that called R4-01 and R4-02
      closed or the request done (the gate summary, ADR-0014, the ADR index, ADR-0002, ADR-0004, ADR-0015, the plan, the
      amendments, the runbook, the session log, the integration log, the Stage 0 README, the Zip guard's evidence
      README, the hand-over's README, deps record and script) now saying answered by an agent's change, review
      pending, each old text gone; and the gate summary's item 119;
  H2  HON-EP-02: Section 8's Branch note no longer gives CLAUDE.md's correction to the preparation, and says whose it
      was; the hand-over's checks' README and its comparison script have their dated notes; item 120;
  H3  HON-EP-03: where the owner's request for that correction is recorded, in the texts the fix names, and the record
      itself, correction-record.log, with the commit message and the relays; item 121;
  H4  HON-EP-04: CLAUDE.md's first statement, unchanged, given beside the branch question in Section 5.4 and noted in
      item 1's step 1, item 104, the Stage 0 README and integration log 30.3 and 30.6; item 122;
  H5  HON-EP-05: the Stage 0 README's heading, Section 8's Written by line, Section 1's bullet and the heading of items
      104-110 dated 24 and 26 October 2026 (the README's 26 October), the State line naming no date of the preparation;
      item 123;
  R   the review's status: the State line (within 200 words), Section 6.2 (the second review's row, a row for the third
      before the hand-over's row, which stays the table's last, and the paragraph after the table), the notes after
      each text that gave the second fix as not reviewed (items 109, 113 and 118, Section 7's item 5, Section 8; item 4,
      Section 1, Section 6.1; ADR-0014, the ADR index, the Stage 0 README, the runbook, integration log 30.6, 31.5 and
      32, and the evidence READMEs), item 124, Section 8's bullet for this fix and integration log section 33;
  S   the sweep: every Markdown file under Docs/, README.md and CLAUDE.md, each line read whole: a text in the phrasings
      of PHRASES (closed by an agent, closed in the guard, done by an agent, row 76 passed-host, passed-host 12, ...)
      must have, in the same sentence or note, a marker of this fix's correction (HON-EP-01, item 119, section 33, or a
      history clause dated 26 October 2026), or be one of ALLOWED, the texts this fix read and found to give no present
      status of R4-01, R4-02 or row 76 (the linkage.sh run, the request itself, an account with its note, item 119,
      another subject), each with its reason; and each of ALLOWED must still be there. A text that says the same in
      other words can escape it.
Most checks are an anchor with the start of the dated note that must follow it, or a text that must stand, or a text
that must be gone. On HEAD every group must pass; on the tree of 415ae25b, the reviewed commit, which the gate checks
beside this file run as its control, every group must be reported. Standard library only; read-only; reads files only.
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
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
INDEX = "Docs/ADRs/README.md"
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
A04 = "Docs/ADRs/0004-epub-reader-adapter.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
A15 = "Docs/ADRs/0015-threat-model.md"
A16 = "Docs/ADRs/0016-capture-envelope-and-anchors.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
AMEND = "Docs/Stage0/M0-plan-amendments.md"
TPI = "Docs/Licenses/third-party-inventory.md"
CHECKER = "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
ITEMS = "Docs/Stage0/evidence/M0-Integration/item-reviews"
SCRIPT = f"{ITEMS}/commands/item-reviews.py"
COMPARE = f"{ITEMS}/commands/compare-gate-checks.py"
DEPS = f"{ITEMS}/deps.md"
IREADME = f"{ITEMS}/README.md"
EXIT = "Docs/Stage0/evidence/M0-ExitPrep"
ZIP = f"{EXIT}/zipguard/README.md"
FIX1 = f"{EXIT}/fix-1/README.md"
FIX2 = f"{EXIT}/fix-1/round-2/README.md"
FIX3 = f"{EXIT}/fix-1/round-3/README.md"
ASM = f"{EXIT}/assembly/README.md"
REVIEWS = f"{EXIT}/reviews/README.md"
RECORD = f"{EXIT}/fix-1/round-3/correction-record.log"
CACHE = {}

ANSWERED = "answered by an agent's change, review pending"
NOTE14 = (" *(24 October 2026: answered by an agent's change, review pending: ADR-0014 status. Until 26 October 2026 "
          "this note said closed: the third review of the M0 exit preparation, its finding HON-EP-01.)*")
OLD14 = " *(24 October 2026: closed by an agent's change, reviewed next: ADR-0014 status.)*"
I119 = "`M0-gate.md` Section 6.3, item 119"
BOTH_NEW = (" *(the fix of R4-01 and R4-02 made by an agent on 24 October 2026, review pending, and `linkage.sh` run the "
            "same day; until 26 October 2026 this note called both done: " + I119 + ")*")
BOTH_OLD = " *(both done by an agent on 24 October 2026, reviewed next)*"
REQ = "your request recorded only in its commit message"


def read(rel):
    if rel not in CACHE:
        p = ROOT / rel
        CACHE[rel] = p.read_text(encoding="utf-8") if p.is_file() else ""
    return CACHE[rel]


problems = 0


def group(name, checks, what):
    """checks: (file, text) pairs that must stand; (file, anchor, note start) triples that must stand together;
    ('gone', file, text) triples that must not stand; ('count', file, text, n) quadruples; and (label, bool) pairs."""
    global problems
    missing = []
    for c in checks:
        if c[0] == "gone":
            _, f, text = c
            if text in read(f):
                missing.append(f"{f} still has: {text[:90]}")
        elif c[0] == "count":
            _, f, text, n = c
            if read(f).count(text) != n:
                missing.append(f"{f} has {read(f).count(text)}, not {n}, of: {text[:80]}")
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


def section2_counts():
    counts, inside = {}, False
    for line in gate.splitlines():
        if line.startswith("## "):
            inside = line.startswith("## 2.")
        if inside and line.startswith("| "):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if cells and cells[0].isdigit():
                counts[cells[2]] = counts.get(cells[2], 0) + 1
    return counts


counts = section2_counts()
row76 = next((line for line in gate.splitlines() if line.startswith("| 76 | ")), "")

# H1: HON-EP-01.
group("H1", [
    (GATE, "| 76 | Dependency lock: the CI guard that keeps marmelroy/Zip 2.1.2 (CVE-2023-39135) out of product code | "
           "failed | Round 4's verdict, reject, stands: R4-01 and R4-02 are answered by an agent's change, review "
           "pending, and this row, an M0 deliverable, stays failed until a review accepts that change"),
    ("row 76 names the open route of R4-01's kind", "one more route of R4-01's kind is open, a version-specific "
                                                    "manifest beside a product `Package.swift`" in row76),
    ("row 76 ends with its note of 26 October 2026 on the third review",
     "*(26 October 2026: failed again, after the third review of the M0 exit preparation, at `415ae25b`, its finding "
     "HON-EP-01." in row76),
    ("gone", GATE, "| passed-host | The guard closes R4-01 and R4-02"),
    (GATE, "so the counts are those of 22 October 2026, passed-host 11 and failed 5"),
    ("gone", GATE, "Since 24 October 2026 row 76 is passed-host"),
    (f"Section 2 counts passed-host 11 and failed 5 (it counts {counts.get('passed-host')} and "
     f"{counts.get('failed')})", counts.get("passed-host") == 11 and counts.get("failed") == 5),
    (CHECKER, '76: ("failed", adr_says(14, "reject", "R4-01 and R4-02 are answered in the guard by its change, review '
              'pending",'),
    (CHECKER, 'lambda: "R4-01 and R4-02 are closed in the guard" not in adr_status(14))]'),
    ("gone", CHECKER, '76: ("passed-host"'),
    (A14, "by an agent: R4-01 and R4-02 are answered in the guard by its change, review pending**"),
    (A14, "No review has accepted that change: until one does, round 4's verdict, given on the record before it, stands, "
          "R4-01 and R4-02 stay open, and the gate summary's row 76 stays failed"),
    ("gone", A14, "R4-01 and R4-02 are closed in the guard"),
    ("gone", A14, "That change answers the findings"),
    ("gone", A14, "whether the findings are answered is the next review's to say. It approves nothing"),
    (A14, "R4-01 and R4-02, are answered by an agent's change, with routes of the same kind, review pending (section 3; "
          "Status; until 26 October 2026 this note said closed"),
    (A14, "R4-01 and R4-02 are answered by an agent's change, review pending, so the sign-off also waits for a review "
          "that accepts it"),
    (A14, "*(Answered, 24 October 2026, by an agent's change, review pending: this item stays open until a review "
          "accepts it."),
    ("gone", A14, "The fix closes R4-01 and R4-02"),
    (GATE, "*(24 October 2026: R4-01 and R4-02 answered by an agent's change, review pending, `linkage.sh` run by an "
           "agent, and the records in"),
    (GATE, "assembled on `m0-exit-prep`: R4-01 and R4-02 answered by an agent's change, review pending, and the "
           "final-review records in: item 4.)*"),
    ("gone", GATE, "R4-01 and R4-02 closed, reviewed next, and the final-review records in"),
    (GATE, "*(24 October 2026: R4-01 and R4-02 are answered by an agent's change, review pending, so this sign-off "
           "waits for a review that accepts it"),
    (GATE, "the fix of R4-01 and R4-02 made by an agent, review pending, and the run of `linkage.sh` done (item 4).)*"),
    (GATE, "*(24 October 2026: answered by an agent's change at the M0 exit preparation, review pending, on "
           "`m0-exit-zipguard`"),
    (GATE, " *(26 October 2026: not closed yet. No review has accepted the change:"),
    ("gone", GATE, "*(24 October 2026: done by an agent at the M0 exit preparation"),
    (GATE, "*(24 October 2026: they are answered in the guard by an agent's change, review pending;"),
    (GATE, "ADR-0014's R4-01 and R4-02 answered in the guard by an agent's change, with R4-03 and R4-04 and routes of "
           "the same kind, review pending, so row 76 stays failed"),
    ("gone", GATE, "so row 76 is passed-host"),
    (GATE, "*(the fix of R4-01 and R4-02 made by an agent on 24 October 2026, review pending, and `linkage.sh` run the "
           "same day; until 26 October 2026 this note called both done: Section 1, item 4;"),
    (GATE, "*(24 October 2026: both findings answered by an agent's change, review pending, so this item stays open"),
    ("count", GATE, "*(24 October 2026: answered by an agent's change on `m0-exit-zipguard`, `6cd842d3`, review "
                    "pending, so still open here;", 2),
    (GATE, "*(24 October 2026: both answered by that change, review pending; until 26 October 2026 this note said "
           "closed"),
    (GATE, "(rows 10, 22, 42, 63 and 76; row 76 was passed-host from 24 to 26 October 2026"),
    (GATE, "105. **R4-01 and R4-02 answered in the guard, review pending**"),
    (GATE, "*(Dated note, 26 October 2026: row 76 is failed again, and the counts are passed-host 11 and failed 5"),
    (GATE, "*(Dated note, 26 October 2026: failed again since the third review of the M0 exit preparation, its finding "
           "HON-EP-01: item 119.)*"),
    (GATE, "*(dated note, 26 October 2026: R4-03 and R4-04, with R4-01 and R4-02, are answered by that change"),
    (GATE, "ADR-0014's R4-01 and R4-02 closed by an agent you ask *(answered by an agent's change on 24 October 2026, "
           "review pending,"),
    (GATE, "and once R4-01 and R4-02 are closed too *(answered by an agent's change on 24 October 2026, review "
           "pending;"),
    ("gone", GATE, "ADR-0014's R4-01 and R4-02 closed by an agent you ask *(done by an agent"),
    (GATE, "119. **R4-01 and R4-02 answered, not closed, and row 76 failed again** (HON-EP-01, major)"),
    (INDEX, "*(24 October 2026: both answered by an agent's change at the M0 exit preparation, review pending,"),
    (INDEX, "*(answered by an agent's change on 24 October 2026, review pending: ADR-0014 status;"),
    (INDEX, "On 26 October 2026 those notes were reworded: R4-01 and R4-02 answered by an agent's change, review "
            "pending, not closed"),
    (A02, "The fix of R4-01 and R4-02 was made before the sessions, by an agent's change, review pending,"),
    (A02, "*(24 October 2026: R4-01 and R4-02 answered by an agent's change, review pending, on a branch of its own"),
    ("count", A04, NOTE14, 1), ("count", A15, NOTE14, 3), ("count", PLAN, NOTE14, 3), ("count", AMEND, NOTE14, 2),
    ("gone", A04, OLD14), ("gone", A15, OLD14), ("gone", PLAN, OLD14), ("gone", AMEND, OLD14),
    (A15, "which an agent's change answered that day, review pending (until 26 October 2026 this said closed:"),
    (AMEND, "which an agent's change answered on 24 October 2026, review pending (until 26 October 2026 this said "
            "closed, reviewed next:"),
    (RUNBOOK, "*(both answered by an agent's change on 24 October 2026, review pending; until 26 October 2026 this note "
              "called them done:"),
    ("count", RUNBOOK, BOTH_NEW, 6), ("gone", RUNBOOK, BOTH_OLD),
    (RUNBOOK, "the R4-01 and R4-02 fix is made, by an agent, before the sessions,"),
    ("gone", RUNBOOK, "the R4-01 and R4-02 fix is done"),
    (RUNBOOK, "*(24 October 2026: R4-01 and R4-02 answered by an agent's change, review pending, and `linkage.sh` run "
              "by an agent: the next two paragraphs."),
    (RUNBOOK, "Not closed: no review has accepted the change, so row 76 stays failed and this request stays open"),
    (RUNBOOK, "*(24 October 2026: answered by an agent's change, review pending; the verdict stays on the record until "
              "a review accepts the change: ADR-0014 status."),
    (SESSIONS, "(5) taken up by agents of the M0 exit preparation"),
    (SESSIONS, "*(the fix of R4-01 and R4-02 made by an agent on 24 October 2026, review pending, and `linkage.sh` run "
               "the same day; until 26 October 2026 this note called both done: run 1)*"),
    ("count", LOG, "*(Dated note, 24 October 2026: R4-01 and R4-02 answered by an agent's change, review pending: "
                   "section 28.", 2),
    (LOG, "## 28. ADR-0014's R4-01 and R4-02 answered in the guard, review pending, and `linkage.sh` under Xcode 27.1 "
          "(24 October 2026)"),
    (LOG, "*(Dated note, 26 October 2026: until then this section's title said that R4-01 and R4-02 are closed"),
    (LOG, "| ADR-0014's R4-01 and R4-02 answered in the guard, review pending (until 26 October 2026 this cell said "
          "closed: section 33)"),
    (LOG, "*(Dated note, 26 October 2026: row 76 is failed again. The request was that of the agent that made the "
          "change, for its own row"),
    (LOG, "*(dated note, 26 October 2026: since section 33 the checker's row 76 expects failed again"),
    (LOG, "R4-03 and R4-04 (closed with it, as this said until 26 October 2026; answered by it, review pending: section "
          "33)"),
    (LOG, "(passed-host 12, failed 4, partial 13, pending-human 21; passed-host 11 and failed 5 since section 33)"),
    (README, "(on 24 October 2026 R4-01 and R4-02 answered by an agent's change, review pending, and `linkage.sh` run by "
             "an agent:"),
    (README, "*(24 October 2026: both answered by an agent's change, review pending, so the verdict stands,"),
    ("gone", README, "the first two done by an agent"),
    (ZIP, "# ADR-0014 review round 4: R4-01 and R4-02 answered in the Zip guard, review pending"),
    (IREADME, "R4-03 and R4-04 answered by it, review pending, R4-05 to R4-07 left open with its owner"),
    (IREADME, "*(Dated note, 26 October 2026: that agent answered both in the guard by its change,"),
    (DEPS, "*(Dated note, 26 October 2026: that agent answered both in the guard by its change on `m0-exit-zipguard`"),
    (DEPS, "R4-03 and R4-04 answered by that fix, review pending,"),
    (SCRIPT, "that agent answered both \"\n        \"in the guard by its change on `m0-exit-zipguard` (`6cd842d3`)"),
    ("gone", DEPS, "that agent closed both"), ("gone", IREADME, "that agent closed both"),
], "row 76 failed again with its checker and the count, ADR-0014's status line, and R4-01 and R4-02 answered, not "
   "closed, wherever the records called them closed or the request done; item 119")

# H2: HON-EP-02.
branch = next((line for line in gate.splitlines() if line.startswith("- **Branch:**")), "")
group("H2", [
    ("the Branch line's note says outside Docs/", "Outside `Docs/` it changed `Scripts/check-dependency-lock.py` and "
                                                  "`Scripts/ci.d/12-dependency-lock.sh`" in branch),
    ("the Branch line no longer says besides CLAUDE.md", "Besides `CLAUDE.md`, it changed" not in branch),
    ("the Branch line says whose the correction was",
     "`CLAUDE.md`'s correction, `5aec2518`, which the preparation's branches were made from, was not the preparation's "
     "work: the orchestrating session made it on top of `main` before the preparation began" in branch),
    (REVIEWS, "(Section 1, item 1, step 2).", " *(Dated note, 26 October 2026: made otherwise than step 2 asks, which "
                                              "is on `m0-decisions`:"),
    (COMPARE, "(Dated note, 26 October 2026: 5aec2518 is that correction made otherwise than step 2 asks, which is on "
              "m0-decisions:"),
    (GATE, "120. **Who made `CLAUDE.md`'s correction** (HON-EP-02)"),
], "Section 8's Branch note, the hand-over's checks' README and comparison script; item 120")

# H3: HON-EP-03.
record = read(RECORD)
group("H3", [
    (GATE, "Your request is recorded only in that commit's message, which the orchestrating session wrote (Section 6.3, "
           "item 121).)*"),
    (GATE, "and at your request, as its commit message records, the orchestrating session corrected"),
    (GATE, "(`5aec2518`, made at your request, as its commit message records: Section 6.3, item 121)"),
    (GATE, "`5aec2518` (your request recorded only in its commit message: Section 6.3, item 121)"),
    ("the Branch line's note says where the request is recorded",
     "at your request as its commit message records (Section 6.3, items 104 and 121)" in branch),
    (GATE, "*(Dated note, 26 October 2026: your request is recorded only in `5aec2518`'s commit message"),
    (GATE, "121. **The record of your request for that correction** (HON-EP-03)"),
    (GATE, "`evidence/M0-ExitPrep/fix-1/round-3/correction-record.log`"),
    ("count", RUNBOOK, REQ, 3),
    (SESSIONS, "(2) made at your request, as its commit message records, by the orchestrating session"),
    (README, "`5aec2518`, a request recorded only in that commit's message: integration log sections 30 and 33)*"),
    (LOG, "(a request recorded only in that commit's message, which the session wrote: section 33, HON-EP-03)"),
    (LOG, "(a request recorded only in that commit's message: section 33)"),
    ("correction-record.log holds the commit message's sentence on the request",
     "The owner asked the orchestrating session to make it on 24 October 2026" in record),
    ("correction-record.log reads the two relays", "owner-answers-2026-10-23.md" in record
     and "xcode-27.1-release.md" in record and "\nresult: pass" in record),
], "where the owner's request is recorded, in the texts the fix names, and its record; item 121")

# H4: HON-EP-04.
s54 = section(gate, "### 5.4 ", "## 6. ")
group("H4", [
    ("CLAUDE.md, the owner's, still begins its milestone paragraph's M0 statement as corrected",
     "All M0 work is on `main`." in read("CLAUDE.md")),
    ("Section 5.4 lists the sentence beside the branch question",
     "Nor does the paragraph's first statement hold, that all M0 work is on `main`:" in s54
     and "when you settle the branch, have that sentence brought into line with it too" in s54),
    (GATE, "the first of these no longer holds, since the M0 exit preparation and its fixes, the correction among them, "
           "are on `m0-exit-prep`, not on `main` (Section 5.4)."),
    (GATE, "And the paragraph's first statement, that all M0 work is on `main`, does not hold while the preparation is "
           "on `m0-exit-prep` and not on `main`"),
    (GATE, "122. **`CLAUDE.md`'s first statement, on `main`** (HON-EP-04)"),
    (README, "and that all M0 work is on `main`, which does not hold while the M0 exit preparation is on "
             "`m0-exit-prep`"),
    (LOG, "the code is the same either way, since `main` and `m0-decisions` have the same tree.",
     " *(Dated note, 26 October 2026: and a third beside them: the paragraph's first statement,"),
    (LOG, "unless the product owner decides otherwise (`CLAUDE.md`).",
     " *(Dated note, 26 October 2026: nor, while it is not, does `CLAUDE.md`'s first statement hold,"),
], "CLAUDE.md's first statement beside the branch question, and the notes on it; item 122")

# H5: HON-EP-05.
state = next((line for line in gate.splitlines() if line.startswith("- **State:**")), "")
group("H5", [
    (README, "**Where M0 stands (26 October 2026).**"),
    ("gone", README, "**Where M0 stands (24 October 2026).**"),
    (README, "Until then this paragraph was dated 24 October 2026, though it reported work of 26 October"),
    (GATE, "nor has the M0 exit preparation of 24 and 26 October 2026 (sections 28-30)"),
    ("gone", GATE, "nor has the M0 exit preparation of 24 October 2026 (sections 28-30)"),
    (GATE, "it dated that preparation 24 October 2026 alone, though its continuation and its checks are of 26 October: "
           "HON-EP-05.)"),
    (GATE, "- **The M0 exit preparation (24 and 26 October 2026).**"),
    (GATE, "Recorded on 24 October 2026, at the M0 exit preparation, and on 26 October 2026 by its continuation (item "
           "110; integration log sections 28-30):"),
    ("the State line names no date of the preparation", "exit preparation of 24 October" not in state),
    (GATE, "123. **The dates of the status lines** (HON-EP-05)"),
], "the README's heading, the Written by line, Section 1's bullet and Section 6.3's heading; item 123")

# R: the review's status.
words = len(state.split())
s62 = section(gate, "### 6.2 Minor findings", "### 6.3 ")
rows = [line for line in s62.splitlines() if line.startswith("| ")]
first = next((i for i, r in enumerate(rows) if r.startswith("| The review of the M0 exit preparation (26 October 2026, "
                                                             "at `609ed492`")), -1)
second = next((i for i, r in enumerate(rows) if r.startswith("| The second review of the M0 exit preparation (26 October "
                                                              "2026, at `83030fba`")), -1)
third = next((i for i, r in enumerate(rows) if r.startswith("| The third review of the M0 exit preparation (26 October "
                                                             "2026, at `415ae25b`")), -1)
handover = next((i for i, r in enumerate(rows) if r.startswith("| The thirteen M0 items' own final reviews |")), -1)
group("R", [
    (GATE, "have not been reviewed, nor has the fix of the third review of the M0 exit preparation (Sections 6.2 and "
           "8)."),
    ("gone", GATE, "nor has the fix of the second review of the M0 exit preparation (Sections 6.2 and 8)."),
    (f"the State line has {words} words (at most 200)", 0 < words <= 200),
    ("Section 6.2: the first review's row, the second's, the third's, then the hand-over's, the table's last",
     0 <= first < second < third < handover == len(rows) - 1),
    (GATE, "that answer read by a third agent review the same day, at `415ae25b` (next row; until the fix of that "
           "review this cell said not reviewed) | integration log section 32 |"),
    (GATE, "answered on 26 October 2026 by the fix of that review, all five (Section 6.3, items 119-124); not reviewed "
           "| integration log section 33 |"),
    (GATE, "that fix has not been reviewed.)*", " *(26 October 2026: a third agent review has read the branch since, at "
                                              "`415ae25b`"),
    (GATE, "*(Dated note, 26 October 2026: and again, with the fix of that review, at `83030fba`: items 114-118.)*",
     " *(Dated note, 26 October 2026: and a third time, with the second fix, at `415ae25b`: items 119-124.)*"),
    (GATE, "which stays with ADR-0014's owner: items 114-118.)*", " *(26 October 2026: a third read the branch at "
                                                                  "`415ae25b`;"),
    (GATE, "The hand-over's two READMEs and integration log section 29 say that both reviews read it.",
     " *(Dated note, 26 October 2026: read by a third agent review at `415ae25b`"),
    (GATE, "124. **Not reviewed**: this fix is agent-written; its checks, on its last commits, are in "
           "`evidence/M0-ExitPrep/fix-1/round-3/` (integration log section 33.4)."),
    (GATE, "*(26 October 2026: and the fix of the second review of the M0 exit preparation, items 114-118)*",
     " *(26 October 2026: and the fix of its third review, items 119-124)*"),
    (GATE, "`evidence/M0-ExitPrep/fix-1/round-2/commands/gate-checks.sh`); not reviewed.",
     " *(26 October 2026: read by the third review of the M0 exit preparation, at `415ae25b`"),
    (GATE, "- **The fix of the third review of the M0 exit preparation (26 October 2026; integration log section 33).**"),
    (GATE, "changed nothing outside `Docs/`: integration log section 32.)*",
     " *(26 October 2026: the fix of the third review of the M0 exit preparation, on `m0-exit-prep`, changed nothing "
     "outside `Docs/`: integration log section 33."),
    (GATE, "the fix of the second, section 32, has had none)*",
     " *(26 October 2026: a third read it at `415ae25b`, the second's fix with it; the fix of the third, section 33, "
     "has had none)*"),
    (GATE, "a third, at `415ae25b`, found that these notes called the request done"),
    (GATE, "*(26 October 2026: a third agent review read it at `415ae25b`, with the second fix, and raised five "
           "findings"),
    (GATE, "*(26 October 2026: a third agent review read the branch at `415ae25b`; its major finding, HON-EP-01,"),
    (A14, "*(26 October 2026: a third agent review of the M0 exit preparation read the branch at `415ae25b`"),
    (INDEX, "none on the guard: ADR-0014 status.)*", " *(26 October 2026: a third read the branch at `415ae25b`;"),
    (README, "*(26 October 2026: a third agent review read the branch at `415ae25b`, with the second fix,"),
    (RUNBOOK, "has not been reviewed: integration log section 32.)*",
     " *(26 October 2026: a third agent review read the branch at `415ae25b`;"),
    (LOG, "whether it judged R4-01 and R4-02 answered was not relayed: section 31.)*",
     " *(Dated note, 26 October 2026: a second agent review read the branch at `83030fba` and a third at `415ae25b`;"),
    (LOG, "whether it judged R4-01 and R4-02 answered was not relayed either (section 32).)*",
     " *(Dated note, 26 October 2026: and a third, at `415ae25b`,"),
    (LOG, "from `83030fba`; agent-written, not reviewed, human sign-off pending.",
     " *(Dated note, 26 October 2026: read by a third agent review the same day, at `415ae25b`: 32.5 and section 33.)*"),
    (LOG, "until a review says whether R4-01 and R4-02 are answered; human sign-off pending.",
     " *(Dated note, 26 October 2026: a third agent review read it the same day, at `415ae25b`"),
    (LOG, "## 33. The third review of the M0 exit preparation, and its fix (26 October 2026)"),
    (LOG, "### 33.1 The findings, and what was done"), (LOG, "### 33.2 What this fix left as it was"),
    (LOG, "### 33.3 Commits"), (LOG, "### 33.4 Checks"), (LOG, "### 33.5 Not done here, and why"),
    (FIX2, "**It is agent-written and not reviewed.**",
     " *(Dated note, 26 October 2026: read since by a third agent review of the M0 exit preparation, at `415ae25b`"),
    (FIX1, "the logs here are this fix's, as they ran.)*", " *(Dated note, 26 October 2026: and by a third, at "
                                                          "`415ae25b`"),
    (ASM, "*(Dated note, 26 October 2026: a third agent review read the branch at `415ae25b`;"),
    (ZIP, "The counts below are this fix's, as it ran.)*", " *(Dated note, 26 October 2026: a second agent review read "
                                                          "the branch at `83030fba`, and a third at `415ae25b`;"),
    (REVIEWS, "The logs here are the hand-over's, as they ran.)*", " *(Dated note, 26 October 2026: and by a third, at "
                                                                  "`415ae25b`"),
    (IREADME, "not reviewed: integration log section 32.)*", " *(Dated note, 26 October 2026: and by a third, at "
                                                             "`415ae25b`"),
], "the State line, Section 6.2, the notes after each text that gave the second fix as not reviewed, item 124, Section "
   "8's bullet for this fix, and integration log section 33")

# S: the sweep of the records.
PHRASES = [r"closed by an agent", r"closed in the (?:Zip )?guard", r"\bboth closed\b", r"are closed by",
           r"closes R4-0[12]", r"[Tt]he fix closes", r"R4-01 and R4-02 closed[,;:] ", r"closed, reviewed next",
           r"[Rr]ow 76 is passed-host", r"passed-host 12", r"fix is done", r"done by an agent", r"both done",
           r"first two done", r"closed with (?:it|that fix)", r"agent closed both", r"closed that day",
           r"closed on 24 October", r"\(Done, 24 October", r"Done on 24 October 2026 by an agent",
           r"so it is, by their fix"]
MARKERS = ["HON-EP-01", "item 119", "section 33", "until 26 October 2026", "Until 26 October 2026",
           "From 24 to 26 October 2026", "from 24 to 26 October 2026"]
# The texts this fix read and found to give no present status of R4-01, R4-02 or row 76, each with its reason; each
# must contain the phrase found and be found around it.
ALLOWED = [
    (A14, "*(Done, 24 October 2026, by an agent that may not fetch, so offline:", "the run of `linkage.sh`, made"),
    (A16, "both done at M0 assembly", "another subject: two of ADR-0016's open items"),
    (TPI, "the further routes the fix closes", "another subject: review round 1's fix of 13 October 2026"),
    (RUNBOOK, "*(24 October 2026: done by an agent, offline, reviewed next: Section 6.)*", "the run of `linkage.sh`"),
    (RUNBOOK, "before the reviews of ADR-0014; *(done by an agent on 24 October 2026, reviewed next: Section 6)*",
     "the run of `linkage.sh`"),
    (RUNBOOK, "*(24 October 2026: done by an agent, reviewed next, offline, so you need not run it:",
     "the run of `linkage.sh`"),
    (GATE, "ADR-0014's R4-01 and R4-02 closed by an agent, whom you ask to start from `m0-decisions`",
     "item 1's step 5: the request itself, what to ask for"),
    (GATE, "Row 76 is passed-host, the checker's facts for it changed with it",
     "item 105's account of the preparation, its dated note of 26 October 2026 at the item's end"),
    (GATE, "and the counts are passed-host 12 and failed 4 (Section 2.9).",
     "item 105's account of the preparation, its dated note of 26 October 2026 at the item's end"),
    (GATE, "moved the counts to passed-host 12 and failed 4", "item 119, the history of the finding"),
    (GATE, "whenever ADR-0014's status says that R4-01 and R4-02 are closed in the guard",
     "item 119, the history of the finding"),
    (GATE, "ADR-0014's status line said that both are closed in the guard", "item 119, the history of the finding"),
    (GATE, "no longer saying that both are closed in the guard", "item 119, the history of the finding"),
    (GATE, "brought up to date from them by its owner (Section 1, item 4) *(done by an agent on 24 October 2026, "
           "reviewed next)*", "Section 7's item 1: the run of `linkage.sh`"),
    (GATE, "which its ADR-0014 items wait for *(done by an agent on 24 October 2026, reviewed next)*",
     "Section 7's item 2: the run of `linkage.sh`"),
    (GATE, "ADR-0014's lock and item 7, after `linkage.sh`'s run *(done by an agent on 24 October 2026, reviewed "
           "next)*", "Section 7's item 2: the run of `linkage.sh`"),
    (GATE, "and of its lock, after `linkage.sh`'s run *(done by an agent on 24 October 2026, reviewed next)*",
     "Section 7's item 3: the run of `linkage.sh`"),
    (FIX3, "moved the counts to passed-host 12 and failed 4", "this fix's README, its account of HON-EP-01"),
    (FIX3, "whenever ADR-0014's status says that R4-01 and R4-02 are closed in the guard",
     "this fix's README, its account of HON-EP-01"),
    (LOG, "moved the counts to passed-host 12 and failed 4, made the checker expect passed-host",
     "integration log 33.1, its account of HON-EP-01"),
    (LOG, "whenever ADR-0014's status says that R4-01 and R4-02 are closed in the guard, called item 4's request done",
     "integration log 33.1, its account of HON-EP-01"),
    (LOG, "no longer saying that R4-01 and R4-02 are closed in the guard, with the guard's logs read as before",
     "integration log 33.1: what the checker reads now"),
    (LOG, "ADR-0014's status planted saying that R4-01 and R4-02 are closed in the guard",
     "integration log 33.4: a control of the checker"),
]
rx = re.compile("|".join(PHRASES))
files = sorted((ROOT / "Docs").rglob("*.md")) + [ROOT / "README.md", ROOT / "CLAUDE.md"]
found, marked, listed, unlisted, used = 0, 0, 0, [], set()
for f in files:
    if not f.is_file():
        continue
    rel = str(f.relative_to(ROOT))
    for n, line in enumerate(f.read_text(encoding="utf-8").split("\n"), 1):
        for m in rx.finditer(line):
            found += 1
            a = max(line.rfind(". ", 0, m.start()), line.rfind("*(", 0, m.start()), 0)
            ends = [i for i in (line.find(". ", m.end()), line.find(")*", m.end())) if i >= 0]
            sentence = line[a:(min(ends) if ends else len(line)) + 2]
            if any(k in sentence for k in MARKERS):
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
      f"the sweep over {len(files)} Markdown files: {found} texts in its phrasings, {marked} with a marker of this fix "
      f"in the same sentence or note, {listed} in the {len(used)} of the {len(ALLOWED)} listed texts found, "
      f"{len(unlisted)} unlisted")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 7 groups not as stated)")
sys.exit(1 if problems else 0)
