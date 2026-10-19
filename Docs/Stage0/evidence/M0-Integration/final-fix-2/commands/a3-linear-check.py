#!/usr/bin/env python3
"""Evidence for the M0 final review round 2 finding contracts R2-01 (rule A3 of anchor.v1 backtracked exponentially).

    python3 -I Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/a3-linear-check.py <repository root>

1. Equivalence. Rule A3's outcome (refused because no composition fits, refused because a page change lacks its
   U+000A, or accepted) with the linear check Scripts/check-spike-anchors.py now uses (pdf_composition_holds) against
   the regular-expression check it replaced (the code of 83ee280, written out below): exhaustively for every list of
   one to three segment texts over {"a", U+000A} of length 0 to 2, every page-change pattern and every exact_text over
   the same two characters of length 0 to 8; then for random lists of up to eight texts over {"a", "b", U+000A} and
   exact_texts built from a composition (some with a page change left without its U+000A) or changed by one character.
   Any difference fails.
2. Time. The review's case (n one-U+000A segments on one page, exact_text 1.5 n U+000A then "x") with the replaced
   check for n = 16 to 26 and with the linear check for n = 26 to 10,000 (the schema's limit), with the load.
3. Schema. The review's anchor, built by the checker's own a3_scale_anchor, is schema-valid at 40 and at 10,000
   segments and breaks A3 alone.
"""
from __future__ import annotations

import importlib.util
import itertools
import os
import random
import re
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("checker", root / "Scripts/check-spike-anchors.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def old_outcome(texts: list[str], page_changes: list[bool], exact: str) -> str:
    """The A3 code of 83ee280 (Scripts/check-spike-anchors.py), on the texts and page changes alone."""
    escaped = [re.escape(t) for t in texts]
    breaks = ["\n" if changed else "\n?" for changed in page_changes]
    if not re.fullmatch(escaped[0] + "".join("\n?" + t for t in escaped[1:]), exact):
        return "refused: no composition"
    if not re.fullmatch(escaped[0] + "".join(j + t for j, t in zip(breaks, escaped[1:])), exact):
        return "refused: page change without U+000A"
    return "accepted"


def new_outcome(texts: list[str], page_changes: list[bool], exact: str) -> str:
    if not checker.pdf_composition_holds(texts, [False] * len(page_changes), exact):
        return "refused: no composition"
    if not checker.pdf_composition_holds(texts, page_changes, exact):
        return "refused: page change without U+000A"
    return "accepted"


def load() -> str:
    return " ".join(f"{x:.2f}" for x in os.getloadavg())


print(f"command: Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/a3-linear-check.py {root}")
print(f"python: {sys.version.split()[0]}; load at the start (1, 5, 15 min): {load()}")
failures = 0
outcomes: dict[str, int] = {}

print("\n== 1. equivalence with the replaced check")
cases = 0
alphabet = ["a", "\n"]
short_texts = [""] + ["".join(p) for k in (1, 2) for p in itertools.product(alphabet, repeat=k)]
exacts = [""] + ["".join(p) for k in range(1, 9) for p in itertools.product(alphabet, repeat=k)]
for n in (1, 2, 3):
    for texts in itertools.product(short_texts, repeat=n):
        for page_changes in itertools.product([False, True], repeat=n - 1):
            for exact in exacts:
                cases += 1
                a, b = old_outcome(list(texts), list(page_changes), exact), new_outcome(list(texts), list(page_changes), exact)
                outcomes[b] = outcomes.get(b, 0) + 1
                if a != b:
                    failures += 1
                    if failures <= 10:
                        print(f"DIFFERENT: texts {texts!r}, page changes {page_changes}, exact {exact!r}: replaced {a}, linear {b}")
print(f"exhaustive: {cases:,} cases (1-3 texts over a and U+000A of length 0-2, every page-change pattern, every exact_text "
      f"of length 0-8 over the same characters); outcomes {dict(sorted(outcomes.items()))}")
rng = random.Random(20261020)
random_cases, random_outcomes = 0, {}
for _ in range(200_000):
    n = rng.randint(1, 8)
    texts = ["".join(rng.choice("ab\n") for _ in range(rng.randint(0, 4))) for _ in range(n)]
    page_changes = [rng.random() < 0.3 for _ in range(n - 1)]
    exact = texts[0]
    for text, changed in zip(texts[1:], page_changes):
        exact += ("\n" if changed and rng.random() < 0.9 else rng.choice(["", "\n"])) + text
    roll = rng.random()
    if roll < 0.3 and exact:
        i = rng.randrange(len(exact))
        exact = exact[:i] + exact[i + 1:]
    elif roll < 0.6:
        i = rng.randrange(len(exact) + 1)
        exact = exact[:i] + rng.choice("ab\n") + exact[i:]
    random_cases += 1
    a, b = old_outcome(texts, page_changes, exact), new_outcome(texts, page_changes, exact)
    random_outcomes[b] = random_outcomes.get(b, 0) + 1
    if a != b:
        failures += 1
        if failures <= 10:
            print(f"DIFFERENT: texts {texts!r}, page changes {page_changes}, exact {exact!r}: replaced {a}, linear {b}")
print(f"random: {random_cases:,} cases (seed 20261020; 1-8 texts over a, b and U+000A of length 0-4); outcomes "
      f"{dict(sorted(random_outcomes.items()))}")
print(f"differences: {failures}")

print("\n== 2. time on the review's case (indicative: other jobs may share this Mac)")
for n in range(16, 27, 2):
    texts, exact = ["\n"] * n, "\n" * (n + n // 2) + "x"
    started = time.perf_counter()
    outcome = old_outcome(texts, [False] * (n - 1), exact)
    print(f"replaced check, n={n}: {outcome}, {time.perf_counter() - started:.3f} s (load {load()})")
for n in (26, 40, 1_000, 10_000):
    anchor = checker.a3_scale_anchor(root, n, "\n" * (n + n // 2) + "x")
    started = time.perf_counter()
    rules = [r for r, _ in checker.anchor_violations(anchor)]
    print(f"linear check (anchor_violations), n={n:,}: rules {rules}, {time.perf_counter() - started:.3f} s (load {load()})")
    if rules != ["A3"]:
        failures += 1
        print("PROBLEM: expected A3 alone")

print("\n== 3. the review's anchor is schema-valid and breaks A3 alone")
schemas = checker.Schemas(checker.load_schemas(root))
for n in (40, 10_000):
    anchor = checker.a3_scale_anchor(root, n, "\n" * (n + n // 2) + "x")
    started = time.perf_counter()
    errors = list(schemas.errors("anchor", anchor))
    rules = [r for r, _ in checker.anchor_violations(anchor)]
    print(f"n={n:,}: schema errors {len(errors)} ({time.perf_counter() - started:.2f} s to validate and check); "
          f"code rules broken {rules}")
    if errors or rules != ["A3"]:
        failures += 1
        print("PROBLEM: expected a schema-valid anchor that breaks A3 alone")

print(f"\nload at the end: {load()}")
print(f"result: {'PASS' if failures == 0 else 'FAIL'} ({failures} problem(s))")
sys.exit(1 if failures else 0)
