#!/usr/bin/env python3
"""The simulator device types of the phones the device-A change of 24 October 2026 names, read from Xcode 27.1's
CoreSimulator profiles (read-only; nothing is created or booted).

For each device type: its identifier and bundle path (from `xcrun simctl list devicetypes -j`, read on stdin), the
model identifier (Contents/Resources/profile.plist), and the main screen's panel in pixels, its pixel pitch and its
scale (the ScreenDimensionsCapability of Contents/Resources/capabilities.plist). The last column divides the panel's
pixels by that scale. That is the layout size in points only where iOS renders at the panel's own resolution: on the
iPhone 12 mini and 13 mini it renders at scale 3 and then downsamples to the panel (a native scale of 2.88), so their
layout size is not this quotient; the screen probe beside this file reads what iOS reports instead (screen-probe.log).
Run by device-type-profiles.sh, with DEVELOPER_DIR set to the pinned Xcode:
    xcrun simctl list devicetypes -j | python3 -I device-type-profiles.py
"""
import json
import plistlib
import sys
from pathlib import Path

NAMES = ["iPhone 13 mini", "iPhone 12 mini", "iPhone 11 Pro", "iPhone 11", "iPhone 11 Pro Max",
         "iPhone SE (2nd generation)", "iPhone SE (3rd generation)", "iPhone 17 Pro"]


def main() -> int:
    types = {t["name"]: t for t in json.load(sys.stdin)["devicetypes"]}
    missing = 0
    for name in NAMES:
        t = types.get(name)
        if t is None:
            print(f"{name}: device type not installed")
            missing += 1
            continue
        res = Path(t["bundlePath"]) / "Contents/Resources"
        profile = plistlib.loads((res / "profile.plist").read_bytes())
        caps_path = res / "capabilities.plist"
        caps = plistlib.loads(caps_path.read_bytes()) if caps_path.exists() else {}
        screen = caps.get("capabilities", {}).get("ScreenDimensionsCapability", {})
        w_px, h_px = screen.get("main-screen-width"), screen.get("main-screen-height")
        scale, pitch = screen.get("main-screen-scale"), screen.get("main-screen-pitch")
        quotient = f"{w_px / scale:g} x {h_px / scale:g}" if w_px and h_px and scale else "n/a"
        print(f"{name}: device type {t['identifier']}; modelIdentifier {profile.get('modelIdentifier')}; "
              f"panel {w_px} x {h_px} px, pitch {pitch} ppi, scale {scale}; panel pixels / scale: {quotient}; "
              f"profile {res / 'profile.plist'}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
