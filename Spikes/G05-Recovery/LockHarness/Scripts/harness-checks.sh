#!/usr/bin/env bash
# The locked-device harness's checks (Spikes/G05-Recovery/LockHarness; T50, G0.5 recovery device checklist step 3;
# PO-23 option (b), product owner, 22 October 2026). Scripts/ci.d/71-g05-recovery.sh runs this as its steps 13-15;
# run alone, it checks the harness only, and says so (it is not a run of the drop-in). Fails on the first failure:
#   13. the lock: Package.resolved beside project.yml pins exactly what the package's ../Package.resolved pins
#       (sylvia_generate installs it into the generated project, which resolves the local package ..)
#   14. the unit tests, and the app's UI smoke test, on the simulator named by G05_SIM_NAME (default
#       Sylvia-M0-g05-recovery; created if missing, shut down when this script ends), with no warning in the build but
#       Xcode's appintentsmetadataprocessor notice that a target has no App Intents. The unit tests drive every state
#       of the device run on a simulated phone. The UI smoke test (since 22 October 2026: review H-05 of the decisions
#       round) runs the app itself from a new installation: launch, Start, 14 s in the background, back, Stop, and a
#       second launch; then the app's harness.log is copied out of the simulator and every line of that run checked
#       (harness-ui-smoke-check.log), and the app is uninstalled. The tone plays at the test volume, 0.01. The
#       simulator cannot lock, and its protection readback is not faithful, so nothing here is device evidence.
#   15. the app for a generic iOS device, Debug, signed automatically for team $SYLVIA_TEAM_ID with what is on this
#       host (no -allowProvisioningUpdates: nothing contacts Apple's developer service). Build only: nothing is
#       installed on or run on a device. Without an Apple Development identity on the host it is an unsigned compile
#       check, and the signing is recorded as pending. The signature, the team, the profile, the entitlements, the
#       Info.plist's background modes and its device family (iPhone only, UIDeviceFamily [1]: since 22 October 2026,
#       review H-08) are recorded.
# Logs go to $G05_LOG_DIR (default .build/g05-recovery/logs under the repository): harness-lock.log,
# harness-simulator-tests.log, harness-ui-smoke-harness.log, harness-ui-smoke-check.log, harness-device-build.log and
# harness-device-signing.txt.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

HARNESS="$SYLVIA_ROOT/Spikes/G05-Recovery/LockHarness"
BUNDLE_ID=com.jevidon.sylvia.spike.g05lockharness
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

step "14. harness unit tests and the app's UI smoke test on the simulator ($SIM_NAME)"
sylvia_generate "$HARNESS"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
trap 'sylvia_sim_shutdown "$UDID"' EXIT
# The UI smoke test starts from a new installation, so the log it leaves holds its own run only.
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
{
  echo "simulator: $SIM_NAME $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); load: $(uptime | sed 's/.*load averages*: //')"
} | tee "$LOGS/harness-simulator-tests.log"
xcodebuild test -project "$PROJECT" -scheme G05LockHarness -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution 2>&1 | tee -a "$LOGS/harness-simulator-tests.log"
plain "$LOGS/harness-simulator-tests.log" > "$LOGS/.harness-tests.plain"
grep -q "Test run with .* passed" "$LOGS/.harness-tests.plain" || { echo "FAIL: the harness tests did not pass"; exit 1; }
if grep -qE "✘|Test run with .* failed" "$LOGS/.harness-tests.plain"; then echo "FAIL: a harness test failed"; exit 1; fi
grep -q "Test Suite 'LockHarnessSmokeUITests' passed" "$LOGS/.harness-tests.plain" \
  || { echo "FAIL: the app's UI smoke test did not pass"; exit 1; }
grep -q "\*\* TEST SUCCEEDED \*\*" "$LOGS/.harness-tests.plain" || { echo "FAIL: xcodebuild test did not succeed"; exit 1; }
rm -f "$LOGS/.harness-tests.plain"
if [[ -n "$(harness_warnings "$LOGS/harness-simulator-tests.log")" ]]; then
  harness_warnings "$LOGS/harness-simulator-tests.log"
  echo "FAIL: warnings in the harness's simulator build"; exit 1
fi
# The app's own log of the UI smoke run, out of its container on the simulator (its lines hold only the harness's
# synthetic values and no path: HarnessLog), and every line of that run checked.
container="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
cp "$container/Library/Application Support/G05LockHarness/harness.log" "$LOGS/harness-ui-smoke-harness.log"
/usr/bin/python3 -I - "$LOGS/harness-ui-smoke-harness.log" <<'PY' 2>&1 | tee "$LOGS/harness-ui-smoke-check.log"
import re, sys

path = sys.argv[1]
problems = []

def fields(line):
    reason = None
    if ' reason="' in line:
        line, reason = line.split(' reason="', 1)
    parts = line.split(" ")
    out = {"time": parts[0], "event": parts[1] if len(parts) > 1 else ""}
    for part in parts[2:]:
        if "=" in part:
            key, value = part.split("=", 1)
            out[key] = value
    if reason is not None:
        out["reason"] = reason.rstrip('"')
    return out

lines = [fields(l) for l in open(path, encoding="utf-8").read().splitlines() if l.strip()]
def expect(ok, what):
    print(("ok    " if ok else "FAIL  ") + what)
    if not ok:
        problems.append(what)

def having(line, **want):
    return all(line.get(k) == v for k, v in want.items())

