#!/usr/bin/env python3
"""Re-checks the second review's findings (the review of the decisions round's fix, at d0a24c43; integration log section
19) on the tree as the follow-up of 23 October 2026 leaves it. The workflow relayed thirteen of them to the follow-up
again with the third review's findings: the twelve minor findings of the fidelity, honesty and harness lenses that the
second fix answered (FID2-01 to FID2-05, HON-12 to HON-14, R2-H-01 to R2-H-04) and HON-11, which it left; the owner
lens's OWN2-01 to OWN2-08 were not relayed again. Each check below reads the texts the
finding named, as the finding's own command did, and asserts what the second fix's answer (integration log 19.1) says
is there now: the stale text gone, or kept only with its dated note. HON-11 is reported as it stands: still open,
because no agent changes CLAUDE.md on a workflow's request.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/commands/recheck-review2.py <repository root>

Read-only; standard library only; host only. Prints one line per finding and exits 1 if any of the twelve is no longer
answered.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def lines_with(path, pattern):
    return [(n, line) for n, line in enumerate(read(path).splitlines(), 1) if re.search(pattern, line)]


def report(finding, ok, what, detail=""):
    global problems
    if not ok:
        problems += 1
    print(f"{'answered' if ok else 'PROBLEM '} {finding}: {what}" + (f" ({detail})" if detail and not ok else ""))


LOG = "Docs/Stage0/integration-log.md"
GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
AMEND = "Docs/Stage0/M0-plan-amendments.md"
G05R = "Docs/Stage0/device-checklists/G05-Recovery.md"

# FID2-01: the integration log's stale requests each carry the dated note of the decision.
hits = lines_with(LOG, r"the request stands|decisions D-1 and D-6 of the runbook|with the owner.s review still asked for")
bad = [n for n, line in hits if "23 October 2026" not in line]
updates = lines_with(LOG, r"\*\*The App Store's automatic updates\*\* are the owner's to turn off")
bad_updates = [n for n, line in updates if "the owner confirmed them off on 22 October 2026" not in line]
report("FID2-01", hits and not bad and len(updates) == 2 and not bad_updates,
       f"the {len(hits)} log lines that still asked for D-7's review or D-1 and D-6, and the {len(updates)} App Store "
       "items of 13.5 and 14.5, each carry the dated note of the decision",
       f"lines without the note: {bad + bad_updates}; App Store items found: {len(updates)}")

# FID2-02: the report findings and table cells that asked for decisions taken carry the decision.
pairs = [
    ("Docs/Stage0/G03-Intake.md", "The product owner should approve the 1-hour value", "PO-14 as recommended"),
    ("Docs/Stage0/G03-Intake.md", "are spike proposals for the product owner", "PO-14 as recommended"),
    ("Docs/Stage0/G01-EPUB.md", "are spike proposals for the product owner", "PO-02 (a)"),
    ("Docs/Stage0/G05-AI.md", r"the product owner should confirm it \(Q2\)", "PO-25 (a)"),
    (AMEND, "the ATS key is chosen after the device run", "D-9 (b) chose `NSAllowsLocalNetworking`"),
]
missing = []
for path, pattern, note in pairs:
    found = lines_with(path, pattern)
    if not found or any(note not in line for _, line in found):
        missing.append(f"{path}: {pattern}")
b6 = [line for _, line in lines_with("Docs/ADRs/0015-threat-model.md", r"^\| I, T: cleartext to a non-local host")]
b6_cell = b6[0].rstrip(" |").split(" | ")[-1] if b6 else ""
if not b6_cell or b6_cell.startswith("ATS key choice pending-device"):
    missing.append("ADR-0015's B6 cell still begins with the key pending")
report("FID2-02", not missing, "the four report findings and the amendments' rows carry their decisions, and ADR-0015's "
       "B6 cell no longer begins with the ATS key pending", "; ".join(missing))

# FID2-03: the gate summary's D14 row names D14's open items, not a sequencing no decision made.
d14 = [line for _, line in lines_with(GATE, r"^\| D14 ")]
d14_ok = (d14 and "Phase A against the Docker hub" in d14[0] and "Phase C feasibility bar" in d14[0]
          and d14[0].count("the later web reader is sequenced when Phase A is") == 1
          and "(Until 23 October 2026 this cell said the later web reader is sequenced when Phase A is" in d14[0])
report("FID2-03", d14_ok, "the D14 row names the ordering of Phase A against the Docker hub and the Phase C feasibility "
       "bar, and keeps the old sequencing only in its dated note")

# FID2-04: the runbook's People line names the iPad's Session 9 among the owner's design judgement.
runbook = read(RUNBOOK)
report("FID2-04", "you judge G0.6's design steps in Sessions 7 and 8" not in runbook
       and "you judge the design steps of Sessions 2 (2.7 and 2.8, G0.1 EPUB), 7, 8 and 9" in runbook,
       "1.3 names Sessions 2, 7, 8 and 9")

# FID2-05: ADR-0005 no longer gives the iOS lead's sign-off to the owner as settled.
adr5 = read("Docs/ADRs/0005-pdf-reading-and-anchors.md")
report("FID2-05", "the iOS lead's device confirmation at the M0 gate. Sylvia is a solo project, so the product owner "
       "gives it personally" not in adr5 and "this record assumes the product owner gives that confirmation too" in adr5,
       "ADR-0005's Deciders say the role is assumed to be the owner's")

# HON-11: reported as it stands (left for the owner; no agent changes CLAUDE.md on a workflow's request).
claude = read("CLAUDE.md")
stale = "are combined on `m0-integrate`" in claude
print(f"{'open    ' if stale else 'changed '} HON-11: CLAUDE.md's milestone paragraph "
      + ("still says the M0 work is combined on `m0-integrate`: left for the product owner, now in M0-gate.md Section 1, "
         "item 1" if stale else "no longer says the M0 work is combined on `m0-integrate`"))

# HON-12: the records that said the decisions round's records were not reviewed now say which reviews read them.
gate = read(GATE)
plan = read(PLAN)
amend = read(AMEND)
hon12 = []
if re.search(r"these records have not been reviewed|the assembly has not been reviewed", gate):
    hon12.append("M0-gate.md still says these records or the assembly were not reviewed")
if "(Dated note, 23 October 2026: reviewed by an agent with the assembly on 22 October 2026" not in gate:
    hon12.append("M0-gate.md item 29 lacks its dated note")
if "two agent reviews have since read this draft" not in plan:
    hon12.append("plan Appendix D's draft 0.8 entry lacks its review note")
if "were read by later agent reviews" not in amend:
    hon12.append("the amendments' header lacks its review statement")
if "the changes since were read by later agent reviews" not in runbook:
    hon12.append("the runbook's header lacks its review statement")
if "This record of the re-pin is agent-written and not reviewed" in read("Docs/ADRs/0001-platform-baseline-and-toolchain.md"):
    hon12.append("ADR-0001 still says not reviewed")
if "the record of 22 October 2026, are agent-written and not reviewed" in read("Docs/ADRs/README.md"):
    hon12.append("the ADR index still says not reviewed")
report("HON-12", not hon12, "the gate summary, the plan, the amendments, the runbook, ADR-0001 and the ADR index say "
       "which agent reviews read the records", "; ".join(hon12))

# HON-13: the plan round's evidence README and integration log 18.4 say what the logs show.
plan_readme = read("Docs/Stage0/evidence/M0-Decisions/plan/README.md")
log = read(LOG)
report("HON-13", "pass's logs were never committed" in plan_readme
       and "The first three rows ran on `713d99b1`" in log,
       "(a) the 7a22201 pass has no committed record and the 96832c6 pass is in the history; (b) 18.4 says on which "
       "commit each check ran")

# HON-14: the quiet tone's keeping the harness running while locked is not stated as fact.
g05r = read(G05R)
report("HON-14", "so iOS keeps it running while the phone is locked" not in runbook
       and "stays running while the phone is locked by playing a quiet tone" not in g05r
       and "a `gap` line while the phone is locked means iOS suspended the harness" in g05r,
       "the checklist's step 3 and runbook 6.1 give the tone's effect as the design's intent, which the device run shows")

# R2-H-01: step 3's Failed rule names the verify line after the restart's previous-session line.
r1 = ("the `verify` line that follows a `previous-session` line with `result=ended-by-restart`" in g05r
      or "`verify` line that follows a `previous-session` line with `result=ended-by-restart`" in g05r)
report("R2-H-01", r1 and "a `verify` line that follows a `previous-session` line with `result=ended-by-restart`" in runbook
       and "The lines recorded before the first unlock" in g05r
       and "the lines recorded before the first unlock are never criteria" in runbook,
       "the checklist's item 9 and runbook 6.1 judge the verify line after the restart, never the lines before the first "
       "unlock")

# R2-H-02: the Failed rules win, whatever else a run meets.
report("R2-H-02", "**Failed**, whatever else the run meets" in g05r and "**Failed**, whatever else the run meets" in runbook,
       "the checklist's item 9 and runbook 6.1 put Failed first")

# R2-H-03: the smoke check and the UI test no longer credit the tone with keeping the app running in the background.
checks = read("Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh")
uitest = read("Spikes/G05-Recovery/LockHarness/UITests/LockHarnessSmokeUITests.swift")
report("R2-H-03", "the tone keeping the app running" not in checks
       and "In the background the tone keeps the app running" not in uitest
       and "the app was not suspended in the background" not in uitest
       and "audioCategory" in read("Spikes/G05-Recovery/LockHarness/Core/HarnessController.swift"),
       "the check's label and the UI test's comments say what the simulator shows, and the start line records the audio "
       "session's category")

# R2-H-04: FileLogSink.append no longer reads the class back after writing, and undoes a failed append.
files = read("Spikes/G05-Recovery/LockHarness/Core/HarnessFiles.swift")
start = files.find("public func append(_ lines: [String]) throws {")
body = files[start:files.find("\n    }\n", start)] if start >= 0 else ""
report("R2-H-04", bool(body) and "protector.verify(paths.log)" not in body and "truncate(atOffset:" in body,
       "FileLogSink.append writes, flushes and on failure cuts the file back, with no class readback after the append")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of the twelve no longer answered)")
sys.exit(1 if problems else 0)
