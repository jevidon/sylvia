#!/usr/bin/env bash
# The locked-device harness's checks (Spikes/G05-Recovery/LockHarness; T50, G0.5 recovery device checklist step 3;
# PO-23 option (b), product owner, 22 October 2026). Scripts/ci.d/71-g05-recovery.sh runs this as its steps 13-15;
# run alone, it checks the harness only, and says so (it is not a run of the drop-in). Fails on the first failure:
#   13. the lock: Package.resolved beside project.yml pins exactly what the package's ../Package.resolved pins
#       (sylvia_generate installs it into the generated project, which resolves the local package ..)
#   14. the unit tests on the simulator named by G05_SIM_NAME (default Sylvia-M0-g05-recovery; created if missing,
#       shut down when this script ends), with no warning in the build but Xcode's appintentsmetadataprocessor notice
#       that a target has no App Intents. The tests drive every state of the device run on a simulated phone; the
#       simulator cannot lock, and its protection readback is not faithful, so nothing here is device evidence.
#   15. the app for a generic iOS device, Debug, signed automatically for team $SYLVIA_TEAM_ID with what is on this
#       host (no -allowProvisioningUpdates: nothing contacts Apple's developer service). Build only: nothing is
#       installed on or run on a device. Without an Apple Development identity on the host it is an unsigned compile
#       check, and the signing is recorded as pending. The signature, the team, the profile, the entitlements and the
#       Info.plist's background modes are recorded.
# Logs go to $G05_LOG_DIR (default .build/g05-recovery/logs under the repository): harness-lock.log,
# harness-simulator-tests.log, harness-device-build.log and harness-device-signing.txt.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

HARNESS="$SYLVIA_ROOT/Spikes/G05-Recovery/LockHarness"
LOGS="${G05_LOG_DIR:-$SYLVIA_ROOT/.build/g05-recovery/logs}"
SIM_NAME="${G05_SIM_NAME:-Sylvia-M0-g05-recovery}"
DERIVED="$HARNESS/.build/DerivedData"
PROJECT="$HARNESS/G05LockHarness.xcodeproj"
mkdir -p "$LOGS"
LOGS="$(cd "$LOGS" && pwd)"

step() { echo; echo "=== $1"; }
plain() { perl -pe 's/\e\[[0-9;]*m//g' "$1"; }
# Warnings in a build log, except the App Intents metadata tool's notice about targets that use no App Intents
# (Xcode's, printed for the package's targets too; the G0.5 recovery report records it).
harness_warnings() { plain "$1" | grep -E "warning:" | grep -v "appintentsmetadataprocessor" || true; }

step "13. harness lock: LockHarness/Package.resolved pins what ../Package.resolved pins"
/usr/bin/python3 -I - "$HARNESS/Package.resolved" "$HARNESS/../Package.resolved" <<'PY' 2>&1 | tee "$LOGS/harness-lock.log"
import json, sys

def pins(path):
    with open(path) as handle:
        data = json.load(handle)
    return data.get("originHash"), {p["identity"]: (p["location"], p["state"].get("version"), p["state"].get("revision")) for p in data["pins"]}

mine_hash, mine = pins(sys.argv[1])
theirs_hash, theirs = pins(sys.argv[2])
if mine != theirs:
    print("MISMATCH: LockHarness/Package.resolved does not pin what ../Package.resolved pins")
    for name in sorted(set(mine) | set(theirs)):
        if mine.get(name) != theirs.get(name):
            print("  %s: %s vs %s" % (name, mine.get(name), theirs.get(name)))
    sys.exit(1)
print("ok: LockHarness/Package.resolved pins exactly what ../Package.resolved pins: "
      + ", ".join("%s %s %s" % (k, v[1], v[2]) for k, v in sorted(mine.items())))
print("originHash %s" % ("equal" if mine_hash == theirs_hash else "differs (%s vs %s)" % (mine_hash, theirs_hash)))
PY

