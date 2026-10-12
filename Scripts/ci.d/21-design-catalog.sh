#!/usr/bin/env bash
# G0.6 part 3 (plan 4.1-4.4, 18.3, 21.2; ADR-0013 Section 11): the design catalog app
# (Apps/DesignCatalog), a product UI target that consumes Packages/Design.
#
# Steps: the design lint over the catalog with no exemptions; project generation with the
# committed package lock (checked against Packages/Design's lock); a build for the iOS simulator
# that fails on any compiler warning in the catalog's sources; the unit tests of the prototype's
# save ordering (DesignCatalogTests: "Saved" only after the durable write, failures keep the text,
# an interrupted answer is never complete) on Sylvia-M0-g06-design; then the XCUITest smoke tests:
#   - on Sylvia-M0-g06-design (iPhone 17, iOS 26.5): every interaction-prototype screen in light,
#     dark and at the largest accessibility size (labels, layout audit, reachability of the key
#     action, 1x screenshots), the flow tests (Inbox attention dot, "Saved" only after the write,
#     failed save keeps the text), the component gallery tests, Command-1/2/3 from a simulated
#     hardware keyboard, and the large content viewer at AX5: shown on a tab bar item (screenshots
#     taken from the host by lcv_helper while the test holds the press), opening the item under
#     the finger on lift (also after sliding to another item), and activating a control exactly
#     once;
#   - on Sylvia-M0-g06-design-SE (iPhone SE (3rd generation), 375 x 667 pt, iOS 26.5), the
#     narrowest and shortest iPhone screen iOS 26 supports: every prototype screen in light and at
#     the largest accessibility size, and the all-components page;
#   - on Sylvia-M0-g06-design-iPad (iPad (A16), iOS 26.5): the regular-width layout with the
#     sidebar and the reader's Thoughts pane, and Command-1/2/3 in the sidebar.
# Simulator names: SYLVIA_G06_SIM (default Sylvia-M0-g06-design), SYLVIA_G06_SE_SIM and
# SYLVIA_G06_PAD_SIM (default: the iPhone name with -SE and -iPad), so parallel jobs use their own.
# Exits non-zero on any failure, any skipped test, a run with a different number of tests than
# expected, a missing report or screenshot, a report listing a truncated or off-screen text, a
# screenshot over 2 MB, or a warning in Apps/DesignCatalog.
#
# Outputs go to $SYLVIA_G06_EVIDENCE_DIR (default .build/ci-logs/g06-design); set it to
# Docs/Stage0/evidence/G06-Design to refresh the committed evidence.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

EVIDENCE="${SYLVIA_G06_EVIDENCE_DIR:-$SYLVIA_ROOT/.build/ci-logs/g06-design}"
mkdir -p "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd)"
APP_DIR="$SYLVIA_ROOT/Apps/DesignCatalog"
DERIVED="$APP_DIR/.build/DerivedData"
# Each job uses its own simulators (ADR-0002): SYLVIA_G06_SIM, SYLVIA_G06_SE_SIM and SYLVIA_G06_PAD_SIM
# override the names (the device types and runtime stay fixed).
PHONE_SIM="${SYLVIA_G06_SIM:-Sylvia-M0-g06-design}"
SE_SIM="${SYLVIA_G06_SE_SIM:-${PHONE_SIM}-SE}"
SE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
PAD_SIM="${SYLVIA_G06_PAD_SIM:-${PHONE_SIM}-iPad}"
PAD_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-A16"
PHONE_VISITS=28   # PhonePrototypeTests.visits
PAD_VISITS=4      # PadLayoutTests.visits

step() { echo; echo "--- $* ($(date -u +%Y-%m-%dT%H:%M:%SZ))"; }

step "toolchain"
sylvia_check_xcode || true
xcodebuild -version

step "design lint over the catalog, no exemptions (Scripts/lint-design.py lint Apps/DesignCatalog)"
sylvia_python "$SYLVIA_ROOT/Scripts/lint-design.py" lint "$APP_DIR" | tee "$EVIDENCE/lint-catalog.log"

step "project generation and package lock"
sylvia_generate "$APP_DIR"
# The catalog's only package is the local Packages/Design; its lock must pin exactly what the
# package itself pins (swift-snapshot-testing 1.19.6 and its test-only dependencies).
if ! diff <(grep -E '"(identity|version)"' "$SYLVIA_ROOT/Packages/Design/Package.resolved") \
          <(grep -E '"(identity|version)"' "$APP_DIR/Package.resolved"); then
  echo "FAIL: Apps/DesignCatalog/Package.resolved differs from Packages/Design/Package.resolved"; exit 1
fi
echo "lock matches Packages/Design/Package.resolved"

