#!/bin/bash
# The build Mac's Xcode, Swift, SDKs, simulator runtimes and device types after Xcode updated itself from 27.0
# (27A266a) to 27.1 (27A9275) on 18 October 2026, recorded for the re-pin to 27.1 that the product owner chose on
# 20 October 2026 (PO-35, D-3; ADR-0001; integration log section 13). Read-only, except one step: it creates the
# named simulator (iPhone 17, iOS 26.5, the drop-ins' default) if it does not exist, boots it to show that the runtime
# the drop-ins use still boots under 27.1's simulator components, and shuts it down; the agent deletes it at the end
# of the round. No device is listed or contacted (devicectl prints only its version), nothing is installed, updated
# or downloaded, and no setting is changed: the App Store's automatic-update setting is only read.
#
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/toolchain-state.sh <simulator name> > <log> 2>&1
set -uo pipefail
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
sim_name="${1:?usage: toolchain-state.sh <simulator name>}"

echo "command: Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/toolchain-state.sh $sim_name"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ) ($(date '+%Y-%m-%d %H:%M %Z') on the build Mac's clock)"
echo "load: $(uptime)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"

echo
echo "== Xcode (DEVELOPER_DIR=$DEVELOPER_DIR)"
xcodebuild -version
echo "version.plist ProductBuildVersion: $(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$DEVELOPER_DIR/../version.plist" 2>&1)"
echo "Info.plist CFBundleShortVersionString: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEVELOPER_DIR/../Info.plist" 2>&1)"
echo "Xcode.app modified: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S %Z' /Applications/Xcode.app)"
if [[ -f /Applications/Xcode.app/Contents/_MASReceipt/receipt ]]; then
  echo "Mac App Store receipt: present (Contents/_MASReceipt/receipt): installed or updated by the App Store"
else
  echo "Mac App Store receipt: absent"
fi
echo "Xcode applications in /Applications: $(ls -d /Applications/Xcode*.app 2>/dev/null | tr '\n' ' ')"
echo "Scripts/lib/env.sh pin at this commit: SYLVIA_XCODE_BUILD_PINNED=$SYLVIA_XCODE_BUILD_PINNED"
if sylvia_check_xcode; then
  echo "sylvia_check_xcode: the installed build matches the pin"
else
  echo "sylvia_check_xcode: the installed build differs from the pin (warning above)"
fi
echo
echo "== Swift"
xcrun swift --version 2>&1
echo
echo "== SDKs (xcodebuild -showsdks)"
xcodebuild -showsdks 2>/dev/null | grep -E -- '-sdk ' | sed 's/^[[:space:]]*/  /'
echo
echo "== Simulator runtimes (xcrun simctl list runtimes)"
xcrun simctl list runtimes 2>&1
for runtime in "$SYLVIA_SIM_RUNTIME" "$SYLVIA_SIM_RUNTIME_LATEST"; do
  if xcrun simctl list runtimes 2>/dev/null | grep -q -- "- $runtime\$"; then
    echo "present: $runtime"
  else
    echo "MISSING: $runtime"
  fi
done
echo
echo "== The device types the drop-ins use (Scripts/lib/env.sh default; 21-design-catalog's SE and iPad)"
for devtype in "$SYLVIA_SIM_DEVICE_TYPE" com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation \
               com.apple.CoreSimulator.SimDeviceType.iPad-A16; do
  line="$(xcrun simctl list devicetypes 2>/dev/null | grep -F "($devtype)")"
  if [[ -n "$line" ]]; then echo "present: $line"; else echo "MISSING: $devtype"; fi
done
echo
echo "== Every device type (xcrun simctl list devicetypes)"
xcrun simctl list devicetypes 2>&1
echo
echo "== The iOS 26.5 runtime boots under these simulator components ($sim_name, created by sylvia_sim_udid)"
udid="$(sylvia_sim_udid "$sim_name")"
echo "simulator: $sim_name $udid ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)"
if sylvia_sim_boot "$udid"; then
  echo "booted: $(xcrun simctl list devices 2>/dev/null | grep -F "$udid" | sed 's/^[[:space:]]*//')"
else
  echo "BOOT FAILED"
fi
sylvia_sim_shutdown "$udid"
echo "after shutdown: $(xcrun simctl list devices 2>/dev/null | grep -F "$udid" | sed 's/^[[:space:]]*//')"
echo
echo "== devicectl (version only; no device listed or contacted)"
echo "devicectl version: $(xcrun devicectl --version 2>&1)"
echo
echo "== App Store automatic updates (read-only)"
echo "defaults read /Library/Preferences/com.apple.commerce AutoUpdate: $(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>&1)"
echo
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
