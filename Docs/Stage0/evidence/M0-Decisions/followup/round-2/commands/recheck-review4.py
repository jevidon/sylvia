#!/usr/bin/env python3
"""Checks the answers to the review of the follow-up (the fourth agent review of the M0 decisions round; integration log
section 21): the workflow relayed its fidelity lens's eight findings, FID4-01 to FID4-08, to the follow-up's fix of 23
October 2026. Each check below reads the texts its finding named and asserts what the fix's answer (integration log
21.1) says is there now: the stale text gone, or kept only inside its dated note, and the answer's text present. For
FID4-01 it also reads what the records say is still missing, the notices of the OpenDyslexic fonts, and asserts that it
is still missing, so the records' "not yet" stays true until someone adds them. HON-11 is reported as it stands.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-2/commands/recheck-review4.py <repository root>

Run on the follow-up's own tree (git archive 19489f10), it must report all eight as not answered: the gate checks of
this round (gate-checks.sh beside this file) run it there as a control. Read-only; standard library only; host only.
Prints one line per finding and exits 1 if any of the eight is not answered.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def line_with(path, start):
    found = [line for line in read(path).splitlines() if line.startswith(start)]
    return found[0] if len(found) == 1 else ""


def report(finding, missing, what):
    global problems
    if missing:
        problems += 1
    print(f"{'answered' if not missing else 'PROBLEM '} {finding}: {what}" + (f" ({'; '.join(missing)})" if missing else ""))


def need(text, phrases, where):
    return [f"{where} lacks: {p}" for p in phrases if p not in text]


def gone(text, phrases, where):
    return [f"{where} still says: {p}" for p in phrases if p in text]


GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
AMEND = "Docs/Stage0/M0-plan-amendments.md"
LOG = "Docs/Stage0/integration-log.md"
INV = "Docs/Licenses/inventory.json"
DRAFT = "Docs/Licenses/acknowledgements-draft.md"
TPI = "Docs/Licenses/third-party-inventory.md"
A01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
INDEX = "Docs/ADRs/README.md"
G06C = "Docs/Stage0/device-checklists/G06-Design.md"
G01C = "Docs/Stage0/device-checklists/G01-EPUB.md"
G06R = "Docs/Stage0/G06-Design.md"

gate, runbook, plan, amend, log = read(GATE), read(RUNBOOK), read(PLAN), read(AMEND), read(LOG)
a14, draft = read(A14), read(DRAFT)

# FID4-01: the gate summary no longer says the draft carries the notices; the inventory and the draft record the
# answer and what is missing; ADR-0014 has the open item; and what is missing is still missing.
m = need(gate, ["but not yet for PO-41's OpenDyslexic fonts**: it has neither the CC BY 3.0 license nor its URI, nor the "
                "copyright and permission notice of the Bitstream license"], "M0-gate.md item 4")
m += gone(gate, ["(the acknowledgements draft carries them)"], "M0-gate.md")
inventory = json.loads(read(INV))
fonts = [e for p in inventory["acknowledgements"]["products"] for e in p["entries"]
         if e["name"] == "OpenDyslexic (font, in Readium's resources)"]
entry = fonts[0] if len(fonts) == 1 else {}
m += need(entry.get("note", ""), ["The product owner decided on 23 October 2026 that, in the owner's own and TestFlight "
                                  "builds, these fonts ship with the attribution and notices their licenses require"],
          "the inventory's OpenDyslexic note")
m += need(entry.get("pending", ""), ["Not yet here, and needed before a TestFlight build carries these fonts: the CC BY "
                                     "3.0 license or its URI, and the copyright and permission notice of the Bitstream "
                                     "license"], "the inventory's OpenDyslexic pending note")
m += gone(json.dumps(inventory), ["whether to ship these files at all, is for the product owner and counsel"], "the inventory")
m += need(draft, ["**Pending (not yet decided):** Whether App Store distribution is compatible with CC BY 3.0 section "
                  "4(a)"], "the acknowledgements draft")
m += need(a14, ["- This record's owner, with the product owner or an agent the owner allows to fetch: add to "
                "`Docs/Licenses/inventory.json` the notices the OpenDyslexic fonts need"], "ADR-0014's open items")
still_missing = "creativecommons.org" not in draft and not any(
    "bitstream" in p.name.lower() for p in (ROOT / "Docs/Licenses/texts").rglob("*"))
if not still_missing:
    m.append("the draft now has a Creative Commons link or the texts a Bitstream file: update the records' 'not yet'")
report("FID4-01", m, "item 4 names the notices PO-41's fonts lack; the inventory, the draft and ADR-0014 record the answer "
       "and what is missing, which is still missing (no Creative Commons link in the draft, no Bitstream text)")

# FID4-02: agent work is merged into m0-decisions, never straight into main before the exit.
m = gone(runbook, ["or by pull request for `main`), between sessions"], "the runbook")
m += need(runbook, ["Never merge it into `main`, or open a pull request of it into `main`, before the M0 exit",
                    "and it reaches your build only when you merge it into `m0-decisions` (`git checkout m0-decisions`",
                    "which reaches your build only when you merge it into `m0-decisions` between sessions, never "
                    "straight into `main` (0.3)"], "the runbook")
m += gone(gate, ["merge that branch into the branch you build from"], "M0-gate.md")
m += need(gate, ["Never merge it, or a pull request of it, straight into `main` before the M0 exit",
                 "merge that branch into `m0-decisions`, never straight into `main` (item 1)",
                 "agent work reaches that build only when you merge it into `m0-decisions` between sessions"], "M0-gate.md")
m += need(read(A02), ["reaches `main` before the M0 exit only through `m0-decisions`"], "ADR-0002's Branches")
report("FID4-02", m, "the runbook's run 1 and 0.3, the gate summary's items 1 and 4 and Section 7, and ADR-0002 route "
       "agent work through m0-decisions")

# FID4-03: no record states the iPad's iPadOS; it is checked before Session 0, and 21.1 depends on that check.
m = gone(read(A01), ["on iPadOS 26.x or 27.x as it has."], "ADR-0001")
line_c = line_with(G06C, "- **C. An iPad**")
if not line_c.startswith("- **C. An iPad** (any model that runs iPadOS 26.x or 27.x)"):
    m.append("the G0.6 checklist's line C does not state the iPadOS as a requirement")
m += gone(plan, ["(23 October 2026; ADR-0001), so no device has to be acquired"], "the plan")
m += need(plan, ["no device has to be acquired if that iPad runs iPadOS 26 or later"], "plan 21.1")
m += need(runbook, ["**Before Session 0, check that it runs iPadOS 26**", "checked as device A is (Section 1.1)"],
          "the runbook")
m += need(gate, ["Check it as device A: it must run iPadOS 26"], "M0-gate.md item 1")
report("FID4-03", m, "ADR-0001, the G0.6 checklist and plan 21.1 state no iPadOS for the owner's iPad; run 1, 1.1 and "
       "item 1 check it before Session 0")

# FID4-04: the open statuses the finding listed carry the answer or a dated note.
m = []
row28 = line_with(G06R, "| G0.6: component set viewed on a device")
m += need(row28, ["the iPhone 17 Pro and an iPad (no hardware yet).", "23 October 2026: the product owner has an iPad"],
          "the G0.6 report's grayscale row (C51's words kept)")
m += gone(read(G06C), ["in regular width once one is available"], "the G0.6 checklist")
m += need(line_with(G01C, "- **Devices:**"), ["(23 October 2026: the product owner has both"], "the G0.1 EPUB checklist")
m += need(amend, ["23 October 2026: the product owner has an iPad with a keyboard and a trackpad or mouse, whose model and "
                  "iPadOS the device runbook records at Session 0",
                  "so acquiring them is no longer on every milestone's path to exit unless that check fails"], "the amendments")
m += gone(amend, ["| A15 (job store only) |"], "the amendments")
m += need(log, ["The gate summary asks the owner to say if D-6 was meant to approve the ADRs now (`M0-gate.md` Section 1, "
                "item 4; Section 6.3, item 30). *(Dated note, 23 October 2026: the owner confirmed"], "integration log 17.2")
m += gone(plan, ["as D13's row now says"], "the plan")
m += need(plan, ["ADR-0009 say (decided on 23 October 2026, set aside and recover"], "plan Appendix D")
m += need(read(TPI), ["no longer all pending as written above"], "the third-party inventory")
m += need(a14, ["except those the product owner took on 22 and 23 October 2026"], "ADR-0014's status")
m += need(amend, ["A15 (the job store since 22 October 2026, the sources file and the import ledger since 23 October 2026"],
          "the amendments' PO-12 row")
m += need(read(INDEX), ["| ADR | Title | Status (23 October 2026) | Owner during Stage 0 |"], "the ADR index")
report("FID4-04", m, "the iPad, D-6, PO-12, PO-42 and the license statuses the finding listed carry the answers or dated "
       "notes, and the ADR index's status column is dated 23 October 2026")

# FID4-05: no record reads the answer as covering the companion's notarized builds.
reading = "read as before the companion's public release too"
m = []
for path in (GATE, PLAN, AMEND, A14):
    m += gone(read(path), [reading, "these records read your answer as putting the lawyer's review before its public "
                           "release too", "the records read the answer as putting that review before the companion's "
                           "public release too, for the product owner to correct"], path)
m += need(plan, ["the answer does not name the notarized companion's builds, so PO-42 is still settled before one is "
                 "distributed beyond the team", "for the Mac companion's notarized builds, which the answer does not "
                 "name, the next item"], "the plan's D13 row and Appendix D")
m += need(a14, ["the records keep the gate of 22 October 2026"], "ADR-0014 item 2")
m += need(gate, ["for a notarized companion build distributed beyond the team these records keep the gate of 22 October "
                 "2026"], "M0-gate.md item 4")
report("FID4-05", m, "the gate summary, the plan, the amendments and ADR-0014 keep the gate of 22 October 2026 for the "
       "companion's notarized builds")

# FID4-06: ADR-0014's approval is D-6's, the Zip request is the security reviewer's, and the requests' timing is the
# records' suggestion.
m = gone(gate, ["the exit review approves ADR-0014 with the lawyer's review",
                "each before the lawyer's review that precedes a public App Store release",
                "with your requests to Readium and SwiftSoup's maintainers made before it"], "M0-gate.md")
m += gone(runbook, ["so the exit review approves ADR-0014 with that review"], "the runbook")
m += gone(a14, ["the exit review approves this record with that review open",
                "and asking Readium is the product owner's, before that review.)*",
                "asking the maintainers is the product owner's, before the lawyer's review"], "ADR-0014")
m += need(gate, ["under D-6, ADR-0014 is approved once Session 10's review of it is recorded, with your security sign-off",
                 "it set no time for them; these records suggest making each before the lawyer's review",
                 "The fourth is not part of that answer"], "M0-gate.md item 4")
m += need(runbook, ["so ADR-0014's approval, once Session 10's review of it and your security sign-off are recorded (D-6)"],
          "the runbook's exit review")
report("FID4-06", m, "item 4, the runbook and ADR-0014 leave ADR-0014's approval to D-6, give the Zip request to the "
       "security sign-off, and give the requests' timing as the records' suggestion")

# FID4-07: PO-12's repairs are built with the transfer client, in M6.
m = gone(gate, ["before M6 builds the transfer client, the repairs of PO-12's"], "M0-gate.md Section 7")
m += need(gate, ["in M6, with the transfer client, which builds them, the repairs of PO-12's sources file and import "
                 "ledger"], "M0-gate.md Section 7")
report("FID4-07", m, "Section 7, item 4 builds PO-12's repairs with the transfer client in M6, as 5.4 and plan 15.5 do")

# FID4-08: the repository README says the rule stays, and that neither merge approves anything.
readme = read("README.md")
m = gone(readme, ["this merge before the M0 exit review, which approves nothing"], "README.md")
m += need(readme, ["the rule stays, and neither merge approves anything"], "README.md")
report("FID4-08", m, "the README records that the branch rule stays and that neither merge approves anything")

# HON-11: reported as it stands (left for the owner; no agent changes CLAUDE.md on a workflow's request).
stale = "are combined on `m0-integrate`" in read("CLAUDE.md")
print(f"{'open    ' if stale else 'changed '} HON-11: CLAUDE.md's milestone paragraph "
      + ("still says the M0 work is combined on `m0-integrate`: left for the product owner, in M0-gate.md Section 1, "
         "item 1" if stale else "no longer says the M0 work is combined on `m0-integrate`"))

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of the eight not answered)")
sys.exit(1 if problems else 0)
