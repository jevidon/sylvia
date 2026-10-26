#!/bin/bash
# M0 device fixes, assembly: the checks of the merged tree (branch m0-device-fixes: m0-device-fixes-recovery and
# m0-device-fixes-ats merged into c72247a6) on the build Mac. Build Mac and simulator only: no physical device is used
# or contacted, nothing is installed on a device, nothing is pushed. Audio plays only in the lock harness's tone test
# (step 3's step 14), at the test volume 0.01 that the harness sets; nothing changes the Mac's audio.
#   Docs/Stage0/evidence/M0-DeviceFixes/assembly/commands/run-checks.sh
# Steps, each with its log under Docs/Stage0/evidence/M0-DeviceFixes/assembly/ and its expectation written into the
# log before it runs:
#  1. host-tests.log: G0.5 recovery's host suite, `xcrun swift test --force-resolved-versions` in Spikes/G05-Recovery,
#     after deleting the spike's build products.
#  2. dropin/: G0.5 recovery's drop-in (Scripts/ci.d/71-g05-recovery.sh) from clean, through `Scripts/ci.sh
#     g05-recovery`, after deleting Spikes/G05-Recovery/.build, Spikes/G05-Recovery/LockHarness/.build and
#     .build/g05-recovery. G05_ALLOW_MISSING_CLASS_B is never set: with the screen locked the drop-in stops at its
#     row-10 guard after its step 3, and this record says so.
#  3. dropin-steps-4-15/: only when step 2 stopped at that guard, the drop-in's steps 4-15 by hand, each with the
#     drop-in's own command and arguments, on step 2's build. Not a run of the drop-in and no evidence for report row 10.
#  4. devicetests-ios-build.log: the recovery suite's app host (Spikes/G05-Recovery/DeviceTests, Codex's project,
#     unchanged) generated with sylvia_generate and built for a generic iOS device: build-for-testing, unsigned.
#  5. atsprobe-ios-build.log: the ATS probe (Spikes/G05-AI/ATSProbe) generated and built for a generic iOS device:
#     build-for-testing, unsigned.
#  6. atsprobe-simulator-tests.log: the probe's tests in each variant on this job's simulator, the device checklist's
#     step 1 command with the simulator as destination and no signing flags (as Scripts/ci.d/70-g05-ai.sh runs it);
#     private IPv4 addresses masked beyond their first two octets, as the G0.5 AI device checklist keeps them.
# The screen lock state (ioreg, read only) and the load are recorded at the start and end of each step. Simulator:
# Sylvia-M0-devfix-assembly (iPhone 17, iOS 26.5), this job's own, created if missing and shut down after each step
# that boots it; the job deletes it at its end. Exit 0 only if every step showed what its log states before it ran.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh

OUT="$root/Docs/Stage0/evidence/M0-DeviceFixes/assembly"
FULL="$root/.build/scratch/m0-devfix-assembly"
SPIKE="$root/Spikes/G05-Recovery"
PROBE="$root/Spikes/G05-AI/ATSProbe"
WORK="$root/.build/g05-recovery"
SIM_NAME=Sylvia-M0-devfix-assembly
mkdir -p "$OUT" "$FULL"
# Counted before this run deletes or writes anything.
uncommitted="$(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
commit="$(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
failures=()

plain() { perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' "$@"; }
mask() {  # private IPv4 (10/8, 172.16/12, 192.168/16) and shared (100.64/10) addresses beyond their first two octets
  perl -pe 's/\e\[[0-9;]*[A-Za-z]//g; s/\b(10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])|192\.168|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b/$1.x.x/g'
}
header() {  # header <title> <expected>
  echo "# $1"
  echo "# expected (stated before the run): $2"
  echo "# commit: $commit; uncommitted files before this run: $uncommitted"
  echo "# host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "# screen lock (ioreg) at the start: $(lock_state)"
  echo "# started: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //') (other jobs may share this Mac: timings are indicative only)"
}
footer() {  # footer <exit status>
  echo "# screen lock (ioreg) at the end: $(lock_state)"
  echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ); exit status $1; load: $(uptime | sed 's/.*load averages*: //')"
}
verdict() {  # verdict <log> <ok 0|1> <step> <what>
  if [[ "$2" == 0 ]]; then
    echo "# result: as expected ($4)" >> "$1"; echo "step $3: as expected ($4)"
  else
    echo "# result: NOT as expected ($4)" >> "$1"; echo "step $3: NOT as expected ($4)"; failures+=("$3")
  fi
}
own_warnings() { plain "$1" | grep -cE "Spikes/G05-Recovery/(Sources|Tests)/[^:]+:[0-9]+:[0-9]+: warning:"; }

