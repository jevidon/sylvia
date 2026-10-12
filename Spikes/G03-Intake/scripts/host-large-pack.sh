#!/usr/bin/env bash
# G0.3 host run on the >4 GiB pack (T42 host half, deliverables 2 and 4):
#   validate and extract with memory sampling, independent cross-checks (Python zipfile, shasum of the extracted
#   file), truncated and zero-padded copies at structural boundaries and spread offsets, and the multi-GiB copy
#   through the share extension's write routine with memory sampling.
#
#   Spikes/G03-Intake/scripts/host-large-pack.sh [log]
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
log="${1:-$SYLVIA_ROOT/Docs/Stage0/evidence/G03-Intake/host-large-pack.log}"
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1

cache="$SYLVIA_FIXTURE_CACHE/generated/g03-intake"
pack="$cache/large.sylviapack"
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"
# A working directory of this run's own (next to the pack, so the truncation sweep's clones stay on its volume), removed
# on exit: two runs at once (two worktrees, a reviewer) never touch each other's files.
run="$(mktemp -d "$cache/host-run.XXXXXX")"
trap 'rm -rf "$run"' EXIT

echo "# G0.3 host large-pack run"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "environment: host, $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.memsize) bytes RAM"
"$SYLVIA_ROOT/Scripts/fixtures/generate-g03-intake-pack.sh"
(cd "$kit" && swift build --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"

echo; echo "## 1. Validate (streaming SHA-256 of every entry, no extraction)"
"$tool" validate "$pack"

echo; echo "## 2. Extract while validating"
"$tool" validate "$pack" --extract "$run/extracted"
echo "independent check: shasum of the extracted 4.5 GiB file vs the generator's source file"
a="$(shasum -a 256 "$run/extracted/Generated Audiobook/part-01.caf" | awk '{print $1}')"
b="$(shasum -a 256 "$cache/work/part-01.caf" | awk '{print $1}')"
echo "  extracted=$a"; echo "  source   =$b"
[[ "$a" == "$b" ]] || { echo "MISMATCH"; exit 1; }
echo "extracted modes: $(find "$run/extracted" -type f -exec stat -f '%Sp' {} \; | sort | uniq -c | tr '\n' ' ')"
rm -rf "$run/extracted"

echo; echo "## 3. Independent reader (Python zipfile): entry list and ZIP64 records"
/usr/bin/python3 - "$pack" <<'PY'
import struct, sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path) as z:
    for i in z.infolist():
        print(f"  {i.filename}: method={i.compress_type} size={i.file_size} compressed={i.compress_size} offset={i.header_offset} mode={oct(i.external_attr >> 16)}")
with open(path, 'rb') as f:
    f.seek(-22, 2); eocd = f.read(22)
    f.seek(-42, 2); loc = f.read(20)
end_ok = eocd[:4] == bytes([0x50, 0x4B, 0x05, 0x06])
comment = struct.unpack('<H', eocd[20:22])[0]
locator_ok = loc[:4] == bytes([0x50, 0x4B, 0x06, 0x07])
print(f"  end record in the last 22 bytes={end_ok} comment_length={comment}")
print(f"  ZIP64 end-record locator directly before it={locator_ok}")
PY

echo; echo "## 4. Truncated and zero-padded copies (APFS clones)"
"$tool" truncation-sweep "$pack" "$run/sweep" 100

echo; echo "## 5. Multi-GiB copy through the share extension's write routine (HandoffSession, 1 MiB buffer)"
"$tool" copy-measure "$run/inbox" "$cache/work/part-01.caf"
echo
echo "Documented comparison: Apple does not publish a numeric memory limit for share extensions; see the G0.3 report."
echo "host large-pack run finished"
