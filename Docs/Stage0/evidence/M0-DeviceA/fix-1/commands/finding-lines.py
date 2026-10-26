#!/usr/bin/env python3
"""Do the lines the review of the update of 24 October 2026 cites hold what it says, at the commit it read? (The fix of
its fidelity findings, 26 October 2026; integration log section 29.) The workflow relayed seven findings, FID-DA-01 to
FID-DA-07, each with the files and line numbers it cites, and the commit the review read, 8082bdb6. This reads each
cited line with `git show` at a commit (by default 8082bdb6) and reports whether it holds the text the finding quotes or
names, and checks the finding's claims about other commits: that the assembly's logs of the branches and of the
drop-in's paths name the time and the commit FID-DA-01 and FID-DA-03 give; that m0-decisions holds 8 commits after
044ed3cf, which add Spikes/G05-Recovery/DeviceTests and change the session log; that m0-sessions was made from 5aec2518
and 6cede84a made on it (FID-DA-07); and that integration log 28.1's reading of `git worktree list` came in fdbec8b8 with
no committed log of it (FID-DA-01). Read-only: it reads git objects and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line and every claim holds at the commit given. The gate checks of this fix run it at
the fix's own commit as its control, where the lines the fix changed no longer hold the cited text, so it must fail.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
REVIEWED = sys.argv[2] if len(sys.argv) > 2 else "8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22"

RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
STAGE0 = "Docs/Stage0/README.md"
README = "README.md"
INDEX = "Docs/ADRs/README.md"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
ADR13 = "Docs/ADRs/0013-design-language.md"
CL = "Docs/Stage0/device-checklists/"
DEVICEA = "Docs/Stage0/evidence/M0-DeviceA/README.md"
INSTR = "Docs/Stage0/evidence/M0-DeviceA/instructions/README.md"
# (finding, path, cited line, text the finding quotes or names on that line)
CITED = [
    ("FID-DA-01", GATE, 16, "1. **Check that `~/Git/sylvia-sessions` is on `m0-sessions`**"),
    ("FID-DA-01", GATE, 16, "The orchestrating session switches the checkout to it, from `main` at `96bdc7e9`"),
    ("FID-DA-01", RUNBOOK, 163, "The orchestrating session switches this checkout to it, from `main` at `96bdc7e9`"),
    ("FID-DA-01", RUNBOOK, 163, "if it still reads `main`, the switch is not made yet: ask for it, or run `git checkout "
                                "m0-sessions` there yourself"),
    ("FID-DA-01", LOG, 1570, "on `main` at `96bdc7e9`, as `git worktree list` showed it on 26 October 2026"),
    ("FID-DA-01", README, 49, "since then the M0 work and the device sessions use the branch `m0-sessions`"),
    ("FID-DA-01", RUNBOOK, 6, "- **Nothing in this runbook has been run on a device.**"),
    ("FID-DA-01", GATE, 714, "115. **Seen at the assembly, and not in these records**"),
    ("FID-DA-01", LOG, 1682, "#### 28.8.6 Seen at the assembly: the sessions' checkout on `m0-decisions`"),
    ("FID-DA-02", CL + "G02-Transfer.md", 199, "(24 October 2026: no A13 phone is at hand in M0."),
    ("FID-DA-02", CL + "G02-Transfer.md", 199, "5. Repeat once on the oldest supported iPhone if available"),
    ("FID-DA-02", RUNBOOK, 383, "which no device of M0 has (Section 1.1)"),
    ("FID-DA-02", CL + "G01-EPUB.md", 65, "which no device in M0 has"),
    ("FID-DA-02", CL + "G06-Design.md", 48, "whose A13 no device in M0 has"),
    ("FID-DA-02", RUNBOOK, 25, "your iPhone 11"),
    ("FID-DA-03", RUNBOOK, 210, "**Checked on 24 October 2026:**"),
    ("FID-DA-03", RUNBOOK, 210, "None of them changed between `9cdb0a02` and `6cede84a`"),
    ("FID-DA-03", RUNBOOK, 210, "ran that check again on the merged tree: none of those paths changed since `9cdb0a02`, "
                                "so 0.8 still needs nothing from you"),
    ("FID-DA-04", STAGE0, 5, "**Where M0 stands (24 October 2026).**"),
    ("FID-DA-04", STAGE0, 5, "an agent brought the owner's instructions up to date that day"),
    ("FID-DA-04", STAGE0, 5, "and on 26 October 2026 an assembly merged both into `m0-sessions`"),
    ("FID-DA-04", GATE, 128, "The same day an agent brought your instructions up to date"),
    ("FID-DA-04", RUNBOOK, 12, "on 24 October 2026 to record your decision"),
    ("FID-DA-04", GATE, 698, "Recorded on 24 October 2026, after pull request #6"),
    ("FID-DA-04", GATE, 704, "108. **The checks**"),
    ("FID-DA-04", INSTR, 13, "**Finished on 26 October 2026.**"),
    ("FID-DA-04", INDEX, 29, "then the iPhone 13 mini at the same 375 × 812 pt, on which G0.6's type roles are checked; "
                             "the iPad in M0) and PO-28 to PO-32, decided on 22 October 2026"),
    ("FID-DA-05", ADR01, 57, "ADR-0013 (it does not apply to G0.6's steps on device A, which depend on the screen)"),
    ("FID-DA-05", DEVICEA, 63, "ADR-0013 (it does not apply to G0.6's steps on A, which depend on the screen)"),
    ("FID-DA-05", RUNBOOK, 952, "depends on the phone's speed too, so on A it is the 13 mini's result"),
    ("FID-DA-05", ADR13, 290, "In M3, when the screens are built and reviewed on device: steps 1-3, 5-9, 12 and 16-19 on "
                              "device A"),
    ("FID-DA-05", ADR13, 136, "does not apply to these steps: they depend on the screen"),
    ("FID-DA-06", ADR01, 3, "has not been checked against Apple's release notes"),
    ("FID-DA-06", ADR01, 116, "no agent has read them"),
    ("FID-DA-06", INDEX, 17, "still awaits a check of Apple's release notes"),
    ("FID-DA-06", RUNBOOK, 159, "Apple's pages show that 27A9275 is Xcode 27.1's release build"),
    ("FID-DA-07", GATE, 128, "made `m0-sessions` from that commit (`6cede84a`)"),
    ("FID-DA-07", INSTR, 5, "made the branch `m0-sessions` from that commit (`6cede84a`)"),
    ("FID-DA-07", GATE, 700, "made `m0-sessions` from that commit (`6cede84a` points `CLAUDE.md` at it)"),
]


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def lines_at(commit, path):
    out = git("show", f"{commit}:{path}")
    return out.stdout.splitlines() if out.returncode == 0 else None


problems = 0
cache = {}
print(f"commit read: {git('rev-parse', REVIEWED).stdout.strip()}")
for finding, path, number, text in CITED:
    if path not in cache:
        cache[path] = lines_at(REVIEWED, path)
    lines = cache[path]
    line = lines[number - 1] if lines and 0 < number <= len(lines) else ""
    ok = text in line
    problems += 0 if ok else 1
    print(f"{'holds' if ok else 'NOT  '} {finding} {path}:{number}: {text[:110]}")

# The claims about other commits and files.
claims = []
branch_log = lines_at(REVIEWED, "Docs/Stage0/evidence/M0-DeviceA/assembly/checks/branch-state.log") or []
claims.append(("FID-DA-01", "the assembly's branch-state.log: read at 2026-10-25T17:46:45Z, the checkout on m0-decisions "
               "at c72247a6", any(l.startswith("date: 2026-10-25T17:46:45Z") for l in branch_log)
               and "HEAD c72247a69a374ce361834550b92689b4abab95ee" in branch_log
               and "branch refs/heads/m0-decisions" in branch_log))
tip = "044ed3cf86db838c93cda7e2ca4829474b234ae5"
count = git("rev-list", "--count", f"{tip}..c72247a69a374ce361834550b92689b4abab95ee").stdout.strip()
files = git("diff", "--name-only", tip, "c72247a69a374ce361834550b92689b4abab95ee").stdout.splitlines()
claims.append(("FID-DA-01", f"c72247a6 is 8 commits past 044ed3cf ({count}), adds Spikes/G05-Recovery/DeviceTests and "
               "changes the session log", count == "8"
               and any(f.startswith("Spikes/G05-Recovery/DeviceTests/") for f in files)
               and "Docs/Stage0/evidence/M0-runbook/sessions.md" in files))
added = git("log", "--format=%h", "-S", "as `git worktree list` showed it on 26 October 2026", "--", LOG).stdout.split()
logs = git("grep", "-l", "-F", "showed it on 26 October 2026", REVIEWED, "--", "Docs/Stage0/evidence").stdout.split()
claims.append(("FID-DA-01", f"28.1's reading of `git worktree list` came in fdbec8b8 (commits that added or removed it: "
               f"{' '.join(added) or 'none'}), and no evidence file holds it", added[-1:] == ["fdbec8b8"] and not logs))
dropin_log = lines_at(REVIEWED, "Docs/Stage0/evidence/M0-DeviceA/assembly/checks/dropin-paths.log") or []
claims.append(("FID-DA-03", "the assembly's dropin-paths.log checked 5e455f70",
               any(l.startswith("commit: 5e455f706c20d46711030a8b030c9dbf87dd4acd") for l in dropin_log)))
parent = git("rev-parse", "6cede84a^").stdout.strip()
claims.append(("FID-DA-07", f"6cede84a's parent is 5aec2518 ({parent[:8]}), so m0-sessions was made from 5aec2518",
               parent.startswith("5aec2518")))
for finding, what, ok in claims:
    problems += 0 if ok else 1
    print(f"{'holds' if ok else 'NOT  '} {finding} claim: {what}")
print(f"result: {'every cited line and claim holds' if problems == 0 else f'{problems} do not hold'} "
      f"({len(CITED)} citations, {len(claims)} claims)")
sys.exit(1 if problems else 0)
