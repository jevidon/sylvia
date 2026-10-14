#!/usr/bin/env python3
"""Checks for Docs/Stage0/M0-gate.md (run by gate-summary-checks.sh).

1. Every backticked path in the summary exists: paths are taken relative to
   Docs/Stage0/ first, then to the repository root. Bare names (no slash) are
   checked only when they end in .md. Tokens with spaces, wildcards, braces,
   angle brackets, '$' or '=' are not paths and are skipped.
2. Counts the status column of the numbered criteria rows of Section 2 and
   prints each row's number and status, so the structured result can be
   compared with the table.

Exit status 1 if a path is missing or a status is outside the allowed set.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1]).resolve()
DOC = ROOT / "Docs/Stage0/M0-gate.md"
STAGE0 = ROOT / "Docs/Stage0"
ALLOWED = {"passed-host", "passed-simulator", "failed", "partial", "pending-device", "pending-human"}
PREFIXES = ("evidence/", "device-checklists/", "Docs/", "Spikes/", "Contracts/", "Scripts/", "Packages/", "Apps/", "Fixtures/", ".github/")
EXTS = (".md", ".log", ".txt", ".json", ".tsv", ".png", ".sh", ".yml", ".yaml", ".py", ".resolved", ".swift", ".sqlite")

text = DOC.read_text(encoding="utf-8")
problems = 0

checked = 0
for token in sorted(set(re.findall(r"`([^`\n]+)`", text))):
    if any(c in token for c in " *{}<>$=#:"):
        continue
    if "/" not in token:
        if not token.endswith(".md"):
            continue
    elif not (token.endswith(EXTS) or token.startswith(PREFIXES)):
        # a slash-bearing name such as a package (readium/ZIPFoundation), not a path
        continue
    candidates = [STAGE0 / token, ROOT / token]
    checked += 1
    if not any(c.exists() for c in candidates):
        print(f"MISSING path: {token}")
        problems += 1
print(f"paths checked: {checked}; missing: {problems}")

counts = {}
rows = []
in_section_2 = False
for line in text.splitlines():
    if line.startswith("## "):
        in_section_2 = line.startswith("## 2.")
    if not in_section_2 or not line.startswith("| "):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
    if not cells[0].isdigit():
        continue
    status = cells[2]
    rows.append((int(cells[0]), status))
    if status not in ALLOWED:
        print(f"BAD status in row {cells[0]}: {status}")
        problems += 1
    counts[status] = counts.get(status, 0) + 1

numbers = [n for n, _ in rows]
if numbers != list(range(1, len(numbers) + 1)):
    print(f"row numbers not consecutive: {numbers}")
    problems += 1
for n, s in rows:
    print(f"row {n}: {s}")
print(f"rows: {len(rows)}; " + ", ".join(f"{k} {counts[k]}" for k in sorted(counts)))
sys.exit(1 if problems else 0)
