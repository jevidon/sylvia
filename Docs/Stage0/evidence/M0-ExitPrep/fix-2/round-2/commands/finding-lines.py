#!/usr/bin/env python3
"""The fifth review of the M0 exit preparation (26 October 2026; integration log section 35): each line and fact its
three findings, HON-EP-06 to HON-EP-08, cite, read where they cite it.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/round-2/commands/finding-lines.py [<commit>]

The workflow relayed that the review read m0-exit-prep at 941ac9a2. Most of the findings' line numbers are those of
941ac9a2 and of fcbd6c89 alike; ADR-0014's 245 and 258 and the gate summary's 709 (item 105) are those of fcbd6c89, the
commit the fourth review read, whose ADR-0014 and gate summary are three lines and one line shorter there, and the
findings name the gate checks of the first three fixes, not the fourth's (which 941ac9a2 adds, and which read the same).
So each citation is read with git show at <commit> (941ac9a2 when none is given) at the line where its text stands
there, and at the line the finding gives at fcbd6c89, the facts on the refs as the repository holds them (read-only),
and the phrasings of the third fix's sweep against the texts HON-EP-07 says it did not match. The gate checks beside
this file run it at the fix's last commit as its control, where the texts the fix changes are no longer as cited, so it
must fail there. Standard library only; read-only. Exits 1 if any citation is not as the findings give it.
"""
import datetime
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", "..", ".."))
REVIEWED = "941ac9a298730b7cf46a44faf1db1274166cb930"
EARLIER = "fcbd6c89aead7f5e67f0d1cd14f9869d718d8ffc"
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
README = "Docs/Stage0/README.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
INDEX = "Docs/ADRs/README.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
EXIT = "Docs/Stage0/evidence/M0-ExitPrep"
ZIP = f"{EXIT}/zipguard/README.md"
HON = f"{EXIT}/fix-1/round-3/commands/recheck-hon.py"
RECORD = f"{EXIT}/fix-1/round-3/correction-record.log"

problems = 0


def git(*args, ok=(0,)):
    done = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True)
    return done.returncode, done.stdout.decode("utf-8", errors="replace")


def lines_at(commit, path):
    code, out = git("show", f"{commit}:{path}")
    return out.split("\n") if code == 0 else []


def report(ok, finding, message):
    global problems
    print(("ok      " if ok else "PROBLEM ") + f"{finding}: " + message)
    if not ok:
        problems += 1


def at(commit, finding, path, number, text, earlier=None):
    """The text at <path>:<number> at <commit>; and, where the finding's number is that of fcbd6c89, at <earlier> too."""
    lines = lines_at(commit, path)
    got = lines[number - 1] if 0 < number <= len(lines) else ""
    report(text in got, finding, f"{path}:{number} at {commit[:8]} has: {text[:110]}"
           + ("" if text in got else f" (it reads: {got[:110]!r})"))
    if earlier:
        lines = lines_at(EARLIER, path)
        got = lines[earlier - 1] if 0 < earlier <= len(lines) else ""
        report(text in got, finding, f"{path}:{earlier} at {EARLIER[:8]}, the finding's number, has it too"
               + ("" if text in got else f" (it reads: {got[:110]!r})"))


