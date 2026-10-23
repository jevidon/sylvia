#!/usr/bin/env python3
"""The fix of the review of the record of G0.5 recovery's whole drop-in run with the screen unlocked (23 October 2026;
integration log section 26). Checks that each of the review's five findings, UNL-01 to UNL-05, is answered by the texts
it names and by the facts its answer rests on, and that the records say which review read the record.

UNL-01  The fifteen texts that gave the run as pending, still to run or the owner's with no note (the twelve the finding
        names: integration log 17.5, 18.5, 19.5 and 20.5-23.5, and the Not run lines of the evidence READMEs of the
        second fix, the follow-up and its first three fixes; and three this fix's own sweep found: integration log 16's
        list of what was not done, 18.1's row of HON-6 and 20.2's row of OWN3-06), each kept as history with the dated
        note after it that records the run on 9cdb0a02 and what remains for the owner; the three statements that said
        every record was covered (integration log 25.2, the record's evidence README, the gate summary's item 92), each
        with its dated note; and the sweep: in every Markdown file of Docs/Stage0 (the evidence folders and the device
        checklists included) and Docs/ADRs, each text that calls the whole drop-in run with the screen unlocked pending,
        not done, still to run, to run once more, or the owner's (the patterns of STALE below; the record's recheck swept
        five records for fewer of them) must have, later in the same line, a dated note that names 9cdb0a02.
UNL-02  The State line names the record of the drop-in run and its fix among the edits with no accepting review and no
        longer names the fourth fix as the last unreviewed work, within the fourth fix's limit of 200 words, with its
        pointer; the Stage 0 README gives the review of the record and its fix; integration log 25.2's row on the State
        line has its dated note.
UNL-03  Session 0's time without 0.8's run: the runbook's heading and its note, its run 2, the gate summary's table and
        the total under it. The facts are recomputed: the steps' own times in the runbook (0.3, whose steps are run 1's,
        and 0.8 left out) and the table's column.
UNL-04  Item 2's trigger for repeating 0.8 names what item 4 and runbook 0.8 name; the facts are read in the code: the
        drop-in sources Scripts/lib/env.sh and sim.sh, the harness's checks Scripts/lib/xcodegen.sh, and its step 10's
        check reads Contracts/schemas and Contracts/fixtures; and the rule's command lists those folders.
UNL-05  Integration log section 25's account of what is read in the run's evidence has its dated note, as have 25.4's
        row and the record's evidence README; this round's check-run.py says what it reads and what is inferred, and
        differs from the record's only in its docstring and in three labels, the record's kept as it ran.
Review  The record of the run is said to have been read by an agent review, and its fix to be unreviewed, wherever the
        records gave its review status: the gate summary (Section 6.2, items 93 and 99, Section 7's item 5, Section 8),
        the runbook's Who wrote it, integration log 25.5, the record's evidence README and the ADR index, which gives
        the reviews of ADR-0015's revisions (the notes of its status line are kept as written, as for its earlier ones).

    python3 -I Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-2/commands/recheck-unl.py <repository root>

Run on the tree of 91c3b46a (git archive), the record's last commit, where this fix starts, it must report all five
findings and the review statuses, and the sweep every one of the fifteen texts; the gate checks of this round
(gate-checks.sh beside this file) run that control. Read-only; standard library only; host only. Exit status 1 if any
finding is not answered.
"""
import difflib
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
a15 = read("Docs/ADRs/0015-threat-model.md")
index = read("Docs/ADRs/README.md")
DEC = "Docs/Stage0/evidence/M0-Decisions"
record_readme = read(f"{DEC}/unlocked-record/README.md")

# UNL-01: the fifteen texts, each with its dated note.
LOGNOTE = (" *(Dated note, 23 October 2026: a waiter of the orchestrating session ran it on `9cdb0a02`, the follow-up's "
           "fourth fix's last commit, with the screen unlocked, and it passed; 0.8 is the owner's again only if what the "
           "drop-in builds, copies or runs changes after that commit: section 25, and section 26, UNL-01.)*")
OWNER = "it stays the runbook's 0.8, for the owner, in Session 0."
READMENOTE = ("; *dated note, 23 October 2026: a waiter of the orchestrating session ran it on `9cdb0a02`, the "
              "follow-up's fourth fix's last commit, with the screen unlocked, and it passed, so 0.8 is the owner's again "
              "only if what the drop-in builds, copies or runs changes after that commit: `{up}assembly/unlocked-run-1/`, "
              "integration log sections 25 and 26*")
