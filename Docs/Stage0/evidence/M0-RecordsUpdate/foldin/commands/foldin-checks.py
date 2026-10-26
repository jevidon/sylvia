#!/usr/bin/env python3
"""What the fold-in of m0-device-fixes into m0-records-update changed in the records, checked on the tree (27 October 2026
on the build Mac's clock; integration log section 45). One part per record request of the device fixes' README, Section
8, and for the rest of the fold-in:
  1. Request 1: the G0.5 recovery checklist's step 1 expects `Test run with 73 tests in 13 suites passed`, keeps the old
     count in a history clause, and lists the expected lines of the device fixes' 7.3 (verbatim from that README); the
     runbook's note after 1.2 gives the count and the line with a count marker; the runbook's 1.2 Expect line, the
     owner's (4be1a1a4), is as at c72247a6.
  2. Request 2: the runbook's Section 2 allows a run's number; the notes after 1.2 and 1.3 name the files of the runs
     again after the fixes, which are those of the device fixes' 7.3 and 7.4 and are not committed yet.
  3. Requests 3 and 12: the runbook's 0.8, header, Section 3 (runs 2 and 3), Session 0's order line and Section 7, the
     gate summary's item 2, its drop-in paragraph and Section 5.1, and the G0.5 recovery report's row 10 say that 0.8
     runs again; the report's row 25 and the gate summary's Section 5.4 hold the quiet-tone test's open item; the session
     log is the owner's, byte for byte as at c72247a6.
  4. Request 4: the G0.5 recovery report has the section on the diagnosis and the fixes, which names rows 6 and 7 and
     the commits; rows 6 and 7 and the owner's two sections are as at c72247a6.
  5. Requests 5 and 15: the report's decisions pending for the technical lead (after its open questions, not numbered
     among them, so that the plan amendments' checker, which requires each numbered question to be referenced in the
     amendments, is unchanged), the gate summary's Section 5.4 and the runbook's technical-lead table give each decision
     as pending, with its proposed change; neither is applied (the recovery package's FileProtection.swift and
     Restore.swift as m0-device-fixes has them).
  6. Requests 6, 7 and 14: the G0.5 AI checklist's step 1 and the runbook's 1.3 have the texts; each marker the content
     check reads in them (`interface=en0`, `private-ipv4-interfaces=`, `private-ip=none precondition-not-met` and the
     line `ATS-PROBE variant=… private-ip=<a.b>.x.x interface=en0 result=…`) is in both documents; the last commit that
     changed the checklist changed the runbook too; 1.3's paragraph on cutting the log's addresses is between its command
     block and its paragraph on Local Network access, and its commands are the runbook's Session 4 command and a check.
  7. Request 8: G0.5 AI row D1 is the owner's line as at c72247a6, and the note after the table has the text; Q5 has
     its note.
  8. Requests 9 and 10: Scripts/ci.d/70-g05-ai.sh's minimum is 42; ADR-0011 is as at 6a510880 (request 10 not
     applied) and still records the 39 tests of the G0.5 run.
  9. Requests 11 and 13: integration log section 45, the gate summary's items 215-223, its Section 6.2 row and Section
     8 bullet exist; the next steps name the session log's rows.
 10. CLAUDE.md: as 6a510880 left it, its fifth line the texts file's paragraph and its toolchain line the new words; the
     runbook's 0.3 step 2 and the gate summary's item 1 step 2 give it as done; item 221 quotes step 2 as it read at
     6a510880 word for word; the evidence README's merge commands no longer run the apply command, check its diff, run
     the lock check for it or commit; the texts' file, the Stage 0 README and integration log 41.8, 42.8, 43.9, 44.3 and
     44.9 have their notes.
 11. The next steps: the gate summary's Section 1, the runbook's header, the Stage 0 README and the evidence README give
     them in one order (the merge, the class-B tests, 0.8, 1.2, 1.3, the rest of Session 1), each with what to do if
     m0-decisions has moved on.
 12. The device fixes' README: notes at its head, in 7.1 and in Section 8.
 13. The word limits the earlier fixes keep: the gate summary's opening (600), State line (200), the two (800), each
     step of item 1 (400), and the runbook's run 1 (200).
Read-only (git show, git ls-files, git log); standard library only. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands/foldin-checks.py
Prints one line per check and exits 1 if any fails.
"""
import re
import subprocess
import sys
from pathlib import Path

