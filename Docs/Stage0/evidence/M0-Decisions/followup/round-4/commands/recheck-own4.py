#!/usr/bin/env python3
"""Checks the answers to the owner-readability findings of the review of the follow-up (the fourth agent review of the
M0 decisions round; integration log section 23): the workflow relayed that lens's nine findings, OWN4-01 to OWN4-09, to
the follow-up's third fix of 23 October 2026, after the fidelity lens's eight (section 21) and the honesty lens's six
(section 22). Each check reads the texts its finding named and asserts what the third fix's answer (integration log
23.1) says is there now: the text the finding faulted gone from where the owner reads it (a history note may keep it, in
the gate summary's Section 6.3, item 74, or in a dated note), and the answer's text present. Where the answer rests on a
fact of the repository, the check reads that fact as well: which records name a technical lead among their deciders
(OWN4-01), which folders the harnesses and the design catalog build from (OWN4-02), which steps of Session 2 the threat
model's row cites (OWN4-04), which EPUB steps 2.9 and 2.12 are (OWN4-05), and what `linkage.sh`'s header asks and
writes, with the committed log still Xcode 27.0's and no run under 27.1 recorded (OWN4-07). HON-11 is reported as it
stands.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-4/commands/recheck-own4.py <repository root>

Run on the follow-up's own tree (git archive 19489f10, the commit the review read) and on the second fix's tree (git
archive 11f41be5, where this fix starts), it must report all nine as not answered: OWN4-03 and the second half of
OWN4-08 were already answered at 11f41be5, by the follow-up's two fixes, but each check also asserts this fix's own
addition (the order of agent branches; the wording review in item 3). The gate checks of this round (gate-checks.sh
beside this file) run both controls. Read-only; standard library only; host only. Prints one line per finding and exits
1 if any of the nine is not answered.
"""
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


def block(text, start, end):
    """The text from the line that starts with `start` to the next line that starts with `end` (empty if not found)."""
    lines = text.splitlines()
    first = [i for i, l in enumerate(lines) if l.startswith(start)]
    if len(first) != 1:
        return ""
    rest = [i for i in range(first[0] + 1, len(lines)) if lines[i].startswith(end)]
    return "\n".join(lines[first[0]:rest[0] if rest else len(lines)])


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
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
A15 = "Docs/ADRs/0015-threat-model.md"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"

gate, runbook = read(GATE), read(RUNBOOK)
item1 = block(gate, "**1. Before the first session**", "**2. The device sessions**")
item2 = line_with(GATE, "**2. The device sessions**")
item3 = block(gate, "**3. Then", "**4. ")
section7 = block(gate, "## 7. Recommendation", "## 8. ")
item74 = block(gate, "74. **The owner's lists, as checklists** (OWN4-09)", "75. ")
session10 = block(runbook, "## 6. Session 10", "## 7. What blocks the M0 gate")
tech = block(session10, "**Technical lead: you**", "**QA: you**")
approvals = block(session10, "**The ADR approvals (D-6), yours as product owner**", "**The M0 exit review**")
step03 = block(runbook, "**0.3 Commit**", "**0.4 Devices.**")
run1 = line_with(RUNBOOK, "| 1 | Before the sessions |")
run12 = line_with(RUNBOOK, "| 12 | 10 Sign-offs and the exit review |")

# OWN4-01: Session 10 lists every sign-off and step the exit waits for; every record whose deciders name a technical
# lead has the technical lead's review there; every Stage 0 record has its row in the table of approvals.
m = need(session10, ["**Technical lead: you**", "**Release owner: you, as this runbook assumes**",
                     "ADR-0014's section 7 item 6", "ADR-0014's item 7",
                     "**Before the reviews of ADR-0014: `linkage.sh` under Xcode 27.1**",
                     "with item 4's request to Readium to drop marmelroy/Zip",
                     "**The ADR approvals (D-6), yours as product owner**"], "the runbook's Session 10")
m += gone(session10, ["**Technical lead and QA: you** (about 2 h each)"], "the runbook's Session 10")
named = []
# The instruction of 22 October 2026 names four roles, quoted in the Deciders of ADR-0005 and ADR-0013 to say which roles
# it does not name; that list is not a technical lead among a record's deciders, so it is left out before matching.
ROLES = "(security reviewer, QA, design, technical lead)"
for adr in sorted((ROOT / "Docs/ADRs").glob("00[0-9][0-9]-*.md")):
    number = adr.name[:4]
    if number == "0000":
        continue
    deciders = [l for l in adr.read_text(encoding="utf-8").splitlines() if l.startswith("- **Deciders:**")]
    if deciders and re.search(r"technical[ -]lead", deciders[0].replace(ROLES, "").lower()):
        named.append(number)
        anchor = "ADR-0014's item 7" if number == "0014" else f"ADR-{number}"
        if anchor not in tech:
            m.append(f"the technical lead's table lacks {anchor}, whose Deciders name the technical lead")
    if "0003" <= number <= "0016" and f"| ADR-{number} |" not in approvals:
        m.append(f"the table of approvals lacks ADR-{number}")
