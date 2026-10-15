#!/usr/bin/env bash
# G0.5 recovery spike (Spikes/G05-Recovery): persistence, durable saves, migrations, media removal,
# backup and restore. Runs, in order, and fails on the first failure:
#   1. toolchain and SQLite report
#   2. host build; fails on any compiler warning in the spike's own sources
#   3. host tests (swift test; includes short SIGKILL drills). Also fails when the host log lacks the
#      class-B data-protection evidence (report row 10): that test is skipped while the Mac's screen
#      is locked, so an unattended run on a locked Mac would otherwise pass without the evidence.
#      G05_ALLOW_MISSING_CLASS_B=1 turns the failure into a printed "row 10 evidence missing" warning.
#   4. full SIGKILL crash drill with the chosen durability (G05_CRASH_ITERATIONS, default 900)
#   5. the same drill with synchronous=OFF, to show what a process-kill drill cannot distinguish
#   6. capture-save latency against the 200 ms p95 budget (host, indicative)
#   7. restore drill after source deletion (J-06, T35)
#   8. SIGKILL restore crash drill during prepare and the swap (T47; G05_RESTORE_CRASH_ITERATIONS, default 300)
#   9. SIGKILL drill over a failed migration's snapshot put-back (T45; G05_MIGRATION_CRASH_ITERATIONS,
#      default 240)
#  10. backup-manifest contract: exporter output validates; invalid fixtures fail for one reason
#  11. tests on the workstream simulator (G05_SIM_NAME, default Sylvia-M0-g05-recovery; iPhone 17,
#      iOS 26.5), created if missing and shut down when the step ends. Another checkout or agent must
#      pass its own G05_SIM_NAME: never boot a simulator you did not create.
#  12. library and test build for iOS devices (generic/platform=iOS, unsigned)
# Logs of each step go to $G05_LOG_DIR (default .build/g05-recovery/logs under the repository).
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"

SPIKE="$SYLVIA_ROOT/Spikes/G05-Recovery"
WORK="$SYLVIA_ROOT/.build/g05-recovery"
LOGS="${G05_LOG_DIR:-$WORK/logs}"
ITERATIONS="${G05_CRASH_ITERATIONS:-900}"
RESTORE_CRASH_ITERATIONS="${G05_RESTORE_CRASH_ITERATIONS:-300}"
MIGRATION_CRASH_ITERATIONS="${G05_MIGRATION_CRASH_ITERATIONS:-240}"
SIM_NAME="${G05_SIM_NAME:-Sylvia-M0-g05-recovery}"
mkdir -p "$WORK" "$LOGS"
LOGS="$(cd "$LOGS" && pwd)"   # a relative G05_LOG_DIR is relative to the caller's directory
cd "$SPIKE"

step() { echo; echo "=== $1"; }
plain() { perl -pe 's/\e\[[0-9;]*m//g' "$1"; }   # log text without ANSI colour codes
own_warnings() { plain "$1" | grep -E "Spikes/G05-Recovery/(Sources|Tests)/[^:]+:[0-9]+:[0-9]+: warning:" || true; }
run_logged() { # name, command...
  local name="$1"; shift
  "$@" 2>&1 | tee "$LOGS/$name.log"
}

step "1. toolchain"
{
  xcodebuild -version
  xcrun swift --version 2>&1
  python3 -c 'import json
for pin in json.load(open("Package.resolved"))["pins"]:
    print("pinned package:", pin["identity"], pin["state"]["version"], pin["state"]["revision"])'
} 2>&1 | tee "$LOGS/toolchain.log"

step "2. host build"
xcrun swift build --force-resolved-versions --build-tests 2>&1 | tee "$LOGS/host-build.log"
if [[ -n "$(own_warnings "$LOGS/host-build.log")" ]]; then
  own_warnings "$LOGS/host-build.log"
  echo "FAIL: compiler warnings in Spikes/G05-Recovery sources"; exit 1
fi
TOOL="$(xcrun swift build --force-resolved-versions --show-bin-path)/g05-recovery-tool"
run_logged env-report "$TOOL" env-report

