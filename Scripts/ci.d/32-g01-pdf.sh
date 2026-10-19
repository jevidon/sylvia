#!/usr/bin/env bash
# G0.1 PDF spike (ADR-0005): verifies the committed fixtures, generates the large PDF, regenerates the Xcode
# project, then builds and runs every unit and UI test on the simulator Sylvia-M0-g01-pdf (iPhone 17, iOS 26.5),
# then runs the overlay concurrency tests again in a Thread Sanitizer build, then shuts that simulator down and runs
# CrossOSRestoreTests (anchors captured on iOS 26.5, and the page text of every fixture page) on a simulator of the
# same name on the iOS 27.0 runtime ($SYLVIA_SIM_RUNTIME_LATEST), whose PDFKit is that release's build, and compares
# the two runtimes' page text. One simulator runs at a time.
# Fails on any build error, failed, skipped or crashed test, or sanitizer report. A page-text difference between the
# runtimes is printed, not failed (the extractor ships with the OS; anchors relocate when it changes).
#
# Evidence files written by the tests go to $G01_PDF_EVIDENCE_DIR (default .build/g01-pdf-evidence), never into
# Docs/ automatically.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

SPIKE="$SYLVIA_ROOT/Spikes/G01-PDF"
SIM_NAME="${G01_PDF_SIM_NAME:-Sylvia-M0-g01-pdf}"
EVIDENCE_DIR="${G01_PDF_EVIDENCE_DIR:-$SYLVIA_ROOT/.build/g01-pdf-evidence}"
LARGE_PDF="$SYLVIA_FIXTURE_CACHE/generated/g01-pdf/large-1000.pdf"
LOG_DIR="$SYLVIA_ROOT/.build/g01-pdf-logs"
mkdir -p "$EVIDENCE_DIR" "$LOG_DIR"
# The tests run inside the simulator with their own working directory, so they get an absolute path; a relative
# G01_PDF_EVIDENCE_DIR is taken relative to the directory this script was started from.
EVIDENCE_DIR="$(cd "$EVIDENCE_DIR" && pwd)"
# Files named after the runtime that wrote them: remove earlier runs' copies, so the comparison at the end reads only
# what this run wrote.
rm -f "$EVIDENCE_DIR"/page-text-digests-*.txt "$EVIDENCE_DIR"/cross-os-restore-*.txt

echo "== toolchain"
xcodebuild -version
sylvia_check_xcode || true

echo "== committed fixtures regenerate byte-identically (host, python3 standard library)"
/usr/bin/env python3 "$SPIKE/Tools/make_pdf_fixtures.py" --check "$SPIKE/Fixtures"

echo "== large PDF fixture"
"$SYLVIA_ROOT/Scripts/fixtures/generate-g01-pdf-large.sh"

echo "== simulator"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
echo "$SIM_NAME $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)"
sylvia_sim_boot "$UDID"
# Each simulator is shut down when its tests are done (below); also when this script stops early (M0 final review
# CC-05). LATEST_UDID is set once the iOS 27.0 simulator is in use.
LATEST_UDID=""
trap 'sylvia_sim_shutdown "$UDID" "$LATEST_UDID"' EXIT

echo "== project"
sylvia_generate "$SPIKE"

run_tests() {
  (cd "$SPIKE" && \
    TEST_RUNNER_SYLVIA_G01_PDF_EVIDENCE_DIR="$EVIDENCE_DIR" \
    TEST_RUNNER_SYLVIA_G01_PDF_LARGE="$LARGE_PDF" \
    xcodebuild test \
      -project G01PDF.xcodeproj \
      -scheme PDFSpikeHarness \
      -destination "id=$UDID" \
      -derivedDataPath .build/DerivedData \
      -disableAutomaticPackageResolution) >"$LOG_DIR/xcodebuild-test.log" 2>&1
}

