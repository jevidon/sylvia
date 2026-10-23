#!/usr/bin/env python3
"""The second fix of the record of G0.5 recovery's whole drop-in run with the screen unlocked (23 October 2026;
integration log section 27): the review of the record's fix raised UNL2-01 to UNL2-03. Checks that each is answered by
the texts it names and the facts its answer rests on, and that the records say which review read the record's fix.

UNL2-01  The two rows of integration log 18.1 the finding names (HON-2's and OWN-11's), each kept as history with the
         dated note after it that records the run on 9cdb0a02 and says what remains for the owner; the eight statements
         that gave the fix's sweep, or the texts it annotated, as every such text (the gate summary's items 92 and 94 and
         its Section 8 bullet on the fix; integration log 25.2 and the rows of 26.1 and 26.4 on the fix's recheck; the
         evidence READMEs of the record and of its fix), each kept with its dated note; and two sweeps of every Markdown
         file under Docs/ (the evidence folders, the checklists, the ADRs and the plan included), README.md and CLAUDE.md,
         each paragraph read whole (a hard-wrapped one joined; each table row and list item on its own):
         1. the phrasings of PHRASES below (the fix's fifteen, "since" dropped from the one that had it, and three more):
            each text found must have a dated note naming 9cdb0a02 after it in the same paragraph or row, unless it is
            quoted, in double quotation marks, by an account of what a text said;
         2. every sentence (in a table row, every cell's) that names the drop-in, its run or step 0.8 (TOPIC) with one of
            the words of status of STATUS, names neither 9cdb0a02 nor the run's folder (unlocked-run-1), and has no dated
            note naming 9cdb0a02 after it in its paragraph or cell, must be one of READ below: the sentences this fix read
            and found to give no present status of the run, each with its kind. A sentence it does not list fails it; a
            listed sentence it does not find is only counted (three are listed as they read on 26530d49, before this
            fix's dated notes, which name 9cdb0a02, followed them).
         A text that names the run in other words, or with none of those words of status, can escape both.
UNL2-02  The two notes the finding names (integration log 24.5's and the fourth fix's evidence README's) say what remains
         for the owner, and so does the note after every text of sweep 1 that gives the run to the owner.
UNL2-03  Section 2.10's two pointers name the bullet on G0.5 recovery with the lock harness, which records the passing
         run and has two bullets after it; "the last bullet of this section" is gone from Section 2.10.
Review   The record's fix said to have been read by an agent review at 26530d49, and this second fix to be unreviewed,
         wherever the records give the fix's review status: the gate summary (the State line, Section 6.2, items 99 and
         103, Section 7's item 5, Section 8), the runbook's Who wrote it, integration log 26.5, the fix's evidence README
         and the Stage 0 README.

    python3 -I Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-3/commands/recheck-unl2.py <repository root>

Run on the tree of 26530d49 (git archive), the fix's last commit, where this second fix starts, it must report all
three findings and the review status: sweep 1 must find with no note exactly the two rows UNL2-01 names, sweep 2 must
find unlisted exactly those two rows' sentences, and the owner's clause must be missing after exactly the two notes
UNL2-02 names. The gate checks of this round (gate-checks.sh beside this file) run that control. Read-only; standard
library only; host only. Exit status 1 if any finding is not answered.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0
SEEN = "`9cdb0a02`"


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


def need(text, phrases, where):
    if not text:
        return [f"{where} not found"]
    return [f"{where} lacks: {p}" for p in phrases if p not in text]


def gone(text, phrases, where):
    return [f"{where} still says: {p}" for p in phrases if p in text]


def kept(text, pairs, where):
    """Each (history, note) pair: the history text kept, and the note right after it."""
    out = []
    for history, note in pairs:
        if history not in text:
            out.append(f"{where} lacks the history: {history[:80]}")
        elif history + note not in text:
            out.append(f"{where} lacks the dated note after: {history[-60:]}")
    return out


def report(finding, m, what):
    global problems
    if m:
        problems += 1
    print(f"{'answered' if not m else 'PROBLEM '} {finding}: {what}" + (f" ({'; '.join(m)})" if m else ""))


gate = read("Docs/Stage0/M0-gate.md")
runbook = read("Docs/Stage0/M0-device-runbook.md")
log = read("Docs/Stage0/integration-log.md")
stage0 = read("Docs/Stage0/README.md")
DEC = "Docs/Stage0/evidence/M0-Decisions"
record_readme = read(f"{DEC}/unlocked-record/README.md")
fix_readme = read(f"{DEC}/unlocked-record/round-2/README.md")
round5 = read(f"{DEC}/followup/round-5/README.md")
section8 = block(gate, "## 8. About this summary", "## 9. ")

# UNL2-01: the two rows, each with its dated note.
ROWNOTE = "0.8 is the owner's again only if what the drop-in builds, copies or runs changes after that commit"
m = kept(log, [
    ("Both say what changed on 22 October 2026 (the lock harness's steps 13-15, which no run of the whole drop-in has "
     "passed)",
     " *(dated note, 23 October 2026: a run of the whole drop-in passed them on `9cdb0a02`, made by a waiter of the "
     f"orchestrating session with the screen unlocked, and both now say so; {ROWNOTE}: section 25, and section 27, "
     "UNL2-01)*"),
    ("Section 1 no longer says the assembly ran every check or that G0.5 recovery's drop-in passed on its current steps",
     " *(dated note, 23 October 2026: Section 1 now says that the drop-in did pass on them, on `9cdb0a02`, in a run of "
     "the whole drop-in that a waiter of the orchestrating session made with the screen unlocked (item 4's paragraph on "
     f"the drop-in run, and the paragraph on whether each gate met its criteria); {ROWNOTE}: section 25, and section "
     "27, UNL2-01)*"),
], "the integration log")
# What the two notes say Section 1, 2.10 and Section 8 now say.
m += need(line_with(gate, "**The drop-in run.**"), ["Made, and passed, on `9cdb0a02`"], "M0-gate.md item 4's drop-in run")
m += need(line_with(gate, "**Did each gate meet its criteria?**"),
          ["until a run from clean on `9cdb0a02` found the screen unlocked", "and passed every step, steps 13-15 included"],
          "M0-gate.md, whether each gate met its criteria")
m += need(line_with(gate, "- **Xcode 27.1 on the build Mac, and the pin since 20 October"),
          ["the whole drop-in has passed on that code once, from clean with the screen unlocked, on `9cdb0a02`"],
          "M0-gate.md Section 2.10, Xcode 27.1")
m += need(section8, ["it passed on `9cdb0a02`, with the screen unlocked, on 22 October 2026 UTC"], "M0-gate.md Section 8")
# The eight statements of coverage, each kept with its dated note.
m += kept(line_with(gate, "92. **The drop-in run with the screen unlocked**"),
          [("each now has its dated note: item 94.)*", " *(Dated note, 23 October 2026: nor were those all.")], "item 92")
m += kept(line_with(gate, "94. **Where the run is recorded** (UNL-01, major)"),
          [("(`evidence/M0-Decisions/unlocked-record/round-2/recheck-unl.log`).",
            " *(Dated note, 23 October 2026: not any such text, only those its fixed list of phrasings matches")], "item 94")
m += kept(section8, [("for any text left without one", " *(dated note, 23 October 2026: for the texts its fixed list of "
                                                         "phrasings matches, not any text")],
          "M0-gate.md Section 8, the bullet on the fix")
m += kept(line_with(log, "Each record that called the run pending, still to run or the owner's to make"),
          [("its finding UNL-01; section 26.)*", " *(Dated note, 23 October 2026: nor were the fifteen all.")],
          "integration log 25.2")
m += kept(line_with(log, "| UNL-01: the record put dated notes after some texts"),
          [("it finds exactly the fifteen with none. The texts themselves are kept as history",
            " *(dated note, 23 October 2026: the 23 are the texts its fixed list of phrasings matches")],
          "integration log 26.1, UNL-01")
m += kept(line_with(log, "| The recheck of the five findings and of the record's review status"),
          [("each with a dated note naming `9cdb0a02` after it", " *(dated note, 23 October 2026: the 23 its fixed list "
                                                                 "of phrasings matches")], "integration log 26.4")
m += kept(record_readme, [("for any text left without one: [`round-2/`](round-2/README.md), its finding UNL-01.)*",
                           " *(Dated note, 23 October 2026: not any text, nor were the fifteen all.")],
          "the record's evidence README")
m += kept(fix_readme, [("with no dated note naming `9cdb0a02` after it", " *(dated note, 23 October 2026: for the texts "
                                                                          "its fixed list of 15 phrasings matches, not any "
                                                                          "text")], "the fix's evidence README")
m += need(gate, ["100. **Where the run is recorded, again** (UNL2-01, major)"], "M0-gate.md Section 6.3")
m += need(log, ["## 27. The review of the fix of the drop-in run's record, and the second fix (23 October 2026)"],
          "the integration log")

# The two sweeps.
FILES = sorted(set((ROOT / "Docs").rglob("*.md")) | {p for p in (ROOT / "README.md", ROOT / "CLAUDE.md") if p.is_file()})
PHRASES = re.compile(
    r"stays the runbook's 0\.8, for the owner|[Ii]t is (?:now )?the runbook's 0\.8, for the owner|"
    r"asks the owner to run it|A run with the screen unlocked is pending|"
    r"\*\*Not done:\*\*[^\n]*a run of the whole drop-in with the screen unlocked|"
    r"0\.8 asks for the whole drop-in to run once more|0\.8 repeated if a fix changes the harness after it ran|"
    r"the whole drop-in with the screen unlocked is still to run|"
    r"A run of the whole drop-in with the screen unlocked(?:, steps 13-15 included,)? is (?:still )?pending|"
    r"no run of the whole drop-in has passed|run it once more now|0\.8 runs it once more|"
    r"the whole drop-in run once more|0\.8 is to be run once more|has it run once more|"
    r"passed on its current steps|whole drop-in has not passed|(?:has|have) not run inside")
NOTED = re.compile(r"(?:[Dd]ated note, 23 October 2026|\*\(23 October 2026, integration log section 25)[^\n]*`9cdb0a02`")
OWNER = re.compile(r"for the owner|the owner's|asks the owner|\byours\b|asks you")
TOPIC = re.compile(
    r"whole drop-in|G0\.5 recovery's (?:whole )?drop-in|recovery drop-in|71-g05-recovery|drop-in(?:'s)? run\b|"
    r"run of the drop-in|runbook(?:'s)? (?:step |Session )?0\.8|(?:[Ss]tep|Session) 0\.8|"
    r"\b0\.8(?:'s)? (?:run|asks|runs|is|was|must|needs|again|to)\b|steps? 13-15|lock harness's steps|screen unlocked|"
    r"unlocked run")
STATUS = re.compile(
    r"not passed|has not (?:passed|run|been run)|had not (?:passed|run|then passed)|have not (?:passed|run)|no run|"
    r"not (?:been )?run|not yet|yet to|still to|is pending|are pending|stays? pending|remains? pending|to be (?:run|made)|"
    r"to make|once more|for the owner|the owner's|yours|current steps|asks? (?:you|the owner)|did not run|never ran|"
    r"is to come|run it\b", re.I)
RUNREF = re.compile(r"`9cdb0a02`|unlocked-run-1")
SPLIT = re.compile(r"(?<=[.;:!?])\s+(?=[A-Z(*`\[|])")
STARTS = re.compile(r"^\s*(?:[-*] |\d+\. |\||#|```|>)")

# The sentences of sweep 2 this fix read, by file and opening words, each with its kind: "history" (what a text said
# until a date, the run recorded there or where it points), "locked" (a run that found the screen locked, as it ran),
# "earlier" (the run of 19 October 2026 or an earlier one, recorded as made), "account" (the record of the run, its
# fixes or their reviews, telling what the records said), "other" (not the run's status: the complete CI, what a check
# reads, a sign-off, where records go, a review's status).
READ = {
    "Docs/ADRs/0012-retention-backup-restore.md": {
        "Until 23 October 2026 it listed the whole drop-in's run with the screen unlocked as still to come": "history"},
    "Docs/ADRs/0015-threat-model.md": {
        "`G05-Recovery.md` row 10, `G05-Recovery/logs/host-tests.log`), and on the code after M0 assembly": "earlier"},
    "Docs/Stage0/G05-Recovery.md": {
        "A re-run with the screen unlocked is pending: an agent may not unlock the Mac": "earlier"},
    "Docs/Stage0/M0-device-runbook.md": {
        "M0 final review round 2, R6-04; and then, until the review of the decisions round": "history"},
    "Docs/Stage0/M0-gate.md": {
        "(Until the review of the decisions round, the same day, this sentence said every drop-in had passed": "history",
        "A run of the whole drop-in with the screen unlocked was then still to come": "history",
        "Approved (PO-21 (a)); the security sign-off of class C, yours": "other",
        "Until 23 October 2026 it said that no run of the whole drop-in had passed since that day's change": "history",
        "*(22 October 2026: the decisions round added the lock harness": "other",
        # Items 92 and 94, as on 26530d49, before this fix's dated notes, which name 9cdb0a02, followed them.
        "Until then these records called that run pending, still to run, or yours to make": "account",
        "**Where the run is recorded** (UNL-01, major): the record put dated notes": "account"},
    "Docs/Stage0/README.md": {
        "(Until 23 October 2026 this paragraph offered the merge as the other way to build": "history",
        "- [M0-gate.md](M0-gate.md) is the gate summary for the product owner": "other"},
    "Docs/Stage0/evidence/M0-Decisions/assembly/README.md": {
        "Not run, and why: the complete CI (since `4c73da57`": "other"},
    "Docs/Stage0/evidence/M0-Decisions/fix-1/README.md": {
        "Not run, and why: the complete CI (since `88d4e1c7`": "other"},
    "Docs/Stage0/evidence/M0-Decisions/followup/round-4/README.md": {
        "The gate summary's checks for this fix, the current equivalent of": "other"},
    "Docs/Stage0/evidence/M0-Decisions/followup/round-5/README.md": {
        "The gate summary's checks for this fix, the current equivalent of": "other"},
    "Docs/Stage0/evidence/M0-Decisions/harness/README.md": {
        "`71-g05-recovery` stopped at its row-10 guard, as it must with the screen locked": "locked"},
    "Docs/Stage0/evidence/M0-Decisions/unlocked-record/README.md": {
        "The records: each place that called the run pending, still to run or the owner's to make": "account",
        # The README's opening, as on 26530d49, before this fix's dated note, which names 9cdb0a02, followed it.
        "The record puts the run wherever the records called it pending": "account"},
    "Docs/Stage0/integration-log.md": {
        "A re-run with the screen unlocked is pending: an agent may not unlock the Mac": "earlier",
        "- **The complete CI** was not run: since `4c73da57`": "other",
        "- **The complete CI** was not run: since `88d4e1c7`": "other",
        "Passed: nothing outside `Docs/` changed since `11f41be5`": "other",
        "| OWN5-02: nothing said where the owner commits the session records": "other",
        "Step 5's ordering rule covers the owner's own edits too": "other",
        "Passed: nothing outside `Docs/` changed since `660c2b3a`": "other",
        "Until then the records called that run pending, still to run, or the owner's to make": "account",
        "| UNL-01: the record put dated notes after some texts that gave the whole drop-in run to the owner": "account",
        "The State line names the record of the drop-in run and its fix among the agent edits": "other",
        "| UNL-03: the runbook's Session 0 heading": "account",
        "Each gives about 1.25 h of the owner's time, 1.75 h elapsed": "account",
        "Both notes now say that 0.8 is the owner's again only if": "account",
        "The texts the second sweep lists, which tell what a text said until a date": "account"},
}


def units(text):
    """Paragraphs with their hard-wrapped lines joined; each list item and table row its own unit."""
    out, cur, start = [], [], 0
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            if cur:
                out.append((start, " ".join(cur)))
            cur = []
            continue
        if not cur or STARTS.match(line) or cur[-1].lstrip().startswith("|"):
            if cur:
                out.append((start, " ".join(cur)))
            cur, start = [line], n
        else:
            cur.append(line.strip())
    if cur:
        out.append((start, " ".join(cur)))
    return out


def sentences(unit):
    """A table row's cells, or the paragraph whole; each split into sentences, with where each starts in its part."""
    for part in (unit.split(" | ") if unit.lstrip().startswith("|") else [unit]):
        pos = 0
        for sent in SPLIT.split(part):
            i = part.find(sent, pos)
            pos = i + len(sent)
            yield part, i, sent