m = kept(log, [
    ("a run of the whole drop-in with the screen unlocked; any review.",
     " *(Dated note, 23 October 2026: the run of the whole drop-in with the screen unlocked was made by a waiter of the "
     "orchestrating session on `9cdb0a02`, the follow-up's fourth fix's last commit, and passed; 0.8 is the owner's "
     "again only if what the drop-in builds, copies or runs changes after that commit: section 25, and section 26, "
     "UNL-01."),
    ("since the recovery package it reads has not changed. A run with the screen unlocked is pending.", LOGNOTE),
    ("It is now the runbook's 0.8, for the owner, in Session 0, before Session 6.", LOGNOTE),
    ("It is the runbook's 0.8, for the owner, in Session 0, before Session 6.", LOGNOTE),
    (f"Not run: no code changed since `a1ea66d2`, and {OWNER}", LOGNOTE),
    (f"Not run: no code changed since `19489f10`, and {OWNER}", LOGNOTE),
    (f"Not run: no code changed since `13d2b4c7`, and {OWNER}", LOGNOTE),
    (f"Not run: no code changed since `11f41be5`, and {OWNER}", LOGNOTE),
    ("0.8 asks for the whole drop-in to run once more, before Session 6, with its expected lines and where its logs go "
     "(the runbook's header, run 2 and 0.8, the gate summary's 2.10, 5.1 and Section 1, ADR-0012, ADR-0015, the session "
     "log); run 2's date is given in UTC and on the build Mac's clock",
     " *(dated note, 23 October 2026: that run was made by a waiter of the orchestrating session on `9cdb0a02` and "
     "passed, and 0.8 now asks for it again only if what the drop-in builds, copies or runs changes after that commit: "
     "section 25, and section 26, UNL-01)*"),
    ("and 0.8 repeated if a fix changes the harness after it ran",
     " *(dated note, 23 October 2026: 0.8's run was made by a waiter of the orchestrating session on `9cdb0a02` and "
     "passed; item 2 now repeats 0.8 if a fix, or another commit the owner builds from, changes what the drop-in builds, "
     "copies or runs after that commit: section 25, and section 26, UNL-01 and UNL-04)*"),
], "the integration log")
for path, history, up in (
        (f"{DEC}/fix-2/README.md", "(the screen was locked at every reading; runbook 0.8 asks the owner to run it in "
                                    "Session 0", "../"),
        (f"{DEC}/followup/README.md", "(no code changed; it stays the runbook's 0.8, for the owner", "../"),
        (f"{DEC}/followup/round-2/README.md", "(no code changed; it stays the runbook's 0.8, for the owner", "../../"),
        (f"{DEC}/followup/round-3/README.md", "(no code changed; it stays the runbook's 0.8, for the owner", "../../"),
        (f"{DEC}/followup/round-4/README.md", "(no code changed; it stays the runbook's 0.8, for the owner", "../../")):
    m += kept(read(path), [(history, READMENOTE.format(up=up) + ");")], path)
# The three statements that said every record was covered.
m += need(line_with(log, "Each record that called the run pending, still to run or the owner's to make"),
          ["*(Dated note, 23 October 2026: not every record.", "Each of the fifteen now has its dated note, and the fix's "
           "recheck sweeps this log and every evidence README too: the review of this record, its finding UNL-01; "
           "section 26.)*"], "integration log 25.2")
m += need(record_readme, ["and checks that it did. *(Dated note, 23 October 2026: not everywhere. Fifteen texts",
                          "it reads a fixed list of 33 places, and its closing sweep five records"],
          "the record's evidence README")
m += need(line_with(gate, "92. **The drop-in run with the screen unlocked**"),
          ["*(Dated note, 23 October 2026: not every record.", "each now has its dated note: item 94.)*"], "item 92")
m += need(gate, ["94. **Where the run is recorded** (UNL-01, major)"], "M0-gate.md Section 6.3")
m += need(log, ["## 26. The review of the record of the drop-in run, and its fix (23 October 2026)"], "the integration log")
# The sweep: every text that gives the run as pending or the owner's has a dated note naming 9cdb0a02 after it.
STALE = re.compile(
    r"stays the runbook's 0\.8, for the owner|[Ii]t is (?:now )?the runbook's 0\.8, for the owner|"
    r"asks the owner to run it|A run with the screen unlocked is pending|"
    r"\*\*Not done:\*\*[^\n]*a run of the whole drop-in with the screen unlocked|"
    r"0\.8 asks for the whole drop-in to run once more|0\.8 repeated if a fix changes the harness after it ran|"
    r"the whole drop-in with the screen unlocked is still to run|"
    r"A run of the whole drop-in with the screen unlocked(?:, steps 13-15 included,)? is (?:still )?pending|"
    r"no run of the whole drop-in has passed since|run it once more now|0\.8 runs it once more|"
    r"the whole drop-in run once more|0\.8 is to be run once more|has it run once more")
