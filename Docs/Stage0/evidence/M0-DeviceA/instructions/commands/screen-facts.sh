#!/bin/bash
# The screen facts the device-A change of 24 October 2026 relies on (the product owner's iPhone 13 mini in place of the
# iPhone 11 Pro), read on the build Mac with the pinned Xcode 27.1. Host and simulator only: no device is contacted.
#   1. Xcode's simulator device types for the iPhone 13 mini, the iPhone 11 Pro, the iPhone 11, the iPhone 12 mini and
#      the iPhone SE (2nd and 3rd generation): name, identifier and model identifier (`xcrun simctl list devicetypes`).
#   2. For the 13 mini, the 11 Pro, the 11 and the SE (2nd generation), each profile's main display as its
#      capabilities.plist gives it (pixels, the canvas iOS draws, scale, pixels per inch) and its
#      ScreenDimensionsCapability, with the layout size in points (canvas / scale) and the width of a 375-point line
#      in inches (pixels across those points / ppi) computed from them, and the 13 mini's against the 11 Pro's.
#   3. The layout size confirmed on the simulator: a probe app, compiled here with swiftc into .build/scratch (never
#      committed), prints UIScreen's bounds, scale, nativeScale and nativeBounds at launch and exits; it runs on two
#      simulators this script creates on the iOS 26.5 runtime (Sylvia-M0-DeviceA-13mini, an iPhone 13 mini, and
#      Sylvia-M0-DeviceA-11Pro, an iPhone 11 Pro, the control) and deletes at the end. A simulator lays out as the
#      device type says; it is not a device result.
#   Docs/Stage0/evidence/M0-DeviceA/instructions/commands/screen-facts.sh <log>
# Exit status 1 if any expected value differs (the 13 mini: iPhone14,4, 375 x 812 pt at scale 3, 1080 x 2340 pixels,
# 476 ppi; the 11 Pro: iPhone12,3, 375 x 812 pt, 1125 x 2436 pixels, 458 ppi) or the probe does not report.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"  # six folders up: commands, instructions, M0-DeviceA, evidence, Stage0, Docs
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
status=0
work=.build/scratch/devicea-screen-probe
rm -rf "$work"
mkdir -p "$work"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Simulator device types (xcrun simctl list devicetypes -j)"
} > "$log" 2>&1
xcrun simctl list devicetypes -j > "$work/devicetypes.json"
python3 -I - "$work/devicetypes.json" >> "$log" 2>&1 <<'PY' || status=1
import json, sys
types = {t["name"]: t for t in json.load(open(sys.argv[1]))["devicetypes"]}
expected = {"iPhone 13 mini": "iPhone14,4", "iPhone 11 Pro": "iPhone12,3", "iPhone 11": "iPhone12,1",
            "iPhone 12 mini": "iPhone13,1", "iPhone SE (2nd generation)": "iPhone12,8", "iPhone SE (3rd generation)": "iPhone14,6"}
bad = 0
for name, model in expected.items():
    t = types.get(name)
    if t is None:
        print(f"PROBLEM {name}: no such device type"); bad += 1; continue
    ok = t.get("modelIdentifier") == model
    bad += 0 if ok else 1
    print(f"{'ok     ' if ok else 'PROBLEM'} {name}: identifier {t['identifier']}; modelIdentifier {t.get('modelIdentifier')} "
          f"(expected {model}); profile {t['bundlePath']}")
sys.exit(1 if bad else 0)
PY
{
  echo
  echo "== 2. Each profile's main display (Contents/Resources/capabilities.plist), and what follows from it"
} >> "$log"
python3 -I - "$work/devicetypes.json" >> "$log" 2>&1 <<'PY' || status=1
import json, plistlib, sys
from pathlib import Path
types = {t["name"]: t for t in json.load(open(sys.argv[1]))["devicetypes"]}
expected = {"iPhone 13 mini": (1080, 2340, 1125, 2436, 3, 476), "iPhone 11 Pro": (1125, 2436, 1125, 2436, 3, 458),
            "iPhone 11": None, "iPhone SE (2nd generation)": None}
