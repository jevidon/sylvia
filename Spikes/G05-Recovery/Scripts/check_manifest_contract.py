#!/usr/bin/env python3
"""Checks the backup-manifest.v1 contract against real output and its fixtures.

Usage: check_manifest_contract.py <repo root> <manifest.json produced by the Swift exporter>...

1. Every manifest the Swift exporter wrote must validate against
   Contracts/schemas/backup-manifest.v1.schema.json (the code and the contract agree).
2. Every invalid fixture must fail for exactly one reason (Contracts/README.md: one reason per
   file). Errors are reduced to (location, keyword) pairs; one distinct pair is one reason.
Exit status is non-zero on any failure.
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator, FormatChecker


def leaves(error, out):
    if error.context:
        for child in error.context:
            leaves(child, out)
    else:
        out.add(("/".join(map(str, error.absolute_path)) or "(root)", error.validator))


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    schema = json.loads((root / "Contracts/schemas/backup-manifest.v1.schema.json").read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    failures = 0
    for produced in sys.argv[2:]:
        errors = list(validator.iter_errors(json.loads(pathlib.Path(produced).read_text(encoding="utf-8"))))
        status = "valid" if not errors else f"INVALID: {errors[0].message}"
        print(f"exporter manifest {pathlib.Path(produced).parent.name}/manifest.json: {status}")
        failures += bool(errors)
    for path in sorted((root / "Contracts/fixtures/backup-manifest.v1/invalid").glob("*.json")):
        reasons = set()
        for error in validator.iter_errors(json.loads(path.read_text(encoding="utf-8"))):
            leaves(error, reasons)
        ok = len(reasons) == 1
        failures += not ok
        print(f"invalid fixture {path.name}: {'one reason' if ok else 'FAIL'} {sorted(reasons)}")
    print("RESULT: PASS" if failures == 0 else f"RESULT: FAIL ({failures})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
