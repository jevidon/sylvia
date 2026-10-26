#!/usr/bin/env python3
"""The fourth review of the M0 exit preparation (26 October 2026; integration log section 34): each line and fact its
one finding, SEC-ZIPGUARD-03, cites, read where it cites it.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/commands/finding-lines.py [<commit>]

The workflow relayed that the review read m0-exit-prep at fcbd6c89. Each citation is read with git show at <commit>
(fcbd6c89 when none is given): the text the finding quotes or names, at the line it cites. The finding gives ADR-0014's
rule 5 at line 39, section 5's marmelroy/Zip paragraph at line 147 and the list of what the check cannot see at lines
110-120; the check's dump_package at lines 913-925, the raw-text read of the manifest-input rule at line 935 and its
failure at lines 1498-1499; the gate summary's row 76 and item 113; and the first fix's observation-vsm.log. It says
that check_manifests reads a manifest only by the basename Package.swift (line 1401 here) and that ADR-0014 does not
name the route at all; both are read too. The review's own reproduction script is in its worktree, which this fix does
not read. The gate checks beside this file run it at the fix's last commit as its control, where the texts the fix
changes (the check's lines, ADR-0014's sections) are no longer as cited, so it must fail there. Standard library only;
read-only. Exits 1 if any citation is not as the finding gives it.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", ".."))
REVIEWED = "fcbd6c89aead7f5e67f0d1cd14f9869d718d8ffc"
ADR14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
CHECK = "Scripts/check-dependency-lock.py"
GATE = "Docs/Stage0/M0-gate.md"
OBS = "Docs/Stage0/evidence/M0-ExitPrep/fix-1/observation-vsm.log"

problems = 0


def git(*args):
    done = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True)
    return done.returncode, done.stdout


def lines_at(commit, path):
    code, out = git("show", f"{commit}:{path}")
    return out.decode("utf-8").split("\n") if code == 0 else []


def report(ok, message):
    global problems
    print(("ok      " if ok else "PROBLEM ") + "SEC-ZIPGUARD-03: " + message)
    if not ok:
        problems += 1


def at(commit, path, number, text):
    lines = lines_at(commit, path)
    got = lines[number - 1] if 0 < number <= len(lines) else ""
    report(text in got, f"{path}:{number} at {commit[:8]} has: {text[:110]}"
           + ("" if text in got else f" (it reads: {got[:110]!r})"))


def main():
    commit = sys.argv[1] if len(sys.argv) > 1 else REVIEWED
    code, full = git("rev-parse", "--verify", "--quiet", commit + "^{commit}")
    commit = full.decode().strip() if code == 0 else commit
    print(f"command: python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/commands/finding-lines.py {commit}")
    print(f"reading the cited lines at {commit} (the review read {REVIEWED[:8]}); HEAD is "
          f"{git('rev-parse', 'HEAD')[1].decode().strip()}")

    print()
    print("== ADR-0014: rule 5, section 5 and the list of what the check cannot see")
    at(commit, ADR14, 39, "5. **Product code comes only from what git tracks under `Apps/` and `Packages/`.**")
    at(commit, ADR14, 39, "a product `Package.swift`, which every build evaluates again in its own environment, reads "
                          "nothing but its own text")
    at(commit, ADR14, 147, "**One advisory applies to a pinned version: marmelroy/Zip 2.1.2, CVE-2023-39135**")
    at(commit, ADR14, 147, "CI also reads every value a product manifest gives as the build uses it")
    at(commit, ADR14, 147, "no `Package.swift` that reads anything but its own text")
    at(commit, ADR14, 110, "**What the check cannot see**, and so does not claim:")
    adr = lines_at(commit, ADR14)
    limits = adr[110:120]
    report(len(limits) == 10 and all(line.startswith("- ") for line in limits),
           f"{ADR14}:111-120 at {commit[:8]} are the ten items of that list")
    whole = "\n".join(adr)
    report("version-specific" not in whole and "Package@" not in whole,
           f"{ADR14} at {commit[:8]} names no version-specific manifest anywhere (neither 'version-specific' nor "
           f"'Package@')")

    print()
    print("== the check: what it evaluates and what its manifest-input rule reads")
    at(commit, CHECK, 913, "    def dump_package(self, rel):")
    at(commit, CHECK, 919, "r = subprocess.run(self.swift + ['package', '--package-path', pkg_dir, '--scratch-path', "
                           "tmp, 'dump-package'],")
    at(commit, CHECK, 925, "return _rebase(copy.deepcopy(_DUMP_CACHE[key]), [_ROOT_PLACEHOLDER], self.root)")
    at(commit, CHECK, 935, "text = open(self.path(rel), encoding='utf-8', errors='replace').read()")
    at(commit, CHECK, 1401, "manifests = [f for f in files if os.path.basename(f) in ('Package.swift', 'project.yml')")
    at(commit, CHECK, 1498, "for line, what in m.get('inputs', []):")
    at(commit, CHECK, 1499, "self.fail('manifest-input', f'{rel}:{line}'")
    check = "\n".join(lines_at(commit, CHECK))
    report("Package@" not in check and "version-specific" not in check,
           f"{CHECK} at {commit[:8]} names no version-specific manifest")

    print()
    print("== the gate summary's disclosure, and the first fix's observation")
    gate = lines_at(commit, GATE)
    row76 = next((line for line in gate if line.startswith("| 76 | ")), "")
    report("one more route of R4-01's kind is open, a version-specific manifest beside a product `Package.swift`, which "
           "the fix of the first review of the M0 exit preparation found and no finding names" in row76,
           f"{GATE} row 76 at {commit[:8]} names the route as open, that no finding names")
    item113 = next((line for line in gate if line.startswith("113. ")), "")
    report("SwiftPM evaluates a version-specific manifest (`Package@swift-6.4.swift`) instead of the `Package.swift` "
           "beside it" in item113 and "it is for ADR-0014's owner and the next review" in item113,
           f"{GATE} item 113 at {commit[:8]} gives the route to ADR-0014's owner and the next review")
    obs = "\n".join(lines_at(commit, OBS))
    report("  SYLVIA_EXTRA unset: exit 0; the SylviaDesign target's path: Sources/SylviaDesign" in obs
           and "  SYLVIA_EXTRA Sources/Elsewhere: exit 0; the SylviaDesign target's path: Sources/Elsewhere" in obs
           and "  dependency lock check: 0 failure(s), 0 warning(s)" in obs,
           f"{OBS} at {commit[:8]}: dump-package follows SYLVIA_EXTRA, and the check reports 0 failures")

    print()
    print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} citation(s) not as the finding gives them)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
