#!/bin/bash
# Fetches the pinned downloads and runs every cache generator the drop-ins need (each is idempotent: an existing
# file with its pinned digest is kept). Generators that write committed files are not run here: the drop-ins check
# them (G0.1 EPUB --check, G0.2 contract fixtures), and the G0.2 certificate generator makes new random keys.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"   # the run used a copy under .build/scratch/, root two levels up
cd "$root"
source Scripts/lib/env.sh
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
for cmd in fetch.sh generate-g01-pdf-large.sh generate-g02-transfer-large.sh generate-g02-transfer-sim-files.sh \
           generate-g03-intake-pack.sh generate-g04-audio-fixtures.sh generate-g04-audio-long-formats.sh \
           generate-g04-audio-probes.sh generate-g04-audio-stereo.sh; do
  echo "==> Scripts/fixtures/$cmd"
  "Scripts/fixtures/$cmd" 2>&1 | tail -n 15
  echo "    exit ${PIPESTATUS[0]}"
done
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
