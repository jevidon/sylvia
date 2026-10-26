#!/usr/bin/env python3
"""A new version of Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/commands/completeness-checks.py, made by the
fix of the owner-readability findings of the same review (27 October 2026; integration log section 44). That fix rewrote
the evidence README's merge section (its findings OWN-RU-03 and OWN-RU-04): the merge commands now merge with
--ff-only and put CLAUDE.md's texts in with a command, the lock check before the commit; the bullet on a moved-on
m0-decisions, which names the files a conflict can come in, now begins "If the `log` line printed a commit, or the merge
refused", and "After the merge" no longer gives the texts' latest time, the merge commands' comment does. So three
checks of the version this one replaces fail on that tree by design (part 1's two on the merge commands and on the
latest time, and part 7's on the merge bullet), and this version asserts the new texts in their place: part 1, the
order of the merge commands (the fast-forward merge, the apply command, the lock check, the commit, the commit noted)
and the latest time in Left for the owner and in the commands' comment; part 7, the files named in the new bullet.
Everything else is the earlier version's, unchanged. Its description follows.

What the fix of the completeness findings of the review of m0-records-update changed, checked on the tree (27 October
2026 on the build Mac's clock; integration log section 43). One part per finding:
  1. CMP-01: CLAUDE.md is m0-decisions's, byte for byte (no agent text in it); the owner's step 2 has its latest time,
     right after the merge of m0-records-update, and names both texts, in the gate summary, the runbook's 0.3 and run 1,
     the evidence README's merge commands and the texts' file; the Stage 0 README opens with the caveat; every note that
     gives CLAUDE.md's paragraph as corrected has a later note; integration log 41.2 records the merge's message.
  2. CMP-02: the runbook's 0.7 and the gate summary's Section 5.4 name m0-decisions as the branch to commit to and build
     from (the fix of the fidelity findings changed them; retired-branch-texts.py, run beside this, reads every text).
  3. CMP-03: the five references the renumbering missed read as renumbered (renumbered-references.py, run beside this,
     reads every reference against the two branches).
  4. CMP-04: the one existing evidence file this branch changes, and the commits that changed it, are as the records now
     say; the evidence README, integration log 41.7 and the gate summary's item 180 say so.
  5. CMP-05: each note this fix gave a later note has it, after it on its line; and a sweep of the live texts (as
     retired-branch-texts.py reads them) for any paragraph that mentions R4-01, R4-02, the Zip guard or linkage.sh and
     whose last word on their state is an open one ("review pending", "reviewed next", "stays open until a review",
     "so the verdict stands", "a review that accepts it is still to come", a word inside a quotation not counting) with
     no later note after it: such a paragraph fails unless that word is in a history clause (after an opening "(Until"
     or "(until") or in a record the gate summary keeps of an earlier round (its Section 6.3 groups before item 178 and
     Section 8's bullets of integration log sections before 41), each listed.
  6. CMP-06: git diff --stat <commit> HEAD -- Apps Packages Spikes Fixtures Scripts Contracts
     Docs/Stage0/device-checklists, against each commit the owner's session log and this fix name, lists what the
     runbook's 0.3, step 7, now says; and the step says it.
  7. CMP-07: the logs of m0-records-update's checks with no header are the nine the evidence README now lists, and the
     files this branch changes against c72247a6 are the ones its merge bullet names.
  8. The records of this fix: the gate summary's items 199-206 and integration log section 43 exist, and the word limits
     of the opening (600), the State line (200), the two (800) and the runbook's run 1 (200) hold.
Read-only (git show, git diff, git log, git rev-parse); standard library only. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/completeness-checks.py
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/completeness-checks.py --sweep <root>
Prints one line per check, then the sweep's list, and exits 1 if any check fails. With --sweep, runs part 5's sweep
alone on the tree at <root> (the runner's control: 7f7eae88's tree, where it must find the open paragraphs this fix gave
later notes) and exits 1 if it finds an open paragraph.
"""
import re
import subprocess
import sys
from pathlib import Path

failures = []