if "| ADR-0002's amendments |" not in approvals:
    m.append("the table of approvals lacks ADR-0002's amendments")
if named != ["0001", "0003", "0006", "0007", "0009", "0012", "0014", "0015", "0016"]:
    m.append(f"the records whose deciders name a technical lead are {', '.join(named)}, not the nine of the finding "
             "and of Session 10's table (ADR-0001, 0003, 0006, 0007, 0009, 0012, 0014, 0015 and 0016)")
m += need(item3, ["**As technical lead**", "**As release owner**", "ADR-0014's item 6", "ADR-0014's item 7",
                  "your review of each record whose deciders name the technical lead",
                  "make the request item 4 recommends, to Readium to drop marmelroy/Zip"], "M0-gate.md item 3")
m += gone(item3, ["as QA and as technical lead (about 2 h each"], "M0-gate.md item 3")
m += need(run12, ["ADR-0014's item 6", "`linkage.sh` under Xcode 27.1", "about 6-6.5 days of your time"],
          "the runbook's run 12")
m += need(line_with(SESSIONS, "| 12 | 10 Sign-offs"), ["the release owner's ADR-0014 item 6"], "the session log's row 12")
report("OWN4-01", m, f"Session 10, item 3, run 12 and the session log list the technical lead's review of each of the "
       f"{len(named)} records whose deciders name one ({', '.join(named)}), the release owner's item 6, linkage.sh and "
       "the request to drop marmelroy/Zip, and the reviews each record's approval waits for")

# OWN4-02: the repeat rule counts what a step builds, copies or runs, and its command lists every folder the harnesses
# and the design catalog build from.
command = "-- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists`"
m = need(step03, [command, "changes something a step built, copied or ran"], "the runbook's 0.3")
m += need(item2, [command, "changes something a step built, copied or ran"], "M0-gate.md item 2")
for where, text in (("the runbook's 0.3", step03), ("M0-gate.md item 2", item2)):
    m += gone(text, ["-- Docs/Stage0/device-checklists Spikes Scripts/ci.d`", "(its harness, spike or drop-in)"], where)
listed = {"Apps", "Packages", "Spikes", "Fixtures", "Scripts", "Contracts"}
outside = []
for manifest in sorted(list((ROOT / "Apps").rglob("project.yml")) + list((ROOT / "Spikes").rglob("project.yml"))
                       + list((ROOT / "Apps").rglob("Package.swift")) + list((ROOT / "Spikes").rglob("Package.swift"))):
    if "/.build/" in str(manifest):
        continue
    for ref in re.findall(r"(?<![\w.])((?:\.\./)+[\w.\-/]+)", manifest.read_text(encoding="utf-8")):
        target = (manifest.parent / ref).resolve()
        try:
            top = target.relative_to(ROOT.resolve()).parts[0]
        except (ValueError, IndexError):
            continue
        if top not in listed:
            outside.append(f"{manifest.relative_to(ROOT)}: {ref}")
if outside:
    m.append("manifests reach folders the command does not list: " + ", ".join(outside))
report("OWN4-02", m, "item 2 and the runbook's 0.3 count what a step builds, copies or runs, and list every folder the "
       "manifests under Apps/ and Spikes/ reach")

# OWN4-03: agent work goes into m0-decisions on both paths (the follow-up's fix), ADR-0002 words the kept rule as the
# owner did and asks about a later merge (its second fix); and this fix's addition: one agent's work on the same records
# starts only once the other's branch is merged.
a02 = read(A02)
m = need(a02, ["before the M0 exit review the exception covers pull request #4, pull request #5 and this merge, and no "
               "other merge into `main`",
               "- Product owner: whether H-1's exception also covers bringing agent work started during the device "
               "sessions"], "ADR-0002")
m += gone(a02, ["The rule stays for every other milestone branch"], "ADR-0002")
m += gone(runbook, ["or by pull request for `main`), between sessions"], "the runbook")
m += gone(gate, ["merge that branch into the branch you build from"], "M0-gate.md")
m += need(step03, ["only once the other's branch is merged into `m0-decisions`"], "the runbook's 0.3")
m += need(item1, ["only once the other's branch is merged into `m0-decisions`"], "M0-gate.md item 1")
report("OWN4-03", m, "ADR-0002 keeps the rule as the owner did and asks about a later merge; agent branches go into "
       "m0-decisions; an agent on the same records starts once the other's branch is merged")

