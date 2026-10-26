#!/usr/bin/env python3
"""What the fix of the owner-readability findings of the review of m0-records-update changed, checked on the tree (27
October 2026 on the build Mac's clock; integration log section 44), and the answers of the earlier fixes it relies on.
One part per finding, or pair of findings:
  1. OWN-RU-01 and OWN-RU-02 (answered by the fix of the fidelity findings): the runbook's 0.7 has the Mac identity log
     committed on m0-decisions, and the gate summary's Section 5.4 bullet on H-1 has the records committed on, and the
     sessions built from, m0-decisions (retired-branch-texts.py, run beside this, reads every live text).
  2. OWN-RU-03, the evidence README's merge section: its commands check that m0-records-update..m0-decisions is empty and
     merge with --ff-only, then apply CLAUDE.md's texts by the command, check the diff, run the lock check, commit and note
     the commit, in that order, with no plain merge; its bullet on a moved-on m0-decisions has an agent merge
     m0-decisions into this branch first, bring the account of the sittings up to date and run the new owner-records
     check with --owner-head; "After the merge" runs 0.8's and 0.3 step 7's checks, 0.8's paths being runbook 0.8's
     exactly, and no longer asserts their answers; the README's items 1 and 5 have their notes; the new owner-records
     check exists and takes --owner-head. It also prints, as a note that fails nothing, whether m0-decisions (read only)
     is in HEAD's history, so that the merge would be a fast-forward now.
  3. OWN-RU-03, every merge into m0-decisions: the runbook's 0.3, step 5, gives `git merge --ff-only <its branch>` and
     the gate summary's item 1, step 5, the fast-forward, each with the agent's merge of m0-decisions first; the
     runbook's step has a history clause, and the gate summary's step a pointer to item 209, which quotes the history
     note the step had at 7c87a82d word for word (moved to keep the step within 400 words); the paragraph for CLAUDE.md
     says so to agents, and its note gives the earlier sentence.
  4. OWN-RU-04: CLAUDE.md is c72247a6's, byte for byte; the apply command exists and is named in the README's merge
     commands, the runbook's 0.3, step 2, the gate summary's item 1, step 2, and the texts' file; the steps give the
     same pause, before Codex or any agent works in the checkout again; the texts' file states the order.
  5. OWN-RU-05: the runbook's Section 2 has the rule for a step run again; 1.2 and 1.3 have their notes, with new names
     for each committed file; 0.3, step 7, and the gate summary's rule on repeats say so; 1.2's and 1.3's command lines
     are as before (the owner's); no checklist changed since 7c87a82d; every file the notes call committed is.
  6. OWN-RU-06: Session 0's order line points to the setup record and gives 0.3 as it stands; the gate summary's item 1,
     step 8, says before Session 0.4 records A; each with its history clause.
  7. OWN-RU-07 and OWN-RU-08 (answered by the earlier fixes): the runbook's 0.3, step 7, names DeviceTests against rows
     3a-3c's commits; the integration log's opening, the gate summary's bullet on the M0 work on main, its technical
     lead's item, its Section 6.3 item 1, the runbook's run 12 and Section 7's notes on linkage.sh each have a later note.
  8. The records of this fix: the gate summary's items 207-214, integration log section 44, the runbook's Who wrote it,
     the Stage 0 README and the evidence README name it; the word limits of the opening (600), the State line (200), the
     two (800), run 1 (200) and each step of the gate summary's item 1 (400) hold.
Read-only (git show, git diff, git ls-files, git merge-base, git rev-parse); standard library only. Run from the root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/owner-checks.py
Prints one line per check and exits 1 if any fails.
"""
import re
import subprocess
import sys
from pathlib import Path

failures = []


def git(*args, ok=(0,)):
    out = subprocess.run(["git", *args], capture_output=True, text=True)
    if out.returncode not in ok:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out


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


GATE, RB, LOG = "Docs/Stage0/M0-gate.md", "Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/integration-log.md"
STAGE0 = "Docs/Stage0/README.md"
EV = "Docs/Stage0/evidence/M0-RecordsUpdate/README.md"
PARA = "Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md"
HERE = "Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands"
APPLY = f"{HERE}/apply-claude-md-texts.py"
gate, rb, log, stage0, ev, para = (read(p) for p in (GATE, RB, LOG, STAGE0, EV, PARA))
print(f"commit: {git('rev-parse', 'HEAD').stdout.strip()}; uncommitted paths: "
      f"{len(git('status', '--porcelain').stdout.splitlines())}")