def git(*args):
    out = subprocess.run(["git", *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def read(path):
    return Path(path).read_text(encoding="utf-8")


def check(part, label, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'} {part} {label}" + (f" ({detail})" if detail and not ok else ""))
    if not ok:
        failures.append(f"{part} {label}")


def has(part, label, text, *needs, gone=()):
    missing = [n for n in needs if n not in text]
    stale = [g for g in gone if g in text]
    check(part, label, bool(text) and not missing and not stale,
          "; ".join(["lacks: " + n[:100] for n in missing] + ["still says: " + g[:100] for g in stale]))


def line_with(text, start):
    found = [l for l in text.split("\n") if l.startswith(start)]
    return found[0] if len(found) == 1 else ""


def after(part, label, text, old, new):
    """The note `new` follows the note `old` on the same line."""
    lines = [l for l in text.split("\n") if old in l]
    ok = len(lines) == 1 and lines[0].find(old) < lines[0].find(new, lines[0].find(old))
    check(part, label, ok, f"{len(lines)} line(s) hold the old note" if len(lines) != 1 else "the later note is not after it")


GATE, RB, STAGE0 = "Docs/Stage0/M0-gate.md", "Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/README.md"
OPEN = re.compile(r"(?<!human )review pending|reviewed next|stays? open until a review|so the verdict stands|"
                  r"a review that accepts it is still to come")
LATER = re.compile(r"c3adae68|accepted|closed since|closed, the change|item 180|are closed|is closed")


def live_files(root):
    base = Path(root)
    files = [base / "CLAUDE.md", base / "README.md", base / "Docs/Sylvia_v1_iOS_Implementation_Plan.md"]
    for folder in ("Docs/ADRs", "Docs/Stage0", "Docs/Stage0/device-checklists"):
        files += sorted((base / folder).glob("*.md"))
    files += sorted(p for p in (base / "Docs/Stage0/evidence/M0-RecordsUpdate").rglob("*.md")
                    if p.name != "relayed-findings.md")
    return [(p, p.relative_to(base).as_posix()) for p in files if p.is_file()]


def gate_history(lines):
    """Lines of the gate summary that record an earlier round, as the fidelity fix's check reads them."""
    skip, in63, in8, skipping, reached = set(), False, False, False, False
    for n, line in enumerate(lines, 1):
        if line.startswith("#"):
            in63, in8, skipping = line.startswith("### 6.3 "), line.startswith("## 8. "), False
        if in63 and not reached and re.match(r"^(?:Corrected|Recorded) ", line):
            reached = line.startswith("Recorded on 26 October 2026, when `m0-records-update`")
            skipping = not reached
        if skipping:
            skip.add(n)
        heading = re.match(r"^- \*\*([^*]*)\*\*", line)
        if in8 and heading:
            nums = [int(x) for x in re.findall(r"integration log sections? (\d+)", heading.group(1))]
            if nums and max(nums) < 41:
                skip.add(n)
    return skip


def sweep_tree(root):
    """Part 5's sweep of the live texts under root: (its list, the number of open paragraphs)."""
    found, opened = [], 0
    for full, path in live_files(root):
        if path.endswith("integration-log.md"):
            continue  # the record of each round as it was done, and this branch's sections, with their own notes
        lines = full.read_text(encoding="utf-8").split("\n")
        history = gate_history(lines) if path == GATE else set()
        for n, line in enumerate(lines, 1):
            if not re.search(r"R4-0[12]|Zip guard|linkage\.sh", line):
                continue
            # A word inside a quotation (an odd number of double quotes before it on the line) quotes a text, here or a
            # finding's, and says nothing of the state.
            opens = [x for x in OPEN.finditer(line) if line.count('"', 0, x.start()) % 2 == 0]
            if not opens or any(x.start() > opens[-1].start() for x in LATER.finditer(line)):
                continue
            last = opens[-1]
            clause = line[line.rfind("(", 0, last.start()):last.start()]
            if n in history:
                found.append(f"history   {path}:{n}: a record of an earlier round ({last.group(0)!r})")
            elif re.match(r"\((?:\*\()?[Uu]ntil ", clause.lstrip("*")) or re.match(r"\(Until ", clause):
                found.append(f"history   {path}:{n}: in a history clause: ...{clause[:90]!r}")
            else:
                opened += 1
                found.append(f"OPEN      {path}:{n}: ...{line[max(0, last.start() - 140):last.end()]!r}")
    return found, opened


if len(sys.argv) > 2 and sys.argv[1] == "--sweep":
    # The sweep alone, on another tree (the runner's control runs it on 7f7eae88's, where it must find open ones).
    listing, opened = sweep_tree(sys.argv[2])
    print(f"the sweep of part 5 on {sys.argv[2]}: {opened} open paragraph(s)")
    for entry in listing:
        print(entry)
    sys.exit(1 if opened else 0)

EV, PARA = "Docs/Stage0/evidence/M0-RecordsUpdate/README.md", "Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md"
LOG = "Docs/Stage0/integration-log.md"
gate, rb, stage0, ev, para, log = (read(p) for p in (GATE, RB, STAGE0, EV, PARA, LOG))
print(f"commit: {git('rev-parse', 'HEAD').strip()}; uncommitted paths: {len(git('status', '--porcelain').splitlines())}")
print()

# 1. CMP-01
check("1", "CLAUDE.md is byte for byte c72247a6's", read("CLAUDE.md") == git("show", "c72247a6:CLAUDE.md"))
LATEST = "at the latest in the same pause between sittings as your merge of `m0-records-update`, right after it"
TOOLCHAIN = ("with a second text for the toolchain line, which still says that whether 27A9275 is the release build "
             "awaits a check of Apple's release notes")
step2_gate = line_with(gate, "2. **`CLAUDE.md`'s milestone paragraph: yours to correct")
has("1", "the gate summary's item 1, step 2: its latest time and both texts", step2_gate, LATEST, TOOLCHAIN,
    "item 199.)")
step2_rb = line_with(rb, "2. **`CLAUDE.md`'s milestone paragraph: yours to correct**")
has("1", "the runbook's 0.3, step 2: its latest time and both texts", step2_rb, LATEST, TOOLCHAIN, "item 199.)")
run1 = line_with(rb, "| 1 | Before the sessions |")
has("1", "the runbook's run 1: step 2 with the merge at the latest", run1,
    "step 2, `CLAUDE.md`, yours, at the latest with your merge of `m0-records-update` (0.3)")
block = ev[ev.find("```sh"):ev.find("```", ev.find("```sh") + 5)]
# Changed by the fix of the owner-readability findings: the fast-forward merge, then the command that puts the texts in,
# the lock check, the commit and the commit noted (the version this replaces wanted "merge m0-records-update" and the
# commit before the lock check).
order = [block.find(t) for t in ("merge --ff-only m0-records-update",
                                 "fix-1/owner/commands/apply-claude-md-texts.py",
                                 "Scripts/ci.d/12-dependency-lock.sh",
                                 "commit -m \"Point CLAUDE.md's milestone paragraph at m0-decisions\" -- CLAUDE.md",
                                 "rev-parse HEAD")]
check("1", "the evidence README's merge commands: the fast-forward merge, the command that puts the texts in, the lock "
      "check, the commit, then the commit noted", all(i >= 0 for i in order) and order == sorted(order), str(order))
# Changed by the same fix: the latest time is in Left for the owner, as before, and in the merge commands' comment, where
# "After the merge" no longer gives it.
has("1", "the evidence README's Left for the owner and its merge commands give the latest time", ev,
    "and at the latest in the same pause between sittings as the merge, right after it",
    "# Run 1's step 2, in the same pause, before Codex or any agent works in this checkout again.")
has("1", "the texts' file has its note of 27 October 2026", para,
    "*(27 October 2026: apply them at the latest in the same pause between sittings as your merge of "
    "`m0-records-update`,")
paragraphs = [p for p in stage0.split("\n\n") if p.strip()]
caveat = paragraphs[2] if len(paragraphs) > 2 else ""
has("1", "the Stage 0 README opens, after its first line, with the caveat on CLAUDE.md", caveat,
    "**`CLAUDE.md` is out of date on `m0-decisions` (27 October 2026).**",
    "`m0-records-update` leaves the file exactly as `m0-decisions` has it",
    "and both say never to build on `m0-decisions`",
    "`m0-decisions` is the product owner's session branch",
    "agent work goes on a branch of its own made from `m0-decisions` and reaches the owner's build only when merged",
    "`m0-sessions` is retired", "nothing reaches `main` before the M0 exit unless the product owner decides otherwise",
    "evidence/M0-RecordsUpdate/claude-md-paragraph.md")
check("1", "the caveat comes before the paragraph on where M0 stands",
      len(paragraphs) > 3 and paragraphs[3].startswith("**Where M0 stands (27 October 2026).**"))
for path, text, old in ((STAGE0, stage0, "*(corrected at the product owner's request on 24 October 2026, `5aec2518`, a "
                         "request recorded only in that commit's message: integration log sections 30 and 33)*"),
                        (GATE, gate, "(Section 7, item 5) *(corrected at your request on 24 October 2026, `5aec2518`: "
                         "Section 6.3, item 104)*"),
                        (GATE, gate, "(integration log section 20; Section 6.3, items 48-56) *(corrected at your request "
                         "on 24 October 2026: Section 6.3, item 104)*"),
                        (GATE, gate, "*(HON-11: corrected at your request on 24 October 2026, `5aec2518`: Section 6.3, "
                         "item 104)*"),
                        (GATE, gate, "now in Section 1, item 1 *(corrected at your request on 24 October 2026: item 104)*"),
                        (GATE, gate, "*(Dated note, 24 October 2026: changed at your request by the orchestrating session "
                         "that day, `5aec2518`: item 104.)*"),
                        (GATE, gate, "*(Dated note, 24 October 2026: changed at your request that day: item 104.)*"),
                        (GATE, gate, "a fourth thing for Section 5.4 (item 127).)*"),
                        (GATE, gate, "It was not put to a review either, and belongs in this one: Section 6.3, item 104.)*")):
    after("1", f"{path}: a later note after {old[:70]!r}", text, old, "*(27 October 2026:")
noted = [l for l in gate.split("\n") if re.search(r"(?:\(|: )(?:corrected|changed) at your request", l)]
bare_notes = [l[:60] for l in noted if "*(27 October 2026:" not in l[re.search(r"(?:\(|: )(?:corrected|changed) at "
                                                                                 r"your request", l).start():]]
check("1", f"every note in the gate summary that gives the paragraph as corrected or changed at your request has a "
      f"later note after it on its line ({len(noted)} lines)", len(noted) >= 7 and not bare_notes,
      f"{len(noted)} lines; without one: {bare_notes}")
has("1", "integration log 41.2 records the merge's message and that no commit rewrote the paragraph", log,
    "the merge's message says that \"the next commit rewrites it\"; no commit of this branch rewrote the paragraph")
check("1", "git diff 4c0fa815 d1fb3dd4 -- CLAUDE.md prints nothing, as that note says",
      git("diff", "4c0fa815", "d1fb3dd4", "--", "CLAUDE.md") == "")

# 2. CMP-02
seven = rb[rb.find("**0.7 The Mac identity key"):rb.find("**0.8 ")]
has("2", "the runbook's 0.7 has the log committed on m0-decisions", seven,
    "Record: commit the regenerated log on `m0-decisions` (0.3, step 6;",
    gone=("commit the regenerated log on `m0-sessions` (0.3, step 6; until",))
h1 = line_with(gate, "- You, the product owner, only if you want agent work done during the sessions")
has("2", "Section 5.4's bullet on H-1 has the records committed on, and builds from, m0-decisions", h1,
    "which you commit on `m0-decisions`", "until you say so, build from `m0-decisions`",
    gone=("committed on `m0-sessions` (Section 1", "until you say so, build from `m0-sessions`"))

# 3. CMP-03
branch = line_with(gate, "- **Branch:**")
has("3", "Section 8's Branch bullet dates pull request #6's merge by item 173", branch,
    "this line dated it 24 October alone: Section 6.3, item 173)", gone=("alone: Section 6.3, item 146)",))
instr = line_with(gate, "- **Your instructions brought up to date (24 October 2026).**")
has("3", "Section 8's bullet on the update of your instructions cites items 131-137, section 36 and items 138-142",
    instr, "the Stage 0 README (Section 6.3, items 131-137;", "the reports and the integration log, section 36)",
    "made the two agree (Section 6.3, items 138-142).",
    gone=("(Section 6.3, items 104-110;", "the integration log, section 28)", "(Section 6.3, items 111-115)"))
item150 = line_with(gate, "150. **Not reviewed**")
has("3", "item 150 cites integration log 36 and 37", item150, "integration log 36 and 37;",
    gone=("integration log 36 and 29",))
has("3", "item 184 and integration log 41.2 have their notes", gate + log, "kept four of `m0-sessions`'s numbers, item "
    "146 for 173", "kept four of `m0-sessions`'s numbers, item 146, items 104-110, section 28 and items 111-115")

# 4. CMP-04
FILE = "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
changed = [l for l in git("diff", "--name-status", "c72247a6", "HEAD", "--", "Docs/Stage0/evidence/").splitlines()
           if not l.startswith("A")]
check("4", "the one existing evidence file this branch changes against c72247a6", changed == [f"M\t{FILE}"],
      "; ".join(changed))
commits = sorted(c[:8] for c in git("log", "--format=%h", "c72247a6..HEAD", "--", FILE).split())
check("4", "the commits that changed it on this branch's line: 83ed5ff3, 944a6302, f95de709 and 9f5edab1",
      commits == sorted(["83ed5ff3", "944a6302", "f95de709", "9f5edab1"]), " ".join(commits))
check("4", "m0-decisions's text is 05bdea4d's", git("rev-parse", f"c72247a6:{FILE}") == git("rev-parse", f"05bdea4d:{FILE}"))
has("4", "the evidence README, integration log 41.7 and item 180 say so", ev + log + gate,
    "*(27 October 2026: the second is the text `m0-exit-prep` left, which of the earlier rounds only that branch's "
    "fourth and fifth fixes ran",
    "is the text `m0-exit-prep` left, which of the earlier rounds only that branch's fourth and fifth fixes ran",
    "*(27 October 2026: the old one is the text `m0-exit-prep` left, its row 76 entry rewritten in place there four "
    "times")

# 5. CMP-05
for path, text, old in (
        (RB, rb, "before the reviews of ADR-0014; *(done by an agent on 24 October 2026, reviewed next: Section 6)*"),
        (GATE, gate, "by its owner (Section 1, item 4) *(done by an agent on 24 October 2026, reviewed next)*"),
        (GATE, gate, "which its ADR-0014 items wait for *(done by an agent on 24 October 2026, reviewed next)*"),
        (GATE, gate, "ADR-0014's lock and item 7, after `linkage.sh`'s run *(done by an agent on 24 October 2026, "
         "reviewed next)*"),
        (GATE, gate, "and of its lock, after `linkage.sh`'s run *(done by an agent on 24 October 2026, reviewed next)*"),
        (GATE, gate, "so this item stays open until a review accepts the change, and `linkage.sh` run offline;"),
        (GATE, gate, "The fix of that review answers the three, not reviewed: Section 6.3, items 127-130.)*"),
        (GATE, gate, "this note called both done: Section 1, item 4; Section 6.3, item 119)*"),
        (GATE, gate, "the review of the decisions round's fix, OWN2-01) *(24 October 2026: answered by an agent's change"),
        (GATE, gate, "their fix answers both, review pending, so row 76 stays failed until a review accepts it;"),
        (GATE, gate, "so the counts are those of 22 October 2026, passed-host 11 and failed 5"),
        (GATE, gate, "`evidence/M0-ExitPrep/fix-2/round-2/commands/gate-checks.sh`); not reviewed."),
        (GATE, gate, "`evidence/M0-DeviceA/fix-1/commands/gate-checks.sh`); this fix has not been reviewed."),
        (GATE, gate, "`evidence/M0-DeviceA/fix-1/accuracy/commands/gate-checks.sh`); this fix has not been reviewed."),
        (GATE, gate, "`evidence/M0-DeviceA/fix-1/completeness/commands/gate-checks.sh`); this fix has not been reviewed."),
        (GATE, gate, "`evidence/M0-DeviceA/fix-1/owner/commands/gate-checks.sh`); this fix has not been reviewed."),
        ("Docs/ADRs/0004-epub-reader-adapter.md", read("Docs/ADRs/0004-epub-reader-adapter.md"),
         "(two routes around that rule are still open: ADR-0014, review round 4, R4-01 and R4-02)"),
        ("Docs/ADRs/0014-dependency-lock-and-license-inventory.md",
         read("Docs/ADRs/0014-dependency-lock-and-license-inventory.md"), "Since that fix, by an agent and not reviewed, "
         "CI fails a version-specific manifest"),
        ("Docs/ADRs/0015-threat-model.md", read("Docs/ADRs/0015-threat-model.md"), "which has two open routes around it "
         "(ADR-0014 review round 4, R4-01 and R4-02)"),
        ("Docs/ADRs/0015-threat-model.md", read("Docs/ADRs/0015-threat-model.md"), "only once ADR-0014's R4-01 and R4-02 "
         "are closed (below) *(24 October 2026"),
        ("Docs/ADRs/0015-threat-model.md", read("Docs/ADRs/0015-threat-model.md"), "the open routes around the CI import "
         "rule (B12), before the M1 app target is created"),
        ("Docs/ADRs/0015-threat-model.md", read("Docs/ADRs/0015-threat-model.md"), "Revised on 26 October 2026 by the fix "
         "of that review (integration log section 33): those notes now say answered, review pending"),
        ("Docs/ADRs/README.md", read("Docs/ADRs/README.md"), "On 26 October 2026 those notes were reworded: R4-01 and "
         "R4-02 answered by an agent's change, review pending, not closed"),
        (STAGE0, stage0, "both answered by an agent's change, review pending, so the verdict stands"),
        (STAGE0, stage0, "with the branch read read-only and the device results neither judged nor taken in (section "
         "35); that fix has not been reviewed.)*")):
    later = "Revised on 27 October 2026" if old.startswith("Revised on 26 October") else "(27 October 2026:"
    after("5", f"{Path(path).name}: a later note after {old[:60]!r}", text, old, later)
has("5", "the ADR index's column is dated 27 October 2026, with its history", read("Docs/ADRs/README.md"),
    "| ADR | Title | Status (27 October 2026) | Owner during Stage 0 |",
    "Until 27 October 2026 it read \"Status (26 October 2026)\"")

sweep, open_found = sweep_tree(".")
check("5", "no live paragraph's last word on R4-01, R4-02 or linkage.sh is an open one without a later note",
      open_found == 0, f"{open_found} found")

# 6. CMP-06
PATHS = ["Apps", "Packages", "Spikes", "Fixtures", "Scripts", "Contracts", "Docs/Stage0/device-checklists"]
for commit, early in (("96bdc7e9", True), ("8404f342", True), ("432acc13", True), ("4be1a1a4", False),
                      ("d5336111", False), ("c72247a6", False)):
    stat = git("diff", "--stat", commit, "HEAD", "--", *PATHS)
    files = [l.split("|")[0].strip() for l in stat.splitlines() if "|" in l]
    code = [f for f in files if f.split("/")[0] in ("Apps", "Packages", "Spikes", "Fixtures", "Contracts", "...")]
    recovery = re.search(r"device-checklists/G05-Recovery\.md\s*\|\s*(\d+)", stat)
    scripts = sorted(f for f in files if f.startswith("Scripts/"))
    ok = scripts == ["Scripts/check-dependency-lock.py", "Scripts/ci.d/12-dependency-lock.sh"] and (
        (len(code) == 4 and all("DeviceTests" in c for c in code) and recovery and recovery.group(1) == "25") if early
        else (not code and recovery and recovery.group(1) == "7"))
    check("6", f"against {commit}: " + ("the four files of DeviceTests and 25 lines of the G0.5 recovery checklist, with "
          "the Zip guard's two scripts and the checklists' wording" if early else "nothing under Apps, Packages, "
          "Spikes, Fixtures or Contracts; the Zip guard's two scripts and the checklists' wording"),
          bool(ok), f"{len(files)} files: " + ", ".join(files))
step7 = line_with(rb, "7. **When a session already run is repeated:**")
has("6", "the runbook's 0.3, step 7, says both", step7,
    "they are what it lists against the commits of your sittings from `4be1a1a4` on",
    "against the earlier commits of rows 3a-3c, `96bdc7e9`, `8404f342` and `432acc13`, it also lists your own "
    "`4be1a1a4`", "its finding CMP-06", gone=("they are what it lists against your first sittings' commits",))

# 7. CMP-07
checks_dir = Path("Docs/Stage0/evidence/M0-RecordsUpdate/checks")
headed = re.compile(r"(command:|commit:|step-08-paths:|correction-texts-compare:|renumber-sessions\.py)")
bare = sorted(p.name for p in checks_dir.glob("*.log")
              if p.stat().st_size and not headed.match(p.read_text(encoding="utf-8").split("\n", 1)[0]))
listed = re.search(r"the\s+nine others start with their results, with no header: (.*?)\. They ran", ev, re.S)
names = sorted(re.findall(r"`([^`]+\.log)`", listed.group(1))) if listed else []
check("7", "the README's nine logs with no header are the ones that have none", names == bare and len(bare) == 9,
      f"README: {names}; logs: {bare}")
modified = [l.split("\t")[1] for l in git("diff", "--name-status", "c72247a6", "HEAD").splitlines()
            if l.startswith("M")]
named = {"ADRs": "the ADRs and their index", "reports": "the gate reports", "checklists": "the checklists",
         "runbook": "the runbook", "gate": "the gate summary", "plan": "the plan", "amendments": "the amendments",
         "log": "the integration log", "stage0": "the Stage 0 README", "contracts": "`M0-contracts.md`",
         "readme": "the repository `README.md`", "inventory": "`Docs/Licenses/third-party-inventory.md`",
         "guard": "the Zip guard's two scripts", "evidence": "one evidence file"}  # "that one\n  evidence file" until the
# fix of the owner-readability findings, which rewrote the bullet


def group(p):
    for key, rx in (("ADRs", r"Docs/ADRs/"), ("checklists", r"Docs/Stage0/device-checklists/"),
                    ("reports", r"Docs/Stage0/G0\d"), ("runbook", r"Docs/Stage0/M0-device-runbook"),
                    ("gate", r"Docs/Stage0/M0-gate"), ("plan", r"Docs/Sylvia_v1"), ("amendments", r"Docs/Stage0/M0-plan"),
                    ("log", r"Docs/Stage0/integration-log"), ("stage0", r"Docs/Stage0/README"),
                    ("contracts", r"Docs/Stage0/M0-contracts"), ("readme", r"README\.md$"),
                    ("inventory", r"Docs/Licenses/third-party"), ("guard", r"Scripts/"),
                    ("evidence", r"Docs/Stage0/evidence/")):
        if re.match(rx, p):
            return key
    return None


groups = {group(p) for p in modified}
# The bullet as the fix of the owner-readability findings rewrote it (until then "- **If it has moved on**", which ended
# before "- **After the merge:**").
merge_bullet = ev[ev.find("- **If the `log` line printed a commit, or the merge refused**"):ev.find("- **After the merge,**")]
check("7", "every file this branch changes against c72247a6 is in a group the merge bullet names",
      None not in groups and all(named[g] in merge_bullet for g in groups),
      "unnamed: " + ", ".join(sorted(p for p in modified if group(p) is None or named[group(p)] not in merge_bullet)))
check("7", "CLAUDE.md is not among them", "CLAUDE.md" not in modified)

# 8. The records of this fix
for n in range(199, 207):
    check("8", f"the gate summary's item {n}", bool(re.search(rf"(?m)^{n}\. \*\*", gate)))
check("8", "integration log section 43", "\n## 43. " in log)


def words(text):
    return len(text.split())


opening, state = line_with(gate, "**Recommendation** (Section 7)"), line_with(gate, "- **State:**")
check("8", f"word limits: the opening {words(opening)} (600), the State line {words(state)} (200), the two "
      f"{words(opening) + words(state)} (800), run 1 {words(run1)} (200)",
      words(opening) <= 600 and words(state) <= 200 and words(opening) + words(state) <= 800 and words(run1) <= 200)

print()
print("== the sweep of part 5: every paragraph whose last word on R4-01, R4-02 or linkage.sh is an open one")
for s in sweep:
    print(s)
print()
print(f"result: {'pass' if not failures else 'FAIL'} ({len(failures)} failed)")
for f in failures:
    print("  failed: " + f)
sys.exit(1 if failures else 0)
