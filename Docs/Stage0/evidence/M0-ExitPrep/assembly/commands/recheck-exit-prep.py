#!/usr/bin/env python3
"""Recheck of the assembly of the M0 exit preparation (24 October 2026; integration log section 30): every request the
two branches made of other owners' records, as applied or as declined with its reason, and the three things the
assembly recorded besides them (Apple's pages for Xcode 27.1, as relayed; CLAUDE.md's correction of 5aec2518; the gate
summary's, the integration log's and the Stage 0 README's account of the round).

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/assembly/commands/recheck-exit-prep.py <tree>

<tree> is a repository root or an extracted tree (git archive). Each check is a text that must stand in a file, most of
them an anchor with the start of the dated note that must follow it at once, so that a note in the wrong place fails;
one line per group. On HEAD every group must pass. On the tree of 6ce2c119 (both branches merged, before the
assembly's own changes), which the gate checks beside this file run as the control, every group must be reported. The
checks read files only; they do not judge the notes' wording beyond the texts given here. Standard library only;
read-only. Exits 1 if any group is not as stated.
"""
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
README = "Docs/Stage0/README.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
INDEX = "Docs/ADRs/README.md"
A01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
A04 = "Docs/ADRs/0004-epub-reader-adapter.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
A15 = "Docs/ADRs/0015-threat-model.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
AMEND = "Docs/Stage0/M0-plan-amendments.md"
CHECKER = "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
CACHE = {}


def read(rel):
    if rel not in CACHE:
        p = ROOT / rel
        CACHE[rel] = p.read_text(encoding="utf-8") if p.exists() else ""
    return CACHE[rel]


problems = 0


def group(name, checks, what):
    """checks: (file, text) pairs, or (file, anchor, note start) triples."""
    global problems
    missing = []
    for c in checks:
        if len(c) == 2:
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


DONE = " *(done by an agent on 24 October 2026, reviewed next)*"
BOTH = " *(both done by an agent on 24 October 2026, reviewed next)*"
NOTE = " *(24 October 2026: closed by an agent's change, reviewed next: ADR-0014 status.)*"
IN = " *(Dated note, 24 October 2026: in, by a pointer in each report or record to its item's record: item 4.)*"
HANDED = " *(Dated note, 24 October 2026: handed over that day, with a pointer in each gate report and record:"

print("== The zipguard branch's requests (m0-exit-zipguard; integration log 30.2)")
group("Z1", [(GATE, "| 76 | Dependency lock: the CI guard that keeps marmelroy/Zip 2.1.2 (CVE-2023-39135) out of product "
                    "code | passed-host | The guard closes R4-01 and R4-02 and the routes of the same kind, R4-03 and "
                    "R4-04 among them."),
             (GATE, "Each of 23 routes passed the check before the change and fails it after, on copies of the tree "
                    "(`evidence/M0-ExitPrep/zipguard/reproductions.log`)."),
             (GATE, "| ADR-0014 status and section 3; integration log section 28 |")],
      "row 76 passed-host, its Evidence and Source as requested")
group("Z2", [(GATE, "so the counts are partial 13 and pending-human 21, the others unchanged (`evidence/M0-Decisions/"
                    "stage0/gate-checks.log`, part 3).", " Since 24 October 2026 row 76 is passed-host"),
             (GATE, "(rows 10, 22, 42 and 63; row 76 was failed until the fix of R4-01 and R4-02 on 24 October 2026)"),
             (CHECKER, '76: ("passed-host", adr_says(14, "R4-01 and R4-02 are closed in the guard")'),
             (CHECKER, '"self-test: 278 mutations")),')],
      "the count, Section 6.1's last paragraph and the checker's row 76, changed together")
group("Z3", [(GATE, "bringing it on to `main` before the exit is a further merge your answer did not cover (item 1).",
              " *(24 October 2026: done by an agent at the M0 exit preparation, on `m0-exit-zipguard` from `5aec2518`"),
             (GATE, "bring section 4 and its Evidence up to date, or record that nothing changed, before those reviews.",
              " *(24 October 2026: the measurement is made.")],
      "item 4's two bullets")
