#!/bin/bash
# The device-A change of 24 October 2026 (the product owner's iPhone 13 mini in place of the iPhone 11 Pro): what iOS
# reports for the main screen of the iPhone 13 mini simulator, beside the iPhone 11 Pro's and those of the other
# oldest iPhones iOS 26 supports (the iPhone 11, the iPhone 11 Pro Max and the iPhone SE (2nd generation)), under the
# pinned Xcode 27.1 on the iOS 26.5 runtime. A throwaway Swift package with one XCTest, written by this script under
# .build/scratch (never committed), prints UIScreen.main's bounds, scale, nativeScale and nativeBounds (UIScreen.main is
# deprecated in iOS 26, a warning only), and the simulator's own model identifier and runtime. The script creates one simulator of each device type, runs the test on each, and deletes the
# simulators at the end (a trap deletes them on any exit). It refuses to start if a simulator of any of its names exists,
# so it never deletes one it did not create. No physical device is used; nothing plays audio.
#   Docs/Stage0/evidence/M0-DeviceA/simulator/screen-probe.sh > Docs/Stage0/evidence/M0-DeviceA/simulator/screen-probe.log 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
echo "command: Docs/Stage0/evidence/M0-DeviceA/simulator/screen-probe.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m); $(xcodebuild -version | tr '\n' ' ')"
sylvia_check_xcode && echo "sylvia_check_xcode: the installed build is the pin, $SYLVIA_XCODE_BUILD_PINNED"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
runtime="$SYLVIA_SIM_RUNTIME"
echo "runtime: $runtime"
xcrun simctl list runtimes | grep -F "$(echo "$runtime" | sed 's/.*iOS-\([0-9]*\)-\([0-9]*\)/iOS \1.\2/')" || true

pkg="$root/.build/scratch/m0-devicea-screen-probe"
rm -rf "$pkg"
mkdir -p "$pkg/Sources/ScreenProbe" "$pkg/Tests/ScreenProbeTests"
cat > "$pkg/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScreenProbe",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "ScreenProbe", targets: ["ScreenProbe"])],
    targets: [
        .target(name: "ScreenProbe"),
        .testTarget(name: "ScreenProbeTests", dependencies: ["ScreenProbe"]),
    ]
)
SWIFT
cat > "$pkg/Sources/ScreenProbe/ScreenProbe.swift" <<'SWIFT'
/// A throwaway package for the device-A change's screen probe (Docs/Stage0/evidence/M0-DeviceA/simulator/).
public enum ScreenProbe {
    public static let name = "ScreenProbe"
}
SWIFT
cat > "$pkg/Tests/ScreenProbeTests/ScreenProbeTests.swift" <<'SWIFT'
import ScreenProbe
import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class ScreenProbeTests: XCTestCase {
    @MainActor
    func testMainScreen() throws {
        #if canImport(UIKit)
        let environment = ProcessInfo.processInfo.environment
        let screen = UIScreen.main
        print("SCREEN-PROBE simulator: \(environment["SIMULATOR_DEVICE_NAME"] ?? "?"); "
              + "model identifier \(environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "?"); "
              + "runtime \(environment["SIMULATOR_RUNTIME_VERSION"] ?? "?") (\(environment["SIMULATOR_RUNTIME_BUILD_VERSION"] ?? "?"))")
        print("SCREEN-PROBE UIScreen.main.bounds: \(screen.bounds.size.width) x \(screen.bounds.size.height) pt")
        print("SCREEN-PROBE UIScreen.main.scale: \(screen.scale)")
        print("SCREEN-PROBE UIScreen.main.nativeScale: \(screen.nativeScale)")
        print("SCREEN-PROBE UIScreen.main.nativeBounds: \(screen.nativeBounds.size.width) x \(screen.nativeBounds.size.height) px")
        print("SCREEN-PROBE bounds x scale: \(screen.bounds.size.width * screen.scale) x \(screen.bounds.size.height * screen.scale) px")
        XCTAssertGreaterThan(screen.bounds.size.width, 0)
        #else
        throw XCTSkip("UIKit is not available on this platform")
        #endif
    }
}
SWIFT
echo
echo "== the test package (written by this script; not committed)"
for f in Package.swift Sources/ScreenProbe/ScreenProbe.swift Tests/ScreenProbeTests/ScreenProbeTests.swift; do
  echo "--- $f"
  cat "$pkg/$f"
done

# Device A (the iPhone 13 mini), the iPhone 11 Pro it replaces, and the other oldest iPhones iOS 26 supports.
names=(Sylvia-M0-DeviceA-13mini Sylvia-M0-DeviceA-11Pro Sylvia-M0-DeviceA-11 Sylvia-M0-DeviceA-11ProMax
  Sylvia-M0-DeviceA-SE2)
types=(com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro
  com.apple.CoreSimulator.SimDeviceType.iPhone-11 com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max
  com.apple.CoreSimulator.SimDeviceType.iPhone-SE--2nd-generation-)
for name in "${names[@]}"; do
  if [[ -n "$(sylvia_sim_find "$name" "$runtime")" ]]; then
    echo "refused: a simulator named $name already exists; this script deletes only simulators it creates"
    exit 2
  fi
done
created=()
cleanup() {
  local udid name
  for udid in ${created[@]+"${created[@]}"}; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" && echo "deleted simulator $udid"
  done
  for name in "${names[@]}"; do
    if [[ -n "$(sylvia_sim_find "$name" "$runtime")" ]]; then
      echo "PROBLEM: a simulator named $name is still there"
    else
      echo "no simulator named $name remains"
    fi
  done
}
trap cleanup EXIT

status=0
for i in "${!names[@]}"; do
  name="${names[$i]}"
  devtype="${types[$i]}"
  echo
  echo "== $name ($devtype, $runtime)"
  udid="$(xcrun simctl create "$name" "$devtype" "$runtime")" || { echo "could not create $name"; status=1; continue; }
  created+=("$udid")
  echo "created simulator $udid"
  sylvia_sim_boot "$udid"
  echo "booted; load: $(uptime)"
  log="$pkg/xcodebuild-$name.log"
  (cd "$pkg" && xcodebuild test -scheme ScreenProbe -destination "id=$udid" \
    -derivedDataPath "$pkg/.build/DerivedData" -disableAutomaticPackageResolution) > "$log" 2>&1
  xb=$?
  echo "xcodebuild test exit: $xb (its full output: .build/scratch/m0-devicea-screen-probe/xcodebuild-$name.log, not committed)"
  grep -E '^SCREEN-PROBE|Test Suite .ScreenProbeTests|Test Case .*testMainScreen|Executed [0-9]+ test|\*\* TEST (SUCCEEDED|FAILED) \*\*' "$log"
  (( xb == 0 )) || status=1
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
done
echo
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "probe exit: $status"
exit $status