def quoted(unit, start, end):
    """Whether unit[start:end] lies inside double quotation marks opened and closed in its sentence."""
    before = unit[max(0, unit.rfind(". ", 0, start)):start]
    return before.count('"') % 2 == 1 and '"' in unit[end:end + 200]


hits, bare, owner_hits, owner_bare = 0, [], 0, []
flagged, unlisted, seen_keys = 0, [], set()
for path in FILES:
    rel = str(path.relative_to(ROOT))
    for n, unit in units(path.read_text(encoding="utf-8")):
        for hit in PHRASES.finditer(unit):
            if quoted(unit, hit.start(), hit.end()):
                continue
            hits += 1
            note = NOTED.search(unit, hit.end())
            if not note:
                bare.append(f"{rel}:{n}: ...{hit.group(0)[-70:]}")
            elif OWNER.search(hit.group(0)):
                owner_hits += 1
                closing = unit.find("*", note.end())
                if "only if" not in unit[note.start():closing if closing >= 0 else len(unit)]:
                    owner_bare.append(f"{rel}:{n}: ...{hit.group(0)[-70:]}")
        for part, i, sent in sentences(unit):
            if TOPIC.search(sent) and STATUS.search(sent) and not RUNREF.search(sent) and not NOTED.search(part, i):
                flagged += 1
                key = next((k for k in READ.get(rel, {}) if sent.startswith(k)), None)
                if key is None:
                    unlisted.append(f"{rel}:{n}: {sent[:120]}")
                else:
                    seen_keys.add((rel, key))
