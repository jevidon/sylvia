#!/usr/bin/env python3
"""Mutation checks for the draft 0.8 check-amendments.py (the plan decisions round, 22 October 2026).

The successor of Docs/Stage0/evidence/M0-plan-amendments/commands/mutation-checks.py. Each mutation breaks one
claim the amendments or the product owner's decisions make; the checker must then fail the check that guards that
claim. The first twenty-two are that version's, two of them rewritten because the plan text they mutate changed
with the decisions (15.4's token copies, PO-38; the 21.2 M1 row, PO-34); the rest guard the draft 0.8 checks.
Run from the repository root, on a clean tree:
    python3 -I Docs/Stage0/evidence/M0-Decisions/plan/commands/mutation-checks.py
Each mutation is written to the working copy, the checker runs, and the file is
restored from memory before the next one. Exits 1 if any mutation is missed.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
CHECKER = "Docs/Stage0/evidence/M0-Decisions/plan/commands/check-amendments.py"
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
    ("D-1 reverted: the iPhone 12-class baseline proposed again in 19.1", PLAN,
     "The baseline, the oldest supported iPhone (device A in `Docs/Stage0/M0-device-runbook.md`), is an iPhone 11 Pro: "
     "the product owner chose the iPhone 11 family on 22 October 2026",
     "Proposed baseline is iPhone 12-class hardware (device A in `Docs/Stage0/M0-device-runbook.md`): "
     "the product owner may choose the iPhone 11 family",
     "draft 0.8: the five decisions that are not the recommendation"),
    ("D-1 reverted in 21.1: the iPhone 12-class baseline named again", PLAN,
     "on the baseline iPhone (device A, an iPhone 11 Pro; Section 19.1) and an iPad",
     "on the iPhone 12-class baseline and an iPad",
     "draft 0.8: the five decisions that are not the recommendation"),
    ("PO-13 reverted: the background inbox read dropped from 15.1", PLAN,
     ", and also periodically in the background whenever iOS gives the app background time",
     "",
     "draft 0.8: the five decisions that are not the recommendation"),
    ("PO-23 reverted in T50: the harness built only if step 3 is inconclusive", PLAN,
     "Stage 0 builds a background-audio harness for the locked-device check (G0.5 recovery device step 3) before the "
     "device run",
     "a background-audio harness is built for the locked-device check (G0.5 recovery device step 3) only if it is "
     "inconclusive, after the device run",
     "draft 0.8: the five decisions that are not the recommendation"),
    ("PO-33 reverted: one onboarding sample", PLAN,
     "three ship in M2, each a short excerpt of a Standard Ebooks (CC0) edition: *Middlemarch*, *Walden* and "
     "*Meditations*",
     "one ships in M2, a short excerpt of a Standard Ebooks (CC0) edition: *Middlemarch*",
     "draft 0.8: the five decisions that are not the recommendation"),
    ("PO-39 reverted: the rewind after a long pause off by default", PLAN,
     "Resuming after a long pause rewinds by default, graduated as other audiobook players do",
     "Resuming after a long pause rewinds only when the listener turns it on, never by default",
     "draft 0.8: the five decisions that are not the recommendation"),
    ("PO-39's notice dropped from the 4.4.6 gaps table", PLAN,
     "; the brief notice that playback resumed earlier after a long pause, with its action that undoes the rewind "
     "(Section 10.1, PO-39; added in draft 0.8)",
     "",
     "draft 0.8: the five decisions that are not the recommendation"),
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
