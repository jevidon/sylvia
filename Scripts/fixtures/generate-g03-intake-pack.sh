#!/usr/bin/env bash
# Generates the G0.3 large .sylviapack fixture (above 4 GiB) into the fixture cache. Deterministic: the same
# inputs always give a byte-identical pack, checked against the pinned SHA-256 below.
#
#   Scripts/fixtures/generate-g03-intake-pack.sh            # build if missing or wrong, then verify
#   Scripts/fixtures/generate-g03-intake-pack.sh --force    # rebuild
#
# Output ($SYLVIA_FIXTURE_CACHE/generated/g03-intake/):
#   large.sylviapack     ~4.52 GiB pack: audiobook group of two generated CAF files (part-01 is 4.5 GiB, stored),
#                        generated Markdown and text (deflated), and LibriVox Meditations section 01 (public domain,
#                        pinned by Scripts/fixtures/fetch.sh).
#   work/part-01.caf     the 4.5 GiB generated CAF itself (used as the multi-GiB source for copy-memory runs)
# Content: CAF files are 44.1 kHz mono 16-bit LPCM, a quiet 441 Hz tone plus low-level SplitMix64 noise (seeded),
# written by `sylviapack-tool make-caf`; text files are fixed strings. No third-party content except the LibriVox
# file. Disk: about 9.1 GiB while both files exist.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

out_dir="$SYLVIA_FIXTURE_CACHE/generated/g03-intake"
pack="$out_dir/large.sylviapack"
work="$out_dir/work"
audio_bytes=$((4 * 1024 * 1024 * 1024 + 512 * 1024 * 1024 + 778))   # 4.5 GiB + 778 bytes (header + odd tail)
librivox="$SYLVIA_FIXTURE_CACHE/downloads/meditationsofmarcusaurelius_01_aurelius_64kb.mp3"
expected_sha="982562b020ea7213721661fa0a6adf4d7a81c9bf68e5eda498bc417beebf0268"   # 4846059727 bytes
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"

if [[ "${1:-}" != "--force" && -f "$pack" ]]; then
  actual="$(shasum -a 256 "$pack" | awk '{print $1}')"
  if [[ "$actual" == "$expected_sha" && -f "$work/part-01.caf" ]]; then
    echo "ok       $pack ($actual)"
    exit 0
  fi
fi

"$SYLVIA_ROOT/Scripts/fixtures/fetch.sh" meditationsofmarcusaurelius_01 >/dev/null
mkdir -p "$out_dir" "$work"
(cd "$kit" && swift build --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"

rm -f "$pack"
"$tool" gen-pack "$pack" "$work" "$audio_bytes" \
  "$librivox" "LibriVox Meditations/meditations-01.mp3" audio audio/mpeg
echo "afinfo part-01.caf:"
afinfo "$work/part-01.caf" | grep -E 'File type|Data format|estimated duration|audio bytes' | sed 's/^/  /'
rm -f "$work/part-02.caf" "$work/notes.md" "$work/chapter.txt"

actual="$(shasum -a 256 "$pack" | awk '{print $1}')"
size="$(stat -f %z "$pack")"
echo "pack: $pack"
echo "size: $size bytes"
echo "sha256: $actual"
if [[ "$actual" != "$expected_sha" ]]; then
  echo "MISMATCH: expected $expected_sha" >&2
  exit 1
fi
echo "matches the pinned digest"