step "14. harness unit tests on the simulator ($SIM_NAME)"
sylvia_generate "$HARNESS"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
trap 'sylvia_sim_shutdown "$UDID"' EXIT
{
  echo "simulator: $SIM_NAME $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); load: $(uptime | sed 's/.*load averages*: //')"
} | tee "$LOGS/harness-simulator-tests.log"
xcodebuild test -project "$PROJECT" -scheme G05LockHarness -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution 2>&1 | tee -a "$LOGS/harness-simulator-tests.log"
plain "$LOGS/harness-simulator-tests.log" > "$LOGS/.harness-tests.plain"
grep -q "Test run with .* passed" "$LOGS/.harness-tests.plain" || { echo "FAIL: the harness tests did not pass"; exit 1; }
if grep -qE "✘|Test run with .* failed" "$LOGS/.harness-tests.plain"; then echo "FAIL: a harness test failed"; exit 1; fi
rm -f "$LOGS/.harness-tests.plain"
if [[ -n "$(harness_warnings "$LOGS/harness-simulator-tests.log")" ]]; then
  harness_warnings "$LOGS/harness-simulator-tests.log"
  echo "FAIL: warnings in the harness's simulator build"; exit 1
fi
sylvia_sim_shutdown "$UDID"
trap - EXIT
echo "simulator $SIM_NAME shut down"

step "15. harness app for a generic iOS device (Debug; automatic signing for team $SYLVIA_TEAM_ID; build only)"
SIGNING="$LOGS/harness-device-signing.txt"
APP="$DERIVED/Build/Products/Debug-iphoneos/G05LockHarness.app"
{
  echo "# The harness app built for a generic iOS device (Debug, automatic signing). Host macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | head -1) ($(xcodebuild -version | awk '/Build version/ {print $3}'))."
  echo "# Build only: nothing is installed on or run on a device (device checklist step 3 installs it)."
} > "$SIGNING"
if security find-identity -v -p codesigning | grep -q '"Apple Development: '; then
  xcodebuild build -project "$PROJECT" -scheme G05LockHarness -configuration Debug -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$SYLVIA_TEAM_ID" 2>&1 \
    | tee "$LOGS/harness-device-build.log"
  grep -q "\*\* BUILD SUCCEEDED \*\*" "$LOGS/harness-device-build.log" || { echo "FAIL: the device build did not succeed"; exit 1; }
  codesign --verify --strict "$APP"
  details="$(codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)=' || true)"
  grep -q "^TeamIdentifier=$SYLVIA_TEAM_ID\$" <<<"$details" || { echo "FAIL: the app is not signed by team $SYLVIA_TEAM_ID: $details"; exit 1; }
  {
    echo "== G05LockHarness.app: codesign --verify --strict ok"
    echo "$details"
    security cms -D -i "$APP/embedded.mobileprovision" > "$LOGS/.profile.plist"
    for key in Name TeamIdentifier:0 ExpirationDate; do
      echo "profile $key=$(/usr/libexec/PlistBuddy -c "Print :$key" "$LOGS/.profile.plist")"
    done
    rm -f "$LOGS/.profile.plist"
    echo "-- entitlements (codesign -d --entitlements)"
    codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>&1 \
      | { grep -E 'application-identifier|team-identifier|get-task-allow' || echo "(no entitlement lines read)"; } | sed -E 's/^ +//'
  } >> "$SIGNING"
else
  xcodebuild build -project "$PROJECT" -scheme G05LockHarness -configuration Debug -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO 2>&1 \
    | tee "$LOGS/harness-device-build.log"
  grep -q "\*\* BUILD SUCCEEDED \*\*" "$LOGS/harness-device-build.log" || { echo "FAIL: the device build did not succeed"; exit 1; }
  echo "no Apple Development identity on this host: unsigned compile check only; signing pending (device checklist step 3)" >> "$SIGNING"
fi
if [[ -n "$(harness_warnings "$LOGS/harness-device-build.log")" ]]; then
  harness_warnings "$LOGS/harness-device-build.log"
  echo "FAIL: warnings in the harness's device build"; exit 1
fi
{
  echo "-- Info.plist of the built app (plutil -p): background modes and the refresh task"
  plutil -p "$APP/Info.plist" | sed -n '/UIBackgroundModes/,/]/p;/BGTaskSchedulerPermittedIdentifiers/,/]/p' | sed -E 's/^ +//'
} >> "$SIGNING"
plutil -extract UIBackgroundModes json -o - "$APP/Info.plist" | grep -q '"audio"' || { echo "FAIL: the app does not declare background audio"; exit 1; }
cat "$SIGNING"

echo
echo "G0.5 recovery lock harness: steps 13-15 passed (logs in $LOGS)"
