#!/usr/bin/env python3
"""Do the lines the review's completeness findings cite hold what they say, at the commit they read? (The fix of the
completeness findings of the review of the update of 24 October 2026, 26 October 2026; integration log section 31.) The
workflow relayed nine findings, DA-01 to DA-09 (../relayed-findings.md), and named ec91f66a as the commit reviewed; their
line numbers and quoted texts are those of 8082bdb6, the commit the same review's fidelity and accuracy findings cite
("At 8082bdb6, m0-sessions still tells the owner otherwise", DA-01), so this reads each cited line with `git show` at a
commit (by default 8082bdb6) and reports whether it holds the text the finding quotes or names. A citation is taken to
hold when the text is on the cited line, or within three lines of it (the line found is printed); a text the findings
quote or name without a line number must be in the file at that commit (NAMED).

It then checks the findings' claims about refs and other commits: the sessions' checkout on m0-decisions at c72247a6
(`git for-each-ref`), the 8 commits of m0-decisions that main lacks with their times, the session log's rows 3a-3d there
(the first six cells only: run, session, date, who, the commit built from, the devices; the steps run and their results,
the last two cells, are not read here, as the first two fixes did not read them), the four files of DeviceTests and the
runbook's 1.2 commands on m0-decisions, and the drop-in and the lock harness's checks naming no DeviceTests. Two of the
findings' quotations are paraphrases, and are read as the text they paraphrase: DA-02 quotes integration log 28.8.6 as
"whose messages record device runs" (it reads "their messages record device runs"), and names plan 19.1 among the records
that give phone B's iOS 26.7 (23H24), where 19.1 gives "on iOS 26.7" without the build. Read-only: it reads git objects
and refs and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line, named text and claim holds at the commit given. The gate checks beside this file
run it at this fix's head as its control, where the lines this fix or the first two changed no longer hold the cited
text, so it must fail.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
READ = sys.argv[2] if len(sys.argv) > 2 else "8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22"

RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
STAGE0 = "Docs/Stage0/README.md"
LOG = "Docs/Stage0/integration-log.md"
INDEX = "Docs/ADRs/README.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
ADR13 = "Docs/ADRs/0013-design-language.md"
ADR14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
CL = "Docs/Stage0/device-checklists/"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
DEVICEA = "Docs/Stage0/evidence/M0-DeviceA/README.md"
ASM = "Docs/Stage0/evidence/M0-DeviceA/assembly/"
TESTS = "Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DurabilityTests.swift"
# (finding, path, cited line, text the finding quotes or names on or near that line)
CITED = [
    ("DA-01", RUNBOOK, 163, "The orchestrating session switches this checkout to it, from `main` at `96bdc7e9`"),
    ("DA-01", RUNBOOK, 163, "if it still reads `main`"),
    ("DA-01", RUNBOOK, 163, "run `git checkout m0-sessions` there yourself"),
    ("DA-01", RUNBOOK, 163, "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"),
    ("DA-01", GATE, 16, "The orchestrating session switches the checkout to it, from `main` at `96bdc7e9`"),
    ("DA-01", GATE, 16, "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"),
    ("DA-01", CL + "G04-Audio.md", 11, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("DA-01", CL + "G05-AI.md", 7, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("DA-01", CL + "G05-Recovery.md", 11, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("DA-01", LOG, 1570, "on `main` at `96bdc7e9`"),
    ("DA-01", "CLAUDE.md", 5, "both are behind `main`"),
    ("DA-01", GATE, 714, "115. **Seen at the assembly, and not in these records**"),
    ("DA-01", GATE, 714, "do not describe that checkout as it now is"),
    ("DA-01", RUNBOOK, 950, "Do: the commands of 1.2 with A's `DEVICE_ID`"),
    ("DA-02", GATE, 10, "None of the gates' device or human steps has run"),
    ("DA-02", GATE, 132, "no device step has run"),
    ("DA-02", GATE, 718, "not one device or human step has run"),
    ("DA-02", STAGE0, 5, "no device step has run, so every gate stays pending"),
    ("DA-02", RUNBOOK, 6, "Nothing in this runbook has been run on a device"),
    ("DA-02", GATE, 714, "whose messages record device runs"),
    ("DA-02", LOG, 1684, "their messages record device runs and the sessions' setup"),
    ("DA-02", RUNBOOK, 22, "| **B. iPhone 17 Pro** (iPhone18,1), iOS 26.7 (23H24), Developer Mode on |"),
    ("DA-02", ADR01, 62, "**Test devices.** Recorded for Stage 0: iPhone 17 Pro (iPhone18,1), iOS 26.7 (23H24)"),
    ("DA-02", PLAN, 900, "The current iPhone is an iPhone 17 Pro on iOS 26.7 (phone B in the runbook)"),
    ("DA-03", SESSIONS, 40, "(1) `m0-decisions` checked out"),
    ("DA-03", SESSIONS, 40, "(2) `CLAUDE.md`'s milestone paragraph corrected on `m0-decisions`"),
    ("DA-03", SESSIONS, 40, "(5) R4-01 and R4-02 asked of an agent (base `m0-decisions`"),
    ("DA-03", SESSIONS, 40, "merged into `m0-decisions`"),
    ("DA-03", SESSIONS, 40, "(6) after each sitting, its records and evidence committed on `m0-decisions`"),
    ("DA-03", SESSIONS, 40, "(7) Apple's release notes for Xcode 27.1 read as technical lead"),
    ("DA-03", SESSIONS, 49, "| 8 | 8 Device A, your iPhone 11 Pro (after Session 4) |"),
    ("DA-03", SESSIONS, 7, "No device step has been run."),
    ("DA-03", RUNBOOK, 105, "add one row per sitting to [`evidence/M0-runbook/sessions.md`]"),
    ("DA-03", RUNBOOK, 163, "1. `git branch --show-current` reads `m0-sessions`"),
    ("DA-03", GATE, 705, "109. **Asked of other owners, not done here**: the session log's rows 1 and 8"),
    ("DA-03", GATE, 711, "the session log's rows 1 and 8, which still name `m0-decisions` and your iPhone 11 Pro"),
    ("DA-04", INDEX, 17, "whether 27A9275 is the non-beta release still awaits a check of Apple's release notes"),
    ("DA-04", PLAN, 1159, "Pending: the technical lead's sign-off, with the check of Apple's release notes for Xcode "
                          "27.1 (ADR-0001)"),
    ("DA-04", ADR01, 3, "has not been checked against Apple's release notes"),
    ("DA-04", "CLAUDE.md", 16, "whether 27A9275 is the non-beta release awaits a check of Apple's release notes"),
    ("DA-04", GATE, 22, "7. **As technical lead, confirm that Xcode 27.1 (27A9275) is the release build: one line**"),
    ("DA-04", RUNBOOK, 159, "Apple's pages show that 27A9275 is Xcode 27.1's release build"),
    ("DA-05", ADR14, 247, "the request names `m0-decisions` as the agent's base and a branch of its own for the result, "
                          "which reaches the device sessions' build only when the product owner merges it into "
                          "`m0-decisions`"),
    ("DA-06", RUNBOOK, 918, "8.8 and 8.9 record what iOS does, not a speed or memory figure, and so does step 1 of 8.10"),
    ("DA-06", RUNBOOK, 1025, "(8.1-8.5, 8.8, 8.9 and step 1 of 8.10) are not affected"),
    ("DA-06", TESTS, 169, "func latency() throws {"),
    ("DA-06", TESTS, 173, "#expect(result.p95Ms <= 200)"),
    ("DA-06", CL + "G05-Recovery.md", 46, "1. Step 1's log already contains `capture save latency synchronous=FULL "
                                          "fullfsync=ON:"),
    ("DA-07", RUNBOOK, 210, "ran that check again on the merged tree"),
    ("DA-07", RUNBOOK, 210, "any output means 0.8 runs again"),
    ("DA-07", GATE, 714, "so runbook 0.8 would then run again"),
    ("DA-08", RUNBOOK, 952, "in G0.6 step 12, whether a stall of the phone of more than 150 ms makes a press toggle twice"),
    ("DA-08", DEVICEA, 61, "G0.6 step 12, whose stated limit is a stall of the phone of more than 150 ms"),
    ("DA-08", ADR13, 136, "does not apply to these steps: they depend on the screen"),
    ("DA-08", ADR13, 290, "steps 1-3, 5-9, 12 and 16-19 on device A"),
    ("DA-08", ADR13, 220, "more than 150 ms"),
    ("DA-09", GATE, 22, "which is recorded in ADR-0001 as your check"),
    ("DA-09", GATE, 22, "ADR-0001 records the same evidence on `m0-exit-prep`, until its merge into `m0-sessions`"),
    ("DA-09", GATE, 22, "if you do not confirm it, PO-35 comes back to you before any device result rests on it"),
    ("DA-09", RUNBOOK, 159, "your confirmation of that reading, as technical lead, is still to be recorded: one line "
                            "(run 1, step 7)"),
    ("DA-09", RUNBOOK, 167, "and leave those records to it until its branch is merged"),
]
# Texts the findings quote or name without a line number: each must be in the file at the commit read.
NAMED = [
    ("DA-01", ASM + "checks/branch-state.log", "m0-decisions behind main (an ancestor of it): no"),
    ("DA-01", ASM + "checks/gate-checks.log", "m0-decisions: c72247a69a374ce361834550b92689b4abab95ee; behind main: NO"),
    ("DA-01", LOG, "#### 28.8.6 Seen at the assembly: the sessions' checkout on `m0-decisions`"),
    ("DA-04", INDEX, "| ADR | Title | Status (24 October 2026) | Owner during Stage 0 |"),
    ("DA-06", CL + "G05-Recovery.md", "`Test run with 68 tests in 11 suites passed`"),
    ("DA-07", ASM + "checks/dropin-paths.log", "commit: 5e455f706c20d46711030a8b030c9dbf87dd4acd (m0-sessions)"),
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

# The claims about refs and other commits (read from the repository, whatever commit the texts are read at).
claims = []
tip = "044ed3cf86db838c93cda7e2ca4829474b234ae5"
c722 = "c72247a69a374ce361834550b92689b4abab95ee"
ref = git("for-each-ref", "--format=%(refname:short) %(objectname) %(worktreepath)", "refs/heads/m0-decisions").stdout
claims.append(("DA-01", f"git for-each-ref refs/heads/m0-decisions: {ref.strip()}",
               ref.split() == ["m0-decisions", c722, str(Path.home() / "Git" / "sylvia-sessions")]))
count = git("rev-list", "--count", "main..m0-decisions").stdout.strip()
times = git("log", "--reverse", "--format=%h %ad", "--date=iso", f"{tip}..{c722}").stdout.splitlines()
claims.append(("DA-01", f"git rev-list --count main..m0-decisions gives {count}; the commits after 044ed3cf run from "
               f"{times[0] if times else '?'} to {times[-1] if times else '?'} (NZDT, as the commits record it)",
               count == "8" and len(times) == 8 and times[0].startswith("8404f342") and times[-1].startswith("c72247a6")
               and "06:12:41 +1300" in times[0] and "06:33:13 +1300" in times[-1]
               and git("merge-base", "--is-ancestor", "m0-decisions", "main").returncode == 1))
rows = []
for line in lines_at(c722, SESSIONS) or []:
    if line.startswith("| 3"):
        cells = [c.strip() for c in line.strip()[1:-1].split("|")]
        if len(cells) >= 6 and cells[0] in ("3a", "3b", "3c", "3d"):
            rows.append(cells[:6])
print("the session log on m0-decisions (c72247a6), rows 3a-3d, the first six cells only (run | session | date | who | "
      "commit | devices):")
for r in rows:
    print("   " + " | ".join(r))
claims.append(("DA-01", "the session log on m0-decisions has rows 3a-3d, sittings on phone B (iPhone 17 Pro) on "
               "2026-10-25 UTC (the steps run and their results, the last two cells, not read here)",
               [r[0] for r in rows] == ["3a", "3b", "3c", "3d"] and all("iPhone 17 Pro" in r[5] for r in rows)
               and all(r[2].startswith("2026-10-25") for r in rows)))
claims.append(("DA-02", "those rows give phone B as iOS 27.0.1 (24A446)",
               bool(rows) and all("27.0.1 (24A446)" in r[5] for r in rows)))
added = git("diff", "--name-status", tip, c722, "--", "Spikes").stdout.split("\n")
want = {"A\tSpikes/G05-Recovery/DeviceTests/project.yml", "A\tSpikes/G05-Recovery/DeviceTests/App/TestHost.swift",
        "A\tSpikes/G05-Recovery/DeviceTests/Support/Bundle+Module.swift",
        "A\tSpikes/G05-Recovery/DeviceTests/Package.resolved"}
claims.append(("DA-01", "under Spikes, m0-decisions adds exactly DeviceTests's project.yml, App/TestHost.swift, "
               "Support/Bundle+Module.swift and Package.resolved", set(a for a in added if a) == want))
rb = "\n".join(lines_at(c722, RUNBOOK) or [])
block12 = rb.split("**1.2 The persistence suite on the device", 1)[-1].split("**1.3 ", 1)[0]
claims.append(("DA-01", "on m0-decisions the runbook's 1.2 generates DeviceTests and runs its two xcodebuild commands "
               "with -project DeviceTests/G05RecoveryDeviceTests.xcodeproj -scheme G05RecoveryDeviceTests",
               "sylvia_generate Spikes/G05-Recovery/DeviceTests" in block12
               and block12.count("xcodebuild test -project DeviceTests/G05RecoveryDeviceTests.xcodeproj -scheme "
                                 "G05RecoveryDeviceTests") == 2 and "-scheme G05Recovery-Package" not in block12))
names = [line for f in ("Scripts/ci.d/71-g05-recovery.sh", "Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh")
         for line in (lines_at(READ, f) or []) if "DeviceTests" in line]
claims.append(("DA-07", "Scripts/ci.d/71-g05-recovery.sh and LockHarness/Scripts/harness-checks.sh name no DeviceTests "
               f"at the commit read ({len(names)} lines)", not names))
for finding, what, ok in claims:
    problems += 0 if ok else 1
    print(f"{'holds' if ok else 'NOT  '} {finding} claim: {what}")

print(f"result: {'every cited line, named text and claim holds' if problems == 0 else f'{problems} do not hold'} "
      f"({len(CITED)} citations, {moved} of them found within three lines of the line cited; {len(NAMED)} named texts; "
      f"{len(claims)} claims)")
sys.exit(1 if problems else 0)
