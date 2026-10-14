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
# file. Disk: about 9.1 GiB for the published files, and as much again while a rebuild runs.
#
# Overlapping runs (several worktrees, a reviewer, CI) are safe (G0.3 review R2-06):
#   - The whole check-and-build sequence holds an exclusive lock on .generate.lock in the output folder (flock(2)
#     through lockf(1)). The kernel releases it when the holding processes exit, killed or not; a second run waits.
#   - A rebuild writes into a private folder beside the cache (.rebuild.*, same volume), verifies the pinned digests
#     there, and only then publishes each file with one rename(2): part-01.caf first, the pack (which the quick check
#     reads) last. A reader that opens either path sees the previous complete file or the new one, never part of one,
#     and an interrupted rebuild leaves the published files as they were. Leftover .rebuild.* folders can only come
#     from an interrupted run (only the lock holder creates them), so the next lock holder removes them.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

out_dir="$SYLVIA_FIXTURE_CACHE/generated/g03-intake"
pack="$out_dir/large.sylviapack"
work="$out_dir/work"
caf="$work/part-01.caf"
audio_bytes=$((4 * 1024 * 1024 * 1024 + 512 * 1024 * 1024 + 778))   # 4.5 GiB + 778 bytes (header + odd tail)
librivox="$SYLVIA_FIXTURE_CACHE/downloads/meditationsofmarcusaurelius_01_aurelius_64kb.mp3"
expected_sha="982562b020ea7213721661fa0a6adf4d7a81c9bf68e5eda498bc417beebf0268"       # 4846059727 bytes
expected_caf_sha="b4e3eac6d299ef937eb52a103187a2847a63cc0084e9ab2d4c18d41bfa91bcc1"   # as listed in the pack's manifest
expected_caf_size=4831838986
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"

mkdir -p "$out_dir"
exec 9>>"$out_dir/.generate.lock"
if ! lockf -s -t 0 9; then
  echo "waiting for another run of this generator to finish (lock: $out_dir/.generate.lock)"
  lockf -s 9 || { echo "could not lock $out_dir/.generate.lock" >&2; exit 1; }
  echo "lock acquired"
fi
for leftover in "$out_dir"/.rebuild.*; do
  [[ -e "$leftover" ]] || continue
  echo "removing the leftovers of an interrupted rebuild: $leftover"
  rm -rf "$leftover"
done

if [[ "${1:-}" != "--force" && -f "$pack" && -f "$caf" && "$(stat -f %z "$caf")" == "$expected_caf_size" ]]; then
  actual="$(shasum -a 256 "$pack" | awk '{print $1}')"
  if [[ "$actual" == "$expected_sha" ]]; then
    echo "ok       $pack ($actual)"
    exit 0
  fi
fi

"$SYLVIA_ROOT/Scripts/fixtures/fetch.sh" meditationsofmarcusaurelius_01 >/dev/null
(cd "$kit" && swift build --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"

rebuild="$(mktemp -d "$out_dir/.rebuild.XXXXXX")"
trap 'rm -rf "$rebuild"' EXIT
"$tool" gen-pack "$rebuild/large.sylviapack" "$rebuild/work" "$audio_bytes" \
  "$librivox" "LibriVox Meditations/meditations-01.mp3" audio audio/mpeg
echo "afinfo part-01.caf:"
afinfo "$rebuild/work/part-01.caf" | grep -E 'File type|Data format|estimated duration|audio bytes' | sed 's/^/  /'

actual="$(shasum -a 256 "$rebuild/large.sylviapack" | awk '{print $1}')"
size="$(stat -f %z "$rebuild/large.sylviapack")"
caf_actual="$(shasum -a 256 "$rebuild/work/part-01.caf" | awk '{print $1}')"
echo "pack: $pack"
echo "size: $size bytes"
echo "sha256: $actual"
if [[ "$actual" != "$expected_sha" ]]; then
  echo "MISMATCH: expected $expected_sha" >&2
  exit 1
fi
echo "matches the pinned digest"
if [[ "$caf_actual" != "$expected_caf_sha" ]]; then
  echo "MISMATCH: part-01.caf $caf_actual, expected $expected_caf_sha" >&2
  exit 1
fi
echo "part-01.caf matches its pinned digest ($caf_actual)"

# Publish: one rename(2) per file on the same volume; part-01.caf first, the pack last.
mkdir -p "$work"
mv -f "$rebuild/work/part-01.caf" "$caf"
mv -f "$rebuild/large.sylviapack" "$pack"
echo "published by rename: $caf, then $pack"