print()

# 1. OWN-RU-01 and OWN-RU-02
seven = rb[rb.find("**0.7 The Mac identity key"):rb.find("**0.8 ")]
has("1", "the runbook's 0.7 has the log committed on m0-decisions, with its history clause", seven,
    "Record: commit the regenerated log on `m0-decisions` (0.3, step 6;", "this said `m0-sessions`: that review's finding "
    "FID-RU-01", gone=("commit the regenerated log on `m0-sessions` (0.3, step 6; until",))
h1 = line_with(gate, "- You, the product owner, only if you want agent work done during the sessions")
has("1", "Section 5.4's bullet on H-1 has the records committed on, and builds from, m0-decisions", h1,
    "which you commit on `m0-decisions`", "until you say so, build from `m0-decisions`", "FID-RU-02",
    gone=("committed on `m0-sessions` (Section 1", "until you say so, build from `m0-sessions`"))

# 2. OWN-RU-03: the evidence README's merge section
section = ev[ev.find("## Merging it into `m0-decisions`, between sittings"):ev.find("## The checks")]
block = section[section.find("```sh"):section.find("```", section.find("```sh") + 5)]
order = [block.find(t) for t in ("cd ~/Git/sylvia-sessions", "git status --short", "git branch --show-current",
                                 "git log --oneline m0-records-update..m0-decisions", "git merge --ff-only m0-records-update",
                                 "python3 -I " + APPLY, "git diff --stat", "Scripts/ci.d/12-dependency-lock.sh",
                                 "git commit -m \"Point CLAUDE.md's milestone paragraph at m0-decisions\" -- CLAUDE.md",
                                 "git rev-parse HEAD")]
check("2", "the merge commands, in order: the log line, the fast-forward merge, the apply command, the diff, the lock "
      "check, the commit, the commit noted", all(i >= 0 for i in order) and order == sorted(order), str(order))
check("2", "no plain merge of m0-records-update in the merge commands",
      not re.search(r"git merge (?!--ff-only)\S*\s*m0-records-update", block) and block.count("git merge") == 1)
moved = section[section.find("- **If the `log` line printed a commit, or the merge refused**"):
                section.find("- **After the merge,**")]
has("2", "the bullet on a moved-on m0-decisions: no other merge; the agent's merge first; the account of the sittings; "
    "the new check with --owner-head", moved, "Do not merge another way.",
    "to merge `m0-decisions` into\n  `m0-records-update`", "bring\n  the account of your sittings in these records up to date",
    "these records changing, never yours", "fix-1/owner/commands/owner-records-intact.py", "`--owner-head`",
    "the merge is\n  now a fast-forward", gone=("merge cleanly",))
after = section[section.find("- **After the merge,**"):section.find("*(This section's history.")]
has("2", "After the merge runs 0.8's check and 0.3 step 7's, rather than state their answers", after,
    "git diff --stat 9cdb0a02 HEAD -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery",
    "':(exclude)Spikes/G05-Recovery/DeviceTests'",
    "git diff --stat <the commit your last sitting built from> HEAD -- Apps Packages Spikes Fixtures Scripts Contracts",
    "The first prints nothing when 0.8 still needs nothing; if it prints anything, 0.8 runs again",
    "fix-1/owner/checks/merge-simulation.log")
check("2", "the README no longer states that nothing repeats after the merge", "nothing is to be repeated for it" not in ev)


def paths_of(command):
    words = command.replace("\\\n", " ").split()
    return words[words.index("--") + 1:] if "--" in words else []


rb08 = rb[rb.find("**0.8 G0.5 recovery report row 10"):rb.find("**0.9 ")]
m = re.search(r"`git diff --stat 9cdb0a02 HEAD -- ([^`]*)`", rb08)
readme08 = re.search(r"git diff --stat 9cdb0a02 HEAD -- (.*?)# runbook 0.8", after, re.S)
check("2", "the README's 0.8 check names runbook 0.8's paths exactly",
      bool(m and readme08) and m.group(1).split() == readme08.group(1).replace("\\", " ").split(),
      f"runbook: {m.group(1) if m else None}; README: {readme08.group(1) if readme08 else None}")
has("2", "the README's items 1 and 5 have their notes", ev,
    "its new version,\n   [`fix-1/owner/commands/owner-records-intact.py`]",
    "*(27 October 2026: on this branch; on `m0-decisions` after your\n   merge, 0.8's command")