# OWN4-04: ADR-0015 times the security sign-off by every input the runbook's Session 10 reads for the threat model, and
# R4-01 and R4-02 before that sign-off.
a15 = read(A15)
reviewer = line_with(A15, "- Security reviewer: review and sign this model")
r4 = line_with(A15, "- ADR-0014's owner: close review round 4's R4-01 and R4-02")
m = gone(a15, ["Sessions 0.7, 0.8, 1.1-1.3, 4 and 6.1-6.5, and G0.1 EPUB steps 11 and 13)"], "ADR-0015")
m += need(reviewer, ["after the runbook's runs 3-6 and 8-11", "only once ADR-0014's R4-01 and R4-02 are closed"],
          "ADR-0015's security reviewer item")
m += need(r4, ["in practice before the security reviewer's sign-off in the device runbook's Session 10"],
          "ADR-0015's R4 item")
threat_row = [l for l in session10.splitlines() if l.startswith("| The threat model (an M0 deliverable")]
# The runbook's step numbers in the row's Read column ("2.9", "5.3-5.6"), not gate names ("G0.3") or plan sections.
cited = re.findall(r"(?<![\w.])\d+\.\d+(?:-\d+\.\d+)?(?![\w.])", threat_row[0].split(" | ")[1]) if threat_row else []
if not cited:
    m.append("the runbook's threat-model row names no step")
m += [f"ADR-0015's security reviewer item lacks {step}, which the runbook's threat-model row reads" for step in cited
      if not re.search(rf"(?<![\w.]){re.escape(step)}(?![\w.])", reviewer)]
report("OWN4-04", m, f"ADR-0015 records the sign-off after runs 3-6 and 8-11, with every step the runbook's threat-model "
       f"row reads ({', '.join(cited)}), and R4-01 and R4-02 before it")

# OWN4-05: the EPUB row names 2.9 and 2.12, which are G0.1 EPUB steps 13 and 11.
m = need(session10, ["| ADR-0004 section 4; Session 2's 2.9 and 2.12 (G0.1 EPUB steps 13 and 11) | ADR-0004 |"],
         "the runbook's EPUB row")
m += gone(runbook, ["Session 2's steps 11 and 13"], "the runbook")
if "(EPUB step 13)" not in line_with(RUNBOOK, "**2.9 "):
    m.append("2.9's heading does not name EPUB step 13")
if "(EPUB step 11" not in line_with(RUNBOOK, "**2.12 "):
    m.append("2.12's heading does not name EPUB step 11")
report("OWN4-05", m, "Session 10's EPUB row reads 2.9 and 2.12, whose headings name EPUB steps 13 and 11")

# OWN4-06: the change of CLAUDE.md is committed on m0-decisions, before any merge into main.
m = need(item1, ["commit the change on `m0-decisions`"], "M0-gate.md item 1")
m += gone(item1, ["change its milestone paragraph, or ask for the change, with the wording of Section 7, item 5"],
          "M0-gate.md item 1")
m += need(section7, ["change it on `m0-decisions` and commit it there"], "M0-gate.md Section 7, item 5")
m += need(step03, ["here on `m0-decisions`"], "the runbook's 0.3")
m += need(run1, ["change its milestone paragraph on `m0-decisions` and commit it there"], "the runbook's run 1")
m += gone(run1, ["change its milestone paragraph, or ask for the change (`M0-gate.md`"], "the runbook's run 1")
m += need(line_with(SESSIONS, "| 1 | Before the sessions"), ["corrected on `m0-decisions` and committed there"],
          "the session log's row 1")
report("OWN4-06", m, "item 1, Section 7, run 1, 0.3 and the session log have CLAUDE.md corrected and committed on "
       "m0-decisions, before any merge into main")

# OWN4-07: linkage.sh with resolve-locks.sh first, its logs in a folder of their own, and ADR-0014 updated from them.
m = need(gate, ["Run `evidence/M0-dependencies/commands/resolve-locks.sh` first",
                "a folder of their own under `evidence/M0-dependencies/`"], "M0-gate.md item 4")
m += need(section7, ["`linkage.sh` run under Xcode 27.1 after `resolve-locks.sh`"], "M0-gate.md Section 7")
m += need(session10, ["Docs/Stage0/evidence/M0-dependencies/commands/resolve-locks.sh > "
                      "Docs/Stage0/evidence/M0-dependencies/xcode-27.1/resolve-locks.log",
                      "Docs/Stage0/evidence/M0-dependencies/commands/linkage.sh > "
                      "Docs/Stage0/evidence/M0-dependencies/xcode-27.1/linkage.log"], "the runbook's Session 10")