NOTED = re.compile(r"(?:[Dd]ated note, 23 October 2026|\*\(23 October 2026, integration log section 25)[^\n]*`9cdb0a02`")
swept, hits, bare = 0, 0, []
paths = sorted(set((ROOT / "Docs/Stage0").rglob("*.md")) | set((ROOT / "Docs/ADRs").glob("*.md")))
for path in paths:
    swept += 1
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for hit in STALE.finditer(line):
            hits += 1
            if not NOTED.search(line, hit.end()):
                bare.append(f"{path.relative_to(ROOT)}:{n}: ...{hit.group(0)[-70:]}")
m += [f"no dated note naming {SEEN} after: {b}" for b in bare]
report("UNL-01", m, f"the fifteen texts each with its dated note, the three statements of coverage each with its note; "
       f"the sweep: {swept} Markdown files of Docs/Stage0 and Docs/ADRs, {hits} texts that gave the run as pending or "
       f"the owner's, {hits - len(bare)} with a dated note naming {SEEN} after them")

# UNL-02: the State line, the Stage 0 README and 25.2's row.
state = line_with(gate, "- **State:**")
words = len(state.split())
m = need(state, ["the follow-up and its four fixes, the record of item 4's drop-in run and its fix, and this summary's own "
                 "updates", "and the last two fixes, the follow-up's fourth and that record's, have not been reviewed",
                 "(This line's history: Section 6.2, and Section 6.3, item 88.)"], "the State line")
m += gone(state, ["the last fix, the follow-up's fourth (23 October 2026), has not been reviewed"], "the State line")
m += [f"the State line has {words} words (at most 200)"] if words > 200 else []
m += need(stage0, ["and a sixth agent review, of that record, raised five findings, one of them major, which a fix of the "
                   "record answered the same day (section 26); that fix has not been reviewed either.",
                   "by the fix of the review of that run's record, section 26)"], "the Stage 0 README")
m += need(line_with(log, "| The gate summary | Section 1: item 2's repeat of 0.8"),
          ["*(dated note, 23 October 2026: that phrase covers this summary's edits only"], "integration log 25.2's row")
m += need(gate, ["95. **What has had no review** (UNL-02)"], "M0-gate.md Section 6.3")
report("UNL-02", m, f"the State line ({words} words) names the record of the drop-in run and its fix and the last two "
       "fixes as unreviewed; the Stage 0 README gives the review of the record and its fix; 25.2's row has its note")

# UNL-03: Session 0's time without 0.8, recomputed from the runbook's steps and the table's column.
s0 = block(runbook, "### Session 0 ", "### Session 1 ")


def step_minutes(number):
    body = block(s0, f"**0.{number} ", "**0.")
    times = re.findall(r"\b(\d+) min( per device)?\b", body)
    if not times:
        return None
    minutes, per_device = times[-1]
    return int(minutes) * (3 if per_device else 1)


steps = {n: step_minutes(n) for n in (1, 2, 4, 5, 6, 7, 9)}
total = sum(v for v in steps.values() if v is not None)
m = [f"runbook 0.{n}: no time found" for n, v in steps.items() if v is None]
m += [f"the steps without 0.3 and 0.8 add up to {total} min, not 77"] if total != 77 else []
m += need(line_with(runbook, "### Session 0 "), ["(about 1.25 h of your time, 1.75 h elapsed; 10-15 min more if 0.8 "
                                                 "must run again)"], "the runbook's Session 0 heading")
m += need(s0, ["Until 23 October 2026, after the review of the record of the drop-in's run on `9cdb0a02`, it said about "
               "1.5 h of your time, 2 h elapsed", "the steps add up to 77 min"], "the heading's note")
m += need(line_with(runbook, "| 2 | 0 Mac setup |"), ["| 1.25 h / 1.75 h (three devices to register, 0.4), and 10-15 "
                                                       "min more if 0.8 must run again |"], "the runbook's run 2")
