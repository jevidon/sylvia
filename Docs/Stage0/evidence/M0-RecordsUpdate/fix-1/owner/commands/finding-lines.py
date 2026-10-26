#!/usr/bin/env python3
"""The review of m0-records-update, its owner-readability findings OWN-RU-01 to OWN-RU-08 (relayed 27 October 2026 on the
build Mac's clock; integration log section 44): does every line they cite hold the text they quote at 832a3636, the
commit the review read, and do their claims about other commits and branches hold? Read-only, with git (`git show
<commit>:<path>`, `git diff`, `git log`, `git rev-parse`, `git merge-base`); the findings as relayed are in
../relayed-findings.md. Where a finding cites a line loosely (one line off, or a range), the check reads the exact text
and says so. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/finding-lines.py
Prints one line per citation or claim and exits 1 if any does not hold.
"""
import subprocess
import sys

REVIEWED = "832a3636"
results = []


def git(*args, ok_codes=(0,)):
    out = subprocess.run(["git", *args], capture_output=True, text=True)
    if out.returncode not in ok_codes:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def lines_of(commit, path):
    return git("show", f"{commit}:{path}").splitlines()


def line(commit, path, number):
    lines = lines_of(commit, path)
    return lines[number - 1] if 0 < number <= len(lines) else ""


def holds(finding, label, ok, detail=""):
    results.append(ok)
    print(f"{'ok  ' if ok else 'FAIL'} {finding} {label}" + (f" ({detail})" if detail else ""))


def cites(finding, commit, path, number, *texts, absent=(), note=""):
    text = line(commit, path, number)
    missing = [t for t in texts if t not in text]
    present = [t for t in absent if t in text]
    holds(finding, f"{commit}:{path}:{number}" + (f" [{note}]" if note else ""), not missing and not present,
          "; ".join(["lacks: " + t[:90] for t in missing] + ["has: " + t[:90] for t in present]))


def cites_lines(finding, commit, path, first, last, *texts, note=""):
    """A text wrapped over lines first..last (the evidence READMEs are wrapped at 120 characters)."""
    joined = " ".join(line(commit, path, n).strip() for n in range(first, last + 1))
    missing = [t for t in texts if t not in joined]
    holds(finding, f"{commit}:{path}:{first}-{last}" + (f" [{note}]" if note else ""), not missing,
          "; ".join("lacks: " + t[:90] for t in missing))


def diff_files(a, b, *paths):
    return [l.split("|")[0].strip() for l in git("diff", "--stat", a, b, "--", *paths).splitlines() if "|" in l]


RB, GATE, LOG = "Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/M0-gate.md", "Docs/Stage0/integration-log.md"
EV = "Docs/Stage0/evidence/M0-RecordsUpdate/README.md"
PARA = "Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md"
ORI = "Docs/Stage0/evidence/M0-RecordsUpdate/commands/owner-records-intact.py"
print(f"reviewed commit: {git('rev-parse', REVIEWED).strip()}")
print(f"m0-decisions now: {git('rev-parse', 'm0-decisions').strip()} (read-only)")
print()

# OWN-RU-01
cites("OWN-RU-01", REVIEWED, RB, 210, "Record: commit the regenerated log on `m0-sessions` (0.3, step 6; until 24 October "
      "2026 this said `m0-decisions`); update the G0.2 row.")
cites("OWN-RU-01", "c72247a6", RB, 207, "commit the regenerated log on `m0-decisions` (0.3, step 6)")
setup = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-runbook/2026-10-26-setup.txt")
holds("OWN-RU-01", "the owner's setup record: 0.7's Keychain test not run",
      "The Keychain test itself has NOT run; this is not a pass for step 0.7" in setup)
cites("OWN-RU-01", REVIEWED, EV, 28, "restated everywhere the records give it")
cites("OWN-RU-01", REVIEWED, RB, 221, "committed on `m0-decisions` (0.3, step 6; from 24 to 26 October 2026 this said "
      "`m0-sessions`)")
