#!/bin/bash
# The recovery suite's device host (Spikes/G05-Recovery/DeviceTests, Codex's project of 26 October 2026, unchanged)
# generated with sylvia_generate and built for a generic iOS device with xcodebuild build-for-testing: the app host
# and the test bundle that compiles the unchanged Tests/SylviaRecoveryTests sources with this branch's changes. Build
# only and unsigned (CODE_SIGNING_ALLOWED=NO): nothing contacts Apple's developer service, nothing is installed on or
# run on a device. The owner's device run (runbook step 1.2) signs it with -allowProvisioningUpdates.
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/build-devicetests.sh
# Log: Docs/Stage0/evidence/M0-DeviceFixes/recovery/devicetests-ios-build.log
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
out="Docs/Stage0/evidence/M0-DeviceFixes/recovery/devicetests-ios-build.log"
source Scripts/lib/env.sh
source Scripts/lib/xcodegen.sh
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/build-devicetests.sh"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "---- sylvia_generate Spikes/G05-Recovery/DeviceTests"
} > "$out"
sylvia_generate Spikes/G05-Recovery/DeviceTests >> "$out" 2>&1 || { echo "FAIL: sylvia_generate" >> "$out"; exit 1; }
echo "---- xcodebuild build-for-testing, generic/platform=iOS, unsigned" >> "$out"
(cd Spikes/G05-Recovery && xcodebuild build-for-testing -project DeviceTests/G05RecoveryDeviceTests.xcodeproj \
  -scheme G05RecoveryDeviceTests -destination "generic/platform=iOS" -derivedDataPath DeviceTests/.build/DerivedData \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO) >> "$out" 2>&1
status=$?
{
  echo "---- xcodebuild exit: $status"
  echo "warnings in Spikes/G05-Recovery sources and tests: $(grep -cE 'Spikes/G05-Recovery/(Sources|Tests)/[^:]+:[0-9]+:[0-9]+: warning:' "$out")"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$out"
exit $status
