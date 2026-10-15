#!/usr/bin/env bash
# M0 device runbook: do the -only-testing identifiers that the device checklists use select the tests they name?
# A filter that matches nothing makes xcodebuild run zero tests and still report success, which on a device step
# would look like a pass. Checked on this job's own simulator (Sylvia-M0-runbook, iPhone 17, iOS 26.5):
#   1. G05-AI step 2's function-level identifier, written without "()" as in the checklist and with "()", is run
#      with test-without-building and without G05_LAN_TARGET / G05_EXPECT_LOCAL_NETWORK, so a selected test reports
#      "skipped" with its reason and an unmatched filter runs no test. Nothing is sent over any network.
#   2. Every other identifier is listed with `xcodebuild test-without-building -enumerate-tests`, which enumerates
#      the tests a command would execute without executing them (no audio plays, nothing is sent).
# Each enumeration is compared with the number of tests the runbook says the filter selects (expected_count,
# written before the run); the script exits 1 if any differs or any build fails.
# Environment: simulator. Build products go to .build/DerivedData-sim inside each project, and the Release build of
# G05-Recovery to .build/DerivedData-sim-release (all deleted at the end of the job).
#
#   Docs/Stage0/evidence/M0-runbook/commands/check-only-testing-ids.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$ROOT"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh

OUT="$ROOT/Docs/Stage0/evidence/M0-runbook/only-testing-ids.log"
FULL="$ROOT/.build/scratch/only-testing"
mkdir -p "$FULL"
unset G05_LAN_TARGET G05_EXPECT_LOCAL_NETWORK TEST_RUNNER_G05_LAN_TARGET TEST_RUNNER_G05_EXPECT_LOCAL_NETWORK
unset SYLVIA_DEVICE_LOCK_PROBE SYLVIA_DEVICE_PERSIST_PROBE TEST_RUNNER_SYLVIA_DEVICE_LOCK_PROBE TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE

UDID="$(sylvia_sim_udid Sylvia-M0-runbook)"
sylvia_sim_boot "$UDID"
{
  echo "# environment: host macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | tr '\n' ' ')"
  echo "# simulator: Sylvia-M0-runbook ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME), created by this job"
  echo "# commit: $(git -C "$ROOT" rev-parse HEAD); started $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"
} > "$OUT"

trim() { sed -e "s#$ROOT/##g" -e "s#$HOME#~#g"; }

# The number of tests each filter selects, as the runbook states it (Section 9 and the steps that cite this log).
expected_count() {
  case "$1" in
    g05-ai-step2-as-written|g05-recovery-step2-release-latency-without-parentheses) echo 0 ;;
    g05-ai-step2-with-parentheses|g05-ai-step4|g05-recovery-step3|g05-recovery-step4) echo 1 ;;
    g05-recovery-step2-release-latency|g04-step1.5-BudgetTests) echo 1 ;;
    g02-step1|g04-step1.5-PerFileTimingTests) echo 3 ;;
    g03-step24|g04-step1.5-RealPreviewTests|g04-step1.5-LongFormatTests) echo 4 ;;
    g01-epub-step11) echo 37 ;;
    *) echo unknown ;;
  esac
}
MISMATCHES=0

# Derived data inside each project; DD=<folder> overrides it for one call (the Release build of G05-Recovery).
# build LABEL DIR ARGS...: build-for-testing for the simulator in DIR (relative to the repository root).
build() {
  local label="$1" dir="$2" dd="${DD:-.build/DerivedData-sim}"
  shift 2
  (cd "$dir" && xcodebuild build-for-testing "$@" -destination "id=$UDID" -derivedDataPath "$dd" \
    -disableAutomaticPackageResolution) > "$FULL/build-$label.log" 2>&1
  local rc=$?
  echo "build-for-testing $label (simulator, in $dir, $dd): exit $rc $(grep -E '\*\* TEST BUILD (SUCCEEDED|FAILED) \*\*' "$FULL/build-$label.log")" >> "$OUT"
  (( rc == 0 )) || MISMATCHES=$((MISMATCHES + 1))
}

