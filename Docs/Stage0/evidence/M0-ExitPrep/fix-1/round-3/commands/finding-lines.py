#!/usr/bin/env python3
"""The third review of the M0 exit preparation (26 October 2026; integration log section 33): each line and fact its
five findings, HON-EP-01 to HON-EP-05, cite, read where they cite it.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands/finding-lines.py [<commit>]

The workflow relayed that the review read m0-exit-prep at 415ae25b. Each citation is read with git show at <commit>
(415ae25b when none is given): the text the finding quotes or names, at the line it cites. Up to line 500 of the gate
summary the findings' line numbers are 415ae25b's; past it several are not (:704 and :705 are its lines 707 and 708,
:733 is line 750, :749 is line 768), and ADR-0014's :257 is line 258 there, as the second fix found for its own review
at 83030fba: each such citation is read at the line where its text stands and printed with the line the finding gives.
The State line, which HON-EP-05 cites for "the M0 exit preparation of 24 October 2026", is read at 415ae25b, where it
does not hold that clause, and at 609ed492, the assembly's last commit, where it did. The relayed hash of the check the
review ran its reproductions with (its first eight digits, 3427e76f) is compared with Scripts/check-dependency-lock.py
at 6cd842d3, the Zip guard's fix, and at the commit read. The gate checks beside this file run it at the fix's last
commit as its control, where the texts this fix corrects are no longer as quoted, so it must fail there. Standard
library only; read-only. Exits 1 if any citation is not as the finding gives it.
"""
import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", "..", ".."))
REVIEWED = "415ae25b33f2b79f46e689b433392d261207c21f"
ASSEMBLY = "609ed49250da6a44984359bddc8219cdc6ad7c13"
ZIPFIX = "6cd842d3"
CORRECTION = "5aec2518c90427a283d9c8195e11bb9ab23e5d12"
PR6 = "96bdc7e996f99fcd2571ea983cc32a04076a5a07"
GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
ADR14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
LOG = "Docs/Stage0/integration-log.md"
README = "Docs/Stage0/README.md"
ZIPEV = "Docs/Stage0/evidence/M0-ExitPrep/zipguard"
CHECKER = "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
REVIEWS = "Docs/Stage0/evidence/M0-ExitPrep/reviews/README.md"
COMPARE = "Docs/Stage0/evidence/M0-Integration/item-reviews/commands/compare-gate-checks.py"

problems = 0


def git(*args):
    done = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True)
    return done.returncode, done.stdout


def lines_at(commit, path):
    code, out = git("show", f"{commit}:{path}")
    return out.decode("utf-8").split("\n") if code == 0 else []


def report(ok, finding, message):
    global problems
    print(("ok      " if ok else "PROBLEM ") + f"{finding}: {message}")
    if not ok:
        problems += 1


def at(finding, commit, path, number, text, cited=None):
    """The text at the line; `cited` is the line the finding gives, where it is not the line the text stands on."""
    lines = lines_at(commit, path)
    got = lines[number - 1] if 0 < number <= len(lines) else ""
    where = f"{path}:{number}" + (f" (the finding: :{cited})" if cited else "")
    report(text in got, finding, f"{where} at {commit[:8]} has: {text[:110]}"
           + ("" if text in got else f" (it reads: {got[:110]!r})"))


