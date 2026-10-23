#!/usr/bin/env python3
"""The facts the records state about G0.5 recovery's whole drop-in run with the screen unlocked (22 October 2026,
22:36-22:44 UTC, 23 October on the build Mac's clock; integration log section 25), each read in the run's committed
evidence: the console that Docs/Stage0/evidence/M0-Decisions/assembly/commands/run-dropin-clean.sh wrote, the
drop-in's whole output and its step logs. The fix of the review of that record (23 October 2026; integration log
section 26, finding UNL-05) made this version from the record's (Docs/Stage0/evidence/M0-Decisions/unlocked-record/
commands/check-run.py), whose docstring said that nothing is inferred: it checks the same 34 facts in the same way, and
says here and in its labels what each reads and what the records infer beyond it.

Checked, each as read: the command and the commit and branch it names, with no uncommitted file before the run; the
host and Xcode; the simulator; the screen's lock state (ioreg) at the start and the end; the start and end times and
the one-minute load the records quote; the two steps ci.sh ran, the drop-in's time and ci.sh's exit status; the
guard's row-10 line, and no line of a missing row-10 evidence (the FAIL that stops a run, or the WARNING that
G05_ALLOW_MISSING_CLASS_B=1 prints instead); that the wrapper itself never sets that switch; the class-B readback on
53 files and directories and the SQLite line in the host tests' log; the test counts (73 host, 68 simulator, 49 lock
harness); the drills' iterations and failures, the restore drill's checks, the save latency's and the manifest
check's results; the device builds and the harness app's signature; the harness's lock, its UI smoke check (11
attempts, 7 in the background, no gap, the test volume); the closing lines; and the number of `git status` lines the
console records after the run.

Not read, and so not checked here: whether G05_ALLOW_MISSING_CLASS_B was set in the environment the wrapper ran in,
which no evidence records (the records' "not set" rests on the relay; what is read is that the wrapper never sets it and
that the switch changed nothing, there being no line of missing row-10 evidence); and which path the one `git status`
line after the run names, which the console does not record: the records infer that it is the run's own folder, new,
not ignored and untracked until 35543102 committed it, which accounts for one line.

    python3 -I Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-2/commands/check-run.py <repository root> [<run folder>]

The run folder, relative to the root, defaults to Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1. As its
control, the gate checks of this round (gate-checks.sh beside this file) point it at the assembly's run of the same
wrapper with the screen locked, Docs/Stage0/evidence/M0-Decisions/assembly/dropin-clean, where it must fail.
Read-only; standard library only; host only. Prints one line per fact and exits 1 if any is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
FOLDER = sys.argv[2] if len(sys.argv) > 2 else "Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1"
RUN = ROOT / FOLDER
WRAPPER = ROOT / "Docs/Stage0/evidence/M0-Decisions/assembly/commands/run-dropin-clean.sh"
problems = 0


def read(name):
    path = RUN / name
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def fact(what, ok, seen=""):
    global problems
    if not ok:
        problems += 1
    print(f"{'ok     ' if ok else 'PROBLEM'} {what}" + (f" (found: {seen})" if not ok and seen else ""))


def line(text, prefix):
    found = [l for l in text.splitlines() if l.startswith(prefix)]
    return found[0] if found else ""


console = read("console.log")
dropin = read("71-g05-recovery.log")
host = read("logs/host-tests.log")
print(f"run folder: {FOLDER}")

# The run: command, commit, host, simulator, lock state, times.
fact("command: run-dropin-clean.sh unlocked-run-1",
     line(console, "command: ") == "command: Docs/Stage0/evidence/M0-Decisions/assembly/commands/run-dropin-clean.sh "
                                   "unlocked-run-1", line(console, "command: "))
fact("commit 9cdb0a02 on m0-decisions, 0 uncommitted files before the run",
     line(console, "commit: ") == "commit: 9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e (m0-decisions); uncommitted files "
                                  "before the run: 0", line(console, "commit: "))
fact("host: macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)",
     line(console, "host: ").startswith("host: macOS 26.6.2 (25G83), Apple M5 Max; Xcode 27.1 Build version 27A9275"),
     line(console, "host: "))
fact("deleted before the run: the spike's, the harness's and the drop-in's build products",
     line(console, "deleted before the run: ") == "deleted before the run: Spikes/G05-Recovery/.build "
                                                  "Spikes/G05-Recovery/LockHarness/.build .build/g05-recovery",
     line(console, "deleted before the run: "))
fact("simulator Sylvia-M0-dec-assembly (iPhone 17, iOS 26.5)",
     line(console, "simulator name ").startswith("simulator name Sylvia-M0-dec-assembly (iPhone 17, iOS 26.5;"),
     line(console, "simulator name "))
unlocked = "unlocked IOConsoleLocked=False CGSSessionScreenIsLocked=False"
fact("the screen unlocked at the start (ioreg)",
     line(console, "screen lock (ioreg) at the start: ") == f"screen lock (ioreg) at the start: {unlocked}",
     line(console, "screen lock (ioreg) at the start: "))
fact("the screen unlocked at the end (ioreg)",
     line(console, "screen lock (ioreg) at the end: ") == f"screen lock (ioreg) at the end: {unlocked}",
     line(console, "screen lock (ioreg) at the end: "))
start, end = line(console, "start: "), line(console, "end: ")
fact("start 2026-10-22T22:36:32Z, one-minute load 2.96",
     start.startswith("start: 2026-10-22T22:36:32Z;") and "load averages: 2.96 " in start, start)
fact("end 2026-10-22T22:44:05Z, one-minute load 18.06",
     end.startswith("end: 2026-10-22T22:44:05Z;") and "load averages: 18.06 " in end, end)

# What ci.sh ran, and its result.
steps = re.findall(r"(?m)^==> (\S+)\n {4}(pass|FAIL)[^\n]*", console)
fact("ci.sh ran 00-git-lfs and 71-g05-recovery, both passing",
     steps == [("00-git-lfs", "pass"), ("71-g05-recovery", "pass")], str(steps))
fact("71-g05-recovery passed in 447 s", "==> 71-g05-recovery\n    pass (447s)" in console)
fact("all 2 steps passed; ci.sh exit: 0",
     "all 2 steps passed" in console and line(console, "ci.sh exit: ") == "ci.sh exit: 0", line(console, "ci.sh exit: "))

# The guard and the class-B evidence of report row 10.
present = "row 10 evidence present: class-B readback and inheritance lines found in host-tests.log"
fact("the guard's line: row 10 evidence present (console and drop-in log)",
     present in console and present in dropin)
fact("no missing-evidence line (no FAIL, no WARNING) in the drop-in's log, so the switch, set or not, changed nothing",
     dropin != "" and "row 10 evidence missing" not in dropin)
assigns = [l for l in WRAPPER.read_text(encoding="utf-8").splitlines()
           if "G05_ALLOW_MISSING_CLASS_B" in l and not l.lstrip().startswith("#")]
fact("the wrapper itself never sets G05_ALLOW_MISSING_CLASS_B (it appears only in its comments; whether the "
     "environment set it is not recorded)", not assigns,
     "; ".join(assigns))
fact("host-tests.log: class B read back on 53 files and directories",
     'class B (non-default) requested: read back on 53 files and directories: ["NSFileProtectionCompleteUnlessOpen": 53]'
     in host)
fact("host-tests.log: the files SQLite creates in a class-B directory are class B",
     "files SQLite created in a class-B directory: probe.sqlite=NSFileProtectionCompleteUnlessOpen "
     "probe.sqlite-wal=NSFileProtectionCompleteUnlessOpen probe.sqlite-shm=NSFileProtectionCompleteUnlessOpen" in host)

# The tests.
fact("73 host tests passed", "✔ Test run with 73 tests in 11 suites passed" in host
     and "✔ Test run with 73 tests in 11 suites passed" in console)
fact("68 simulator tests passed", "✔ Test run with 68 tests in 11 suites passed" in read("logs/simulator-tests.log")
     and "✔ Test run with 68 tests in 11 suites passed" in console)
fact("the lock harness's 49 tests passed", "✔ Test run with 49 tests in 4 suites passed"
     in read("logs/harness-simulator-tests.log") and "✔ Test run with 49 tests in 4 suites passed" in console)
fact("two simulator test runs succeeded (the package's and the harness's)", console.count("** TEST SUCCEEDED **") == 2,
     str(console.count("** TEST SUCCEEDED **")))


# The drills and checks.
def drill(name, iterations):
    text = read(f"logs/{name}")
    return (f"iterations: {iterations}\n" in text and "\nfailures: 0\n" in text
            and text.rstrip().endswith("RESULT: PASS"))


fact("crash drill, chosen durability: 900 iterations, 0 failures", drill("crash-drill-full.log", 900))
fact("crash drill, synchronous=OFF: 150 iterations, 0 failures", drill("crash-drill-sync-off.log", 150))
fact("restore drill: 49 checks passed", read("logs/restore-drill.log").rstrip().endswith("RESULT: PASS (49 checks)"))
fact("restore crash drill: 300 iterations, 0 failures", drill("restore-crash-drill.log", 300))
fact("migration put-back crash drill: 240 iterations, 0 failures", drill("migration-crash-drill.log", 240))
fact("save latency: passed (indicative)", "RESULT: PASS (chosen p95" in read("logs/latency.log"))
fact("backup-manifest contract check passed", read("logs/manifest-contract.log").rstrip().endswith("RESULT: PASS"))

# The builds and the lock harness's steps 13-15.
fact("the iOS device build of step 12 (TEST BUILD SUCCEEDED)", "** TEST BUILD SUCCEEDED **" in console)
lock = read("logs/harness-lock.log")
fact("step 13: the harness's lock pins exactly what the package's pins, the same origin hash",
     "ok: LockHarness/Package.resolved pins exactly what ../Package.resolved pins" in lock and "originHash equal" in lock)
smoke = read("logs/harness-ui-smoke-check.log")
fact("step 14: the UI smoke check passed, 11 attempts, 7 in the background, no gap, at the test volume",
     smoke.rstrip().endswith("result: PASS")
     and "ok    at least 10 attempts, numbered from 1 without a break (11)" in smoke
     and re.search(r"(?m)^ok    at least 5 attempts made in the background: .*\(7\)$", smoke) is not None
     and "ok    no gap line" in smoke and "volume=0.01 (test volume)" in smoke)
signing = read("logs/harness-device-signing.txt")
fact("step 15: the app built for a generic iOS device and signed for team A4KBDX665Z, iPhone only (build only)",
     "** BUILD SUCCEEDED **" in console and "== G05LockHarness.app: codesign --verify --strict ok" in signing
     and "TeamIdentifier=A4KBDX665Z" in signing and "UIDeviceFamily of the built app (plutil -extract): [1]" in signing)
fact("the closing lines: lock harness steps 13-15 passed, and all steps passed",
     "G0.5 recovery lock harness: steps 13-15 passed" in console and "G0.5 recovery: all steps passed" in console)
fact("after the run: the console counts one git status line (the count is read; that it is the run's own folder, "
     "untracked, is inferred, not read)",
     line(console, "git status --porcelain lines after the run: ") == "git status --porcelain lines after the run: 1",
     line(console, "git status --porcelain lines after the run: "))

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} fact(s) not as the records state them)")
sys.exit(1 if problems else 0)