# run_filter LABEL DIR ID ARGS...: test-without-building with one -only-testing filter (G05-AI step 2 only).
run_filter() {
  local label="$1" dir="$2" id="$3" log="$FULL/run-$1.log"
  shift 3
  (cd "$dir" && xcodebuild test-without-building "$@" -destination "id=$UDID" -derivedDataPath .build/DerivedData-sim \
    "-only-testing:$id") > "$log" 2>&1
  local rc=$?
  {
    echo
    echo "== run $label: xcodebuild test-without-building ... -only-testing:$id (exit $rc)"
    grep -E 'Test run with|➜ Test|✔ Test|✘ Test|\*\* TEST' "$log" | sed -E 's/^[[:space:]]+//' | sort -u
  } >> "$OUT"
}

# enumerate LABEL DIR ID ARGS...: lists the tests a -only-testing filter selects, without running them.
enumerate() {
  local label="$1" dir="$2" id="$3" log="$FULL/enum-$1.log" list="$FULL/enum-$1.txt" dd="${DD:-.build/DerivedData-sim}"
  shift 3
  rm -f "$list"
  (cd "$dir" && xcodebuild test-without-building "$@" -destination "id=$UDID" -derivedDataPath "$dd" \
    "-only-testing:$id" -enumerate-tests -test-enumeration-style flat -test-enumeration-format text \
    -test-enumeration-output-path "$list") > "$log" 2>&1
  local rc=$?
  {
    echo
    echo "== enumerate $label: -only-testing:$id (exit $rc)"
    if [[ -s "$list" ]]; then
      # xcodebuild lists every test of the scheme and marks the ones the filter leaves out "(disabled)".
      local selected skipped
      selected="$(grep -vE '^[[:space:]]*$|^Plan |\(disabled\)' "$list" | wc -l | tr -d ' ')"
      skipped="$(grep -c '(disabled)' "$list")"
      echo "selected by the filter: $selected; left out (listed as disabled): $skipped"
      local want; want="$(expected_count "$label")"
      if [[ "$selected" == "$want" ]]; then echo "expected: $want; as expected: yes"; else echo "expected: $want; as expected: no"; MISMATCHES=$((MISMATCHES + 1)); fi
      grep -vE '^[[:space:]]*$|^Plan |\(disabled\)' "$list" | sed -E 's/^[[:space:]]+/  /' | trim
    else
      echo "no enumeration output (see the xcodebuild lines below); as expected: no"
      MISMATCHES=$((MISMATCHES + 1))
      grep -E 'error:|\*\* TEST' "$log" | trim | sort -u | head -10
    fi
  } >> "$OUT"
}

# G05-AI ATS probe (checklist steps 1, 2 and 4).
sylvia_generate Spikes/G05-AI/ATSProbe > "$FULL/generate-atsprobe.log" 2>&1
build g05-ai Spikes/G05-AI/ATSProbe -project G05ATSProbe.xcodeproj -scheme G05ATSProbe
run_filter g05-ai-step2-as-written Spikes/G05-AI/ATSProbe "ProbeLocalNetworkingTests/ATSProbeTests/plainHTTPToAnotherDeviceOnTheLAN" \
  -project G05ATSProbe.xcodeproj -scheme G05ATSProbe
run_filter g05-ai-step2-with-parentheses Spikes/G05-AI/ATSProbe "ProbeLocalNetworkingTests/ATSProbeTests/plainHTTPToAnotherDeviceOnTheLAN()" \
  -project G05ATSProbe.xcodeproj -scheme G05ATSProbe
enumerate g05-ai-step2-as-written Spikes/G05-AI/ATSProbe "ProbeLocalNetworkingTests/ATSProbeTests/plainHTTPToAnotherDeviceOnTheLAN" \
  -project G05ATSProbe.xcodeproj -scheme G05ATSProbe
enumerate g05-ai-step2-with-parentheses Spikes/G05-AI/ATSProbe "ProbeLocalNetworkingTests/ATSProbeTests/plainHTTPToAnotherDeviceOnTheLAN()" \
  -project G05ATSProbe.xcodeproj -scheme G05ATSProbe