m += need(read(A14), ["`Docs/Stage0/evidence/M0-dependencies/xcode-27.1/`"], "ADR-0014's open item")
script = read("Docs/Stage0/evidence/M0-dependencies/commands/linkage.sh")
if "Run resolve-locks.sh first" not in script:
    m.append("linkage.sh's header no longer asks for resolve-locks.sh first: correct the records")
if "> Docs/Stage0/evidence/M0-dependencies/linkage.log" not in script:
    m.append("linkage.sh's usage line no longer writes the committed log: correct the records")
if "Xcode 27.0 Build version 27A266a" not in read("Docs/Stage0/evidence/M0-dependencies/linkage.log"):
    m.append("the committed linkage.log is no longer Xcode 27.0's: correct the records")
if (ROOT / "Docs/Stage0/evidence/M0-dependencies/xcode-27.1").exists():
    m.append("a run under Xcode 27.1 is now recorded: the records that call it pending need updating")
report("OWN4-07", m, "item 4, Section 7, the runbook's Session 10 and ADR-0014 give resolve-locks.sh first, a folder of "
       "its own for the logs and the update of ADR-0014; the committed log is still Xcode 27.0's and no 27.1 run exists")

# OWN4-08: item 3 lists the wording review of G0.5 AI step 9.2 and its two decisions, and D03's outcome.
m = need(item3, ["**G0.5 AI step 9.2, the wording review**",
                 "whether M5's request view must show an earlier attempt that may have reached the provider",
                 "whether dismissing the consent sheet should return the record to its earlier state",
                 "the outcome of D03"], "M0-gate.md item 3")
m += need(line_with(GATE, "**Recommendation** (Section 7)"),
          ["the outcome of D03, whether quick capture can be advertised (item 3)"], "M0-gate.md Section 1's opening")
report("OWN4-08", m, "item 3 lists G0.5 AI step 9.2's wording review with its two decisions and D03's outcome; the "
       "opening names D03's outcome")

# OWN4-09: item 1 and the runbook's 0.3 are numbered checklists without their history notes, item 3 a list by role,
# run 1 without its history, the bullet on main without its layered note, and item 74 holds the notes.
m = []
for n in range(1, 11):
    if not re.search(rf"(?m)^{n}\. \*\*", item1):
        m.append(f"item 1 lacks its step {n}")
for n in range(1, 8):
    if not re.search(rf"(?m)^{n}\. ", step03):
        m.append(f"the runbook's 0.3 lacks its step {n}")
longest = max((len(p.split()) for p in re.split(r"(?m)^(?=\d+\. )", item1)), default=0)
if longest > 400:
    m.append(f"a step of item 1 has {longest} words")
for start in ("- **As security reviewer**", "- **As designer**", "- **As technical lead**", "- **As QA**",
              "- **As product owner**", "- **As release owner**", "- **The ADR approvals**", "- **Then the M0 exit review**"):
    if start not in item3:
        m.append(f"item 3 lacks {start}")
for where, text in (("M0-gate.md item 1", item1), ("M0-gate.md item 3", item3), ("the runbook's 0.3", step03)):
    m += gone(text, ["(Until 22 October 2026", "(Added on 23 October 2026"], where)
m += gone(run1, ["until then this run asked for decisions D-1, D-2 and D-10"], "the runbook's run 1")
m += gone(line_with(GATE, "- **The M0 work is on `main`, and the M0 gate is still pending.**"),
          ["and since your answer of the same day, before the exit review too"], "the bullet on the M0 work on main")
if not item74:
    m.append("Section 6.3 has no item 74 with the moved history notes")
report("OWN4-09", m, f"item 1 (its longest step {longest} words) and 0.3 are numbered checklists without their history "
       "notes, item 3 a list by role, run 1 and the bullet on main without theirs, and item 74 holds them")

# HON-11: reported as it stands (left for the owner; no agent changes CLAUDE.md on a workflow's request).
stale = "are combined on `m0-integrate`" in read("CLAUDE.md")
print(f"{'open    ' if stale else 'changed '} HON-11: CLAUDE.md's milestone paragraph "
      + ("still says the M0 work is combined on `m0-integrate`: left for the product owner, who commits the change on "
         "m0-decisions (M0-gate.md Section 1, item 1, step 2)" if stale else
         "no longer says the M0 work is combined on `m0-integrate`"))

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of the nine not answered)")
sys.exit(1 if problems else 0)