echo "== build and test (log: $LOG_DIR/xcodebuild-test.log)"
# The tests record timings (large-pdf-timing.txt); other jobs may share this Mac, so log the load around them.
echo "load before the tests: $(uptime)"
status=0
run_tests || status=$?
# A launch refused by the simulator before any test ran ("Application failed preflight checks") is an
# infrastructure failure, not a test result; retry once after re-booting, and say so.
if (( status != 0 )) && grep -q "Application failed preflight checks" "$LOG_DIR/xcodebuild-test.log" \
   && ! grep -q "Test Case .* failed" "$LOG_DIR/xcodebuild-test.log"; then
  echo "simulator refused to launch the test host (preflight checks); rebooting and retrying once"
  cp "$LOG_DIR/xcodebuild-test.log" "$LOG_DIR/xcodebuild-test.first-attempt.log"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  sylvia_sim_boot "$UDID"
  status=0
  run_tests || status=$?
fi
LOG="$LOG_DIR/xcodebuild-test.log"
echo "load after the tests: $(uptime)"

grep -E "^Test Case .*(passed|failed|skipped)|^Test Suite '(PDFAnchorKitTests|PDFSpikeHarnessUITests)\.xctest' (passed|failed)|Executed [0-9]+ tests?|\*\* TEST|error: -\[|warning: " "$LOG" \
  | grep -v "appintentsmetadataprocessor" || true

passed="$(grep -cE "^Test Case .* passed" "$LOG" || true)"
failed="$(grep -cE "^Test Case .* failed" "$LOG" || true)"
skipped="$(grep -cE "^Test Case .* skipped" "$LOG" || true)"
expected="$(cat "$SPIKE"/Tests/Unit/*.swift "$SPIKE"/Tests/UI/*.swift | { grep -cE "^\s+func test[A-Za-z0-9_]*\(\)" || true; })"
crashes="$(grep -c "Restarting after unexpected exit, crash, or test timeout" "$LOG" || true)"
swift_warnings="$({ grep -E "^/.*\.swift:[0-9]+:[0-9]+: warning:" "$LOG" || true; } | sort -u | wc -l | tr -d ' ')"
echo "== summary: $passed passed, $failed failed, $skipped skipped, $crashes test-process restarts, $expected test methods in source, $swift_warnings Swift warnings"

if (( status != 0 )); then echo "FAIL: xcodebuild exited $status"; exit 1; fi
if (( failed > 0 || skipped > 0 || crashes > 0 )); then echo "FAIL: failed, skipped or crashed tests"; exit 1; fi
if (( passed != expected )); then echo "FAIL: $passed tests passed but the source has $expected test methods"; exit 1; fi

# Overlay drawing races PDFKit's tile threads against main-thread highlight changes (ADR-0005). Run those tests again
# in a Thread Sanitizer build; any sanitizer report stops the test process (halt_on_error) and fails this step.
# Tools/tsan_control_unguarded.sh shows the same run reporting a race when the overlay store's mutex is removed.
TSAN_LOG="$LOG_DIR/xcodebuild-tsan.log"
echo "== Thread Sanitizer: OverlayConcurrencyTests (log: $TSAN_LOG)"
tsan_status=0
(cd "$SPIKE" && \
  TEST_RUNNER_SYLVIA_G01_PDF_EVIDENCE_DIR="$EVIDENCE_DIR" \
  TEST_RUNNER_SYLVIA_G01_PDF_TSAN=1 \
  TEST_RUNNER_TSAN_OPTIONS=halt_on_error=1 \
  xcodebuild test \
    -project G01PDF.xcodeproj \
    -scheme PDFSpikeHarness \
    -destination "id=$UDID" \
    -derivedDataPath .build/DerivedData \
    -disableAutomaticPackageResolution \
    -enableThreadSanitizer YES \
    -only-testing:PDFAnchorKitTests/OverlayConcurrencyTests) >"$TSAN_LOG" 2>&1 || tsan_status=$?
grep -E "^Test Case .*(passed|failed|skipped)|ThreadSanitizer|\*\* TEST" "$TSAN_LOG" || true
tsan_passed="$(grep -cE "^Test Case .* passed" "$TSAN_LOG" || true)"
tsan_expected="$(grep -cE "^\s+func test[A-Za-z0-9_]*\(\)" "$SPIKE/Tests/Unit/OverlayConcurrencyTests.swift" || true)"
tsan_reports="$(grep -c "WARNING: ThreadSanitizer" "$TSAN_LOG" || true)"
echo "== Thread Sanitizer summary: $tsan_passed of $tsan_expected passed, $tsan_reports sanitizer reports, xcodebuild exit $tsan_status"
if (( tsan_status != 0 || tsan_reports > 0 || tsan_passed != tsan_expected )); then
  echo "FAIL: Thread Sanitizer run of OverlayConcurrencyTests"
  exit 1
