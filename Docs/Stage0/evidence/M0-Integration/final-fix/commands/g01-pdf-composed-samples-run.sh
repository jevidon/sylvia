#!/usr/bin/env bash
# The M0 final fix's run of G0.1 PDF's ComposedSelectionTests (final review R1-02), which wrote
# Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json: builds the spike and runs only that test class on the
# simulator Sylvia-M0-final-fix (iPhone 17, iOS 26.5), with its evidence going to .build/scratch (the JSON was then
# copied into Docs/Stage0/evidence/G01-PDF/; the class's four text files were compared with the committed ones).
# The run used an identical copy under .build/scratch/run-g01-composed.sh, with the worktree's path written out
# where this copy computes it. The whole spike runs in Scripts/ci.d/32-g01-pdf.sh (the complete CI run).
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/g01-pdf-composed-samples-run.sh > <log> 2>&1
set -uo pipefail
W="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$W" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
out="$W/.build/scratch/g01-pdf-composed-evidence"
rm -rf "$out"; mkdir -p "$out"
echo "commit: $(git rev-parse HEAD); uncommitted: $(git status --porcelain | wc -l | tr -d ' ')"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
xcodebuild -version
udid="$(sylvia_sim_udid Sylvia-M0-final-fix)"
echo "simulator Sylvia-M0-final-fix $udid ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)"
sylvia_sim_boot "$udid"
sylvia_generate Spikes/G01-PDF
cd Spikes/G01-PDF
TEST_RUNNER_SYLVIA_G01_PDF_EVIDENCE_DIR="$out" xcodebuild test -project G01PDF.xcodeproj -scheme PDFSpikeHarness \
  -destination "id=$udid" -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution \
  -only-testing:PDFAnchorKitTests/ComposedSelectionTests > "$W/.build/scratch/g01-composed-xcodebuild.log" 2>&1
status=$?
grep -E "^Test Case .*(passed|failed|skipped)|\*\* TEST|error:" "$W/.build/scratch/g01-composed-xcodebuild.log"
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
echo "xcodebuild exit: $status"
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
ls -la "$out"
exit $status
