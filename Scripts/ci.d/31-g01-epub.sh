#!/usr/bin/env bash
# G0.1 EPUB spike (Spikes/G01-EPUB, ADR-0004): fixture check, host tests, harness build and every simulator test.
#
#   Scripts/ci.d/31-g01-epub.sh
#
# Environment (all optional):
#   G01_EPUB_SIM_NAME        simulator name (default Sylvia-M0-g01-epub; iPhone 17, iOS 26.5 from Scripts/lib/env.sh)
#   G01_EPUB_EVIDENCE_DIR    where the tests write their evidence files (default Spikes/G01-EPUB/.build/evidence;
#                            the committed run used Docs/Stage0/evidence/G01-EPUB)
#   G01_EPUB_ONLY_TESTING    space-separated xcodebuild -only-testing identifiers, for local iteration only
#
# Exits non-zero on any failure. Needs network access the first time (Readium 3.11.0 package checkout).
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

SPIKE="$SYLVIA_ROOT/Spikes/G01-EPUB"
DERIVED="$SPIKE/.build/DerivedData"
EVIDENCE="${G01_EPUB_EVIDENCE_DIR:-$SPIKE/.build/evidence}"
SIM_NAME="${G01_EPUB_SIM_NAME:-Sylvia-M0-g01-epub}"
mkdir -p "$EVIDENCE" "$SPIKE/.build"
# The UI tests append to these logs; start each run with empty ones. Every other evidence file is overwritten.
rm -f "$EVIDENCE/ui-tests.log" "$EVIDENCE/ui-deep-nesting.log" "$EVIDENCE/crash-reports.txt"

echo "== environment"
sylvia_check_xcode || true
xcodebuild -version
xcrun swift --version 2>&1 | head -1
xcodegen --version
sw_vers | paste -sd' ' -

echo "== committed generated fixtures match their generator"
"$SYLVIA_ROOT/Scripts/fixtures/generate-g01-epub-fixtures.sh" --check

echo "== host: G01EPUBCore (swift test, macOS)"
# The sanitizer's timing and real-book fidelity results are written to $EVIDENCE.
(cd "$SPIKE/Core" && SYLVIA_EVIDENCE_DIR="$EVIDENCE" xcrun swift test --scratch-path "$SPIKE/.build/core")

echo "== generate the Xcode project"
sylvia_generate "$SPIKE"
PROJECT="$SPIKE/G01EPUB.xcodeproj"

UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
echo "simulator: $SIM_NAME ($UDID), $(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
u = sys.argv[1]
for rt, ds in json.load(sys.stdin)["devices"].items():
    for d in ds:
        if d["udid"] == u: print(rt.split(".")[-1], d.get("deviceTypeIdentifier", "").split(".")[-1])
' "$UDID")"

echo "== build for testing (simulator)"
xcodebuild build-for-testing \
  -project "$PROJECT" -scheme EPUBHarness \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution \
  -skipPackagePluginValidation \
  -quiet 2>&1 | tee "$SPIKE/.build/xcodebuild-build.log"
# -quiet prints only warnings and errors, so this counts every compiler warning in the build.
echo "build warnings outside package checkouts: $(grep ": warning:" "$SPIKE/.build/xcodebuild-build.log" | grep -vc "/SourcePackages/" || true)"
echo "build warnings in package checkouts: $(grep -c "/SourcePackages/.*: warning:" "$SPIKE/.build/xcodebuild-build.log" || true)"

only=()
for t in ${G01_EPUB_ONLY_TESTING:-}; do only+=("-only-testing:$t"); done

echo "== test (simulator): hosted unit tests and UI tests"
# TEST_RUNNER_ variables reach the test processes; the simulator shares the host file system, so the tests
# write their evidence straight into $EVIDENCE.
LOG="$SPIKE/.build/xcodebuild-test.log"
MARKER="$SPIKE/.build/test-start.marker"
touch "$MARKER"
set +e
TEST_RUNNER_SYLVIA_EVIDENCE_DIR="$EVIDENCE" \
xcodebuild test-without-building \
  -project "$PROJECT" -scheme EPUBHarness \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution \
  -parallel-testing-enabled NO \
  -resultBundlePath "$SPIKE/.build/results/$(date +%Y%m%d-%H%M%S).xcresult" \
  ${only[@]+"${only[@]}"} >"$LOG" 2>&1