step "3. host tests"
run_logged host-tests xcrun swift test --force-resolved-versions
plain "$LOGS/host-tests.log" | grep -q "Test run with .* passed"
# Report row 10 rests on the class-B run and the inheritance probe, which skip (and still "pass")
# while the host screen is locked. A green run must carry their evidence lines.
missing_class_b=""
plain "$LOGS/host-tests.log" > "$WORK/host-tests.plain.log"   # a file, not a pipe: grep -q under pipefail
for line in "class B (non-default) requested: read back on" "files SQLite created in a class-B directory:"; do
  grep -qF "$line" "$WORK/host-tests.plain.log" || missing_class_b="$missing_class_b [$line]"
done
if [[ -n "$missing_class_b" ]]; then
  if [[ "${G05_ALLOW_MISSING_CLASS_B:-0}" == 1 ]]; then
    echo "WARNING: row 10 evidence missing from host-tests.log:$missing_class_b (host screen locked?); this run is not evidence for row 10"
  else
    echo "FAIL: row 10 evidence missing from host-tests.log:$missing_class_b. The class-B protection tests skip while the host screen is locked; unlock it and rerun (or set G05_ALLOW_MISSING_CLASS_B=1 to accept a run without that evidence)"
    exit 1
  fi
else
  echo "row 10 evidence present: class-B readback and inheritance lines found in host-tests.log"
fi

step "4. crash drill, chosen durability, $ITERATIONS iterations"
run_logged crash-drill-full "$TOOL" crash-drill --root "$WORK/crash-full" --iterations "$ITERATIONS" --sync full --fullfsync 1

step "5. crash drill, synchronous=OFF (limit of a process-kill drill)"
run_logged crash-drill-sync-off "$TOOL" crash-drill --root "$WORK/crash-off" --iterations 150 --sync off --fullfsync 0

step "6. capture save latency"
run_logged latency "$TOOL" latency --root "$WORK/latency" --iterations 2000

step "7. restore drill"
run_logged restore-drill "$TOOL" restore-drill --root "$WORK/drill"

step "8. restore crash drill, $RESTORE_CRASH_ITERATIONS iterations"
run_logged restore-crash-drill "$TOOL" restore-crash-drill --root "$WORK/restore-crash" --iterations "$RESTORE_CRASH_ITERATIONS"

step "9. migration put-back crash drill, $MIGRATION_CRASH_ITERATIONS iterations"
run_logged migration-crash-drill "$TOOL" migration-crash-drill --root "$WORK/migration-crash" --iterations "$MIGRATION_CRASH_ITERATIONS"

step "10. backup-manifest contract"
run_logged manifest-contract sylvia_python "$SPIKE/Scripts/check_manifest_contract.py" "$SYLVIA_ROOT" \
  "$WORK/drill/Exports/Sylvia-drill.sylviabackup/manifest.json"

step "11. simulator tests ($SIM_NAME)"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
# Shut the simulator down when this script ends, whether the tests pass or not.
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true' EXIT
echo "simulator: $SIM_NAME $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)" | tee "$LOGS/simulator-tests.log"
xcodebuild test -scheme G05Recovery-Package -destination "id=$UDID" -derivedDataPath "$SPIKE/.build/DerivedData" \
  -disableAutomaticPackageResolution 2>&1 | tee -a "$LOGS/simulator-tests.log"
plain "$LOGS/simulator-tests.log" | grep -q "Test run with .* passed"
xcrun simctl shutdown "$UDID"
trap - EXIT
echo "simulator $SIM_NAME shut down"

step "12. iOS device build (library, and the tests unsigned so the device checklist can run them)"
run_logged ios-device-build xcodebuild build-for-testing -scheme G05Recovery-Package -destination "generic/platform=iOS" \
  -derivedDataPath "$SPIKE/.build/DerivedData" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
if [[ -n "$(own_warnings "$LOGS/ios-device-build.log")" ]]; then
  own_warnings "$LOGS/ios-device-build.log"
  echo "FAIL: compiler warnings in Spikes/G05-Recovery sources (iOS)"; exit 1
fi

echo
echo "G0.5 recovery: all steps passed (logs in $LOGS)"
