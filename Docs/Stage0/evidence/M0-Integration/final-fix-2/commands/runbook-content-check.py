#!/usr/bin/env python3
"""Does the device runbook say what each checklist step says? (M0 final review round 2: evidence R2-01, owner
readability R6-01 and R6-02; the step-number check beside it is final-fix/commands/runbook-coverage.py.)

    python3 -I runbook-content-check.py <repository root> [<runbook file to check instead of Docs/Stage0/M0-device-runbook.md>]

Forward. Every step of the eight checklists (Docs/Stage0/device-checklists/, read by each file's own numbering, as
runbook-coverage.py reads it) is split into its markers, outside fenced code blocks: each text in double quotes (an
on-screen or log text the step expects, or a name the step uses) and each text in backticks that holds a log field
(an "=") or a count ("Test run with", "Executed", "read back on", "N tests"). Each marker must occur in the runbook,
compared with runs of whitespace made one space and curly quotes made straight. A marker that does not is a problem,
unless the runbook leaves that step's details to the checklist and says so where the step is (DEFERRED, each with the
runbook's words), or the marker is listed in NOT_CARRIED with the reason it is not carried.

Reverse. Every count the runbook states as an expected result ("Test run with N test(s)", "Executed N tests", "read
back on N", "pull the N result tables") must occur with the same number in a checklist, unless it is listed in
RUNBOOK_OWN with its reason. This catches a runbook that keeps a count the checklists no longer give.

Neither direction reads meaning: a paraphrase that changed what a step asks would pass. Read-only; standard library
only. Exit status 1 if any problem is printed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
RUNBOOK = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "Docs/Stage0/M0-device-runbook.md"
CHECKLISTS = ROOT / "Docs/Stage0/device-checklists"

# Steps whose expected values the runbook leaves to the checklist, saying so where the step is: (file, step) -> the
# runbook's words that say so (which must occur in the runbook, or the deferral itself is a problem).
DEFERRED = {
    ("G04-Audio.md", 1): "only the longest lists of expected values (G0.4 step 1.3's result tables, G0.5 AI step 9.2's strings) stay in the checklist",
    ("G05-AI.md", 9): "only the longest lists of expected values (G0.4 step 1.3's result tables, G0.5 AI step 9.2's strings) stay in the checklist",
}

# Markers of a checklist step that the runbook does not carry, each with the reason. Keyed by (file, step, marker).
NOT_CARRIED: dict[tuple[str, int, str], str] = {
    ("G02-Transfer.md", 8, "Download <title>"): "the runbook names the item it downloads (4.8: \"Download from inbox: large-5GiB\")",
    ("G02-Transfer.md", 8, "Download from inbox: <title>"): "the same: the runbook names the item",
    ("G02-Transfer.md", 13, "app_state=background_relaunch"): "a quotation of the simulator's events in the step's introduction; the runbook "
        "writes the expected result as the step does, `app_state=background` or `background_relaunch` (4.10)",
    ("G02-Transfer.md", 20, "No Accounts"): "the step's history of the failed signing attempts of 12 and 13 October 2026; the runbook "
        "states the build Mac's state instead (Section 1.5: no developer account in Xcode)",
    ("G02-Transfer.md", 23, "Spikes/G02-Transfer/Scripts/device-ats-probe.sh Docs/Stage0/evidence/G02-Transfer/device/23-ats-none.log "
        "none 'platform=iOS,name=<the iPhone>' -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z"):
        "the runbook's command targets the phone by its UDID, \"id=$DEVICE_ID\" (correction C1; 4.19)",
    ("G04-Audio.md", 9, "key=value"): "the checklist's description of the log format; the runbook names the fields to check (3.8)",
    ("G04-Audio.md", 9, "ranges="): "the same: a field named in that description, not an expected value",
    ("G04-Audio.md", 9, "origin=intent.control@..."): "the simulator's result quoted in the step's introduction; the runbook gives the "
        "device's expected origin in full (3.8)",
    ("G04-Audio.md", 12, "loaded=true played_since_load=false"): "the step's history: the simulator's line under the rule before review "
        "6; the runbook gives the rule and each field to check (3.11)",
    ("G04-Audio.md", 12, "nothing loaded"): "the step's history: the name of the rule review 6 replaced (3.11 gives the rule since)",
    ("G04-Audio.md", 15, "music uninterrupted during steps 2-4"): "the runbook names the parts (the copy, the launch and the captures) "
        "instead of the checklist's sub-step numbers (3.14)",
    ("G05-Recovery.md", 4, "Sylvia shows a safe unavailable state before first unlock (class-C files unreadable, no class lowered)"):
        "step 4.5, which can wait for the first milestone with an app shell (Section 7); 6.3 says it stays pending",
    ("G06-Design.md", 21, "API.EXAMPLE.CO / M"): "step 21 is the designer's review of the snapshot references, done from the checklist "
        "(Session 10)",
    ("G06-Design.md", 21, "Saved 2:02 PM"): "the same: a detail of the designer's review of the snapshot references",
}

# Counts the runbook states that no checklist gives, each with the reason. Keyed by the count's text. (Sections 8 and 9
# are records of corrections and checks as written at `471b143` and are not read by the reverse pass.)
RUNBOOK_OWN: dict[str, str] = {
    "pull the 35 result tables": "the number of file names in G0.4 step 1.2's pull loop, which the checklist lists without "
        "counting them; this check counts them (its first reverse line)",
}


def normalized(text: str) -> str:
    text = text.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text)


def without_code_blocks(text: str) -> str:
    return re.sub(r"^\s*```.*?^\s*```", " ", text, flags=re.M | re.S)


def checklist_steps(name: str) -> dict[int, str]:
    """Step number -> the step's text, by the file's own numbering (as runbook-coverage.py reads the numbers)."""
    text = (CHECKLISTS / name).read_text(encoding="utf-8")
    if name == "G02-Transfer.md":
        pattern = r"^### (\d+)\. "
    elif name in ("G04-Audio.md", "G05-AI.md", "G05-Recovery.md"):
        pattern = r"^## (\d+)\. "
    elif name in ("G01-EPUB.md", "G01-PDF.md"):
        pattern = r"^(\d+)\. \*\*"
    elif name == "G03-Intake.md":
        pattern = r"^(\d+)\. "
    else:
        pattern = r"^\| (\d+) \| "
    starts = [(m.start(), int(m.group(1))) for m in re.finditer(pattern, text, re.M)]
    if name == "G03-Intake.md":
        starts = [(s, n) for s, n in starts if n >= 6]
    steps: dict[int, str] = {}
    for i, (start, number) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
        heading = text.find("\n## ", start + 1)  # a section that follows the last step (Notes) is not the step's
        if heading != -1:
            end = min(end, heading)
        if name == "G06-Design.md":
            end = text.index("\n", start)  # one table row
        steps[number] = steps.get(number, "") + text[start:end]
    return steps


QUOTED = re.compile(r'(?<![\w"])"([^"\n]{3,300}?)"(?![\w"])')
TICKED = re.compile(r"`([^`\n]{3,300})`")
COUNT_LIKE = re.compile(r"=|Test run with|Executed \d|read back on|\b\d+ tests?\b")


def markers(step_text: str) -> list[str]:
    text = normalized(without_code_blocks(step_text))
    found = []
    for m in QUOTED.finditer(text):
        value = m.group(1)
        if value != value.strip() or "**" in value:
            continue  # a fragment between two quotations, not a quotation
        found.append(value)
    for m in TICKED.finditer(text):
        if COUNT_LIKE.search(m.group(1)):
            found.append(m.group(1))
    return sorted(set(found))


RUNBOOK_COUNTS = re.compile(r"Test run with \d+ tests? in \d+ suites?|Executed \d+ tests|read back on \d+ files and directories"
                            r"|pull the \d+ result tables")


def main() -> int:
    runbook = RUNBOOK.read_text(encoding="utf-8")
    rb = normalized(runbook)
    problems = 0
    print(f"runbook: {RUNBOOK.relative_to(ROOT) if RUNBOOK.is_relative_to(ROOT) else RUNBOOK}")
    print("== forward: each checklist step's quoted texts and counted values, in the runbook")
    used_not_carried = set()
    for path in sorted(CHECKLISTS.glob("*.md")):
        steps = checklist_steps(path.name)
        checked = carried = deferred = listed = 0
        missing = []
        for number, text in sorted(steps.items()):
            deferral = DEFERRED.get((path.name, number))
            if deferral and normalized(deferral) not in rb:
                print(f"PROBLEM {path.name} step {number}: listed as left to the checklist, but the runbook no longer says so")
                problems += 1
            for marker in markers(text):
                checked += 1
                if marker in rb:
                    carried += 1
                elif deferral:
                    deferred += 1
                elif (path.name, number, marker) in NOT_CARRIED:
                    listed += 1
                    used_not_carried.add((path.name, number, marker))
                else:
                    missing.append((number, marker))
        print(f"{path.name}: {len(steps)} steps, {checked} markers: {carried} in the runbook, {deferred} in steps left to "
              f"the checklist, {listed} listed as not carried, {len(missing)} missing")
        for number, marker in missing:
            print(f"  MISSING step {number}: {marker[:200]}")
        problems += len(missing)
    for key in sorted(set(NOT_CARRIED) - used_not_carried):
        print(f"PROBLEM stale NOT_CARRIED entry (the marker is in the runbook now, or no longer in its step): {key}")
        problems += 1

    print("== reverse: each count Sections 1-7 of the runbook state, in a checklist")
    checklists = normalized(" ".join(p.read_text(encoding="utf-8") for p in sorted(CHECKLISTS.glob("*.md"))))
    sessions = normalized(runbook.split("\n## 8. ")[0])
    seen = set()
    loop = re.search(r"for t in (.*?); do", (CHECKLISTS / "G04-Audio.md").read_text(encoding="utf-8"), re.S)
    tables = len(re.findall(r"\b[\w.-]+\.(?:txt|tsv)\b", loop.group(1))) if loop else 0
    stated = re.search(r"pull the (\d+) result tables", sessions)
    if stated and int(stated.group(1)) != tables:
        print(f"PROBLEM the runbook says {stated.group(0)}, and G0.4 step 1.2's loop names {tables}")
        problems += 1
    elif stated:
        print(f"  ok   {stated.group(0)}: G0.4 step 1.2's loop names {tables} tables")
    for m in RUNBOOK_COUNTS.finditer(sessions):
        count = m.group(0)
        if count in seen:
            continue
        seen.add(count)
        if count in checklists:
            print(f"  ok   {count}")
        elif count in RUNBOOK_OWN:
            print(f"  own  {count}: {RUNBOOK_OWN[count]}")
        else:
            print(f"  STALE {count}: in no checklist")
            problems += 1
    print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