kinds = {}
for rel, keys in READ.items():
    for key, kind in keys.items():
        if (rel, key) in seen_keys:
            kinds[kind] = kinds.get(kind, 0) + 1
listed = sum(len(keys) for keys in READ.values())
m += [f"no dated note naming {SEEN} after: {b}" for b in bare]
m += [f"a sentence that names the drop-in with a word of status, not read: {u}" for u in unlisted]
report("UNL2-01", m, f"the two rows each with its dated note; the eight statements of coverage each with its note; "
       f"sweep 1 over {len(FILES)} Markdown files: {hits} texts in its phrasings, {hits - len(bare)} with a dated note "
       f"naming {SEEN} after them; sweep 2: {flagged} sentences that name the drop-in, its run or step 0.8 with a word of "
       f"status and no such note, {flagged - len(unlisted)} of them read and listed ("
       + ", ".join(f"{kinds[k]} {k}" for k in sorted(kinds)) + f"), {len(unlisted)} not; of the {listed} sentences "
       f"listed, {listed - len(seen_keys)} not found on this tree")

# UNL2-02: the two notes, and the owner's clause after every text of sweep 1 that gives the run to the owner.
m = need(line_with(log, "- **G0.5 recovery's whole drop-in with the screen unlocked.** Not run: no code changed since "
                        "`660c2b3a`"),
         ["*(Dated note, 23 October 2026: a waiter of the orchestrating session ran it after this fix, on `9cdb0a02`, the "
          f"fix's last commit, with the screen unlocked, and it passed; {ROWNOTE}: section 25, and section 27, "
          "UNL2-02.)*"], "integration log 24.5")
