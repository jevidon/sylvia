#!/usr/bin/env python3
"""Do the lines the review's owner-readability findings cite hold what they say, at the commit they read? (The fix of the
owner-readability findings of the review of the update of 24 October 2026, 26 October 2026; integration log section 32.)
The workflow relayed nine findings, OWN-DA-01 to OWN-DA-09 (../relayed-findings.md), and named caf75a84 as the commit
reviewed; their line numbers and quoted texts are those of 8082bdb6, the commit the same review's fidelity, accuracy and
completeness findings cite (OWN-DA-01 cites item 115 of the gate summary at line 714, where 8082bdb6 has it), so this
reads each cited line with `git show` at a commit (by default 8082bdb6) and reports whether it holds the text the
finding quotes or names. A citation is taken to hold when the text is on the cited line, or within three lines of it
(the line found is printed); a text the findings quote or name without a line number must be in the file at that commit
(NAMED). Where a finding quotes with an ellipsis, the part quoted on the cited line is checked.

It then checks the findings' claims about refs and other commits, read from the repository whatever commit the texts are
read at: m0-decisions at c72247a6, the 8 commits main lacks and the 1 it has that m0-decisions lacks (the merge
96bdc7e9), with the first and last commits' times and titles; DeviceTests under Spikes/G05-Recovery on m0-decisions and
not at 8082bdb6; the files those commits change, and the four that both branches changed since 044ed3cf; the session
log's rows 3a-3d on m0-decisions (the first six cells only: run, session, date, who, the commit built from, the devices;
the last two cells, the steps run and their results, are not read, as the first three fixes did not read them) and its
changed opening; phone B's iOS in the setup record there, and the 26.7 (23H24) the records at 8082bdb6 give; the Xcode
message of the recovery suite's first device attempt there, which the runbook's 1.5 now quotes, and the texts OWN-DA-03
quotes from that attempt's record; the commit that added DeviceTests; and the merge commit's date. OWN-DA-02's quotations
from the record of G0.2 step 1 on m0-decisions are a sitting's results: only that the record and its log exist is
checked, not what they say. OWN-DA-08's remark that `git branch` showed no "+" beside m0-sessions at the review's time is
not checked: at this fix's time this fix's own worktree has m0-sessions checked out. Read-only: it reads git objects and
refs and writes nothing.

    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/owner/commands/finding-lines.py <repository root> [<commit>]

Exit status 1 unless every cited line, named text and claim holds at the commit given. The gate checks beside this file
run it at this fix's head as its control, where the lines this fix or the first three changed no longer hold the cited
text, so it must fail.
"""
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
READ = sys.argv[2] if len(sys.argv) > 2 else "8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22"

RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
STAGE0 = "Docs/Stage0/README.md"
LOG = "Docs/Stage0/integration-log.md"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
ADR02 = "Docs/ADRs/0002-repository-build-and-ci.md"
CL = "Docs/Stage0/device-checklists/"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
DEVICEA = "Docs/Stage0/evidence/M0-DeviceA/README.md"
ASM = "Docs/Stage0/evidence/M0-DeviceA/assembly/"
INSTR = "Docs/Stage0/evidence/M0-DeviceA/instructions/"
REC = "Docs/Stage0/evidence/G05-Recovery/device/"
PKG = "xcodebuild test -scheme G05Recovery-Package"
# (finding, path, cited line, text the finding quotes or names on or near that line)
CITED = [
    ("OWN-DA-01", RUNBOOK, 163, "The orchestrating session switches this checkout to it, from `main` at `96bdc7e9`, once "
                                "this update is reviewed, between your sittings"),
    ("OWN-DA-01", RUNBOOK, 163, "if it still reads `main`"),
    ("OWN-DA-01", RUNBOOK, 163, "ask for it, or run `git checkout m0-sessions` there yourself"),
    ("OWN-DA-01", RUNBOOK, 163, "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"),
    ("OWN-DA-01", GATE, 16, "The orchestrating session switches the checkout to it, from `main` at `96bdc7e9`, once this "
                            "update is reviewed, between your sittings"),
    ("OWN-DA-01", GATE, 16, "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"),
    ("OWN-DA-01", CL + "G04-Audio.md", 11, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("OWN-DA-01", CL + "G05-Recovery.md", 11, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("OWN-DA-01", CL + "G05-AI.md", 7, "`m0-integrate` and `m0-decisions` are behind `main`"),
    ("OWN-DA-01", "CLAUDE.md", 5, "both are behind `main`"),
    ("OWN-DA-01", RUNBOOK, 8, "the sessions now build from `m0-sessions`"),
    ("OWN-DA-01", GATE, 128, "the branch the sessions build from, which holds your session records"),
    ("OWN-DA-01", "README.md", 49, "the device sessions use the branch `m0-sessions`"),
    ("OWN-DA-01", GATE, 714, "The orchestrating session reconciles the two branches with you before the checkout moves"),
    ("OWN-DA-01", RUNBOOK, 22, "| **B. iPhone 17 Pro** (iPhone18,1), iOS 26.7 (23H24), Developer Mode on |"),
    ("OWN-DA-01", RUNBOOK, 276, "on phone B's iOS 26.7"),
    ("OWN-DA-01", RUNBOOK, 946, "than phone B's 26.7"),
    ("OWN-DA-01", ADR01, 62, "iPhone 17 Pro (iPhone18,1), iOS 26.7 (23H24)"),
    ("OWN-DA-02", RUNBOOK, 6, "Nothing in this runbook has been run on a device."),
    ("OWN-DA-02", GATE, 10, "None of the gates' device or human steps has run"),
    ("OWN-DA-02", GATE, 718, "not one device or human step has run"),
    ("OWN-DA-02", GATE, 128, "Nothing ran on a device"),
    ("OWN-DA-02", SESSIONS, 7, "No device step has been run."),
    ("OWN-DA-02", GATE, 714, "messages record device runs"),
    ("OWN-DA-03", RUNBOOK, 257, PKG + " -destination"),
    ("OWN-DA-03", RUNBOOK, 267, PKG + " -configuration Release"),
    ("OWN-DA-03", RUNBOOK, 795, PKG + " -destination"),
    ("OWN-DA-03", RUNBOOK, 950, "the commands of 1.2 with A's `DEVICE_ID`"),
    ("OWN-DA-03", CL + "G05-Recovery.md", 27, PKG),
    ("OWN-DA-03", CL + "G05-Recovery.md", 49, PKG),
    ("OWN-DA-03", CL + "G05-Recovery.md", 106, PKG),
    ("OWN-DA-03", CL + "G05-Recovery.md", 118, PKG),
    ("OWN-DA-03", RUNBOOK, 76, "Whether `xcodebuild test` signs it for the phone is only known when Session 1 runs it."),
    ("OWN-DA-04", GATE, 22, "one line**, which is recorded in ADR-0001 as your check"),
    ("OWN-DA-04", RUNBOOK, 159, "your confirmation of that reading, as technical lead, is still to be recorded: one line"),
    ("OWN-DA-04", RUNBOOK, 1026, "What is left is your confirmation as technical lead, one line (run 1, step 7)."),
    ("OWN-DA-04", RUNBOOK, 1037, "one line, recorded in ADR-0001 as your check"),
    ("OWN-DA-04", ADR01, 3, "That 27A9275 is the non-beta release has not been checked against Apple's release notes"),
    ("OWN-DA-04", ADR01, 116, "read Apple's release notes for Xcode 27.1"),
    ("OWN-DA-04", ADR01, 116, "and record here whether 27A9275 is the release build"),
    ("OWN-DA-04", ADR01, 116, "with the page and the date read"),
    ("OWN-DA-04", ADR01, 116, "no agent has read them"),
    ("OWN-DA-04", RUNBOOK, 167, "leave those records to it until its branch is merged"),
    ("OWN-DA-04", GATE, 20, "leave those records to it until its branch is merged"),
    ("OWN-DA-05", SESSIONS, 40, "(1) `m0-decisions` checked out"),
    ("OWN-DA-05", SESSIONS, 40, "(2) `CLAUDE.md`'s milestone paragraph corrected on `m0-decisions`"),
    ("OWN-DA-05", SESSIONS, 40, "(3) only if you build from `main`: `m0-decisions` merged into it"),
    ("OWN-DA-05", SESSIONS, 40, "(base `m0-decisions`"),
    ("OWN-DA-05", SESSIONS, 40, "committed on `m0-decisions`"),
    ("OWN-DA-05", SESSIONS, 40, "(7) Apple's release notes for Xcode 27.1 read as technical lead and recorded in ADR-0001"),
    ("OWN-DA-05", SESSIONS, 49, "| 8 | 8 Device A, your iPhone 11 Pro (after Session 4) |"),
    ("OWN-DA-05", SESSIONS, 16, "rows 1, 8 and 12 still had the tasks"),
    ("OWN-DA-05", RUNBOOK, 105, "add one row per sitting to [`evidence/M0-runbook/sessions.md`]"),
    ("OWN-DA-05", GATE, 705, "109. **Asked of other owners, not done here**: the session log's rows 1 and 8"),
    ("OWN-DA-05", GATE, 711, "112. **What each part asked of the other.**"),
    ("OWN-DA-06", GATE, 5, "A run or an event (a CI run, Xcode's update) is dated by UTC, with its time where known, and "
                           "with the build Mac's date beside it wherever that differs"),
    ("OWN-DA-06", RUNBOOK, 8, "The same day pull request #6 merged `m0-decisions` into `main` (`96bdc7e9`)"),
    ("OWN-DA-06", RUNBOOK, 163, "It was made that day from `main` after pull request #6 (`96bdc7e9`)"),
    ("OWN-DA-06", RUNBOOK, 165, "pull request #6 merged `m0-decisions` into `main` on 24 October 2026 (`96bdc7e9`)"),
    ("OWN-DA-06", GATE, 10, "On 24 October 2026 pull request #6 made that merge (`96bdc7e9`)"),
    ("OWN-DA-06", GATE, 18, "by pull request #6 on 24 October 2026 (`96bdc7e9`)"),
    ("OWN-DA-06", GATE, 128, "- **Pull request #6, `m0-sessions`, and your decision on device A (24 October 2026).**"),
    ("OWN-DA-06", GATE, 460, "which pull request #6 made on 24 October 2026"),
    ("OWN-DA-06", GATE, 737, "pull request #6 merged `m0-decisions` into `main` on 24 October 2026 (`96bdc7e9`)"),
    ("OWN-DA-06", "README.md", 49, "which pull request #6 merged into main on 24 October 2026 (`96bdc7e9`)"),
    ("OWN-DA-06", RUNBOOK, 159, "read them again the same day"),
    ("OWN-DA-06", GATE, 22, "read them again the same day"),
    ("OWN-DA-07", RUNBOOK, 23, "whether iOS 27 supports the iPhone 13 mini was not checked"),
    ("OWN-DA-07", RUNBOOK, 23, "on the iOS 26.x it has"),
    ("OWN-DA-08", RUNBOOK, 167, "(`git checkout m0-sessions`, then `git merge <its branch>`, by you or by an agent you ask)"),
    ("OWN-DA-08", GATE, 20, "(by you, or by an agent you ask)"),
    ("OWN-DA-09", GATE, 303, "device A, the baseline, is your iPhone 13 mini"),
    ("OWN-DA-09", GATE, 303, "its owners change plan 19.1 and ADR-0001 with it"),
]
# Texts the findings quote or name without a line number: each must be in the file at the commit read.
NAMED = [
    ("OWN-DA-01", ASM + "checks/branch-state.log", "worktree /Users/jevidon/Git/sylvia-sessions"),
    ("OWN-DA-01", ASM + "checks/branch-state.log", "branch refs/heads/m0-decisions"),
    ("OWN-DA-01", ASM + "checks/branch-state.log", "m0-decisions behind main (an ancestor of it): no"),
    ("OWN-DA-01", ASM + "README.md", "## Seen at the assembly: the sessions' checkout on `m0-decisions`"),
    ("OWN-DA-01", LOG, "### 28.8 The assembly (26 October 2026)"),
    ("OWN-DA-03", ASM + "checks/branch-state.log", "Record the recovery suite device-host blocker"),
    ("OWN-DA-04", INSTR + "checks/apple-pages.log", "read: 2026-10-23T17:49:55Z"),
    ("OWN-DA-04", ASM + "README.md", "Its merge will conflict on ADR-0001's Status line"),
    ("OWN-DA-05", ASM + "README.md", "**Not applied.** The session log is the owner's record"),
    ("OWN-DA-06", STAGE0, "On 24 October 2026 pull request #6 merged `m0-decisions` into `main` (`96bdc7e9`)"),
    ("OWN-DA-06", ADR02, "on 23 October 2026 at 15:34 UTC (24 October, 04:34, on the build Mac's clock"),
    ("OWN-DA-09", DEVICEA, "plan D01's row: device A \"the baseline for small-screen layout on a device\", as 19.1 says "
                           "(it said \"the baseline device\")"),
]
TOLERANCE = 3


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def lines_at(commit, path):
    out = git("show", f"{commit}:{path}")
    return out.stdout.splitlines() if out.returncode == 0 else None


def text_at(commit, path):
    out = git("show", f"{commit}:{path}")
    return out.stdout if out.returncode == 0 else None


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
tip = "044ed3cf86db838c93cda7e2ca4829474b234ae5"
c722 = "c72247a69a374ce361834550b92689b4abab95ee"
reviewed = "8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22"
rev = git("rev-parse", "m0-decisions").stdout.strip()
claims.append(("OWN-DA-01", f"git rev-parse m0-decisions = {rev[:8]}", rev == c722))
ahead = git("rev-list", "--count", "main..m0-decisions").stdout.strip()
behind = git("rev-list", "main", "^m0-decisions").stdout.split()
claims.append(("OWN-DA-01", f"git rev-list --count main..m0-decisions = {ahead}; m0-decisions..main = {len(behind)} "
               f"({', '.join(b[:8] for b in behind)}), the merge of pull request #6",
               ahead == "8" and behind == ["96bdc7e996f99fcd2571ea983cc32a04076a5a07"]))
log8 = git("log", "--reverse", "--format=%h|%ad|%s", "--date=iso", f"{tip}..{c722}").stdout.splitlines()
first = log8[0].split("|") if log8 else ["", "", ""]
last = log8[-1].split("|") if log8 else ["", "", ""]
claims.append(("OWN-DA-01", f"the 8 commits after 044ed3cf run from {first[1]} ({first[2]}) to {last[1]} ({last[2]})",
               len(log8) == 8 and first[1].startswith("2026-10-26 06:12") and first[1].endswith("+1300")
               and first[2] == "Record the first physical iPhone Keychain test result"
               and last[2] == "Record setup checks and the audio device run in progress"))
tree_dec = git("ls-tree", "--name-only", "m0-decisions", "Spikes/G05-Recovery/").stdout.split()
tree_rev = git("ls-tree", "--name-only", reviewed, "Spikes/G05-Recovery/").stdout.split()
claims.append(("OWN-DA-01", "git ls-tree m0-decisions Spikes/G05-Recovery/ lists DeviceTests, which 8082bdb6 lacks",
               "Spikes/G05-Recovery/DeviceTests" in tree_dec and "Spikes/G05-Recovery/DeviceTests" not in tree_rev))
dec_files = set(git("diff", "--name-only", tip, c722).stdout.split())
for_owner = {SESSIONS, RUNBOOK, CL + "G05-Recovery.md", "Docs/Stage0/G02-Transfer.md", "Docs/Stage0/G05-AI.md",
             "Docs/Stage0/G05-Recovery.md"}
claims.append(("OWN-DA-01", "those commits change the session log, the runbook, the G0.5 recovery checklist and three "
               "reports (G0.2, G0.5 AI, G0.5 recovery)", for_owner <= dec_files
               and len([f for f in dec_files if f.startswith("Docs/Stage0/G0") and f.count("/") == 2]) == 3))
both = sorted(dec_files & set(git("diff", "--name-only", tip, reviewed).stdout.split()))
claims.append(("OWN-DA-01", f"both branches changed, since 044ed3cf, exactly these files: {', '.join(both)}",
               both == sorted([RUNBOOK, CL + "G05-Recovery.md", "Docs/Stage0/G02-Transfer.md",
                               "Docs/Stage0/G05-Recovery.md"])))
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
claims.append(("OWN-DA-01", "the session log on m0-decisions has rows 3a-3d, Session 1's 1.1, 1.2 and 1.3, the first "
               "built from 96bdc7e9", [r[0] for r in rows] == ["3a", "3b", "3c", "3d"]
               and rows[0][1].startswith("1 ") and "1.1" in rows[0][1] and "96bdc7e9" in rows[0][4]
               and any("1.2" in r[1] for r in rows) and any("1.3" in r[1] for r in rows)))
opening = (lines_at(c722, SESSIONS) or [""] * 7)[6]
claims.append(("OWN-DA-05", "m0-decisions changed the session log's opening line (line 7 there no longer reads "
               "'No device step has been run.')", not opening.startswith("No device step has been run.")))
setup = text_at(c722, "Docs/Stage0/evidence/M0-runbook/2026-10-26-setup.txt") or ""
claims.append(("OWN-DA-01", "the setup record on m0-decisions gives phone B as iOS 27.0.1 (24A446)",
               "Phone B: iPhone 17 Pro (iPhone18,1), iOS 27.0.1 (24A446)" in setup))
g02 = "Docs/Stage0/evidence/G02-Transfer/device/01-keychain-class"
claims.append(("OWN-DA-02", "the record of G0.2 step 1 on m0-decisions and its log exist (what they say is a sitting's "
               "result, not read here)", text_at(c722, g02 + ".md") is not None and text_at(c722, g02 + ".log") is not None))
attempt = text_at(c722, REC + "step-1-tests.log") or ""
xcode = ("Tool-hosted testing is unavailable on device destinations. Select a host application for the test target, or "
         "use a simulator destination instead.")
claims.append(("OWN-DA-03", "step-1-tests.log on m0-decisions holds Xcode's message, which the runbook's 1.5 now quotes, "
               "after the package scheme's command", xcode in attempt and "-scheme G05Recovery-Package" in attempt))
results = text_at(c722, REC + "step-1-2-results.txt") or ""
claims.append(("OWN-DA-03", "step-1-2-results.txt on m0-decisions holds the three texts OWN-DA-03 quotes from it "
               "(the attempt's status, xcodebuild's exit status and the retry's commit)",
               "BLOCKED, no device tests executed" in results and "xcodebuild exit: 70" in results
               and "build commit 38f9604e" in results))
host = git("show", "--name-status", "--format=%s", "4be1a1a4").stdout.splitlines()
claims.append(("OWN-DA-03", f"4be1a1a4 ({host[0] if host else '?'}) adds Spikes/G05-Recovery/DeviceTests",
               bool(host) and host[0] == "Host the recovery suite in an iOS test app"
               and any(l.startswith("A\tSpikes/G05-Recovery/DeviceTests/") for l in host)))
ad = git("log", "-1", "--format=%ad", "--date=iso", "96bdc7e9").stdout.strip()
utc = git("log", "-1", "--format=%ad", "--date=iso-strict", "96bdc7e9").stdout.strip()
when = datetime.fromisoformat(utc).astimezone(timezone.utc) if utc else None
claims.append(("OWN-DA-06", f"git log -1 --format=%ad --date=iso 96bdc7e9 gives {ad}, which is "
               f"{when.strftime('%Y-%m-%d %H:%M UTC') if when else '?'}",
               ad == "2026-10-24 04:34:37 +1300" and when is not None and when.strftime("%Y-%m-%d %H:%M") == "2026-10-23 15:34"))
s1 = "\n".join((lines_at(READ, GATE) or [])[7:129])
claims.append(("OWN-DA-05", "the gate summary's Section 1 at the commit read names neither the session log's rows nor "
               "CLAUDE.md's toolchain line", "sessions.md" not in s1 and "toolchain line" not in s1
               and "rows 1 and 8" not in s1))
for finding, what, ok in claims:
    problems += 0 if ok else 1
    print(f"{'holds' if ok else 'NOT  '} {finding} claim: {what}")

print(f"result: {'every cited line, named text and claim holds' if problems == 0 else f'{problems} do not hold'} "
      f"({len(CITED)} citations, {moved} of them found within three lines of the line cited; {len(NAMED)} named texts; "
      f"{len(claims)} claims)")
sys.exit(1 if problems else 0)