script = read(f"{HERE}/owner-records-intact.py")
check("2", "the new owner-records check takes --owner-head and --base, its defaults those of the version it replaces",
      'ap.add_argument("--owner-head", default=OWNER_HEAD' in script and 'ap.add_argument("--base", default=BASE' in script
      and 'OWNER_HEAD = "c72247a69a374ce361834550b92689b4abab95ee"' in script)
real = git("rev-parse", "m0-decisions").stdout.strip()
ff = git("merge-base", "--is-ancestor", "m0-decisions", "HEAD", ok=(0, 1)).returncode == 0
print(f"note 2 m0-decisions (read only) is at {real[:8]}; it is {'' if ff else 'NOT '}in HEAD's history, so a merge "
      f"of HEAD into it would {'' if ff else 'NOT '}be a fast-forward now")

# 3. OWN-RU-03: every merge into m0-decisions a fast-forward
step5 = line_with(rb, "5. **Agent work.**")
has("3", "the runbook's 0.3, step 5: git merge --ff-only, the agent's merge first, and its history clause", step5,
    "by you (`git merge --ff-only <its branch>` in `~/Git/sylvia-sessions`",
    "then ask the agent to merge `m0-decisions` into its branch first",
    "(Until 27 October 2026 this step gave `git merge <its branch>`", "its finding OWN-RU-03",
    gone=("by you (`git merge <its branch>` in",))
gstep5 = line_with(gate, "5. **The two requests of item 4: answered by agents.**")
has("3", "the gate summary's item 1, step 5: the fast-forward, the agent's merge first, and its history pointing to item "
    "209", gstep5, "as a fast-forward (`git merge --ff-only`), the agent first merging `m0-decisions` into its branch if "
    "`m0-decisions` has moved on, so that you never resolve a conflict",
    "(Its history: Section 6.3, items 119, 178, 180 and 209.)",
    gone=("(Until 26 October 2026, on `m0-exit-prep`, this step gave R4-01 and R4-02",))
OLD_NOTE = ("\"(Until 26 October 2026, on `m0-exit-prep`, this step gave R4-01 and R4-02 as answered by an agent's change, "
            "review pending, and, on `m0-sessions`, both requests as in an agent's run and agent work as starting from and "
            "merging into `m0-sessions`: Section 6.3, items 119, 178 and 180.)\"")
old5 = line_with(git("show", f"7c87a82d:{GATE}").stdout, "5. **The two requests of item 4: answered by agents.**")
has("3", "item 209 quotes step 5's history note as it read at 7c87a82d, word for word, and says why it moved",
    line_with(gate, "209. **Every merge into `m0-decisions` a fast-forward**"), OLD_NOTE,
    "To keep item 1's step 5 within the 400 words the follow-up's check of its finding OWN4-09 allows a step of item 1")
check("3", "that note is step 5's at 7c87a82d", OLD_NOTE.strip('"') in old5)
block_para = para[para.find("```markdown"):para.find("```", para.find("```markdown") + 5)]
has("3", "the paragraph for CLAUDE.md gives the fast-forward, and its note the earlier sentence", para,
    "as a fast-forward (`git merge --ff-only`): if `m0-decisions` has moved on since the branch was made, first merge "
    "`m0-decisions` into the branch", "on agent work ended \"by the owner or by an agent the owner asks; never change the "
    "owner's session records or evidence.\"")
check("3", "that sentence is in the paragraph itself (the fenced block)", "as a fast-forward (`git merge --ff-only`)"
      in block_para)

# 4. OWN-RU-04
check("4", "CLAUDE.md is byte for byte c72247a6's", read("CLAUDE.md") == git("show", "c72247a6:CLAUDE.md").stdout)
check("4", "the apply command exists", Path(APPLY).is_file())
step2_rb = line_with(rb, "2. **`CLAUDE.md`'s milestone paragraph: yours to correct**")
step2_gate = line_with(gate, "2. **`CLAUDE.md`'s milestone paragraph: yours to correct")
SAME = "before Codex or any agent works in the checkout again"
for name, text in (("the runbook's 0.3, step 2", step2_rb), ("the gate summary's item 1, step 2", step2_gate)):
    has("4", f"{name}: the command, the same pause, and its history clause", text, "python3 -I " + APPLY, SAME,
        "at the latest in the same pause between sittings as your merge of `m0-records-update`, right after it",
        "its finding OWN-RU-04" if name.startswith("the runbook") else "item 210.)",
        gone=("before you ask an agent for anything, and at the latest",
              "put the paragraph in place of the one that begins"))
