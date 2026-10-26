#!/usr/bin/env python3
"""The second review of the M0 exit preparation (26 October 2026; integration log section 32): each line and record its
four findings, EV-01 to EV-04, cite, read where they cite it.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/finding-lines.py [<commit>]

The workflow relayed that the review read m0-exit-prep at 83030fba; some of the findings' texts say "at 609ed492", the
assembly's last commit, and their line numbers in ADR-0014 are 609ed492's. Each citation is read with git show at
<commit> (83030fba when none is given), except those the findings place at 609ed492, which are read there, and the
records, which are read in the committed extraction (the .json.txt files, which no commit since 480d1757 changed). Each
check is the text the finding quotes or names at the line it cites. The gate checks beside this file run it at the fix's
last commit as its control, where the texts this fix dates or corrects are no longer as quoted, so it must fail there.
Standard library only; read-only. Exits 1 if any citation is not as the finding gives it.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", "..", ".."))
REVIEWED = "83030fba191735fa237c2cec014e590ee73a645c"
ASSEMBLY = "609ed49250da6a44984359bddc8219cdc6ad7c13"
HANDOVER = "480d1757"
ITEMS = "Docs/Stage0/evidence/M0-Integration/item-reviews"
ADR14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
LOG = "Docs/Stage0/integration-log.md"
GATE = "Docs/Stage0/M0-gate.md"

problems = 0


def git(*args):
    done = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True, text=True)
    return done.returncode, done.stdout


def lines_at(commit, path):
    code, out = git("show", f"{commit}:{path}")
    return out.split("\n") if code == 0 else []


def report(ok, finding, message):
    global problems
    print(("ok      " if ok else "PROBLEM ") + f"{finding}: {message}")
    if not ok:
        problems += 1


def line_has(finding, commit, path, number, text):
    lines = lines_at(commit, path)
    got = lines[number - 1] if 0 < number <= len(lines) else ""
    report(text in got, finding, f"{path}:{number} at {commit[:8]} has: {text[:110]}"
           + ("" if text in got else f" (it reads: {got[:110]!r})"))


def records(name):
    with open(os.path.join(ROOT, ITEMS, "extracted", name + ".json.txt"), "rb") as fh:
        return {r["label"]: r["result"] for r in json.loads(fh.read().decode("utf-8"))}


def main():
    commit = sys.argv[1] if len(sys.argv) > 1 else REVIEWED
    code, full = git("rev-parse", "--verify", "--quiet", commit + "^{commit}")
    commit = full.strip() if code == 0 else commit
    print(f"command: python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/finding-lines.py {commit}")
    print(f"reading the cited lines at {commit} (the review read {REVIEWED[:8]}), those placed at {ASSEMBLY[:8]} there; "
          f"HEAD is {git('rev-parse', 'HEAD')[1].strip()}")
    print()
    print("== EV-01: the deps item's record on ADR-0014, and the texts gone stale with it")
    note = ("The final round's minor findings R4-03 to R4-07 are not in ADR-0014, which names R4-01 and R4-02 only "
            "(searched by ID on this branch).")
    line_has("EV-01", ASSEMBLY, f"{ITEMS}/deps.md", 115, note)
    line_has("EV-01", commit, f"{ITEMS}/deps.md", 115, note)
    line_has("EV-01", commit, f"{ITEMS}/commands/item-reviews.py", 101,
             "\"The final round's minor findings R4-03 to R4-07 are not in ADR-0014, which names R4-01 and R4-02 only \"")
    line_has("EV-01", commit, f"{ITEMS}/commands/item-reviews.py", 102, "\"(searched by ID on this branch).\",")
    adr = lines_at(ASSEMBLY, ADR14)
    want = {"R4-03": [3, 88, 104, 214, 257], "R4-04": [3, 87, 104, 214, 257], "R4-05": [257], "R4-06": [257],
            "R4-07": [257]}
    for fid, numbers in want.items():
        got = [n for n, line in enumerate(adr, 1) if re.search(re.escape(fid) + r"(?![0-9])", line) and n != 7]
        report(got == numbers, "EV-01", f"{ADR14} at {ASSEMBLY[:8]}: {fid} on lines {got} outside the pointer line, "
               f"line 7 (the finding: {numbers})")
    now = lines_at(commit, ADR14)
    print("        at " + commit[:8] + ": " + "; ".join(
        f"{fid} on lines {[n for n, line in enumerate(now, 1) if re.search(re.escape(fid) + r'(?![0-9])', line) and 'item-reviews/' not in line]}"
        for fid in want))
    line_has("EV-01", commit, ADR14, 7, "and since that fix it gives all seven")
    line_has("EV-01", commit, "Docs/Stage0/evidence/M0-ExitPrep/assembly/check-item-reviews.log", 500,
             "ADR-0014 names R4-03, R4-04, R4-05, R4-06, R4-07")
    line_has("EV-01", commit, "Docs/Stage0/evidence/M0-ExitPrep/assembly/gate-checks.log", 436,
             "ADR-0014 names R4-03, R4-04, R4-05, R4-06, R4-07")
    line_has("EV-01", commit, LOG, 1690, "*ADR-0014's header line.*")
    line_has("EV-01", commit, LOG, 1690, "The item-reviews README's line on that pointer has a dated note.")
    line_has("EV-01", commit, f"{ITEMS}/README.md", 93, "*(Dated note, 26 October 2026: added at the assembly of the "
                                                         "M0 exit preparation")
    _, changed = git("diff", "--name-only", HANDOVER, ASSEMBLY, "--", ITEMS)
    changed = [x for x in changed.split("\n") if x]
    report(changed == [f"{ITEMS}/README.md"], "EV-01", f"from {HANDOVER} to {ASSEMBLY[:8]} the hand-over's folder "
           f"changed in: {', '.join(changed) or 'nothing'} (the finding: README.md alone)")
    _, recheck = git("show", f"{commit}:Docs/Stage0/evidence/M0-ExitPrep/assembly/commands/recheck-exit-prep.py")
    report("deps.md" not in recheck and "item-reviews/README.md" in recheck, "EV-01",
           "the assembly's recheck (its group N) reads the hand-over's README and not deps.md")
    line_has("EV-01", commit, f"{ITEMS}/README.md", 77, "the others appear only where those documents cite other "
                                                         "reviews' findings under the same IDs")
    line_has("EV-01", commit, f"{ITEMS}/README.md", 90, "A parallel agent's task of 24 October 2026 is to close them")
    line_has("EV-01", commit, f"{ITEMS}/deps.md", 114, "A parallel agent's task of 24 October 2026 is to close them")
    line_has("EV-01", commit, LOG, 1614, "none of which but those two was written into any report")

    print()
    print("== EV-02: the reason given for the 25 findings no later record names")
    line_has("EV-02", commit, GATE, 65, "25 of them named by no later record because the lists handed to two items' "
                                        "fixers were cut off")
    line_has("EV-02", commit, LOG, 1614, "5 left unresolved and 25 named by no later record, because the lists handed to "
                                         "the contracts and amendments items' fixers were cut off")
    line_has("EV-02", commit, f"{ITEMS}/README.md", 82, "The 25 findings no later record names are of those two items' "
                                                         "second lenses.")
    line_has("EV-02", commit, f"{ITEMS}/amendments.md", 142, "fix-2 names none of review-2b's L2-12 to L2-17")
    am = records("amendments")
    fix2 = json.dumps(am["amendments:fix-2"])
    named = [i for i in ("L2-12", "L2-13", "L2-14", "L2-15", "L2-16", "L2-17") if re.search(i + r"(?![0-9])", fix2)]
    cut = [w for w in ("cut off", "truncat", "partway") if w in fix2]
    report(not named and not cut, "EV-02", f"amendments fix-2 names {', '.join(named) or 'none'} of L2-12 to L2-17 and "
           f"says nothing of a list cut off ({', '.join(cut) or 'no such word'})")
    fix1 = am["amendments:fix-1"]
    l67 = [e for e in fix1.get("not_fixed", []) if e.get("id", "").startswith("L2-06")]
    report(bool(l67) and "cut off partway through L2-01" in l67[0].get("reason", ""), "EV-02",
           "amendments fix-1 left L2-06 and L2-07: \"the findings list was cut off partway through L2-01\"")
    gaps3 = " ".join(am["amendments:review-3"].get("gate_gaps", []))
    report("The brief truncates partway through R2-06" in gaps3, "EV-02",
           "amendments review-3, in its gate gaps: \"The brief truncates partway through R2-06\"")
    r206 = [p for p in am["amendments:review-3b"].get("previous_findings_status", []) if p.get("id") == "R2-06"]
    report(bool(r206) and "The brief was cut off after R2-06" in r206[0].get("note", ""), "EV-02",
           "amendments review-3b, in its status of R2-06: \"The brief was cut off after R2-06\"")
    co = records("contracts")
    r205 = [e for e in co["contracts:fix-2"].get("not_fixed", []) if e.get("id") == "R2-05"]
    report(bool(r205) and "outside this work's ownership" in r205[0].get("reason", ""), "EV-02",
           "contracts fix-2 declined R2-05: \"The move is outside this work's ownership\"")
    ai = records("minors-g05-ai")
    r704 = [e for e in ai["minors-g05-ai:fix-1"].get("not_fixed", []) if e.get("id", "").startswith("R7-04")]
    report(bool(r704) and r704[0].get("reason", "").startswith("pending-human"), "EV-02",
           "minors-g05-ai fix-1 left R7-04 pending-human (the owner's action)")
    cf2 = [e for e in co["contracts:fix-2"].get("not_fixed", []) if "after L2-R2-01" in e.get("id", "")]
    report(bool(cf2) and "cut off partway through L2-R2-01" in cf2[0].get("reason", ""), "EV-02",
           "contracts fix-2: \"The task's finding list was cut off partway through L2-R2-01\"")
    r110 = [e for e in co["contracts:fix-1"].get("fixed", []) if e.get("id") == "R1-10"]
    report(bool(r110) and "the detail was truncated" in r110[0].get("how", ""), "EV-02",
           "contracts fix-1 on R1-10: \"Reconstructed from the title and location because the detail was truncated\"")

    print()
    print("== EV-03: the check log's part for R8-04")
    line_has("EV-03", commit, f"{ITEMS}/README.md", 91, "The command is still there (the check log's part 6 notes it)")
    for path, number in (("Docs/Stage0/evidence/M0-ExitPrep/reviews/check-item-reviews.log", 463),
                         ("Docs/Stage0/evidence/M0-ExitPrep/assembly/check-item-reviews.log", 501)):
        line_has("EV-03", commit, path, number, "the cleanup command R8-04 names is still in G05-AI.md")
        line_has("EV-03", commit, path, 402, "== 7. What stayed open at the merge")

    print()
    print("== EV-04: where the records' commits are kept")
    line_has("EV-04", commit, f"{ITEMS}/README.md", 45, "on the item's branch, which still exists here")
    _, script = git("show", f"{commit}:{ITEMS}/commands/item-reviews.py")
    part5 = script.split("== 5. The merge", 1)[-1].split("== 6. ", 1)[0]
    report("head = git(\"rev-parse\", f\"refs/heads/{it.branch}\").stdout.strip()" in part5, "EV-04",
           "item-reviews.py's part 5 reads the branch with git's default check=True, so a missing branch stops it")
    print()
    print(f"result: {'pass' if not problems else 'FAIL'} ({problems} citation(s) not as the findings give them)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