m += need(round5, ["*dated note, 23 October 2026: a waiter of the orchestrating session ran it after this fix, on "
                   f"`9cdb0a02`, this fix's last commit, with the screen unlocked, and it passed, so {ROWNOTE}: "
                   "`../../assembly/unlocked-run-1/`, integration log sections 25 and 27*"],
          "the fourth fix's evidence README")
m += [f"the note after a text that gives the run to the owner does not say what remains: {b}" for b in owner_bare]
m += need(gate, ["101. **What remains for you, in two more notes** (UNL2-02)"], "M0-gate.md Section 6.3")
report("UNL2-02", m, f"24.5's note and the fourth fix's README say what remains for the owner; of sweep 1's texts that "
       f"give the run to the owner, {owner_hits - len(owner_bare)} of {owner_hits} have a note that says it")

# UNL2-03: Section 2.10's two pointers.
s210 = block(gate, "### 2.10 ", "## 3. ")
heads = [re.match(r"- \*\*([^*]+)\*\*", l).group(1) for l in s210.splitlines() if l.startswith("- **")]
lock = [i for i, h in enumerate(heads) if h.startswith("G0.5 recovery with the lock harness")]
m = gone(s210, ["the last bullet of this section, where", "22:36-22:44 UTC; the last bullet of this section)"],
         "M0-gate.md Section 2.10")