bad = 0
widths = {}
for name, want in expected.items():
    caps = plistlib.loads((Path(types[name]["bundlePath"]) / "Contents/Resources/capabilities.plist").read_bytes())["capabilities"]
    main = caps["displays"][0]
    dims = caps.get("ScreenDimensionsCapability", {})
    w, h = main["width"], main["height"]
    cw, ch = main.get("canvasWidth", w), main.get("canvasHeight", h)
    scale, ppi = main["scale"], main["hdpi"]
    pt_w, pt_h = cw / scale, ch / scale
    inches = w / ppi
    widths[name] = inches
    print(f"{name}: displays[0] width {w}, height {h}, canvasWidth {main.get('canvasWidth')}, canvasHeight "
          f"{main.get('canvasHeight')}, scale {scale}, hdpi {ppi}, vdpi {main['vdpi']}; ScreenDimensionsCapability "
          + ", ".join(f"{k} {dims[k]}" for k in sorted(dims)))
    print(f"   layout size (canvas / scale): {pt_w:g} x {pt_h:g} pt; pixels across the width: {w}, so {w / pt_w:.4g} "
          f"pixels per point (the native scale); the width's physical size: {w} / {ppi} = {inches:.4f} in")
    if want is not None:
        got = (w, h, cw, ch, scale, ppi)
        if got != want:
            print(f"   PROBLEM: expected width, height, canvas, scale and ppi {want}, read {got}"); bad += 1
        else:
            print("   ok: as expected")
ratio = widths["iPhone 13 mini"] / widths["iPhone 11 Pro"]
print(f"the 13 mini's 375-pt width against the 11 Pro's: {widths['iPhone 13 mini']:.4f} / {widths['iPhone 11 Pro']:.4f} "
      f"= {ratio:.4f}, so the 13 mini draws each point {100 * (1 - ratio):.1f}% smaller")
sys.exit(1 if bad else 0)
PY
{
  echo
  echo "== 3. The layout size on the simulator: a probe app on an iPhone 13 mini and an iPhone 11 Pro (iOS 26.5)"
} >> "$log"
app="$work/ScreenProbe.app"
mkdir -p "$app"
cat > "$work/main.swift" <<'SWIFT'
// Stage 0 probe (never shipped): prints the main screen's geometry at launch, then exits.
import UIKit

@main
final class ProbeDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let screen = UIScreen.main
        let bounds = screen.bounds.size
        let native = screen.nativeBounds.size
        print("SCREEN bounds_pt=\(Int(bounds.width))x\(Int(bounds.height)) scale=\(screen.scale) "
              + "nativeScale=\(screen.nativeScale) nativeBounds_px=\(Int(native.width))x\(Int(native.height)) "
              + "system=\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        fflush(stdout)
        exit(0)
    }
}
SWIFT
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.jevidon.sylvia.spike.screenprobe</string>
  <key>CFBundleExecutable</key><string>ScreenProbe</string>
  <key>CFBundleName</key><string>ScreenProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>MinimumOSVersion</key><string>26.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>UILaunchScreen</key><dict/>
</dict>
</plist>
PLIST
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
if xcrun --sdk iphonesimulator swiftc -sdk "$sdk" -target arm64-apple-ios26.0-simulator -parse-as-library \
     "$work/main.swift" -o "$app/ScreenProbe" > "$work/compile.log" 2>&1 \
   && codesign --force --sign - --timestamp=none "$app" >> "$work/compile.log" 2>&1; then
  echo "probe compiled (swiftc, arm64-apple-ios26.0-simulator, the iOS Simulator SDK of $(xcrun --sdk iphonesimulator --show-sdk-version)) and signed ad hoc" >> "$log"
else
  { echo "PROBLEM: the probe did not compile:"; cat "$work/compile.log"; } >> "$log"; status=1
fi
probe() { # simulator name, device type, expected SCREEN prefix
  local name="$1" type="$2" want="$3" udid out
  udid="$(sylvia_sim_udid "$name" "$type" "$SYLVIA_SIM_RUNTIME")"
  echo "-- $name ($type, $SYLVIA_SIM_RUNTIME): $udid" >> "$log"
  sylvia_sim_boot "$udid"
  xcrun simctl install "$udid" "$app" >> "$log" 2>&1
  out="$(perl -e 'alarm shift; exec @ARGV' 180 xcrun simctl launch --console-pty --terminate-running-process "$udid" \
           com.jevidon.sylvia.spike.screenprobe 2>&1 | tr -d '\r' | grep '^SCREEN ' | head -n 1)"
  echo "   $out" >> "$log"
  if [[ "$out" == "$want"* ]]; then echo "   ok: $want" >> "$log"; else echo "   PROBLEM: expected $want" >> "$log"; status=1; fi
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" && echo "   simulator $name deleted (this script created it)" >> "$log"
}
if [[ -x "$app/ScreenProbe" ]]; then
  probe Sylvia-M0-DeviceA-13mini com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini \
    "SCREEN bounds_pt=375x812 scale=3.0 nativeScale=2.88 nativeBounds_px=1080x2340"
  probe Sylvia-M0-DeviceA-11Pro com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro \
    "SCREEN bounds_pt=375x812 scale=3.0 nativeScale=3.0 nativeBounds_px=1125x2436"
fi
rm -rf "$work"
{
  echo
  echo "exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log"
exit $status
