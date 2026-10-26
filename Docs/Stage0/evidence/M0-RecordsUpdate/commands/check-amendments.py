#!/usr/bin/env python3
"""Consistency checks for the M0 plan amendments, for plan draft 0.8 (the product owner's decisions of 22 October 2026,
the answers of 23 October 2026 and the decision of 24 October 2026 on device A recorded within it).

m0-records-update (26 October 2026; integration log section 41): a copy of
Docs/Stage0/evidence/M0-DeviceA/fix-1/accuracy/commands/check-amendments.py, unchanged but for four texts its check 10k
requires, which m0-records-update changed when it brought m0-sessions onto the product owner's session branch line
after m0-exit-prep: m0-sessions's integration log sections 28-32 are sections 36-40 since, so Appendix D's item of
24 October 2026 cites section 38 (it cited 30) and this document's dated note of 26 October 2026 sections 37 and 38
(29 and 30); and Section 9's pointer to the latest checker names the accuracy fix's version, which it did not
(Section 7's row keeps the version that checked it). The old version, run on the same tree, fails exactly its check 10k, by design.


This version (26 October 2026, the fix of the accuracy findings of the review of the update of 24 October 2026, which
read that update at 8082bdb6; integration log section 30) replaces Docs/Stage0/evidence/M0-DeviceA/commands/check-amendments.py
with every one of its checks unchanged except 10k, whose name is kept, because the fix changed the plan and this
document within draft 0.8 for the review's finding ACC-06 and for the review status that the fix of its fidelity
findings left to the next fix to change the plan (integration log 29.3):
- 10k, D01's row: its pending check of Apple's release notes for Xcode 27.1 must carry the dated note that Apple's
  pages, read on 24 October 2026, list 27A9275 as released, so what remains is the technical lead's confirmation;
- 10k, the Revised line: its entry of 26 October 2026 must also give that note and the record's review status;
- 10k, Appendix D's item of 24 October 2026 and the draft 0.8 entry's review note: they must say that an agent review
  read the record at 8082bdb6 and that no review accepted it, the item the dated note of D01's row too; their old
  endings, which said "not reviewed" and "has not been reviewed either", must be gone;
- 10k, this document's State line and its dated note under How to read this: the same review status, the old sentence
  that said the record "has not been reviewed" gone from the State line (the dated note of 24 October 2026 stays, as
  the record of what it said then).
Run on the plan and this document as the fix left them, the records part's version fails exactly its check 10k, on
those texts (the gate checks beside this file show it).

The records part's version (24 October 2026, the update of the M0 records for the device-A change, completed on 26 October 2026 by
that update's second attempt, before any review; integration log section 28) replaces
Docs/Stage0/evidence/M0-Decisions/followup/round-2/commands/check-amendments.py with every one of its checks unchanged
except three, and adds one, because on 24 October 2026 the product owner decided D-1 again (the iPhone 11 Pro, device A
since 22 October 2026, no longer charges: device A is the owner's iPhone 13 mini, and the A13 floor is left for M8's
release device matrix), and the plan records it within draft 0.8:
- 7, the anchors: "**Revised:** 23 October 2026" and "**Revised:** 24 October 2026" are now required to be absent, and
  "**Revised:** 26 October 2026" present (the first attempt wrote 24 October 2026, the second, which corrected two of
  the record's wordings in D01's row and 19.1 on 26 October 2026, the date of that correction);
- 10c, D-1: its anchors of 22 October 2026 in 19.1 and 21.1 (the iPhone 11 Pro as the baseline, the iPhone 11 as a
  second A13 phone, every budget stricter on them) are replaced by the decision of 24 October 2026 (the iPhone 13 mini,
  its screen as the iPhone 11 Pro's, its A15, the A13 floor left for M8), the old wording now required to be absent
  outside 19.1's dated history;
- 10i: Appendix D's draft 0.8 entry must end with the dated item of 23 October 2026, the item that corrects it and,
  last, the dated item of 24 October 2026 that records the decision on device A;
- 10k (new): the decision of 24 October 2026 is recorded wherever the plan and this document state device A: 19.1, 21.1
  (with how G0.6's check of the type roles on the oldest supported iPhone is made), 21.2's M8 row, 21.4's input, D01's
  row, the Literata and device-evidence risk rows, Appendix D's D-1 item and draft 0.3 note; this document's header,
  Section 2.9's A46 row, Section 3.2's ADR-0001 item (2), Section 5 and the new row of Section 7; and the stale
  statements (the iPhone 11 Pro as the oldest supported iPhone or the baseline device, the baseline's A13 making the
  budgets stricter, the oldest-device check) are gone from the plan before Appendix D.
Run on the plan as revised, the follow-up's fix's checker fails exactly on the cited path this update adds before it
exists (none, once the evidence README is committed), the revision date, 10c and 10i (the runner beside this file,
run-checks.sh, shows it).

The follow-up's fix's version (23 October 2026, after the review of the follow-up; integration log section 21)
replaced Docs/Stage0/evidence/M0-Decisions/followup/commands/check-amendments.py with every one of its checks unchanged
except three, and adds one, because the fix corrected three of the plan's records of the answers of 23 October 2026
within draft 0.8 (the review's findings FID4-03 to FID4-05):
- 10g: D13's row must also say that the answer does not name the notarized companion's builds, so PO-42 is still
  settled before one is distributed beyond the team, and the reading "read as before the companion's public release
  too" must be gone from the plan (FID4-05);
- 10h: 21.1 must say that the iPad's model and iPadOS are recorded at the runbook's Session 0 and that no device has to
  be acquired only if that iPad runs iPadOS 26 or later, which the runbook checks before Session 0; the unconditional
  "(23 October 2026; ADR-0001), so no device has to be acquired" must be gone (FID4-03);
- 10i: Appendix D's draft 0.8 entry must end with the item that corrects the dated item of 23 October 2026, after an
  agent review, and that dated item must come just before it, as the follow-up wrote it;
- 10j (new): the entry's items that left PO-12's two parts and PO-42 open point to the answers of 23 October 2026, the
  item on the decisions with no plan text says that D13's row "then" left PO-42 with counsel, and the entry's review
  note names the fourth review (FID4-04).
Run on the plan as corrected, the follow-up's checker fails exactly on 10h and 10i (the runner beside this file,
run-checks.sh, shows it), and the earlier versions as before.

The follow-up's version (23 October 2026, the follow-up of the decisions round; integration log section 20) replaced
Docs/Stage0/evidence/M0-Decisions/fix-1/commands/check-amendments.py with every one of its checks unchanged except two
places, because on 23 October 2026 the product owner answered the points the decisions had left open and the plan
records the answers within draft 0.8:
- the revision date: the anchor "**Revised:** 22 October 2026" is now required to be absent, and
  "**Revised:** 23 October 2026" present (check 7);
- 10f: the first fix's 10f required plan 15.5 to say that PO-12's sources file and import ledger are still the product
  owner's to decide; the owner decided them on 23 October 2026 (set aside and recover), so 10f now requires 15.5 to
  record that decision and the open wording to be gone. Its guard against the wording the review of the decisions
  round found (FID-01: a decision that "keeps it so") is kept.
It adds three checks: 10g, D13's row records that the product owner took PO-42, with PO-41, PO-43 and PO-44, on for
now, with a lawyer's review before any public App Store release, and the sentence that left PO-42 pending with counsel
is gone; 10h, Sections 19.1 and 21.1 and the device-evidence risk row record that the product owner has an iPad, and
no text before Appendix D says that none is recorded as available or asks to acquire one; 10i, Appendix D's draft 0.8
entry ends with the dated item that records the answers of 23 October 2026. Run on the plan as revised, the first
fix's checker fails exactly on the revision date and its 10f, and the plan round's on the revision date alone (the
follow-up's runner, run-checks.sh beside this file, shows both).

The first fix's version (22 October 2026, the fix of the review of the decisions round; integration log section 18) replaced
Docs/Stage0/evidence/M0-Decisions/plan/commands/check-amendments.py with every one of its checks unchanged, and adds
one, 10f: the review found that plan 15.5 and its Appendix D entry said the product owner's decision kept PO-12's
sources file and import ledger without a repair path, an option the owner never chose (the recommendation proposed
none for them), and that no check read that sentence (its finding FID-01). 10f requires 15.5 to say that approving
PO-12 as recommended chose nothing for them and that the choice is still the product owner's, and the wording that
credited the owner with a choice to be gone from the plan. 10a's rule (no sentence says a decision is pending) does
not cover these two parts: they are the one product-owner choice that stays open, and 10f checks that 15.5 says so.

Its predecessor, below, was the successor of Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py, which checked plan draft 0.7
and stays as the record of what it checked: draft 0.8 necessarily replaces several of the exact phrases that version
requires (the draft number, the revision date, and the sentences that said a decision was pending), so it fails on
draft 0.8 by design. This version keeps every check of that one, with those anchors replaced by draft 0.8's wording
(the replaced draft 0.7 phrases are now required to be absent), and adds the checks of section 10 below: the
decisions are recorded, the five that are not the recommendation (D-1, PO-13, PO-23, PO-33, PO-39) are applied
where the plan states them, Section 23.1 records D01-D17 approved, Section 23.3 records who signs and that nothing is
signed, and Appendix D has a draft 0.8 entry. Like its predecessor it reads the amendments document as well, which
the plan decisions round did not change.

Run from the repository root with the Python standard library only:
    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/accuracy/commands/check-amendments.py
Prints one line per check and exits 1 if any check fails.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path.cwd()
STAGE0 = ROOT / "Docs/Stage0"
PLAN = ROOT / "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
DOC = STAGE0 / "M0-plan-amendments.md"
SELF_LOG = "evidence/M0-plan-amendments/check-amendments.log"
# Draft 0.5 tagged A01-A53; its re-check, draft 0.7, added A54-A56 and PO-37 to PO-44.
LAST_DRAFT_05_TAG = 53
LAST_TAG = 56
LAST_PO = 44

# Text the plan quotes in Sections 1-23 that is not interface text, each with its reason.
# Every other quoted phrase must be in the design package or in the 4.4.6 gaps table.
NOT_INTERFACE_TEXT = dict([
    ("import a book", "an onboarding action (plan 4.2), left out by the gaps table's introduction"),
    ("connect a mac", "an onboarding action (plan 4.2), left out by the gaps table's introduction"),
    ("add a record", "an onboarding action (plan 4.2), left out by the gaps table's introduction"),
    ("aa", "the reader chrome's settings glyph (plan 4.4.7); the package labels it Reader settings"),
    ("indexed", "a word the plan contrasts with Ready (plan 4.4.1)"),
    ("derived", "the plan's own marking of derived tints (plan 4.4.2)"),
    ("(derived)", "the plan's own marking of derived tints (plan 4.4.2)"),
    ("every role scales", "the plan quoting its own rule (plan 4.4.3)"),
    ("not imported", "a state the plan names, not interface text (plan 8.2)"),
    ("i recommended this", "the meaning of an outbound recommendation (plan 12)"),
    ("successful import", "the plan quoting its own wording (plan 16.4)"),
    ("context available", "a term the teams agree on (plan 21.3)"),
    ("removed", "a term the teams agree on (plan 21.3)"),
    ("continues in the background when ios allows it, and resumes from verified parts whenever sylvia runs",
     "the promise the interface may not exceed (plan 15.5), not a status phrase"),
    ("20h 58m left", "an example of the duration format (plan 4.4.6), which the package's formats carry"),
    ("indexing 12 of 40 chapters", "an example of the vocabulary's chapter-count phrase"),
    ("3.1 of 5.2 gb verified", "an example of the vocabulary's verified-bytes phrase"),
    ("page 183", "wording the plan forbids (plan 7.5)"),
    ("full text available", "wording the plan forbids (plan 9.4)"),
    ("ai failed", "wording the plan forbids (plan 14.3)"),
    ("free because you subscribe", "wording the plan forbids (plan 14.5)"),
    ("ignore certificate error", "a switch the plan forbids (plan 15.2)"),
    ("complete backup", "a claim the plan forbids (plan 17.3)"),
    ("temporary trust-all", "code the plan forbids (plan 21.1)"),
    ("open with", "the Files app's own menu, not Sylvia's text (plan 8.1)"),
    ("remove finished audio after 30 days", "an example of a deferred rule (plan 17.2)"),
])

failures = []


def check(ok, label, detail=""):
    print(("PASS " if ok else "FAIL ") + label + (f": {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def section_text(text, heading_prefix):
    """Text from a heading starting with heading_prefix to the next heading of the same or higher level."""
    lines = text.splitlines()
    out, level = [], None
    for line in lines:
        m = re.match(r"^(#+) (.*)$", line)
        if m and level is None and m.group(2).startswith(heading_prefix):
            level = len(m.group(1))
            continue
        if level is not None:
            if m and len(m.group(1)) <= level:
                break
            out.append(line)
    return "\n".join(out)


# ---------- plan structure ----------

TAG = re.compile(r"\[M0-A(\d\d)\]")


def plan_key(title):
    m = re.match(r"(\d+(?:\.\d+)*)\.?\s", title)
    if m:
        return m.group(1)
    m = re.match(r"Appendix ([A-D])\.", title)
    if m:
        return "Appendix " + m.group(1)
    m = re.match(r"([A-D]\.\d+)\s", title)
    if m:
        return m.group(1)
    return None


def plan_tag_sections(text):
    """Map tag -> set of plan section keys, for the body before Appendix D."""
    current, found = "front", defaultdict(set)
    for line in text.splitlines():
        h = re.match(r"^(#{1,3}) (.*)$", line)
        if h:
            key = plan_key(h.group(2))
            if key:
                current = key
            if current == "Appendix D":
                break
            continue
        for t in TAG.findall(line):
            found["A" + t].add(current)
    return found


def normalize_sections(cell):
    keys = set()
    for raw in re.split(r",\s*", cell.strip()):
        token = raw.strip()
        token = re.sub(r"\s*\(.*?\)$", "", token)            # "23.1 (D16)" -> "23.1"
        token = re.sub(r"^Sections?\s+", "", token)
        if token.lower() in ("front matter", "introduction"):
            keys.add("front")
            continue
        m = re.match(r"^Appendix ([A-D]\.\d+)$", token)
        if m:
            keys.add(m.group(1))
            continue
        keys.add(token)
    return keys


# ---------- markdown tables ----------

def table_rows(text):
    """Yield (header_cells, row_cells) for every table row under a header."""
    lines = text.splitlines()
    header = None
    for i, line in enumerate(lines):
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if header is None:
                header = cells
                continue
            if set(line.replace("|", "").strip()) <= set("- :"):
                continue
            yield header, cells
        else:
            header = None


def main():
    plan = PLAN.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")

    # 1. Every cited path exists.
    prefixes = ("Docs/", "Contracts/", "Fixtures/", "Scripts/", "Spikes/", "Packages/", "Apps/")
    missing, checked = [], 0
    for source_name, text, stage_relative in (("amendments", doc, True), ("plan", plan, False)):
        for token in sorted(set(re.findall(r"`([^`\n]+)`", text))):
            if "<" in token or ">" in token or token == SELF_LOG:
                continue
            path = None
            if stage_relative and (token.startswith("evidence/") or token.startswith("device-checklists/")):
                path = STAGE0 / token
            elif stage_relative and re.fullmatch(r"(G0\d-[A-Za-z]+|README|integration-log)\.md", token):
                path = STAGE0 / token
            elif token.startswith(prefixes):
                path = ROOT / token
            if path is None:
                continue
            checked += 1
            if not path.exists():
                missing.append(f"{source_name}: {token}")
    check(not missing, f"cited paths exist ({checked} checked; the run's own log excluded)", "; ".join(missing))

    # 2. Every numbered finding in the eight reports is in Section 2 or Section 3.
    reports = {
        "G01-EPUB.md": ("2.1 G0.1 EPUB", "G0.1 EPUB", "Findings that change the plan's scope or approach", r"^\*\*F(\d+)\.", "F"),
        "G01-PDF.md": ("2.2 G0.1 PDF", "G0.1 PDF", "Findings that change the plan's approach", r"^(\d+)\. \*\*", ""),
        "G02-Transfer.md": ("2.3 G0.2", "G0.2", "Findings that change the plan's scope or approach", r"^(\d+)\. \*\*", ""),
        "G03-Intake.md": ("2.4 G0.3", "G0.3", "Findings that change the plan's scope or approach", r"^\*\*F(\d+)\.", "F"),
        "G04-Audio.md": ("2.5 G0.4", "G0.4", "Findings that change scope or approach", r"^(\d+)\. \*\*", ""),
        "G05-AI.md": ("2.6 G0.5 AI", "G0.5 AI", "Findings that change scope or approach", r"^\*\*F(\d+)\.", "F"),
        "G05-Recovery.md": ("2.7 G0.5 Recovery", "G0.5 recovery", "Findings that change scope or approach", r"^\*\*F(\d+)\.", "F"),
        "G06-Design.md": ("2.8 G0.6", "G0.6", "Findings that change the plan's scope or approach", r"^(\d+)\. \*\*", ""),
    }
    no_change = defaultdict(set)
    for header, cells in table_rows(section_text(doc, "3. Findings that change nothing")):
        m = re.match(r"^(G0\.\d(?: EPUB| PDF| AI| recovery)?) (?:F(\d+)|finding (\d+))", cells[0])
        if m:
            no_change[m.group(1)].add(("F" + m.group(2)) if m.group(2) else m.group(3))
    total_findings = 0
    for report, (subsection, label, heading, pattern, prefix) in reports.items():
        rtext = (STAGE0 / report).read_text(encoding="utf-8")
        ids = [prefix + n for n in re.findall(pattern, section_text(rtext, heading), re.M)]
        total_findings += len(ids)
        listed = set()
        for header, cells in table_rows(section_text(doc, subsection)):
            m = re.match(r"^(F?\d+)(?: \([^)]*\))?\. ", cells[0])
            if m:
                listed.add(m.group(1))
        uncovered = [i for i in ids if i not in listed and i not in no_change[label]]
        check(ids and not uncovered, f"{report}: {len(ids)} findings, each in Section 2 or 3", ", ".join(uncovered) or "no findings parsed")

    # G0.6 "Other findings" bullets: each has a row in Section 3.
    g06 = (STAGE0 / "G06-Design.md").read_text(encoding="utf-8")
    bullets = re.findall(r"^- \*\*([^*]+)\*\*", section_text(g06, "Other findings"), re.M)
    keywords = [
        ("Status pills at AX5", "Status pills wrap"),
        ("Selection menu in Night", "selection menu is light in Night"),
        ("Rating stars in grayscale", "grayscale margin is moderate"),
        ("The audit", "layout audit"),
        ("Pills in the same family", "differ only by their phrase"),
        ("Test-only private call", "private accessibility call"),
        ("Previous WIP reviewed", "earlier WIP reviewed"),
        ("Part 3, earlier WIP reviewed", "earlier WIP reviewed"),
        ("The ViewThatFits phantom texts", "ViewThatFits"),
        ("Simulator launch refusals", "simulator launch refusals"),
        ("Where the prototype differs from the boards", "Where the prototype differs from the boards"),
        ("Example values only", "example host and model values"),
        ("Evidence size", "Evidence and reference images"),
    ]
    section3 = section_text(doc, "3. Findings that change nothing")
    unmatched = []
    for bullet in bullets:
        pairs = [k for p, k in keywords if bullet.strip().startswith(p)]
        if len(pairs) != 1 or pairs[0] not in section3:
            unmatched.append(bullet.strip())
    check(len(bullets) == len(keywords) and not unmatched,
          f"G06-Design.md: {len(bullets)} Other-findings bullets, each in Section 3", "; ".join(unmatched))

    # 3. Every open question in the reports is referenced in the amendments document.
    def referenced_numbers(label):
        nums = set()
        pattern = re.escape(label) + r" [^|;\n]*?open questions? ((?:\d+(?:, | and ))*\d+)"
        for m in re.finditer(pattern, doc):
            nums.update(int(n) for n in re.findall(r"\d+", m.group(1)))
        return nums

    numbered = dict([
        ("G01-EPUB.md", "G0.1 EPUB"),
        ("G01-PDF.md", "G0.1 PDF"),
        ("G02-Transfer.md", "G0.2"),
        ("G03-Intake.md", "G0.3"),
        ("G05-Recovery.md", "G0.5 recovery"),
        ("G06-Design.md", "G0.6"),
    ])
    for report, label in numbered.items():
        rtext = (STAGE0 / report).read_text(encoding="utf-8")
        count = len(re.findall(r"^\d+\. ", section_text(rtext, "Open questions"), re.M))
        missing_q = sorted(set(range(1, count + 1)) - referenced_numbers(label))
        check(count and not missing_q, f"{report}: {count} open questions, each referenced", ", ".join(map(str, missing_q)))
    ai = (STAGE0 / "G05-AI.md").read_text(encoding="utf-8")
    qs = sorted(int(n) for n in re.findall(r"^- \*\*Q(\d+)", section_text(ai, "Open questions"), re.M))
    missing_q = [q for q in qs if not re.search(r"G0\.5 AI Q" + str(q) + r"\b", doc)]
    check(qs and not missing_q, f"G05-AI.md: {len(qs)} open questions, each referenced", ", ".join(map(str, missing_q)))
    g04 = (STAGE0 / "G04-Audio.md").read_text(encoding="utf-8")
    g04_items = re.findall(r"^- (.*)$", section_text(g04, "Open questions"), re.M)
    sec3 = section_text(doc, "3. Findings that change nothing")
    sec5 = section_text(doc, "5. Questions for other owners")
    po_sources = dict()
    for header, cells in table_rows(section_text(doc, "4. Open questions only the product owner")):
        if header[0] == "ID" and len(cells) > 2:
            po_sources[cells[0]] = cells[2]
    # Each bullet: its opening words, where its coverage is, and what must be there.
    g04_map = [
        ("Product owner: decisions PO-1 to PO-6", "po", ["PO-17", "PO-18", "PO-19", "PO-20", "PO-39"]),
        ("Technical lead (M2): whether reading a file through", "s5",
         ["reading a file through removes the MP3 first-seek cost (G0.4 open questions"]),
        ("Design package (G0.6): the vocabulary has no key for \"the book is being opened\"", "s5",
         ["G0.4 open questions: the player's `preparing` state"]),
        ("Design package (G0.6): the vocabulary has no key for \"a quick-capture surface", "s5",
         ["`audio.nothing_to_capture` and `audio.moment_not_saved` keys"]),
        ("Design package (G0.6): the vocabulary has no phrase for the incomplete-edition warning", "s5",
         ["the incomplete-edition warning (`audio.edition_incomplete`"]),
        ("Contract consolidation: the audio anchor", "s5", ["the audio anchor and excerpt fields (G0.4 open questions"]),
        ("Warnings:", "s3", ["| G0.4 open questions, the warnings note |"]),
    ]
    g04_problems, used = [], set()
    for item in g04_items:
        hits = [m for m in g04_map if item.startswith(m[0])]
        if len(hits) != 1:
            g04_problems.append("no single mapping: " + item[:50])
            continue
        prefix, where, keys = hits[0]
        used.add(prefix)
        for key in keys:
            if where == "po":
                ok = key in po_sources and "G0.4 open questions" in po_sources[key]
            elif where == "s5":
                ok = key in sec5
            else:
                ok = key in sec3
            if not ok:
                g04_problems.append(prefix[:30] + " -> " + key)
    if len(used) != len(g04_map):
        g04_problems.append("%d mappings unused" % (len(g04_map) - len(used)))
    check(len(g04_items) == 7 and not g04_problems,
          "G04-Audio.md: %d open-question bullets (six questions and a warnings note), each matched to the entry that covers it"
          % len(g04_items), "; ".join(g04_problems))

    # 3a. Every consequence of ADR-0001 to ADR-0016 has its numbered item in Section 3.2 (ADR-0015 and ADR-0016 since
    # 20 October 2026: the M0 final review's second round, plan R2-06 and owner-readability R6-13, found them unmapped).
    adr_cells = dict()
    for header, cells in table_rows(section_text(doc, "3.2 ADR consequences")):
        if header[0] == "ADR" and re.fullmatch(r"ADR-00\d\d", cells[0]):
            adr_cells[cells[0]] = cells[1]
    known_tags = set("A%02d" % n for n in range(1, LAST_TAG + 1))
    adr_problems, adr_items = [], 0
    for n in range(1, 17):
        name = "ADR-%04d" % n
        files = sorted((ROOT / "Docs/ADRs").glob("%04d-*.md" % n))
        if len(files) != 1:
            adr_problems.append(name + ": file not found")
            continue
        bullets = re.findall(r"^- ", section_text(files[0].read_text(encoding="utf-8"), "Consequences"), re.M)
        adr_items += len(bullets)
        cell = adr_cells.get(name)
        if cell is None:
            adr_problems.append(name + ": no row")
            continue
        parts = re.split(r"\((\d+)\) ", cell)
        numbers = list(int(x) for x in parts[1::2])
        if numbers != list(range(1, len(bullets) + 1)):
            adr_problems.append("%s: items %s against %d bullets" % (name, numbers, len(bullets)))
        for number, text in zip(numbers, parts[2::2]):
            tags = set(re.findall(r"\bA\d\d\b", text)) & known_tags
            if "no change" not in text and not tags:
                adr_problems.append("%s item %d names neither a tag nor no change" % (name, number))
    check(len(adr_cells) == 16 and not adr_problems,
          "Section 3.2: ADR-0001 to ADR-0016, %d consequences, each mapped to a tag or to no change" % adr_items,
          "; ".join(adr_problems))

    # 4. Amendment tags: the plan body, Section 6 of the amendments and Appendix D agree, tag by tag and section by section.
    plan_tags = plan_tag_sections(plan)
    table6, table6_sources = dict(), dict()
    for header, cells in table_rows(section_text(doc, "6. Amendments applied")):
        if header[0] == "Tag" and re.fullmatch(r"A\d\d", cells[0]):
            table6[cells[0]] = normalize_sections(cells[2])
            table6_sources[cells[0]] = cells[3] if len(cells) > 3 else ""
    entry_match = re.search(r"\*\*Draft 0\.5 - proposed at the M0 gate, pending product-owner approval\.\*\*(.*?)\*\*Draft 0\.4 - ", plan, re.S)
    recheck_match = re.search(r"\*\*Draft 0\.7 - draft 0\.5 re-checked at the M0 final fix, pending product-owner approval\.\*\*(.*?)\*\*Draft 0\.6 - ", plan, re.S)
    appendix_d, by_entry = dict(), dict()
    for name, match in (("0.5", entry_match), ("0.7", recheck_match)):
        by_entry[name] = set()
        if match:
            for tag, cell in re.findall(r"^- \*\*(A\d\d)\*\* \(([^)]*)\):", match.group(1), re.M):
                if tag in appendix_d:
                    appendix_d[tag + " (twice)"] = set()
                appendix_d[tag] = normalize_sections(cell)
                by_entry[name].add(tag)
    check(bool(entry_match) and bool(recheck_match),
          "Appendix D has the draft 0.7 entry before draft 0.6, and the draft 0.5 entry before draft 0.4")
    expected = ["A%02d" % n for n in range(1, LAST_TAG + 1)]
    label = "A01-A%02d" % LAST_TAG
    check(sorted(table6) == expected, f"Section 6 lists tags {label} ({len(table6)} rows)", ", ".join(sorted(set(expected) ^ set(table6))))
    check(sorted(appendix_d) == expected, f"Appendix D lists tags {label} ({len(appendix_d)} bullets)", ", ".join(sorted(set(expected) ^ set(appendix_d))))
    check(by_entry["0.5"] == set(expected[:LAST_DRAFT_05_TAG]) and by_entry["0.7"] == set(expected[LAST_DRAFT_05_TAG:]),
          "Appendix D gives A01-A%02d their bullets in the draft 0.5 entry and A%02d-A%02d in the draft 0.7 entry"
          % (LAST_DRAFT_05_TAG, LAST_DRAFT_05_TAG + 1, LAST_TAG),
          "draft 0.5: %s; draft 0.7: %s" % (", ".join(sorted(by_entry["0.5"] ^ set(expected[:LAST_DRAFT_05_TAG]))),
                                            ", ".join(sorted(by_entry["0.7"] ^ set(expected[LAST_DRAFT_05_TAG:])))))
    check(sorted(plan_tags) == expected, f"the plan text carries every tag {label} ({len(plan_tags)} tags)", ", ".join(sorted(set(expected) ^ set(plan_tags))))
    mismatched = []
    for tag in expected:
        trio = (plan_tags.get(tag, set()), table6.get(tag, set()), appendix_d.get(tag, set()))
        if not (trio[0] == trio[1] == trio[2]):
            mismatched.append(f"{tag} plan={sorted(trio[0])} table={sorted(trio[1])} appendixD={sorted(trio[2])}")
    check(not mismatched, "each tag names the same plan sections in the text, Section 6 and Appendix D", " | ".join(mismatched))
    bad_tags = re.findall(r"\[M0-A(?:\d|\d\d\d+)\]", plan)
    check(not bad_tags, "every tag is well formed", ", ".join(bad_tags))

    # 4a. A47 (the decision register) collects exactly the tags that plan Section 23.1 carries.
    register = set(t for t, secs in plan_tags.items() if "23.1" in secs) - set(["A47"])
    collected = set(re.findall(r"\bA\d\d\b", table6_sources.get("A47", "")))
    check(bool(register) and collected == register,
          "A47 collects exactly the %d tags plan Section 23.1 carries" % len(register),
          "only in 23.1: %s; only in A47: %s" % (", ".join(sorted(register - collected)), ", ".join(sorted(collected - register))))

    # 5. Section 2 rows: six cells, an allowed class and a known tag.
    classes = ["scope narrowing", "approach change", "budget change", "value change", "new risk", "clarification"]
    bad_rows, counted = [], 0
    for header, cells in table_rows(section_text(doc, "2. Findings that change the plan")):
        if header[0] == "Finding":
            counted += 1
            if len(cells) == 6 and cells[4] in classes and cells[5] in table6:
                continue
            bad_rows.append(cells[0][:60])
    check(counted > 0 and not bad_rows, f"Section 2: {counted} rows, each with six cells, a class and a known tag", "; ".join(bad_rows))

    # 5a. Section 1 lists every scope narrowing, and plan Appendix D names the same tags.
    narrowing_tags, row_tags = set(), set()
    for header, cells in table_rows(section_text(doc, "2. Findings that change the plan")):
        if header[0] == "Finding" and len(cells) == 6:
            row_tags.add(cells[5])
            if cells[4] == "scope narrowing":
                narrowing_tags.add(cells[5])

    def section_tags(prefix):
        return set("A" + t for t in TAG.findall(section_text(doc, prefix)))

    forced = section_tags("1.1 Narrowings forced")
    unforced = section_tags("1.2 Narrowings no failed spike forces")
    kept = section_tags("1.3 Narrowings considered")
    listed = forced | unforced | kept
    check(bool(forced) and bool(unforced) and not (forced & unforced) and not (kept & (forced | unforced)),
          "Section 1: the tags of %d forced, %d unforced and %d considered-and-kept narrowings, none listed twice"
          % (len(forced), len(unforced), len(kept)))
    check(narrowing_tags <= (forced | unforced),
          "every scope-narrowing row's tag (%d tags) is in Section 1.1 or 1.2" % len(narrowing_tags),
          ", ".join(sorted(narrowing_tags - forced - unforced)))
    check(listed <= row_tags, "every Section 1 tag has a Section 2 row", ", ".join(sorted(listed - row_tags)))
    check(unforced <= narrowing_tags, "every Section 1.2 tag has a Section 2 row classified scope narrowing",
          ", ".join(sorted(unforced - narrowing_tags)))
    entry_intro = (entry_match.group(1) if entry_match else "").split("\n- **A01**", 1)[0]
    named = set(re.findall(r"\bA\d\d\b", entry_intro))
    check(named == listed, "plan Appendix D's draft 0.5 entry names exactly the %d Section 1 tags" % len(listed),
          "only in Appendix D: %s; only in Section 1: %s"
          % (", ".join(sorted(named - listed)), ", ".join(sorted(listed - named))))

    # 6. Section 4: PO-01 to PO-36 in order, six cells, and only known tags in the Applied column.
    ids, bad_po = [], []
    for header, cells in table_rows(section_text(doc, "4. Open questions only the product owner")):
        if header[0] == "ID":
            ids.append(cells[0])
            unknown = [t for t in re.findall(r"A\d\d", cells[5]) if t not in table6]
            if len(cells) == 6 and not unknown:
                continue
            bad_po.append(cells[0])
    check(ids == ["PO-%02d" % n for n in range(1, LAST_PO + 1)], f"Section 4 lists PO-01 to PO-{LAST_PO} in order ({len(ids)} rows)")
    check(not bad_po, "Section 4 rows have six cells and known tags", ", ".join(bad_po))

    # 7. Replaced plan text is gone and its replacement is present.
    gone = [
        "Status:** Draft 0.4",
        "No app code, performance results, platform spikes or compatibility tests have been executed",
        "must be pinned after the feasibility stage",
        "Literata roles scale through `UIFontMetrics`",
        "`UIFontMetrics` scaling, role enum",
        "1px rules and borders",
        "dashed 1px frame",
        "**Hairline:** 1px",
        "| 1px dashed",
        "with `ground` as the title color",
        "tints darken one step",
        "copyable code/link",
        "High-entropy code/link",
        "Retry transient connection/429/5xx",
        "Long selections crossing resource boundaries may require multiple anchors",
        "printed label when present",
        'no "continue into the next chapter" action is offered',
        "places snapshots on the source volume",
        "as an APFS clone does",
        "Only a normal end with visible answer text is `complete`.",
        "with three adapter workarounds",
        "native FLAC and Ogg Opus members are always remuxed",
        "Present it as a copyable code and a QR code",
        "excluded from device backup, except a bundle",
        "Release scope narrows only where a failed or narrowed spike forces it",
        "Four other narrowings, which no failed spike forces",
        "on devices as well as the simulator, before feature implementation begins",
        "revised after one agent review round",
        "Treat a 500, 502 or 504, and any 5xx",
        "proposed repair path: the damaged store is moved aside",
        "content documents must be well-formed XHTML with an XHTML `html` root, declared",
        "| Security + product; before M6;",
        # Replaced by the re-check (draft 0.7).
        "**Status:** Draft 0.6",
        "validates the clone: a copy still in progress fails",
        "the task window bounds those copies, a pause",
        "The task window bounds the outstanding tasks (four per job, proposed)",
        "Rows failed in three gates",
        "rows failed in three gates",
        "the G0.1 PDF report asks for it before M1",
        "(the G0.1 PDF report says before M1;",
        "are being written by M0 contract consolidation",
        "about 25-30 minutes",
        "took about 27 seconds",
        "about 27 s for a 10-hour",
        "(peak 48.1 MB)",
        "(stereo is downmixed, for speech)",
        "the measured cost on the host is small",
        "after scanning for 43-75 seconds",
        # Replaced by the product owner's decisions of 22 October 2026 (draft 0.8): each was an anchor the draft 0.7
        # checker required, and each said a decision was pending or proposed.
        "**Status:** Draft 0.7",
        "**Revised:** 20 October 2026",
        "and nothing bounds them across jobs yet",
        "nothing bounds them across jobs until the product owner chooses",
        "**Per-file timing mode (proposed, pending product-owner approval).**",
        "**Import remux (proposed, pending product-owner approval).**",
        "Which hosts count as local is proposed",
        "Every narrowing of release scope in draft 0.5 is a proposal.",
        "approving draft 0.5 does not by itself approve it",
        "Proposed for the job store (product-owner decision pending)",
        "| M0; the G0.5 recovery device steps (proposed, Section 21.1) [M0-A46] |",
        # The text the non-recommended decisions replaced (D-1, PO-13, PO-23, PO-39).
        "Proposed baseline is iPhone 12-class hardware",
        "on the iPhone 12-class baseline and an iPad",
        "Neither device is available yet (ADR-0001)",
        "while a paired Mac is reachable (product-owner decision pending)",
        "M1 also waits for the background-capable harness that repeats it",
        "Proposed: the app-level unavailable state before the first unlock is demonstrated in M1",
        "Resume-after-a-long-pause may rewind a configurable small amount",
        "Offer a bundled, licensed short sample for trying capture without networking.",
        # Replaced on 23 October 2026, when the product owner's answers of that day were recorded within draft 0.8.
        "**Revised:** 22 October 2026",
        # Replaced on 24 October 2026, when the product owner's decision of that day on device A was recorded within
        # draft 0.8 (the follow-up's fix's version required this anchor).
        "**Revised:** 23 October 2026",
        # Replaced on 26 October 2026, when that record was completed before any review (this checker's first version,
        # of 24 October 2026, required this anchor).
        "**Revised:** 24 October 2026",
    ]
    present = [
        # Draft 0.8 (22 October 2026): the draft 0.7 checker required "**Status:** Draft 0.7" and
        # "**Revised:** 20 October 2026" here; those are now in the list of replaced phrases above.
        "**Status:** Draft 0.8",
        # 24 October 2026: the revision date moved with the decision of that day on device A, and on 26 October 2026
        # with the completion of that record (the follow-up's fix's version required "**Revised:** 23 October 2026"
        # here, the first fix's "**Revised:** 22 October 2026", and this checker's first version "**Revised:** 24
        # October 2026"; all three are now in the list of replaced phrases above).
        "**Revised:** 26 October 2026",
        "Not yet the versioned 1.0 execution specification: Section 23.3 says that follows the M0 exit, which waits for the device sessions.",
        "**Draft 0.8 - 22 October 2026: the product owner's decisions on the M0 gate's questions recorded.**",
        "**Approved by the product owner on 22 October 2026.** The product owner approved every decision below, D01 to D17",
        "**Draft 0.7 - draft 0.5 re-checked at the M0 final fix, pending product-owner approval.**",
        "A raw file has no manifest and no end record, so nothing proves it complete",
        "the task window bounds those copies per job, and in the Stage 0 spike nothing bounds them across jobs",
        "across jobs, the job scheduler lets two jobs download at a time, so at most eight requests carrying a token wait (PO-38 (a)",
        "Rows failed in four gates on the simulator",
        "rows failed in four gates, each changing the approach",
        "| A raw file copied with Finder can be staged incomplete |",
        "| A linked dependency carries an advisory with no fixed release: marmelroy/Zip 2.1.2, CVE-2023-39135",
        "each line rectangle of a PDF anchor also carries the line's reading direction",
        "Text holding U+0000 cannot be stored exactly",
        "**Draft 0.5 - proposed at the M0 gate, pending product-owner approval.**",
        "| D16 - Tailscale route and ATS |",
        "| D17 - Data protection and durability |",
        "**Vocabulary gaps found in Stage 0 (draft 0.5, pending design review).**",
        "**Per-file timing mode (decided by the product owner on 22 October 2026, PO-20).**",
        "**Import remux (decided by the product owner on 22 October 2026, PO-20).**",
        "**Stage 0 status at the M0 gate (draft 0.5).**",
        "**At the M0 gate (draft 0.5) the ranges are unchanged.**",
        "takes about twice its original's space on the device",
        "the capture flow offers an action that extends a quotation into the next chapter",
        "Present it as a copyable code and optionally a QR code",
        "Which hosts count as local was decided by the product owner on 22 October 2026 (PO-36 (a)",
        "ends `complete` with outcome `refusal` or `content_filtered`",
        "| Background download tasks hold the bearer token",
        "| Real-world EPUBs fall outside the compatibility subset",
        "G0.3, and G0.6, whose design package every screen from M2 on is built from",
        "Every narrowing of release scope in draft 0.5 was a proposal.",
        "Every narrowing of release scope is a proposal.",
        "so approving draft 0.5 did not by itself approve it: the product owner decided each of them explicitly on 22 October 2026",
        "approving this draft does not by itself approve them",
        "Treat every other 5xx (a 500, 502 or 504 among them)",
        "Decided for the job store by the product owner on 22 October 2026 (PO-12 (a))",
        "a content document declared `application/xhtml+xml` or `text/html` in the manifest must be well-formed XHTML",
        "signed at the M0 gate like every decision here",
        "EPUBs are imported only as single files, so a folder is refused that way on every route, a narrowing no failed spike forces",
        "the alternative asks the user whether to resend the earlier turns",
    ]
    doc_gone = [
        "Release scope narrows only where a failed or narrowed spike forces it",
        "Four further narrowings that no failed spike forces",
        "ask before resending after a 500, a 502 or 504 from any endpoint",
        "19.1 already says the simulator establishes no network or background behavior",
        "proposed repair path: the damaged store is moved aside",
        "Collects A01, A13, A14",
        "content documents must be well-formed XHTML declared as XHTML or HTML",
        # Replaced by the re-check (draft 0.7): stale mappings and the old count.
        "Rows failed in three gates",
        "to restore the class-B evidence for the current code (G0.5 recovery open question 7)",
        "(integration log row 6; open question 8)",
        "(in progress on its own branch)",
    ]
    still = [g for g in gone if g in plan]
    lacking = [p for p in present if p not in plan]
    doc_still = [g for g in doc_gone if g in doc]
    check(not still and not doc_still,
          f"replaced phrases are absent ({len(gone)} from the plan, {len(doc_gone)} from this document)",
          "; ".join(still + doc_still))
    check(not lacking, f"new anchor phrases are present in the plan ({len(present)})", "; ".join(lacking))

    # 7b. T54 names every section that the 4.4.6 gaps table sends into the vocabulary.
    gaps_region = plan.split("**Vocabulary gaps found in Stage 0", 1)[1].split("### 4.4.7", 1)[0]
    gap_sections = set()
    for header, cells in table_rows(gaps_region):
        if header[:2] == ["Moment", "State machine"] and len(cells) > 1:
            gap_sections |= set(re.findall(r"\d+(?:\.\d+)*", cells[1]))
    t54_rows = [line for line in plan.splitlines() if line.startswith("| T54 |")]
    t54_sections = set(re.findall(r"(?<![\w.])\d+(?:\.\d+)*(?![\w.])", t54_rows[0])) if len(t54_rows) == 1 else set()
    check(bool(gap_sections) and gap_sections <= t54_sections,
          "T54 names every section the 4.4.6 gaps table names (%d sections)" % len(gap_sections),
          "missing from T54: %s" % ", ".join(sorted(gap_sections - t54_sections, key=lambda s: [int(x) for x in s.split(".")])))

    # 7c. The milestone gating rule includes M1 in every place that states it, and the earlier
    # wording, under which M1 started before its device steps, is gone.
    def line_with(text, prefix):
        found = [line for line in text.splitlines() if line.startswith(prefix)]
        return found[0] if len(found) == 1 else ""

    gating = [
        ("plan introduction", line_with(plan, "This is a greenfield implementation proposal"),
         "each milestone, M1 included, starts only after the device steps of the gates it builds on have passed"),
        ("plan 21.1", section_text(plan, "21.1 Stage 0"),
         "each milestone, M1 included, starts only after the device steps of the gates it builds on have passed on the iPhone available now (M1: G0.5 recovery steps 1-4,"),
        # Draft 0.8: "(proposed, Section 21.1)" became "(Section 21.1)" when the product owner decided PO-34.
        ("plan 21.2 M1 row", line_with(plan, "| M1 - Durable foundation |"),
         "| M0; the G0.5 recovery device steps (Section 21.1) [M0-A46] |"),
        ("plan device-evidence risk row", line_with(plan, "| No device evidence yet;"),
         "each milestone, M1 included, starts after the device steps it builds on have passed on the iPhone available now"),
        ("plan Appendix D A46", line_with(plan, "- **A46**"),
         "each milestone, M1 included, starts after its gates' device steps on the iPhone available now (M1: G0.5 recovery steps 1-4;"),
        ("amendments Section 2.9 row", line_with(doc, "| No device evidence:"),
         "each milestone, M1 included, starts after the device steps of the gates it builds on pass on the iPhone available now (M1: G0.5 recovery steps 1-4;"),
        ("amendments PO-34", line_with(doc, "| PO-34 |"),
         "(b) start each milestone, M1 included, after the device steps of the gates it builds on pass on the iPhone available now (M1: G0.5 recovery steps 1-4,"),
    ]
    gating_problems = [name for name, text, phrase in gating if phrase not in text]
    po34 = line_with(doc, "| PO-34 |").split(" | ")
    if len(po34) < 5 or not po34[4].startswith("(b), "):
        gating_problems.append("PO-34's recommended default is not (b)")
    outside_po34 = doc.replace(line_with(doc, "| PO-34 |"), "")
    for old in ("M1 starts after the M0 review", "exits after the G0.5 recovery device steps",
                "exits only after the G0.5 recovery device steps"):
        if old in plan:
            gating_problems.append("plan still says: " + old)
        if old in outside_po34:
            gating_problems.append("this document says, outside PO-34's option (c): " + old)
    check(not gating_problems,
          "the milestone gating rule includes M1 in all %d places that state it, and the earlier wording is gone" % len(gating),
          "; ".join(gating_problems))

    # 7a. Every phrase quoted in plan Sections 1-23 is in the design package, in the 4.4.6 gaps
    # table or its introduction, or in NOT_INTERFACE_TEXT with its reason.
    tokens = json.loads((ROOT / "Contracts/design/marginalia.v1.json").read_text(encoding="utf-8"))
    package_phrases = set(v.lower() for v in tokens["vocabulary"].values())
    package_phrases |= set(v.lower() for v in tokens["labels"].values())
    package_phrases |= set(p.lower() for p in tokens["lint"]["forbidden_phrases"])
    fence, hash_mark = chr(96) * 3, chr(35)
    body = plan.split("\n" + hash_mark + " 24. ", 1)[0]
    body = re.sub(re.escape(fence) + ".*?" + re.escape(fence), "", body, flags=re.S)
    gaps_text = body.split("**Vocabulary gaps found in Stage 0", 1)[1].split(hash_mark * 3 + " 4.4.7", 1)[0].lower()
    quoted_phrases = dict()
    for line in body.splitlines():
        for phrase in re.findall(r'"([^"\n]*)"', line):
            if len(phrase) >= 2:
                quoted_phrases[phrase.lower()] = phrase
    uncovered = []
    for low, phrase in sorted(quoted_phrases.items()):
        if low in package_phrases or low in NOT_INTERFACE_TEXT:
            continue
        if re.search(r"(?<![a-z0-9])" + re.escape(low) + r"(?![a-z0-9])", gaps_text):
            continue
        uncovered.append(phrase)
    stale = sorted(k for k in NOT_INTERFACE_TEXT if k not in quoted_phrases)
    check(not uncovered and not stale,
          "plan Sections 1-23: %d quoted phrases, each in the design package, in the 4.4.6 gaps table or its "
          "introduction, or listed as not interface text (%d)" % (len(quoted_phrases), len(NOT_INTERFACE_TEXT)),
          "uncovered: %s; listed but no longer quoted: %s" % ("; ".join(uncovered), "; ".join(stale)))

    # 8. Every table row in both files has as many cells as its header.
    for name, text in (("plan", plan), ("amendments", doc)):
        ragged = [f"{len(h)}/{len(c)}: {c[0][:40]}" for h, c in table_rows(text) if len(h) - len(c)]
        rows = sum(1 for _ in table_rows(text))
        check(not ragged, f"{name}: {rows} table rows, none ragged", "; ".join(ragged))

    # 9. Sections left unchanged on purpose equal their last revision by the product owner: Sections 2.2 and 21.5 and
    # the budget values plan draft 0.4 at commit 471b143; Section 24 draft 0.6 as written on main (0ef8c39), which
    # revised the roadmap and is merged unchanged (177ed9a).
    import hashlib
    base = [
        ("2.2 Non-negotiable", "a0d848691c7313e03ba33b4a58650e2d394b503066c61f2783e93f542d71dd27", "draft 0.4 (471b143)"),
        ("21.5 Safe scope", "d975a0694524538c7591ad98da9dfde60d94c6d4ce62b4ab06337a1fe2578923", "draft 0.4 (471b143)"),
        ("24. Roadmap", "7062f657073beec13b7dcd54cfa90ea69d8105eef28083fa19b44da3588c39bf", "draft 0.6 (0ef8c39)"),
    ]
    for prefix, digest, revision in base:
        lines = []
        level = None
        for line in plan.splitlines():
            m = re.match(r"^(#+) (.*)$", line)
            if m and level is None and m.group(2).startswith(prefix):
                level = len(m.group(1))
                lines.append(line)
                continue
            if level is not None:
                if m and len(m.group(1)) <= level:
                    break
                lines.append(line)
        actual = hashlib.sha256("\n".join(lines).encode()).hexdigest()
        check(actual == digest, f"Section {prefix.split()[0].rstrip('.')} is byte-identical to {revision}", actual)
    budgets = re.findall(r"^\| [^|]+ \| ([^|]+) \|", section_text(plan, "19.2 Proposed"), re.M)[2:]
    base_budgets = ["p95 <= 2.5 seconds", "p95 <= 500 ms", "p95 <= 200 ms", "p95 <= 1.5 seconds",
                    "p95 <= 2 seconds", "<= 5 seconds", "No sustained main-thread stalls over 100 ms",
                    "Within 500 ms of intended boundary", "Bounded; no growth proportional to file size",
                    "Zero missing items in fault tests"]
    check(budgets == base_budgets, f"the {len(base_budgets)} budget values of Section 19.2 equal draft 0.4", "; ".join(budgets))

    # 10. Draft 0.8 (22 October 2026): the product owner's decisions are recorded, and the five that are not the
    # recommendation are applied where the plan states them. Approval is not a device result, so these checks look
    # for the decisions and for the pending device and sign-off steps beside them, never for a passed device step.
    marker = "\n# Appendix D. Change log"
    before_d = plan.split(marker, 1)[0]
    after_d = plan.split(marker, 1)[1] if marker in plan else ""

    # 10a. No sentence before Appendix D still says that a product-owner decision or approval is pending. The
    # Prepared and Revised line is exempt: it is the dated history of the drafts, and records drafts 0.5 and 0.7 as
    # they were proposed. Pending design reviews, security sign-offs and device steps are not matched: they stay.
    pending = re.compile(
        r"pending product-owner approval|product-owner (?:decision|approval|confirmation) pending|"
        r"product-owner decision \(pending\)|product-owner and security decision pending|"
        r"product and design decision pending|security review and product-owner decision pending|"
        r"\(pending approval|approval pending|the product owner confirms|the product owner chooses it|"
        r"awaits? the product owner", re.I)
    pending_hits = []
    for number, line in enumerate(before_d.splitlines(), 1):
        if line.startswith("**Prepared:**"):
            continue
        for m in pending.finditer(line):
            pending_hits.append("line %d: ...%s..." % (number, line[max(0, m.start() - 40):m.end() + 20]))
    check(not pending_hits,
          "draft 0.8: no sentence before Appendix D says a product-owner decision or approval is pending "
          "(the dated Revised line excepted)", "; ".join(pending_hits))

    # 10b. Section 23.1: D01-D17 in order, each recorded as approved on 22 October 2026, none still "Proposed default".
    rows231, headers231 = [], []
    for header, cells in table_rows(section_text(plan, "23.1 Decisions")):
        if header[0] == "Decision":
            headers231.append(header[1])
            rows231.append(cells)
    ids231 = []
    for cells in rows231:
        m = re.match(r"(D\d\d) - ", cells[0])
        ids231.append(m.group(1) if m else cells[0][:20])
    unapproved = [i for i, cells in zip(ids231, rows231)
                  if "Approved by the product owner on 22 October 2026" not in cells[-1]
                  or re.search(r"approval pending|Proposed default", " | ".join(cells))]
    check(ids231 == ["D%02d" % n for n in range(1, 18)] and not unapproved
          and all(h != "Proposed default" for h in headers231),
          "draft 0.8: Section 23.1 lists D01-D17, each recorded as approved by the product owner on 22 October 2026 "
          "(%d rows)" % len(rows231),
          "rows: %s; not recorded as approved: %s; column headed: %s"
          % (", ".join(ids231), ", ".join(unapproved), ", ".join(sorted(set(headers231)))))

    # 10c. The five decisions that are not the recommendation, applied where the plan states them; and before
    # Appendix D only Section 19.1 still names the iPhone 12-class hardware the recommendation of D-1 kept, as history.
    # 24 October 2026: D-1's part (i) was decided again (device A the iPhone 13 mini), so its anchors are the decision
    # of that day, read in 19.1's current text (before its dated history), and the wording of 22 October 2026 must be
    # gone from that current text; the follow-up's fix's version required the iPhone 11 Pro's anchors here.
    sec = lambda prefix: section_text(plan, prefix)  # noqa: E731
    s191 = sec("19.1 Reference")
    current191 = s191.split("(Until 22 October 2026 this section proposed", 1)[0]
    history191 = s191[len(current191):]
    five = [
        ("D-1 (19.1)", current191, [
            "is an iPhone 13 mini: the iPhone 11 Pro chosen on 22 October 2026 no longer charges, and on 24 October 2026 "
            "the product owner decided that device A is the iPhone 13 mini the owner has (the runbook's decision D-1, "
            "taken again)",
            "It lays out at 375 × 812 pt, as the iPhone 11 Pro does, and draws each point about 8% smaller",
            "Its chip, Apple's A15, is two generations newer than the A13 of the oldest iPhones iOS 26 supports",
            "a budget of Section 19.2 it meets is not shown to hold on an A13 phone, and a budget it misses is a failure, "
            "recorded; no budget value changes",
            "No A13 iPhone is measured in M0: on 24 October 2026 the product owner left the A13 floor for M8's release "
            "device matrix (Section 21.2), where the Section 19.2 budgets are to be measured on an A13 iPhone",
            "The iPhone 11 is not device A",
            "is not available on a device and stays a simulator check"]),
        ("D-1 (19.1, its history)", history191, [
            "and until 24 October 2026 it said that the baseline, the oldest supported iPhone, is an iPhone 11 Pro: the "
            "product owner chose the iPhone 11 family on 22 October 2026"]),
        ("D-1 (21.1)", sec("21.1 Stage 0"), [
            "on the baseline iPhone (device A, an iPhone 13 mini since 24 October 2026; Section 19.1) and an iPad"]),
        ("PO-13 (15.1)", sec("15.1 Connectivity"), [
            "Decided by the product owner on 22 October 2026 (PO-13 (b))",
            "and also periodically in the background whenever iOS gives the app background time",
            "adds no promise of timely delivery"]),
        ("PO-23 (T50)", line_with(plan, "| T50 |"), [
            "Stage 0 builds a background-audio harness for the locked-device check (G0.5 recovery device step 3) "
            "before the device run",
            "the app-level unavailable state before the first unlock is demonstrated in M1 with the app shell"]),
        ("PO-23 (21.1)", sec("21.1 Stage 0"), [
            "Stage 0 builds a background-audio harness for G0.5 recovery step 3 before the device run"]),
        ("PO-23 (21.2)", line_with(plan, "| M1 - Durable foundation |"), ["Stage 0 builds the locked-device harness"]),
        ("PO-33 (4.2)", sec("4.2 Onboarding"), [
            "three ship in M2, each a short excerpt of a Standard Ebooks (CC0) edition: *Middlemarch*, *Walden* and "
            "*Meditations*",
            "clearly marked as a sample and removable",
            "*Meditations* is paired with an excerpt of its LibriVox recording (public domain)",
            "`Fixtures/LICENSES.md`"]),
        ("PO-33 (21.2)", line_with(plan, "| M2 - Direct ingestion |"), [
            "the three bundled onboarding samples (Section 4.2; PO-33"]),
        ("PO-39 (10.1)", sec("10.1 Playback"), [
            "**Playback control defaults (decided by the product owner on 22 October 2026, PO-39).**",
            "Skip intervals default to 15 seconds back and 15 seconds forward",
            "The sleep timer offers both kinds",
            "Resuming after a long pause rewinds by default, graduated as other audiobook players do: about 10 seconds "
            "after a pause of a few minutes, rising to about 60 seconds after a pause of a day",
            "a brief notice that offers to undo it",
            "can be turned off, in Settings",
            "it never changes a saved bookmark, quote or capture anchor"]),
        ("PO-39 (4.4.6)", line_with(plan, "| Playback | Section 10.1 |"), [
            "the brief notice that playback resumed earlier after a long pause, with its action that undoes the rewind"]),
    ]
    missing5 = ["%s: %s" % (name, phrase) for name, text, phrases in five for phrase in phrases if phrase not in text]
    stale12 = [line[:80] for line in before_d.splitlines()
               if "12-class" in line and not line.startswith("Use at least one older supported physical iPhone")]
    # The wording of 22 October 2026 that D-1's new decision replaced, now only in 19.1's dated history.
    stale_d1 = [g for g in ("is an iPhone 11 Pro", "the iPhone 11 is a second A13 phone", "is stricter to meet",
                            "the oldest supported iPhone (device A") if g in current191]
    check(not missing5 and not stale12 and not stale_d1,
          "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation (D-1, decided "
          "again on 24 October 2026, PO-13, PO-23, PO-33, PO-39) are applied where the plan states them, and before "
          "Appendix D only Section 19.1 names iPhone 12-class hardware",
          "; ".join(missing5 + ["12-class outside Section 19.1: " + line for line in stale12]
                    + ["19.1's current text still says: " + g for g in stale_d1]))

    # 10d. Section 23.3: who signs, that no role is signed yet, that every review so far was an agent's, and the
    # outside security review recommended before any public release.
    signoff = sec("23.3 Review sign-off")
    signoff_phrases = [
        "Sylvia is a solo project. The product owner signs the roles of the security reviewer, QA, design and the "
        "technical lead above personally",
        "only after the device sessions have produced the evidence that role signs",
        "until then each stays pending, and none is signed in this draft",
        "it is no role's sign-off and no device result",
        "Every review of the M0 work so far was made by agents, not by independent people",
        "a security review by someone outside the project is recommended",
    ]
    check(all(p in signoff for p in signoff_phrases),
          "draft 0.8: Section 23.3 records who signs, that no role is signed yet, that every review so far was an "
          "agent's, and the outside security review",
          "; ".join(p for p in signoff_phrases if p not in signoff))

    # 10e. Appendix D opens with the draft 0.8 entry, which lists exactly the five decisions that are not the
    # recommendation and states that it is agent-written and not reviewed.
    entry08 = re.search(r"\*\*Draft 0\.8 - 22 October 2026: the product owner's decisions on the M0 gate's questions "
                        r"recorded\.\*\*(.*?)\*\*Draft 0\.7 - ", plan, re.S)
    body08 = entry08.group(1) if entry08 else ""
    bullets08 = re.findall(r"^- \*\*((?:PO|D)-\d+)\*\* \(", body08, re.M)
    first_entry = re.search(r"^\*\*Draft (\d\.\d) - ", after_d, re.M)
    check(bool(entry08) and sorted(bullets08) == ["D-1", "PO-13", "PO-23", "PO-33", "PO-39"]
          and first_entry is not None and first_entry.group(1) == "0.8"
          and "Agent-written; not reviewed; human sign-off pending." in body08,
          "draft 0.8: Appendix D opens with the draft 0.8 entry, which lists exactly the five decisions that are not "
          "the recommendation and says it is agent-written and not reviewed",
          "entry found: %s; its bullets: %s; first entry: %s"
          % (bool(entry08), ", ".join(bullets08) or "none", first_entry.group(1) if first_entry else "none"))

    # 10f. PO-12's sources file and import ledger: no option was recommended or chosen on 22 October 2026, and the
    # product owner decided both on 23 October 2026 (set aside and recover). 15.5 records that decision, the wording
    # that left them open is gone, and the wording the review of the decisions round found (FID-01) stays gone. (The
    # first fix's 10f required them open; replaced by the follow-up of 23 October 2026.)
    s155 = sec("15.5 Recovery")
    po12_phrases = [
        "Decided for the job store by the product owner on 22 October 2026 (PO-12 (a))",
        "approving PO-12 as recommended chose nothing for them",
        "Decided for the sources file and the import ledger by the product owner on 23 October 2026: each is set aside "
        "and recovered",
        "A damaged sources file is moved aside for the diagnostic export and every Mac is paired again",
        "a damaged import ledger is moved aside",
        "an item already imported may arrive again as a duplicate for review (Sections 7.3 and 8.1)",
        "transfers keep working",
    ]
    po12_gone_plan = ["the product owner's decision keeps it so", "the decision keeps it so"]
    po12_gone_before_d = [
        "a repair path for a damaged sources file or import ledger is still the product owner's to decide",
        "until it is decided a damaged one keeps the client's launch deferred",
    ]
    check(all(p in s155 for p in po12_phrases) and not any(g in plan for g in po12_gone_plan)
          and not any(g in before_d for g in po12_gone_before_d),
          "draft 0.8 as revised on 23 October 2026: 15.5 records the product owner's decision on PO-12's sources file and "
          "import ledger, and no text before Appendix D leaves them open or says a decision kept them so",
          "; ".join(["15.5 lacks: " + p for p in po12_phrases if p not in s155]
                    + ["the plan still says: " + g for g in po12_gone_plan if g in plan]
                    + ["before Appendix D the plan still says: " + g for g in po12_gone_before_d if g in before_d]))

    # 10g. PO-41 to PO-44, the questions left for counsel: the product owner took them on for now on 23 October 2026.
    # D13's row records it for PO-42, which had no default, and its approval of 22 October 2026 stays; the sentence that
    # left PO-42 pending with counsel is gone.
    d13 = line_with(plan, "| D13 - Distribution |")
    d13_phrases = [
        "Approved by the product owner on 22 October 2026",
        "on 23 October 2026 the product owner took it on for now, with PO-41, PO-43 and PO-44",
        "the owner's own and TestFlight builds carry the notices the licenses require",
        "a lawyer's review, the advertising clauses included, comes before any public App Store release",
        # The follow-up's fix (FID4-05): the answer names neither the companion's notarized builds nor its release.
        "the answer does not name the notarized companion's builds, so PO-42 is still settled before one is distributed "
        "beyond the team",
    ]
    d13_gone = "Pending: whether BoringSSL's advertising clauses are acceptable for the notarized companion is left to counsel"
    d13_reading = "read as before the companion's public release too"
    check(all(p in d13 for p in d13_phrases) and d13_gone not in plan and d13_reading not in plan,
          "draft 0.8 as revised on 23 October 2026: D13's row records that the product owner took PO-42, with PO-41, "
          "PO-43 and PO-44, on for now, a lawyer's review before any public App Store release",
          "; ".join(["D13 lacks: " + p for p in d13_phrases if p not in d13]
                    + (["the plan still says: " + d13_gone] if d13_gone in plan else [])
                    + (["the plan still says: " + d13_reading] if d13_reading in plan else [])))

    # 10h. The iPad: the product owner has one (23 October 2026). 19.1, 21.1 and the device-evidence risk row say so,
    # and no text before Appendix D says that none is recorded as available or asks to acquire one.
    ipad = [
        ("19.1", sec("19.1 Reference"), [
            "the product owner has an iPad with a hardware keyboard and a trackpad or mouse (23 October 2026)"]),
        # The follow-up's fix (FID4-03): no device has to be acquired only if the iPad runs iPadOS 26 or later.
        ("21.1", sec("21.1 Stage 0"), [
            "has an iPad with a hardware keyboard and a trackpad or mouse (23 October 2026; ADR-0001), whose model and "
            "iPadOS the device runbook records at Session 0",
            "no device has to be acquired if that iPad runs iPadOS 26 or later, which every Stage 0 harness needs and the "
            "runbook checks before Session 0"]),
        ("23.2", line_with(plan, "| No device evidence yet;"), [
            "the baseline iPhone and an iPad are at hand but untested",
            "the product owner has an iPad with a keyboard and a trackpad or mouse (23 October 2026)"]),
    ]
    ipad_missing = ["%s: %s" % (name, phrase) for name, text, phrases in ipad for phrase in phrases if phrase not in text]
    ipad_gone = [g for g in ("no iPad is recorded as available", "acquire an iPad",
                             "(23 October 2026; ADR-0001), so no device has to be acquired") if g in before_d]
    check(not ipad_missing and not ipad_gone,
          "draft 0.8 as revised on 23 October 2026: 19.1, 21.1 and the device-evidence risk row record the product "
          "owner's iPad, and no text before Appendix D says none is available or asks to acquire one",
          "; ".join(ipad_missing + ["before Appendix D the plan still says: " + g for g in ipad_gone]))

    # 10i. Appendix D's draft 0.8 entry ends with the dated item that records the answers of 23 October 2026, each of
    # them named, the item that corrects it after the review of the follow-up and, last, the dated item of 24 October
    # 2026 on device A (10k reads its content), before the draft 0.7 entry; 10e still requires the entry's five bullets
    # and its review statement. (The follow-up's version required the dated item of 23 October 2026 to be the last; the
    # follow-up's fix added the correction after it, and the update of 24 October 2026 the item of that day.)
    items08 = [line for line in body08.rstrip().split("\n") if line.startswith("- ")]
    last_item = items08[-3] if len(items08) >= 3 else ""
    corrected_item = items08[-2] if len(items08) >= 2 else ""
    item_24 = items08[-1] if items08 else ""
    answers = [
        "*Recorded on 23 October 2026, within draft 0.8:",
        "PO-12's sources file and import ledger: set aside and recover",
        "PO-41 to PO-44, the questions left for counsel, PO-42 included: the product owner handles them for now",
        "a lawyer's review comes before any public App Store release",
        "The iPad: the product owner has one with a keyboard and a trackpad or mouse",
        "H-1's exception also covers pull request #5",
        "The readings of D-6, D-7 and D-9 (b) are confirmed",
        "Agent-written; not reviewed.*",
    ]
    corrections = [
        "- *Corrected on 23 October 2026, after an agent review of the item above, the review of the follow-up of the "
        "decisions round (its findings FID4-03, FID4-04 and FID4-05):",
        "now makes that depend on the device runbook's check, before its Session 0, that the iPad runs iPadOS 26 or later",
        "so for the companion's notarized builds PO-42 is still settled before one is distributed beyond the team",
        "No budget, scope or decision changed. Agent-written; not reviewed.*",
    ]
    item_24_ok = item_24.startswith("- *Recorded on 24 October 2026, within draft 0.8:")
    check(last_item.startswith("- *Recorded on 23 October 2026") and all(a in last_item for a in answers)
          and all(c in corrected_item for c in corrections) and item_24_ok,
          "draft 0.8 as revised on 24 October 2026: Appendix D's draft 0.8 entry ends with the dated item that records "
          "the answers of 23 October 2026, the item that corrects it and the dated item of 24 October 2026",
          "; ".join(["the dated item lacks: " + a for a in answers if a not in last_item]
                    + ["the correction item lacks: " + c for c in corrections if c not in corrected_item]
                    + ([] if item_24_ok else ["the last item is not the dated item of 24 October 2026"]))
          or "the entry's last three items are not the dated item of 23 October 2026, its correction and the item of "
             "24 October 2026")

    # 10j. (The follow-up's fix, 23 October 2026; the review of the follow-up, its finding FID4-04.) The entry's items
    # that left PO-12's two parts and PO-42 open point to the answers of 23 October 2026, the item on the decisions with
    # no plan text says D13's row "then" left PO-42 with counsel, and the entry's review note names the fourth review.
    j_phrases = [
        "and both stay open with the product owner, as `Docs/Stage0/M0-gate.md`, the amendments and ADR-0009 say (decided "
        "on 23 October 2026, set aside and recover: the item recorded that day, below)",
        "PO-42 has no default and stays with counsel, as D13's row then said (23 October 2026: the product owner took all "
        "four on for now, the item recorded that day, below)",
        "decided on 23 October 2026, the item recorded that day, below)",
        "were read by a fourth agent review the same day, whose findings named three defects in them, corrected in the last "
        "item of this entry",
    ]
    j_gone = ["as D13's row now says", "(the last item of this entry) have not been reviewed"]
    check(all(p in body08 for p in j_phrases) and not any(g in plan for g in j_gone),
          "draft 0.8 as corrected on 23 October 2026: Appendix D's draft 0.8 entry points its items on PO-12 and PO-42 "
          "to the answers of 23 October 2026, and its review note names the fourth review",
          "; ".join(["the entry lacks: " + p for p in j_phrases if p not in body08]
                    + ["the plan still says: " + g for g in j_gone if g in plan]))

    # 10k. (24 October 2026, the update of the M0 records for the device-A change.) The product owner's decision of that
    # day, D-1 taken again (device A the iPhone 13 mini; the A13 floor left for M8's release device matrix), is recorded
    # wherever the plan and this document state device A, and the statements it made stale are gone from the plan before
    # Appendix D. 10c reads 19.1 and 21.1's baseline iPhone; this check reads the rest.
    m8 = line_with(plan, "| M8 - Release hardening and pilot |")
    d01 = line_with(plan, "| D01 - Platform floor |")
    literata = line_with(plan, "| Literata or Dynamic Type scaling fails on the oldest device |")
    evidence_row = line_with(plan, "| No device evidence yet;")
    s214 = sec("21.4 Effort model")
    k_plan = [
        ("the Status line", line_with(plan, "**Status:** Draft 0.8"), [
            "and so is the owner's decision of 24 October 2026 to take decision D-1 again, the iPhone 11 Pro chosen as "
            "device A no longer charging: device A is the owner's iPhone 13 mini, and the A13, the oldest chip iOS 26 "
            "supports, is left for M8's release device matrix"]),
        ("the Revised line", line_with(plan, "**Prepared:**"), [
            "24 October: the product owner's decision of that day on device A recorded within draft 0.8",
            "26 October: that record completed before any review, two of its wordings corrected (D01's row and Section "
            "19.1)",
            # 26 October 2026, the fix of the review's accuracy findings (ACC-06).
            "The same day, after an agent review of that record, a dated note on Apple's release notes for Xcode 27.1 "
            "added to D01's row, and the record's review status given."]),
        ("21.1", sec("21.1 Stage 0"), [
            "The product owner has device A (24 October 2026; until then device A was the owner's iPhone 11 Pro, which no "
            "longer charges",
            "G0.6's check of the type roles on the oldest supported iPhone (above) is made on device A, whose screen in "
            "points, 375 × 812, is the iPhone 11 Pro's: among the oldest iPhones iOS 26 supports only the iPhone SE (2nd "
            "generation) has a smaller one, 375 × 667 pt, which stays a simulator check"]),
        ("21.2's M8 row", m8, [
            "the A13 floor, which M0's device A, an iPhone 13 mini (A15), does not measure: the Section 19.2 budgets on "
            "an A13 iPhone, the product owner's iPhone 11 if it still works then, or one borrowed or bought if the owner "
            "wants one (left to this milestone's device matrix by the product owner on 24 October 2026; Section 19.1)"]),
        ("21.4", s214, [
            "device A (D-1: an older baseline iPhone until 24 October 2026; since then an iPhone 13 mini, the A13 floor "
            "left for M8's device matrix, Section 19.1)"]),
        ("D01's row", d01, [
            "Device A, the baseline for small-screen layout on a device, is an iPhone 13 mini (A15, 375 × 812 pt); the "
            "A13, the oldest chip iOS 26 supports, is left for M8's release device matrix (Section 19.1)",
            "on 24 October 2026 the product owner took D-1 again, the iPhone 11 Pro no longer charging: device A is the "
            "iPhone 13 mini, and the A13 floor is left for M8 (Section 19.1)",
            "Approved by the product owner on 22 October 2026, with the oldest supported iPhone decided (runbook D-1 (b):",
            # 26 October 2026 (ACC-06): the dated note on the release notes, the pending check's own words kept.
            "Pending: the technical lead's sign-off, with the check of Apple's release notes for Xcode 27.1 (ADR-0001; 24 "
            "October 2026: Apple's pages were read that day, and they list Xcode 27.1 (27A9275) as released, with no beta "
            "or release-candidate label, so what remains of that check is the technical lead's confirmation of them, one "
            "line, `Docs/Stage0/M0-device-runbook.md` 0.2; this note added on 26 October 2026 after an agent review, its "
            "finding ACC-06) |"]),
        ("the Literata row", literata, [
            "G0.6 on device A, an iPhone 13 mini the product owner has (D-1, decided again by the product owner on 24 "
            "October 2026, the iPhone 11 Pro chosen on 22 October 2026 no longer charging): its 375 × 812 pt are the "
            "iPhone 11 Pro's, drawn about 8% smaller",
            "the device-A check waits for its device session (runbook Session 8)"]),
        ("the device-evidence row", evidence_row, [
            "the baseline's A15 is two generations newer than the A13 of the oldest iPhones iOS 26 supports, so a budget "
            "met on it is not shown to hold on them",
            "the baseline device is the iPhone 13 mini the product owner has (D-1, decided again on 24 October 2026, the "
            "iPhone 11 Pro no longer charging), its speed, memory, thermal and storage figures the iPhone 13 mini's, never "
            "an A13 phone's, and the A13 floor left for M8's release device matrix (Section 19.1)"]),
        ("Appendix D's D-1 item", line_with(after_d, "- **D-1** (Section 19.1;"), [
            "*(24 October 2026: the product owner took part (i) of D-1 again, the iPhone 11 Pro no longer charging: "
            "device A is the iPhone 13 mini, and the A13 floor is left for M8's release device matrix; the item recorded "
            "that day, below.)*"]),
        ("Appendix D's item of 24 October 2026", item_24, [
            "the product owner's decision of that day on device A, as relayed to the update of the M0 records "
            "(`Docs/Stage0/evidence/M0-DeviceA/README.md` quotes it)",
            "the owner chose the iPhone 13 mini alone, the recommended option",
            "\"with a borrowed or bought A13 phone if wanted\"",
            "So part (i) of D-1 is decided again, not read anew",
            "D-2 (a) stands: the M0 exit waits for Session 8 on device A",
            "The record was completed on 26 October 2026, before any review",
            # 26 October 2026 (ACC-06, and the review status integration log 29.3 left to the next fix of the plan).
            "An agent review read the record the same day, at `8082bdb6`, and found more to fix; after its accuracy "
            "findings, D01's row has a dated note on its pending check of Apple's release notes for Xcode 27.1: Apple's "
            "pages, read on 24 October 2026, list 27A9275 as released, so the technical lead's confirmation is what "
            "remains (its finding ACC-06; `Docs/Stage0/integration-log.md` section 38).",
            "No budget, scope or other decision changed. Agent-written; read by that review, which did not accept it, and "
            "not reviewed since.*"]),
        ("Appendix D's draft 0.3 note on D01", line_with(after_d, "- D01: platform floor amended"), [
            "*(24 October 2026: device A is now an iPhone 13 mini, the iPhone 11 Pro no longer charging, and the A13 floor "
            "is left for M8's release device matrix; draft 0.8 as revised that day.)*"]),
        ("the draft 0.8 entry's review note", body08, [
            "which has not been reviewed (since 24 October 2026 the item before the last: the last records the product "
            "owner's decision of that day on device A, which an agent review read on 26 October 2026, at `8082bdb6`, and "
            "no review has accepted; until a fix of that review's accuracy findings, the same day, this note said it had "
            "not been reviewed either)"]),
    ]
    k_doc = [
        ("this document's header", line_with(doc, "- **What it records now:**"), [
            "(24 October 2026: your iPhone 11 Pro no longer charges, and you decided D-1 again: device A is your iPhone "
            "13 mini, and the A13 floor is left for M8's release device matrix"]),
        ("this document's State line", line_with(doc, "- **State:**"), [
            "The record of your decision of 24 October 2026 on device A",
            # 26 October 2026: the review status (integration log 29.3, 30).
            "is agent-written; an agent review read it with the rest of that update on 26 October 2026, at `8082bdb6`, "
            "and found more to fix, the findings of it relayed so far naming nothing in this document, and no review has "
            "accepted it"]),
        ("this document's dated note of 26 October 2026", doc, [
            "*(Dated note, 26 October 2026: an agent review read that record with the rest of the update that day, at "
            "`8082bdb6`; the findings of it relayed so far, its fidelity and accuracy lenses', name nothing in this "
            "document, and no review has accepted the record (integration log sections 37 and 38).)*"]),
        ("Section 2.9's A46 row", line_with(doc, "| No device evidence:"), [
            "24 October 2026: the product owner's iPhone 11 Pro no longer charges, and the owner decided D-1 again: "
            "device A, the baseline for small-screen layout on a device, is the owner's iPhone 13 mini"]),
        ("Section 3.2's ADR-0001 row", line_with(doc, "| ADR-0001 |"), [
            "(2) iOS 26 runs on the iPhone 11 and later and on the iPhone SE (2nd generation), so device A, the iPhone "
            "13 mini the product owner named on 24 October 2026"]),
        ("Section 5", sec5, [
            "the baseline device, device A, is the iPhone 13 mini since 24 October 2026",
            "and the G0.6 review on the baseline device, device A (the iPhone 13 mini since the product owner's decision "
            "of 24 October 2026"]),
        ("Section 7", line_with(doc, "| Device A and the A13 floor (24 October 2026) |"), [
            "Checked (`evidence/M0-DeviceA/commands/check-amendments.py`, its checks 10c and 10k)"]),
        ("Section 9", line_with(doc, "- **Applied as:**"), [
            "(the latest, for draft 0.8 as revised on 24 and 26 October 2026, "
            "`evidence/M0-DeviceA/fix-1/accuracy/commands/check-amendments.py`"]),
    ]
    k_missing = ["%s: %s" % (name, phrase) for name, text, phrases in k_plan + k_doc for phrase in phrases
                 if not text or phrase not in text]
    # Statements of 22 October 2026 that the decision of 24 October 2026 made stale, gone from the plan before Appendix D
    # (19.1 keeps its old wording only in its dated history, which 10c reads).
    k_gone = [
        "The baseline, the oldest supported iPhone (device A in",
        "The oldest supported iPhone, the baseline device, is an iPhone 11 Pro",
        "G0.6 on the oldest supported iPhone, an iPhone 11 Pro",
        "the baseline device is the iPhone 11 Pro the product owner has access to",
        "the baseline's A13 makes the budgets stricter to meet",
        "(device A, an iPhone 11 Pro; Section 19.1)",
        "The product owner has access to device A (22 October 2026)",
        "the oldest-device check waits for its device session",
        "and an older baseline iPhone (D-1))",
        "the iPhone 11 is a second A13 phone",
        "so every budget of Section 19.2 measured on them is stricter to meet, while no budget value changes",
    ]
    k_stale = [g for g in k_gone if g in before_d]
    # 26 October 2026: the review status the accuracy fix replaced, gone from Appendix D's item, the entry's review note
    # and this document's State line (each keeps a dated note of what it said).
    k_stale += ["(Appendix D) " + g for g in (
        "No budget, scope or other decision changed. Agent-written; not reviewed.*",
        "the last records the product owner's decision of that day on device A, and has not been reviewed either)")
        if g in after_d]
    k_stale += ["(this document's State line) " + g for g in (
        "(this header and Sections 2.9, 3.2, 5, 6, 7, 8 and 9; integration log section 28) is agent-written and has not "
        "been reviewed.",) if g in line_with(doc, "- **State:**")]
    check(not k_missing and not k_stale,
          "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A (the iPhone 13 mini; the "
          "A13 floor left for M8) is recorded wherever the plan and this document state device A, and the statements it "
          "made stale are gone from the plan before Appendix D",
          "; ".join(["lacks, in " + item for item in k_missing] + ["the plan or this document still says: " + g
                                                                  for g in k_stale]))

    print(f"summary: {total_findings} numbered findings in the eight reports; "
          f"{len(table6)} amendment tags; {len(ids)} product-owner questions; "
          f"{len(failures)} failed checks")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
