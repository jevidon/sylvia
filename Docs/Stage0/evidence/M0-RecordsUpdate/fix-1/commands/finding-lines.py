#!/usr/bin/env python3
"""The review of m0-records-update, its fidelity findings FID-RU-01 to FID-RU-11 (26 October 2026; integration log
section 42): does every line they cite hold the text they quote at 832a3636, the commit the review read, and do their
claims about other commits hold? Read-only, with git (`git show <commit>:<path>`, `git show --stat`, `git log`); the
findings as relayed are in ../relayed-findings.md. Where a finding quotes loosely, the check reads the exact text and
says so. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/commands/finding-lines.py
Prints one line per citation or claim and exits 1 if any does not hold.
"""
import subprocess
import sys

REVIEWED = "832a3636"
results = []


def git(*args):
    out = subprocess.run(["git", *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def line(commit, path, number):
    lines = git("show", f"{commit}:{path}").splitlines()
    return lines[number - 1] if 0 < number <= len(lines) else ""


def holds(finding, label, ok, detail=""):
    results.append(ok)
    print(f"{'ok  ' if ok else 'FAIL'} {finding} {label}" + (f" ({detail})" if detail else ""))


def cites(finding, commit, path, number, *texts, absent=()):
    text = line(commit, path, number)
    missing = [t for t in texts if t not in text]
    present = [t for t in absent if t in text]
    holds(finding, f"{commit}:{path}:{number}", not missing and not present,
          "; ".join(["lacks: " + t[:90] for t in missing] + ["has: " + t[:90] for t in present]))


RB, GATE = "Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/M0-gate.md"
print(f"reviewed commit: {git('rev-parse', REVIEWED).strip()}")
print()

# FID-RU-01
cites("FID-RU-01", REVIEWED, RB, 210, "Record: commit the regenerated log on `m0-sessions` (0.3, step 6; until 24 October "
      "2026 this said `m0-decisions`)")
cites("FID-RU-01", "c72247a6", RB, 207, "Record: commit the regenerated log on `m0-decisions` (0.3, step 6); update the "
      "G0.2 row.")
cites("FID-RU-01", "1d5ac477", RB, 209, "Record: commit the regenerated log on `m0-sessions`")
cites("FID-RU-01", REVIEWED, RB, 221, "committed on `m0-decisions` (0.3, step 6; from 24 to 26 October 2026 this said "
      "`m0-sessions`)")
cites("FID-RU-01", REVIEWED, RB, 1011, "from 24 to 26 October 2026 this paragraph said `m0-sessions`, twice")
setup = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-runbook/2026-10-26-setup.txt")
holds("FID-RU-01", "the owner's setup record: 0.7's Keychain test not run",
      "The Keychain test itself has NOT run; this is not a pass for step 0.7." in setup)
cites("FID-RU-01", REVIEWED, GATE, 774, "the runbook's header, Section 2, 0.7, 0.8 and Section 6")
item178 = line(REVIEWED, GATE, 839)
runbook_list = item178[item178.find("the runbook (its header"):][:400]
holds("FID-RU-01", f"{REVIEWED}:{GATE}:839 item 178's list of the runbook's parts names 0.3 and 0.8, not 0.7",
      item178.startswith("178. ") and "0.3, 0.8" in runbook_list and "0.7" not in runbook_list, runbook_list[:160])
in_merge = line("4c0fa815", RB, 210)
holds("FID-RU-01", "the merge 4c0fa815 took m0-sessions's 0.7", "commit the regenerated log on `m0-sessions`" in in_merge)
in_fix = line("d1fb3dd4", RB, 210)
holds("FID-RU-01", "d1fb3dd4 left it", "commit the regenerated log on `m0-sessions`" in in_fix)

# FID-RU-02
cites("FID-RU-02", REVIEWED, GATE, 466, "The same holds for the records and evidence of your sessions, committed on "
      "`m0-sessions` (Section 1, item 1, step 6). Not needed for the exit: until you say so, build from `m0-sessions`.")
cites("FID-RU-02", "c72247a6", GATE, 459, "which you commit on `m0-decisions`", "until you say so, build from "
      "`m0-decisions`")
cites("FID-RU-02", REVIEWED, GATE, 482, "**The branch the sessions use: `m0-decisions`, as the runbook said, settled on 26 "
      "October 2026.**")
cites("FID-RU-02", REVIEWED, GATE, 16, "1. **Done: `~/Git/sylvia-sessions` is on `m0-decisions`**")
cites("FID-RU-02", REVIEWED, GATE, 21, "6. **Your session records, committed on `m0-decisions`.**")

# FID-RU-03
claude = line(REVIEWED, "CLAUDE.md", 5)
holds("FID-RU-03", f"{REVIEWED}:CLAUDE.md:5 is 6cede84a's paragraph",
      claude == line("6cede84a", "CLAUDE.md", 5) and "Since 24 October 2026 the M0 work is on `m0-sessions`" in claude
      and "Further M0 work goes on a branch of its own made from `m0-sessions`" in claude
      and "Never build on `m0-integrate` or `m0-decisions`: both are behind `main`." in claude)
owner = line("c72247a6", "CLAUDE.md", 5)
holds("FID-RU-03", "c72247a6:CLAUDE.md:5 holds the paragraph of 22 October 2026 (d076f6fe's)",
      owner == line("d076f6fe", "CLAUDE.md", 5) and "are combined on `m0-integrate`" in owner
      and "m0-sessions" not in owner)
for commit in ("5aec2518", "6cede84a"):
    message = git("log", "-1", "--format=%B", commit)
    holds("FID-RU-03", f"{commit}'s message records the owner's request of 24 October 2026",
          "asked the orchestrating session" in message or "at the owner's request" in message
          or "owner asked" in message.lower(), message.splitlines()[0])

# FID-RU-04
cites("FID-RU-04", REVIEWED, GATE, 122, "the M0 work continues on `m0-sessions`, made from `main` that day")
cites("FID-RU-04", REVIEWED, GATE, 471, "ADR-0001 records the same evidence on `m0-exit-prep`, merged into `m0-sessions` "
      "once reviewed")
cites("FID-RU-04", REVIEWED, GATE, 556, "the sessions build from `m0-sessions`.)*")
cites("FID-RU-04", REVIEWED, "Docs/Stage0/README.md", 41, "*(26 October 2026: the M0 work continues on `m0-decisions`, "
      "the product owner's session branch, and `m0-sessions` is retired;")

# FID-RU-05
for path in ("Docs/ADRs/0003-persistence.md", "Docs/ADRs/0005-pdf-reading-and-anchors.md",
             "Docs/ADRs/0007-quick-capture-evaluation.md", "Docs/ADRs/0009-transfer-protocol.md",
             "Docs/ADRs/0010-intake-handoff-and-wired-bundles.md"):
    cites("FID-RU-05", REVIEWED, path, 3, "read the update it belongs to at `8082bdb6` (26 October 2026)",
          "and no review has accepted it")
cites("FID-RU-05", REVIEWED, "Docs/ADRs/0013-design-language.md", 3, "which has not been reviewed.")
cites("FID-RU-05", REVIEWED, "Docs/ADRs/README.md", 29, "the fix of whose fidelity findings is not reviewed",
      absent=("c2fd9ece",))
cites("FID-RU-05", REVIEWED, GATE, 4, "an agent review accepted the M0 exit preparation and the device-A records of the "
      "update of 24 October 2026, with minor findings, as relayed")
cites("FID-RU-05", REVIEWED, "Docs/ADRs/0001-platform-baseline-and-toolchain.md", 3, "that second review accepted the "
      "device-A records in its fidelity, accuracy and completeness lenses")
cites("FID-RU-05", REVIEWED, "Docs/ADRs/README.md", 17, "the second review of the device-A update, at `c2fd9ece`, "
      "accepted its records in three lenses, as relayed")
cites("FID-RU-05", REVIEWED, "Docs/Stage0/README.md", 5, "accepted the device-A records in its fidelity, accuracy and "
      "completeness lenses, with minor findings")
cites("FID-RU-05", REVIEWED, "Docs/Stage0/M0-plan-amendments.md", 5, "a second agent review of that update, at "
      "`c2fd9ece`, accepted its device-A records, this document's among them, in its fidelity, accuracy and "
      "completeness lenses")

# FID-RU-06
cites("FID-RU-06", REVIEWED, "Docs/Stage0/integration-log.md", 2385, "`4be1a1a4` also changed the runbook's device "
      "commands for the recovery suite, the G0.5 recovery checklist and report.")
stat = git("show", "--stat", "--format=", "4be1a1a4")
files = sorted(l.split("|")[0].strip() for l in stat.splitlines() if "|" in l)
holds("FID-RU-06", "git show --stat 4be1a1a4: the runbook, the G0.5 recovery checklist and four DeviceTests files, not "
      "the report", len(files) == 6 and "Docs/Stage0/M0-device-runbook.md" in files
      and "Docs/Stage0/device-checklists/G05-Recovery.md" in files and "Docs/Stage0/G05-Recovery.md" not in files
      and sum("DeviceTests" in f for f in files) == 4, ", ".join(files))
for commit in ("38f9604e", "d5336111"):
    changed = git("show", "--name-only", "--format=", commit).split()
    holds("FID-RU-06", f"{commit} changes the G0.5 recovery report", "Docs/Stage0/G05-Recovery.md" in changed)

# FID-RU-07
s7 = line(REVIEWED, GATE, 855)
first = s7.find("*(closed: the change of 24 October 2026, accepted by an agent review at `c3adae68`")
second = s7.find("*(answered by an agent's change on 24 October 2026, review pending, so a review that accepts it is "
                 "still to come")
holds("FID-RU-07", f"{REVIEWED}:{GATE}:855 the current note, then the older one", 0 <= first < second)
cites("FID-RU-07", REVIEWED, "Docs/ADRs/0002-repository-build-and-ci.md", 41, "The fix of R4-01 and R4-02 was made "
      "before the sessions, by an agent's change, review pending", absent=("c3adae68",))

# FID-RU-08
cites("FID-RU-08", REVIEWED, GATE, 10, "G0.4 step 1 still running")
status = git("show", f"{REVIEWED}:Docs/Stage0/evidence/G04-Audio/device/step-01-status.txt")
holds("FID-RU-08", "the owner's step-01-status.txt claims no result", "Full suite not complete. No result claimed." in
      status)

# FID-RU-09 (the gate summary's wording differs from the quotation: "two of them passing ... and two failing")
cites("FID-RU-09", REVIEWED, "Docs/Sylvia_v1_iOS_Implementation_Plan.md", 5, "Session 1's steps 1.1 to 1.3, two of "
      "which passed on the device and two failed")
cites("FID-RU-09", REVIEWED, GATE, 851, "have run Session 1's steps 1.1 to 1.3, two of them passing on the device and "
      "two failing")
cites("FID-RU-09", REVIEWED, GATE, 10, "G0.2 step 1 and G0.5 AI step 4 passed on the device, G0.5 AI step 1 and the "
      "recovery suite failed")

# FID-RU-10
cites("FID-RU-10", REVIEWED, "Docs/Stage0/device-checklists/G06-Design.md", 15, "(iOS 27.0.1 (24A446) since 26 "
      "October 2026; 26.7 until then: the devices below)")
cites("FID-RU-10", "c72247a6", "Docs/Stage0/device-checklists/G06-Design.md", 15, "On the iPhone 17 Pro (iOS 26.7),")

# FID-RU-11
cites("FID-RU-11", REVIEWED, "Docs/Stage0/M0-plan-amendments.md", 529, "(the latest, for draft 0.8 as revised on 24 and "
      "26 October 2026, `evidence/M0-DeviceA/fix-1/accuracy/commands/check-amendments.py`")
accuracy = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-RecordsUpdate/checks/check-amendments-accuracy.log")
own = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-RecordsUpdate/checks/check-amendments.log")
holds("FID-RU-11", "at the reviewed commit the accuracy fix's checker failed its check 10k, and m0-records-update's "
      "passed", "1 failed checks" in accuracy and "0 failed checks" in own)

print()
print(f"summary: {len(results)} citations and claims, {results.count(True)} hold, {results.count(False)} do not")
sys.exit(0 if all(results) else 1)
