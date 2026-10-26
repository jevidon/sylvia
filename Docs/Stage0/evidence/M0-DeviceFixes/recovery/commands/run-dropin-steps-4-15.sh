#!/bin/bash
# Steps 4-15 of G0.5 recovery's drop-in (Scripts/ci.d/71-g05-recovery.sh), each with the drop-in's own command and
# arguments, run by hand after a run of the drop-in that stopped at its row-10 guard because the screen was locked
# (the guard follows step 3; nothing here touches it, and G05_ALLOW_MISSING_CLASS_B is not set). This is not a run of
# the drop-in and not evidence for report row 10: it shows that the steps after the guard pass on this code, the crash
# drills' template copy (FileProtector.copyTree) at the drop-in's full iteration counts above all. It uses the build
# and the tool of the drop-in run that preceded it (steps 1-3), and the drop-in's work folder (.build/g05-recovery).
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-dropin-steps-4-15.sh <name>
# Logs: Docs/Stage0/evidence/M0-DeviceFixes/recovery/<name>/console.log and the step logs in <name>/logs/.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
out="$root/Docs/Stage0/evidence/M0-DeviceFixes/recovery/$name"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
SPIKE="$SYLVIA_ROOT/Spikes/G05-Recovery"
WORK="$SYLVIA_ROOT/.build/g05-recovery"
LOGS="$out/logs"
SIM_NAME=Sylvia-M0-devfix-recovery
rm -rf "$out"
mkdir -p "$LOGS"
console="$out/console.log"
exec > >(tee "$console") 2>&1
echo "command: Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-dropin-steps-4-15.sh $*"
echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "screen lock (ioreg) at the start: $(lock_state)"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
cd "$SPIKE" || exit 1
step() { echo; echo "=== $1"; }
plain() { perl -pe 's/\e\[[0-9;]*m//g' "$1"; }
own_warnings() { plain "$1" | grep -E "Spikes/G05-Recovery/(Sources|Tests)/[^:]+:[0-9]+:[0-9]+: warning:" || true; }
run_logged() { local n="$1"; shift; "$@" 2>&1 | tee "$LOGS/$n.log"; return "${PIPESTATUS[0]}"; }
failed=()
check() { local n="$1" s="$2"; if (( s == 0 )); then echo "step $n: exit 0"; else echo "step $n: FAILED (exit $s)"; failed+=("$n"); fi; }
TOOL="$(xcrun swift build --force-resolved-versions --show-bin-path)/g05-recovery-tool"
echo "tool: $TOOL (built by the preceding drop-in run's step 2)"

step "4. crash drill, chosen durability, 900 iterations"
run_logged crash-drill-full "$TOOL" crash-drill --root "$WORK/crash-full" --iterations 900 --sync full --fullfsync 1; check 4 $?
step "5. crash drill, synchronous=OFF (limit of a process-kill drill)"
run_logged crash-drill-sync-off "$TOOL" crash-drill --root "$WORK/crash-off" --iterations 150 --sync off --fullfsync 0; check 5 $?
step "6. capture save latency"
run_logged latency "$TOOL" latency --root "$WORK/latency" --iterations 2000; check 6 $?
step "7. restore drill"
run_logged restore-drill "$TOOL" restore-drill --root "$WORK/drill"; check 7 $?
step "8. restore crash drill, 300 iterations"
run_logged restore-crash-drill "$TOOL" restore-crash-drill --root "$WORK/restore-crash" --iterations 300; check 8 $?
step "9. migration put-back crash drill, 240 iterations"
run_logged migration-crash-drill "$TOOL" migration-crash-drill --root "$WORK/migration-crash" --iterations 240; check 9 $?
step "10. backup-manifest contract"
run_logged manifest-contract sylvia_python "$SPIKE/Scripts/check_manifest_contract.py" "$SYLVIA_ROOT" \
  "$WORK/drill/Exports/Sylvia-drill.sylviabackup/manifest.json"; check 10 $?

step "11. simulator tests ($SIM_NAME)"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
echo "simulator: $SIM_NAME $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)" | tee "$LOGS/simulator-tests.log"
xcodebuild test -scheme G05Recovery-Package -destination "id=$UDID" -derivedDataPath "$SPIKE/.build/DerivedData" \
  -disableAutomaticPackageResolution 2>&1 | tee -a "$LOGS/simulator-tests.log"
plain "$LOGS/simulator-tests.log" | grep -q "Test run with .* passed"; check 11 $?
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
echo "simulator $SIM_NAME shut down"

step "12. iOS device build (library, and the tests unsigned so the device checklist can run them)"
run_logged ios-device-build xcodebuild build-for-testing -scheme G05Recovery-Package -destination "generic/platform=iOS" \
  -derivedDataPath "$SPIKE/.build/DerivedData" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO; s=$?
if [[ -n "$(own_warnings "$LOGS/ios-device-build.log")" ]]; then own_warnings "$LOGS/ios-device-build.log"; s=1; fi
check 12 $s

step "13-15. the lock harness (harness-checks.sh, with this run's log folder and simulator)"
G05_LOG_DIR="$LOGS" G05_SIM_NAME="$SIM_NAME" "$SPIKE/LockHarness/Scripts/harness-checks.sh"; check 13-15 $?

echo
echo "screen lock (ioreg) at the end: $(lock_state)"
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
if (( ${#failed[@]} )); then echo "steps 4-15 by hand: FAILED steps: ${failed[*]}"; exit 1; fi
echo "steps 4-15 by hand: all passed (not a run of the drop-in; report row 10's class-B evidence not taken)"
