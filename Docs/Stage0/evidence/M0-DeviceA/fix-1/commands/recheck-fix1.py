#!/usr/bin/env python3
"""Checks the fix of the fidelity findings of the review of the update of 24 October 2026 and its assembly (26 October
2026 on the build Mac's clock; integration log section 29), which read m0-sessions at 8082bdb6. One item per finding, and
one for the review status:
  checkout      FID-DA-01: the owner's run-1 step 1 (the gate summary's item 1 and the runbook's 0.3), the runbook's
                header, the repository README and integration log 28.1 describe the sessions' checkout as found on
                m0-decisions, say what to do if it reads another branch than m0-sessions (no switch by the owner; the
                orchestrating session switches it once the update is reviewed and once that branch's commits are merged
                into m0-sessions; steps 4 and 6 on the checkout's branch until then; 0.8 again after the merge), no longer
                call m0-decisions behind main (the checklists' setup lines included), and no longer say that no device
                step has run; the fix's read of the branches is committed and shows that state;
  a13           FID-DA-02: the four texts that gave the lack of an A13 phone in M0 as a fact give the owner's decision,
                each with its dated note, and no live record gives that lack as a fact;
  step-0.8      FID-DA-03: runbook 0.8 names the commit of each check of the drop-in's paths (6cede84a, the assembly's
                5e455f70, the fix's 8082bdb6 and its own), what the merge of m0-decisions adds, and the gate summary's
                item 2 the same; the fix's log records no change for those commits;
  dates         FID-DA-04: the Stage 0 README's heading and sentence, the gate summary's bullet and its line over items
                104-110, the runbook's Who wrote it, and the ADR index's row of ADR-0013 date each part as it was done or
                decided;
  step-12       FID-DA-05: ADR-0001 limits the narrower exception's absence to the G0.6 steps on device A in M0 and applies
                it to step 12's repeat in M3; ADR-0013 and the records' evidence README say so too;
  release-notes FID-DA-06: ADR-0001's Status and technical lead's open item, and the ADR index's row of ADR-0001, give
                Apple's pages as read on 24 October 2026 and the technical lead's confirmation as what remains; the
                index's status column dated 26 October 2026, with its history;
  base          FID-DA-07: the gate summary's bullet and the instructions part's evidence README give m0-sessions as made
                from 5aec2518, with 6cede84a committed on it;
  review        the review at 8082bdb6 and this fix (not reviewed) where the records give the update's review status: the
                gate summary (the State line within 200 words, Section 6.2's row, items 116-123, Section 7's item 5,
                Section 8), the runbook's Who wrote it, the Stage 0 README, integration log sections 28 and 29, the
                Status lines of the eight ADRs with a record of 24 October 2026, the ADR index's three rows, and the
                update's three evidence READMEs.
    python3 -I Docs/Stage0/evidence/M0-DeviceA/fix-1/commands/recheck-fix1.py <repository root>
Run on the tree of 8082bdb6 (git archive), the commit the review read, it must report all eight items: the gate checks
beside this file run that control. Read-only; standard library only; host only. Prints one line per item and exits 1 if
any is not as stated.
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
README = "README.md"
INDEX = "Docs/ADRs/README.md"
CL = "Docs/Stage0/device-checklists/"
EV = "Docs/Stage0/evidence/M0-DeviceA/"
ADRS = {n: f"Docs/ADRs/{f}" for n, f in (
    ("0001", "0001-platform-baseline-and-toolchain.md"), ("0002", "0002-repository-build-and-ci.md"),
    ("0003", "0003-persistence.md"), ("0005", "0005-pdf-reading-and-anchors.md"),
    ("0007", "0007-quick-capture-evaluation.md"), ("0009", "0009-transfer-protocol.md"),
    ("0010", "0010-intake-handoff-and-wired-bundles.md"), ("0013", "0013-design-language.md"))}
REVIEWED = "`8082bdb6`"


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


runbook, gate, stage0, log, readme, index = (read(p) for p in (RUNBOOK, GATE, STAGE0, LOG, README, INDEX))
adr = {n: read(p) for n, p in ADRS.items()}
step03 = block(runbook, "**0.3 Commit**", "**0.4 Devices.**")
step031 = line_with(step03, "1. `git branch --show-current` reads `m0-sessions`")
step08 = block(runbook, "**0.8 G0.5 recovery report row 10", "**0.9 ")
item1 = block(gate, "**1. Before the first session**", "**2. The device sessions**")
item11 = line_with(item1, "1. **Check that `~/Git/sylvia-sessions` is on `m0-sessions`**")
item2 = line_with(gate, "**2. The device sessions**")
s281 = block(log, "### 28.1 ", "### 28.2 ")
s29 = block(log, "## 29. ", "## 30. ")
header = line_with(runbook, "- **No device result is recorded on this branch yet.**")
who = line_with(runbook, "- **Who wrote it.**")
state = line_with(gate, "- **State:**")
section7 = block(gate, "## 7. Recommendation", "## 8. ")
section8 = block(gate, "## 8. About this summary", "## 9. ")
branch_log = read(EV + "fix-1/checks/branch-state.log")
dropin_log = read(EV + "fix-1/checks/dropin-paths.log")

# checkout: FID-DA-01.
m = need(step031, ["If it reads another branch, do not switch it yourself", "once everything the checkout's branch has "
                   "that `m0-sessions` lacks is merged into `m0-sessions`", "`git log --oneline m0-sessions..HEAD`",
                   "it was on `m0-decisions`, at `c72247a6`", "as this step and step 6 said until 24 October 2026",
                   "a switch before that merge would build your next sitting from a branch without those records or that "
                   "app", "so 0.8's check from `9cdb0a02` then lists it and 0.8 runs again after it",
                   "Until the switch, steps 4 and 6 apply to the branch the checkout is on",
                   "nor, once that merge is made, from `m0-decisions`",
                   "(evidence/M0-DeviceA/fix-1/checks/branch-state.log)",
                   "(Until 26 October 2026 this step said that the orchestrating session switches the checkout from "
                   "`main` at `96bdc7e9`"], "the runbook's 0.3, step 1")
m += gone(step03, ["The orchestrating session switches this checkout to it, from `main` at `96bdc7e9`, once",
                   "ask for it, or run `git checkout m0-sessions` there yourself.",
                   "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"], "the runbook's 0.3")
m += need(item11, ["If it reads another branch, do not switch it yourself", "the checkout was on `m0-decisions` at "
                   "`c72247a6`, not on `main` at `96bdc7e9`", "`evidence/M0-DeviceA/fix-1/checks/branch-state.log`",
                   "Until the switch, steps 4 and 6 apply to the branch the checkout is on",
                   "nor, once that merge is made, from `m0-decisions`"], "M0-gate.md item 1, step 1")
m += gone(item1, ["The orchestrating session switches the checkout to it, from `main` at `96bdc7e9`, once",
                  "Never build from `m0-integrate` or `m0-decisions`, both behind `main`"], "M0-gate.md item 1")
m += need(header, ["Your first sittings, on phone B from 25 October 2026 (UTC), were built from `96bdc7e9` and later "
                   "commits of `m0-decisions` and recorded on `m0-decisions`", "they reach this branch only when merged "
                   "into it, before your checkout moves to it (0.3, step 1)", "and until 26 October 2026 it said that "
                   "nothing in this runbook had been run on a device",
                   # The two texts the drop-in record's recheck reads in this line, under its old first words.
                   "passed from clean in an agent's run on `9cdb0a02` with the screen unlocked",
                   "so 0.8 asks you to run it again only if what it builds changes after that commit"],
          "the runbook's header")
m += gone(runbook, ["- **Nothing in this runbook has been run on a device.**"], "the runbook")
m += need(line_with(runbook, "- **Your decision of 24 October 2026, and the branch you build from since then.**"),
          ["Your first sittings, from 25 October 2026 (UTC), were recorded on `m0-decisions` instead"],
          "the runbook's paragraph on the branch")
m += need(readme, ["which the device sessions build from once the product owner's first sittings, recorded on "
                   "`m0-decisions` from 25 October 2026, are merged into it"], "README.md")
m += gone(readme, ["since then the M0 work and the device sessions use the branch `m0-sessions`"], "README.md")
m += need(s281, ["on `main` at `96bdc7e9` on 24 October 2026, as the state was relayed to this update",
                 "*(Until the fix of section 29, the same day, this cell gave the checkout as on `main` at `96bdc7e9` as "
                 "`git worktree list` showed it on 26 October 2026, a reading no committed log records"],
          "integration log 28.1")
m += gone(s281, ["as `git worktree list` showed it on 26 October 2026, until the orchestrating session"],
          "integration log 28.1")
opening = line_with(gate, "**Recommendation** (Section 7)")
m += need(opening, ["No device or human step's result is recorded here yet", "the sessions' branch became `m0-sessions` "
                    "(item 1)"], "M0-gate.md's opening")
m += gone(opening, ["None of the gates' device or human steps has run", "the sessions moved to `m0-sessions`"],
          "M0-gate.md's opening")
m += gone(gate, ["No row is passed on a device: no device step has run.", "the evidence is not: not one device or human "
                 "step has run"], "M0-gate.md")
m += gone(stage0, ["no device step has run, so every gate stays pending"], "the Stage 0 README")
m += need(stage0, ["The product owner's first sittings, on phone B from 25 October 2026 (UTC), were built from `96bdc7e9` "
                   "and later commits of `m0-decisions` and recorded on `m0-decisions`"], "the Stage 0 README")
for name in ("G04-Audio.md", "G05-AI.md", "G05-Recovery.md"):
    text = read(CL + name)
    m += need(text, ["`m0-integrate` is behind `main`, `m0-decisions` holds, past pull request #6, your first sittings' "
                     "records and what they added", "and until 26 October 2026 it said that `m0-decisions` is behind "
                     "`main`"], f"the {name[:-3]} checklist's setup line")
    m += gone(text, ["`m0-integrate` and `m0-decisions` are behind `main`"], f"the {name[:-3]} checklist's setup line")
m += need(adr["0002"], ["*(26 October 2026: the product owner's first sittings, on phone B from 25 October 2026 UTC, were "
                        "built from `96bdc7e9` and later commits of `m0-decisions` and recorded on `m0-decisions`"],
          "ADR-0002's Branches")
m += need(gate, ["116. **The sessions' checkout, found on `m0-decisions`** (FID-DA-01, major)"], "M0-gate.md Section 6.3")
m += need(s29, ["### 29.2 The reconciliation of `m0-decisions` with `m0-sessions`, and why this fix did not make it"],
          "integration log section 29")
if ("branch refs/heads/m0-decisions" not in branch_log or "HEAD c72247a69a374ce361834550b92689b4abab95ee" not in branch_log
        or "the first of them: 8404f342, whose parent is 044ed3cf" not in branch_log
        or "merge-tree exit: 0" not in branch_log or "exit: 0" not in branch_log):
    m.append("the fix's branch-state.log is missing or does not show the checkout on m0-decisions at c72247a6, the first "
             "commit after 044ed3cf made on it, and a merge without a conflict")
report("checkout", m, "the sessions' checkout as found, on m0-decisions, in run 1's step 1, the runbook's header, README.md "
       "and 28.1; what to do before it moves; m0-decisions no longer called behind main; no claim that no device step ran")

# a13: FID-DA-02.
m = need(read(CL + "G02-Transfer.md"), ["*(24 October 2026: the product owner left the A13 floor for M8 that day (decision "
                                        "D-1, decided again), so no A13 phone is measured in M0, and this repeat on the "
                                        "oldest supported iPhone waits for M8 with it", "whether the owner's iPhone 11, an "
                                        "A13 phone, still works was not asked"], "the G0.2 checklist's step 22.5")
m += gone(read(CL + "G02-Transfer.md"), ["*(24 October 2026: no A13 phone is at hand in M0."], "the G0.2 checklist")
m += need(runbook, ["which no device measures in M0: on 24 October 2026 you left the A13 floor for M8 (Section 1.1; "
                    "Section 6, D-1)"], "the runbook's 2.12")
m += gone(runbook, ["which no device of M0 has (Section 1.1)."], "the runbook's 2.12")
m += need(read(CL + "G01-EPUB.md"), ["which no device measures in M0: the product owner left the A13 floor for M8 on 24 "
                                     "October 2026."], "the G0.1 EPUB checklist")
m += gone(read(CL + "G01-EPUB.md"), ["which no device in M0 has. (Until"], "the G0.1 EPUB checklist")
m += need(read(CL + "G06-Design.md"), ["whose A13 no device measures in M0: the product owner left the A13 floor for M8 the "
                                       "same day.)*"], "the G0.6 checklist")
m += gone(read(CL + "G06-Design.md"), ["whose A13 no device in M0 has.)*"], "the G0.6 checklist")
# The sweep: no live record gives the lack of an A13 phone in M0 as a fact; an occurrence inside a dated note that says
# what a text said ("said that ...", "saying that ...") is the record of what it said.
LACK = re.compile(r"A13 phone is at hand|no device (?:of|in) M0 has|whose A13 no device in M0|no A13 phone is available")
live = [p for p in [README, RUNBOOK, GATE, STAGE0, LOG, INDEX, "Docs/Sylvia_v1_iOS_Implementation_Plan.md",
                    "Docs/Stage0/M0-plan-amendments.md"] + sorted(str(q.relative_to(ROOT)) for q in
                                                                  (ROOT / "Docs/ADRs").glob("*.md"))
        + sorted(str(q.relative_to(ROOT)) for q in (ROOT / "Docs/Stage0").glob("G0*.md"))
        + sorted(str(q.relative_to(ROOT)) for q in (ROOT / CL).glob("*.md"))]
seen = 0
for path in dict.fromkeys(live):
    text = read(path)
    for hit in LACK.finditer(text):
        seen += 1
        before = text[max(0, hit.start() - 80):hit.start()]
        if not re.search(r"said that|saying that|gave as a fact", before):
            m.append(f"{path}: gives the lack of an A13 phone as a fact: ...{text[max(0, hit.start() - 40):hit.end()]}")
report("a13", m, f"the four texts give the owner's decision (the A13 floor left for M8, so no A13 phone measured in M0), "
       f"each with its dated note; no live record gives the lack of an A13 phone as a fact ({seen} occurrences, each the "
       "record of what a text said)")

# step-0.8: FID-DA-03.
m = need(step08, ["none of those paths changed since `9cdb0a02` in it, at `5e455f70`, before the assembly's own changes",
                  "whose header names that commit", "That fix ran the check again on `8082bdb6`, the head of `m0-sessions` "
                  "the review read, and on its own last documents commit", "(evidence/M0-DeviceA/fix-1/checks/"
                  "dropin-paths.log)", "adds `Spikes/G05-Recovery/DeviceTests` under those paths: after that merge the "
                  "check from `9cdb0a02` lists it, and 0.8 runs again"], "the runbook's 0.8")
m += need(item2, ["On 26 October 2026 none of those paths had changed from `9cdb0a02` to `5e455f70`, the assembly's merge, "
                  "or to `8082bdb6`", "`evidence/M0-DeviceA/fix-1/checks/dropin-paths.log`"], "M0-gate.md item 2")
for commit in ("6cede84a6f6ac610976b233d875e26dd89419dbd", "5e455f706c20d46711030a8b030c9dbf87dd4acd",
               "8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22"):
    if f"-- {commit} ({commit}): no change" not in dropin_log:
        m.append(f"the fix's dropin-paths.log lacks no change at {commit[:8]}")
if not re.search(r"^-- HEAD \([0-9a-f]{40}\): no change", dropin_log, re.M) or "CHANGED" in dropin_log \
        or "NAMED:" in dropin_log or "exit: 0" not in dropin_log:
    m.append("the fix's dropin-paths.log is missing, records a change at HEAD, or names a file m0-exit-prep changes")
report("step-0.8", m, "0.8 names the commit of each check (6cede84a, 5e455f70, 8082bdb6, the fix's own) and what the merge "
       "of m0-decisions adds; item 2 says so; the fix's log records no change at those commits")

# dates: FID-DA-04.
m = need(stage0, ["**Where M0 stands (26 October 2026).**", "an agent brought the owner's instructions up to date from that "
                  "day to 26 October 2026"], "the Stage 0 README")
m += gone(stage0, ["**Where M0 stands (24 October 2026).**", "an agent brought the owner's instructions up to date that day"],
          "the Stage 0 README")
m += need(gate, ["From that day to 26 October 2026 an agent brought your instructions up to date",
                 "Recorded from 24 to 26 October 2026 (the build Mac's dates;"], "M0-gate.md")
m += gone(gate, ["The same day an agent brought your instructions up to date"], "M0-gate.md")
m += [f"M0-gate.md: a line still begins: Recorded on 24 October 2026, after pull request #6"] if line_with(
    gate, "Recorded on 24 October 2026, after pull request #6") else []
m += need(who, ["and from 24 to 26 October 2026 to record your decision of 24 October 2026 on device A"],
          "the runbook's Who wrote it")
m += gone(who, ["and on 24 October 2026 to record your decision of that day on device A"], "the runbook's Who wrote it")
row13 = line_with(index, "| [0013](0013-design-language.md) |")
m += need(row13, ["with D-1 (device A the iPhone 11 Pro, 375 × 812 pt; the iPad in M0) and PO-28 to PO-32, decided on 22 "
                  "October 2026, and D-1 decided again on 24 October 2026 (device A the iPhone 13 mini"],
          "the ADR index's row of ADR-0013")
m += gone(row13, ["the iPad in M0) and PO-28 to PO-32, decided on 22 October 2026; every device step"],
          "the ADR index's row of ADR-0013")
report("dates", m, "the Stage 0 README's heading and sentence, the gate summary's bullet and its line over items 104-110, "
       "the runbook's Who wrote it, and the ADR index's row of ADR-0013 each give the day each part was done or decided")

# step-12: FID-DA-05.
m = need(adr["0001"], ["ADR-0013 (it does not apply to G0.6's steps on device A in M0, which depend on the screen; it "
                       "applies to G0.6 step 12's repeat on device A in M3"], "ADR-0001")
m += gone(adr["0001"], ["ADR-0013 (it does not apply to G0.6's steps on device A, which depend on the screen)"],
          "ADR-0001")
m += need(adr["0013"], ["*(26 October 2026: of the M3 steps on device A, step 12 records, for the accessibility reviewer, "
                        "section 10's stated limit (b)", "so the narrower exception ADR-0001 records applies to it"],
          "ADR-0013's open item on devices")
m += need(read(EV + "README.md"), ["*(26 October 2026: for ADR-0013, it does not apply to G0.6's steps on A in M0"],
          "the records' evidence README")
report("step-12", m, "ADR-0001 limits the exception's absence to the G0.6 steps on device A in M0 and applies it to step "
       "12's repeat in M3; ADR-0013 and the records' evidence README say so")

# release-notes: FID-DA-06.
m = need(adr["0001"], ["awaits the technical lead's confirmation of Apple's pages, which the orchestrating session read on "
                       "24 October 2026", "Apple's pages were read on 24 October 2026, by the orchestrating session and "
                       "again by an agent (above), so what is left here is the technical lead's one-line confirmation",
                       "Until 26 October 2026 this item said that no agent had read them"], "ADR-0001")
m += gone(adr["0001"], ["That 27A9275 is the non-beta release has not been checked against Apple's release notes",
                        "and no agent has read them (above)"], "ADR-0001")
row01 = line_with(index, "| [0001](0001-platform-baseline-and-toolchain.md) |")
m += need(row01, ["awaits the technical lead's confirmation of Apple's pages, read on 24 October 2026"],
          "the ADR index's row of ADR-0001")
m += gone(row01, ["still awaits a check of Apple's release notes, and"], "the ADR index's row of ADR-0001")
m += need(index, ["| ADR | Title | Status (26 October 2026) | Owner during Stage 0 |",
                  "Until 26 October 2026 it read \"Status (24 October 2026)\""], "the ADR index")
report("release-notes", m, "ADR-0001's Status and open item, and the ADR index's row, give Apple's pages as read on 24 "
       "October 2026 and the technical lead's confirmation as what remains; the index's column dated 26 October 2026")

# base: FID-DA-07.
m = need(gate, ["made `m0-sessions` from that commit, committing `6cede84a` on it"], "M0-gate.md")
m += gone(gate, ["made `m0-sessions` from that commit (`6cede84a`), the branch"], "M0-gate.md")
instr = joined(EV + "instructions/README.md")
m += need(instr, ["made the branch `m0-sessions` from that commit, committing `6cede84a` on it"],
          "the instructions part's evidence README")
m += gone(instr, ["made the branch `m0-sessions` from that commit (`6cede84a`)"], "the instructions part's evidence README")
report("base", m, "m0-sessions made from 5aec2518, with 6cede84a committed on it, in the gate summary and the instructions "
       "part's evidence README")

# review: the review at 8082bdb6 and this fix where the records give the update's review status.
words = len(state.split())
m = need(state, ["nor has the update's fix (Section 6.2)", "and the last two fixes, the follow-up's fourth and that "
                 "record's second, have not been reviewed"], "the State line")
m += [f"the State line has {words} words (at most 200)"] if words > 200 else []
m += need(gate, ["| The review of the update of 24 October 2026 and its assembly (26 October 2026, at `8082bdb6`) |",
                 "And the review of the update of 24 October 2026 and its assembly (the last row but one) raised seven "
                 "fidelity findings", "123. **Not reviewed**: this fix is agent-written"], "M0-gate.md Section 6.2 and 6.3")
for n in range(116, 124):
    if not re.search(rf"^{n}\. \*\*", gate, re.M):
        m.append(f"M0-gate.md Section 6.3 lacks item {n}")
m += need(section7, ["which an agent review read at `8082bdb6`, and the fix of that review's fidelity findings (items "
                     "116-123"], "M0-gate.md Section 7, item 5")
m += need(section8, ["- **The fix of the fidelity findings of the update's review (26 October 2026; integration log section "
                     "29).**", "`evidence/M0-DeviceA/fix-1/checks/gate-checks.log`, written by "
                     "`evidence/M0-DeviceA/fix-1/commands/gate-checks.sh`", "nor the fix of the review that read the "
                     "update of your instructions of 24 October 2026 and its assembly at `8082bdb6`"], "M0-gate.md Section 8")
m += need(who, ["and of the update of 24 October 2026 and its assembly at `8082bdb6`", "nor has the fix of the update's "
                "review"], "the runbook's Who wrote it")
m += need(stage0, ["an agent review read that update and its assembly the same day, at `8082bdb6`, and a fix answered its "
                   "fidelity findings (integration log section 29; `evidence/M0-DeviceA/fix-1/`), which has not been "
                   "reviewed"], "the Stage 0 README")
m += need(log, ["Agent-written; read by an agent review at `8082bdb6`, whose fidelity findings section 29 answers"],
          "integration log section 28")
for heading in ("### 29.1 ", "### 29.2 ", "### 29.3 ", "### 29.4 ", "### 29.5 ", "### 29.6 "):
    if heading not in s29:
        m.append(f"integration log section 29 lacks {heading.strip()}")
for n, text in adr.items():
    if REVIEWED not in line_with(text, "- **Status:**"):
        m.append(f"ADR-{n}'s Status does not name the review at {REVIEWED}")
for n in ("0001", "0002", "0013"):
    if REVIEWED not in line_with(index, f"| [{n}]("):
        m.append(f"the ADR index's row of ADR-{n} does not name the review at {REVIEWED}")
for part in ("README.md", "instructions/README.md", "assembly/README.md"):
    if REVIEWED not in read(EV + part):
        m.append(f"{EV}{part} does not name the review at {REVIEWED}")
if not (ROOT / EV / "fix-1/relayed-findings.md").is_file():
    m.append("the findings as relayed are not committed")
report("review", m, f"the review at 8082bdb6 and this fix, not reviewed, in the gate summary (the State line: {words} "
       "words), the runbook, the Stage 0 README, integration log 28 and 29, eight ADRs, the ADR index and the update's "
       "evidence READMEs")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 8 not as stated)")
sys.exit(1 if problems else 0)
