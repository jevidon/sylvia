#!/usr/bin/env python3
"""Do the owner's instructions describe the branches as git shows them? (The fix of the accuracy findings of the review
of the update of 24 October 2026, 26 October 2026; its finding ACC-01: the assembly's gate checks printed
"m0-decisions ...; behind main: NO" and passed while the runbook, the gate summary and three checklists called
m0-decisions behind main.) This judges the branch state instead of printing it. It reads, read-only, with git:
  - whether m0-decisions is behind main (an ancestor of it);
  - whether it is merged into the tree's commit (an ancestor of HEAD), and how many of its commits HEAD lacks;
  - the sessions' checkout, ~/Git/sylvia-sessions, as `git worktree list` shows it: its branch and head;
  - the session log as committed on the checkout's branch: how many dated rows are not an agent's (the owner's sittings;
    only the first four cells of each row are read: run, session, date, who);
and the live texts of the owner's instructions in the tree given: the runbook, the gate summary, the Stage 0 README, the
repository README and the eight device checklists. It fails when:
  behind    m0-decisions is not behind main, and a live text calls it behind main (a text inside a dated note that says
            what a text said, "said that ...", is the record of what it said, and is not judged);
  merged    m0-decisions is merged into HEAD, and a live text still says that its commits are not on m0-sessions; or it
            is not, and run 1's step 1 (the gate summary's item 1 and the runbook's 0.3) lacks the case for a checkout
            on another branch, which says to wait for that merge;
  checkout  the checkout is on another branch than m0-sessions, and run 1's step 1 lacks that case;
  sittings  the session log on the checkout's branch records a sitting of the owner's, and a live text says, without
            saying where (here, on this branch), that no device step has run or that no device result is recorded.
CLAUDE.md is not judged: no agent changes it on a workflow's request (the first fix's integration log 29.3). Its claims
are printed, as reported, not judged.
    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/accuracy/commands/branch-texts.py <repository root> [<tree root>]
The texts are read from the tree root (by default the repository root); the branches always from the repository. Run
on the trees of 8082bdb6 and d6315ad3 (git archive), the commits before this fix, it must fail: the gate checks beside
this file run those controls. Standard library only; read-only. Exit status 1 if any rule fails.
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
TREE = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else REPO
SESSIONS = str(Path.home() / "Git" / "sylvia-sessions")
LIVE = (["Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/M0-gate.md", "Docs/Stage0/README.md", "README.md"]
        + [f"Docs/Stage0/device-checklists/{n}" for n in (
            "G01-EPUB.md", "G01-PDF.md", "G02-Transfer.md", "G03-Intake.md", "G04-Audio.md", "G05-AI.md",
            "G05-Recovery.md", "G06-Design.md")])
# What marks the record of what a text said, in the 80 characters before a match: a verb of saying in the past, a
# report of what another text says ("says that"), or "no longer" (a text that no longer says it).
HISTORY = re.compile(r"\bsaid\b|\bsaying\b|\bsays that\b|\bgave\b|\bcalled\b|\bno longer\b|\bquot")
# A claim that m0-decisions is behind main, as the texts of 8082bdb6 and CLAUDE.md word it.
BEHIND = re.compile(r"`m0-decisions`[^.;()]{0,40}?\b(?:is|are)\s+behind\s+`main`"
                    r"|`m0-integrate`\s+(?:and|or)\s+`m0-decisions`[^.;()]{0,40}?\bbehind\s+`main`")
# A claim that m0-decisions's commits are not on m0-sessions (true only until the merge).
NOT_MERGED = re.compile(r"[Nn]one of (?:that|it) is on `m0-sessions`|which is not on `m0-sessions`")
# A claim that no device step has run, or no device result is recorded, without saying where.
NOTHING_RAN = re.compile(r"[Nn]othing in (?:it|this runbook|the runbook) has been run on a device"
                         r"|[Nn]o device step has (?:been )?run|[Nn]one of the gates' device or human steps has run"
                         r"|not one device or human step has run"
                         r"|no device (?:or human step's )?result is recorded yet"
                         r"|[Nn]o device step's result is recorded yet")
CASE = "If it reads another branch, do not switch it yourself"


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True)


def read(path, root=TREE):
    p = root / path
    return p.read_text(encoding="utf-8") if p.is_file() else ""


def live_hits(pattern, text):
    """Matches of pattern that are not inside the record of what a text said (the 80 characters before the match)."""
    out = []
    for m in pattern.finditer(text):
        before = text[max(0, m.start() - 80):m.start()]
        if not HISTORY.search(before):
            out.append(text[max(0, m.start() - 60):m.end() + 20].replace("\n", " "))
    return out


def owner_rows(branch):
    out = git("show", f"{branch}:Docs/Stage0/evidence/M0-runbook/sessions.md")
    if out.returncode != 0:
        return None
    rows = [l for l in out.stdout.splitlines() if l.startswith("| ")][2:]
    owner = []
    for r in rows:
        cells = [c.strip() for c in r.strip()[1:-1].split("|")]
        if len(cells) >= 4 and cells[2] and not cells[3].startswith("agent"):
            owner.append(f"{cells[0]} ({cells[2]}, {cells[3]})")
    return owner


failures = []
head = git("rev-parse", "HEAD").stdout.strip()
decisions = git("rev-parse", "m0-decisions").stdout.strip()
main = git("rev-parse", "main").stdout.strip()
behind = git("merge-base", "--is-ancestor", "m0-decisions", "main").returncode == 0
merged = git("merge-base", "--is-ancestor", "m0-decisions", "HEAD").returncode == 0
lacks = git("rev-list", "--count", "HEAD..m0-decisions").stdout.strip()
ahead = git("rev-list", "--count", "main..m0-decisions").stdout.strip()
entry, branch, checkout_head = [], "", ""
show = False
for line in git("worktree", "list", "--porcelain").stdout.splitlines():
    if line.startswith("worktree "):
        show = line[len("worktree "):] == SESSIONS
    elif show and line.startswith("branch "):
        branch = line[len("branch refs/heads/"):]
    elif show and line.startswith("HEAD "):
        checkout_head = line[len("HEAD "):]
sittings = owner_rows(branch) if branch else None
print(f"repository: {REPO}; texts read from: {TREE}")
print(f"HEAD: {head}; main: {main}; m0-decisions: {decisions}")
print(f"m0-decisions behind main (an ancestor of it): {'yes' if behind else 'no'}; commits on it that main lacks: {ahead}")
print(f"m0-decisions merged into HEAD (an ancestor of it): {'yes' if merged else 'no'}; commits on it that HEAD lacks: "
      f"{lacks}")
print(f"the sessions' checkout ({SESSIONS}): branch {branch or '(none: detached or not found)'}, head {checkout_head}")
print(f"the session log on that branch: "
      + ("not found" if sittings is None else f"{len(sittings)} dated rows not an agent's"
         + (f": {'; '.join(sittings)}" if sittings else "")))
print()

texts = {p: read(p) for p in LIVE}
missing = [p for p, t in texts.items() if not t]
if missing:
    failures.append("texts")
    print(f"FAIL texts: not found in the tree: {', '.join(missing)}")

# behind
hits = [] if behind else [f"{p}: ...{h}..." for p, t in texts.items() for h in live_hits(BEHIND, t)]
print(("FAIL" if hits else "PASS") + " behind: " + ("m0-decisions is behind main, so no text is judged" if behind else
      "m0-decisions is not behind main, and " + (f"{len(hits)} live texts call it behind main" if hits else
                                                  "no live text of the instructions calls it behind main")))
for h in hits:
    print("     " + h[:300])
if hits:
    failures.append("behind")

# merged / checkout: run 1's step 1 in both places.
gate = texts["Docs/Stage0/M0-gate.md"]
runbook = texts["Docs/Stage0/M0-device-runbook.md"]
item11 = next((l for l in gate.splitlines() if l.startswith("1. **Check that `~/Git/sylvia-sessions` is on")), "")
step031 = next((l for l in runbook.splitlines() if l.startswith("1. `git branch --show-current` reads `m0-sessions`")), "")
if merged:
    hits = [f"{p}: ...{h}..." for p, t in texts.items() for h in live_hits(NOT_MERGED, t)]
    print(("FAIL" if hits else "PASS") + " merged: m0-decisions is merged into HEAD, and "
          + (f"{len(hits)} live texts still say its commits are not on m0-sessions" if hits else
             "no live text says its commits are not on m0-sessions"))
    for h in hits:
        print("     " + h[:300])
    if hits:
        failures.append("merged")
else:
    lacking = [w for w, t in (("the gate summary's item 1, step 1", item11), ("the runbook's 0.3, step 1", step031))
               if CASE not in t]
    print(("FAIL" if lacking else "PASS") + f" merged: m0-decisions is not merged into HEAD ({lacks} commits HEAD lacks), "
          + (f"and {' and '.join(lacking)} lack the case for a checkout on another branch" if lacking else
             "and run 1's step 1, in the gate summary's item 1 and the runbook's 0.3, has the case for a checkout on "
             "another branch, which waits for that merge"))
    if lacking:
        failures.append("merged")
if branch != "m0-sessions":
    lacking = [w for w, t in (("the gate summary's item 1, step 1", item11), ("the runbook's 0.3, step 1", step031))
               if CASE not in t]
    print(("FAIL" if lacking else "PASS") + f" checkout: the checkout is on {branch or 'no branch'}, not m0-sessions, "
          + (f"and {' and '.join(lacking)} lack its case" if lacking else "and run 1's step 1 says what to do then"))
    if lacking:
        failures.append("checkout")
else:
    print("PASS checkout: the checkout is on m0-sessions")

# sittings
if sittings:
    hits = [f"{p}: ...{h}..." for p, t in texts.items() for h in live_hits(NOTHING_RAN, t)]
    print(("FAIL" if hits else "PASS") + f" sittings: the session log on {branch} records {len(sittings)} sittings of the "
          "owner's, and " + (f"{len(hits)} live texts say, without saying where, that no device step has run or no "
                             "device result is recorded" if hits else
                             "no live text says, without saying where, that no device step has run or that no device "
                             "result is recorded"))
    for h in hits:
        print("     " + h[:300])
    if hits:
        failures.append("sittings")
else:
    print("PASS sittings: the session log on the checkout's branch records no sitting of the owner's, so no text is "
          "judged")

# CLAUDE.md: reported, not judged.
claude = read("CLAUDE.md")
reported = live_hits(BEHIND, claude) if not behind else []
print("reported, not judged: CLAUDE.md " + (f"calls m0-decisions behind main: ...{reported[0][:200]}..." if reported
                                            else "has no such claim"))
print()
print(f"result: {'pass' if not failures else 'FAIL'} ({', '.join(failures) if failures else 'every rule as required'})")
sys.exit(1 if failures else 0)
