#!/usr/bin/env bash
# iOS simulator tests for G0.2 part 1:
#   1. TransferKit package tests (SylviaTransferCore, SylviaTransferClient) on the simulator: proves the
#      shared protocol core builds and runs on iOS.
#   2. Hosted tests in Spikes/G02-Transfer/iOS (Keychain accessibility of the transfer token). The suite
#      SimulatorTransferTests needs a running source and is run by simulator-pairing-run.sh instead.
#
#   Spikes/G02-Transfer/Scripts/test-ios.sh [--resolve] [simulator-name]
# --resolve re-resolves the iOS project's packages. The project has no direct remote package, so Xcode writes no
# lock for it; swift-asn1 is fixed by TransferKit's exact: requirement and its committed Package.resolved.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

resolve=0
if [[ "${1:-}" == "--resolve" ]]; then resolve=1; shift; fi
name="${1:-Sylvia-M0-g02-transfer}"
udid="$(sylvia_sim_udid "$name")"
echo "simulator: $name ($udid); runtime $SYLVIA_SIM_RUNTIME; device type $SYLVIA_SIM_DEVICE_TYPE"
sylvia_sim_boot "$udid"

filter() { grep -E 'error:|warning:|\*\* (TEST|BUILD)|✔|✘|Test run with|Executed|Test Suite .*(passed|failed)' || true; }

spike="$SYLVIA_ROOT/Spikes/G02-Transfer"
logs="$SYLVIA_ROOT/.build/scratch/g02-ios"
mkdir -p "$logs"
echo "== TransferKit package tests on the simulator"
(cd "$spike/TransferKit" && xcodebuild test \
  -scheme SylviaTransferKit-Package \
  -destination "id=$udid" \
  -derivedDataPath "$spike/TransferKit/.build/DerivedData" \
  -skipPackagePluginValidation 2>&1) > "$logs/ios-package-tests.log" || package_status=$?
filter < "$logs/ios-package-tests.log"

echo "== Hosted iOS tests (Spikes/G02-Transfer/iOS)"
sylvia_generate "$spike/iOS"
if (( resolve )); then sylvia_resolve "$spike/iOS"; fi
(cd "$spike/iOS" && xcodebuild test \
  -project G02Transfer.xcodeproj \
  -scheme G02TransferHarness \
  -destination "id=$udid" \
  -derivedDataPath "$spike/iOS/.build/DerivedData" \
  -disableAutomaticPackageResolution \
  -skipPackagePluginValidation \
  -skip-testing:G02TransferHostedTests/SimulatorTransferTests \
  -skip-testing:G02TransferHostedTests/BackgroundSessionTests \
  -skip-testing:G02TransferHostedTests/ATSProbeTests \
  -skip-testing:G02TransferUITests 2>&1) > "$logs/ios-hosted-tests.log" || hosted_status=$?
filter < "$logs/ios-hosted-tests.log"
echo "full xcodebuild logs: $logs/ios-package-tests.log, $logs/ios-hosted-tests.log"

echo "package tests exit status: ${package_status:-0}; hosted tests exit status: ${hosted_status:-0}"
if [[ "${package_status:-0}" != 0 || "${hosted_status:-0}" != 0 ]]; then exit 1; fi
# xcodebuild succeeds when a scheme has no tests; require passing runs that executed tests, none skipped.
for log in "$logs/ios-package-tests.log" "$logs/ios-hosted-tests.log"; do
  grep -Eq '✔ Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed' "$log" \
    || { echo "CHECK FAILED: no passing test run in $(basename "$log")"; exit 1; }
  if grep -Eq '➜ Test .* skipped|✘' "$log"; then echo "CHECK FAILED: skipped or failed tests in $(basename "$log")"; exit 1; fi
done
echo "checked: every Swift Testing run passed with at least one test and none skipped"
