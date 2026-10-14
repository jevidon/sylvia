#!/usr/bin/env bash
# G0.3: checks that what the current code writes and reads conforms to the contracts, not just the hand-written
# fixtures.
#   1. a handoff.json written now by the share extension's write routine (sylviapack-tool handoff, the same
#      HandoffSession code) validates against import-handoff-manifest.v1;
#   2. the manifest inside the generated large pack validates against sylviapack-manifest.v1, and its
#      sylviapack/manifest.sha256 entry is the SHA-256 of the manifest bytes plus a line feed;
#   3. differential check (review R2-04): edge inputs (every string bound at, below and above its limit in ASCII and
#      in non-ASCII text, orders, RFC 3339 date-times, path and file-name byte limits, the rules the schemas leave to
#      readers) go through the schemas and through the Swift readers (sylviapack-tool check-manifest). The verdicts
#      must agree, except where a divergence is documented: the schema accepts and the reader refuses, either because
#      the schema's description leaves the rule to readers, or because of a Python validator quirk (`$` matches before
#      a final line feed in Python's re module, not in ECMA-262, the regular-expression dialect JSON Schema names).
#
#   Spikes/G03-Intake/scripts/check-contract-instances.sh
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"
pack="$SYLVIA_FIXTURE_CACHE/generated/g03-intake/large.sylviapack"
work="$SYLVIA_ROOT/.build/g03-contract-check"
[[ -f "$pack" ]] || { echo "missing $pack; run Scripts/fixtures/generate-g03-intake-pack.sh" >&2; exit 1; }

(cd "$kit" && swift build --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"
rm -rf "$work"; mkdir -p "$work/inbox"
"$tool" handoff "$work/inbox" "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" "$SYLVIA_ROOT/Fixtures/audio/meditations-01-first180s.mp3"
handoff="$(find "$work/inbox" -name handoff.json)"

sylvia_python - "$SYLVIA_ROOT/Contracts" "$handoff" "$pack" <<'PY'
import hashlib, json, pathlib, sys, zipfile
from jsonschema import Draft202012Validator, FormatChecker

contracts, handoff, pack = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]

def validator(name):
    schema = json.loads((contracts / "schemas" / f"{name}.schema.json").read_text())
    return Draft202012Validator(schema, format_checker=FormatChecker())

failures = 0
def check(label, name, document):
    global failures
    errors = list(validator(name).iter_errors(document))
    print(f"{label}: {'valid' if not errors else 'INVALID'} against {name}")
    for e in errors:
        print("  ", "/".join(map(str, e.absolute_path)) or "(root)", e.message)
    failures += len(errors)

check("handoff.json written by HandoffSession now", "import-handoff-manifest.v1", json.loads(handoff.read_text()))
with zipfile.ZipFile(pack) as z:
    names = z.namelist()
    manifest_bytes = z.read("sylviapack/manifest.json")
    digest_entry = z.read("sylviapack/manifest.sha256")
print(f"large pack entries: {names[:2]} then {len(names) - 2} content entries")
check("large pack sylviapack/manifest.json", "sylviapack-manifest.v1", json.loads(manifest_bytes))
expected = (hashlib.sha256(manifest_bytes).hexdigest() + "\n").encode()
ok = digest_entry == expected
print(f"manifest.sha256 entry equals SHA-256(manifest.json) + LF: {ok}")
failures += 0 if ok else 1
sys.exit(1 if failures else 0)
PY

echo
echo "differential check (schema verdict vs Swift reader verdict on edge inputs):"
cases="$work/cases"
mkdir -p "$cases/pack" "$cases/handoff"
sylvia_python - "$SYLVIA_ROOT/Contracts" "$cases" <<'PY'
import copy, json, pathlib, sys
from jsonschema import Draft202012Validator, FormatChecker

contracts, cases = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
def load(rel): return json.loads((contracts / "fixtures" / rel).read_text())
def validator(name):
    return Draft202012Validator(json.loads((contracts / "schemas" / f"{name}.schema.json").read_text()),
                                format_checker=FormatChecker())
schemas = {"pack": validator("sylviapack-manifest.v1"), "handoff": validator("import-handoff-manifest.v1")}
bases = {"pack": load("sylviapack-manifest.v1/valid/publication-and-audiobook.json"),
         "handoff": load("import-handoff-manifest.v1/valid/one-file-representation.json")}
plan = []