echo "run-checks.sh: commit $commit; uncommitted files: $uncommitted; logs in ${OUT#"$root/"}"

# 1. Host suite.
log="$OUT/host-tests.log"
rm -rf "$SPIKE/.build"
{
  header "G0.5 recovery's host suite: xcrun swift test --force-resolved-versions (in Spikes/G05-Recovery, its .build deleted first)" \
    "exit 0 and 'Test run with 79 tests in 13 suites passed'; skipped: the 2 device probes, and with the screen locked the 4 class-B tests (with it unlocked, the locked-host observation instead); the copy guard reports 0 calls that keep the source's class; the /private test rejects the missing file as 'missing file'"
  echo "---- xcrun swift test --force-resolved-versions"
} > "$log"
(cd "$SPIKE" && xcrun swift test --force-resolved-versions) > "$FULL/host-tests.out" 2>&1
status=$?
plain "$FULL/host-tests.out" >> "$log"
{
  echo "---- summary"
  echo "skipped tests:"; plain "$FULL/host-tests.out" | grep -E 'Test ".*" skipped' | sed 's/^/  /'
  echo "evidence lines of the two new suites:"; plain "$FULL/host-tests.out" | grep -E '\] (copy guard|missing listed file|containment check|v1 library installed|class-B tree)' | sed 's/^/  /'
  footer "$status"
} >> "$log"
ok=1
[[ "$status" == 0 ]] && grep -q 'Test run with 79 tests in 13 suites passed' "$log" \
  && grep -q 'calls that keep the source.s class: 0' "$log" && grep -q 'missing listed file, bundle .*through /private, as an iPhone.s folders are named: missing file:' "$log" && ok=0
verdict "$log" "$ok" 1 "swift test exit $status; $(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites (passed|failed)[^.]*' "$log" | tail -1)"

