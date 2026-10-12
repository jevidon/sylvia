#!/usr/bin/env bash
# G0.5 AI spike (Spikes/G05-AI): providers, context packs, citations, transcription.
#
#   1. Host: check that no test double is defined in the library targets, build with zero warnings in the spike's own
#      code, run every package test (Swift Testing) and check that the tests left nothing in their scratch directory,
#      export Swift-built contract instances and validate them against Contracts/schemas.
#   2. Host: dry-run the gated live tests against a loopback fake OpenAI-compatible server (not a provider).
#   3. Contracts: validate schemas and fixtures (same validator as 10-contracts), check that each invalid fixture
#      fails only for its named rule, and that the committed fixtures regenerate byte for byte from the export.
#   4. Simulator (own simulator, default Sylvia-M0-g05-ai or $SYLVIA_G05_SIM_NAME; iPhone 17, iOS 26.5): run the package tests, then the
#      ATS/Keychain probe app (three host-app variants) generated with XcodeGen, and the suspension UI test.
#
# Needs network only to fetch the pinned GRDB package on a clean clone. Uses committed fixtures only
# (Fixtures/epub, Fixtures/audio). Never contacts a real provider: the live tests are run with the opt-in
# variable removed (they report "skipped" with the reason), and the dry run removes the provider keys.
# Logs go to Spikes/G05-AI/.build/g05-ci/. Exits non-zero on any failure.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

SPIKE="$SYLVIA_ROOT/Spikes/G05-AI"
PROBE="$SPIKE/ATSProbe"
# Each runner uses its own simulator (CLAUDE.md); override for a second runner, for example a reviewer.
SIM_NAME="${SYLVIA_G05_SIM_NAME:-Sylvia-M0-g05-ai}"
WORK="$SPIKE/.build/g05-ci"
EXPORT="$WORK/contract-export"
# Totals reported by Swift Testing (skipped live tests included); a drop means tests went missing.
MIN_HOST_TESTS=242
MIN_SIM_PACKAGE_TESTS=242
MIN_PROBE_TESTS=39

sylvia_check_xcode || echo "continuing with the active Xcode"
echo "toolchain: $(xcodebuild -version | tr '\n' ' ')"
echo "swift: $(xcrun swift --version 2>&1 | head -1)"
rm -rf "$WORK"
mkdir -p "$WORK"

# Sums "Test run with N tests" lines (Swift Testing) and fails if fewer than the minimum ran.
require_tests() {
  local log="$1" minimum="$2" label="$3" total
  total="$(grep -Eo 'Test run with [0-9]+ tests' "$log" | awk '{sum += $4} END {print sum + 0}')"
  echo "$label: $total tests reported"
  if (( total < minimum )); then
    echo "FAIL: $label ran $total tests, expected at least $minimum" >&2
    return 1
  fi
  if grep -Eq '✘ Test run|recorded an issue' "$log"; then
    echo "FAIL: $label reported failures" >&2
    return 1
  fi
}

echo "== host: test doubles stay out of the library targets (they live in G05TestSupport)"
if grep -rnE "(class|struct|actor) (InMemoryCredentialStore|RecordingSleeper|ManualClock|FakeConnectivity|CapturingLogSink|ScriptedProvider|FakeHTTPServer)\b" \
     "$SPIKE/Sources/SylviaAI" "$SPIKE/Sources/SylviaContext"; then
  echo "FAIL: a test double is defined in SylviaAI or SylviaContext" >&2
  exit 1
fi
echo "no test doubles in SylviaAI or SylviaContext"

echo "== host: build (warnings in Spikes/G05-AI code fail the step)"
cd "$SPIKE"
set +e
swift build --build-tests > "$WORK/host-build.log" 2>&1
status=$?
set -e
grep -E "warning:|error:|Build complete" "$WORK/host-build.log" || true
if [[ "$status" -ne 0 ]]; then echo "FAIL: swift build exited $status" >&2; exit 1; fi
if grep -E "Spikes/G05-AI/(Sources|Tests)/.*(warning|error):" "$WORK/host-build.log"; then
  echo "FAIL: compiler warnings or errors in the spike's code" >&2
  exit 1
fi

echo "== host: swift test (exporting contract instances to $EXPORT)"
# Tests write stored questions, packs and clips only under one per-process directory in G05_TEST_SCRATCH, removed when
# the test process exits; the check after the run fails if anything is left there.
SCRATCH="$WORK/test-scratch"
mkdir -p "$SCRATCH"
set +e
env -u SYLVIA_LIVE_PROVIDER_TESTS G05_CONTRACT_EXPORT="$EXPORT" G05_TEST_SCRATCH="$SCRATCH" swift test 2>&1 | tee "$WORK/host-test.log" | grep -E "✔ Test run|✘|recorded an issue|skipped|EVAL-SUMMARY|^eval-|^id	"
status="${PIPESTATUS[0]}"
set -e
if [[ "$status" -ne 0 ]]; then echo "FAIL: swift test exited $status" >&2; exit 1; fi
require_tests "$WORK/host-test.log" "$MIN_HOST_TESTS" "host"
if ! grep -q "Test everyScratchDirectoryLivesUnderOneRootInTheConfiguredParent() passed" "$WORK/host-test.log"; then
  echo "FAIL: the test scratch directory check did not run" >&2
  exit 1
