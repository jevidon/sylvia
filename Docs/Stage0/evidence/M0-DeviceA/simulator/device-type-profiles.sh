#!/bin/bash
# Reads, read-only, the simulator device types and runtimes the device-A change relies on: the runtimes' supported
# device types for the phones it names, and each device type's profile (device-type-profiles.py beside this file).
#   Docs/Stage0/evidence/M0-DeviceA/simulator/device-type-profiles.sh > Docs/Stage0/evidence/M0-DeviceA/simulator/device-type-profiles.log 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
here=Docs/Stage0/evidence/M0-DeviceA/simulator
echo "command: $here/device-type-profiles.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m); $(xcodebuild -version | tr '\n' ' ')"
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "== the runtimes, and which of the phones named here each supports (xcrun simctl list runtimes -j)"
xcrun simctl list runtimes -j | python3 -I -c '
import json, sys
wanted = ["iPhone 13 mini", "iPhone 12 mini", "iPhone 11 Pro", "iPhone 11", "iPhone 11 Pro Max",
          "iPhone SE (2nd generation)", "iPhone SE (3rd generation)", "iPhone X", "iPhone Xs"]
for r in json.load(sys.stdin)["runtimes"]:
    names = [t["name"] for t in r.get("supportedDeviceTypes", [])]
    print("%s %s (%s), available %s: supports %s; not %s" % (
        r["identifier"], r["version"], r["buildversion"], r.get("isAvailable"),
        ", ".join(n for n in wanted if n in names) or "none of them",
        ", ".join(n for n in wanted if n not in names) or "-"))
'
echo
echo "== the device types (xcrun simctl list devicetypes -j, then each profile)"
xcrun simctl list devicetypes -j | python3 -I "$here/device-type-profiles.py"
echo "exit status: $?"
