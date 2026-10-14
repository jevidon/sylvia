"""G0.3: one reason per invalid fixture (Contracts/README.md), checked for G0.3's two contracts.

    sylvia_python Spikes/G03-Intake/scripts/fixture-reasons.py <repository root>

For every fixture of import-handoff-manifest.v1 and sylviapack-manifest.v1, lists the schema's errors (jsonschema, Draft
2020-12, with format checks, as Scripts/validate-contracts.py validates): a valid fixture must have none, an invalid one
exactly one, printed with its location and keyword so that it can be read against the fixture's name. Not run by CI;
its output is evidence/G03-Intake/contract-fixture-reasons.log (review round 3).
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator, FormatChecker

root = pathlib.Path(sys.argv[1])
bad = 0
counts = {}
for name in ("import-handoff-manifest.v1", "sylviapack-manifest.v1"):
    schema = json.loads((root / "Contracts/schemas" / f"{name}.schema.json").read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    for kind in ("valid", "invalid"):
        paths = sorted((root / "Contracts/fixtures" / name / kind).glob("*.json"))
        counts[(name, kind)] = len(paths)
        for path in paths:
            errors = list(validator.iter_errors(json.loads(path.read_text(encoding="utf-8"))))
            where = "; ".join(f"{'/'.join(map(str, e.absolute_path)) or '(root)'}: {e.validator}" for e in errors)
            ok = len(errors) == (0 if kind == "valid" else 1)
            bad += 0 if ok else 1
            print(f"{'ok ' if ok else 'BAD'} {name}/{kind}/{path.name}: {len(errors)} error(s){': ' + where if where else ''}")
for (name, kind), count in counts.items():
    print(f"{name} {kind}: {count}")
print(f"fixtures not as expected: {bad}")
sys.exit(1 if bad else 0)
