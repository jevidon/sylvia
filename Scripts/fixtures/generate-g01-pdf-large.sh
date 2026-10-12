#!/usr/bin/env bash
# Generates the large text PDF for the G0.1 PDF spike's open-time measurement into the fixture cache:
#   $SYLVIA_FIXTURE_CACHE/generated/g01-pdf/large-1000.pdf
# 1,000 US Letter pages of the spike's own generated prose (no third-party text), /PageLabels i-x then 1-990,
# uncompressed. Deterministic: same bytes on every run (python3 standard library only). Not committed.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

PAGES=1000
OUT_DIR="$SYLVIA_FIXTURE_CACHE/generated/g01-pdf"
OUT="$OUT_DIR/large-$PAGES.pdf"
# Expected digest of the deterministic output; a mismatch means the generator changed.
EXPECTED_SHA256="cfa95b03bc0bc3a268a7738c491b1ac974ccd72023c5bd171eb048351d2ee299"

mkdir -p "$OUT_DIR"
if [[ -f "$OUT" ]] && [[ "$(shasum -a 256 "$OUT" | awk '{print $1}')" == "$EXPECTED_SHA256" ]]; then
  echo "up to date: $OUT"
  exit 0
fi
/usr/bin/env python3 "$SYLVIA_ROOT/Spikes/G01-PDF/Tools/make_pdf_fixtures.py" --large "$OUT" --pages "$PAGES"
actual="$(shasum -a 256 "$OUT" | awk '{print $1}')"
if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
  echo "error: $OUT has sha256 $actual, expected $EXPECTED_SHA256" >&2
  exit 1
fi
echo "generated: $OUT ($(stat -f %z "$OUT") bytes, sha256 $actual)"