m += need(line_with(gate, "- **G0.5 recovery on the current code, with its class-B readback (19 October 2026"),
          ["(the bullet on G0.5 recovery with the lock harness, below, where that run, on `9cdb0a02`, passed)"],
          "Section 2.10's second bullet")
m += need(line_with(gate, "- **Xcode 27.1 on the build Mac, and the pin since 20 October"),
          ["on `9cdb0a02` (22 October 2026, 22:36-22:44 UTC; the bullet on G0.5 recovery with the lock harness, below)",
           "its pointer, like the one in the second bullet, named the last bullet of this section, two bullets further "
           "on: item 102.)"], "Section 2.10's bullet on Xcode 27.1")
lock_bullet = line_with(gate, "- **G0.5 recovery with the lock harness (22 October 2026).**")
m += [] if len(lock) == 1 and len(heads) - lock[0] - 1 == 2 else [f"Section 2.10's bullets: {heads}"]
m += need(lock_bullet, ["**With the screen unlocked, the whole drop-in passed (22 October 2026, 22:36:32-22:44:05 UTC"],
          "the bullet on G0.5 recovery with the lock harness")
m += need(gate, ["102. **Section 2.10's pointers to the passing run** (UNL2-03)"], "M0-gate.md Section 6.3")
report("UNL2-03", m, f"Section 2.10's two pointers name the bullet on G0.5 recovery with the lock harness, bullet "
       f"{lock[0] + 1 if lock else '?'} of {len(heads)}, which records the passing run")

