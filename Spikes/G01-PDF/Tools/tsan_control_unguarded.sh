#!/usr/bin/env bash
# Control for the overlay concurrency tests (ADR-0005, report finding 4): shows that the Thread Sanitizer run of
# OverlayConcurrencyTests can tell a guarded overlay store from an unguarded one.
#
# Copies the spike into .build/tsan-control/ (never touches the source tree), replaces the Mutex that guards
# OverlayPage's rectangles with a plain unsynchronized cell of the same API, builds with -enableThreadSanitizer YES and
# runs OverlayConcurrencyTests on the simulator Sylvia-M0-g01-pdf. Expected: ThreadSanitizer reports a data race and
# the run fails. Exits 0 only when that happens (the control worked); prints the first report.
#
#   Spikes/G01-PDF/Tools/tsan_control_unguarded.sh [output-file]
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

SPIKE="$SYLVIA_ROOT/Spikes/G01-PDF"
WORK="$SYLVIA_ROOT/.build/tsan-control"
OUT="${1:-$WORK/tsan-control-unguarded.txt}"
SIM_NAME="${G01_PDF_SIM_NAME:-Sylvia-M0-g01-pdf}"

rm -rf "$WORK/G01-PDF"
mkdir -p "$WORK"
rsync -a --exclude .build --exclude '*.xcodeproj' "$SPIKE/" "$WORK/G01-PDF/"
OVERLAY="$WORK/G01-PDF/Sources/PDFAnchorKit/HighlightOverlay.swift"
grep -q 'let rects = Mutex<\[CGRect\]>(\[\])' "$OVERLAY" || { echo "OverlayBox no longer uses Mutex<[CGRect]>; update the control" >&2; exit 2; }
/usr/bin/sed -i '' 's/let rects = Mutex<\[CGRect\]>(\[\])/let rects = UnguardedCell<[CGRect]>([])/' "$OVERLAY"
cat >>"$OVERLAY" <<'SWIFT'

/// Control build only (Tools/tsan_control_unguarded.sh): the Mutex API without a lock.
final class UnguardedCell<T>: @unchecked Sendable {
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R { body(&value) }
}
SWIFT

UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
sylvia_generate "$WORK/G01-PDF"
LOG="$WORK/xcodebuild-tsan-control.log"
status=0
(cd "$WORK/G01-PDF" && \
  TEST_RUNNER_SYLVIA_G01_PDF_EVIDENCE_DIR="$WORK/evidence" \
  TEST_RUNNER_SYLVIA_G01_PDF_TSAN=1 \
  TEST_RUNNER_TSAN_OPTIONS=halt_on_error=1 \
  xcodebuild test -project G01PDF.xcodeproj -scheme PDFSpikeHarness -destination "id=$UDID" \
    -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution -enableThreadSanitizer YES \
    -only-testing:PDFAnchorKitTests/OverlayConcurrencyTests) >"$LOG" 2>&1 || status=$?

# Sanitizer output carries ANSI colour codes; strip them for counting and for the evidence file.
PLAIN="$WORK/xcodebuild-tsan-control.plain.log"
/usr/bin/sed -E $'s/\x1b\\[[0-9;]*m//g' "$LOG" >"$PLAIN"
races="$(grep -c "^WARNING: ThreadSanitizer" "$PLAIN" || true)"
{
  echo "TSan control: OverlayBox.rects changed from Mutex<[CGRect]> to an unsynchronized cell (copy in .build/tsan-control)"
  echo "command: Spikes/G01-PDF/Tools/tsan_control_unguarded.sh; simulator $SIM_NAME ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME), $(xcodebuild -version | tr '\n' ' ')"
  echo "xcodebuild test -enableThreadSanitizer YES -only-testing:PDFAnchorKitTests/OverlayConcurrencyTests, TSAN_OPTIONS=halt_on_error=1"
  echo "xcodebuild exit status: $status; ThreadSanitizer reports: $races"
  echo
  echo "First report (Swift and PDFKit frames; addresses removed):"
  awk '/^WARNING: ThreadSanitizer/{p=1} p{print} /^SUMMARY: ThreadSanitizer/{if(p) exit}' "$PLAIN" \
    | { grep -E "WARNING|access|Location|SUMMARY|Thread T|#[0-9]+ .*(PDFAnchorKit|PDFKit|Overlay|withLock|highlightRects)" || true; } \
    | sed -E 's/ \((PDFAnchorKit|PDFAnchorKitTests|PDFKit):arm64\+0x[0-9a-f]+\)//; s/ at 0x[0-9a-f]+//' | head -40
  echo
  echo "Test results (a crashed test process is restarted by xcodebuild and the remaining tests run):"
  { grep -E "^Test Case .*(passed|failed)|Restarting after|^Failing tests:|^\s+OverlayConcurrencyTests\." "$PLAIN" || true; }
} >"$OUT"
cat "$OUT"
if (( status != 0 && races > 0 )); then
  echo "control OK: the sanitizer reports the unguarded store"
  exit 0
fi
echo "control FAILED: expected a ThreadSanitizer data race and a failing run" >&2
exit 1