def main():
    commit = sys.argv[1] if len(sys.argv) > 1 else REVIEWED
    code, full = git("rev-parse", "--verify", "--quiet", commit + "^{commit}")
    commit = full.decode().strip() if code == 0 else commit
    print(f"command: python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands/finding-lines.py {commit}")
    print(f"reading the cited lines at {commit} (the review read {REVIEWED[:8]}); HEAD is "
          f"{git('rev-parse', 'HEAD')[1].decode().strip()}")

    print()
    print("== HON-EP-01: R4-01 and R4-02 recorded as closed and done, and row 76 as passed-host, before a review")
    at("HON-EP-01", commit, GATE, 64, "row 76, an M0 deliverable, stays failed until they are closed")
    at("HON-EP-01", commit, GATE, 64, "Closing them is an agent's change to the guard, which `12-dependency-lock` runs, "
                                      "with an agent review of it")
    at("HON-EP-01", commit, GATE, 64, "once the review of the change accepts it, merge that branch")
    at("HON-EP-01", commit, RUNBOOK, 996, "the M0 deliverable row 76 stays failed until they are closed")
    at("HON-EP-01", commit, RUNBOOK, 996, "Closing them is an agent's change to ADR-0014's CI guard (its section 3, "
                                          "checked by `12-dependency-lock`) with an agent review of it")
    at("HON-EP-01", commit, LOG, 1724, "round 4's verdict on ADR-0014, reject, stays on the record until that review says "
                                       "whether R4-01 and R4-02 are answered")
    at("HON-EP-01", commit, GATE, 250, "| 76 | Dependency lock: the CI guard that keeps marmelroy/Zip 2.1.2 "
                                       "(CVE-2023-39135) out of product code | passed-host |")
    at("HON-EP-01", commit, GATE, 250, "*(Failed until 24 October 2026, on round 4's verdict, reject, with R4-01 and R4-02 "
                                       "open: Section 6.1.")
    at("HON-EP-01", commit, GATE, 273, "Since 24 October 2026 row 76 is passed-host (ADR-0014's R4-01 and R4-02 closed by "
                                       "an agent, reviewed next), so passed-host 12 and failed 4.")
    at("HON-EP-01", commit, GATE, 495, "row 76 is closed by R4-01 and R4-02 above *(24 October 2026: so it is, by their "
                                       "fix, which an agent review reads next; row 76 is passed-host)*", cited=494)
    at("HON-EP-01", commit, GATE, 20, "*(24 October 2026: both done, by agents of the M0 exit preparation")
    at("HON-EP-01", commit, GATE, 20, "R4-01 and R4-02 closed, reviewed next")
    at("HON-EP-01", commit, GATE, 64, "*(24 October 2026: done by an agent at the M0 exit preparation")
    at("HON-EP-01", commit, GATE, 128, "ADR-0014's R4-01 and R4-02 closed in the guard, with R4-03 and R4-04 and the "
                                       "routes of the same kind, so row 76 is passed-host")
    at("HON-EP-01", commit, GATE, 708, "105. **R4-01 and R4-02 closed in the guard**", cited=705)
    at("HON-EP-01", commit, ADR14, 258, "*(Done, 24 October 2026, by an agent; an agent review reads it next.", cited=257)
    at("HON-EP-01", commit, RUNBOOK, 996, "*(24 October 2026: done by an agent, reviewed next,")
    at("HON-EP-01", commit, LOG, 1559, "## 28. ADR-0014's R4-01 and R4-02 closed, and `linkage.sh` under Xcode 27.1")
    at("HON-EP-01", commit, README, 5, "(on 24 October 2026 the first two done by an agent, reviewed next: integration "
                                       "log section 28")
    at("HON-EP-01", commit, README, 36, "*(24 October 2026: both closed by an agent's change, reviewed next,")
    at("HON-EP-01", commit, f"{ZIPEV}/README.md", 1, "# ADR-0014 review round 4: R4-01 and R4-02 closed in the Zip guard")
    at("HON-EP-01", commit, ADR14, 3, "R4-01 and R4-02 are closed in the guard**")
    at("HON-EP-01", commit, ADR14, 3, "That change answers the findings;")
    at("HON-EP-01", commit, ADR14, 3, "whether the findings are answered is the next review's to say.")
    at("HON-EP-01", commit, LOG, 1664, "| Zip guard | The gate summary's row 76: passed-host, its Source and its Evidence as "
                                       "worded | Applied as worded")
    at("HON-EP-01", commit, CHECKER, 152, '76: ("passed-host", adr_says(14, "R4-01 and R4-02 are closed in the guard")')
    at("HON-EP-01", commit, GATE, 49, "has the security sign-off accept the marmelroy/Zip advisory's residual risk only "
                                      "once R4-01 and R4-02 are closed")
    zipguard = git("show", f"{ZIPFIX}:Scripts/check-dependency-lock.py")[1]
    now = git("show", f"{commit}:Scripts/check-dependency-lock.py")[1]
    zh, nh = hashlib.sha256(zipguard).hexdigest(), hashlib.sha256(now).hexdigest()
    report(zh.startswith("3427e76f"), "HON-EP-01", f"Scripts/check-dependency-lock.py at {ZIPFIX}: SHA-256 {zh} (the "
           f"review's check, as relayed: 3427e76f...); at {commit[:8]}: {nh} (the first fix's change, ad709059, since)")
    log = lines_at(commit, f"{ZIPEV}/reproductions.log")
    routes = [x for x in log if x.startswith("--- route ") and x.endswith(": ok (passed before the fix, fails after it)")]
    report(len(routes) == 23, "HON-EP-01", f"{ZIPEV}/reproductions.log: {len(routes)} routes, each passing before the fix "
           "and failing after it (the review: all 23, line for line)")
    at("HON-EP-01", commit, f"{ZIPEV}/ci-2/12-dependency-lock.log", 337, "self-test: 278 mutations")
    at("HON-EP-01", commit, f"{ZIPEV}/ci-2/12-dependency-lock.log", 337, "119 of the 119 failure branches reached")

    print()
    print("== HON-EP-02: who made CLAUDE.md's correction, and at what request")
    at("HON-EP-02", commit, GATE, 750, "the M0 exit preparation was made on branches of its own from `5aec2518`",
       cited=733)
    at("HON-EP-02", commit, GATE, 750, "Besides `CLAUDE.md`, it changed `Scripts/check-dependency-lock.py` and "
                                       "`Scripts/ci.d/12-dependency-lock.sh`", cited=733)
    at("HON-EP-02", commit, GATE, 707, "No workflow's agent changed it (item 46).")
    at("HON-EP-02", commit, LOG, 1647, "which held `5aec2518` and nothing more")
    at("HON-EP-02", commit, REVIEWS, 18, "and `5aec2518` is the `CLAUDE.md` correction the gate summary asks for (Section "
                                         "1, item 1, step 2)")
    at("HON-EP-02", commit, COMPARE, 6, "hand-over starts from, 5aec2518, is the CLAUDE.md correction the gate summary "
                                        "asks for (Section 1, item 1, step 2)")
    at("HON-EP-02", commit, GATE, 17, "and commit the change on `m0-decisions`")
    parent = git("rev-parse", f"{CORRECTION}^")[1].decode().strip()
    files = git("diff", "--name-only", PR6, CORRECTION)[1].decode().split()
    report(parent == PR6 and files == ["CLAUDE.md"], "HON-EP-02", f"{CORRECTION[:8]}'s parent is {parent[:8]} (main after "
           f"pull request #6) and it changes {', '.join(files)} alone")

    print()
    print("== HON-EP-03: the owner's request, stated with no record but the commit message")
    at("HON-EP-03", commit, GATE, 17, "*(Done on 24 October 2026, at your request, by the orchestrating session: "
                                      "`5aec2518`")
    at("HON-EP-03", commit, GATE, 707, "on 24 October 2026 you asked the orchestrating session to correct it", cited=704)
    at("HON-EP-03", commit, LOG, 1647, "at the product owner's request on 24 October 2026")
    at("HON-EP-03", commit, README, 5, "*(corrected at the product owner's request on 24 October 2026, `5aec2518`")
    message = git("show", "--no-patch", "--format=%B", CORRECTION)[1].decode()
    report("The owner asked\nthe orchestrating session to make it on 24 October 2026" in message, "HON-EP-03",
           f"{CORRECTION[:8]}'s message says: The owner asked the orchestrating session to make it on 24 October 2026")
    for relay in ("Docs/Stage0/evidence/M0-ExitPrep/assembly/xcode-27.1-release.md",
                  "Docs/Stage0/evidence/M0-Decisions/followup/owner-answers-2026-10-23.md"):
        text = "\n".join(lines_at(commit, relay))
        report(bool(text) and "5aec2518" not in text, "HON-EP-03", f"{relay} is committed and names no 5aec2518")

    print()
    print("== HON-EP-04: CLAUDE.md's first statement, on main")
    at("HON-EP-04", commit, "CLAUDE.md", 5, "All M0 work is on `main`.")
    at("HON-EP-04", commit, GATE, 16, "says that all M0 work is on `main`")
    at("HON-EP-04", commit, GATE, 476, "says that all M0 work is on `main`")
    at("HON-EP-04", commit, GATE, 707, "The paragraph now says that all M0 work is on `main`", cited=704)
    at("HON-EP-04", commit, GATE, 476, "The correction itself is not yet on `main`")
    main = git("rev-parse", "main")[1].decode().strip()
    held = git("merge-base", "--is-ancestor", CORRECTION, "main")[0] == 0
    report(main == PR6 and not held, "HON-EP-04", f"main is {main[:8]} and does not hold {CORRECTION[:8]}: "
           f"{'so' if main == PR6 and not held else 'not so'}")

    print()
    print("== HON-EP-05: status lines dated 24 October 2026 reporting work of 26 October")
    at("HON-EP-05", commit, README, 5, "**Where M0 stands (24 October 2026).**")
    at("HON-EP-05", commit, GATE, 768, "nor has the M0 exit preparation of 24 October 2026 (sections 28-30)", cited=749)
    state = lines_at(commit, GATE)[3] if len(lines_at(commit, GATE)) > 3 else ""
    report(state.startswith("- **State:**") and "exit preparation of 24 October 2026" not in state, "HON-EP-05",
           f"{GATE}:4 at {commit[:8]}, the State line, does not name the M0 exit preparation of 24 October 2026 (it "
           "names the fix of the second review of the M0 exit preparation)")
    at("HON-EP-05", ASSEMBLY, GATE, 4, "nor has the M0 exit preparation of 24 October 2026 (Sections 6.2 and 8).")
    dates = git("log", "--format=%h %ad", "--date=iso", "6ce2c119..609ed492")[1].decode().split("\n")
    dates = [d for d in dates if d]
    report(len(dates) == 4 and all(" 2026-10-26 " in d and d.endswith("+1300") for d in dates), "HON-EP-05",
           "the assembly's commits after the merges, 83ed5ff3 to 609ed492, all dated 26 October 2026 on the build Mac's "
           "clock: " + "; ".join(dates))

    print()
    print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} citation(s) not as the findings give them)")
    sys.exit(1 if problems else 0)


main()