events = [l["event"] for l in lines]
launches = [i for i, l in enumerate(lines) if l["event"] == "launch"]
starts = [i for i, l in enumerate(lines) if l["event"] == "start"]
stops = [i for i, l in enumerate(lines) if l["event"] == "stop"]
attempts = [l for l in lines if l["event"] == "attempt"]
print("lines: %d; events: %s" % (len(lines), ", ".join("%s %d" % (e, events.count(e)) for e in sorted(set(events)))))
expect(len(launches) == 2 and len(starts) == 1 and len(stops) == 1 and launches[0] < starts[0] < stops[0] < launches[1],
       "two launches, one Start and one Stop, in that order: launch, start, stop, launch")
if len(launches) == 2 and len(starts) == 1 and len(stops) == 1:
    first, second = lines[launches[0]], lines[launches[1]]
    expect(all("state" not in lines[i] for i in launches),
           "no launch line records an application state (H-03: it reads background until a scene connects)")
    expect(having(first, platform="simulator", protectedDataAvailable="true", classA="absent"),
           "the first launch: platform=simulator protectedDataAvailable=true classA=absent (no canary before Start: H-04)")
    expect(having(second, platform="simulator", protectedDataAvailable="true", classA="readable"),
           "the second launch: classA=readable (the canary exists, and the simulator never locks)")
    expect(any(having(l, event="event", name="app-state", state="active") for l in lines[launches[0]:starts[0]]),
           "the first launch's activation is recorded (event name=app-state state=active) before the Start")
    start = lines[starts[0]]
    expect(having(start, volume="0.01", volumeReason="test-volume", audio="playing", store="open", canary="created",
                  session="ok", protection="NSFileProtectionCompleteUntilFirstUserAuthentication",
                  durability="journal_mode=wal,synchronous=FULL,fullfsync=1,checkpoint_fullfsync=1"),
           "the start line: volume=0.01 (test volume) audio=playing store=open canary=created session=ok, class C, D17's durability")
    run = start.get("run")
    expect(len(attempts) >= 10 and [a.get("n") for a in attempts] == [str(i) for i in range(1, len(attempts) + 1)],
           "at least 10 attempts, numbered from 1 without a break (%d)" % len(attempts))
    expect(all(having(a, run=run, save="saved", readback="equal", file="ok", session="ok", classes="simulator-unverified",
                      protectedDataAvailable="true", classA="readable") for a in attempts),
           "every attempt: save=saved readback=equal file=ok session=ok classes=simulator-unverified classA=readable")
    background = [a for a in attempts if a.get("app") == "background"]
    expect(len(background) >= 5, "at least 5 attempts made in the background, the tone keeping the app running (%d)" % len(background))
    times = [float(a["t"]) for a in attempts]
    deltas = [b - a for a, b in zip(times, times[1:])]
    expect(bool(deltas) and max(deltas) <= 5.0,
           "no pause between attempts above the 5 s gap threshold (between %.1f and %.1f s)" % (min(deltas or [0]), max(deltas or [0])))
    expect("gap" not in events, "no gap line")
    expect(any(having(l, event="event", name="app-state", state="background") for l in lines[starts[0]:stops[0]])
           and any(having(l, event="event", name="app-state", state="active") for l in lines[starts[0]:stops[0]]),
           "the run went to the background and came back (app-state events)")
    stop = lines[stops[0]]
    expect(having(stop, run=run, failures="0", gaps="0", lockedAttempts="0", session="ok")
           and stop.get("attempts") == str(len(attempts)),
           "the stop line: failures=0 gaps=0 lockedAttempts=0 session=ok, its attempts the attempt lines' count")
    after_stop = [l for l in lines[stops[0]:launches[1]] if l["event"] == "verify"]
    acknowledged = stop.get("acknowledged")
    expect(bool(after_stop) and having(after_stop[0], result="ok", run=run, acknowledged=acknowledged, extra="0",
                                         integrity="ok", foreignKeyViolations="0", failures="0"),
           "the check after Stop: verify result=ok acknowledged=%s extra=0 integrity=ok foreignKeyViolations=0 failures=0" % acknowledged)
    previous = [l for l in lines[launches[1]:] if l["event"] == "previous-session"]
    verifies = [l for l in lines[launches[1]:] if l["event"] == "verify"]
    expect(bool(previous) and having(previous[0], when="launch", result="stopped-cleanly", run=run, failures="0", gaps="0"),
           "the second launch reads the run as stopped-cleanly (previous-session when=launch)")
    expect(bool(verifies) and having(verifies[0], result="ok", run=run, acknowledged=acknowledged, extra="0"),
           "the second launch's check of the library: verify result=ok acknowledged=%s extra=0" % acknowledged)
    refresh = sorted({l.get("result", "") for l in lines if l["event"] == "refresh"})
    print("recorded, not checked: refresh results %s (BGTaskScheduler is not available in the simulator)" % ", ".join(refresh))
print("result: %s" % ("PASS" if not problems else "FAIL (%d)" % len(problems)))
sys.exit(1 if problems else 0)
PY
xcrun simctl uninstall "$UDID" "$BUNDLE_ID"
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
family="$(plutil -extract UIDeviceFamily json -o - "$APP/Info.plist")"
echo "-- UIDeviceFamily of the built app (plutil -extract): $family (1 is iPhone, 2 is iPad)" >> "$SIGNING"
[[ "$family" == "[1]" ]] || { echo "FAIL: the app is not built for iPhone only: UIDeviceFamily $family"; exit 1; }
cat "$SIGNING"

echo
echo "G0.5 recovery lock harness: steps 13-15 passed (logs in $LOGS)"