fi
leftover="$(find "$SCRATCH" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
if [[ "$leftover" -ne 0 ]]; then
  find "$SCRATCH" -mindepth 1 -maxdepth 1 >&2
  echo "FAIL: the tests left $leftover entries in $SCRATCH" >&2
  exit 1
fi
echo "test scratch: nothing left behind in $SCRATCH"

echo "== host: live-test dry run against a loopback fake server"
"$SPIKE/Scripts/live-tests-dry-run.sh" 2>&1 | tee "$WORK/live-dry-run.log"
if grep -Eq '✘|recorded an issue' "$WORK/live-dry-run.log" || ! grep -q 'Test run with 4 tests in 1 suite passed' "$WORK/live-dry-run.log" \
   || [[ "$(grep -cE '^✔ Test [A-Za-z]+\(\) passed' "$WORK/live-dry-run.log")" -ne 2 ]]; then
  echo "FAIL: live-test dry run (expected the compatible-endpoint and transcription tests to pass, the other two skipped)" >&2
  exit 1
fi

echo "== contract instances produced by Swift"
sylvia_python "$SPIKE/Scripts/validate-exports.py" "$SYLVIA_ROOT/Contracts" "$EXPORT" | tee "$WORK/contract-exports.log"

echo "== contracts (schemas and committed fixtures)"
sylvia_python "$SYLVIA_ROOT/Scripts/validate-contracts.py" "$SYLVIA_ROOT/Contracts" | tee "$WORK/contracts.log"
echo "== contracts: why each invalid G0.5 fixture fails (each must fail only for its named rule)"
sylvia_python "$SPIKE/Scripts/explain-invalid-fixtures.py" "$SYLVIA_ROOT/Contracts" | tee "$WORK/contracts-invalid-reasons.log"
echo "== contracts: committed G0.5 fixtures regenerate byte for byte from the Swift export"
REGEN="$WORK/regenerated-contracts"
mkdir -p "$REGEN"
cp -R "$SYLVIA_ROOT/Contracts/." "$REGEN/"
sylvia_python "$SPIKE/Scripts/make-contract-fixtures.py" "$EXPORT" "$REGEN"
for name in context-pack.v1 provider-config.v1; do
  if ! diff -r "$SYLVIA_ROOT/Contracts/fixtures/$name" "$REGEN/fixtures/$name"; then
    echo "FAIL: Contracts/fixtures/$name differs from a fresh export (run Spikes/G05-AI/Scripts/make-contract-fixtures.py)" >&2
    exit 1
  fi
done
echo "fixtures reproduce: context-pack.v1 and provider-config.v1 identical to a fresh export"

echo "== simulator: $SIM_NAME"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
xcrun simctl list devices | grep "$UDID"

echo "== simulator: package tests"
set +e
env -u SYLVIA_LIVE_PROVIDER_TESTS xcodebuild test -scheme G05AI-Package -destination "id=$UDID" -derivedDataPath "$SPIKE/.build/DerivedData" \
  -disableAutomaticPackageResolution > "$WORK/sim-package-test.log" 2>&1
status=$?
set -e
grep -E "✔ Test run|✘|recorded an issue|skipped|TEST (SUCCEEDED|FAILED)|warning:|error:" "$WORK/sim-package-test.log" | grep -v appintentsmetadataprocessor || true
if [[ "$status" -ne 0 ]]; then echo "FAIL: simulator package tests exited $status" >&2; exit 1; fi
require_tests "$WORK/sim-package-test.log" "$MIN_SIM_PACKAGE_TESTS" "simulator package"

echo "== simulator: ATS and Keychain probe"
sylvia_generate "$PROBE"
set +e
(cd "$PROBE" && xcodebuild test -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination "id=$UDID" \
  -derivedDataPath "$PROBE/.build/DerivedData" -disableAutomaticPackageResolution) > "$WORK/sim-probe-test.log" 2>&1
status=$?
set -e
grep -E "✔ Test run|✘|recorded an issue|ATS-PROBE|SUSPENSION-PROBE|Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)|warning:|error:" "$WORK/sim-probe-test.log" | grep -v appintentsmetadataprocessor | cut -c1-400 || true
if [[ "$status" -ne 0 ]]; then echo "FAIL: probe tests exited $status" >&2; exit 1; fi
require_tests "$WORK/sim-probe-test.log" "$MIN_PROBE_TESTS" "simulator probe"
if ! grep -q "Test Case '-\[ProbeDefaultATSUITests.SuspensionUITests testLeavingTheForegroundMidStreamLeavesAnInterruptedPartialAnswer\]' passed" "$WORK/sim-probe-test.log"; then
  echo "FAIL: the suspension UI test did not pass" >&2
  exit 1
fi

if grep -E "Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:" "$WORK/sim-package-test.log" "$WORK/sim-probe-test.log"; then
  echo "FAIL: compiler warnings in the spike's code (simulator build)" >&2
  exit 1
fi
echo "G0.5 AI: all steps passed"
