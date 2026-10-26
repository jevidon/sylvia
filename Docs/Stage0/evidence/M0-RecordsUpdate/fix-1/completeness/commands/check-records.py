#!/usr/bin/env python3
"""The fix of the completeness findings of the review of m0-records-update (27 October 2026; integration log section
43): a copy of Docs/Stage0/evidence/M0-RecordsUpdate/commands/check-records.py, unchanged but for its check of the ADR
index, whose status column is dated 27 October 2026 since that fix gave the row of ADR-0015 later notes on R4-01 and
R4-02 (its finding CMP-05), with the history line of the change. m0-records-update's version, run on the same tree,
fails exactly that check, by design. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/commands/check-records.py [<root>]

m0-records-update's version, below:

m0-records-update (26 October 2026; integration log section 41): a copy of
Docs/Stage0/evidence/M0-DeviceA/commands/check-records.py, unchanged but for two checks whose texts changed after it
was written: the ADR index's status column, dated 26 October 2026 since the fixes of the review of the update of 24
October 2026 (the old version already failed on it there, by design: M0-DeviceA/fix-1/owner/README.md), and the
integration log's section on the device-A change and its parts, numbered 28 on m0-sessions and 36 since
m0-records-update brought it onto the product owner's session branch line after m0-exit-prep's sections 28-35. The
old version, run on the same tree, fails exactly those two checks, by design. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/commands/check-records.py [<root>]

The records part's version, below:

The device-A change of 24 October 2026 in the records the plan amendments' checker does not read: the ADRs and their
index, the gate reports and the integration log (integration log section 28).

The product owner decided D-1 again on 24 October 2026: the iPhone 11 Pro, device A since D-1 (b) of 22 October 2026,
no longer charges, and device A is the owner's iPhone 13 mini; the A13 floor is left for M8's release device matrix; the
chip-dependent results on device A are not A13 results, a narrower form of D-2 (b)'s exception, recorded where (b) said
an exception goes, each as far as it applies. This check reads, for each record:
  1. the text that records the decision, and the narrower exception or why it does not apply;
  2. that the statements of 22 October 2026 it made stale are gone (each record keeps them only as dated history);
  3. that the words other checks read in these records are kept: the runbook's content check (ADR-0009's "memory on the
     oldest supported iPhone", ADR-0010's "Device runs in", the G0.2 report's row name "T38 on a device (Wi-Fi, oldest
     supported iPhone)"), the correction-text check (correction C51's words in the G0.6 report and ADR-0001), and the
     earlier rounds' rechecks (ADR-0002's Branches);
  4. that no report row this change touched changed its status;
  5. the ADR index's status column, dated 24 October 2026: the new text of the assertion two earlier rechecks make
     (the follow-up's fix's FID4-04 and the second fix's HON4-06 require "Status (23 October 2026)", and now report it);
  6. ADR-0002's record of the state of 24 October 2026 (pull request #6, `m0-sessions`);
  7. the integration log's section 28.
Run from the repository root, or with the root of another tree as its argument (the runner's control runs it on the tree
of the commit this update starts from, where every check must fail):
    python3 -I Docs/Stage0/evidence/M0-DeviceA/commands/check-records.py [<root>]
Prints one line per check and exits 1 if any fails.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
failures = []


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def line_with(text, prefix):
    found = [line for line in text.splitlines() if line.startswith(prefix)]
    return found[0] if len(found) == 1 else ""


def check(label, text, need=(), gone=()):
    missing = [n for n in need if n not in text]
    stale = [g for g in gone if g in text]
    ok = bool(text) and not missing and not stale
    detail = "; ".join(["lacks: " + n[:110] for n in missing] + ["still says: " + g[:110] for g in stale])
    print(("PASS " if ok else "FAIL ") + label + (f" ({detail or 'text not found'})" if not ok else ""))
    if not ok:
        failures.append(label)


A01 = read("Docs/ADRs/0001-platform-baseline-and-toolchain.md")
A02 = read("Docs/ADRs/0002-repository-build-and-ci.md")
A03 = read("Docs/ADRs/0003-persistence.md")
A05 = read("Docs/ADRs/0005-pdf-reading-and-anchors.md")
A07 = read("Docs/ADRs/0007-quick-capture-evaluation.md")
A09 = read("Docs/ADRs/0009-transfer-protocol.md")
A10 = read("Docs/ADRs/0010-intake-handoff-and-wired-bundles.md")
A13 = read("Docs/ADRs/0013-design-language.md")
INDEX = read("Docs/ADRs/README.md")
EPUB = read("Docs/Stage0/G01-EPUB.md")
PDF = read("Docs/Stage0/G01-PDF.md")
G02 = read("Docs/Stage0/G02-Transfer.md")
G03 = read("Docs/Stage0/G03-Intake.md")
G05R = read("Docs/Stage0/G05-Recovery.md")
G06 = read("Docs/Stage0/G06-Design.md")
LOG = read("Docs/Stage0/integration-log.md")
EXCEPTION = "Recorded here, as ADR-0001 records it: a narrower form of the exception decision D-2 (b) described"

# 1-3. ADR-0001.
check("ADR-0001: the decision of 24 October 2026, the owner's words and choice, device A, the A13 floor, the narrower "
      "exception and G0.6's criterion", A01, need=[
          "**The decision of 24 October 2026: D-1 taken again**",
          "The owner wrote: \"iphone 11 pro seems to be no longer charging. i do have a 13 mini that is still working, so "
          "update the plan. even better from a screen size.\"",
          "the owner chose \"13 mini only (Recommended)\": \"The 13 mini becomes device A. The records say plainly that the "
          "slowest supported chip (A13) isn't measured on a device. That's left for M8's release device matrix, with a "
          "borrowed or bought A13 phone if wanted. Simplest, and no extra session time.\"",
          "Whether the iPhone 11 still works was not asked.",
          "**Device A is the iPhone 13 mini** (iPhone14,4 expected; A15 Bionic; 375 × 812 pt",
          "the baseline for small-screen layout on a device, not the oldest supported iPhone",
          "No A13 iPhone is measured in M0: the owner left the A13 floor for M8's release device matrix",
          "*D-2 and the narrower exception.* D-2 (a) stands",
          "*G0.6's criterion.* Plan 21.1 asks for the type roles \"on the oldest supported iPhone\". They are checked on "
          "device A",
          "- M8, the release device matrix (plan 21.2): the A13 floor, which device A does not measure.",
          "- **The iPhone 11 and the iPhone 13 mini together**",
          "- **The iPhone 11 alone**",
          # C51's words (the correction-text check reads them; C51 is not applied).
          "- Product owner: an iPhone 12-class device and an iPad for G0.6 and the device matrix.",
          # The earlier rechecks of the iPad's record (HON4-03).
          "until then whether it can run the iPad's steps is not verified",
      ], gone=[
          "Device A, the oldest supported iPhone, is the iPhone 11 Pro (A13) since the product owner's decision D-1 (b)",
          "**Device A, the oldest supported iPhone, is the iPhone 11 Pro**",
          "so the oldest supported iPhone the product owner named on 22 October 2026, the iPhone 11 Pro (D-1 (b)), is "
          "supported",
      ])

# 1-3. The ADRs with device-A items.
check("ADR-0003: device A the iPhone 13 mini; the narrower exception for the save latency", A03, need=[
    "on device A, the iPhone 13 mini since the product owner's decision of 24 October 2026", EXCEPTION,
    "the SQLite version, the pragma readback and the protection classes depend on the iOS build, not the chip"],
    gone=["on device A, the iPhone 11 Pro since D-1 (b) of the same day", "Device A is the iPhone 11 Pro (A13) since"])
check("ADR-0005: device A the iPhone 13 mini; the narrower exception for the highlight redraw", A05, need=[
    "on device A, the iPhone 13 mini since the product owner's decision of 24 October 2026", EXCEPTION,
    "this record assumes the product owner gives that confirmation too"],
    gone=["on device A, the iPhone 11 Pro since D-1 (b) of the same day",
          "The baseline device, device A, is the iPhone 11 Pro since"])
check("ADR-0007: device A the iPhone 13 mini, no Action button; the exception changes nothing but step 12's race", A07,
      need=["on device A, the iPhone 13 mini since the product owner's decision of 24 October 2026",
            "device A has none: the iPhone 13 mini since 24 October 2026, which has a Ring/Silent switch instead",
            "changes nothing here but one observation"],
      gone=["on device A, the iPhone 11 Pro since D-1 (b) of the same day",
            "device A, the oldest supported iPhone, has none: the iPhone 11 Pro since 22 October 2026"])
check("ADR-0009: step 11 on the iPhone 13 mini; the narrower exception; the words the runbook check reads kept", A09,
      need=["memory on the oldest supported iPhone (checklist step 11, which runs on device A. Device A was the iPhone "
            "11 Pro (A13), the product owner's decision D-1 (b) of 22 October 2026, which no longer charges; since the "
            "owner's decision of 24 October 2026 it is the iPhone 13 mini (A15), which is not the oldest supported iPhone.",
            EXCEPTION, "and an A13 phone's wait for M8's release device matrix, plan 19.1)",
            "step 11 on device A, the iPhone 13 mini since the product owner's decision of 24 October 2026"],
      gone=["memory on the oldest supported iPhone (device A: the iPhone 11 Pro since",
            "step 11 on device A, the iPhone 11 Pro since D-1 (b) of the same day"])
check("ADR-0010: the repeats on device A, the iPhone 13 mini; the narrower exception; \"Device runs in\" kept", A10,
      need=["- Device runs in `Docs/Stage0/device-checklists/G03-Intake.md`",
            "the same runs on device A (the iPhone 13 mini since the product owner's decision of 24 October 2026",
            EXCEPTION, "(the G0.3 repeats on device A move to M2; Open items)"],
      gone=["the same runs on the oldest supported iPhone, device A (the iPhone 11 Pro)",
            "(the G0.3 repeats on the oldest supported iPhone move to M2; Open items)"])
check("ADR-0013: G0.6's steps for the oldest supported iPhone made on device A; the exception does not apply", A13, need=[
    "that check is made on device A, the iPhone 13 mini (A15)",
    "does not apply to these steps: they depend on the screen and record no speed, memory or thermal figure",
    "steps 4, 13-15, 22-27, 29 and 30 on device A (the iPhone 13 mini since 24 October 2026, the iPhone 11 Pro until "
    "then), the steps for the oldest supported iPhone, which device A covers by its screen size in points"],
    gone=["Since the product owner's decision D-1 (b) of 22 October 2026 that phone is the iPhone 11 Pro",
          "The oldest supported iPhone is device A, the iPhone 11 Pro (375 × 812 pt)",
          "steps 4, 13-15, 22-27, 29 and 30 on the oldest supported iPhone (device A, the iPhone 11 Pro)",
          # 26 October 2026: the first attempt's wording, which set the iPhone 13 mini beside "the oldest supported
          # iPhone" as if it were it.
          "for the oldest supported iPhone (the iPhone 13 mini since",
          "G0.6's type roles on the oldest supported iPhone are checked on it"])

# 1-4. The gate reports.
t38 = line_with(G02, "| T38 on a device (Wi-Fi, oldest supported iPhone) |")
check("G0.2 report: row T38 (its name kept, pending-device) records the narrower exception", t38, need=[
    "| T38 on a device (Wi-Fi, oldest supported iPhone) | pending-device |",
    "step 11 runs on device A, the owner's iPhone 13 mini (A15), not on an A13 phone",
    "under that narrower form of the exception decision D-2 (b) described (ADR-0001, ADR-0009)"],
    gone=["the oldest supported iPhone is the product owner's iPhone 11 Pro since 22 October 2026"])
check("G0.2 report: open question 7 measures on device A, the iPhone 13 mini", G02, need=[
    "since 24 October 2026 step 11 runs on device A, the iPhone 13 mini"])
check("G0.1 EPUB and PDF reports: their open questions' notes of 24 October 2026", EPUB + PDF, need=[
    "*(24 October 2026: device A is now the product owner's iPhone 13 mini",
    "*(24 October 2026: the baseline device, device A, is now the product owner's iPhone 13 mini"])
check("G0.3 report: open item 5 on device A, the iPhone 13 mini", G03, need=[
    "and device A (M2, ADR-0010; runbook correction C56, accepted on 22 October 2026), the product owner's iPhone 13 "
    "mini since 24 October 2026"],
    gone=["and the oldest supported iPhone, the product owner's iPhone 11 Pro (M2, ADR-0010;"])
row13 = line_with(G05R, "| 13 | Plan 19.2: acknowledged capture save p95 on the device |")
row26 = line_with(G05R, "| 26 | T50 lock harness on a device:")
check("G0.5 recovery report: rows 13 and 26 (pending-device) and open question 6 name the iPhone 13 mini", G05R, need=[
    "| 13 | Plan 19.2: acknowledged capture save p95 on the device | pending-device |",
    "since the product owner's decision of 24 October 2026 that is the iPhone 13 mini (A15)",
    "*Decided again 24 October 2026 by the product owner, the iPhone 11 Pro no longer charging"],
    gone=["since decision D-1 (b) of 22 October 2026 (product owner) that is the iPhone 11 Pro (A13; runbook 8.10)"])
check("G0.5 recovery report: row 26 stays pending-device, on device A, the iPhone 13 mini", row26, need=[
    "| pending-device |", "on device A (the iPhone 13 mini since 24 October 2026; the iPhone 11 Pro until then) in M1"])
g06_rows = [line_with(G06, "| G0.6: type roles under Dynamic Type"), line_with(G06, "| G0.6: component set viewed on a device"),
            line_with(G06, "| G0.6 device review of the component set")]
check("G0.6 report: three rows (pending-device) made on device A, C51's words kept", "\n".join(g06_rows) if all(g06_rows)
      else "", need=[
          "these steps are made on device A, the owner's iPhone 13 mini",
          "Checklist steps 13, 14, 23, 24 and 27 on the oldest supported iPhone (no hardware yet), the iPhone 17 Pro and "
          "an iPad (no hardware yet).",
          "oldest supported iPhone, iPhone 17 Pro, iPad",
          "24 October 2026: on device A, the product owner's iPhone 13 mini, D-1 decided again."])
statuses = [row.split(" | ")[1] for row in g06_rows if row]
check("G0.6 report: the three rows' statuses unchanged", "ok" if statuses == ["pending-device"] * 3 else "",
      need=["ok"])

# 5. The ADR index.
check("the ADR index: its status column dated 24 October 2026, D-1 decided again, rows 0001-0013 on device A", INDEX,
      need=["| ADR | Title | Status (27 October 2026) | Owner during Stage 0 |",
            "decided again on 24 October 2026, the iPhone 11 Pro no longer charging: device A is the iPhone 13 mini",
            "Since 24 October 2026 device A is the iPhone 13 mini",
            "Until 24 October 2026 it read \"Status (23 October 2026)\"",
            "Until 27 October 2026 it read \"Status (26 October 2026)\""],
      gone=["| ADR | Title | Status (23 October 2026) | Owner during Stage 0 |",
            "| ADR | Title | Status (26 October 2026) | Owner during Stage 0 |",
            "Since 22 October 2026 device A, the oldest supported iPhone, is the iPhone 11 Pro (D-1 (b))"])

# 6. ADR-0002: the state of 24 October 2026, with the texts the earlier rechecks read kept.
check("ADR-0002: pull request #6 and m0-sessions in Branches, the earlier rechecks' texts kept", A02, need=[
    "- *Since 24 October 2026: `m0-sessions`.* Pull request #6 merged `m0-decisions` into `main` on 23 October 2026",
    "merge commit `96bdc7e9`, whose parents are `4c73da57` on `main` and `044ed3cf`",
    "before the M0 exit review the exception covers pull requests #4, #5 and #6, and no other merge into `main`",
    "before the M0 exit review the exception covers pull request #4, pull request #5 and this merge, and no other merge "
    "into `main`",
    "is merged into `m0-decisions`, never into `main` directly",
    "Bringing that work to `main` before the M0 exit is a further merge that the answer did not cover",
    "- Product owner: whether H-1's exception also covers bringing agent work started during the device sessions",
    "*Decided on 23 October 2026: it does.*"])

# 7. The integration log.
check("the integration log: section 36 (28 on m0-sessions) and its parts", LOG, need=[
    "## 36. Device A is the iPhone 13 mini, and the owner's instructions brought up to date (24 October 2026)",
    "### 36.1 The state on 24 October 2026", "### 36.2 The device-A change: the decision, and where each record changed",
    "### 36.3 The owner's instructions brought up to date", "### 36.4 Commits", "### 36.5 Checks",
    "### 36.6 Not done here, and why", "### 36.7 What stays pending",
    "the M0 work moved to `m0-sessions`, and the product owner decided device A again",
    # The second attempt (26 October 2026): the record says what the first attempt left and what the second ran.
    "This part was made in two attempts", "whether they ran is not known",
    "when the workflow relayed the product owner's \"keep going\""])

print(f"summary: {len(failures)} failed checks")
sys.exit(1 if failures else 0)
