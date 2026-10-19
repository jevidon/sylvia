#!/usr/bin/env python3
"""Which timestamp spellings each contract's timestamp definition accepts (M0 final review, contracts R1-02), with
the repository's own validator settings (jsonschema Draft 2020-12 with its FormatChecker), as Contracts/README.md's
units exceptions state them.

    <tools venv python> -I timestamp-forms.py <repository root>
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(sys.argv[1])
# contract -> JSON Pointer of one timestamp definition in it (every timestamp field of a contract uses that form)
DEFINITIONS = {
    "transfer-manifest (G0.2)": ("transfer-manifest.v1", "/$defs/timestamp"),
    "receipt (G0.2)": ("receipt.v1", "/properties/occurred_at"),
    "capture-envelope": ("capture-envelope.v1", "/$defs/utc_timestamp"),
    "backup-manifest": ("backup-manifest.v1", "/$defs/utc_timestamp"),
    "context-pack": ("context-pack.v1", "/properties/created_at"),
    "import-handoff-manifest (G0.3)": ("import-handoff-manifest.v1", "/properties/created_at"),
    "sylviapack-manifest (G0.3)": ("sylviapack-manifest.v1", "/properties/created_at"),
}
SAMPLES = [
    "2026-10-05T00:00:00Z",
    "2026-10-05T00:00:00.123456789Z",
    "2026-10-05T00:00:00.1234567890Z",
    "2026-10-05t00:00:00Z",
    "2026-10-05T00:00:00z",
    "2026-10-06T15:00:00.5+13:00",
    "2026-10-05T00:00:00+00:00",
]


def node(document, pointer):
    for part in pointer.strip("/").split("/"):
        document = document[part]
    return document


def main():
    header = "| Timestamp | " + " | ".join(DEFINITIONS) + " |"
    print(header)
    print("| --- |" + " --- |" * len(DEFINITIONS))
    validators = {}
    for label, (stem, pointer) in DEFINITIONS.items():
        schema = json.loads((ROOT / "Contracts/schemas" / f"{stem}.schema.json").read_text(encoding="utf-8"))
        validators[label] = Draft202012Validator(node(schema, pointer), format_checker=FormatChecker())
    for sample in SAMPLES:
        cells = ["accepted" if validators[label].is_valid(sample) else "refused" for label in DEFINITIONS]
        print(f"| `{sample}` | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