group("Z4", [(GATE, "and the final reviews' records, which need no device (item 4)",
              " *(24 October 2026: the first two done by an agent, reviewed next, and the records in"),
             (GATE, "and the thirteen M0 items' final-review records, which item 4 says where to look for.",
              " *(24 October 2026: both done, by agents of the M0 exit preparation"),
             (GATE, "at any time you choose: the run of `linkage.sh` under Xcode 27.1 (item 4).",
              " *(Made by an agent, offline, on 24 October 2026: item 4.)*"),
             (GATE, "and make the request item 4 recommends, to Readium to drop marmelroy/Zip or move to a fixed fork "
                    "(item 4).", " *(24 October 2026: R4-01 and R4-02 are closed by an agent, reviewed next"),
             (GATE, "nor who updates ADR-0014: the review of the follow-up, its finding OWN4-07).",
              " *(Done on 24 October 2026 by an agent, reviewed next: both findings closed and `linkage.sh` run "
              "offline"),
             (GATE, "comes after the exit under D-10 (i) (integration log 7.1, 7.7 and 19; final review SEC-04; until 23 "
                    "October 2026 this cell gave that later deadline alone: the review of the decisions round's fix, "
                    "OWN2-01)", " *(24 October 2026: closed by an agent's change on `m0-exit-zipguard`, `6cd842d3`"),
             (GATE, "passes | serious | Same", " *(24 October 2026: closed by an agent's change on `m0-exit-zipguard`"),
             (GATE, "which Readium 3.11.0 depends on, out of product code.",
              " *(24 October 2026: both closed by that change, reviewed next.)*"),
             (GATE, "ADR-0014's R4-01 and R4-02 closed by an agent you ask", DONE),
             (GATE, "with ADR-0014's section 4 brought up to date from them by its owner (Section 1, item 4)", DONE),
             (GATE, "and once R4-01 and R4-02 are closed too", DONE),
             (GATE, "and after `linkage.sh`'s run, which its ADR-0014 items wait for", DONE),
             (GATE, "ADR-0014's lock and item 7, after `linkage.sh`'s run", DONE),
             (GATE, "and of its lock, after `linkage.sh`'s run", DONE),
             (GATE, "- **The M0 exit preparation's fix of ADR-0014's R4-01 and R4-02 (24 October 2026; integration log "
                    "section 28).**")],
      "the gate summary's dated notes (a) to (h)")
group("Z5", [(LOG, "## 28. ADR-0014's R4-01 and R4-02 closed, and `linkage.sh` under Xcode 27.1 (24 October 2026)"),
             (LOG, "### 28.1 What was done"), (LOG, "### 28.2 Commits"), (LOG, "### 28.3 Checks"),
             (LOG, "### 28.4 Not done here, and why"),
             (LOG, "ADR-0014, ADR-0015, `M0-gate.md` and plan 23.2.)*",
              " *(Dated note, 24 October 2026: R4-01 and R4-02 closed by an agent's change, reviewed next: section "
              "28.)*"),
             (LOG, "the review of the decisions round's fix, its finding OWN2-01.)*",
              " *(Dated note, 24 October 2026: R4-01 and R4-02 closed by an agent's change, reviewed next: section "
              "28.)*")],
      "integration log section 28, and the notes on 7.1 and 7.7")
group("Z6", [(README, "which need no device ([M0-gate.md](M0-gate.md) Section 1, item 4)",
              " (on 24 October 2026 the first two done by an agent, reviewed next: integration log section 28"),
             (README, "(R4-01, R4-02; ADR-0014 status).",
              " *(24 October 2026: both closed by an agent's change, reviewed next, and `linkage.sh` run under Xcode "
              "27.1 offline")],
      "the Stage 0 README's lines 5 and 36")