def main():
    commit = sys.argv[1] if len(sys.argv) > 1 else REVIEWED
    code, full = git("rev-parse", "--verify", "--quiet", commit + "^{commit}")
    commit = full.strip() if code == 0 else commit
    print(f"command: python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/round-2/commands/finding-lines.py {commit}")
    print(f"reading the cited lines at {commit} (the review read {REVIEWED[:8]}); HEAD is "
          f"{git('rev-parse', 'HEAD')[1].strip()}")

    print()
    print("== HON-EP-06: the two branches' trees, m0-decisions behind main, no device step run")
    same = "The code is the same either way for now: `main` (`96bdc7e9`) and `m0-decisions` (`044ed3cf`) have the same tree."
    at(commit, "HON-EP-06", GATE, 476, same, earlier=476)
    at(commit, "HON-EP-06", LOG, 1687, "the code is the same either way, since `main` and `m0-decisions` have the same "
                                       "tree.", earlier=1687)
    at(commit, "HON-EP-06", LOG, 1719, "`main` and `origin/main` at `96bdc7e9`, and `m0-decisions` with the same tree.",
       earlier=1719)
    third = git("diff", "-U0", "415ae25b", "fcbd6c89", "--", GATE)[1]
    touched = any(re.match(r"^@@ -476(,\d+)? \+476(,\d+)? @@", l) for l in third.splitlines())
    report(touched and same in "\n".join(lines_at("fcbd6c89", GATE)), "HON-EP-06",
           "the third fix (415ae25b to fcbd6c89) changed line 476, Section 5.4's branch question, and left the same-tree "
           "sentence standing")
    asm = lines_at(commit, f"{EXIT}/assembly/gate-checks.log")
    report(len(asm) > 61 and asm[61].strip() == "m0-decisions: 044ed3cf86db838c93cda7e2ca4829474b234ae5; "
           "origin/m0-decisions: 044ed3cf86db838c93cda7e2ca4829474b234ae5; its tree is main's: yes"
           and any(l.startswith("start: 2026-10-25T17:01") for l in asm[:5]), "HON-EP-06",
           f"{EXIT}/assembly/gate-checks.log:62 reads m0-decisions at 044ed3cf, its tree main's: yes, in a run started "
           "at 17:01 UTC on 25 October 2026")
    for rel in ("fix-1", "fix-1/round-2", "fix-1/round-3", "fix-2"):
        log = lines_at(commit, f"{EXIT}/{rel}/gate-checks.log")
        report(len(log) > 61 and log[61].strip() == "m0-decisions: c72247a69a374ce361834550b92689b4abab95ee; "
               "origin/m0-decisions: 044ed3cf86db838c93cda7e2ca4829474b234ae5; its tree is main's: no", "HON-EP-06",
               f"{EXIT}/{rel}/gate-checks.log:62 reads m0-decisions at c72247a6, its tree not main's"
               + (" (the fourth fix's, which the finding does not name)" if rel == "fix-2" else ""))
    for number, text in ((1769, "Passed: the assembly's parts 1a-1g"), (1819, "Passed: the first fix's parts 1a-1g"),
                         (1873, "Passed: the second fix's parts 1a-1h")):
        at(commit, "HON-EP-06", LOG, number, text, earlier=number)
    log_lines = lines_at(commit, LOG)
    i344 = next((i for i, l in enumerate(log_lines, 1) if "Passed: the third fix's parts 1a-1l" in l), 0)
    report(i344 > 0, "HON-EP-06", f"{LOG}:{i344} at {commit[:8]}, 34.4, which the finding does not name, reports the "
                                  "third fix's parts 1a-1l as passing too")
    at(commit, "HON-EP-06", GATE, 16, "never to build on `m0-decisions`, which is behind it", earlier=16)
    at(commit, "HON-EP-06", RUNBOOK, 163, "says never to build on `m0-decisions`, which is behind `main`", earlier=163)
    at(commit, "HON-EP-06", "CLAUDE.md", 5, "Never build on `m0-integrate` or `m0-decisions`: both are behind `main`.",
       earlier=5)
    for number, text in ((4, "no device result is recorded yet"), (10, "None of the gates' device or human steps has run"),
                         (94, "nothing has been run on a phone"), (132, "No row is passed on a device: no device step "
                                                                        "has run.")):
        at(commit, "HON-EP-06", GATE, number, text, earlier=number)
    at(commit, "HON-EP-06", README, 5, "no device step has run, so every gate stays pending", earlier=5)
    records = [l for l in git("ls-tree", "-r", "--name-only", commit)[1].split("\n") if l.endswith(".md")]
    naming = [r for r in records if "c72247a6" in "\n".join(lines_at(commit, r))]
    report(not naming, "HON-EP-06", f"no Markdown record at {commit[:8]} names c72247a6 (it is named only in the gate "
                                    f"checks' logs){'' if not naming else ': ' + ', '.join(naming)}")
    tip = git("rev-parse", "m0-decisions")[1].strip()
    count = git("rev-list", "--count", "main..m0-decisions")[1].strip()
    trees = (git("rev-parse", "m0-decisions^{tree}")[1].strip(), git("rev-parse", "main^{tree}")[1].strip())
    report(tip.startswith("c72247a6") and count == "8" and trees[0].startswith("6e46ef59")
           and trees[1].startswith("576168b6"), "HON-EP-06",
           f"git rev-parse m0-decisions: {tip[:8]}; git rev-list --count main..m0-decisions: {count}; trees "
           f"{trees[0][:8]} and main's {trees[1][:8]}")
    stamps = git("log", "--format=%at", "main..m0-decisions")[1].split()
    span = (min(map(int, stamps)), max(map(int, stamps))) if stamps else (0, 0)
    fmt = [datetime.datetime.fromtimestamp(s, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M") for s in span]
    report(fmt == ["2026-10-25 17:12", "2026-10-25 17:33"], "HON-EP-06",
           f"the eight commits were made from {fmt[0]} to {fmt[1]} UTC")

    print()
    print("== HON-EP-07: the first fix's route called closed; item 105; integration log 28 and 28.4")
    gate_at = lines_at(commit, GATE)
    l64 = gate_at[63] if len(gate_at) > 63 else ""
    notes64 = re.findall(r"\*\((?:(?!\)\*).)*\)\*", l64)
    report(len(notes64) > 1 and "which the fix of that review closes, not reviewed" in notes64[1], "HON-EP-07",
           f"{GATE}:64 at {commit[:8]}, its second note, has: which the fix of that review closes, not reviewed")
    at(commit, "HON-EP-07", GATE, 128, "which the fix of that review closes, not reviewed", earlier=128)
    at(commit, "HON-EP-07", GATE, 491, "which the fix of that review closes the same day, not reviewed", earlier=491)
    at(commit, "HON-EP-07", INDEX, 30, "an agent's fix of that review closes it in the guard, not reviewed", earlier=30)
    at(commit, "HON-EP-07", A14, 248, "which an agent's fix closes, not reviewed", earlier=245)
    at(commit, "HON-EP-07", README, 5, "called R4-01 and R4-02 done and the route the first fix answered closed",
       earlier=5)
    hon = lines_at(commit, HON)
    block = "\n".join(hon[431:437])
    phrases = re.findall(r'r"((?:[^"\\]|\\.)*)"', block)
    rx = re.compile("|".join(phrases)) if phrases else None
    missed = [t for t in ("which the fix of that review closes, not reviewed", "an agent's fix closes, not reviewed",
                          "an agent's fix of that review closes it in the guard")
              if rx and not rx.search(t)]
    report(block.startswith("PHRASES = [") and len(phrases) == 21 and len(missed) == 3, "HON-EP-07",
           f"{HON}:432-437 at {commit[:8]} hold the sweep's {len(phrases)} phrasings, which match none of the three "
           "texts (the fix of that review closes, an agent's fix closes)")
    at(commit, "HON-EP-07", GATE, 710, "so that both routes, R4-03 and R4-04 and the other routes of the same kind fail "
                                       "`12-dependency-lock`", earlier=709)
    item105 = next((l for l in gate_at if l.startswith("105. ")), "")
    notes105 = re.findall(r"\*\((?:(?!\)\*).)*\)\*", item105)
    report(len(notes105) == 2 and "291 since the fix of its fourth review" in notes105[0]
           and "row 76 is failed again, and the counts are passed-host 11 and failed 5" in notes105[1], "HON-EP-07",
           f"item 105's dated notes at {commit[:8]} cover the counts and row 76 alone")
    item111 = next((l for l in gate_at if l.startswith("111. ")), "")
    item125 = next((l for l in gate_at if l.startswith("125. ")), "")
    report("passed the check before the change and fail it after" in item111 and "passed the check before the change "
           "and fail it after" in item125, "HON-EP-07", f"items 111 and 125 at {commit[:8]} each give routes of the same "
                                                        "kind that passed the change")
    at(commit, "HON-EP-07", LOG, 1561, "Agent-written and agent-checked; not reviewed: an agent review reads it next.",
       earlier=1561)
    at(commit, "HON-EP-07", LOG, 1598, "- **Review:** none yet; an agent review reads this change next.", earlier=1598)

    print()
    print("== HON-EP-08: 5aec2518 placed on main")
    at(commit, "HON-EP-08", A14, 3, "on a branch of its own from `main` at `5aec2518` (`m0-exit-zipguard`)", earlier=3)
    at(commit, "HON-EP-08", A14, 261, "on a branch of its own from `main` at `5aec2518`, `m0-exit-zipguard`",
       earlier=258)
    at(commit, "HON-EP-08", ZIP, 5, "on branch `m0-exit-zipguard` from `main` at `5aec2518`, by an agent.", earlier=5)
    code = git("merge-base", "--is-ancestor", "5aec2518", "main", ok=(0, 1))[0]
    report(code == 1, "HON-EP-08", f"git merge-base --is-ancestor 5aec2518 main exits {code}")
    record = "\n".join(lines_at(commit, RECORD))
    report("main is 96bdc7e996f99fcd2571ea983cc32a04076a5a07; it holds 5aec2518c90427a283d9c8195e11bb9ab23e5d12: no"
           in record, "HON-EP-08", f"{RECORD} at {commit[:8]}: main holds 5aec2518: no")
    at(commit, "HON-EP-08", GATE, 64, "from `5aec2518` (`main` after pull request #6, with `CLAUDE.md`'s correction",
       earlier=64)

    print()
    print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} citation(s) not as the findings give them)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
