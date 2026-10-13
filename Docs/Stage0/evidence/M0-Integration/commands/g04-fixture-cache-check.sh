#!/usr/bin/env bash
# G0.4 merge (M0 integration): check the generated G0.4 fixtures in $SYLVIA_FIXTURE_CACHE against the manifests beside
# them and against the manifests the committed generation logs recorded, and the LibriVox downloads the G0.4 tests use.
# Read-only. Run from anywhere:
#   Docs/Stage0/evidence/M0-Integration/commands/g04-fixture-cache-check.sh > Docs/Stage0/evidence/M0-Integration/g04-fixture-cache-check.log
set -euo pipefail
cd "$(dirname "$0")/../../../../.."
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh

BASE="$SYLVIA_FIXTURE_CACHE/generated/g04-audio"
EVID="Docs/Stage0/evidence/G04-Audio"
echo "# Command: Docs/Stage0/evidence/M0-Integration/commands/g04-fixture-cache-check.sh; started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# Environment: host, macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(ffmpeg -version | head -1)"
echo "# Host load: $(uptime | sed 's/^ *//')"
echo "# Commit: $(git rev-parse HEAD)"
status=0
total_files=0
total_bytes=0
for entry in "main|$BASE|$EVID/fixture-generation.log" \
             "long-formats|$BASE/long-formats|$EVID/fixture-generation-long-formats.log" \
             "probes|$BASE/probes|$EVID/fixture-generation-probes.log"; do
  IFS='|' read -r label dir log <<<"$entry"
  manifest="$dir/manifest.tsv"
  echo "== $label: ${manifest#"$SYLVIA_FIXTURE_CACHE"/} (under \$SYLVIA_FIXTURE_CACHE)"
  echo "stamp: $(cat "$dir/.stamp")"
  rows=0; ok=0; bytes=0
  while IFS=$'\t' read -r f sha size _; do
    [[ -z "$f" || "$f" == \#* ]] && continue
    rows=$((rows + 1))
    got="$(shasum -a 256 "$dir/$f" | awk '{print $1}')"
    actual_size="$(stat -f %z "$dir/$f")"
    if [[ "$got" == "$sha" && "$actual_size" == "$size" ]]; then
      ok=$((ok + 1)); bytes=$((bytes + actual_size))
    else
      echo "MISMATCH $f: manifest $sha $size, file $got $actual_size"; status=1
    fi
  done < "$manifest"
  echo "files: $rows listed, $ok match their SHA-256 and size; $bytes bytes"
  total_files=$((total_files + ok)); total_bytes=$((total_bytes + bytes))
  # The committed log holds the manifest the gate's generation printed (the probe log holds two identical
  # generations): compare the file, SHA-256 and byte columns, each distinct row once.
  if diff <(grep -v '^#' "$manifest" | awk -F'\t' 'NF >= 3 {print $1"\t"$2"\t"$3}' | LC_ALL=C sort -u) \
          <(grep -E $'^[^#\t ][^\t]*\t[0-9a-f]{64}\t[0-9]+' "$log" | awk -F'\t' '{print $1"\t"$2"\t"$3}' | LC_ALL=C sort -u); then
    echo "the cache manifest equals the manifest recorded in $log (file, SHA-256, bytes)"
  else
    echo "the cache manifest differs from $log"; status=1
  fi
done
echo "all generated G0.4 fixtures: $total_files files, $total_bytes bytes"
echo "== downloads the G0.4 generators and tests read (Scripts/fixtures/manifest.tsv)"
while IFS=$'\t' read -r f sha size _; do
  [[ -z "$f" || "$f" == \#* ]] && continue
  got="$(shasum -a 256 "$SYLVIA_FIXTURE_CACHE/downloads/$f" | awk '{print $1}')"
  if [[ "$got" == "$sha" ]]; then echo "ok $f ($size bytes)"; else echo "MISMATCH $f: $got"; status=1; fi
done < Scripts/fixtures/manifest.tsv
echo "# finished $(date -u +%Y-%m-%dT%H:%M:%SZ); exit $status"
exit "$status"
