#!/usr/bin/env python3
"""Do the lines the review's accuracy findings cite hold what they say, at the commit they read? (The fix of the accuracy
findings of the review of the update of 24 October 2026, 26 October 2026; integration log section 30.) The workflow
relayed six findings, ACC-01 to ACC-06 (../relayed-findings.md), and named d6315ad3 as the commit reviewed; their line
numbers and quoted texts are those of 8082bdb6, the commit the same review's fidelity findings cite, so this reads each
cited line with `git show` at a commit (by default 8082bdb6) and reports whether it holds the text the finding quotes or
names. A citation is taken to hold when the text is on the cited line, or within three lines of it (the line found is
printed: two of the findings cite the records' evidence README one line below the bullet they quote); a text the
findings quote or name without a line number must be in the file at that commit (NAMED). It then checks
the findings' claims about other commits and refs: the left-right count of main...m0-decisions, the 8 commits of
m0-decisions after 044ed3cf with their times and the two commits that add DeviceTests, the first six cells of the session
log's dated rows there (their dates and who ran them; the last two cells, the steps run and their results, are not read
here, as the first fix did not read them), and the G0.4 checklist's device line at 6cede84a. Read-only: it reads git
objects and refs and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/accuracy/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line and every claim holds at the commit given. The gate checks beside this file run it
at this fix's head as its control, where the lines this fix changed no longer hold the cited text, so it must fail.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
READ = sys.argv[2] if len(sys.argv) > 2 else "8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22"

RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
INDEX = "Docs/ADRs/README.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
ADR10 = "Docs/ADRs/0010-intake-handoff-and-wired-bundles.md"
ADR13 = "Docs/ADRs/0013-design-language.md"
CL = "Docs/Stage0/device-checklists/"
DEVICEA = "Docs/Stage0/evidence/M0-DeviceA/README.md"
ASM = "Docs/Stage0/evidence/M0-DeviceA/assembly/checks/"
# (finding, path, cited line, text the finding quotes or names on or near that line)
CITED = [
    ("ACC-01", RUNBOOK, 163, "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"),
    ("ACC-01", RUNBOOK, 163, "The orchestrating session switches this checkout to it, from `main` at `96bdc7e9`"),
    ("ACC-01", RUNBOOK, 163, "if it still reads `main`, the switch is not made yet: ask for it, or run `git checkout "
                             "m0-sessions` there yourself"),
    ("ACC-01", RUNBOOK, 6, "- **Nothing in this runbook has been run on a device.**"),
    ("ACC-01", RUNBOOK, 8, "and the sessions now build from `m0-sessions`"),
    ("ACC-01", GATE, 16, "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"),
    ("ACC-01", GATE, 16, "The orchestrating session switches the checkout to it, from `main` at `96bdc7e9`"),
    ("ACC-01", GATE, 4, "no device result is recorded yet"),
    ("ACC-01", GATE, 714, "115. **Seen at the assembly, and not in these records**"),
    ("ACC-01", GATE, 714, "do not describe that checkout as it now is"),
    ("ACC-01", LOG, 1682, "#### 28.8.6 Seen at the assembly: the sessions' checkout on `m0-decisions`"),
    ("ACC-01", LOG, 1682, "do not describe that checkout as it now is"),
    ("ACC-01", CL + "G04-Audio.md", 11, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("ACC-01", CL + "G05-AI.md", 7, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("ACC-01", CL + "G05-Recovery.md", 11, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("ACC-01", ASM + "branch-state.log", 5, "== the sessions' checkout, as git worktree list shows it"),
    ("ACC-01", ASM + "branch-state.log", 6, "worktree /Users/jevidon/Git/sylvia-sessions"),
    ("ACC-01", ASM + "branch-state.log", 7, "HEAD c72247a69a374ce361834550b92689b4abab95ee"),
    ("ACC-01", ASM + "branch-state.log", 8, "branch refs/heads/m0-decisions"),
    ("ACC-01", ASM + "branch-state.log", 19, "m0-decisions behind main (an ancestor of it): no"),
    ("ACC-01", ASM + "branch-state.log", 19, "commits on m0-decisions that main lacks: 8"),
    ("ACC-01", ASM + "gate-checks.log", 103, "m0-decisions: c72247a69a374ce361834550b92689b4abab95ee; behind main: NO"),
    ("ACC-02", CL + "G02-Transfer.md", 199, "5. Repeat once on the oldest supported iPhone if available"),
    ("ACC-02", CL + "G02-Transfer.md", 199, "no A13 phone is at hand in M0"),
    ("ACC-02", CL + "G01-EPUB.md", 65, "which no device in M0 has"),
    ("ACC-02", RUNBOOK, 383, "which no device of M0 has"),
    ("ACC-02", CL + "G06-Design.md", 48, "whose A13 no device in M0 has"),
    ("ACC-02", CL + "G05-AI.md", 40, "the phone on hand besides the iPhone 17 Pro is device A"),
    ("ACC-02", RUNBOOK, 23, "it can be phone D"),
    ("ACC-02", RUNBOOK, 25, "your iPhone 11 will do if it can place a call"),
    ("ACC-03", ADR01, 57, "ADR-0013 (it does not apply to G0.6's steps on device A, which depend on the screen)"),
    ("ACC-03", DEVICEA, 63, "ADR-0013 (it does not apply to G0.6's steps on A, which depend on the screen)"),
    ("ACC-03", ADR13, 290, "steps 1-3, 5-9, 12 and 16-19 on device A"),
    ("ACC-03", RUNBOOK, 952, "depends on the phone's speed too, so on A it is the 13 mini's result"),
    ("ACC-04", CL + "G03-Intake.md", 7, "the share extension's memory figures, memory limit and times on it (steps 14-16)"),
    ("ACC-04", CL + "G03-Intake.md", 7, "repeat steps 6-32 on device A in M2"),
    ("ACC-04", CL + "G03-Intake.md", 21, "Record also the time from \"Received by Sylvia\" to the harness's scan line with "
                                         "`accepted=1`"),
    ("ACC-04", CL + "G03-Intake.md", 48, "Record the elapsed time and the free space before and after."),
    ("ACC-04", DEVICEA, 62, "G0.3's repeats (steps 14-16)"),
    ("ACC-04", RUNBOOK, 952, "G0.3's share-extension memory, memory limit and times (steps 14-16)"),
    ("ACC-04", ADR10, 139, "the memory limit and peak measured on device A are the iPhone 13 mini's"),
    ("ACC-05", RUNBOOK, 1127, "| 1, 3, 15 and 17 on A |"),
    ("ACC-05", RUNBOOK, 1127, "(the checklist asked for them \"when one is available\", and since 24 October 2026 asks "
                              "for them on device A)"),
    ("ACC-05", CL + "G04-Audio.md", 5, "Repeat steps 1, 3, 8-13 and 15 on device A"),
    ("ACC-06", INDEX, 17, "whether 27A9275 is the non-beta release still awaits a check of Apple's release notes"),
    ("ACC-06", PLAN, 1159, "Pending: the technical lead's sign-off, with the check of Apple's release notes for Xcode "
                           "27.1 (ADR-0001) |"),
    ("ACC-06", RUNBOOK, 159, "Apple's pages show that 27A9275 is Xcode 27.1's release build"),
]
# Texts the findings quote or name without a line number: each must be in the file at the commit read (the line found is
# printed).
NAMED = [
    ("ACC-01", ASM + "branch-state.log", "date: 2026-10-25T17:46:45Z"),
    ("ACC-02", GATE, "your iPhone 11, whose state was not asked"),
    ("ACC-03", DEVICEA, "in M3, G0.6 step 12, whose stated limit is a stall of the phone of more than 150 ms"),
    ("ACC-03", CL + "G06-Design.md", "if the device stalls for more than 150 ms between a touch lift and the Button's "
                                     "action"),
    ("ACC-04", CL + "G03-Intake.md", "Record which happened and how long the provider took."),
    ("ACC-04", CL + "G03-Intake.md", "Record the time from tapping the extension to \"Received\""),
    ("ACC-04", CL + "G03-Intake.md", "record how long, and whether a progress indicator shows"),
    ("ACC-06", INDEX, "| ADR | Title | Status (24 October 2026) | Owner during Stage 0 |"),
    ("ACC-06", GATE, "7. **As technical lead, confirm that Xcode 27.1 (27A9275) is the release build: one line**"),
]
TOLERANCE = 3


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def lines_at(commit, path):
    out = git("show", f"{commit}:{path}")
    return out.stdout.splitlines() if out.returncode == 0 else None


problems = 0
moved = 0
cache = {}
print(f"commit read: {git('rev-parse', READ).stdout.strip()}")
for finding, path, number, text in CITED:
    if path not in cache:
        cache[path] = lines_at(READ, path)
    lines = cache[path] or []
    near = [n for n in range(number - TOLERANCE, number + TOLERANCE + 1) if 0 < n <= len(lines) and text in lines[n - 1]]
    found = min(near, key=lambda n: abs(n - number)) if near else None
    problems += 0 if found else 1
    where = "" if found == number else (f" (found on line {found})" if found else "")
    print(f"{'holds' if found else 'NOT  '} {finding} {path}:{number}{where}: {text[:110]}")
    moved += 1 if found and found != number else 0
for finding, path, text in NAMED:
    if path not in cache:
        cache[path] = lines_at(READ, path)
    lines = cache[path] or []
    found = [n for n, line in enumerate(lines, 1) if text in line]
    problems += 0 if found else 1
    print(f"{'holds' if found else 'NOT  '} {finding} {path} (named, no line cited; found on line "
          f"{', '.join(map(str, found)) or 'none'}): {text[:110]}")

# The claims about refs and other commits.
claims = []
lr = git("rev-list", "--left-right", "--count", "main...m0-decisions").stdout.split()
heads = (git("rev-parse", "main").stdout.strip(), git("rev-parse", "m0-decisions").stdout.strip())
claims.append(("ACC-01", f"git rev-list --left-right --count main...m0-decisions gives '{' '.join(lr)}' (main "
               f"{heads[0][:8]}, m0-decisions {heads[1][:8]}): 1 8, m0-decisions not behind main",
               lr == ["1", "8"] and heads[1].startswith("c72247a6")
               and git("merge-base", "--is-ancestor", "m0-decisions", "main").returncode == 1))
tip = "044ed3cf86db838c93cda7e2ca4829474b234ae5"
c722 = "c72247a69a374ce361834550b92689b4abab95ee"
nz = git("log", "--reverse", "--format=%h %ad", "--date=iso", f"{tip}..{c722}").stdout.splitlines()
claims.append(("ACC-01", f"8404f342..c72247a6 are 8 commits after 044ed3cf, from {nz[0].split(' ', 1)[1] if nz else '?'} "
               f"to {nz[-1].split(' ', 1)[1] if nz else '?'} (NZDT, as the commits record it)",
               len(nz) == 8 and nz[0].startswith("8404f342") and nz[-1].startswith("c72247a6")
               and "06:12:41 +1300" in nz[0] and "06:33:13 +1300" in nz[-1]))
subjects = {line.split(" ", 1)[0]: line.split(" ", 1)[1] for line in
            git("log", "--format=%h %s", f"{tip}..{c722}").stdout.splitlines()}
files = git("diff", "--name-only", tip, c722).stdout.splitlines()
claims.append(("ACC-01", "38f9604e is 'Record the recovery suite device-host blocker' and 4be1a1a4 'Host the recovery "
               "suite in an iOS test app', and m0-decisions adds Spikes/G05-Recovery/DeviceTests",
               subjects.get("38f9604e") == "Record the recovery suite device-host blocker"
               and subjects.get("4be1a1a4") == "Host the recovery suite in an iOS test app"
               and any(f.startswith("Spikes/G05-Recovery/DeviceTests/") for f in files)))
session_log = lines_at(c722, "Docs/Stage0/evidence/M0-runbook/sessions.md") or []
rows = []
for line in session_log:
    if line.startswith("| 3"):
        cells = [c.strip() for c in line.strip()[1:-1].split("|")]
        if len(cells) >= 6 and cells[0] in ("3a", "3b", "3c", "3d"):
            rows.append(" | ".join(cells[:6]))
print("the session log on m0-decisions (c72247a6), rows 3a-3d, the first six cells only (run | session | date | who | "
      "commit | devices):")
for r in rows:
    print("   " + r)
claims.append(("ACC-01", "the session log on m0-decisions has rows 3a-3d, sittings on phone B (iPhone 17 Pro) from "
               "2026-10-25 17:12 UTC (the steps run and their results, the last two cells, not read here)",
               len(rows) == 4 and rows[0].split(" | ")[2] == "2026-10-25 17:12 UTC"
               and all("iPhone 17 Pro" in r.split(" | ")[5] for r in rows)))
g04 = (lines_at("6cede84a6f6ac610976b233d875e26dd89419dbd", CL + "G04-Audio.md") or [""] * 5)[4]
claims.append(("ACC-05", "at 6cede84a the G0.4 checklist's device line asks for steps 1, 3, 8-13 and 15 on the oldest "
               "supported iPhone, not 17", "Repeat steps 1, 3, 8-13 and 15 on the oldest supported iPhone" in g04
               and "17" not in g04.split("(ADR-0001).", 1)[1].split("*(22 October", 1)[0]))
for finding, what, ok in claims:
    problems += 0 if ok else 1
    print(f"{'holds' if ok else 'NOT  '} {finding} claim: {what}")
print(f"result: {'every cited line, named text and claim holds' if problems == 0 else f'{problems} do not hold'} "
      f"({len(CITED)} citations, {moved} of them found within three lines of the line cited; {len(NAMED)} named texts; "
      f"{len(claims)} claims)")
sys.exit(1 if problems else 0)