def add(kind, name, mutate, expect, note=""):
    document = copy.deepcopy(bases[kind])
    mutate(document)
    (cases / kind / f"{name}.json").write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
    plan.append({"kind": kind, "name": name, "expect": expect, "note": note,
                 "schema": "valid" if schemas[kind].is_valid(document) else "invalid"})

def setter(keys, value):
    def mutate(document):
        target = document
        for key in keys[:-1]:
            target = target[key]
        target[keys[-1]] = value
    return mutate

E = "é"   # one code point, two UTF-8 bytes
bounds = {
    "pack": [("generator.name", ["generator", "name"], 1, 128), ("generator.version", ["generator", "version"], 1, 64),
             ("media_type", ["files", 0, "media_type"], 1, 128), ("title", ["groups", 0, "title"], 0, 1024),
             ("creator", ["groups", 0, "creators", 0], 0, 512), ("language", ["groups", 0, "language"], 0, 35),
             ("identifier.scheme", ["groups", 0, "identifiers", 0, "scheme"], 1, 64),
             ("identifier.value", ["groups", 0, "identifiers", 0, "value"], 1, 512)],
    "handoff": [("bundle_identifier", ["producer", "bundle_identifier"], 1, 255),
                ("build_version", ["producer", "build_version"], 1, 64),
                ("content_type", ["items", 0, "content_type"], 1, 128),
                ("provider_type_identifier", ["items", 0, "provider_type_identifier"], 1, 128)],
}
for kind, fields in bounds.items():
    for label, keys, low, high in fields:
        lengths = sorted({n for n in (low - 1, low, high, high + 1) if n >= 0})
        for n in lengths:
            add(kind, f"{label}-ascii-{n}", setter(keys, "a" * n), "agree")
        for n in (high, high + 1):
            add(kind, f"{label}-nonascii-{n}cp-{2 * n}bytes", setter(keys, E * n), "agree")

for order in (-1, 0, 1):
    add("pack", f"order-{order}-publication-member", setter(["files", 0, "order"], order), "agree")

dates_ok = ["2026-10-06T12:00:00Z", "2026-10-06T12:00:00.5Z", "2026-10-06t12:00:00z", "2026-10-06T12:00:00+13:00",
            "2026-10-06T12:00:00-00:00", "2026-10-06T15:30:00.123456789+13:00", "2024-02-29T00:00:00Z"]
dates_bad = ["2026-02-30T12:00:00Z", "2025-02-29T00:00:00Z", "2026-10-06T24:00:00Z", "2026-10-06T12:00:60Z",
             "2026-10-06T12:00:00+1300", "2026-10-06T12:00:00+24:00", "2026-10-06T12:00:00", "2026-10-06 12:00:00Z",
             "2026-10-06T12:00:00.Z", "0000-01-01T00:00:00Z", "20261006T120000Z", "6 October 2026"]
for kind in ("pack", "handoff"):
    for i, value in enumerate(dates_ok + dates_bad):
        add(kind, f"created_at-{'ok' if value in dates_ok else 'bad'}-{i:02d}", setter(["created_at"], value), "agree",
            value)

# Paths (pack) and file names (handoff): byte limits the schemas cannot express (documented in their descriptions).
c255, c254, c256 = E * 127 + "a", E * 127, E * 128
paths = [
    ("path-ascii-512bytes", "a" * 250 + "/" + "c" * 250 + "/bbbbbb.txt", "agree"),
    ("path-ascii-513bytes", "a" * 250 + "/" + "c" * 250 + "/bbbbbbb.txt", "agree"),
    ("path-nonascii-512bytes-258cp", c255 + "/" + c254 + "/a", "agree"),
    ("path-nonascii-513bytes-259cp", c255 + "/" + c255 + "/a", "documented"),
    ("path-example-607bytes-307cp", E * 100 + "/" + E * 100 + "/" + E * 100 + ".epub", "documented"),
    ("path-component-255bytes", "Book/" + c255, "agree"),
    ("path-component-256bytes-128cp", "Book/" + c256, "documented"),
    ("path-sixteen-components", "/".join(f"d{i}" for i in range(1, 16)) + "/f.txt", "agree"),
]
for name, value, expect in paths:
    add("pack", name, setter(["files", 0, "path"], value), expect)
