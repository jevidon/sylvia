#!/usr/bin/env bash
# Copies the logs of a Scripts/ci.d/50-g03-intake.sh run into Docs/Stage0/evidence/G03-Intake/. Host script logs are
# copied whole; xcodebuild logs are reduced to test results and G03-EVIDENCE lines (full logs are tens of MB).
#
#   Spikes/G03-Intake/scripts/collect-evidence.sh [ci-log-dir]     default .build/ci-logs/g03-intake
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
src="${1:-$SYLVIA_ROOT/.build/ci-logs/g03-intake}"
dst="$SYLVIA_ROOT/Docs/Stage0/evidence/G03-Intake"
mkdir -p "$dst"

for f in host-large-pack.log host-handoff-kill.log host-contract-instances.log zip-dependency-probe.log zip-eval.log sim-open-in.log; do
  cp "$src/$f" "$dst/$f"
done
# swift test output: drop the per-case "started" lines, keep results and printed evidence.
grep -v -E '^(◇|􀟈)|Test case passing .* started' "$src/host-intakekit-tests.log" > "$dst/host-intakekit-tests.log"
for f in sim-intakekit-tests sim-app-tests; do
  {
    echo "# Reduced from the full xcodebuild log ($f.log of the CI run): test results, issues and evidence lines only."
    grep -E 'G03-EVIDENCE|^(✔|✘)|Test Case|recorded an issue|error:|\*\* TEST|Executed|contract fixtures:|in-memory plain-text|direct file URL provider|truncation sweep:|coordinated writer|short deflate stream|aggregate expansion:|slow but moving provider|EPUB folder|insufficient space:|cancel |coordinator cancelled|raw file|raw Finder file|non-ASCII paths|platform JSONDecoder|hidden-separator|canonical equivalence:|canonical twins of ASCII|contract names checked:|entry limit:|manifest size limit:|handoff.json size:|stall timeout vs|created_at continuity:|↳' "$src/$f.log"
  } > "$dst/$f.log"
done
{
  echo "# Build warnings from the simulator app build (sim-app-build.log of the CI run)"
  grep -E 'warning:' "$src/sim-app-build.log" | grep -v 'appintentsmetadataprocessor' | sort -u || true
} > "$dst/sim-app-build-warnings.log"
for f in "$dst"/*.log; do
  size=$(stat -f %z "$f")
  (( size < 2 * 1024 * 1024 )) || { echo "too large for evidence: $f ($size bytes)" >&2; exit 1; }
done
ls -l "$dst"
