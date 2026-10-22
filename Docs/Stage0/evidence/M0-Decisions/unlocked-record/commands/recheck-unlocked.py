#!/usr/bin/env python3
"""Checks the record of G0.5 recovery's whole drop-in run with the screen unlocked (22 October 2026, 22:36-22:44 UTC, 23
October on the build Mac's clock, on 9cdb0a02; its evidence committed in 35543102; integration log section 25). Every
record that, before it, called that run pending, still to run or the product owner's to make in Session 0 (runbook
0.8), or said that no run of the whole drop-in had passed since the drop-in gained the lock harness's steps on 22
October 2026, must now record the run: the text that said otherwise gone from where the owner reads it, and the record
of the run present, naming 9cdb0a02 or the run's evidence folder. Where a record keeps the earlier text as history (a
dated note, or an item of the gate summary's Section 6.3), the check asserts that the history is still there and that a
dated note follows it. Each record is read where the owner reads it: the gate summary's items and sections, the
runbook's header, run 2, 0.8, its Section 2 table and its Section 7 row, the session log, the G0.5 recovery report,
ADR-0012, ADR-0015 and the ADR index, the Stage 0 README, the evidence READMEs of the assembly and of the fourth fix,
and the integration log. The run's own facts are checked in its evidence by check-run.py beside this file.

    python3 -I Docs/Stage0/evidence/M0-Decisions/unlocked-record/commands/recheck-unlocked.py <repository root>

Run on the tree of 35543102 (git archive), the commit this record starts from, it must report every record; the gate
checks of this record (gate-checks.sh beside this file) run that control. Read-only; standard library only; host only.
Prints one line per record and exits 1 if any record is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0
records = 0


def read(path):
    p = ROOT / path
    return p.read_text(encoding="utf-8") if p.is_file() else ""


def line_with(text, start):
    found = [l for l in text.splitlines() if l.startswith(start)]
    return found[0] if len(found) == 1 else ""


def block(text, start, end):
    lines = text.splitlines()
    first = [i for i, l in enumerate(lines) if l.startswith(start)]
    if len(first) != 1:
        return ""
    rest = [i for i in range(first[0] + 1, len(lines)) if lines[i].startswith(end)]
    return "\n".join(lines[first[0]:rest[0] if rest else len(lines)])


def check(where, text, need=(), gone=(), kept=(), extra=()):
    """need: the record of the run; gone: the text that called it pending; kept: history that must stay, with the
    dated note that follows it; extra: other problems found by the caller."""
    global problems, records
    records += 1
    m = [] if text else ["not found"]
    m += [f"lacks: {p}" for p in need if p not in text]
    m += [f"still says: {p}" for p in gone if p in text]
    m += [f"lacks the history with its note: {p}" for p in kept if p not in text]
    m += list(extra)
    if m:
        problems += 1
    print(f"{'recorded' if not m else 'PROBLEM '} {where}" + (f" ({'; '.join(m)})" if m else ""))


gate = read("Docs/Stage0/M0-gate.md")
runbook = read("Docs/Stage0/M0-device-runbook.md")
sessions = " ".join(read("Docs/Stage0/evidence/M0-runbook/sessions.md").split())
report = read("Docs/Stage0/G05-Recovery.md")
a12 = read("Docs/ADRs/0012-retention-backup-restore.md")
a15 = read("Docs/ADRs/0015-threat-model.md")
index = read("Docs/ADRs/README.md")
stage0 = read("Docs/Stage0/README.md")
assembly = read("Docs/Stage0/evidence/M0-Decisions/assembly/README.md")
round5 = read("Docs/Stage0/evidence/M0-Decisions/followup/round-5/README.md")
log = read("Docs/Stage0/integration-log.md")
SEEN = "`9cdb0a02`"

# The gate summary.
check("M0-gate.md item 2 (repeat 0.8 after a fix of the harness)", line_with(gate, "**2. The device sessions**"),
      [f"changes the harness or the drop-in after {SEEN}, the commit 0.8's run was made on (item 4)"],
      ["if a fix changes the harness after your 0.8 run"])
check("M0-gate.md Section 1's table, run 2", line_with(gate, "| 2 | 0 · At the Mac |"),
      [f"G0.5 recovery's CI step with the screen unlocked passed in an agent's run on {SEEN}"],
      ["and G0.5 recovery's CI step run once with the screen unlocked"])
check("M0-gate.md item 4, the build Mac", line_with(gate, "- **The build Mac:**"),
      [f"The drop-in run below was made on {SEEN} and passed"], ["are yours to delete (Section 5.2); and the drop-in run below."])
check("M0-gate.md item 4, the drop-in run", line_with(gate, "**The drop-in run.**"),
      [f"Made, and passed, on {SEEN}; yours again only if its code changes.",
       "`evidence/M0-Decisions/assembly/unlocked-run-1/console.log`", "so 0.8 needs nothing from you now",
       "commit the folder on `m0-decisions` (item 1, step 6)", "(Its history: Section 6.3, item 92.)"],
      ["In Session 0 (runbook 0.8), at the build Mac with its screen unlocked and on the commit of item 1, run G0.5 "
       "recovery's drop-in once", "an agent can then update the records that call the run pending"])
check("M0-gate.md Section 1, whether each gate met its criteria", line_with(gate, "**Did each gate meet its criteria?**"),
      [f"until a run from clean on {SEEN} found the screen unlocked"],
      ["and no run of the whole drop-in has passed since: those steps passed alone"])
check("M0-gate.md Section 2.10, the run of 19 October 2026",
      line_with(gate, "- **G0.5 recovery on the current code, with its class-B readback (19 October 2026"),
      ["which no run of the whole drop-in had then passed, so 0.8 was to run it once more"],
      ["which no run of the whole drop-in has passed since, so 0.8 runs it once more"])
check("M0-gate.md Section 2.10, Xcode 27.1", line_with(gate, "- **Xcode 27.1 on the build Mac, and the pin since 20 October"),
      [f"the whole drop-in has passed on that code once, from clean with the screen unlocked, on {SEEN}"],
      ["and no run of the whole drop-in has passed on that code (the last bullet of this section)"])
check("M0-gate.md Section 2.10, the lock harness's runs", line_with(gate, "- **G0.5 recovery with the lock harness (22 "),
      ["**With the screen unlocked, the whole drop-in passed (22 October 2026, 22:36:32-22:44:05 UTC; 23 October, "
       "11:36-11:44, on the build Mac's clock).**",
       "`evidence/M0-Decisions/assembly/unlocked-run-1/71-g05-recovery.log`",
       "`evidence/M0-Decisions/unlocked-record/gate-checks.log`, part 1", "runbook 0.8 is done for it"],
      ["A run of the whole drop-in with the screen unlocked is pending;",
       "The run with the screen unlocked is runbook 0.8, in Session 0 (Section 1, item 4)."],
      ["stopped at its row-10 guard each time it ran, after its 73 host tests passed, because the build Mac's screen "
       "was locked", "the whole drop-in from clean on `08062446` stopped at its guard again"])
check("M0-gate.md Section 4.1, PO-23", line_with(gate, "| PO-23 |"),
      [f"passed with the build Mac's screen unlocked in an agent's run on {SEEN}"],
      ["and so is a run of the whole G0.5 recovery drop-in"])
check("M0-gate.md Section 5.1, its opening",
      line_with(gate, "`M0-device-runbook.md` puts every pending checklist step into sessions"),
      [f"from an agent's run on {SEEN} with the screen unlocked, which passed every step"],
      ["and runs the drop-in once more for the steps it gained on 22 October 2026"])
check("M0-gate.md Section 5.1, the G0.5 recovery row", line_with(gate, "| G0.5 recovery | 1-4 on B"),
      [f"passed from clean with the screen unlocked in an agent's run on {SEEN}",
       "`evidence/M0-Decisions/assembly/unlocked-run-1/logs/host-tests.log`"],
      ["and no run of the whole drop-in has passed since, so 0.8 runs it once more, before Session 6 (Section 2.10)."])
check("M0-gate.md Section 6.2, the review of the decisions round",
      line_with(gate, "| The review of the decisions round (22 October 2026, at `88d4e1c7`) |"),
      [f"passed in an agent's run on {SEEN} on 22 October 2026 UTC: item 92"],
      ["the whole G0.5 recovery drop-in with the screen unlocked, is runbook 0.8)"])
items = [line_with(gate, "35. **The lock harness**"), line_with(gate, "42. **The lock harness**")]
kept_note = ("the whole drop-in with the screen unlocked is still to run (Section 2.10; runbook 0.8). *(Dated note, 23 "
             f"October 2026: it ran, and passed, on {SEEN}: item 92.)*")
check("M0-gate.md items 35 and 42, each with its dated note", "\n".join(items) if all(items) else "", [], [], [],
      [f"item {n} lacks the history with its note: {kept_note}" for n, item in zip((35, 42), items) if kept_note not in item])
check("M0-gate.md Section 6.3, items 92 and 93", gate,
      ["Recorded on 23 October 2026, after G0.5 recovery's whole drop-in passed with the screen unlocked (each recorded "
       "in integration log section 25):", "92. **The drop-in run with the screen unlocked** (a run, not a review finding)",
       "93. **Not reviewed**: this record is agent-written"])
check("M0-gate.md Section 7, item 5", block(gate, "## 7. Recommendation", "## 8. "),
      ["the record of G0.5 recovery's whole drop-in run with the screen unlocked (Section 6.3, item 92)"])
check("M0-gate.md Section 8", block(gate, "## 8. About this summary", "## 9. "),
      ["- **The record of G0.5 recovery's whole drop-in run with the screen unlocked (23 October 2026; integration log "
       "section 25).**", "`evidence/M0-Decisions/unlocked-record/commands/gate-checks.sh`",
       f"it passed on {SEEN}, with the screen unlocked, on 22 October 2026 UTC: Section 6.3, item 92",
       "and the record of G0.5 recovery's whole drop-in run with the screen unlocked (section 25) included"],
      ["while G0.5 recovery's whole drop-in has not passed on the current code (Section 2.10)."])

# The runbook.
check("the runbook's header", line_with(runbook, "- **Nothing in this runbook has been run on a device.**"),
      [f"passed from clean in an agent's run on {SEEN} with the screen unlocked",
       "so 0.8 asks you to run it again only if what it builds changes after that commit"],
      ["and no run of the whole drop-in has passed since, so 0.8 asks you to run it once more ("])
check("the runbook's Who wrote it", line_with(runbook, "- **Who wrote it.**"),
      ["to record the agent's run of the whole G0.5 recovery drop-in with the screen unlocked (0.8; section 25)"])
check("the runbook's Section 2, where records go", line_with(runbook, "| G0.5 recovery | `Docs/Stage0/evidence/G05-Recovery/device/`"),
      ["(the agent's run of 22 October 2026 UTC is in `Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1/`)"])
check("the runbook's run 2", line_with(runbook, "| 2 | 0 Mac setup |"),
      [f"only if what it builds has changed since {SEEN}", f"passed in an agent's run on {SEEN}"],
      ["has not passed since) |", "G0.5 recovery's drop-in, once, with the screen unlocked"])
check("the runbook's 0.8", block(runbook, "**0.8 ", "**0.9 "),
      [f"*The whole drop-in, with the lock harness's steps, passed on {SEEN}", "**So 0.8 needs nothing from you now.",
       f"only if a commit you build from changes what the drop-in builds, copies or runs after {SEEN}**",
       "`evidence/M0-Decisions/assembly/unlocked-run-1/console.log`", "Expect: the last line reads `drop-in exit 0`",
       "committed on `m0-decisions` (0.3, step 6); update row 10 to cite it"],
      ["**Run it once more now, as below, before Session 6.**",
       "so this run is the first of the whole drop-in on the current code",
       "have the records that call the whole drop-in's run on the current code pending say it ran"])
check("the runbook's Section 7, G0.5 recovery", line_with(runbook, "| G0.5 recovery | 1-4; review row 23;"),
      [f"the whole drop-in passed on {SEEN}, 0.8, and runs again only if what it builds changes"],
      ["the whole drop-in run once more, 0.8, before Session 6"])

# The session log, the report, the ADRs, the READMEs and the integration log.
check("the session log", sessions,
      [f"a waiter of the orchestrating session ran the whole drop-in from clean on {SEEN} with the screen unlocked, at "
       "22:36-22:44 UTC that day (23 October on the build Mac's clock). Both passed",
       "| 2 (0.8 only, ahead of the session) | 0 Mac setup, step 0.8: the whole drop-in, its steps 13-15 for the lock "
       f"harness included | 2026-10-22, 22:36-22:44 |", f"0.8 again only if what the drop-in builds, copies or runs "
       f"changes after {SEEN} (runbook 0.3, step 7) |"],
      ["no run of the whole drop-in has passed since, so 0.8 is to be run once more, in Session 0 (runbook 0.8)"],
      ["| 2 (0.8 only, ahead of the session) | 0 Mac setup, step 0.8 | 2026-10-19, 15:14-15:20 |"])
check("G05-Recovery.md, the lock harness paragraph", line_with(report, "**The lock harness (22 October 2026;"),
      ["*(23 October 2026, integration log section 25: after the second fix's whole drop-in also stopped at the guard",
       "`Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1/console.log`"],
      [], ["A run of the whole drop-in with the screen unlocked is still pending: runbook 0.8 asks the owner for it.)* "
           "*(23 October 2026"])
check("G05-Recovery.md row 10", line_with(report, "| 10 | Data protection class set in code and read back"),
      ["`Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1/logs/host-tests.log`",
       "runbook 0.8 is done for the code with the lock harness's steps"])
check("ADR-0012, the security reviewer's open item", line_with(a12, "- Security reviewer: approve class C"),
      [f"which passed with the screen unlocked on {SEEN} that day, runbook 0.8"],
      ["the whole drop-in run once more with the screen unlocked"])
check("ADR-0015, the open item on the host run", line_with(a15, "- Host run of `Scripts/ci.d/71-g05-recovery.sh`"),
      ["*(23 October 2026, integration log section 25: done for the code with the lock harness's steps.",
       "`M0-Decisions/assembly/unlocked-run-1/logs/host-tests.log`"],
      [], ["so the device runbook's 0.8 has it run once more with the screen unlocked.)* *(23 October 2026"])
check("ADR-0015's status line", line_with(a15, "- **Status:** Proposed. Security review"),
      ["Revised again the same day by the record of G0.5 recovery's whole drop-in run with the screen unlocked "
       "(integration log section 25)"])
check("the ADR index, ADR-0015", line_with(index, "| [0015](0015-threat-model.md) |"),
      [f"records the whole drop-in's run with the screen unlocked on {SEEN}, which passed (not reviewed)"])
check("the Stage 0 README", stage0,
      ["G0.5 recovery's whole drop-in, the lock harness's steps included, passed from clean with the build Mac's screen "
       f"unlocked, in a run that a waiter of the orchestrating session started on {SEEN}",
       "and with the run of G0.5 recovery's whole drop-in with the screen unlocked, section 25)"])
check("the assembly's evidence README", assembly,
      ["| `unlocked-run-1/` | Added after the assembly (23 October 2026; integration log section 25)"])
check("the fourth fix's evidence README", round5,
      [f"*dated note, 23 October 2026: a waiter of the orchestrating session ran it after this fix, on {SEEN}"],
      [], ["(no code changed; it stays the runbook's 0.8, for the owner; *dated note"])
check("the integration log, section 25 and 24.5's note", log,
      ["## 25. G0.5 recovery's whole drop-in with the screen unlocked, and its record (23 October 2026)",
       f"*(Dated note, 23 October 2026: a waiter of the orchestrating session ran it after this fix, on {SEEN}, the "
       "fix's last commit, with the screen unlocked, and it passed: section 25.)*"],
      [], ["Not run: no code changed since `660c2b3a`, and it stays the runbook's 0.8, for the owner, in Session 0. "
           "*(Dated note, 23 October 2026"])

# No record left that still tells the owner to run the whole drop-in once more as things stand now.
stale = re.compile(r"no run of the whole drop-in has passed since|run it once more now|0\.8 runs it once more|"
                   r"the whole drop-in run once more|0\.8 is to be run once more")
left = []
for name, text in (("M0-gate.md", gate), ("the runbook", runbook), ("the session log", sessions),
                   ("ADR-0012", a12), ("the Stage 0 README", stage0)):
    for hit in stale.finditer(text):
        left.append(f"{name}: ...{text[max(0, hit.start() - 60):hit.end()]}")
records += 1
if left:
    problems += 1
print(f"{'recorded' if not left else 'PROBLEM '} no present-tense request to run it once more in the gate summary, the "
      "runbook, the session log, ADR-0012 or the Stage 0 README" + (f" ({'; '.join(left)})" if left else ""))

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of {records} records not as stated)")
sys.exit(1 if problems else 0)
