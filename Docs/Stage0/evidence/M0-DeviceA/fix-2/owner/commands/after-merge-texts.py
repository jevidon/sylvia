#!/usr/bin/env python3
"""The texts the merge of m0-decisions into m0-sessions, and the switch of the sessions' checkout that comes with it,
make false (the fix of the owner-readability findings of the review of the update's four fixes, 26 October 2026;
integration log section 33; finding OWN-DA-10). Since this fix, the runbook's 0.3, step 1, and the gate summary's item
1, step 1, make three things one step between two of the product owner's sittings: that merge, the update of the texts
it makes false, and the switch; and the switch waits until this check passes on m0-sessions after the merge and the
update. ../after-the-merge.md lists the same texts, by the same ids, with what each is to say then.

Each item is a live text of m0-sessions as this fix left it (an exact, case-sensitive part of it, read with the file's
lines joined, so that a hard-wrapped checklist reads like a one-line paragraph), with its kind:
  merge     false once the merge is made (it says what holds until then);
  switch    false once the checkout is on m0-sessions;
  results   false once the merge brings the sittings' records (it says that no device result is recorded here, or
            that a step has not run, where the merged records record one);
  settle    false once phone B's build is settled with the owner, in the same step;
  rows      true until the session log's rows 1 and 8 take their new text (../session-log-rows.md), false after: on a
            tree whose log still has the old row 8, it must be there; on one with the new row 8, it must be gone;
  owner     a text the owner, or the orchestrating session at the owner's request, changes (CLAUDE.md): reported, not
            judged.
A text kept word for word in a dated note that records what a text said is not a live text, if it is quoted: a match
with a double quotation mark in the two characters before it is not counted (a note that gives the old text in other
words, as the records' notes do, does not match it).

    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-2/owner/commands/after-merge-texts.py <tree root>

The tree holds the merge when it has the files m0-decisions added after 044ed3cf that mark it
(Spikes/G05-Recovery/DeviceTests/project.yml and Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log). On a tree
that does not hold it (this branch until the merge), every item is reported, present or gone, and nothing is judged:
exit 0. On a tree that holds it, exit 1 if any merge, switch, results or settle item is still present, or a rows item
does not match the log. Read-only; standard library only. The gate checks beside this file run it on this fix's head
and, as its control, on the merge of m0-decisions into it, computed with git merge-tree and not made, where every merge,
switch, results and settle item but those the merge itself replaces must be reported.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
RB = "Docs/Stage0/M0-device-runbook.md"
GT = "Docs/Stage0/M0-gate.md"
S0 = "Docs/Stage0/README.md"
CL = "Docs/Stage0/device-checklists/"
LOG = "Docs/Stage0/evidence/M0-runbook/sessions.md"
MARKERS = ("Spikes/G05-Recovery/DeviceTests/project.yml", "Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log")
QUOTED = re.compile(r"[\"“]")
OLD_ROW8 = "| 8 | 8 Device A, your iPhone 11 Pro (after Session 4) |"

# (id, path, kind, the text)
ITEMS = [
    ("rb-header", RB, "results", "- **No device result is recorded on this branch yet.** Your first sittings"),
    ("rb-header-merge", RB, "merge", "they reach this branch only when merged into it, before your checkout moves to it "
                                     "(0.3, step 1)"),
    ("rb-branch", RB, "merge", "they are merged into `m0-sessions` before your checkout moves to it, and until it moves "
                               "each sitting builds from the branch the checkout is on and commits its records there"),
    ("rb-row-b", RB, "settle", "which build these records give for phone B is settled with you when `m0-decisions` is "
                               "merged into `m0-sessions` (0.3, step 1)"),
    ("rb-1.5", RB, "merge", "this branch keeps the earlier commands until `m0-decisions` is merged into `m0-sessions` "
                            "(0.3, step 1)"),
    ("rb-1.2", RB, "merge", "This branch keeps the commands above until `m0-decisions` is merged into `m0-sessions` "
                            "(0.3, step 1)"),
    ("rb-s2-opening", RB, "merge", "On this branch the log's opening also still says that no device step has been run"),
    ("rb-s2-commit", RB, "switch", "Until your checkout is on `m0-sessions`, they are committed on the branch it is on, "
                                   "and reach `m0-sessions` with the merge that comes before the switch (0.3, step 1)."),
    ("rb-s2-rows", RB, "rows", "**The log's rows 1 and 8 still read as they did before 24 October 2026**"),
    ("rb-0.3-1-none", RB, "merge", "None of that is on `m0-sessions`, and nothing here reads or infers its results"),
    ("rb-0.3-1-checkout", RB, "switch", "**Until the switch, the runbook and `M0-gate.md` you read in your checkout are "
                                        "`m0-decisions`'s, from before 24 October 2026**"),
    ("rb-0.3-1-steps", RB, "switch", "Until the switch, steps 4 and 6 apply to the branch the checkout is on: note its "
                                     "head for each sitting"),
    ("rb-0.3-5-outside", RB, "switch", "Until then, while your checkout is on another branch (step 1), that merge is "
                                       "made outside `~/Git/sylvia-sessions`"),
    ("rb-0.3-5-reach", RB, "switch", "(once your checkout is on `m0-sessions`; before that, the work reaches your build "
                                     "with the switch: below)"),
    ("rb-0.3-5-own", RB, "switch", "(step 6; until the switch, on the branch your checkout is on, and merged into "
                                   "`m0-sessions` first: step 1)"),
    ("rb-0.8-head", RB, "switch", "Until your checkout is on `m0-sessions` (0.3, step 1), write `m0-sessions` in place "
                                  "of `HEAD`"),
    ("rb-0.8-merge", RB, "merge", "whose commits after `044ed3cf` are to be merged into `m0-sessions` before your "
                                  "checkout moves to it (0.3, step 1)"),
    ("rb-6.3", RB, "merge", "on this branch item 1's command, which item 4 runs again, is the one from before the change "
                            "1.2's note describes, until `m0-decisions` is merged into `m0-sessions`"),
    ("rb-8.10", RB, "merge", "(on this branch, until `m0-decisions` is merged into `m0-sessions`, the commands from "
                             "before the change 1.2's note of 26 October 2026 describes"),
    ("gt-state", GT, "results", "no sign-off of a plan 23.3 role and no device result is recorded here yet"),
    ("gt-opening", GT, "results", "No device or human step's result is recorded here yet (your sittings, on "
                                  "`m0-decisions`, unreviewed: item 1)"),
    ("gt-item1-rows", GT, "rows", "The session log's row 1 still lists these steps as they read before that day, and its "
                                  "row 8 still names your iPhone 11 Pro as device A"),
    ("gt-item1-step1-none", GT, "merge", "your first sittings were built and recorded there; none of that is on "
                                         "`m0-sessions` yet"),
    ("gt-item1-step1-tells", GT, "switch", "Until then the orchestrating session tells you what this update supersedes "
                                           "in your checkout's runbook and summary"),
    ("gt-item1-step1-steps", GT, "switch", "Until the switch, steps 4 and 6 apply to the branch the checkout is on; a "
                                           "sitting between the merge and the switch"),
    ("gt-item1-step5", GT, "switch", "Until your checkout is on `m0-sessions` (step 1), that merge is made outside it"),
    ("gt-item2", GT, "merge", "the merge of `m0-decisions` that comes before your checkout moves to `m0-sessions` adds "
                              "`DeviceTests` under them"),
    ("gt-item4-opening", GT, "merge", "and whose opening on this branch still says that no device step has been run"),
    ("gt-item4-phone-b", GT, "settle", "- **Phone B's iOS build, settled with you in the step that merges `m0-decisions` "
                                       "into `m0-sessions`**"),
    ("gt-s2", GT, "results", "No row is passed on a device: no device step's result is recorded on this branch (your "
                             "first sittings, recorded on `m0-decisions`, reach `m0-sessions` when merged into it"),
    ("gt-s51", GT, "results", "No result of a device step in it is recorded here yet (your first sittings, on phone B "
                              "from 25 October 2026 UTC, are recorded on `m0-decisions`, and reach these records when "
                              "merged into `m0-sessions`"),
    ("gt-s7", GT, "results", "the evidence is not: no device or human step's result is recorded here yet (your first "
                             "sittings, recorded on `m0-decisions` and not reviewed, reach these records when merged into "
                             "`m0-sessions`"),
    ("s0-merge", S0, "merge", "and are merged into `m0-sessions` before that checkout moves to it, between sittings"),
    ("s0-results", S0, "results", "no device step's result is recorded on this branch yet, so every gate stays pending"),
    ("readme", "README.md", "switch", "which the device sessions build from once the product owner's first sittings, "
                                      "recorded on `m0-decisions` from 25 October 2026, are merged into it"),
    ("cl-g05r-note", CL + "G05-Recovery.md", "merge", "- The device commands of steps 1, 2.4 and 4 below run the "
                                                      "package's own scheme, which Xcode refuses to run on a phone"),
    ("cl-g04-setup", CL + "G04-Audio.md", "merge", "which reach `m0-sessions` by a merge before your checkout moves to "
                                                   "it (runbook 0.3, step 1)"),
    ("cl-g05ai-setup", CL + "G05-AI.md", "merge", "which reach `m0-sessions` by a merge before your checkout moves to "
                                                  "it (runbook 0.3, step 1)"),
    ("cl-g05r-setup", CL + "G05-Recovery.md", "merge", "which reach `m0-sessions` by a merge before your checkout moves "
                                                       "to it (runbook 0.3, step 1)"),
    ("cl-g04-status", CL + "G04-Audio.md", "results", "Status of every step: **pending** (not run)."),
    ("cl-g05ai-none", CL + "G05-AI.md", "results", "None of them has been run."),
    ("cl-g05r-status", CL + "G05-Recovery.md", "results", "Status of every step: **pending** (not run)."),
    ("adr02", "Docs/ADRs/0002-repository-build-and-ci.md", "merge",
     "Its commits after `044ed3cf` are merged into `m0-sessions` before the sessions' checkout moves to it, between "
     "sittings, by the orchestrating session with the owner; until then that checkout stays on `m0-decisions`"),
    ("adr-index", "Docs/ADRs/README.md", "merge", "were recorded on `m0-decisions`, to be merged into `m0-sessions` "
                                                  "before the sessions' checkout moves to it"),
    ("plan-status", "Docs/Sylvia_v1_iOS_Implementation_Plan.md", "results",
     "Approving them approves no device result: every device and human step is still pending."),
    ("log-opening", LOG, "merge", "No device step has been run. One Mac-only step has had agents' runs"),
    ("claude-md", "CLAUDE.md", "owner", "Never build on `m0-integrate` or `m0-decisions`: both are behind `main`."),
]


def joined(path):
    p = ROOT / path
    return re.sub(r"\s*\n\s*", " ", p.read_text(encoding="utf-8")) if p.is_file() else None


def live_count(text, needle):
    n = 0
    for m in re.finditer(re.escape(needle), text):
        if not QUOTED.search(text[max(0, m.start() - 2):m.start()]):
            n += 1
    return n


merged = all((ROOT / m).is_file() for m in MARKERS)
log = joined(LOG) or ""
rows_new = OLD_ROW8 not in log
problems = []
cache = {}
print(f"tree: {ROOT}")
print(f"holds the merge of m0-decisions (both of {', '.join(MARKERS)} present): {'yes' if merged else 'no'}")
print(f"the session log's row 8: {'new text' if rows_new else 'old text (rows 1 and 8 not yet rewritten)'}")
for ident, path, kind, needle in ITEMS:
    if path not in cache:
        cache[path] = joined(path)
    text = cache[path]
    if text is None:
        print(f"  {ident:22} {kind:8} {path}: FILE MISSING")
        problems.append(ident)
        continue
    n = live_count(text, needle)
    state = "present" if n else "gone"
    verdict = ""
    if merged:
        if kind in ("merge", "switch", "results", "settle") and n:
            verdict = "  PROBLEM: still present after the merge"
            problems.append(ident)
        elif kind == "rows" and (bool(n) == rows_new):
            verdict = "  PROBLEM: " + ("still present though rows 1 and 8 have their new text" if n
                                       else "gone though rows 1 and 8 still have their old text")
            problems.append(ident)
        elif kind == "owner":
            verdict = "  (reported, not judged: the owner's text, M0-gate.md item 4)"
    print(f"  {ident:22} {kind:8} {state:8} ({n}) {path}{verdict}")
if not merged:
    print(f"result: not judged (the tree does not hold the merge; {sum(1 for i in ITEMS)} texts listed, "
          f"{sum(1 for i in ITEMS if live_count(cache.get(i[1]) or '', i[3]))} present)")
    sys.exit(0)
print(f"result: {'pass' if not problems else 'FAIL'} ({len(problems)} of {len(ITEMS)} not as the step requires"
      + (f": {' '.join(problems)}" if problems else "") + ")")
sys.exit(1 if problems else 0)