status=$?
set -e
# Test results only (the full log, with WebKit's console noise, stays in $LOG).
grep -E "^Test Case .*(passed|failed)|^Test Suite '(All tests|Selected tests)'|: error: |Executed [0-9]+ tests|\*\* TEST" "$LOG" || true
if [[ $status -ne 0 ]]; then
  echo "simulator tests FAILED (xcodebuild exit $status); full log: $LOG"
  exit "$status"
fi

echo "== crash reports for crashes during the tests"
# DeepNestingUITests crashes the app on purpose (Readium alone, 10,000 nested elements). The test itself decides that
# the app crashed, from the app's process (pid logged in ui-deep-nesting.log); it does not depend on crash reports or on
# XCTest's own crash detection. Here every crash report captured during the run on this run's simulator (reports from
# other checkouts' simulators share the DiagnosticReports folder and are ignored) must belong to one of those pids and
# show a stack overflow in Readium's content iterator; any other crash fails CI. A crashed pid may have no report of
# its own: macOS did not always write a new report for an expected crash (see summarize-crashes.py). Such a pid must
# then have the app's own signal record showing a stack overflow (Harness/CrashSignalRecorder.c, logged by the UI test
# in ui-deep-nesting.log; review R2-03), or CI fails. ReportCrash writes a report a few seconds after the process dies,
# so wait up to 30 s for the expected ones before checking.
check_crashes() {
  "$SPIKE/Scripts/summarize-crashes.py" "$MARKER" "$EVIDENCE/crash-reports.txt" "$UDID" >/dev/null
  /usr/bin/python3 - "$EVIDENCE/crash-reports.txt" "$EVIDENCE/ui-deep-nesting.log" "$1" <<'PY'
import os, re, sys
report_path, log_path, final = sys.argv[1], sys.argv[2], sys.argv[3] == "final"
blocks = open(report_path).read().split("\n\n== ")[1:]
expected = set()
recorded = {}
if os.path.exists(log_path):
    for line in open(log_path):
        if "crashed(" in line:
            m = re.search(r"pid=(\d+)", line)
            if m:
                expected.add(m.group(1))
                s = re.search(r"signal_record=(\[[^\]]*\]|none)", line)
                recorded[m.group(1)] = s.group(1) if s else "none"
def signal_overflow(p):
    return "kind=stack-overflow" in recorded.get(p, "")
def is_stack_overflow_in_readium(b):
    return "excessive recursion" in b and "HTMLResourceContentIterator" in b
by_pid = {}
for b in blocks:
    m = re.search(r"pid: (\d+)", "\n".join(b.splitlines()[:2]))
    by_pid[m.group(1) if m else "?"] = b
without_report = sorted(p for p in expected if p not in by_pid)
wrong = sorted(p for p in expected if p in by_pid and not is_stack_overflow_in_readium(by_pid[p]))
unexpected = sorted(p for p in by_pid if p not in expected)
if without_report and not final:
    sys.exit(2)  # possibly not written yet; poll again
print(f"crashes the UI tests expected and observed (pids in ui-deep-nesting.log): {len(expected)}; crash reports captured during the run: {len(by_pid)}")
for p in sorted(expected):
    if p in without_report:
        if signal_overflow(p):
            state = "no report of its own; the app's signal handler recorded a stack overflow (" + recorded[p] + ")"
        else:
            state = "NO REPORT AND NO STACK-OVERFLOW SIGNAL RECORD: crash kind unverified (" + recorded.get(p, "none") + ")"
    elif p in wrong:
        state = "UNEXPECTED CRASH KIND"
    else:
        state = "report: stack overflow in Readium's content iterator"
    print(f"  pid {p}: {state}")
for p in unexpected:
    print(f"  pid {p}: UNEXPECTED CRASH REPORT: {by_pid[p].splitlines()[0]}")
unverified = sorted(p for p in without_report if not signal_overflow(p))
sys.exit(1 if (wrong or unexpected or (final and unverified)) else 0)
PY
}
for _ in $(seq 1 15); do
  set +e; check_crashes poll >/dev/null 2>&1; crash_status=$?; set -e
  [[ $crash_status -ne 2 ]] && break
  sleep 2
done
set +e; check_crashes final; crash_status=$?; set -e
if [[ $crash_status -ne 0 ]]; then
  echo "crash reports show a crash the tests did not expect (see $EVIDENCE/crash-reports.txt)"
  exit 1
fi
echo "evidence written to $EVIDENCE"
echo "G0.1 EPUB: all checks passed"
