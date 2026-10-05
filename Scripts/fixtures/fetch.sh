#!/usr/bin/env bash
# Downloads the large fixtures listed in manifest.tsv into $SYLVIA_FIXTURE_CACHE/downloads and verifies
# each SHA-256. Re-running is cheap: verified files are skipped. Exits non-zero on any mismatch.
#
#   Scripts/fixtures/fetch.sh              # everything
#   Scripts/fixtures/fetch.sh m4b          # only names containing "m4b"
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

dest="$SYLVIA_FIXTURE_CACHE/downloads"
mkdir -p "$dest"
filter="${1:-}"
status=0

while IFS=$'\t' read -r name sha size url; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [[ -n "$filter" && "$name" != *"$filter"* ]] && continue
  file="$dest/$name"
  if [[ -f "$file" ]] && [[ "$(shasum -a 256 "$file" | awk '{print $1}')" == "$sha" ]]; then
    echo "ok       $name"
    continue
  fi
  echo "fetching $name ($size bytes)"
  curl --fail --location --silent --show-error --retry 3 --output "$file.partial" "$url"
  actual="$(shasum -a 256 "$file.partial" | awk '{print $1}')"
  if [[ "$actual" != "$sha" ]]; then
    echo "MISMATCH $name: expected $sha, got $actual" >&2
    rm -f "$file.partial"
    status=1
    continue
  fi
  mv "$file.partial" "$file"
  echo "ok       $name"
done < "$SYLVIA_ROOT/Scripts/fixtures/manifest.tsv"

exit "$status"