row2 = line_with(gate, "| 2 | 0 · At the Mac |")
m += need(row2, ["| 1.25 h (1.75 h); 10-15 min more if 0.8 must run again (item 4) |"], "the gate summary's run 2")
table = block(gate, "| Run | Runbook session | Device | Your time (elapsed) |", "In all,")
hours = [float(re.search(r"(\d+(?:\.\d+)?) h", row.split(" | ")[3]).group(1))
         for row in table.splitlines()[2:] if row.startswith("| ")]
m += [f"the table's column adds up to {sum(hours)} h, not 42.5"] if abs(sum(hours) - 42.5) > 1e-9 else []
m += need(line_with(gate, "In all, "), ["In all, about 42.5 h of your time over ten sittings (by the table, with no "
                                        "repeat of 0.8)", "its finding UNL-03, Section 6.3, item 96.)"],
          "the sentence after the table")
m += need(gate, ["96. **Session 0's time** (UNL-03)"], "M0-gate.md Section 6.3")
report("UNL-03", m, f"Session 0 about 1.25 h (1.75 h) and 10-15 min more with 0.8, in the runbook's heading and run 2 and "
       f"the summary's table: its steps without 0.3 and 0.8 add up to {total} min; the table's {len(hours)} rows add up "
       f"to {sum(hours)} h")

# UNL-04: item 2 names what item 4 and 0.8 name, which the code shows the drop-in uses.
item2 = line_with(gate, "**2. The device sessions**")
item4 = line_with(gate, "**The drop-in run.**")
step08 = block(runbook, "**0.8 ", "**0.9 ")
m = need(item2, ["if a fix, or any other commit you build from, changes the harness or the drop-in after `9cdb0a02`, the "
                 "commit 0.8's run was made on (item 4), or anything else the drop-in builds, copies or runs (the recovery "
                 "package, `Scripts/lib` or the contracts, as item 4 and runbook 0.8 list them), repeat 0.8",
                 "Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists"], "M0-gate.md item 2")
m += need(item4, ["(the recovery package and its lock harness, the drop-in, `Scripts/lib` or the contracts;"],
          "M0-gate.md item 4")
m += need(step08, ["the recovery package or its lock harness (`Spikes/G05-Recovery`), the drop-in, `Scripts/lib` or "
                   "`Contracts/`"], "runbook 0.8")
dropin = read("Scripts/ci.d/71-g05-recovery.sh")
harness = read("Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh")
manifest = read("Spikes/G05-Recovery/Scripts/check_manifest_contract.py")
m += need(dropin, ['source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"', 'source "$SYLVIA_ROOT/Scripts/lib/sim.sh"',
                   'step "10. backup-manifest contract"', '"$SPIKE/Scripts/check_manifest_contract.py"',
                   "LockHarness/Scripts/harness-checks.sh"], "the drop-in")
m += need(harness, ['source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"'], "the harness's checks")
m += need(manifest, ['"Contracts/schemas/backup-manifest.v1.schema.json"', '"Contracts/fixtures/backup-manifest.v1/invalid"'],
          "step 10's check")
m += need(gate, ["97. **When 0.8 is repeated** (UNL-04)"], "M0-gate.md Section 6.3")
report("UNL-04", m, "item 2 repeats 0.8 for anything the drop-in builds, copies or runs, as item 4 and 0.8 list it: the "
       "drop-in sources Scripts/lib/env.sh and sim.sh, the harness's checks xcodegen.sh, and step 10 reads "
       "Contracts/schemas and Contracts/fixtures")

# UNL-05: what was read in the run's evidence.
intro25 = line_with(log, "On 22 October 2026, 22:36:32-22:44:05 UTC (23 October, 11:36-11:44, on the build Mac's clock), a "
                         "waiter of the orchestrating session")
m = need(intro25, ["everything below is read in the run's committed evidence, except who started it",
                   "*(Dated note, 23 October 2026: two more rest on more than the evidence shows. That "
                   "`G05_ALLOW_MISSING_CLASS_B` was not set is in part the relay's", "is inferred: the console records the "
                   "count alone", "The review of this record, its finding UNL-05; section 26.)*"],
         "integration log section 25's opening")
m += need(line_with(log, "| The run's facts (`commands/check-run.py`, through `run-logged.sh`) |"),
          ["*(dated note, 23 October 2026: its last fact reads the count of `git status` lines after the run, 1, and "
           "nothing more"], "integration log 25.4's row")
m += need(record_readme, ["*(dated note, 23 October 2026: of the `git status` line after the run it reads the count "
                          "alone"], "the record's evidence README")
