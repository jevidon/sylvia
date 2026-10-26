#!/usr/bin/env python3
"""Accounts for every problem line of the second fix's gate checks, run unchanged on the assembly of the M0 exit
preparation (integration log section 30): Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-3/commands/gate-checks.sh
was written for the second fix of the record of G0.5 recovery's drop-in run (section 27), and fails by design on any
change of CLAUDE.md, the scripts or the plan since 26530d49 and on a recorded run under Xcode 27.1. The base is its run
on 5aec2518, the CLAUDE.md correction (Docs/Stage0/evidence/M0-ExitPrep/reviews/gate-checks-at-5aec2518.log), whose
only failing parts are 1b's and 1c's lines on CLAUDE.md (reviews/gate-checks-compare.log). What must hold here:

- every line that reports a problem, a failed control or a failed recheck (as compare-gate-checks.py of the review
  records counts them) and appears in the head log only, or in the base log only, matches exactly one entry below, and
  every entry matches at least one line: each is a change this round makes by design, given with its reason;
- the head log's UNL-02 line is the base log's but for the State line's word count.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/assembly/commands/compare-round-3.py <base log> <head log>

Read-only; standard library only. Exits 1 if any line is unaccounted for or any entry unused.
"""
import collections
import re
import sys

PROBLEM = re.compile(r"PROBLEM|NOT as required|result: FAIL|^\s*exit: [1-9]")
COLUMN = r"\(the ADR index lacks: \| ADR \| Title \| Status \(23 October 2026\) \| Owner during Stage 0 \|\)$"

# (pattern, count, reason): lines in the head log only.
HEAD_ONLY = [
    (r"^PROBLEM: the plan or the license inventory changed$", 1,
     "1b: the plan changed since 26530d49, in three dated notes on R4-01 and R4-02 (D02's row, the 23.2 risk row, A56), "
     "requested by the zip guard's branch; the license inventory and its draft did not"),
    (r"^code, scripts, contracts, fixtures and the workflow changed since 9cdb0a02: PROBLEM: "
     r"Scripts/check-dependency-lock\.py$", 1,
     "1d: the zip guard's two scripts (its second, Scripts/ci.d/12-dependency-lock.sh, on the next line), which the "
     "G0.5 recovery drop-in neither builds, copies nor runs: this round's gate checks, part 1d"),
    (r"^PROBLEM: also Scripts/check-dependency-lock\.py$", 1,
     "1e: the zip guard's two scripts among the folders the repeat rule names; the records give them in a dated note"),
    (r"^a run under Xcode 27\.1 \(Docs/Stage0/evidence/M0-dependencies/xcode-27\.1/\): PROBLEM, present: the records "
     r"call it pending$", 1,
     "1f: the run under Xcode 27.1, made offline by the zip guard's agent; the records now call it made"),
    (r"^PROBLEM: missing path: evidence/M0-ExitPrep/assembly/(12-dependency-lock|gate-checks|gate-checks-round-3-compare)"
     r"\.log$", 3,
     "3: the gate summary cites three logs this round writes after the documents commit these checks run on: the "
     "documents checks' logs come in the next commit, and the gate checks' log after them; this round's gate checks, "
     "run on that commit, find every path"),
    (r"^NOT as required \(22, 42, 66, 71, 78, 92\)$", 1,
     "3b: the negative control's copies lack the zip guard's log that row 76 now reads, so row 76 disagrees there too; "
     "this round's gate checks copy that log"),
    (r"^PROBLEM  FID4-04: .*" + COLUMN, 1,
     "the follow-up's fix's recheck (recheck-review4.py): the ADR index's column, dated 24 October 2026 since this round's notes"),
    (r"^result: FAIL \(3 of the eight not answered\)$", 1, "the follow-up's fix's recheck (recheck-review4.py), FID4-04 added by design: FID4-02 and FID4-06 as before, and FID4-04"),
    (r"^exit: 1; reported: FID4-02 FID4-04 FID4-06$", 1, "the follow-up's fix's recheck (recheck-review4.py), FID4-04 added by design: its exit line"),
    (r"^NOT as required: exactly FID4-02 and FID4-06, on exactly the three anchors the second fix reworded$", 1,
     "the follow-up's fix's recheck (recheck-review4.py), FID4-04 added by design: the second fix's gate checks require FID4-02 and FID4-06 alone"),
    (r"^PROBLEM  HON4-06: .*" + COLUMN, 1, "the second fix's recheck (recheck-hon4.py): the ADR index's column, dated 24 October 2026 since this round's notes"),
    (r"^result: FAIL \(1 of the six not answered\)$", 1, "the second fix's recheck (recheck-hon4.py), HON4-06 by design: its result line (it passed on the base)"),
    (r"^exit: 1$", 1, "the second fix's recheck (recheck-hon4.py), HON4-06 by design: its exit line (it passed on the base)"),
    (r"^PROBLEM  OWN4-07: .*\(a run under Xcode 27\.1 is now recorded: the records that call it pending need "
     r"updating\)$", 1, "the third fix's recheck (recheck-own4.py), by design: the run under Xcode 27.1 is recorded"),
    (r"^result: FAIL \(2 of the nine not answered\)$", 1, "the third fix's recheck (recheck-own4.py), OWN4-07 added by design: OWN4-01 as before, and OWN4-07"),
    (r"^exit: 1; reported: OWN4-01 OWN4-07$", 1, "the third fix's recheck (recheck-own4.py), OWN4-07 added by design: its exit line"),
    (r"^NOT as required: exactly OWN4-01, on run 12's old estimate alone$", 1, "the third fix's recheck (recheck-own4.py), OWN4-07 added by design: the second fix's gate checks require OWN4-01 alone"),
    (r"^PROBLEM  UNL-02: the State line \(\d+ words\) names .*", 1,
     "the fix's recheck of the drop-in run's record: its text names the State line's word count, which this round's "
     "notes changed; the texts it reports are the same (checked below)"),
    (r"^NOT as required: exactly UNL-02 and the review status, on the State line, the Stage 0 README and the runbook's "
     r"Who wrote it$", 1, "the fix of the drop-in run's record's recheck (recheck-unl.py): the second fix's gate checks require its text with 200 words"),
]
# Lines in the base log only, replaced by those above.
BASE_ONLY = [
    (r"^PROBLEM  UNL-02: the State line \(200 words\) names .*", 1, "replaced by the head log's line with its count"),
    (r"^exit: 1; reported: FID4-02 FID4-06$", 1, "replaced: FID4-04 added"),
    (r"^exit: 1; reported: OWN4-01$", 1, "replaced: OWN4-07 added"),
    (r"^result: FAIL \(1 of the nine not answered\)$", 1, "replaced: two of the nine"),
    (r"^result: FAIL \(2 of the eight not answered\)$", 1, "replaced: three of the eight"),
]