enumerate g05-ai-step4 Spikes/G05-AI/ATSProbe "ProbeDefaultATSUITests" -project G05ATSProbe.xcodeproj -scheme G05ATSProbe

# G05-Recovery package (checklist steps 3 and 4).
build g05-recovery Spikes/G05-Recovery -scheme G05Recovery-Package
enumerate g05-recovery-step3 Spikes/G05-Recovery "SylviaRecoveryTests/DeviceLockProbeTests" -scheme G05Recovery-Package
enumerate g05-recovery-step4 Spikes/G05-Recovery "SylviaRecoveryTests/DevicePersistenceProbeTests" -scheme G05Recovery-Package
# Runbook correction for G05-Recovery step 2: the latency test alone in a Release build (ENABLE_TESTABILITY=YES for
# @testable import). A Swift Testing function needs "()" in -only-testing; the form without it is listed for contrast.
DD=.build/DerivedData-sim-release build g05-recovery-release Spikes/G05-Recovery -scheme G05Recovery-Package \
  -configuration Release ENABLE_TESTABILITY=YES
DD=.build/DerivedData-sim-release enumerate g05-recovery-step2-release-latency Spikes/G05-Recovery \
  "SylviaRecoveryTests/DurabilityTests/latency()" -scheme G05Recovery-Package -configuration Release ENABLE_TESTABILITY=YES
DD=.build/DerivedData-sim-release enumerate g05-recovery-step2-release-latency-without-parentheses Spikes/G05-Recovery \
  "SylviaRecoveryTests/DurabilityTests/latency" -scheme G05Recovery-Package -configuration Release ENABLE_TESTABILITY=YES

# G02 transfer harness (checklist step 1).
sylvia_generate Spikes/G02-Transfer/iOS > "$FULL/generate-g02.log" 2>&1
build g02 Spikes/G02-Transfer/iOS -project G02Transfer.xcodeproj -scheme G02TransferHarness
enumerate g02-step1 Spikes/G02-Transfer/iOS "G02TransferHostedTests/KeychainCredentialStoreTests" \
  -project G02Transfer.xcodeproj -scheme G02TransferHarness

# G03 intake harness (checklist step 3 command, used by step 24).
sylvia_generate Spikes/G03-Intake/App > "$FULL/generate-g03.log" 2>&1
build g03 Spikes/G03-Intake/App -project G03Intake.xcodeproj -scheme IntakeHarness
enumerate g03-step24 Spikes/G03-Intake/App "IntakeHarnessTests/InAppLayoutTests" -project G03Intake.xcodeproj -scheme IntakeHarness

# G04 audio (checklist step 1.5's four suites; the BudgetTests filter is also the runbook's Low Power Mode run of
# step 1.4, in the Debug configuration this simulator build uses).
sylvia_generate Spikes/G04-Audio > "$FULL/generate-g04.log" 2>&1
build g04 Spikes/G04-Audio -project G04Audio.xcodeproj -scheme G04AudioHarness
for suite in BudgetTests RealPreviewTests LongFormatTests PerFileTimingTests; do
  enumerate "g04-step1.5-$suite" Spikes/G04-Audio "G04AudioTests/RealAV/$suite" -project G04Audio.xcodeproj -scheme G04AudioHarness
done

# G01-EPUB (checklist step 11).
sylvia_generate Spikes/G01-EPUB > "$FULL/generate-g01-epub.log" 2>&1
build g01-epub Spikes/G01-EPUB -project G01EPUB.xcodeproj -scheme EPUBHarness
enumerate g01-epub-step11 Spikes/G01-EPUB "EPUBHarnessTests" -project G01EPUB.xcodeproj -scheme EPUBHarness

xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
echo >> "$OUT"
echo "# finished $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //'); simulator shut down" >> "$OUT"
echo "# builds failed or enumerations not as expected: $MISMATCHES" >> "$OUT"
cat "$OUT"
(( MISMATCHES == 0 ))
