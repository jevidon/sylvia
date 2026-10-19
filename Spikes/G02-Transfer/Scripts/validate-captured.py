#!/usr/bin/env python3
"""Validate payloads captured from the running source service against the G0.2 JSON Schemas.

The host tests write real responses (and requests, with secrets replaced by placeholders of the same
shape) to Docs/Stage0/evidence/G02-Transfer/captured/. This checks every one of them against its schema
in Contracts/schemas/, so the Swift implementation and the published contract cannot drift apart.

    validate-captured.py <captured-dir> <schemas-dir>

Exit status is non-zero if a file has no schema, fails validation, or an expected capture is missing.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

# File name prefix -> schema name. Longest prefix wins.
PREFIXES = {
    "capabilities": "capabilities",
    "catalog-page": "catalog-page",
    "device-inbox-page": "device-inbox-page",
    "error-": "error",
    "pair-request": "pair-request",
    "pair-response": "pair-response",
    "pairing-payload": "pairing-payload",
    "receipt-": "receipt",
    "receipt-ack-": "receipt-ack",
    "transfer-manifest": "transfer-manifest",
}

# Every schema must be exercised by at least one capture.
EXPECTED = set(PREFIXES.values())


def main(captured: Path, schemas: Path) -> int:
    failures: list[str] = []
    covered: set[str] = set()
    files = sorted(captured.glob("*.json"))
    for path in files:
        matches = [prefix for prefix in PREFIXES if path.name.startswith(prefix)]
        if not matches:
            failures.append(f"{path.name}: no schema mapping")
            continue
        name = PREFIXES[max(matches, key=len)]
        schema = json.loads((schemas / f"{name}.v1.schema.json").read_text(encoding="utf-8"))
        instance = json.loads(path.read_text(encoding="utf-8"))
        errors = sorted(Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(instance),
                        key=lambda e: list(e.absolute_path))
        if errors:
            first = errors[0]
            failures.append(f"{path.name}: {name}.v1: {'/'.join(map(str, first.absolute_path)) or '(root)'}: {first.message}")
        else:
            covered.add(name)
            print(f"valid  {path.name}  ({name}.v1)")
    for name in sorted(EXPECTED - covered):
        failures.append(f"no valid capture for {name}.v1")
    for failure in failures:
        print(f"FAIL   {failure}")
    print(f"{len(files)} captured payloads, {len(covered)} of {len(EXPECTED)} schemas covered, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
