#!/usr/bin/env python3
"""Checks the backup-manifest.v1 contract against real output and its fixtures.

Usage: check_manifest_contract.py <repo root> <manifest.json produced by the Swift exporter>...

1. Every manifest the Swift exporter wrote must validate against
   Contracts/schemas/backup-manifest.v1.schema.json (the code and the contract agree).
2. Every invalid fixture must fail for exactly one reason (Contracts/README.md: one reason per
   file). A reason is one rule of the schema: the schema path of a leaf error (the keyword where it
   stands in the schema), so two rules that both refuse a value at one location are two reasons
   (M0 final review, contracts R1-03: counting (location, keyword) pairs counted the generic path
   pattern and a role's path pattern as one reason).
   Recorded exception (DEFENCE_IN_DEPTH): the generic `$defs/relative_path` pattern is kept as
   defence in depth for a role added later without a path rule of its own. Every role defined now
   constrains its path more tightly, so a path that breaks the generic pattern also breaks its role's
   rule; the four path fixtures fail exactly those two rules, which this check requires.
Exit status is non-zero on any failure.
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator, FormatChecker

# Schema paths as jsonschema reports them, through the files' $ref to $defs/file and the path's to $defs/relative_path.
GENERIC_PATH = "properties/files/items/properties/path/pattern"
MARKDOWN_PATH = "properties/files/items/allOf/2/then/properties/path/pattern"
DEFENCE_IN_DEPTH = {
    name: {GENERIC_PATH, MARKDOWN_PATH}
    for name in ("absolute-path.json", "backslash-path.json", "dot-component-path.json", "path-traversal.json")
}


def leaves(error, out):
    if error.context:
        for child in error.context:
            leaves(child, out)
    else:
        out.add("/".join(map(str, error.schema_path)))


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
        expected = DEFENCE_IN_DEPTH.get(path.name)
        if expected is not None:
            ok = reasons == expected
            verdict = "the generic and the role's path rule (defence in depth)" if ok else "FAIL"
        else:
            ok = len(reasons) == 1
            verdict = "one reason" if ok else "FAIL"
        failures += not ok
        print(f"invalid fixture {path.name}: {verdict} {sorted(reasons)}")
    print("RESULT: PASS" if failures == 0 else f"RESULT: FAIL ({failures})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