def problem_lines(path):
    with open(path, encoding="utf-8") as fh:
        return collections.Counter(line.strip() for line in fh if PROBLEM.search(line))


def account(lines, entries, where):
    bad = 0
    used = collections.Counter()
    for line, n in sorted(lines.items()):
        hits = [i for i, (pattern, _, _) in enumerate(entries) if re.search(pattern, line)]
        if len(hits) != 1:
            print(f"PROBLEM {where} ({n}x), {'unaccounted for' if not hits else 'matched by several entries'}: "
                  f"{line[:200]}")
            bad += 1
            continue
        used[hits[0]] += n
        print(f"ok      {where} ({n}x): {line[:150]}")
        print(f"          because: {entries[hits[0]][2]}")
    for i, (pattern, count, reason) in enumerate(entries):
        if used[i] != count:
            print(f"PROBLEM entry matched {used[i]} line(s), {count} expected: {pattern[:120]}")
            bad += 1
    return bad


base, head = problem_lines(sys.argv[1]), problem_lines(sys.argv[2])
print(f"base: {sys.argv[1]}; head: {sys.argv[2]}")
print(f"lines reporting a problem, a failed control or a failed recheck: {sum(base.values())} in the base log, "
      f"{sum(head.values())} in the head log; in both: {sum((base & head).values())}")
problems = account(head - base, HEAD_ONLY, "head only")
problems += account(base - head, BASE_ONLY, "base only")
strip = lambda text: re.sub(r"\(\d+ words\)", "(N words)", text)
unl_base = [l for l in base if l.startswith("PROBLEM  UNL-02:")]
unl_head = [l for l in head if l.startswith("PROBLEM  UNL-02:")]
same = len(unl_base) == 1 and len(unl_head) == 1 and strip(unl_base[0]) == strip(unl_head[0])
print(f"{'ok     ' if same else 'PROBLEM'} the UNL-02 line is the base log's but for the State line's word count")
problems += 0 if same else 1
print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
sys.exit(1 if problems else 0)
