#!/usr/bin/env python3
"""Rule A3 of anchor.v1 before and after the M0 final fix (final review R1-02), on every composed selection the G0.1
PDF spike stores exactly.

    python3 -I a3-composed-check.py <repository root> <checker before> <checker after>

Loads two copies of Scripts/check-spike-anchors.py (the one at the reviewed commit, and the current one), adapts every
anchor of Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json and anchor-samples.json as the checker adapts
spike output, and prints each one's A3 violations under both. Then the counterexample the review gave: the "\n"-joined
text of two pieces on one page, which the ranges cannot give back (ADR-0005), and the same anchor with a space, two
line feeds or no line feed at a page change. Run from commands/a3-composed-check.sh, which extracts the reviewed
checker with git show. Exit status 0 when the current checker accepts every real anchor and refuses every planted
text the commentary below calls refused.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module


def a3(checker, anchor) -> list[str]:
    return [message for rule, message in checker.anchor_violations(anchor) if rule == "A3"]


def main() -> int:
    root, before_path, after_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    before, after = load(before_path, "checker_before"), load(after_path, "checker_after")
    log = after.Adaptations()
    status = 0
    print(f"checker before: {before_path.name}; checker after: {after_path.relative_to(root)}")
    print(f"rule A3 before: {before.RULES['A3']}")
    print(f"rule A3 after:  {after.RULES['A3']}")
    real = []
    for source in ("anchor-composed-samples.json", "anchor-samples.json"):
        doc = json.loads((root / "Docs/Stage0/evidence/G01-PDF" / source).read_text(encoding="utf-8"))
        print(f"--- {source} ({doc['environment']})")
        for sample in doc["samples"]:
            anchor = after.adapt_pdf_anchor(sample["anchor"], after.fixture_uuid("w"), after.fixture_uuid("e"), log)
            real.append((sample["name"], anchor))
            old, new = a3(before, anchor), a3(after, anchor)
            pieces = len(anchor["segments"])
            print(f"{sample['name']}: {pieces} segment(s), text {json.dumps(anchor['exact_text'])}; "
                  f"before: {'refused (' + old[0] + ')' if old else 'accepted'}; after: {'refused (' + new[0] + ')' if new else 'accepted'}")
            if new:
                status = 1
    refused_before = sum(1 for _, a in real if a3(before, a))
    print(f"real anchors: {len(real)}; refused by A3 before: {refused_before}; refused after: "
          f"{sum(1 for _, a in real if a3(after, a))}")

    print("--- planted texts on real anchors (each must be refused after)")
    by_name = dict(real)
    one_page = by_name["two pieces on one page, two lines apart"]
    two_pages = by_name["multi-page"]
    planted = [
        ("two pieces on one page claiming the \"\\n\"-joined text, which the ranges cannot give back (ADR-0005)", one_page,
         "\n".join(s["text"] for s in one_page["segments"]), False),
        ("two pieces on one page joined by a space", one_page, " ".join(s["text"] for s in one_page["segments"]), True),
        ("two pieces on one page joined by two line feeds", one_page, "\n\n".join(s["text"] for s in one_page["segments"]), True),
        ("two pieces on one page in the wrong order", one_page, "".join(s["text"] for s in reversed(one_page["segments"])), True),
        ("two pages with no line feed where the page changes", two_pages, "".join(s["text"] for s in two_pages["segments"]), True),
        ("two pages joined by a space", two_pages, " ".join(s["text"] for s in two_pages["segments"]), True),
    ]
    for name, base, text, must_refuse in planted:
        anchor = copy.deepcopy(base)
        anchor["exact_text"] = text
        old, new = a3(before, anchor), a3(after, anchor)
        verdict = "refused" if new else "accepted"
        note = ""
        if not must_refuse:
            note = (" (a structural rule cannot tell this from PDFKit's kept line break; the reader's restore check, "
                    "quotationMismatch, refuses it: ADR-0005)")
        print(f"{name}: before: {'refused' if old else 'accepted'}; after: {verdict}{note}")
        if must_refuse and not new:
            status = 1
    print(f"result: {'pass' if status == 0 else 'FAIL'}")
    return status


if __name__ == "__main__":
    sys.exit(main())