PHONE_UDID="$(sylvia_sim_udid "$PHONE_SIM")"
SE_UDID="$(sylvia_sim_udid "$SE_SIM" "$SE_TYPE")"
PAD_UDID="$(sylvia_sim_udid "$PAD_SIM" "$PAD_TYPE")"
echo "iPhone simulator $PHONE_SIM: $PHONE_UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)"
echo "iPhone SE simulator $SE_SIM: $SE_UDID ($SE_TYPE, $SYLVIA_SIM_RUNTIME)"
echo "iPad simulator $PAD_SIM: $PAD_UDID ($PAD_TYPE, $SYLVIA_SIM_RUNTIME)"

step "build for testing (iOS simulator)"
build_log="$EVIDENCE/catalog-build-simulator.log"
status=0
(cd "$APP_DIR" && xcodebuild build-for-testing -project DesignCatalog.xcodeproj -scheme DesignCatalog \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$DERIVED" \
    -disableAutomaticPackageResolution) >"$build_log" 2>&1 || status=$?
grep -E "TEST BUILD (SUCCEEDED|FAILED)" "$build_log" || true
if (( status != 0 )); then
  echo "FAIL: build exited $status; see $build_log"; grep -E "error:" "$build_log" | head -40 || true; exit 1
fi
if grep -qE "Apps/DesignCatalog/.*: warning:" "$build_log"; then
  echo "FAIL: compiler warnings in Apps/DesignCatalog"; grep -E "Apps/DesignCatalog/.*: warning:" "$build_log" | sort -u; exit 1
fi
echo "no warnings in Apps/DesignCatalog"

# Runs tests on a simulator; fails on failure, skip or an unexpected test count.
# Args: label udid device-folder device-label expected-count target[/class[/test]]...
run_ui_tests() {
  local label="$1" udid="$2" folder="$3" device="$4" expected="$5"
  shift 5
  local log="$EVIDENCE/tests-$label.log" only=() t status=0
  for t in "$@"; do only+=("-only-testing:$t"); done
  step "tests on $label ($udid): $*"
  sylvia_sim_boot "$udid"
  local attempt
  for attempt in 1 2; do
    status=0
    (cd "$APP_DIR" && TEST_RUNNER_SYLVIA_EVIDENCE_DIR="$EVIDENCE" TEST_RUNNER_SYLVIA_DEVICE_FOLDER="$folder" \
        TEST_RUNNER_SYLVIA_DEVICE_LABEL="$device" xcodebuild test-without-building \
        -project DesignCatalog.xcodeproj -scheme DesignCatalog -destination "id=$udid" \
        -derivedDataPath "$DERIVED" -disableAutomaticPackageResolution "${only[@]}") >"$log" 2>&1 || status=$?
    # The simulator sometimes refuses to launch the test runner ("Application failed preflight
    # checks", reason Busy) before any test starts. Only that launch failure is retried, once; a
    # test that ran and failed is never retried.
    if (( status != 0 )) && (( attempt == 1 )) && grep -q "Application failed preflight checks" "$log" \
        && ! grep -qE "^Test Case " "$log"; then
      echo "the simulator refused to launch the test runner (Busy) before any test ran; retrying once"
      sleep 10
      continue
    fi
    break
  done
  grep -E "^Test Case .*(passed|failed)|Executed [0-9]+ tests?" "$log" | tail -40 || true
  if (( status != 0 )); then
    echo "FAIL: tests on $label exited $status; see $log"
    grep -E ": error:" "$log" | head -40 || true
    return 1
  fi
  local passed
  passed="$(grep -cE "^Test Case .* passed" "$log" || true)"
  if (( passed != expected )); then
    echo "FAIL: expected $expected passing tests on $label, found $passed"; return 1
  fi
  if grep -qE "^Test Case .* (skipped|failed)" "$log"; then
    echo "FAIL: a test was skipped or failed on $label"; return 1
  fi
}

rm -rf "$EVIDENCE/screens" "$EVIDENCE/.lcv"
rm -f "$EVIDENCE"/ui-prototype-*-simulator.md "$EVIDENCE"/keyboard-shortcuts-*-simulator.md \
  "$EVIDENCE/large-content-viewer-simulator.md" "$EVIDENCE/large-content-viewer-activation-simulator.md"

# Host screenshots for AreaNavigationTests.testLargeContentViewerOnTabBarItem: a UI test cannot
# take a screenshot while it holds a long press, so it writes "<name>.request" (the delay in
# seconds) into $EVIDENCE/.lcv and this helper takes the screenshot with simctl, scales it to 1x
# (402 pt wide on the iPhone 17) and answers with "<name>.done".
lcv_helper() {
  local udid="$1" requests="$EVIDENCE/.lcv" out="$EVIDENCE/screens/iphone/lcv" request name delay
  mkdir -p "$requests" "$out"
  while true; do
    for request in "$requests"/*.request; do
      [[ -e "$request" ]] || continue
      name="$(basename "$request" .request)"
      delay="$(cat "$request")"
      rm -f "$request"
      sleep "${delay:-0}"
      xcrun simctl io "$udid" screenshot --type=png "$out/$name.png" >/dev/null 2>&1 \
        && sips --resampleWidth 402 "$out/$name.png" >/dev/null 2>&1
      touch "$requests/$name.done"
    done
    sleep 0.2
  done
}

UI=DesignCatalogUITests
run_ui_tests unit-iphone-simulator "$PHONE_UDID" iphone "iPhone 17" 11 DesignCatalogTests
lcv_helper "$PHONE_UDID" &
LCV_PID=$!
trap 'kill "$LCV_PID" 2>/dev/null || true' EXIT
ui_status=0
run_ui_tests ui-iphone-simulator "$PHONE_UDID" iphone "iPhone 17" 14 $UI/PhonePrototypeTests $UI/CatalogGalleryTests \
  $UI/AreaNavigationTests || ui_status=$?
kill "$LCV_PID" 2>/dev/null || true
wait "$LCV_PID" 2>/dev/null || true
trap - EXIT
rm -rf "$EVIDENCE/.lcv"
(( ui_status == 0 )) || exit "$ui_status"
run_ui_tests ui-iphone-se-simulator "$SE_UDID" iphone-se "iPhone SE (3rd generation)" 3 \
  $UI/PhonePrototypeTests/testEveryScreenInLight $UI/PhonePrototypeTests/testEveryScreenAtAX5 \
  $UI/CatalogGalleryTests/testEverySamplePage
run_ui_tests ui-ipad-simulator "$PAD_UDID" ipad "iPad (A16)" 2 $UI/PadLayoutTests \
  $UI/AreaNavigationTests/testHardwareKeyboardSwitchesAreas

step "evidence written by the UI tests"
for report in ui-prototype-iphone-light-simulator.md ui-prototype-iphone-dark-simulator.md \
              ui-prototype-iphone-ax5-simulator.md ui-prototype-iphone-se-light-simulator.md \
              ui-prototype-iphone-se-ax5-simulator.md ui-prototype-ipad-simulator.md \
              keyboard-shortcuts-iphone-simulator.md keyboard-shortcuts-ipad-simulator.md \
              large-content-viewer-simulator.md large-content-viewer-activation-simulator.md; do
  [[ -s "$EVIDENCE/$report" ]] || { echo "FAIL: $report was not written"; exit 1; }
done
# One screenshot per visit (named for the screen), plus "<screen>.reached.png" where the key
# action had to be scrolled to.
count_visits() { find "$1" -name '*.png' ! -name '*.reached.png' | wc -l | tr -d ' '; }
for variant in light dark ax5; do
  n="$(count_visits "$EVIDENCE/screens/iphone/$variant")"
  (( n == PHONE_VISITS )) || { echo "FAIL: $n iPhone $variant screenshots, expected $PHONE_VISITS"; exit 1; }
  n="$(count_visits "$EVIDENCE/screens/ipad/$variant")"
  (( n == PAD_VISITS )) || { echo "FAIL: $n iPad $variant screenshots, expected $PAD_VISITS"; exit 1; }
done
for variant in light ax5; do
  n="$(count_visits "$EVIDENCE/screens/iphone-se/$variant")"
  (( n == PHONE_VISITS )) || { echo "FAIL: $n iPhone SE $variant screenshots, expected $PHONE_VISITS"; exit 1; }
done
large="$(find "$EVIDENCE/screens" -name '*.png' -size +2048k)"
[[ -z "$large" ]] || { echo "FAIL: screenshots over 2 MB: $large"; exit 1; }
total="$(find "$EVIDENCE/screens" -name '*.png' | wc -l | tr -d ' ')"
size="$(du -sk "$EVIDENCE/screens" | cut -f1)"
echo "$total screenshots, ${size} KiB"
# Every visit reported zero truncated and zero off-screen texts out of at least one (the tests
# assert it; the reports must agree).
if grep -hE "^\| " "$EVIDENCE"/ui-prototype-*-simulator.md | grep -vE "^\| (Screen|---)" | awk -F'|' '{print $5}' \
    | grep -vqE "^ 0 / 0 / [1-9][0-9]* $"; then
  echo "FAIL: a report lists truncated or off-screen text"; exit 1
fi
echo "every report row: 0 truncated, 0 outside"

echo
echo "21-design-catalog: all checks passed; outputs in $EVIDENCE"