has("4", "the texts' file states the order and names the command", para,
    "*(27 October 2026: the order, in one pause between sittings,", "(1) your merge of `m0-records-update`",
    "(2)\n[`fix-1/owner/commands/apply-claude-md-texts.py`]", "(3) `git diff --stat`", "(4) the lock check",
    "(5) your commit", "(6) the commit noted in the session log")
has("4", "the README's Left for the owner has its note", ev,
    "*(27 October\n2026: the order is now fixed, in one pause between sittings, before Codex or any agent works in the "
    "checkout again:\nyour fast-forward merge of this branch;")

# 5. OWN-RU-05
sec2 = rb[rb.find("## 2. How to record results"):rb.find("## 3. Session plan")]
has("5", "the runbook's Section 2: a step run again writes new names, never over a committed file", sec2,
    "- **A step run again** (a repeat under 0.3, step 7, or a run after a blocked or failed one)",
    "never over a file already committed", "`git rev-parse --short HEAD`",
    "it holds over the file names the checklists' commands give", "its finding OWN-RU-05")
s12 = rb[rb.find("**1.2 The persistence suite on the device"):rb.find("**1.3 App Transport Security")]
s13 = rb[rb.find("**1.3 App Transport Security"):rb.find("**1.4 Automated audio tests")]
has("5", "1.2's note: its committed files and their new names; its commands stay", s12,
    "*(27 October 2026: `step-1-tests.log` holds your first attempt", "`step-1-tests-<commit>.log`",
    "`step-1-2-results-<commit>.txt`", "The commands above stay as you committed them.")
has("5", "1.3's note: its committed files and their new names; its command stays", s13,
    "*(27 October 2026: `step-01-ats.log`, `step-01-ats.txt` and `step-04-suspension.txt`", "`step-01-ats-<commit>.log`",
    "`step-01-ats-<commit>.txt`", "`step-04-suspension-<commit>.txt`", "the command above stays as it is")
for tee in ("  | tee ../../Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log",
            "  2>&1 | tee ../../../Docs/Stage0/evidence/G05-AI/device/step-01-ats.log"):
    check("5", f"the command line is as before: {tee.strip()[:60]}", rb.split("\n").count(tee) == 1
          and git("show", f"7c87a82d:{RB}").stdout.split("\n").count(tee) == 1)
step7 = line_with(rb, "7. **When a session already run is repeated:**")
has("5", "the runbook's 0.3, step 7, writes each repeat under new names", step7,
    "writing each repeat's logs and records under new names, never over the files of the run it repeats")
has("5", "the gate summary's rule on repeats says so", gate,
    "each repeat's logs and records under new names, never over the files of the run it repeats, which stay as you "
    "committed them (runbook Section 2; since 27 October 2026: Section 6.3, item 211)")
check("5", "no checklist changed since 7c87a82d", git("diff", "--name-only", "7c87a82d", "--",
                                                       "Docs/Stage0/device-checklists").stdout == "")
committed = git("ls-files", "Docs/Stage0/evidence/G05-Recovery/device", "Docs/Stage0/evidence/G05-AI/device").stdout.split()
names = ["step-1-tests.log", "step-1-2-results.txt", "step-1-hosted-tests.log", "step-1-hosted-results.md",
         "step-01-ats.log", "step-01-ats.txt", "step-04-suspension.txt", "step-01-ats-initial.log"]
missing = [n for n in names if not any(c.endswith("/" + n) for c in committed)]
check("5", "every file the notes call committed is committed", not missing, ", ".join(missing))

# 6. OWN-RU-06
order0 = line_with(rb, "Order: 0.1, then 0.3")
has("6", "Session 0's order line: the setup record, 0.3 as it stands, and its history clause", order0,
    "Session 0 has begun: your setup record of 26 October 2026 (`evidence/M0-runbook/2026-10-26-setup.txt`)",
    "of 0.3, steps 1 and 3 are done, step 2 is yours with your merge of `m0-records-update`",
    "(Until 27 October 2026 this line said that since 24 October 2026 only 0.3's steps 1 and 4 were left",
    "its finding OWN-RU-06", gone=("(since 24 October 2026 only its steps 1 and 4 are left to do",))