fi

# Plan 9.4 across an OS update: the anchors captured on iOS 26.5 restored by the iOS 27.0 runtime's PDFKit.
CROSS_LOG="$LOG_DIR/xcodebuild-cross-os.log"
echo "== cross-OS restore: CrossOSRestoreTests on $SYLVIA_SIM_RUNTIME_LATEST (log: $CROSS_LOG)"
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
LATEST_UDID="$(sylvia_sim_udid "$SIM_NAME" "$SYLVIA_SIM_DEVICE_TYPE" "$SYLVIA_SIM_RUNTIME_LATEST")"
echo "$SIM_NAME $LATEST_UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME_LATEST)"
sylvia_sim_boot "$LATEST_UDID"
cross_status=0
(cd "$SPIKE" && \
  TEST_RUNNER_SYLVIA_G01_PDF_EVIDENCE_DIR="$EVIDENCE_DIR" \
  xcodebuild test \
    -project G01PDF.xcodeproj \
    -scheme PDFSpikeHarness \
    -destination "id=$LATEST_UDID" \
    -derivedDataPath .build/DerivedData \
    -disableAutomaticPackageResolution \
    -only-testing:PDFAnchorKitTests/CrossOSRestoreTests) >"$CROSS_LOG" 2>&1 || cross_status=$?
xcrun simctl shutdown "$LATEST_UDID" >/dev/null 2>&1 || true
grep -E "^Test Case .*(passed|failed|skipped)|error: -\[|\*\* TEST" "$CROSS_LOG" || true
cross_passed="$(grep -cE "^Test Case .* passed" "$CROSS_LOG" || true)"
cross_bad="$(grep -cE "^Test Case .* (failed|skipped)" "$CROSS_LOG" || true)"
cross_expected="$(grep -cE "^\s+func test[A-Za-z0-9_]*\(\)" "$SPIKE/Tests/Unit/CrossOSRestoreTests.swift" || true)"
echo "== cross-OS summary: $cross_passed of $cross_expected passed, $cross_bad failed or skipped, xcodebuild exit $cross_status"
if (( cross_status != 0 || cross_passed != cross_expected || cross_bad > 0 )); then
  echo "FAIL: CrossOSRestoreTests on $SYLVIA_SIM_RUNTIME_LATEST"
  exit 1
fi

# The page text of every page of every bundled fixture, as each runtime's PDFKit extracts it
# (CrossOSRestoreTests.testRecordPageTextOfEveryFixturePage). Compared line by line, without each file's first line
# (which names the runtime). A difference is reported, not failed: the extractor ships with the OS and may change,
# which is why anchors carry page text digests and relocate (ADR-0005).
echo "== page text of every fixture page: iOS 26.5 and iOS 27.0 compared"
shopt -s nullglob
digest_files=("$EVIDENCE_DIR"/page-text-digests-*.txt)
shopt -u nullglob
if (( ${#digest_files[@]} != 2 )); then
  echo "FAIL: expected one page-text digest file per runtime in $EVIDENCE_DIR, found ${#digest_files[@]}"
  exit 1
fi
first_list="$(tail -n +2 "${digest_files[0]}")"
second_list="$(tail -n +2 "${digest_files[1]}")"
if [[ "$first_list" == "$second_list" ]]; then
  echo "identical: $(basename "${digest_files[0]}") and $(basename "${digest_files[1]}"), $(printf '%s\n' "$first_list" | grep -c ' page [0-9]*: ') pages, every line equal ($(printf '%s\n' "$first_list" | tail -n 1))"
else
  echo "DIFFERENT: $(basename "${digest_files[0]}") and $(basename "${digest_files[1]}") differ (reported, not a failure):"
  diff <(printf '%s\n' "$first_list") <(printf '%s\n' "$second_list") || true
fi
echo "evidence written to $EVIDENCE_DIR"
echo "PASS"