# The review status: the record's fix read by an agent review at 26530d49; this second fix not reviewed.
state = line_with(gate, "- **State:**")
words = len(state.split())
m = need(state, ["the follow-up and its four fixes, the record of item 4's drop-in run and its two fixes, and this "
                 "summary's own updates", "and the last two fixes, the follow-up's fourth and that record's second, have "
                 "not been reviewed", "(This line's history: Section 6.2, and Section 6.3, item 88.)"], "the State line")
m += [f"the State line has {words} words (at most 200)"] if words > 200 else []
m += need(line_with(gate, "99. **Not reviewed**"), ["*(Dated note, 23 October 2026: reviewed by an agent the same day, at "
                                                    "`26530d49`, items 100-103.)*"], "item 99")
m += need(gate, ["| The review of the fix of the record of G0.5 recovery's drop-in run (23 October 2026, at `26530d49`) |",
                 "that answer reviewed the same day, at `26530d49` (next row; until the second fix of that record this "
                 "cell said not reviewed)", "103. **Not reviewed**: this second fix is agent-written",
                 "and the fix of its review (items 94-99) and its second fix (items 100-103)",
                 "this fix was read by an agent review the same day (next bullet; until the second fix this bullet said it "
                 "had not been reviewed)", "- **The second fix of the record of the drop-in run, after the review of its "
                 "fix (23 October 2026; integration log section 27).**", "and that record's second fix (section 27) no "
                 "review at all"], "the gate summary")
m += need(line_with(runbook, "- **Who wrote it.**"), ["and of the record of the drop-in's run at `91c3b46a` and its fix at "
                                                      "`26530d49`", "the follow-up's fourth fix of 23 October 2026, and "
                                                      "the second fix of the drop-in's record, have not been reviewed"],
          "the runbook's Who wrote it")
m += need(block(log, "### 26.5 ", "## 27."), ["*(Dated note, 23 October 2026: an agent review read it the same day, at "
                                              "`26530d49`, and raised UNL2-01 to UNL2-03 (section 27).)*"],
          "integration log 26.5")
m += need(fix_readme, ["*(Dated note, 23 October 2026: read by an agent review the same day, at `26530d49`, which raised "
                       "UNL2-01 to UNL2-03;"], "the fix's evidence README")
m += need(stage0, ["a seventh, of that fix, raised three more, one of them major, which a second fix of the record answered "
                   "the same day (section 27); that second fix has not been reviewed either.",
                   "and by that record's second fix, section 27)"], "the Stage 0 README")
report("review", m, f"the record's fix read by an agent review at 26530d49 and this second fix not reviewed, in the gate "
       f"summary (the State line: {words} words), the runbook, the integration log, the fix's README and the Stage 0 "
       "README")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 4 not as stated)")
sys.exit(1 if problems else 0)