# 2. The drop-in from clean.
dir="$OUT/dropin"
rm -rf "$dir" "$SPIKE/.build" "$SPIKE/LockHarness/.build" "$WORK"
mkdir -p "$dir/logs"
log="$dir/console.log"
{
  header "G0.5 recovery's drop-in from clean: G02_LOOPBACK_ONLY=1 G05_LOG_DIR=<this folder>/logs G05_SIM_NAME=$SIM_NAME Scripts/ci.sh g05-recovery (deleted first: Spikes/G05-Recovery/.build Spikes/G05-Recovery/LockHarness/.build .build/g05-recovery); G05_ALLOW_MISSING_CLASS_B not set" \
    "with the screen unlocked: 'all 2 steps passed' (00-git-lfs and 71-g05-recovery, its steps 1-15) with 'row 10 evidence present'; with it locked: steps 1-3 pass (79 host tests in 13 suites) and the drop-in stops at its row-10 guard with 'FAIL: row 10 evidence missing', so ci.sh exits 1, and steps 4-15 run by hand (step 3 of this script)"
  echo "---- Scripts/ci.sh console"
} > "$log"
G02_LOOPBACK_ONLY=1 G05_LOG_DIR="$dir/logs" G05_SIM_NAME="$SIM_NAME" Scripts/ci.sh g05-recovery >> "$log" 2>&1
status=$?
plain .build/ci-logs/71-g05-recovery.log > "$dir/71-g05-recovery.log"
for f in "$dir/logs"/*.log; do [[ -f "$f" ]] && perl -pi -e 's/\e\[[0-9;]*[A-Za-z]//g' "$f"; done
{
  echo "---- 71-g05-recovery.log: step headers, warnings and verdict lines (the whole output is 71-g05-recovery.log, the step logs are in logs/)"
  grep -E '^(=== |WARNING|FAIL|row 10|G0\.5 recovery|simulator |ok: |originHash|== G05LockHarness)|Test run with|\*\* (TEST|BUILD)' "$dir/71-g05-recovery.log" || true
  footer "$status"
} >> "$log"
guard_stop=0
grep -q '^FAIL: row 10 evidence missing' "$dir/71-g05-recovery.log" && guard_stop=1
host_ok=0
grep -q 'Test run with 79 tests in 13 suites passed' "$dir/71-g05-recovery.log" && host_ok=1
if [[ "$status" == 0 ]]; then
  ok=1; grep -q '^row 10 evidence present' "$dir/71-g05-recovery.log" && grep -q '^G0.5 recovery: all steps passed' "$dir/71-g05-recovery.log" && ok=0
  verdict "$log" "$ok" 2 "ci.sh exit 0: the whole drop-in passed with the row-10 evidence (screen unlocked)"
elif (( guard_stop && host_ok )); then
  verdict "$log" 0 2 "ci.sh exit $status: steps 1-3 passed (79 host tests in 13 suites), then the drop-in stopped at its row-10 guard (screen locked; G05_ALLOW_MISSING_CLASS_B not set): not a passing run, and no class-B evidence for report row 10"
else
  verdict "$log" 1 2 "ci.sh exit $status, and not at the row-10 guard after passing host tests"
fi

# 3. Steps 4-15 by hand, only after a stop at the guard.
if (( guard_stop && host_ok )); then
  dir="$OUT/dropin-steps-4-15"
  rm -rf "$dir"; mkdir -p "$dir/logs"
  log="$dir/console.log"
  LOGS="$dir/logs"
  header "G0.5 recovery's drop-in steps 4-15 by hand, each with the drop-in's own command and arguments, on step 2's build, after step 2 stopped at the row-10 guard; not a run of the drop-in and no evidence for report row 10" \
    "steps 4-13 exit 0 (crash drills with 0 failures, the simulator suite 'Test run with 73 tests in 13 suites passed', the iOS build with no warning in the spike); steps 14-15 (the lock harness) pass, though its quiet-tone test failed on this Mac in every run of 26 October 2026 07:38-07:58 UTC, on the unchanged code too (recovery/README.md section 4)" > "$log"
  failed=()
  check() { if (( $2 == 0 )); then echo "step $1: exit 0"; else echo "step $1: FAILED (exit $2)"; failed+=("$1"); fi; }
  run_logged() { local n="$1"; shift; "$@" 2>&1 | tee "$LOGS/$n.log"; return "${PIPESTATUS[0]}"; }
  (
    cd "$SPIKE" || exit 1
    TOOL="$(xcrun swift build --force-resolved-versions --show-bin-path)/g05-recovery-tool"
    echo "tool: ${TOOL#"$root/"} (built by step 2's drop-in run)"
    echo; echo "=== 4. crash drill, chosen durability, 900 iterations"
    run_logged crash-drill-full "$TOOL" crash-drill --root "$WORK/crash-full" --iterations 900 --sync full --fullfsync 1; check 4 $?
    echo; echo "=== 5. crash drill, synchronous=OFF (limit of a process-kill drill)"
    run_logged crash-drill-sync-off "$TOOL" crash-drill --root "$WORK/crash-off" --iterations 150 --sync off --fullfsync 0; check 5 $?
    echo; echo "=== 6. capture save latency"
    run_logged latency "$TOOL" latency --root "$WORK/latency" --iterations 2000; check 6 $?
    echo; echo "=== 7. restore drill"
    run_logged restore-drill "$TOOL" restore-drill --root "$WORK/drill"; check 7 $?
    echo; echo "=== 8. restore crash drill, 300 iterations"
    run_logged restore-crash-drill "$TOOL" restore-crash-drill --root "$WORK/restore-crash" --iterations 300; check 8 $?
    echo; echo "=== 9. migration put-back crash drill, 240 iterations"
    run_logged migration-crash-drill "$TOOL" migration-crash-drill --root "$WORK/migration-crash" --iterations 240; check 9 $?
    echo; echo "=== 10. backup-manifest contract"
    run_logged manifest-contract sylvia_python "$SPIKE/Scripts/check_manifest_contract.py" "$root" \
      "$WORK/drill/Exports/Sylvia-drill.sylviabackup/manifest.json"; check 10 $?
    echo; echo "=== 11. simulator tests ($SIM_NAME)"
    UDID="$(sylvia_sim_udid "$SIM_NAME")"
    sylvia_sim_boot "$UDID"
    echo "simulator: $SIM_NAME $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)" | tee "$LOGS/simulator-tests.log"
    xcodebuild test -scheme G05Recovery-Package -destination "id=$UDID" -derivedDataPath "$SPIKE/.build/DerivedData" \
      -disableAutomaticPackageResolution 2>&1 | tee -a "$LOGS/simulator-tests.log"
    plain "$LOGS/simulator-tests.log" | grep -q "Test run with .* passed"; check 11 $?
    sylvia_sim_shutdown "$UDID"
    echo "simulator $SIM_NAME shut down"
    echo; echo "=== 12. iOS device build (library, and the tests unsigned so the device checklist can run them)"
    run_logged ios-device-build xcodebuild build-for-testing -scheme G05Recovery-Package -destination "generic/platform=iOS" \
      -derivedDataPath "$SPIKE/.build/DerivedData" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO; s=$?
    w="$(own_warnings "$LOGS/ios-device-build.log")"
    echo "warnings in Spikes/G05-Recovery sources and tests (iOS): $w"
    (( w == 0 )) || s=1
    check 12 $s
    echo; echo "=== 13-15. the lock harness (harness-checks.sh, with this run's log folder and simulator)"
    G05_LOG_DIR="$LOGS" G05_SIM_NAME="$SIM_NAME" "$SPIKE/LockHarness/Scripts/harness-checks.sh"; check 13-15 $?
    sylvia_sim_shutdown "$(sylvia_sim_find "$SIM_NAME")"
    echo
    if (( ${#failed[@]} )); then echo "steps 4-15 by hand: FAILED steps: ${failed[*]}"; exit 1; fi
    echo "steps 4-15 by hand: all passed (not a run of the drop-in; report row 10's class-B evidence not taken)"
  ) > "$FULL/dropin-steps-4-15.out" 2>&1
  status=$?
  plain "$FULL/dropin-steps-4-15.out" >> "$log"
  for f in "$LOGS"/*.log; do perl -pi -e 's/\e\[[0-9;]*[A-Za-z]//g' "$f"; done
  footer "$status" >> "$log"
  if [[ "$status" == 0 ]]; then
    verdict "$log" 0 3 "steps 4-15 by hand all passed"
  else
    verdict "$log" 1 3 "steps 4-15 by hand: $(grep -E '^steps 4-15 by hand:' "$log" | tail -1)"
  fi
fi

# 4. The recovery suite's app host for a generic iOS device.
log="$OUT/devicetests-ios-build.log"
rm -rf "$SPIKE/DeviceTests/.build" "$SPIKE/DeviceTests/G05RecoveryDeviceTests.xcodeproj"
cmd=(xcodebuild build-for-testing -project DeviceTests/G05RecoveryDeviceTests.xcodeproj -scheme G05RecoveryDeviceTests
  -destination generic/platform=iOS -derivedDataPath DeviceTests/.build/DerivedData -disableAutomaticPackageResolution
  CODE_SIGNING_ALLOWED=NO)
{
  header "the recovery suite's app host (Spikes/G05-Recovery/DeviceTests) for a generic iOS device: sylvia_generate, then xcodebuild build-for-testing, unsigned (build only; no device)" \
    "exit 0, TEST BUILD SUCCEEDED; PrivatePathTests.swift and ProtectedCopyTests.swift compiled for arm64 in SylviaRecoveryTests; no warning in Spikes/G05-Recovery sources and tests"
  echo "# command (in Spikes/G05-Recovery, after sylvia_generate Spikes/G05-Recovery/DeviceTests):"
  echo "#   ${cmd[*]}"
} > "$log"
sylvia_generate "$SPIKE/DeviceTests" > "$FULL/devicetests-generate.out" 2>&1 || { echo "sylvia_generate failed:"; cat "$FULL/devicetests-generate.out"; } >> "$log"
(cd "$SPIKE" && "${cmd[@]}") > "$FULL/devicetests-ios-build.out" 2>&1
status=$?
full="$FULL/devicetests-ios-build.out"
{
  echo "--- result lines"; grep -E '\*\* (BUILD|TEST BUILD) (SUCCEEDED|FAILED|INTERRUPTED) \*\*' "$full" | sort -u
  echo "--- error lines ($(grep -c 'error:' "$full") in all)"; grep -E 'error:' "$full" | sed "s#$root/##g" | sort -u | head -40
  echo "--- warning lines ($(grep -c 'warning:' "$full") in all; unique)"; grep -E 'warning:' "$full" | sed "s#$root/##g" | sort -u | head -20
  echo "--- warnings in Spikes/G05-Recovery sources and tests: $(own_warnings "$full")"
  echo "--- Swift sources compiled for arm64 in target SylviaRecoveryTests (SwiftCompile and SwiftDriverJobDiscovery lines)"
  grep -E '^(SwiftCompile|SwiftDriverJobDiscovery) normal arm64 .*Compiling' "$full" | grep "in target 'SylviaRecoveryTests'" \
    | grep -oE '[A-Za-z+]+\.swift' | sort -u | tr '\n' ' '; echo
  echo "--- products (Debug-iphoneos)"
  (cd "$SPIKE/DeviceTests/.build/DerivedData/Build/Products/Debug-iphoneos" 2>/dev/null && ls -d *.app *.app/PlugIns/*.xctest 2>/dev/null)
  echo "--- last 10 lines of the output"; tail -10 "$full" | sed "s#$root/##g"
  footer "$status"
} >> "$log"
compiled=0
for f in PrivatePathTests ProtectedCopyTests; do
  grep -E "^(SwiftCompile|SwiftDriverJobDiscovery) normal arm64 .*Compiling.*[^A-Za-z]$f\.swift" "$full" \
    | grep -q "in target 'SylviaRecoveryTests'" && compiled=$((compiled + 1))
done
ok=1
[[ "$status" == 0 ]] && grep -q '\*\* TEST BUILD SUCCEEDED \*\*' "$full" && [[ "$(own_warnings "$full")" == 0 ]] && (( compiled == 2 )) && ok=0
verdict "$log" "$ok" 4 "exit $status; of the two new test files, $compiled compiled for arm64 in SylviaRecoveryTests"

# 5. The ATS probe for a generic iOS device.
log="$OUT/atsprobe-ios-build.log"
rm -rf "$PROBE/.build" "$PROBE/G05ATSProbe.xcodeproj" "$root/Spikes/G05-AI/.build"
cmd=(xcodebuild build-for-testing -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination generic/platform=iOS
  -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO)
{
  header "the ATS probe (Spikes/G05-AI/ATSProbe) for a generic iOS device: sylvia_generate, then xcodebuild build-for-testing, unsigned (build only; no device)" \
    "exit 0, TEST BUILD SUCCEEDED; ATSProbeTests.swift compiled for arm64 in each of the three test targets; no warning in Spikes/G05-AI code"
  echo "# command (in Spikes/G05-AI/ATSProbe, after sylvia_generate Spikes/G05-AI/ATSProbe):"
  echo "#   ${cmd[*]}"
} > "$log"
sylvia_generate "$PROBE" > "$FULL/atsprobe-generate-1.out" 2>&1 || { echo "sylvia_generate failed:"; cat "$FULL/atsprobe-generate-1.out"; } >> "$log"
(cd "$PROBE" && "${cmd[@]}") > "$FULL/atsprobe-ios-build.out" 2>&1
status=$?
full="$FULL/atsprobe-ios-build.out"
{
  echo "--- result lines"; grep -E '\*\* (BUILD|TEST BUILD) (SUCCEEDED|FAILED|INTERRUPTED) \*\*' "$full" | sort -u
  echo "--- error lines ($(grep -c 'error:' "$full") in all)"; grep -E 'error:' "$full" | mask | sed "s#$root/##g" | sort -u | head -40
  echo "--- warning lines ($(grep -c 'warning:' "$full") in all; unique)"; grep -E 'warning:' "$full" | mask | sed "s#$root/##g" | sort -u | head -20
  echo "--- warnings in Spikes/G05-AI code: $(grep -cE 'Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:' "$full")"
  echo "--- ATSProbeTests.swift compiled for a device (arm64), by target"
  grep -E '^SwiftCompile normal arm64 Compiling\\? ATSProbeTests\.swift' "$full" | grep -oE "in target '[A-Za-z]+'" | sort -u
  echo "--- products (Debug-iphoneos)"
  (cd "$PROBE/.build/DerivedData/Build/Products/Debug-iphoneos" 2>/dev/null && ls -d *.app *.app/PlugIns/*.xctest 2>/dev/null)
  echo "--- last 10 lines of the output"; tail -10 "$full" | mask | sed "s#$root/##g"
  footer "$status"
} >> "$log"
targets="$(grep -E '^SwiftCompile normal arm64 Compiling\\? ATSProbeTests\.swift' "$full" | grep -oE "in target '[A-Za-z]+'" | sort -u | wc -l | tr -d ' ')"
ok=1
[[ "$status" == 0 ]] && grep -q '\*\* TEST BUILD SUCCEEDED \*\*' "$full" && [[ "$targets" == 3 ]] \
  && ! grep -qE 'Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:' "$full" && ok=0
verdict "$log" "$ok" 5 "exit $status; ATSProbeTests.swift compiled for arm64 in $targets test targets"

# 6. The ATS probe's tests on the simulator.
log="$OUT/atsprobe-simulator-tests.log"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
mac_addresses="$(ifconfig | awk '/^[a-z0-9]+:/ {name = $1; sub(":", "", name)} $1 == "inet" && $2 !~ /^127\./ {split($2, o, "."); print name " " o[1] "." o[2] ".x.x"}' | tr '\n' ';')"
cmd=(xcodebuild test -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination "id=$UDID"
  -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution)
{
  header "the ATS probe's tests in each variant on the simulator: the device checklist's step 1 command, destination this job's simulator, no signing flags (Scripts/ci.d/70-g05-ai.sh runs the same)" \
    "exit 0; three 'Test run with 14 tests in 2 suites passed'; in each variant a 'private-ipv4-interfaces=' line with 'rule=simulator: the first of any interface' and a 'private-ip=<a.b>.x.x interface=<name> result=URLError -1004' line; the public IP literal blocked (-1022) and localhost loaded in each; the suspension UI test passes"
  echo "# simulator: $SIM_NAME ($UDID), $SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME"
  echo "# this Mac's IPv4 addresses by interface, loopback left out (the simulator shares them): ${mac_addresses:-none}"
  echo "# command (in Spikes/G05-AI/ATSProbe):"
  echo "#   ${cmd[*]}"
  echo
} > "$log"
sylvia_generate "$PROBE" > "$FULL/atsprobe-generate-2.out" 2>&1 || { echo "sylvia_generate failed:"; cat "$FULL/atsprobe-generate-2.out"; } >> "$log"
(cd "$PROBE" && "${cmd[@]}") > "$FULL/atsprobe-simulator-tests.out" 2>&1
status=$?
sylvia_sim_shutdown "$UDID"
full="$FULL/atsprobe-simulator-tests.out"
mask < "$full" | sed "s#$root/##g" >> "$log"
{
  echo
  echo "--- result lines"
  grep -E "✔ Test run|✘|recorded an issue|ATS-PROBE|SUSPENSION-PROBE|Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)" "$full" | mask | cut -c1-400
  echo "--- warnings in Spikes/G05-AI code: $(grep -cE 'Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:' "$full")"
  footer "$status"
} >> "$log"
runs="$(grep -c 'Test run with 14 tests in 2 suites passed' "$full")"
refused="$(grep -cE '^ATS-PROBE variant=[a-z_]+ private-ip=[0-9]+\.[0-9]+\.x\.x interface=[a-z0-9_]+ result=URLError -1004 ' "$full")"
listed="$(grep -cE '^ATS-PROBE variant=[a-z_]+ private-ipv4-interfaces=.* rule=simulator: the first of any interface$' "$full")"
ok=1
[[ "$status" == 0 ]] && [[ "$runs" == 3 ]] && [[ "$refused" == 3 ]] && [[ "$listed" == 3 ]] \
  && grep -q "testLeavingTheForegroundMidStreamLeavesAnInterruptedPartialAnswer\]' passed" "$full" \
  && ! grep -qE '✘|recorded an issue' "$full" && ok=0
verdict "$log" "$ok" 6 "exit $status; $runs variant runs of 14 tests passed; $refused private-ip lines refused locally (-1004) with their interface; $listed interface lists"

echo
if (( ${#failures[@]} )); then echo "run-checks.sh: NOT as expected: steps ${failures[*]}"; exit 1; fi
echo "run-checks.sh: every step as expected"
