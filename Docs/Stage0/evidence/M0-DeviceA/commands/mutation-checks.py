#!/usr/bin/env python3
"""Mutation checks for the check-amendments.py of the device-A change (24 October 2026, the update of the M0 records
after the product owner decided D-1 again; Docs/Stage0/evidence/M0-DeviceA/commands/check-amendments.py), which checks
plan draft 0.8 as revised on 24 October 2026.

This version replaces Docs/Stage0/evidence/M0-Decisions/followup/round-2/commands/mutation-checks.py, run against this
update's checker: its 51 mutations kept, six of them changed because the text they mutate or the label of the check
they expect changed with the decision of 24 October 2026 (D-1 reverted in 19.1 and in 21.1, now on the text of the iPhone
13 mini; the revision date turned back, now from 24 to 23 October 2026; and the labels of 10c and 10i, which now say
"as revised on 24 October 2026", in the mutations that expect them), and thirteen more, for the checks this update
changed or added: the Status and Revised lines without the decision (10k), the M8 row without the A13 floor (10k), the
baseline's A13 restored in the device-evidence row (10k), the Literata row and D01 back on the iPhone 11 Pro (10k), 21.4's
older baseline iPhone restored (10k), G0.6's check on device A dropped from 21.1 (10k), the iPhone 11 a second A13 phone
again in 19.1 (10c), the A13 floor said to be measured in M0 (10c), a pass on the iPhone 13 mini read as an A13 pass
(10c), the item of 24 October 2026 merged into the entry's previous item (10i), and the amendments' A46 row without its
note of 24 October 2026 (10k).

The follow-up's fix's version replaced Docs/Stage0/evidence/M0-Decisions/followup/commands/mutation-checks.py, run against this round's
checker: its 46 mutations unchanged (the texts they replace are still in the plan once each, and the checks they
expect to fail keep their names' beginnings), and five more, for the checks this round changed or added: D13's row
reading the answer as covering the companion's public release again (10g), 21.1 saying again that no device has to be
acquired before the iPad's iPadOS is known (10h), the correction item merged into the dated item (10i), D13's row
said to "now" leave PO-42 with counsel (10j), and Appendix D's correction item leaving PO-12's two parts open again
(10j).

The follow-up's version replaced Docs/Stage0/evidence/M0-Decisions/fix-1/commands/mutation-checks.py, run against the follow-up's
checker: its first 35 mutations unchanged; its two that restored the FID-01 wording in plan 15.5 and Appendix D
replaced, because 15.5 no longer holds the sentence they mutated (the product owner decided PO-12's two open parts on
23 October 2026), by one that restores the FID-01 wording in 15.5's new text; and ten more, for the revision date and
the checks 10f-10i of 23 October 2026: PO-12's two parts left open again, the ledger's duplicate dropped, D13's row
returned to counsel, the old D13 sentence restored, the iPad's absence restored in 19.1, the request to acquire an iPad
restored in the risk row, and the answers' dated item in Appendix D with a reading left to confirm, without the iPad,
or merged into the entry's previous item.

The first fix's version replaced Docs/Stage0/evidence/M0-Decisions/plan/commands/mutation-checks.py with its 35 mutations
unchanged, run against the fix round's checker, and adds two that guard the checker's new check 10f (PO-12's sources
file and import ledger stay the product owner's to decide in plan 15.5): the sentence the review found (FID-01)
restored in 15.5, and in Appendix D.

Its predecessor, below, was the successor of Docs/Stage0/evidence/M0-plan-amendments/commands/mutation-checks.py. Each mutation breaks one
claim the amendments or the product owner's decisions make; the checker must then fail the check that guards that
claim. The first twenty-two are that version's, two of them rewritten because the plan text they mutate changed
with the decisions (15.4's token copies, PO-38; the 21.2 M1 row, PO-34); the rest guard the draft 0.8 checks.
Run from the repository root, on a clean tree:
    python3 -I Docs/Stage0/evidence/M0-DeviceA/commands/mutation-checks.py
Each mutation is written to the working copy, the checker runs, and the file is
restored from memory before the next one. Exits 1 if any mutation is missed.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
CHECKER = "Docs/Stage0/evidence/M0-DeviceA/commands/check-amendments.py"
DOC = "Docs/Stage0/M0-plan-amendments.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"

# (what the mutation breaks, file, text replaced, replacement, the check that must fail)
MUTATIONS = [
    ("an unforced narrowing left out of Section 1.2", DOC,
     "personal quotation and search without AI text. [M0-A10]",
     "personal quotation and search without AI text.",
     "every scope-narrowing row's tag"),
    ("an unforced narrowing's row labelled a clarification", DOC,
     "stated beside its alternatives (PO-05) | scope narrowing | A10 |",
     "stated beside its alternatives (PO-05) | clarification | A10 |",
     "every Section 1.2 tag has a Section 2 row classified scope narrowing"),
    ("a narrowing missing from plan Appendix D's scope sentence", PLAN,
     "cleartext to a local model server only at an IP literal (A14);",
     "cleartext to a local model server only at an IP literal;",
     "plan Appendix D's draft 0.5 entry names exactly"),
    ("an ADR consequence left unnumbered", DOC,
     " (10) Tasks topped up from background callbacks",
     " Tasks topped up from background callbacks",
     "Section 3.2: ADR-0001 to ADR-0016"),
    ("an ADR consequence with no destination", DOC,
     "Homebrew ffmpeg for the G0.4 fixtures: no change, a repository tooling fact",
     "Homebrew ffmpeg for the G0.4 fixtures: a repository tooling fact",
     "Section 3.2: ADR-0001 to ADR-0016"),
    ("ADR-0016's row left out (20 October 2026: it was missing until then)", DOC,
     "| ADR-0016 | (1) ",
     "| ADR-0016, unmapped | (1) ",
     "Section 3.2: ADR-0001 to ADR-0016"),
    ("a G0.4 open-question bullet left uncovered", DOC,
     "| G0.4 open questions, the warnings note |",
     "| G0.4 warnings |",
     "G04-Audio.md: 7 open-question bullets"),
    ("a new quoted phrase with no vocabulary entry", PLAN,
     'text features show "No selectable text on this page". No guessed OCR text',
     'text features show "No selectable text on this page" or "Text missing here". No guessed OCR text',
     "plan Sections 1-23"),
    ("a phrase dropped from the vocabulary gaps table", PLAN,
     '"Already imported" (a same-file reimport; Section 7.3); ',
     "",
     "plan Sections 1-23"),
    ("a product-owner question renumbered", DOC,
     "| PO-44 |",
     "| PO-45 |",
     "Section 4 lists PO-01 to PO-44"),
    ("a tag left out of the decision register's list (A47)", DOC,
     "Collects A01, A02, A13, A14, A16, A19, A22, A23, A26, A27, A28, A40, A41, A45",
     "Collects A01, A02, A13, A14, A16, A19, A22, A23, A26, A27, A28, A40, A45",
     "A47 collects exactly"),
    ("a gaps-table section dropped from T54", PLAN,
     "from Sections 7.3, 7.5, 8.1, 8.4, 8.5, 9.1, 9.2, 10.1, 10.4, 12, 13.4 and 16.2 once",
     "from Sections 7.3, 7.5, 8.1, 8.4, 8.5, 9.1, 9.2, 10.4, 12, 13.4 and 16.2 once",
     "T54 names every section"),
    ("M1's earlier exception restored in 21.2 (draft 0.8 wording of the row)", PLAN,
     "| M0; the G0.5 recovery device steps (Section 21.1) [M0-A46] |",
     "| M0; exits after the G0.5 recovery device steps (Section 21.1) [M0-A46] |",
     "the milestone gating rule"),
    ("Appendix D's A46 summary without M1", PLAN,
     "each milestone, M1 included, starts after its gates' device steps",
     "each milestone starts after its gates' device steps",
     "the milestone gating rule"),
    ("the narrower uncertain-5xx list restored in 14.4", PLAN,
     "Treat every other 5xx (a 500, 502 or 504 among them), and any 5xx",
     "Treat a 500, 502 or 504, and any 5xx",
     "replaced phrases are absent"),
    ("the EPUB-folder narrowing labelled a clarification", DOC,
     "| scope narrowing | A53 |",
     "| clarification | A53 |",
     "every Section 1.2 tag has a Section 2 row classified scope narrowing"),
    # Added with the re-check of draft 0.5 (draft 0.7).
    ("the bundle's completeness proof applied to raw Finder copies again (8.5)", PLAN,
     "and validates the clone. For a bundle that is a proof of completeness: a copy still in progress fails",
     "and validates the clone: a copy still in progress fails",
     "replaced phrases are absent"),
    ("the bearer-token copies said to be bounded in all again (15.4, draft 0.8 wording)", PLAN,
     "the task window bounds those copies per job, and in the Stage 0 spike nothing bounds them across jobs: N jobs "
     "from one Mac downloading at once hold up to 4N requests carrying that Mac's token. Decided by the product owner "
     "on 22 October 2026 (PO-38 (a)): the job scheduler (Section 6.4) lets two jobs download at a time and queues the "
     "rest, so at most eight requests carrying a token wait in the daemon; the alternative, a bound on the "
     "outstanding tasks across all jobs, was not chosen. A pause",
     "the task window bounds those copies, a pause",
     "replaced phrases are absent"),
    ("the failed-gate count turned back to three (21.1)", PLAN,
     "and rows failed in four gates, each changing the approach",
     "and rows failed in three gates, each changing the approach",
     "replaced phrases are absent"),
    ("a new tag left out of Appendix D's draft 0.7 entry", PLAN,
     "- **A55** (Sections 11.1, 23.2):",
     "- A55 (Sections 11.1, 23.2):",
     "Appendix D lists tags A01-A56"),
    ("G0.4's playback-control decision left without its source", DOC,
     "| G0.4 open questions (its PO-5); row 38;",
     "| G0.4 report (its PO-5); row 38;",
     "G04-Audio.md: 7 open-question bullets"),
    ("a finding the re-check added left without its row", DOC,
     "| F15. A raw file copied with Finder is imported but never proved complete",
     "| A raw file copied with Finder is imported but never proved complete",
     "G03-Intake.md: 19 findings"),
    # Added with draft 0.8 (the product owner's decisions of 22 October 2026).
    ("the status turned back to draft 0.7", PLAN,
     "**Status:** Draft 0.8 - ",
     "**Status:** Draft 0.7 - ",
     "new anchor phrases are present in the plan"),
    ("a decided question said to be pending again (9.4, PO-04)", PLAN,
     "Decided by the product owner on 22 October 2026 (PO-04 (a)): after a settings change",
     "Proposed (product-owner decision pending): after a settings change",
     "draft 0.8: no sentence before Appendix D says"),
    ("a decision of the register left without its approval (D11)", PLAN,
     "| Product; categorization remains open. Approved by the product owner on 22 October 2026 |",
     "| Product; categorization remains open |",
     "draft 0.8: Section 23.1 lists D01-D17"),
    ("D-1 reverted: the iPhone 12-class baseline proposed again in 19.1 (24 October 2026: on the iPhone 13 mini's text)",
     PLAN,
     "is an iPhone 13 mini: the iPhone 11 Pro chosen on 22 October 2026 no longer charges, and on 24 October 2026 the "
     "product owner decided that device A is the iPhone 13 mini the owner has (the runbook's decision D-1, taken again)",
     "is iPhone 12-class hardware, as the recommendation of D-1 proposed",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("D-1 reverted in 21.1: device A the iPhone 11 Pro again (24 October 2026: until then, the 12-class baseline)", PLAN,
     "on the baseline iPhone (device A, an iPhone 13 mini since 24 October 2026; Section 19.1) and an iPad",
     "on the baseline iPhone (device A, an iPhone 11 Pro; Section 19.1) and an iPad",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("PO-13 reverted: the background inbox read dropped from 15.1", PLAN,
     ", and also periodically in the background whenever iOS gives the app background time",
     "",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("PO-23 reverted in T50: the harness built only if step 3 is inconclusive", PLAN,
     "Stage 0 builds a background-audio harness for the locked-device check (G0.5 recovery device step 3) before the "
     "device run",
     "a background-audio harness is built for the locked-device check (G0.5 recovery device step 3) only if it is "
     "inconclusive, after the device run",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("PO-33 reverted: one onboarding sample", PLAN,
     "three ship in M2, each a short excerpt of a Standard Ebooks (CC0) edition: *Middlemarch*, *Walden* and "
     "*Meditations*",
     "one ships in M2, a short excerpt of a Standard Ebooks (CC0) edition: *Middlemarch*",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("PO-39 reverted: the rewind after a long pause off by default", PLAN,
     "Resuming after a long pause rewinds by default, graduated as other audiobook players do",
     "Resuming after a long pause rewinds only when the listener turns it on, never by default",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("PO-39's notice dropped from the 4.4.6 gaps table", PLAN,
     "; the brief notice that playback resumed earlier after a long pause, with its action that undoes the rewind "
     "(Section 10.1, PO-39; added in draft 0.8)",
     "",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("a role recorded as signed in 23.3", PLAN,
     "until then each stays pending, and none is signed in this draft",
     "the security reviewer's role is signed",
     "draft 0.8: Section 23.3 records who signs"),
    ("the agent-only reviews left out of 23.3", PLAN,
     " Every review of the M0 work so far was made by agents, not by independent people.",
     "",
     "draft 0.8: Section 23.3 records who signs"),
    ("a non-recommended decision left out of Appendix D's draft 0.8 entry", PLAN,
     "- **PO-39** (Section 10.1;",
     "- PO-39 (Section 10.1;",
     "draft 0.8: Appendix D opens with the draft 0.8 entry"),
    # Added by the fix of the review of the decisions round (22 October 2026; FID-01), rewritten by the follow-up of
    # 23 October 2026 for 15.5's new text: the wording the review found, restored in place of 15.5's account of what
    # approving PO-12 chose on 22 October 2026.
    ("PO-12's open parts credited to a decision that kept them so, in 15.5", PLAN,
     "so approving PO-12 as recommended chose nothing for them that day.",
     "and the product owner's decision keeps it so.",
     "draft 0.8 as revised on 23 October 2026: 15.5 records the product owner's decision on PO-12"),
    # Added by the follow-up of 23 October 2026 (the product owner's answers of that day).
    ("the revision date turned back to 23 October 2026 (until 24 October 2026: from 23 to 22 October)", PLAN,
     "**Revised:** 24 October 2026 (",
     "**Revised:** 23 October 2026 (",
     "new anchor phrases are present in the plan"),
    ("PO-12's two parts left open again in 15.5", PLAN,
     "Decided for the sources file and the import ledger by the product owner on 23 October 2026: each is set aside and "
     "recovered.",
     "A repair path for a damaged sources file or import ledger is still the product owner's to decide, and until it is "
     "decided a damaged one keeps the client's launch deferred.",
     "draft 0.8 as revised on 23 October 2026: 15.5 records the product owner's decision on PO-12"),
    ("the import ledger's duplicate for review dropped from 15.5", PLAN,
     "so an item already imported may arrive again as a duplicate for review (Sections 7.3 and 8.1)",
     "so an item already imported is skipped",
     "draft 0.8 as revised on 23 October 2026: 15.5 records the product owner's decision on PO-12"),
    ("D13's row returned to counsel", PLAN,
     "on 23 October 2026 the product owner took it on for now, with PO-41, PO-43 and PO-44:",
     "it stays with counsel:",
     "draft 0.8 as revised on 23 October 2026: D13's row records"),
    ("the old D13 sentence restored beside the new one", PLAN,
     "| Product + release; public release approval later. Approved by the product owner on 22 October 2026. Whether "
     "BoringSSL's",
     "| Product + release; public release approval later. Approved by the product owner on 22 October 2026. Pending: "
     "whether BoringSSL's advertising clauses are acceptable for the notarized companion is left to counsel. Whether "
     "BoringSSL's",
     "draft 0.8 as revised on 23 October 2026: D13's row records"),
    ("no iPad again in 19.1", PLAN,
     "the product owner has an iPad with a hardware keyboard and a trackpad or mouse (23 October 2026), whose model",
     "no iPad is recorded as available yet, whose model",
     "draft 0.8 as revised on 23 October 2026: 19.1, 21.1 and the device-evidence risk row"),
    ("acquire an iPad restored in the device-evidence risk row", PLAN,
     "and the product owner has an iPad with a keyboard and a trackpad or mouse (23 October 2026) [M0-A46] |",
     "; acquire an iPad [M0-A46] |",
     "draft 0.8 as revised on 23 October 2026: 19.1, 21.1 and the device-evidence risk row"),
    ("a reading left to confirm in Appendix D's dated item", PLAN,
     "The readings of D-6, D-7 and D-9 (b) are confirmed",
     "The readings of D-6, D-7 and D-9 (b) are for the product owner to confirm",
     "draft 0.8 as revised on 24 October 2026: Appendix D's draft 0.8 entry ends with the dated item"),
    ("the iPad dropped from Appendix D's dated item", PLAN,
     "The iPad: the product owner has one with a keyboard and a trackpad or mouse for the device runbook's Session 9, "
     "its model recorded at Session 0 (Sections 19.1 and 21.1 and the device-evidence risk row). ",
     "",
     "draft 0.8 as revised on 24 October 2026: Appendix D's draft 0.8 entry ends with the dated item"),
    ("the dated item merged into the entry's previous item", PLAN,
     "and this draft carries no text for it.\n- *Recorded on 23 October 2026, within draft 0.8:",
     "and this draft carries no text for it. *Recorded on 23 October 2026, within draft 0.8:",
     "draft 0.8 as revised on 24 October 2026: Appendix D's draft 0.8 entry ends with the dated item"),
    # Added by the follow-up's fix (23 October 2026, after the review of the follow-up): one for each check it changed
    # or added.
    ("the companion's public release read into the answer again in D13", PLAN,
     "; the answer does not name the notarized companion's builds, so PO-42 is still settled before one is distributed "
     "beyond the team, as on 22 October 2026",
     ", read as before the companion's public release too",
     "draft 0.8 as revised on 23 October 2026: D13's row records"),
    ("no device to acquire again in 21.1, before the iPad's iPadOS is known", PLAN,
     ", whose model and iPadOS the device runbook records at Session 0: no device has to be acquired if that iPad runs "
     "iPadOS 26 or later, which every Stage 0 harness needs and the runbook checks before Session 0;",
     ", so no device has to be acquired, and",
     "draft 0.8 as revised on 23 October 2026: 19.1, 21.1 and the device-evidence risk row"),
    ("the correction item merged into the dated item of Appendix D", PLAN,
     "\n- *Corrected on 23 October 2026, after an agent review of the item above",
     " *Corrected on 23 October 2026, after an agent review of the item above",
     "draft 0.8 as revised on 24 October 2026: Appendix D's draft 0.8 entry ends with the dated item"),
    ("D13's row said to now leave PO-42 with counsel, in Appendix D", PLAN,
     "as D13's row then said",
     "as D13's row now says",
     "draft 0.8 as corrected on 23 October 2026: Appendix D's draft 0.8 entry points its items"),
    ("PO-12's two parts left open in Appendix D's correction item", PLAN,
     " (decided on 23 October 2026, set aside and recover: the item recorded that day, below)",
     "",
     "draft 0.8 as corrected on 23 October 2026: Appendix D's draft 0.8 entry points its items"),
    # Added by the device-A change (24 October 2026, the product owner's decision of that day on device A): one or more
    # for each check it changed or added.
    ("the Status line without the decision of 24 October 2026", PLAN,
     "; and so is the owner's decision of 24 October 2026 to take decision D-1 again",
     "; the owner's decision of 24 October 2026 is not recorded",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("the Revised line without the decision of 24 October 2026", PLAN,
     " 24 October: the product owner's decision of that day on device A recorded within draft 0.8 (decision D-1 taken "
     "again: the iPhone 13 mini in place of the iPhone 11 Pro, which no longer charges).",
     "",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("the M8 row without the A13 floor", PLAN,
     "; the A13 floor, which M0's device A, an iPhone 13 mini (A15), does not measure: the Section 19.2 budgets on an A13 "
     "iPhone, the product owner's iPhone 11 if it still works then, or one borrowed or bought if the owner wants one (left "
     "to this milestone's device matrix by the product owner on 24 October 2026; Section 19.1)",
     "",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("the baseline's A13 restored in the device-evidence row", PLAN,
     "; the baseline's A15 is two generations newer than the A13 of the oldest iPhones iOS 26 supports, so a budget met "
     "on it is not shown to hold on them",
     ", and the baseline's A13 makes the budgets stricter to meet",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("the Literata row back on the iPhone 11 Pro", PLAN,
     "| G0.6 on device A, an iPhone 13 mini the product owner has",
     "| G0.6 on the oldest supported iPhone, an iPhone 11 Pro the product owner has",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("D01 back on the iPhone 11 Pro", PLAN,
     "The baseline device, device A, is an iPhone 13 mini (A15, 375 × 812 pt); the A13, the oldest chip iOS 26 supports, "
     "is left for M8's release device matrix (Section 19.1)",
     "The oldest supported iPhone, the baseline device, is an iPhone 11 Pro (A13; Section 19.1)",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("21.4's older baseline iPhone restored", PLAN,
     "device A (D-1: an older baseline iPhone until 24 October 2026; since then an iPhone 13 mini, the A13 floor left "
     "for M8's device matrix, Section 19.1)",
     "an older baseline iPhone (D-1)",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("G0.6's check on device A dropped from 21.1", PLAN,
     " G0.6's check of the type roles on the oldest supported iPhone (above) is made on device A, whose screen in "
     "points, 375 × 812, is the iPhone 11 Pro's: among the oldest iPhones iOS 26 supports only the iPhone SE (2nd "
     "generation) has a smaller one, 375 × 667 pt, which stays a simulator check (Section 19.1; since the product "
     "owner's decision of 24 October 2026).",
     "",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
    ("the iPhone 11 a second A13 phone again in 19.1", PLAN,
     "The iPhone 11 is not device A, and a result taken on it is recorded under its own model.",
     "The iPhone 11 is a second A13 phone.",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("the A13 floor said to be measured in M0, in 19.1", PLAN,
     "No A13 iPhone is measured in M0:",
     "The A13 floor is measured on device A in M0:",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("a pass on the iPhone 13 mini read as an A13 pass, in 19.1", PLAN,
     "a budget of Section 19.2 it meets is not shown to hold on an A13 phone",
     "a budget of Section 19.2 it meets holds on an A13 phone",
     "draft 0.8 as revised on 24 October 2026: the five decisions that are not the recommendation"),
    ("the item of 24 October 2026 merged into the entry's previous item", PLAN,
     "\n- *Recorded on 24 October 2026, within draft 0.8:",
     " *Recorded on 24 October 2026, within draft 0.8:",
     "draft 0.8 as revised on 24 October 2026: Appendix D's draft 0.8 entry ends with the dated item"),
    ("the amendments' A46 row without its note of 24 October 2026", DOC,
     " 24 October 2026: the product owner's iPhone 11 Pro no longer charges, and the owner decided D-1 again: device A, "
     "the baseline for small-screen layout on a device, is the owner's iPhone 13 mini",
     "",
     "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A"),
]


def run_checker():
    result = subprocess.run([sys.executable, "-I", CHECKER], cwd=ROOT, capture_output=True, text=True)
    return result.returncode, result.stdout.splitlines()


def main():
    status, lines = run_checker()
    failing = [line for line in lines if line.startswith("FAIL ")]
    print("control (no mutation): exit %d, %d failed checks" % (status, len(failing)))
    if status != 0 or failing:
        print("the unmutated files must pass first")
        return 1
    missed = 0
    for name, path, old, new, expected in MUTATIONS:
        target = ROOT / path
        original = target.read_text(encoding="utf-8")
        if original.count(old) != 1:
            print("MISSED %s: the text to replace occurs %d times in %s" % (name, original.count(old), path))
            missed += 1
            continue
        try:
            target.write_text(original.replace(old, new, 1), encoding="utf-8")
            status, lines = run_checker()
        finally:
            target.write_text(original, encoding="utf-8")
        failing = [line[5:] for line in lines if line.startswith("FAIL ")]
        caught = status == 1 and any(line.startswith(expected) for line in failing)
        if not caught:
            missed += 1
        # Draft 0.8: name the expected check in full, since several labels contain a colon of their own (the
        # predecessor printed each failing label up to its first colon).
        others = [line[:70] for line in failing if not line.startswith(expected)]
        print("%s %s: exit %d; the guarding check %s: %s%s" % (
            "caught" if caught else "MISSED", name, status, "failed" if caught else "did not fail", expected,
            ("; also failed: " + " | ".join(others)) if others else ""))
    print("summary: %d mutations, %d caught, %d missed" % (len(MUTATIONS), len(MUTATIONS) - missed, missed))
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