group("Z7", [(RUNBOOK, "let it run beside the sessions. (Until 23 October 2026 run 6 said that Session 6 completed this "
                       "review's inputs, and `M0-gate.md` listed R4-01 and R4-02 after the M0 exit, before M1 builds: the "
                       "review of the decisions round's fix, its finding OWN2-01.)",
              " *(24 October 2026: done by an agent, reviewed next, on a branch of its own made from `main`"),
             (RUNBOOK, "(ADR-0014, Open items; `M0-gate.md` Section 1, item 4).",
              " *(24 October 2026: done by an agent, reviewed next, offline, so you need not run it: the logs are in "
              "`Docs/Stage0/evidence/M0-dependencies/xcode-27.1/run-2/`"),
             (RUNBOOK, "`linkage.sh` under Xcode 27.1 (Section 6).",
              " *(24 October 2026: done by an agent, offline, reviewed next: Section 6.)*"),
             (RUNBOOK, "| R4-01 and R4-02 closed; `linkage.sh` run" + BOTH + " | 2.5 h |"),
             (RUNBOOK, "| runs 3-6 and 8-11; R4-01 and R4-02 closed; `linkage.sh` run" + BOTH + " |"),
             (RUNBOOK, "all after `linkage.sh`'s run; not the lawyer's review", BOTH),
             (RUNBOOK, "which your request names;", " *(24 October 2026: the R4-01 and R4-02 fix is done"),
             (RUNBOOK, "and after `linkage.sh`'s run, which its ADR-0014 items 4, 5 and 9 wait for", BOTH)],
      "the runbook's notes: Session 10's two paragraphs and three cells, run 1, 0.3's step 5 and run 12")
group("Z8", [(INDEX, "(in practice before Session 10's security sign-off, and so before the M0 exit: its open items).",
              " *(24 October 2026: both closed by an agent's change at the M0 exit preparation"),
             (INDEX, "which raised OWN5-01 to OWN5-06)", " *(closed by an agent's change on 24 October 2026"),
             (A04, "(two routes around that rule are still open: ADR-0014, review round 4, R4-01 and R4-02)", NOTE),
             (A15, "which has two open routes around it (ADR-0014 review round 4, R4-01 and R4-02)", NOTE),
             (A15, "only once ADR-0014's R4-01 and R4-02 are closed (below)", NOTE),
             (A15, "before any product target links Readium if that comes first.", NOTE),
             (A02, "which the exception does not cover.", " *(24 October 2026: pull request #6 made the merge"),
             (A02, "Section 7, item 5 recommends)", " *(24 October 2026: R4-01 and R4-02 closed by an agent's change"),
             (PLAN, "if that comes first (Section 23.2)", NOTE),
             (PLAN, "before any product target links Readium if that comes first", NOTE),
             (PLAN, "any product target links Readium; security accepts the residual risk.", NOTE),
             (AMEND, "has two open routes around it (ADR-0014 review round 4, R4-01 and R4-02)", NOTE),
             (AMEND, "and its Status (review round 4, R4-01 and R4-02)", NOTE)],
      "the other records that called R4-01 and R4-02 open")
group("Z9", [(LOG, "**A `--no-env` in `Scripts/lib/xcodegen.sh`,** recommended, not needed by the guard: requested, and "
                   "not applied at the assembly (section 30.2)."),
             ("Scripts/lib/xcodegen.sh", "(cd \"$dir\" && xcodegen generate --quiet)")],
      "the recommended --no-env: declined with its reason, the script unchanged")

print("== The reviews branch's requests (m0-exit-reviews; integration log 30.2)")
group("R1", [(A14, "- **Review record:** the deps item's author, review and fix rounds, handed over on 24 October 2026"),
             (A14, "Appendix C; ADR-0001 (toolchain), ADR-0002 (pinning rules)\n- **Review record:**")],
      "ADR-0014's header line, after its Plan references")
group("R2", [(GATE, "or have it recorded that they are lost (Section 6.2, last row); at run 1.",
              " *(Dated note, 24 October 2026: handed over on branch `m0-exit-reviews` (`480d1757`, logs `2c5b2fcc`)"),
             (GATE, "(ADR-0014's added at the assembly of the M0 exit preparation). Every final round reviewed the "
                    "commit that was merged.")],
      "item 4's note on the final-review records")
group("R3", [(GATE, "| The thirteen M0 items' own final reviews | 91 in the final rounds: the deps item's R4-01 and R4-02 "
                    "(major, Section 6.1) and 89 minor;"),
             (GATE, "until 24 October 2026 this row said they were held outside the repository, in the workflow "
                    "journals |")],
      "Section 6.2's last row")
group("R4", [(GATE, "in `evidence/M0-Decisions/stage0/build-mac-state.log`.",
              " *(Dated note, 24 October 2026: the final review of `m0-int-minors-g05-ai`, round 8, found"),
             (GATE, "are yours to delete (Section 5.2), but not with the command `G05-AI.md` gives")],
      "Section 5.2's R8-04 note and item 4's build-Mac bullet")