names = [
    ("original_filename-ascii-255bytes", "M" * 250 + ".epub", "agree"),
    ("original_filename-ascii-256bytes", "M" * 251 + ".epub", "agree"),
    ("original_filename-nonascii-255bytes-128cp", c255, "agree"),
    ("original_filename-nonascii-256bytes-128cp", c256, "documented"),
    ("original_filename-empty", "", "agree"),
]
for name, value, expect in names:
    add("handoff", name, setter(["items", 0, "original_filename"], value), expect)

# Rules the schemas' descriptions leave to readers: the schema accepts, the reader refuses.
def pack_rule(name, mutate):
    add("pack", name, mutate, "documented")
pack_rule("rule-path-not-nfc", setter(["files", 0, "path"], "Walden/se-waldén.epub"))
pack_rule("rule-paths-equal-ignoring-case", lambda d: d["files"][2].__setitem__("path", d["files"][1]["path"].upper()))
pack_rule("rule-file-is-also-a-folder", setter(["files", 1, "path"], "Walden/se-walden.epub/01.mp3"))
pack_rule("rule-total-size-not-the-sum", setter(["total_size"], 1))
pack_rule("rule-unknown-group-id", setter(["files", 0, "group_id"], "nowhere"))
pack_rule("rule-audio-member-without-order", lambda d: d["files"][1].pop("order"))
pack_rule("rule-duplicate-member-order", setter(["files", 2, "order"], 1))
pack_rule("rule-epub-in-audiobook-group", setter(["files", 0, "group_id"], "meditations-audio"))
pack_rule("rule-order-without-group", lambda d: (d["files"][0].pop("group_id"), d["files"][0].__setitem__("order", 1)))
pack_rule("rule-epub-over-1gib", lambda d: (d["files"][0].__setitem__("size", (1 << 30) + 1),
                                            d.__setitem__("total_size", d["total_size"] + (1 << 30) + 1 - 997147)))
add("handoff", "rule-duplicate-stored-path",
    lambda d: d["items"].append(dict(d["items"][0], item_id="6F1E8D2B-3C4A-4B0D-9E8F-7A6B5C4D3E21")) or
              d.__setitem__("total_bytes", 2 * d["total_bytes"]), "documented")
add("handoff", "rule-total-bytes-not-the-sum", setter(["total_bytes"], 1), "documented")

# Python's re: `$` also matches before a final line feed (ECMA-262, which JSON Schema names, does not).
add("pack", "quirk-sha256-trailing-line-feed", lambda d: d["files"][0].__setitem__("sha256", d["files"][0]["sha256"] + "\n"),
    "quirk")
add("handoff", "quirk-stored-path-trailing-line-feed", setter(["items", 0, "stored_path"], "items/0.epub\n"), "quirk")

(cases / "plan.json").write_text(json.dumps(plan))
print(f"  {len(plan)} cases written")
PY
"$tool" check-manifest pack "$cases"/pack/*.json > "$cases/reader.txt"
"$tool" check-manifest handoff "$cases"/handoff/*.json >> "$cases/reader.txt"
sylvia_python - "$cases" <<'PY'
import json, pathlib, sys
cases = pathlib.Path(sys.argv[1])
plan = json.loads((cases / "plan.json").read_text())
reader = {}
for line in (cases / "reader.txt").read_text().splitlines():
    verdict, rest = line.split(" ", 1)
    name = rest.split(":", 1)[0].removesuffix(".json")
    reader[name] = (verdict, rest.split(":", 1)[1].strip() if ":" in rest else "")
failures = 0
counts = {}
for case in plan:
    verdict, reason = reader[case["name"]]
    schema_ok = case["schema"] == "valid"
    reader_ok = verdict == "accepted"
    if case["expect"] == "agree":
        good = schema_ok == reader_ok
    else:   # documented divergence or validator quirk: the schema accepts, the reader refuses
        good = schema_ok and not reader_ok
    counts[(case["expect"], good)] = counts.get((case["expect"], good), 0) + 1
    failures += 0 if good else 1
    note = f" [{case['note']}]" if case["note"] else ""
    print(f"  {'ok' if good else 'MISMATCH'}: {case['kind']} {case['name']}{note}: schema={case['schema']} "
          f"reader={verdict}{(' (' + reason + ')') if reason else ''} expected={case['expect']}")
for expect in ("agree", "documented", "quirk"):
    print(f"differential: {expect}: {counts.get((expect, True), 0)} as expected, {counts.get((expect, False), 0)} not")
print(f"differential: {len(plan)} cases, mismatches={failures}")
sys.exit(1 if failures else 0)
PY
rm -rf "$work"
