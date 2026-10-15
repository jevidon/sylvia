#!/usr/bin/env bash
# G0.3: checks that what the current code writes and reads conforms to the contracts, not just the hand-written
# fixtures.
#   1. a handoff.json written now by the share extension's write routine (sylviapack-tool handoff, the same
#      HandoffSession code) validates against import-handoff-manifest.v1;
#   2. the manifest inside the generated large pack validates against sylviapack-manifest.v1, and its
#      sylviapack/manifest.sha256 entry is the SHA-256 of the manifest bytes plus a line feed;
#   3. differential check (reviews R2-04, R3-01, R3-02, R4-01 to R4-03; contract_differential.py beside this script):
#      named edge inputs and seeded random mutations go through the schemas, judged as Scripts/validate-contracts.py
#      would judge them as fixtures, and through the Swift readers (sylviapack-tool check-manifest, which applies the
#      readers' size limits too). A named case must give its expected outcome; a random one must agree or be refused by
#      the reader for a reason in a documented class. A manifest a reader accepts and its schema refuses always fails.
#      Every created_at both sides accept must decode to Python's proleptic Gregorian instant (sylviapack-tool
#      created-at).
#
#   Spikes/G03-Intake/scripts/check-contract-instances.sh
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"
pack="$SYLVIA_FIXTURE_CACHE/generated/g03-intake/large.sylviapack"
[[ -f "$pack" ]] || { echo "missing $pack; run Scripts/fixtures/generate-g03-intake-pack.sh" >&2; exit 1; }
mkdir -p "$SYLVIA_ROOT/.build"
work="$(mktemp -d "$SYLVIA_ROOT/.build/g03-contract-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT

(cd "$kit" && swift build --force-resolved-versions --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"
mkdir -p "$work/inbox"
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
echo "differential check (schema verdict vs Swift reader verdict):"
mkdir -p "$work/differential"
sylvia_python "$(dirname "$0")/contract_differential.py" "$SYLVIA_ROOT/Contracts" "$work/differential" "$tool"