log832 = git("show", f"{REVIEWED}:{LOG}")
s413 = log832[log832.find("### 41.3 "):log832.find("### 41.4 ")]
holds("OWN-RU-01", "integration log 41.3 lists the runbook places it rewrote, and not 0.7",
      "0.3 (steps 1-6 rewritten" in s413 and "0.7" not in s413)
wording = [c[:8] for c in git("log", "--format=%h", "-S", "commit the regenerated log on `m0-sessions`", "c72247a6.." +
                              REVIEWED, "--", RB).split()]
holds("OWN-RU-01", "the m0-sessions wording reached this branch with the merge 4c0fa815 (git log -S)",
      git("merge-base", "--is-ancestor", "1d5ac477", "4c0fa815", ok_codes=(0, 1)) == ""
      and "commit the regenerated log on `m0-sessions`" in git("show", f"4c0fa815:{RB}")
      and "commit the regenerated log on `m0-sessions`" not in git("show", f"cd27b60b:{RB}"), " ".join(wording))

# OWN-RU-02
cites("OWN-RU-02", REVIEWED, GATE, 466, "The same holds for the records and evidence of your sessions, committed on "
      "`m0-sessions` (Section 1, item 1, step 6). Not needed for the exit: until you say so, build from `m0-sessions`.")
cites("OWN-RU-02", "c72247a6", GATE, 459, "which you commit on `m0-decisions`", "until you say so, build from "
      "`m0-decisions`")
cites("OWN-RU-02", "c3adae68", GATE, 460, "which you commit on `m0-decisions`", "until you say so, build from "
      "`m0-decisions`")
cites("OWN-RU-02", REVIEWED, GATE, 839, "178. **The branch model, restated, and run 1**", "5.4")
cites("OWN-RU-02", REVIEWED, GATE, 482, "**The branch the sessions use: `m0-decisions`, as the runbook said, settled on "
      "26 October 2026.**")

# OWN-RU-03
cites_lines("OWN-RU-03", REVIEWED, EV, 53, 54, "once the sitting in progress is done and its records are committed on "
            "`m0-decisions`")
status = git("show", f"{REVIEWED}:Docs/Stage0/evidence/G04-Audio/device/step-01-status.txt")
holds("OWN-RU-03", "the owner's status file at c72247a6: RUNNING, full suite not complete",
      "RUNNING" in status and "Full suite not complete" in status
      and status == git("show", "c72247a6:Docs/Stage0/evidence/G04-Audio/device/step-01-status.txt"))
for branch in ("m0-device-fixes-ats", "m0-device-fixes-recovery"):
    holds("OWN-RU-03", f"{branch} is cut from c72247a6 (git merge-base)",
          git("merge-base", branch, "c72247a6").strip() == git("rev-parse", "c72247a6").strip())
ats = git("log", "--format=%h", "--reverse", "c72247a6..m0-device-fixes-ats").split()
holds("OWN-RU-03", "m0-device-fixes-ats holds 907538f5..0b0e1e65 (it has moved on since: listed)",
      len(ats) >= 3 and ats[0].startswith("907538f5") and any(c.startswith("0b0e1e65") for c in ats), " ".join(ats))
cites_lines("OWN-RU-03", REVIEWED, EV, 66, 71, "If it has moved on", "merge cleanly", "A conflict can come only where",
            "rerun this branch's checks")
cites_lines("OWN-RU-03", REVIEWED, EV, 72, 74, "**After the merge:**", "nothing is to be repeated",
            "no step of your sittings repeats (runbook 0.3, step 7), and 0.8 needs nothing (runbook 0.8)")
cites("OWN-RU-03", REVIEWED, ORI, 25, 'OWNER_HEAD = "c72247a69a374ce361834550b92689b4abab95ee"',
      note="cited as line 24, which holds BASE; OWNER_HEAD is on line 25")