step8 = line_with(gate, "8. **Check that your iPhone 13 mini (device A) runs iOS 26**")
has("6", "the gate summary's item 1, step 8: before Session 0.4 records it, with its history clause", step8,
    "update it once to iOS 26.x before Session 0.4 records it",
    "(Until 27 October 2026 this step said before Session 0, which your sittings had begun",
    gone=("update it once to iOS 26.x before Session 0, or",))

# 7. OWN-RU-07 and OWN-RU-08
has("7", "the runbook's 0.3, step 7, names DeviceTests against rows 3a-3c's commits", step7,
    "against the earlier commits of rows 3a-3c, `96bdc7e9`, `8404f342` and `432acc13`, it also lists your own "
    "`4be1a1a4`", "the four files of `Spikes/G05-Recovery/DeviceTests`")
opening = log.split("\n")[2]
has("7", "the integration log's opening has the note on m0-sessions retired", opening,
    "then `m0-sessions` was retired, `m0-decisions` staying the product owner's session branch")
has("7", "the gate summary's bullet on the M0 work on main has its later note",
    line_with(gate, "- **The M0 work is on `main`, and the M0 gate is still pending.**"),
    "*(26 October 2026: no longer: `m0-sessions` is retired")
has("7", "the technical lead's item in Section 5.4 has its later note",
    line_with(gate, "- The technical lead, which since 22 October 2026 is you (your instruction): before Session 0"),
    "`m0-sessions` being retired: Section 6.3, items 178 and 190.)*")
has("7", "Section 6.3, item 1, has its later note", line_with(gate, "1. **ADR-0002's branch rule and the merge.**"),
    "*(26 October 2026: no longer: the sessions build from `m0-decisions`")
has("7", "the runbook's run 12 has the later note on linkage.sh", line_with(rb, "| 12 | 10 Sign-offs and the exit review"),
    "*(27 October 2026: made on `m0-exit-prep`, which the last round of its review, at `c3adae68`, accepted")
sec7 = gate[gate.find("## 7. Recommendation"):gate.find("## 8. About this summary")]
notes = [l for l in sec7.split("\n") if "reviewed next" in l]
bare = [l[:50] for l in notes if any(l.find("(27 October 2026:", i) < 0
                                     for i in [m.end() for m in re.finditer(r"reviewed next\)\*", l)])]
check("7", f"in Section 7, every note on linkage.sh reviewed next has a later note after it ({len(notes)} lines)",
      bool(notes) and not bare, f"without one: {bare}")

# 8. The records of this fix
for n in range(207, 215):
    check("8", f"the gate summary's item {n}", bool(re.search(rf"(?m)^{n}\. \*\*", gate)))
check("8", "integration log section 44", "\n## 44. " in log)
has("8", "the runbook's Who wrote it names this fix", line_with(rb, "- **Who wrote it.**"),
    "*(27 October 2026: its owner-readability findings, as relayed,", "integration log section 44.)*")
has("8", "the Stage 0 README and the evidence README name it", stage0 + ev, "(integration log section 44;",
    "[`fix-1/owner/`](fix-1/owner/README.md) and integration log section 44")


def words(text):
    return len(text.split())


opening_g, state = line_with(gate, "**Recommendation** (Section 7)"), line_with(gate, "- **State:**")
run1 = line_with(rb, "| 1 | Before the sessions |")
check("8", f"word limits: the opening {words(opening_g)} (600), the State line {words(state)} (200), the two "
      f"{words(opening_g) + words(state)} (800), run 1 {words(run1)} (200)",
      words(opening_g) <= 600 and words(state) <= 200 and words(opening_g) + words(state) <= 800 and words(run1) <= 200)
# Each step of the gate summary's item 1 within the 400 words the follow-up's check of OWN4-09 allows (read as the
# device-A update's recheck-own.py reads them: item 1 cut at the lines that begin with a number).
item1 = gate[gate.find("**1. Before the first session**"):gate.find("**2. The device sessions**")]
steps = [len(p.split()) for p in re.split(r"(?m)^(?=\d+\. )", item1)]
check("8", f"each step of the gate summary's item 1 within 400 words (the longest {max(steps)})", max(steps) <= 400)

print()
print(f"result: {'pass' if not failures else 'FAIL'} ({len(failures)} failed)")
for f in failures:
    print("  failed: " + f)
sys.exit(1 if failures else 0)