group("R5", [(GATE, "are in the gate reports or recorded as lost (item 4).", IN),
             (GATE, "and the M0 exit review, once the final-review records are in or recorded as lost.", IN),
             (GATE, "the thirteen M0 items' final-review records handed over or recorded as lost", IN),
             (GATE, "and the final-review records in, by a pointer in each report or record to its item's record: "
                    "item 4.)*"),
             (GATE, "and the records in, by a pointer in each report or record to its item's record: item 4)*")],
      "the gate summary's notes that the records are in")
group("R6", [(GATE, "with mutations M63-M77 (`evidence/G05-AI/mutation-checks.log`: 77 of 77 caught).",
              " *(Dated note, 24 October 2026: the twelve items' final rounds, as handed over, raised no blocker"),
             (GATE, "nor has the M0 exit preparation of 24 October 2026 (Sections 6.2 and 8)."),
             (GATE, "the M0 exit preparation of 24 October 2026 (the Zip guard's fix, the review records' hand-over, "
                    "their assembly and this summary's updates with it: items 104-109; Section 8)"),
             (GATE, "- **The thirteen M0 items' review records, handed over (24 October 2026; integration log section "
                    "29).**"),
             (GATE, "`m0-exit-reviews`, assembled on `m0-exit-prep`, where these records now stand."),
             (GATE, "no review at all, nor has the M0 exit preparation of 24 October 2026 (sections 28-30)")],
      "Section 6.1's note, and the hand-over in the State line, Section 7, item 5, and Section 8")
group("R7", [(LOG, "## 29. The thirteen M0 items' review records, handed over (24 October 2026)"),
             (LOG, "### 29.4 Checks"),
             (LOG, "No path is changed by two items (`assembly-path-overlap.log`).",
              " *(Dated note, 24 October 2026: each item's review records, its final round's findings among them, are "
              "now in `evidence/M0-Integration/item-reviews/`; every final round reviewed the final commit this table "
              "gives: section 29.)*")],
      "integration log section 29 (requested as 28, which the Zip guard's entry took), and 7.1's note")
group("R8", [(README, "handed over: [evidence/M0-Integration/item-reviews/](evidence/M0-Integration/item-reviews/"
                      "README.md), section 29)"),
             (README, "and the fixes are agent-reviewed, human sign-off pending.",
              " *(24 October 2026: those findings, with every round of each M0 item, are in")],
      "the Stage 0 README's lines 5 and 26")
group("R9", [(RUNBOOK, "are in or recorded as lost (run 1).", HANDED),
             (RUNBOOK, "says where they are expected).", HANDED)],
      "the runbook's two notes")
group("R10", [(INDEX, "On 24 October 2026 it gained one header line pointing to its item's review record, and dated notes "
                      "where it called R4-01 and R4-02 open (agent-written, not reviewed)."),
              (INDEX, "On 24 October 2026 it gained one header line pointing to its item's review record (agent-written, "
                      "not reviewed) | M0 integration (contract consolidation) |")],
      "the ADR index's rows 0015 and 0016")

print("== What the assembly recorded besides the requests")
group("X", [(A01, "technical-lead confirmation pending the M0 gate.",
             " *(24 October 2026: Apple's pages, read by the orchestrating session that day and relayed"),
            (A01, "At the M0 exit preparation (24 October 2026), as relayed:"),
            (A01, "(Added on 20 October 2026: the review of the re-pin round, TC-01. Still open on 22 October 2026: "
                  "approving PO-35 as recommended did not read the notes.)",
             " *(24 October 2026: Apple's pages were read by the orchestrating session that day and relayed"),
            (GATE, "as you confirmed (Section 5.2).", " *(24 October 2026: the orchestrating session read Apple's "
                                                       "pages that day and relayed them"),
            (GATE, "Xcode 27.1 Release Notes, not beta release notes"),
            (GATE, "108. **Apple's pages for Xcode 27.1**"),
            (INDEX, "confirmation is pending the M0 gate.", " *(24 October 2026: Apple's pages, read by the "
                                                         "orchestrating session and relayed"),
            ("Docs/Stage0/evidence/M0-ExitPrep/assembly/xcode-27.1-release.md", "## As relayed")],
      "Apple's pages for Xcode 27.1, as relayed, in ADR-0001, the gate summary and the ADR index; the confirmation pending")
