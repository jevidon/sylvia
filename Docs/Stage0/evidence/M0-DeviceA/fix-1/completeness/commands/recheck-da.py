#!/usr/bin/env python3
"""Checks the fix of the completeness findings of the review of the update of 24 October 2026 and its assembly (26
October 2026 on the build Mac's clock; integration log section 31), which cite m0-sessions at 8082bdb6; the fix was made
from ec91f66a, the last commit of the fix of the same review's accuracy findings. One item per finding, and one for the
review status:
  branch        DA-01: the runbook's 1.2 has the dated note on the commands m0-decisions changed (DeviceTests), and its
                6.3 and 8.10, item 1's step 1 and the runbook's 0.3, step 1, point to it; the first fix's texts for a
                checkout on another branch kept; this fix's read of the branches and its computed merges committed, the
                read showing the checkout on m0-decisions at c72247a6 and the merge of m0-decisions without a conflict;
                this fix's README gives the text asked for CLAUDE.md's milestone paragraph;
  ran           DA-02: the runbook's 1.1 row B has the dated note on phone B's iOS as the sittings record it; the first
                and second fixes' texts on what is recorded here kept (the runbook's header, the gate summary's opening,
                Section 2's introduction, Section 5.1 and Section 7, the Stage 0 README), none saying that no device step
                has run;
  log-rows      DA-03: the runbook's Section 2 and the gate summary's item 1 say that item 1 and Session 8 supersede the
                session log's rows 1 and 8 until their new text is applied, and where the sittings are logged;
  release-notes DA-04: the first and second fixes' answers kept (the ADR index's row of ADR-0001, ADR-0001's Status, plan
                D01's row), which this fix did not change: this item passes on the tree of ec91f66a too; this fix's
                README gives the text asked for CLAUDE.md's toolchain line (checked under review);
  adr14         DA-05: ADR-0014's open items open with the dated note on m0-sessions, apart from the item that names
                m0-decisions, which is kept as it was;
  step-1        DA-06: Session 8's opening, 8.10 and the D-2 note say that the lines of 8.10's step 1 do not depend on the
                chip and that its pass includes the save-latency test, the old texts gone; the test is as they say;
  dropin        DA-07: 0.8's rule sets DeviceTests apart, with the command that leaves it out, the original command kept;
                0.8's note, the runbook's 0.3, step 1, and the gate summary's item 1, step 1, and item 2 no longer say
                that 0.8 runs again after the merge; this fix's log of the drop-in's paths shows the check that leaves
                DeviceTests out printing nothing for HEAD and for the computed merge;
  step-12       DA-08: the first fix's answer (FID-DA-05) in ADR-0013, which this fix did not change: this item passes on
                the tree of ec91f66a too;
  confirm       DA-09: the gate summary's item 1, step 7, the runbook's 0.2 and its technical-lead part say where the
                one-line confirmation goes until m0-exit-prep is merged;
  review        this fix, not reviewed, where the records give the review status of the update's fixes: the gate summary
                (Section 6.2's row and paragraph, items 131-140, Section 7's item 5, Section 8's Branch, bullet and
                Written by), the runbook's Who wrote it, the Stage 0 README, integration log section 31, the evidence
                READMEs of the records part and of the first two fixes, this fix's README with the CLAUDE.md texts asked,
                and the findings as relayed.
    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/recheck-da.py <repository root>
Run on the tree of ec91f66a (git archive), the commit this fix started from, it must report every item but release-notes
and step-12: the gate checks beside this file run that control. Read-only; standard library only; host only. Prints one
line per item and exits 1 if any is not as stated.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
GATE = "Docs/Stage0/M0-gate.md"
STAGE0 = "Docs/Stage0/README.md"
LOG = "Docs/Stage0/integration-log.md"
INDEX = "Docs/ADRs/README.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
EV = "Docs/Stage0/evidence/M0-DeviceA/"
HERE = EV + "fix-1/completeness/"
ADR01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
ADR13 = "Docs/ADRs/0013-design-language.md"
ADR14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
TESTS = "Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DurabilityTests.swift"
PATHS = ("Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery "
         "Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1")


def read(path):
    p = ROOT / path
    return p.read_text(encoding="utf-8") if p.is_file() else ""


def joined(path):
    """A hard-wrapped Markdown file with its lines joined, for phrases that may cross a line break."""
    return re.sub(r"\s*\n\s*", " ", read(path))


def line_with(text, start):
    found = [line for line in text.splitlines() if line.startswith(start)]
    return found[0] if len(found) == 1 else ""


def block(text, start, end):
    lines = text.splitlines()
    first = [i for i, l in enumerate(lines) if l.startswith(start)]
    if len(first) != 1:
        return ""
    rest = [i for i in range(first[0] + 1, len(lines)) if lines[i].startswith(end)]
    return "\n".join(lines[first[0]:rest[0] if rest else len(lines)])


def need(text, phrases, where):
    return [f"{where} lacks: {p}" for p in phrases if p not in text]


def gone(text, phrases, where):
    return [f"{where} still says: {p}" for p in phrases if p in text]


def report(item, missing, what):
    global problems
    if missing:
        problems += 1
    print(f"{'as stated' if not missing else 'PROBLEM  '} {item}: {what}" + (f" ({'; '.join(missing)})" if missing else ""))


runbook, gate, stage0, log, index, plan = (read(p) for p in (RUNBOOK, GATE, STAGE0, LOG, INDEX, PLAN))
adr01, adr13, adr14 = read(ADR01), read(ADR13), read(ADR14)
readme = joined(HERE + "README.md")
step03 = block(runbook, "**0.3 Commit**", "**0.4 Devices.**")
step031 = line_with(step03, "1. `git branch --show-current` reads `m0-sessions`")
step02 = block(runbook, "**0.2 Xcode account", "**0.3 Commit**")
step08 = block(runbook, "**0.8 G0.5 recovery report row 10", "**0.9 ")
step12 = block(runbook, "**1.2 The persistence suite on the device", "**1.3 ")
step63 = block(runbook, "**6.3 One restart for two checks**", "**6.4 ")
step810 = line_with(runbook, "**8.10 Persistence suite and save latency on A**")
session8 = block(runbook, "### Session 8 ", "**8.1 ")
d2 = line_with(runbook, "- **D-2** If device A cannot be had before the M0 exit")
row_b = line_with(runbook, "| **B. iPhone 17 Pro** (iPhone18,1), iOS 26.7 (23H24), Developer Mode on |")
then = line_with(runbook, "- **Then:** in the gate's report, change each row")
tech = next((line for line in runbook.splitlines()
             if "First, before Session 0, your confirmation that Xcode 27.1 (27A9275) is the release build" in line), "")
who = line_with(runbook, "- **Who wrote it.**")
item1 = block(gate, "**1. Before the first session**", "**2. The device sessions**")
item1_open = line_with(gate, "**1. Before the first session**")
item11 = line_with(item1, "1. **Check that `~/Git/sylvia-sessions` is on `m0-sessions`**")
item17 = line_with(item1, "7. **As technical lead, confirm that Xcode 27.1 (27A9275) is the release build: one line**")
item2 = line_with(gate, "**2. The device sessions**")
s62_row = line_with(gate, "| The review of the update of 24 October 2026 and its assembly (26 October 2026, at `8082bdb6`) |")
s7 = block(gate, "## 7. Recommendation", "## 8. ")
s8 = block(gate, "## 8. About this summary", "## 9. ")
s31 = block(log, "## 31. ", "## 32. ")
branch_log = read(HERE + "checks/branch-state.log")
merges_log = read(HERE + "checks/merges.log")
dropin_log = read(HERE + "checks/dropin-paths.log")

# branch: DA-01.
note12 = ("*(26 October 2026: on `m0-decisions`, where your first sittings are recorded, this step's two commands, 6.3's "
          "item 1 and the text of correction C41 were changed that day to run the recovery suite on the phone through "
          "`Spikes/G05-Recovery/DeviceTests`, an app that hosts it")
m = need(step12, [note12, "`-project DeviceTests/G05RecoveryDeviceTests.xcodeproj -scheme G05RecoveryDeviceTests` in "
                  "place of `-scheme G05Recovery-Package`", "This branch keeps the commands above until `m0-decisions` is "
                  "merged into `m0-sessions` (0.3, step 1), and that merge brings the new ones here: until then, run 1.2, "
                  "6.3 and 8.10 with the commands of the runbook on the branch your checkout is on", "its finding DA-01.)*"],
         "the runbook's 1.2")
m += need(step63, ["*(26 October 2026: on this branch item 1's command, which item 4 runs again, is the one from before "
                   "the change 1.2's note describes"], "the runbook's 6.3")
m += need(step810, ["Do: the commands of 1.2 with A's `DEVICE_ID` (on this branch, until `m0-decisions` is merged into "
                    "`m0-sessions`, the commands from before the change 1.2's note of 26 October 2026 describes"],
          "the runbook's 8.10")
m += need(step031, ["and it brings the commands of 1.2 and 6.3 that run the recovery suite on the phone through "
                    "`DeviceTests` (1.2's note)", "If it reads another branch, do not switch it yourself",
                    "Until the switch, steps 4 and 6 apply to the branch the checkout is on"], "the runbook's 0.3, step 1")
m += need(item11, ["and it brings the runbook's commands that run the recovery suite on the phone through it (runbook "
                   "1.2's note: until then, run 1.2, 6.3 and 8.10 with the commands of the runbook on the checkout's "
                   "branch)", "If it reads another branch, do not switch it yourself",
                   "Until the switch, steps 4 and 6 apply to the branch the checkout is on"], "M0-gate.md item 1, step 1")
m += need(gate, ["131. **The branch state, the commands of 1.2, and the merge again** (DA-01, blocker)",
                 "Not done here, a third time: the merge itself."], "M0-gate.md Section 6.3")
if ("branch refs/heads/m0-decisions" not in branch_log or "HEAD c72247a69a374ce361834550b92689b4abab95ee" not in branch_log
        or "merge-tree exit: 0" not in branch_log or "exit: 0" not in branch_log):
    m.append("this fix's branch-state.log is missing, or does not show the checkout on m0-decisions at c72247a6 and a "
             "merge without a conflict")
if "== 1. m0-decisions into HEAD\n   merge-tree exit: 0" not in merges_log or "exit: 0" not in merges_log:
    m.append("this fix's merges.log is missing, or does not show m0-decisions merging into HEAD without a conflict")
m += need(readme, ["Never build on `m0-integrate`, which is behind `main`, nor on `m0-decisions` once its commits after "
                   "`044ed3cf` are merged into `m0-sessions`"], "this fix's README, the text asked for CLAUDE.md's "
          "milestone paragraph")
report("branch", m, "the runbook's 1.2 note on the commands m0-decisions changed, with 6.3, 8.10, 0.3 step 1 and item 1 "
       "step 1 pointing to it; run 1's case for a checkout on another branch kept; the branches and the merges logged; "
       "the text asked for CLAUDE.md's milestone paragraph")

# ran: DA-02.
m = need(row_b, ["*(26 October 2026: the session log on `m0-decisions`, where your first sittings are recorded, gives phone "
                 "B as iOS 27.0.1 (24A446) in its sittings of 25 October 2026 UTC, not the 26.7 (23H24) above",
                 "which build these records give for phone B is settled with you when `m0-decisions` is merged into "
                 "`m0-sessions` (0.3, step 1)", "its finding DA-02.)*"], "the runbook's 1.1 row B")
m += need(line_with(runbook, "- **No device result is recorded on this branch yet.**"),
          ["Your first sittings, on phone B from 25 October 2026 (UTC), were built from `96bdc7e9` and later commits of "
           "`m0-decisions` and recorded on `m0-decisions`"], "the runbook's header")
m += need(line_with(gate, "**Recommendation** (Section 7)"), ["No device or human step's result is recorded here yet"],
          "M0-gate.md's opening")
m += need(gate, ["No row is passed on a device: no device step's result is recorded on this branch",
                 "No result of a device step in it is recorded here yet"], "M0-gate.md Sections 2 and 5.1")
m += need(s7, ["no device or human step's result is recorded here yet"], "M0-gate.md Section 7")
m += need(stage0, ["no device step's result is recorded on this branch yet, so every gate stays pending"],
          "the Stage 0 README")
m += need(gate, ["132. **What these records say has run, and phone B's build** (DA-02, major)"], "M0-gate.md Section 6.3")
if "27.0.1 (24A446)" not in branch_log:
    m.append("this fix's branch-state.log does not show phone B's build in the session log on m0-decisions")
report("ran", m, "the runbook's 1.1 row B gives phone B's build as the sittings record it, to be settled at the merge; the "
       "earlier fixes' texts on what is recorded here kept; item 132")

# log-rows: DA-03.
m = need(then, ["**The log's rows 1 and 8 still read as they did before 24 October 2026**", "Until you, or an agent you "
                "ask, apply their new text (`evidence/M0-DeviceA/assembly/README.md` gives it), `M0-gate.md` Section 1, "
                "item 1 and Session 8 here supersede them", "On this branch the log's opening also still says that no "
                "device step has been run", "its finding DA-03.)*"], "the runbook's Section 2")
m += need(item1_open, ["The session log's row 1 still lists these steps as they read before that day, and its row 8 "
                       "still names your iPhone 11 Pro as device A: this item and the runbook's Session 8 supersede both "
                       "until their new text, which `evidence/M0-DeviceA/assembly/README.md` gives, is applied to the log"],
          "M0-gate.md item 1's opening")
m += need(gate, ["133. **The session log's rows 1 and 8** (DA-03, major)"], "M0-gate.md Section 6.3")
sessions = read("Docs/Stage0/evidence/M0-runbook/sessions.md")
m += need(sessions, ["| 8 | 8 Device A, your iPhone 11 Pro (after Session 4) |", "(1) `m0-decisions` checked out"],
          "the session log (left as it was: the pointer is what this fix adds)")
report("log-rows", m, "the runbook's Section 2 and item 1's opening say that item 1 and Session 8 supersede the log's rows 1 "
       "and 8 until their new text is applied, and where the sittings are logged; the log left as it was")

# release-notes: DA-04, the first and second fixes' answers, unchanged here.
m = need(line_with(index, "| [0001](0001-platform-baseline-and-toolchain.md) |"),
         ["awaits the technical lead's confirmation of Apple's pages, read on 24 October 2026"],
         "the ADR index's row of ADR-0001")
m += need(line_with(adr01, "- **Status:**"), ["awaits the technical lead's confirmation of Apple's pages, which the "
                                              "orchestrating session read on 24 October 2026"], "ADR-0001's Status")
m += gone(line_with(adr01, "- **Status:**"), ["That 27A9275 is the non-beta release has not been checked against Apple's "
                                              "release notes"], "ADR-0001's Status")
m += need(line_with(plan, "| D01 - Platform floor |"), ["24 October 2026: Apple's pages were read that day, and they list "
                                                        "Xcode 27.1 (27A9275) as released"], "plan D01's row")
report("release-notes", m, "the first and second fixes' answers to FID-DA-06 and ACC-06, which are DA-04's but for "
       "CLAUDE.md: the ADR index's row of ADR-0001, ADR-0001's Status and plan D01's row give Apple's pages as read on 24 "
       "October 2026")

# adr14: DA-05.
openings = block(adr14, "## Open items", "- Product owner, counsel:")
m = need(openings, ["*(Dated note, 26 October 2026, on `m0-sessions`: the dated note of 23 October 2026 on the item below "
                    "that closes R4-01 and R4-02, which names `m0-decisions` as the base of the agent's work",
                    "agent work starts from it, on a branch of its own, and reaches the sessions' build only when merged "
                    "into it between sittings", "The work on R4-01 and R4-02 runs on `m0-exit-prep`, made from `5aec2518` as "
                    "`m0-sessions` was, and is merged into `m0-sessions` once reviewed", "its finding DA-05; agent-written, "
                    "not reviewed.)*"], "ADR-0014's open items")
m += need(adr14, ["*(Dated note, 23 October 2026: the request names `m0-decisions` as the agent's base and a branch of "
                  "its own for the result"], "ADR-0014's item on R4-01 and R4-02 (kept, for the m0-exit-prep run)")
m += need(gate, ["135. **ADR-0014's note on `m0-decisions`** (DA-05)"], "M0-gate.md Section 6.3")
if "does not conflict: this fix's note at the head of its open items merges with that run's changes" not in merges_log:
    m.append("this fix's merges.log is missing, or does not show ADR-0014 merging with m0-exit-prep's changes")
report("adr14", m, "ADR-0014's open items open with the dated note on m0-sessions, the item's own note kept for the "
       "m0-exit-prep run, whose merge does not conflict in ADR-0014")

# step-1: DA-06.
m = need(session8, ["and so do the lines of 8.10's step 1 (the classes read back, the SQLite version and the pragmas), but "
                    "not that step's pass: the suite it runs includes the save-latency test, which expects a p95 of at "
                    "most 200 ms", "its finding DA-06)"], "the runbook's Session 8 opening")
m += gone(session8, ["and so does step 1 of 8.10 (the classes read back"], "the runbook's Session 8 opening")
m += need(step810, ["Step 1's lines (the classes, the SQLite version, the pragmas) do not depend on the chip, but its pass "
                    "does in part", "its finding DA-06.)"], "the runbook's 8.10")
m += need(d2, ["(8.1-8.5, 8.8, 8.9 and the lines of 8.10's step 1: the classes, the SQLite version and the pragmas) are "
               "not affected", "and the pass of 8.10's step 1 rests in part on one, the save-latency test in its suite "
               "expecting a p95 of at most 200 ms", "that review's finding DA-06)",
               "but for which side of the start-up race of G0.4 step 12.2 the intent arrives on in 8.9, which may depend "
               "on the phone's speed and is allowed either way (ADR-0007)"], "the runbook's D-2 note")
m += gone(d2, ["(8.1-8.5, 8.8, 8.9 and step 1 of 8.10) are not affected"], "the runbook's D-2 note")
tests = read(TESTS)
if "func latency() throws" not in tests or "#expect(result.p95Ms <= 200)" not in tests:
    m.append(f"{TESTS} no longer has latency() expecting a p95 of at most 200 ms")
m += need(gate, ["136. **Step 1 of 8.10 on device A** (DA-06)"], "M0-gate.md Section 6.3")
report("step-1", m, "Session 8's opening, 8.10 and the D-2 note: the lines of 8.10's step 1 do not depend on the chip, its "
       "pass includes the save-latency test; the test as they say")

# dropin: DA-07.
m = need(step08, [f"`git diff --stat 9cdb0a02 HEAD -- {PATHS}`", "but for output under `Spikes/G05-Recovery/DeviceTests` "
                  "alone", "neither the drop-in nor the lock harness's checks builds, copies or runs it",
                  "the same command with `':(exclude)Spikes/G05-Recovery/DeviceTests'` after its last path",
                  "(Until 26 October 2026 this rule did not set `DeviceTests` apart: the review of the update of 24 "
                  "October 2026, its finding DA-07.)", "adds `Spikes/G05-Recovery/DeviceTests` under those paths, and "
                  "nothing else", "(evidence/M0-DeviceA/fix-1/completeness/checks/dropin-paths.log)",
                  "(evidence/M0-DeviceA/fix-1/checks/dropin-paths.log)"], "the runbook's 0.8")
m += gone(step08, ["after that merge the check from `9cdb0a02` lists it, and 0.8 runs again, as above"], "the runbook's 0.8")
m += need(step031, ["but G0.5 recovery's drop-in neither builds, copies nor runs it, so its run on `9cdb0a02` still stands "
                    "and 0.8 needs nothing for it"], "the runbook's 0.3, step 1")
m += gone(step031, ["so 0.8's check from `9cdb0a02` then lists it and 0.8 runs again after it (0.8)"],
          "the runbook's 0.3, step 1")
m += need(item11, ["but G0.5 recovery's drop-in neither builds, copies nor runs it, so its run on `9cdb0a02` still stands "
                   "and 0.8 needs nothing for it (item 2)", "that 0.8 runs again after the merge: item 137.)"],
          "M0-gate.md item 1, step 1")
m += gone(item11, ["so 0.8 then runs again (item 2)"], "M0-gate.md item 1, step 1")
m += need(item2, ["`evidence/M0-DeviceA/fix-1/checks/dropin-paths.log`", "G0.5 recovery's drop-in neither builds, copies "
                  "nor runs it", "`evidence/M0-DeviceA/fix-1/completeness/checks/dropin-paths.log`",
                  "On 24 October 2026 none of that had changed between `9cdb0a02` and `6cede84a`"], "M0-gate.md item 2")
m += gone(item2, ["so after it 0.8's check from `9cdb0a02` lists it and 0.8 runs again"], "M0-gate.md item 2")
m += need(gate, ["137. **0.8 after the merge of `m0-decisions`** (DA-07)"], "M0-gate.md Section 6.3")
for commit in ("6cede84a6f6ac610976b233d875e26dd89419dbd", "5e455f706c20d46711030a8b030c9dbf87dd4acd",
               "8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22", "ec91f66a863c70980533f27f53d8e6b44f234485"):
    if f"-- {commit} ({commit}): no change" not in dropin_log:
        m.append(f"this fix's dropin-paths.log lacks no change at {commit[:8]}")
if (not re.search(r"^-- HEAD \([0-9a-f]{40}\): no change", dropin_log, re.M) or "CHANGED" in dropin_log
        or "NAMED" in dropin_log or "PROBLEM" in dropin_log or "exit: 0" not in dropin_log
        or "prints nothing, so 0.8 still needs nothing after that merge" not in dropin_log):
    m.append("this fix's dropin-paths.log is missing, records a change at HEAD, names DeviceTests or a file m0-exit-prep "
             "changes, or does not show the check that sets DeviceTests apart printing nothing for the merge")
report("dropin", m, "0.8's rule sets DeviceTests apart, its command kept; 0.8's note, 0.3 step 1, item 1 step 1 and item 2 "
       "no longer have 0.8 run again after the merge; the log shows the check that leaves DeviceTests out printing "
       "nothing for HEAD and the computed merge")

# step-12: DA-08, the first fix's answer (FID-DA-05), unchanged here.
m = need(adr13, ["*(26 October 2026: of the M3 steps on device A, step 12 records, for the accessibility reviewer, "
                 "section 10's stated limit (b)", "so the narrower exception ADR-0001 records applies to it"],
         "ADR-0013's open item on devices")
report("step-12", m, "the first fix's answer to FID-DA-05, which is DA-08's: ADR-0013's open item on devices notes that "
       "step 12's result on device A in M3 is the 13 mini's")

# confirm: DA-09.
where = ["write your line in the session log's row for run 1, on the branch your checkout is on (step 1), and have it "
         "copied into ADR-0001's open item for the technical lead once that merge is made"]
m = need(item17, where + ["(until 26 October 2026 this step did not say where the line goes until then: item 139)"],
         "M0-gate.md item 1, step 7")
m += need(step02, ["your confirmation of that reading, as technical lead, is still to be recorded: one line (run 1, step "
                   "7). Write it in the session log's row for run 1, on the branch your checkout is on (0.3, step 1)",
                   "and then your line is copied into ADR-0001's open item for the technical lead", "its finding DA-09)"],
          "the runbook's 0.2")
m += need(tech, ["(until the `m0-exit-prep` run, which changes ADR-0001, is merged into `m0-sessions`, written in the "
                 "session log's row for run 1 and copied into ADR-0001 after that merge: 0.2"],
          "the runbook's technical-lead part")
m += need(gate, ["139. **Where your one-line Xcode confirmation goes** (DA-09)"], "M0-gate.md Section 6.3")
report("confirm", m, "item 1's step 7, the runbook's 0.2 and its technical-lead part say where the one-line confirmation "
       "goes until m0-exit-prep is merged")

# review: this fix, not reviewed.
m = need(s62_row, ["Then 9 more, as relayed to a third fix: completeness DA-01 to DA-09", "The nine answered the same day "
                   "by the fix of its completeness findings (items 131-140)", "| integration log sections 29, 30 and 31 |",
                   "`evidence/M0-DeviceA/fix-1/completeness/checks/finding-lines.log`"], "M0-gate.md Section 6.2's row")
m += need(gate, ["And its nine completeness findings, one of them a blocker and two major, a third fix answers (items "
                 "131-140), which has not been reviewed either.", "134. **Apple's release notes** (DA-04)",
                 "138. **G0.6 step 12 in ADR-0013** (DA-08)", "140. **Not reviewed**: this fix is agent-written"],
          "M0-gate.md Sections 6.2 and 6.3")
for n in range(131, 141):
    if not re.search(rf"^{n}\. \*\*", gate, re.M):
        m.append(f"M0-gate.md Section 6.3 lacks item {n}")
m += need(s7, ["and the fix of its completeness findings (items 131-140; integration log section 31)"],
          "M0-gate.md Section 7, item 5")
m += need(s8, ["and the fix of its completeness findings after that (items 131-140)", "- **The fix of the completeness "
               "findings of the update's review (26 October 2026; integration log section 31).**",
               "`evidence/M0-DeviceA/fix-1/completeness/checks/gate-checks.log`, written by "
               "`evidence/M0-DeviceA/fix-1/completeness/commands/gate-checks.sh`", "nor its third, of its completeness "
               "findings (section 31)"], "M0-gate.md Section 8")
m += need(who, ["and then, the same day, to answer the same review's completeness findings", "(integration log section 31; "
                "`evidence/M0-DeviceA/fix-1/completeness/`)", "nor its third, of its completeness findings; human review "
                "pending"], "the runbook's Who wrote it")
m += need(stage0, ["and a third fix its completeness findings (integration log section 31; "
                   "`evidence/M0-DeviceA/fix-1/completeness/`), which has not been reviewed either"], "the Stage 0 README")
for heading in ("## 31. ", "### 31.1 ", "### 31.2 ", "### 31.3 ", "### 31.4 ", "### 31.5 ", "### 31.6 "):
    if heading not in log:
        m.append(f"the integration log lacks {heading.strip()}")
m += need(read(EV + "README.md"), ["*(26 October 2026: a third fix answered the same review's completeness findings the "
                                   "same day"], "the records' evidence README")
m += need(read(EV + "fix-1/README.md"), ["*(26 October 2026: the same review's completeness findings, DA-01 to DA-09, were "
                                         "relayed to a third fix"], "the first fix's README")
m += need(read(EV + "fix-1/accuracy/README.md"), ["*(26 October 2026: the same review's completeness findings, DA-01 to "
                                                  "DA-09, were relayed to a third fix"], "the second fix's README")
m += need(readme, ["whether 27A9275 is the non-beta release awaits the technical lead's one-line confirmation of Apple's "
                   "pages, which the orchestrating session read on 24 October 2026"], "this fix's README, the text asked "
          "for CLAUDE.md's toolchain line")
if not (ROOT / HERE / "relayed-findings.md").is_file():
    m.append("the findings as relayed are not committed")
report("review", m, "this fix, not reviewed, in the gate summary (Section 6.2, items 131-140, Section 7, Section 8), the "
       "runbook's Who wrote it, the Stage 0 README, integration log 31 and the evidence READMEs; the texts asked for "
       "CLAUDE.md in this fix's README; the findings as relayed")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 10 not as stated)")
sys.exit(1 if problems else 0)