cites("OWN-RU-03", REVIEWED, GATE, 10, "G0.4 step 1 still running")
cites("OWN-RU-03", REVIEWED, GATE, 47, "1.4's audio run started, its result not yet recorded")
cites("OWN-RU-03", REVIEWED, RB, 6, "1.4's audio run started, its result not yet recorded")
cites("OWN-RU-03", REVIEWED, "Docs/Stage0/G04-Audio.md", 6, "still all pending", "no result is claimed")
cites("OWN-RU-03", REVIEWED, "Docs/Stage0/device-checklists/G04-Audio.md", 3, "no result is claimed")
cites("OWN-RU-03", REVIEWED, RB, 212, "After each merge into `m0-decisions`, check again")

# OWN-RU-04
cites("OWN-RU-04", REVIEWED, "CLAUDE.md", 5, "Since 24 October 2026 the M0 work is on `m0-sessions`",
      "the product owner builds the device sessions from it",
      "Further M0 work goes on a branch of its own made from `m0-sessions`", "Never build on `m0-integrate` or "
      "`m0-decisions`")
holds("OWN-RU-04", "git diff 6cede84a 832a3636 -- CLAUDE.md prints nothing",
      git("diff", "6cede84a", REVIEWED, "--", "CLAUDE.md") == "")
owner_claude = git("show", "c72247a6:CLAUDE.md")
holds("OWN-RU-04", "c72247a6's CLAUDE.md names m0-integrate and gives no instruction against m0-decisions",
      "are combined on `m0-integrate`" in owner_claude and "Never build on" not in owner_claude
      and "m0-sessions" not in owner_claude)
cites_lines("OWN-RU-04", REVIEWED, EV, 46, 48, "**Left for the owner:** `CLAUDE.md`.", "the paragraph `6cede84a` wrote")
cites_lines("OWN-RU-04", REVIEWED, EV, 66, 68, "A conflict can come only where",
            "the gate reports, the checklists, the runbook, the gate summary or the ADRs", note="CLAUDE.md not named")
holds("OWN-RU-04", "the README's list of conflicts at 832a3636 does not name CLAUDE.md",
      "CLAUDE.md" not in " ".join(lines_of(REVIEWED, EV)[65:68]))
cites("OWN-RU-04", REVIEWED, EV, 72, "**After the merge:** apply `CLAUDE.md`'s texts (above) and commit them on "
      "`m0-decisions`")
cites_lines("OWN-RU-04", REVIEWED, PARA, 7, 10, "Apply them on `m0-decisions`", "before you ask an agent for anything")
holds("OWN-RU-04", "claude-md-paragraph.md at 832a3636 never says to apply the texts after the merge",
      "after the merge" not in git("show", f"{REVIEWED}:{PARA}"))
para = git("show", f"{REVIEWED}:{PARA}")
block = para[para.find("```markdown") + len("```markdown"):para.find("```", para.find("```markdown") + 5)].strip()
holds("OWN-RU-04", "the paragraph left to paste by hand is a long one (the finding says 2,600 characters; the count "
      "follows)", len(block) >= 2500, f"{len(block)} characters")

# OWN-RU-05
cites("OWN-RU-05", REVIEWED, RB, 262, "| tee ../../Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log")
cites("OWN-RU-05", REVIEWED, RB, 79, "`Docs/Stage0/evidence/G05-Recovery/device/step-1-tests.log`")
cites("OWN-RU-05", REVIEWED, RB, 290, "tee ../../../Docs/Stage0/evidence/G05-AI/device/step-01-ats.log")
cites("OWN-RU-05", REVIEWED, RB, 171, "7. **When a session already run is repeated:**")
holds("OWN-RU-05", "0.3 step 7 and Section 2 at 832a3636 say nothing of a repeat's file names",
      "new name" not in line(REVIEWED, RB, 171) and "new name" not in "\n".join(lines_of(REVIEWED, RB)[100:108]))
cites("OWN-RU-05", REVIEWED, GATE, 47, "1.2's repeats wait for the diagnosis of the suite's failures")
holds("OWN-RU-05", "1.2's command came from the owner's 4be1a1a4",
      "step-1-tests.log" in git("show", "4be1a1a4", "--", RB) and "DeviceTests/G05RecoveryDeviceTests.xcodeproj"
      in git("show", "4be1a1a4", "--", RB))