CL = "*(Dated note, 24 October 2026: corrected at the owner's request by the orchestrating session, `5aec2518`"
group("C", [(GATE, "still naming `m0-integrate`.", " *(Done on 24 October 2026, at your request, by the orchestrating "
                                                   "session: `5aec2518`"),
            (GATE, "Otherwise, stay on `m0-decisions`.", " *(Done: pull request #6 merged `m0-decisions` into `main`"),
            (GATE, "as your decisions left them.", " *(24 October 2026: pull request #6 merged `m0-decisions` into "
                                                  "`main` (step 3)"),
            (GATE, "which names `m0-decisions`.", " *(Dated note, 24 October 2026: changed at your request"),
            (GATE, "(Section 1, item 1).", " *(Dated note, 24 October 2026: changed at your request that day: item "
                                          "104.)*"),
            (GATE, "Section 7, item 5)", " *(HON-11: corrected at your request on 24 October 2026, `5aec2518`"),
            (GATE, "now in Section 1, item 1", " *(corrected at your request on 24 October 2026: item 104)*"),
            (GATE, "never into `main`\".", " *(Dated note, 24 October 2026: corrected at your request"),
            (GATE, "104. **`CLAUDE.md`'s milestone paragraph, corrected at your request**"),
            (GATE, "- **You, before Session 0: the branch the sessions use, now that `CLAUDE.md` is corrected.**"),
            (RUNBOOK, "gives a wording).", " *(24 October 2026: corrected at your request by the orchestrating "
                                          "session, `5aec2518`"),
            (RUNBOOK, "so that a merge into `main` carries it.", " *(Done on 24 October 2026, at your request"),
            (RUNBOOK, "Otherwise stay on `m0-decisions`.", " *(Done: pull request #6, merge commit `96bdc7e9`"),
            (SESSIONS, "the App Store's automatic updates are off", ". *(24 October 2026: (2) made at your request"),
            (README, "which still names `m0-integrate`", " *(corrected at the product owner's request on 24 October "
                                                        "2026, `5aec2518`"),
            (LOG, "its finding HON-11.)*", " " + CL),
            (LOG, "`CLAUDE.md` itself points agents to the Stage 0 README, which names `m0-decisions`",
             " *(corrected at the owner's request on 24 October 2026: section 30)*"),
            (LOG, "(gate summary, Section 7, item 5, with a wording).", " " + CL),
            (LOG, "with the wording updated for answer 1", " *(corrected at the owner's request on 24 October 2026: "
                                                         "section 30)*"),
            (LOG, "now before any agent request at run 1.", " " + CL),
            (LOG, "(FID4-02).", " " + CL),
            (LOG, "(the gate summary's Section 1, item 1, and Section 7, item 5).", " " + CL),
            (LOG, "HON-11 was not relayed this round)", " *(corrected at the owner's request on 24 October 2026"),
            (LOG, "before any merge of it into `main`.", " " + CL),
            (LOG, "(HON-11, still open);", " *(corrected at the owner's request on 24 October 2026: section 30)*"),
            (LOG, "says where the owner commits the change. " + CL),
            (LOG, "still open; corrected at the owner's request on 24 October 2026: section 30)")],
      "CLAUDE.md's correction, 5aec2518, where the records gave it as still to do")
log = read(LOG)
group("C-count", [(LOG, "says where the owner commits the change. " + CL)] if log.count(
    "says where the owner commits the change. " + CL) == 4 else [(LOG, "four notes after 25.5-27.5's and 24.5's bullets")],
      "the four identical bullets of 24.5-27.5, each with its note")
group("A", [(LOG, "## 30. The M0 exit preparation assembled on `m0-exit-prep` (24 October 2026)"),
            (LOG, "### 30.2 The requests, and what became of each"),
            (GATE, "- **The M0 exit preparation (24 October 2026).**"),
            (GATE, "Recorded on 24 October 2026, at the M0 exit preparation (integration log sections 28-30):"),
            (GATE, "- **The assembly of the M0 exit preparation (24 October 2026; integration log section 30).**"),
            (README, "**Where M0 stands (24 October 2026).**"),
            (README, "On 24 October 2026 the M0 exit preparation assembled that work on `m0-exit-prep`")],
      "the round's own account: integration log section 30, the gate summary and the Stage 0 README")

print()
print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} group(s) not as stated)")
sys.exit(1 if problems else 0)
