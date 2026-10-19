#!/usr/bin/env python3
"""Consistency checks for the M0 plan amendments (plan draft 0.5, re-checked as draft 0.7).

Run from the repository root with the Python standard library only:
    python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py
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

    # 3a. Every consequence of ADR-0001 to ADR-0014 has its numbered item in Section 3.2.
    adr_cells = dict()
    for header, cells in table_rows(section_text(doc, "3.2 ADR consequences")):
        if header[0] == "ADR" and re.fullmatch(r"ADR-00\d\d", cells[0]):
            adr_cells[cells[0]] = cells[1]
    known_tags = set("A%02d" % n for n in range(1, LAST_TAG + 1))
    adr_problems, adr_items = [], 0
    for n in range(1, 15):
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
    check(len(adr_cells) == 14 and not adr_problems,
          "Section 3.2: ADR-0001 to ADR-0014, %d consequences, each mapped to a tag or to no change" % adr_items,
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
    ]
    present = [
        "**Status:** Draft 0.7",
        "**Revised:** 19 October 2026",
        "**Draft 0.7 - draft 0.5 re-checked at the M0 final fix, pending product-owner approval.**",
        "A raw file has no manifest and no end record, so nothing proves it complete",
        "the task window bounds those copies per job, and nothing bounds them across jobs yet",
        "nothing bounds them across jobs until the product owner chooses",
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
        "**Per-file timing mode (proposed, pending product-owner approval).**",
        "**Import remux (proposed, pending product-owner approval).**",
        "**Stage 0 status at the M0 gate (draft 0.5).**",
        "**At the M0 gate (draft 0.5) the ranges are unchanged.**",
        "takes about twice its original's space on the device",
        "the capture flow offers an action that extends a quotation into the next chapter",
        "Present it as a copyable code and optionally a QR code",
        "Which hosts count as local is proposed",
        "ends `complete` with outcome `refusal` or `content_filtered`",
        "| Background download tasks hold the bearer token",
        "| Real-world EPUBs fall outside the compatibility subset",
        "G0.3, and G0.6, whose design package every screen from M2 on is built from",
        "Every narrowing of release scope in draft 0.5 is a proposal.",
        "Every narrowing of release scope is a proposal.",
        "approving draft 0.5 does not by itself approve it",
        "approving this draft does not by itself approve them",
        "Treat every other 5xx (a 500, 502 or 504 among them)",
        "Proposed for the job store (product-owner decision pending)",
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
        ("plan 21.2 M1 row", line_with(plan, "| M1 - Durable foundation |"),
         "| M0; the G0.5 recovery device steps (proposed, Section 21.1) [M0-A46] |"),
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

    print(f"summary: {total_findings} numbered findings in the eight reports; "
          f"{len(table6)} amendment tags; {len(ids)} product-owner questions; "
          f"{len(failures)} failed checks")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