old = read(f"{DEC}/unlocked-record/commands/check-run.py")
new = read(f"{DEC}/unlocked-record/round-2/commands/check-run.py")


def after_docstring(text):
    parts = text.split('"""')
    return parts[2] if len(parts) >= 3 else ""


m += need(old, ["drop-in's whole output and its step logs. Nothing is inferred."], "the record's check-run.py (kept)")
m += gone(new, ["Nothing is inferred."], "this round's check-run.py")
m += need(new, ["Not read, and so not checked here:", "the records infer that it is the run's own folder",
                "(the count is read; that it is the run's own folder, \"\n     \"untracked, is inferred, not read)"],
          "this round's check-run.py")
facts_old, facts_new = after_docstring(old).count("\nfact("), after_docstring(new).count("\nfact(")
m += [f"the two versions check {facts_old} and {facts_new} facts, not 34 each"] if (facts_old, facts_new) != (34, 34) else []
changed = [l for l in difflib.unified_diff(after_docstring(old).splitlines(), after_docstring(new).splitlines(),
                                           lineterm="", n=0)
           if l[:1] in "+-" and not l.startswith(("+++", "---"))]
labels = [l for l in changed if l[1:].startswith("fact(\"") or l[1:].lstrip().startswith("\"")]
m += [f"this round's check-run.py changes more than labels: {l[:100]}" for l in changed if l not in labels]
m += need(gate, ["98. **What was read in the run's evidence** (UNL-05)"], "M0-gate.md Section 6.3")
report("UNL-05", m, f"section 25's opening, 25.4's row and the record's README have their notes; this round's "
       f"check-run.py says what it reads and infers, and changes only its docstring and {len(labels)} label lines of "
       f"the same {facts_new} facts")

# The record's review status: read by an agent review; its fix not reviewed.
m = need(line_with(gate, "93. **Not reviewed**"), ["*(Dated note, 23 October 2026: reviewed by an agent the same day, at "
                                                   "`91c3b46a`, items 94-99.)*"], "item 93")
m += need(gate, ["99. **Not reviewed**: this fix is agent-written",
                 "| The review of the record of G0.5 recovery's drop-in run with the screen unlocked (23 October 2026, at "
                 "`91c3b46a`) |", "and the fix of its review (items 94-99)",
                 "this record was read by an agent review the same day (next bullet; until its fix this bullet said it had "
                 "not been reviewed)", "- **The fix of the review of the record of the drop-in run (23 October 2026; "
                 "integration log section 26).**", "with the fix of that record's review (section 26), have had no "
                 "accepting review"], "the gate summary")
m += need(line_with(runbook, "- **Who wrote it.**"), ["and of the record of the drop-in's run at `91c3b46a`", "the "
                                                      "follow-up's fourth fix of 23 October 2026, and the fix of the "
                                                      "review of the drop-in's record, have not been reviewed"],
          "the runbook's Who wrote it")
m += gone(line_with(runbook, "- **Who wrote it.**"), ["and the record of the drop-in's run that followed it, have not been "
                                                      "reviewed"], "the runbook's Who wrote it")
m += need(block(log, "### 25.5 ", "## 26."), ["- **Review:** this record has had no review; human sign-off pending. "
                                              "*(Dated note, 23 October 2026: an agent review read it the same day"],
          "integration log 25.5")
m += need(record_readme, ["*(Dated note, 23 October 2026: read by an agent review the same day, which raised UNL-01 to "
                          "UNL-05;"], "the record's evidence README")
m += need(line_with(a15, "- **Status:**"), ["Revised again the same day by the record of G0.5 recovery's whole drop-in "
                                            "run with the screen unlocked (integration log section 25)"],
          "ADR-0015's status line (its revisions' notes are kept as written; the ADR index gives their reviews)")
m += need(line_with(index, "| [0015](0015-threat-model.md) |"), ["which passed (read by the agent review of that record of "
                                                                 "the run, which raised UNL-01 to UNL-05, none on "
                                                                 "ADR-0015's text, and accepted by no review)"],
          "the ADR index")
m += gone(line_with(index, "| [0015](0015-threat-model.md) |"), ["which passed (not reviewed)"], "the ADR index")
report("review", m, "the record read by an agent review, at 91c3b46a, and its fix not reviewed, in the gate summary, the "
       "runbook, the integration log, the record's README and the ADR index")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 6 not as stated)")
sys.exit(1 if problems else 0)