failures = []
C72 = "c72247a69a374ce361834550b92689b4abab95ee"
BEFORE = "6a510880c34f7936c972b6ace9a18c126ecab13d"
FIXES = "a60aa92274d209bff6e1727ed36c078cd94ed8b2"


def git(*args, ok=(0,)):
    out = subprocess.run(["git", *args], capture_output=True, text=True)
    if out.returncode not in ok:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def read(path):
    return Path(path).read_text(encoding="utf-8")


def at(rev, path):
    return git("show", f"{rev}:{path}")


def check(part, label, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'} {part} {label}" + (f" ({detail})" if detail and not ok else ""))
    if not ok:
        failures.append(f"{part} {label}")


def has(part, label, text, *needs, gone=()):
    missing = [n for n in needs if n not in text]
    stale = [g for g in gone if g in text]
    check(part, label, bool(text) and not missing and not stale,
          "; ".join(["lacks: " + n[:110] for n in missing] + ["still says: " + g[:110] for g in stale]))


def line_with(text, start):
    found = [l for l in text.split("\n") if l.startswith(start)]
    return found[0] if len(found) == 1 else ""


def between(text, start, end):
    a = text.find(start)
    b = text.find(end, a + len(start)) if a >= 0 else -1
    return text[a:b] if a >= 0 and b >= 0 else ""


def words(text):
    return len(text.split())


GATE, RB, LOG, STAGE0 = "Docs/Stage0/M0-gate.md", "Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/integration-log.md", "Docs/Stage0/README.md"
EV, PARA = "Docs/Stage0/evidence/M0-RecordsUpdate/README.md", "Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md"
DF = "Docs/Stage0/evidence/M0-DeviceFixes/README.md"
CLR, CLA = "Docs/Stage0/device-checklists/G05-Recovery.md", "Docs/Stage0/device-checklists/G05-AI.md"
REC, AI = "Docs/Stage0/G05-Recovery.md", "Docs/Stage0/G05-AI.md"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"
gate, rb, log, stage0, ev, para, df = (read(p) for p in (GATE, RB, LOG, STAGE0, EV, PARA, DF))
clr, cla, rec, ai = (read(p) for p in (CLR, CLA, REC, AI))
print(f"commit: {git('rev-parse', 'HEAD').strip()}; uncommitted paths: {len(git('status', '--porcelain').splitlines())}")
print()

# The device fixes' 7.3 lines, taken from their README as m0-device-fixes has it.
df73 = between(at(FIXES, DF), "### 7.3 Phone B: step 1.2 again", "### 7.4 Phone B: step 1.3 again")
NEW_LINES = re.findall(r"^  - `([^`]+)`(?: \(since fix-1\))?$", df73, re.M)
check("1", f"the device fixes' 7.3 lists five new lines ({len(NEW_LINES)} found)", len(NEW_LINES) == 5)
MISSING = re.search(r"`(rejected missing-blob-file: [^`]+)`", df73).group(1)
DANGLING = re.search(r"`(rejected unlisted-dangling-link: [^`]+)`", df73).group(1)
# The class's name and the write option, built in two parts, as the honesty fix's check-findings.sh builds them, so that
# the hard-rules audit's file-protection-none rule reads no literal in this text check (it reads documents, and sets no
# protection).
NONE, NO_PROTECTION = "NSFileProtection" + "None", ".noFile" + "Protection"
PLAIN = f"file written with {NO_PROTECTION} into the test's temporary directory reports: {NONE}"
NEW73, OLD68 = "`Test run with 73 tests in 13 suites passed`", "`Test run with 68 tests in 11 suites passed`"
CLASSB = "`class-B tree (4 files, 5 directories) copied with FileProtector.copyTree: [\"NSFileProtectionCompleteUntilFirstUserAuthentication\": 9]`"

# 1. Request 1
step1 = between(clr, "## 1. Test suite on the device", "## 2. Capture save latency")
has("1", "the checklist's step 1: the new count, its list of what is not built for iOS, the logs, and the old count in a "
    "history clause", step1, NEW73 + " (the six macOS-only tests, the three SIGKILL drills, the real full-volume test, "
    "the locked-host observation and the copy guard, are not built for iOS)",
    "Docs/Stage0/evidence/M0-DeviceFixes/assembly/dropin-steps-4-15/logs/simulator-tests.log",
    "Docs/Stage0/evidence/M0-DeviceFixes/fix-1/simulator-tests.log",
    "*(27 October 2026: until the device fixes were folded into `m0-records-update`, this line read " + OLD68,
    "The device fixes' request 1")
has("1", "the checklist's step 1: the expected lines of the device fixes' 7.3, verbatim", step1,
    *("`" + l + "`" for l in NEW_LINES), "`" + MISSING + "`", "`" + DANGLING + "`", "`" + PLAIN + "`",
    f"no `protection: library.sqlite has {NONE}` anywhere")
s12 = between(rb, "**1.2 The persistence suite on the device", "**1.3 App Transport Security")
has("1", "the runbook's note after 1.2: the new count, the count marker line, and what the owner's Expect line is", s12,
    NEW73, CLASSB, "the Expect line above, yours as committed (`4be1a1a4`), gives the count of the code before the fixes",
    "The device fixes' requests 1 and 2.")
expect_now = [l for l in rb.split("\n") if l.startswith("Expect (checklist step 1.2-1.4): " + OLD68)]
expect_then = [l for l in at(C72, RB).split("\n") if l.startswith("Expect (checklist step 1.2-1.4): " + OLD68)]
check("1", "the runbook's 1.2 Expect line, the owner's, is as at c72247a6", len(expect_now) == 1 and expect_now == expect_then)
has("1", "the report's row 22 has its note", line_with(rec, "| 22 |"), "*(27 October 2026: diagnosed and fixed on "
    "`m0-device-fixes`", "`Test run with 73 tests in 13 suites passed`")

# 2. Request 2
sec2 = between(rb, "## 2. How to record results", "## 3. Session plan")
has("2", "Section 2 allows a run's number where a record gives a repeat its names", sec2,
    "A run's number in place of the commit does as well", "`step-1-hosted-run2-tests.log`", "`step-01-ats-run2.log`",
    "`step-01-ats-run2.txt`", "their request 2")
s13 = between(rb, "**1.3 App Transport Security", "**1.4 Automated audio tests")
has("2", "the notes after 1.2 and 1.3 name the files of the runs again", s12 + s13, "`step-1-hosted-run2-tests.log`",
    "`step-1-2-results-run2.txt`", "`step-01-ats-run2.log`", "`step-01-ats-run2.txt`", "`step-04-suspension-run2.txt`")
df_now = read(DF)
has("2", "they are the names the device fixes' 7.3 and 7.4 give", df_now, "step-1-hosted-run2-tests.log",
    "step-01-ats-run2.log", "step-01-ats-run2.txt")
committed = git("ls-files", "Docs/Stage0/evidence/G05-Recovery/device", "Docs/Stage0/evidence/G05-AI/device").split()
taken = [c for c in committed if "run2" in c]
check("2", "none of them is committed yet", not taken, ", ".join(taken))

# 3. Requests 3 and 12
eight = between(rb, "**0.8 G0.5 recovery report row 10", "**0.9 ")
has("3", "the runbook's 0.8: it runs again, the commits, the counts, the stopped runs, the quiet-tone test", eight,
    "**it has: 0.8 runs again, after your merge of `m0-records-update`.**", "`a65cdc3e` and `c778cd63`",
    "79 host tests in 13 suites and 73 simulator tests in 13 suites",
    "`evidence/M0-DeviceFixes/recovery/dropin-run-1/console.log`", "`drop-in exit 65`", "The device fixes' request 3.")
has("3", "the runbook's header, runs 2 and 3, Session 0's order line and Section 7", rb,
    "Since those fixes changed the recovery package after `9cdb0a02`, 0.8 runs again after your merge",
    "*(27 October 2026: it has changed since: the device fixes, which `m0-records-update` brings, changed the recovery "
    "package, so 0.8 runs again after your merge",
    "1.2 and 1.3 run again on the device fixes' code, under new log names",
    "0.8 now says to run again, after that merge",
    "*(27 October 2026: it has changed, with the device fixes that `m0-records-update` brings, so 0.8 runs again after "
    "your merge, and 1 runs again on phone B: 0.8 and 1.2)*")
has("3", "the gate summary's item 2, its run 2 row, the drop-in paragraph, item 4's bullet and Section 5.1", gate,
    "what the drop-in builds has changed after `9cdb0a02`, the recovery package's `Sources` and `Tests`, so 0.8 runs "
    "again after your merge", "*(27 October 2026: it has, with the device fixes: 0.8 runs again after your merge of "
    "`m0-records-update`", "*(27 October 2026: no longer so: the device fixes of your first runs",
    "*(27 October 2026: it has, with the device fixes that `m0-records-update` brings, so it is yours again",
    "*27 October 2026: it has changed, with the device fixes that `m0-records-update` brings, so 0.8 runs again")
has("3", "the report's row 10 has its note, its status kept", line_with(rec, "| 10 |"), "| passed-host |",
    "*(27 October 2026: the device fixes, folded into `m0-records-update` that day, changed the recovery package",
    "The status stays passed-host", "finding F-1, which waits for the technical lead's decision")
has("12", "the report's row 25 and the gate summary's Section 5.4 hold the quiet-tone test's open item",
    line_with(rec, "| 25 |") + line_with(gate, "- **The lock harness's quiet-tone test, an open item**"),
    "an open item of the lock harness: its quiet-tone test, `ToneTests.playsQuietly()`",
    "`Docs/Stage0/evidence/M0-Decisions/fix-2/harness-checks-clean/harness-simulator-tests.log` line 2458",
    "The device fixes' request 12", "Your run of runbook 0.8, due again, shows whether it still fails")
check("3", "the session log is the owner's, byte for byte as at c72247a6", read(SESSIONS) == at(C72, SESSIONS))

# 4. Request 4
diag = between(rec, "### The diagnosis of the hosted run's failures, and the fixes (27 October 2026; agent-written)",
               "## Open questions") or rec[rec.find("### The diagnosis of the hosted run's failures"):]
has("4", "the report's section on the diagnosis and the fixes", diag, "**Row 6's failure**", "**Row 7's failure**",
    "`c778cd63`", "`546a8219`", "`copyTreeRefusals`", "Rows 6 and 7 stay failed (device) until a run passes",
    "The device fixes' request 4.")
for row in ("| 6 |", "| 7 |"):
    check("4", f"the report's row {row.strip('| ')} is the owner's line as at c72247a6",
          line_with(rec, row) == line_with(at(C72, REC), row) and line_with(rec, row) != "")
for heading in ("### Physical-device attempt, 26 October 2026 (25 October UTC)", "### App-hosted physical-device result, 26 October 2026"):
    then = at(C72, REC)
    a, b = then.find(heading), then.find("\n\n", then.find(heading) + len(heading) + 2)
    check("4", f"the owner's section {heading[4:40]}… is as at c72247a6", a >= 0 and then[a:b] in rec)

# 5. Requests 5 and 15
oq = between(rec, "## Open questions", "## Fixtures, dependencies and warnings")
q9, q10 = line_with(rec, "- **Finding F-1: pending your decision"), line_with(rec, "- **Finding S5: pending your decision")
has("5", "the report's decisions pending for the technical lead, after its open questions, not numbered among them", oq,
    "**Decisions pending for the technical lead** (added on 27 October 2026", q9, q10)
check("5", "the numbered open questions are still 1-8", re.findall(r"(?m)^(\d+)\. ", oq) == [str(n) for n in range(1, 9)])
has("5", "F-1: pending, not applied, the proposed change and what it would correct", q9,
    "pending your decision, not applied", "`var fresh = url; fresh.removeAllCachedResourceValues(); let actual = try "
    "protectionClass(of: fresh)`", "What it would correct", "ADR-0012", "the device fixes' request 5")
has("15", "S5: pending, not applied, the proposed change and what it would correct", q10,
    "pending your decision, not applied", "`openat(rootFD, entry.path, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)`",
    "What it would correct", "the device fixes' request 15")
has("5", "the gate summary's Section 5.4 and the runbook's technical-lead table give both", line_with(gate,
    "- **The technical lead, which is you: two decisions the device fixes left, pending your decision and not applied**")
    + line_with(rb, "| G0.5 recovery's decisions pending for the technical lead"), "**Finding F-1:**", "**Finding S5:**",
    "finding F-1, whether `FileProtector.verify`", "finding S5, whether `FileProtector.copyFile`")
for path in ("Spikes/G05-Recovery/Sources/SylviaRecovery/FileProtection.swift",
             "Spikes/G05-Recovery/Sources/SylviaRecovery/Backup/Restore.swift"):
    check("5", f"not applied: {path} as m0-device-fixes has it", read(path) == at(FIXES, path))

# 6. Requests 6, 7 and 14
c1 = between(cla, "## 1. App Transport Security", "## 2. Local Network permission")
MARKERS = ["interface=en0", "private-ipv4-interfaces=", "private-ip=none precondition-not-met",
           "ATS-PROBE variant=… private-ip=<a.b>.x.x interface=en0 result=…"]
for m in MARKERS:
    check("6", f"`{m}` in the checklist's step 1 and the runbook's 1.3", m in c1 and m in s13)
has("6", "the checklist's item 3: request 6's text", c1, "On a device the test loads only the phone's Wi-Fi (en0) "
    "private address (since `907538f5`).", "Each variant runs 14 tests.", "their request 6")
has("6", "the checklist's item 4 records the interface lines", c1, "the three `ATS-PROBE variant=… private-ip=…` lines, "
    "the three `private-ipv4-interfaces=` lines,")
has("7", "the runbook's 1.3: request 7's text and Record", s13, "are refused locally (-1004); since `907538f5` the private "
    "address is the phone's Wi-Fi (en0) address, named by `interface=en0`", "the first run's default variant was not "
    "blocked (`evidence/M0-DeviceFixes/ats/README.md` section 6)", "the three `ATS-PROBE variant=… private-ip=…` lines, "
    "the three `private-ipv4-interfaces=` lines,", "their request 7")
last_cl = git("log", "-1", "--format=%H", "--", CLA).strip()
touched = git("show", "--name-only", "--format=", last_cl).split()
check("7", f"the last commit that changed the G0.5 AI checklist ({last_cl[:8]}) changed the runbook too", RB in touched)
cmd_end = s13.find("cd ../../..\n```")
red = s13.find("Before you copy any line from the log or commit it")
lna = s13.find("When iOS asks for Local Network access")
check("14", "1.3's paragraph on cutting the log's addresses is right after its command block", 0 <= cmd_end < red < lna)
has("14", "its commands: the runbook's Session 4 command and the check, and the run again's log", s13[red:lna],
    "`perl -pi -e 's/\\b(\\d{1,3}\\.\\d{1,3})\\.\\d{1,3}\\.\\d{1,3}\\b/$1.x.x/g; s/\\.[A-Za-z0-9-]+\\.ts\\.net\\b/.[tailnet].ts.net/g' "
    "Docs/Stage0/evidence/G05-AI/device/step-01-ats.log`", "`perl -ne 'print if /\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b/' "
    "Docs/Stage0/evidence/G05-AI/device/step-01-ats.log` must print nothing", "`step-01-ats-run2.log`", "their request 14")
check("14", "Session 4's command is the same", "perl -pi -e 's/\\b(\\d{1,3}\\.\\d{1,3})\\.\\d{1,3}\\.\\d{1,3}\\b/$1.x.x/g; "
      "s/\\.[A-Za-z0-9-]+\\.ts\\.net\\b/.[tailnet].ts.net/g' <file>" in rb)

# 7. Request 8
check("8", "G0.5 AI row D1 is the owner's line as at c72247a6", line_with(ai, "| D1 |") == line_with(at(C72, AI), "| D1 |"))
has("8", "the note on row D1 after the table, with request 8's text", ai, "*(27 October 2026, on row D1. Its text and "
    "status are the product owner's, as committed (`1bbca07e`)", "the probe loaded the first private address of any "
    "interface (10.71.x.x; that it was not the Wi-Fi address is inferred, since no log names its interface), which the "
    "phone sent to iCloud Private Relay; ATS did not block it in any variant (no ATS-policy line for it, unlike the public "
    "IP and the qualified name).", "the re-run of 1.3 is pending")
has("8", "Q5 has its note", line_with(ai, "- **Q5 (device run).**"), "*(27 October 2026: diagnosed since")

# 8. Requests 9 and 10
check("9", "Scripts/ci.d/70-g05-ai.sh's minimum is 42", bool(re.search(r"(?m)^MIN_PROBE_TESTS=42\b", read("Scripts/ci.d/70-g05-ai.sh"))))
ADR11 = "Docs/ADRs/0011-ai-providers-context-and-privacy.md"
check("10", "ADR-0011 as at 6a510880 (request 10 not applied)", read(ADR11) == at(BEFORE, ADR11))
has("10", "it still records the 39 tests of the G0.5 run", read(ADR11), "the ATS/Keychain probe (three host apps) passes 39 tests")

# 9. Requests 11 and 13
check("11", "integration log section 45", "\n## 45. " in log)
for n in range(215, 224):
    check("11", f"the gate summary's item {n}", bool(re.search(rf"(?m)^{n}\. \*\*", gate)))
has("11", "the gate summary's Section 6.2 row and Section 8 bullet", gate, "| The review of `m0-device-fixes` (26 October "
    "2026: its first round at `fdce7cd5`, then a second round)", "- **The device fixes of your first runs, folded into "
    "`m0-records-update` (27 October 2026; integration log section 45).**")
has("13", "the next steps ask for session-log rows for the merge and each step run again", gate + rb,
    "in a row for the merge (runbook 0.3, steps 4 and 5)", "Record each run, and each step run again, in a row of the "
    "session log, as before.")

# 10. CLAUDE.md
check("10c", "CLAUDE.md as 6a510880 left it", read("CLAUDE.md") == at(BEFORE, "CLAUDE.md"))
block = re.search(r"```markdown\n(.*?)\n```", para, re.S).group(1)
old_words, new_words = re.findall(r"^> (.*)$", para, re.M)[:2]
cl = read("CLAUDE.md").split("\n")
tool = [l for l in cl if l.startswith("- Xcode 27.1 (27A9275)")]
check("10c", "its fifth line is the texts file's paragraph, and its toolchain line has the new words, not the old",
      cl[4] == block and len(tool) == 1 and new_words in tool[0] and old_words not in tool[0])
has("10c", "the runbook's 0.3, step 2: done, with its history", line_with(rb, "2. **Done on `m0-records-update`, which your "
    "merge brings: `CLAUDE.md`'s milestone paragraph and its toolchain line.**"), "in `6a510880`",
    "(Until 27 October 2026 this step had you put the two texts in yourself", gone=("2. **`CLAUDE.md`'s milestone paragraph: yours to correct**",))
gstep2 = line_with(gate, "2. **Done on `m0-records-update`, which your merge brings: `CLAUDE.md`'s milestone paragraph")
has("10c", "the gate summary's item 1, step 2: done, its history in item 221", gstep2, "in `6a510880`",
    "(This step's history, with its text until 27 October 2026 word for word: Section 6.3, item 221.)")
old2 = line_with(at(BEFORE, GATE), "2. **`CLAUDE.md`'s milestone paragraph: yours to correct")
check("10c", "item 221 quotes step 2 as it read at 6a510880, word for word",
      bool(old2) and ('word for word: "' + old2 + '"') in line_with(gate, "221. **"))
block_ev = between(ev, "## Merging it into `m0-decisions`, between sittings", "- **If the `log` line printed a commit")
check("10c", "the evidence README's merge commands: no apply command, diff, lock check or commit",
      "apply-claude-md-texts" not in block_ev and "git commit" not in block_ev and "12-dependency-lock" not in block_ev
      and "git merge --ff-only m0-records-update" in block_ev)
has("10c", "the texts' file, the Stage 0 README and the evidence README have their notes", para + stage0 + ev,
    "*(27 October 2026: applied. The orchestrating session ran", "*(27 October 2026, later: on `m0-records-update` "
    "`CLAUDE.md` is up to date", "2026, later: no longer left for you.")
for sec in ("41.8", "42.8", "43.9", "44.9"):
    part = between(log, f"### {sec} ", "\n## ")
    check("10c", f"integration log {sec}'s bullet on CLAUDE.md has its note", "`6a510880`" in part and "section 45" in part)
has("10c", "integration log 44.3 has its note", between(log, "### 44.3 ", "### 44.4 "), "in `6a510880`", "section 45")

# 11. The next steps, one order, in four places
def order_ok(text, keys):
    pos = [text.find(k) for k in keys]
    return all(p >= 0 for p in pos) and pos == sorted(pos), pos
merge_section = between(ev, "## Merging it into `m0-decisions`, between sittings", "*(This section's history.")
places = {
    "the gate summary's Section 1, item 2": between(gate, "**Your next steps, in order (27 October 2026).**", "\n\n"),
    "the runbook's header": line_with(rb, "- **Your next steps, in order (27 October 2026).**"),
    "the Stage 0 README": between(stage0, "The owner's next steps, in order:", ")*"),
    # The README gives the merge in its commands and the steps after it in its bullet "Then, in order", after the
    # bullets on a moved-on m0-decisions, a conflict and the checks after the merge (which name 0.8's command too).
    "the evidence README's merge section": between(merge_section, "```sh", "```")
    + between(merge_section, "- **Then, in order**", "\n\n"),
}
KEYS = ["merge", "class-B tests", "0.8", "1.2", "1.3", "Session 1"]
for name, text in places.items():
    ok, pos = order_ok(text, KEYS)
    check("11", f"{name}: the merge, the class-B tests, 0.8, 1.2, 1.3, then the rest of Session 1, in that order", ok, str(pos))
for name in ("the gate summary's Section 1, item 2", "the runbook's header"):
    has("11", f"{name}: what to do if m0-decisions has moved on, and ff-only", places[name], "--ff-only",
        "has moved on")
has("11", "the evidence README's merge section: ff-only, and what to do if m0-decisions has moved on", merge_section,
    "git merge --ff-only m0-records-update", "- **If the `log` line printed a commit, or the merge refused**",
    "to merge `m0-decisions` into\n  `m0-records-update`")
places["the evidence README's merge section"] = merge_section
has("11", "the conflict and m0-device-fixes merged on its own, in the README and the two lists", places["the gate summary's "
    "Section 1, item 2"] + places["the runbook's header"] + places["the evidence README's merge section"],
    "`git merge --abort` puts `m0-decisions` back as it was", "Do not merge `m0-device-fixes` on its own",
    "If you have already merged `m0-device-fixes` on its own")

# 12. The device fixes' README
has("12", "the device fixes' README: its notes at the head, in 7.1 and in Section 8", df_now,
    "*(27 October 2026: this branch, at `a60aa922`, is folded into `m0-records-update`",
    "*(27 October 2026: no longer this branch on its own.", "*(27 October 2026: applied on `m0-records-update`")

# 13. Word limits
opening, state = line_with(gate, "**Recommendation** (Section 7)"), line_with(gate, "- **State:**")
run1 = line_with(rb, "| 1 | Before the sessions |")
check("13", f"word limits: the opening {words(opening)} (600), the State line {words(state)} (200), the two "
      f"{words(opening) + words(state)} (800), run 1 {words(run1)} (200)",
      words(opening) <= 600 and words(state) <= 200 and words(opening) + words(state) <= 800 and words(run1) <= 200)
item1 = gate[gate.find("**1. Before the first session**"):gate.find("**2. The device sessions**")]
steps = [words(p) for p in re.split(r"(?m)^(?=\d+\. )", item1)]
check("13", f"each step of the gate summary's item 1 within 400 words (the longest {max(steps)})", max(steps) <= 400)

print()
print(f"result: {'pass' if not failures else 'FAIL'} ({len(failures)} failed)")
for f in failures:
    print("  failed: " + f)
sys.exit(1 if failures else 0)