results12 = git("show", f"{REVIEWED}:Docs/Stage0/evidence/G05-Recovery/device/step-1-2-results.txt")
holds("OWN-RU-05", "step-1-2-results.txt: Log: step-1-tests.log", "Log: step-1-tests.log." in results12)
cites("OWN-RU-05", REVIEWED, "Docs/Stage0/G05-Recovery.md", 119, "`evidence/G05-Recovery/device/step-1-tests.log`")
cites("OWN-RU-05", REVIEWED, "Docs/Stage0/G05-Recovery.md", 117, "### Physical-device attempt")
d1 = [l for l in lines_of(REVIEWED, "Docs/Stage0/G05-AI.md") if l.startswith("| D1 |")]
holds("OWN-RU-05", "G0.5 AI's row D1 (failed) cites step-01-ats.log",
      len(d1) == 1 and "| failed |" in d1[0] and "`step-01-ats.log`" in d1[0])
tree = git("ls-tree", "-r", "--name-only", REVIEWED, "Docs/Stage0/evidence/G05-Recovery/device",
           "Docs/Stage0/evidence/G05-AI/device")
holds("OWN-RU-05", "the owner's sittings named their extra runs apart (step-1-hosted-tests.log, step-01-ats-initial.log)",
      "step-1-hosted-tests.log" in tree and "step-01-ats-initial.log" in tree)

# OWN-RU-06
cites("OWN-RU-06", REVIEWED, RB, 157, "since 24 October 2026 only its steps 1 and 4 are left to do before the first "
      "sitting: the rest are done or come later")
cites("OWN-RU-06", REVIEWED, GATE, 23, "8. **Check that your iPhone 13 mini (device A) runs iOS 26**",
      "update it once to iOS 26.x before Session 0", note="cited as line 24, which holds step 9; step 8 is on line 23")
cites("OWN-RU-06", REVIEWED, RB, 24, "before Session 0.4 records it")

# OWN-RU-07
cites("OWN-RU-07", REVIEWED, RB, 171, "nothing under `Apps`, `Packages`, `Spikes`, `Fixtures` or `Contracts`")
PATHS = ["Apps", "Packages", "Spikes", "Fixtures", "Scripts", "Contracts", "Docs/Stage0/device-checklists"]
for commit in ("96bdc7e9", "8404f342", "432acc13", "d5336111"):
    files = diff_files(commit, REVIEWED, *PATHS)
    spikes = [f for f in files if f.startswith("Spikes/") or f.startswith(".../")]
    if commit == "d5336111":
        holds("OWN-RU-07", f"git diff --stat {commit} {REVIEWED}: nothing under Spikes", not spikes, ", ".join(files))
    else:
        holds("OWN-RU-07", f"git diff --stat {commit} {REVIEWED}: the four files of DeviceTests under Spikes",
              len(spikes) == 4 and all("DeviceTests" in f or f.startswith(".../") for f in spikes), ", ".join(spikes))
cites("OWN-RU-07", REVIEWED, GATE, 30, "`Spikes/G05-Recovery/DeviceTests`", note="the gate summary's item 2 note")

# OWN-RU-08
cites("OWN-RU-08", REVIEWED, LOG, 3, "the M0 work moved to `m0-sessions`", "a second fix its accuracy findings "
      "(section 38).", absent=("section 41",))
cites("OWN-RU-08", REVIEWED, GATE, 122, "the M0 work continues on `m0-sessions`")
cites("OWN-RU-08", REVIEWED, GATE, 471, "ADR-0001 records the same evidence on `m0-exit-prep`, merged into `m0-sessions` "
      "once reviewed")
cites("OWN-RU-08", REVIEWED, GATE, 556, "the sessions build from `m0-sessions`")
cites("OWN-RU-08", REVIEWED, RB, 137, "*(done by an agent on 24 October 2026, reviewed next: Section 6)*")
for n in (855, 856, 857):
    cites("OWN-RU-08", REVIEWED, GATE, n, "*(done by an agent on 24 October 2026, reviewed next)*")

print()
print(f"result: {'pass' if all(results) else 'FAIL'} ({sum(results)} of {len(results)} hold)")
sys.exit(0 if all(results) else 1)
