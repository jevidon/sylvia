#!/bin/bash
# M0 device fixes, fix-1 (the correctness review of 26 October 2026, findings F1 and F3): the checks of the recovery
# spike that fix-1 affects, on the build Mac. Build Mac and simulator only: no physical device is used or contacted,
# nothing is installed on a device, nothing is pushed. No audio plays: the lock harness, whose tone test plays at the
# test volume 0.01, is not run (fix-1 does not change it).
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/commands/run-checks.sh
# Steps, each with its log under Docs/Stage0/evidence/M0-DeviceFixes/fix-1/ and its expectation written into the log
# before it runs:
#  1. host-tests.log: G0.5 recovery's host suite, `xcrun swift test --force-resolved-versions` in Spikes/G05-Recovery,
#     after deleting the spike's build products.
#  2. drills.log: the restore crash drill (300 iterations) and the migration put-back crash drill (240 iterations),
#     the drop-in's steps 8 and 9 with its own arguments, on step 1's build: each iteration resets its library with
#     FileProtector.copyTree, whose inside check fix-1 changed.
#  3. simulator-tests.log: the package's tests on this job's simulator, the drop-in's step 11 command.
#  4. devicetests-ios-build.log: the recovery suite's app host (Spikes/G05-Recovery/DeviceTests, Codex's project,
#     unchanged) generated with sylvia_generate and built for a generic iOS device: build-for-testing, unsigned.
# The screen lock state (ioreg, read only) and the load are recorded at the start and end of each step. Simulator:
# Sylvia-M0-devfix-fix1 (iPhone 17, iOS 26.5), this job's own, created if missing and shut down after its step; the job
# deletes it at its end. Exit 0 only if every step showed what its log states before it ran.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh

OUT="$root/Docs/Stage0/evidence/M0-DeviceFixes/fix-1"
FULL="$root/.build/scratch/m0-devfix-fix1"
SPIKE="$root/Spikes/G05-Recovery"
SIM_NAME=Sylvia-M0-devfix-fix1
mkdir -p "$OUT" "$FULL"
# Counted before this run deletes or writes anything.
uncommitted="$(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
commit="$(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
failures=()

plain() { perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' "$@"; }
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

# 1. Host suite, from clean.
log="$OUT/host-tests.log"
rm -rf "$SPIKE/.build"
{
  header "G0.5 recovery's host suite: xcrun swift test --force-resolved-versions (in Spikes/G05-Recovery, its .build deleted first)" \
    "exit 0 and 'Test run with 79 tests in 13 suites passed', no compiler warning in the spike; skipped: the 2 device probes, and with the screen locked the 4 class-B tests (with it unlocked, the locked-host observation instead); the copy guard reports 0 calls that keep the source's class; the missing file rejected as 'missing file' both ways; copyTree's inside refusal under /var and through /private; the unlisted dangling link rejected as a link"
  echo "---- xcrun swift test --force-resolved-versions"
} > "$log"
(cd "$SPIKE" && xcrun swift test --force-resolved-versions) > "$FULL/host-tests.out" 2>&1
status=$?
plain "$FULL/host-tests.out" >> "$log"
{
  echo "---- summary"
  echo "compiler warnings in Spikes/G05-Recovery sources and tests: $(own_warnings "$FULL/host-tests.out")"
  echo "skipped tests:"; plain "$FULL/host-tests.out" | grep -E 'Test ".*" skipped' | sed 's/^/  /'
  echo "evidence lines of fix-1 and of the two suites it extends:"
  plain "$FULL/host-tests.out" | grep -E '\] (copy guard|missing listed file|containment check|v1 library installed|class-B tree|copyTree, |rejected unlisted-dangling-link|rejected missing-blob-file)' | sed 's/^/  /'
  footer "$status"
} >> "$log"
ok=1
[[ "$status" == 0 ]] && grep -q 'Test run with 79 tests in 13 suites passed' "$log" && [[ "$(own_warnings "$FULL/host-tests.out")" == 0 ]] \
  && grep -q 'calls that keep the source.s class: 0' "$log" \
  && grep -q 'missing listed file, bundle .*through /private, as an iPhone.s folders are named: missing file:' "$log" \
  && grep -q 'copyTree, a destination inside the source: under /var, as the Mac names its temporary folder: copy Copy is inside Template: .*; through /private, as an iPhone.s folders are named: copy Copy is inside Template: ' "$log" \
  && grep -q 'rejected unlisted-dangling-link: symbolic link in bundle: export/markdown/dangling.md' "$log" && ok=0
verdict "$log" "$ok" 1 "swift test exit $status; $(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites (passed|failed)[^.]*' "$log" | tail -1)"

# 2. The two SIGKILL drills that reset their library with copyTree, on step 1's build.
log="$OUT/drills.log"
work="$FULL/drills"
rm -rf "$work"
{
  header "the drop-in's steps 8 and 9 with its own arguments (restore crash drill, 300 iterations; migration put-back crash drill, 240 iterations), with the tool step 1 built; every iteration resets its library with FileProtector.copyTree" \
    "each exits 0 with 'failures: 0' and 'RESULT: PASS'"
} > "$log"
(
  cd "$SPIKE" || exit 1
  TOOL="$(xcrun swift build --force-resolved-versions --show-bin-path)/g05-recovery-tool"
  echo "tool: ${TOOL#"$root/"} (built by step 1)"
  echo; echo "=== 8. restore crash drill, 300 iterations"
  "$TOOL" restore-crash-drill --root "$work/restore-crash" --iterations 300; s8=$?
  echo "step 8 exit: $s8"
  echo; echo "=== 9. migration put-back crash drill, 240 iterations"
  "$TOOL" migration-crash-drill --root "$work/migration-crash" --iterations 240; s9=$?
  echo "step 9 exit: $s9"
  (( s8 == 0 && s9 == 0 ))
) > "$FULL/drills.out" 2>&1
status=$?
plain "$FULL/drills.out" | sed "s#$root/##g" >> "$log"
footer "$status" >> "$log"
ok=1
[[ "$status" == 0 ]] && [[ "$(grep -c '^RESULT: PASS' "$log")" == 2 ]] && [[ "$(grep -c '^failures: 0' "$log")" == 2 ]] && ok=0
verdict "$log" "$ok" 2 "exit $status; $(grep -c '^RESULT: PASS' "$log") of 2 drills 'RESULT: PASS'"

# 3. The package's tests on this job's simulator.
log="$OUT/simulator-tests.log"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
{
  header "G0.5 recovery's tests on the simulator: the drop-in's step 11 command (xcodebuild test -scheme G05Recovery-Package), destination this job's simulator" \
    "exit 0 and 'Test run with 73 tests in 13 suites passed'; the class-B, device-only and macOS-only tests skipped or not built, as before; copyTree's inside refusal and the dangling-link rejection as on the Mac (the simulator's folders are in the Mac's home folder, which has no /private form)"
  echo "# simulator: $SIM_NAME ($UDID), $SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME"
  echo "# command (in Spikes/G05-Recovery): xcodebuild test -scheme G05Recovery-Package -destination id=$UDID -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution"
  echo
} > "$log"
(cd "$SPIKE" && xcodebuild test -scheme G05Recovery-Package -destination "id=$UDID" -derivedDataPath "$SPIKE/.build/DerivedData" \
  -disableAutomaticPackageResolution) > "$FULL/simulator-tests.out" 2>&1
status=$?
sylvia_sim_shutdown "$UDID"
plain "$FULL/simulator-tests.out" | sed "s#$root/##g" >> "$log"
{
  echo
  echo "--- summary"
  echo "warnings in Spikes/G05-Recovery sources and tests: $(own_warnings "$FULL/simulator-tests.out")"
  plain "$FULL/simulator-tests.out" | grep -E 'Test run with|TEST (SUCCEEDED|FAILED)|\] (copyTree, |rejected unlisted-dangling-link|rejected missing-blob-file|missing listed file)' | sed "s#$root/##g"
  footer "$status"
} >> "$log"
ok=1
[[ "$status" == 0 ]] && grep -q 'Test run with 73 tests in 13 suites passed' "$log" \
  && grep -q 'rejected unlisted-dangling-link: symbolic link in bundle: export/markdown/dangling.md' "$log" \
  && grep -q 'copyTree, a destination inside the source: .*copy Copy is inside Template: ' "$log" && ok=0
verdict "$log" "$ok" 3 "xcodebuild exit $status; $(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites (passed|failed)[^.]*' "$log" | tail -1)"

# 4. The recovery suite's app host for a generic iOS device.
log="$OUT/devicetests-ios-build.log"
rm -rf "$SPIKE/DeviceTests/.build" "$SPIKE/DeviceTests/G05RecoveryDeviceTests.xcodeproj"
cmd=(xcodebuild build-for-testing -project DeviceTests/G05RecoveryDeviceTests.xcodeproj -scheme G05RecoveryDeviceTests
  -destination generic/platform=iOS -derivedDataPath DeviceTests/.build/DerivedData -disableAutomaticPackageResolution
  CODE_SIGNING_ALLOWED=NO)
{
  header "the recovery suite's app host (Spikes/G05-Recovery/DeviceTests) for a generic iOS device: sylvia_generate, then xcodebuild build-for-testing, unsigned (build only; no device)" \
    "exit 0, TEST BUILD SUCCEEDED; BackupTests.swift, PrivatePathTests.swift and ProtectedCopyTests.swift compiled for arm64 in SylviaRecoveryTests, and FileSystem.swift, FileProtection.swift and Container.swift in SylviaRecovery; no warning in Spikes/G05-Recovery sources and tests"
  echo "# command (in Spikes/G05-Recovery, after sylvia_generate Spikes/G05-Recovery/DeviceTests):"
  echo "#   ${cmd[*]}"
} > "$log"
sylvia_generate "$SPIKE/DeviceTests" > "$FULL/devicetests-generate.out" 2>&1 || { echo "sylvia_generate failed:"; cat "$FULL/devicetests-generate.out"; } >> "$log"
(cd "$SPIKE" && "${cmd[@]}") > "$FULL/devicetests-ios-build.out" 2>&1
status=$?
full="$FULL/devicetests-ios-build.out"
compiled_in() {  # compiled_in <target>: the Swift files compiled for arm64 in that target
  grep -E '^(SwiftCompile|SwiftDriverJobDiscovery) normal arm64 .*Compiling' "$full" | grep "in target '$1'" \
    | grep -oE '[A-Za-z+]+\.swift' | sort -u
}
{
  echo "--- result lines"; grep -E '\*\* (BUILD|TEST BUILD) (SUCCEEDED|FAILED|INTERRUPTED) \*\*' "$full" | sort -u
  echo "--- error lines ($(grep -c 'error:' "$full") in all)"; grep -E 'error:' "$full" | sed "s#$root/##g" | sort -u | head -40
  echo "--- warning lines ($(grep -c 'warning:' "$full") in all; unique)"; grep -E 'warning:' "$full" | sed "s#$root/##g" | sort -u | head -20
  echo "--- warnings in Spikes/G05-Recovery sources and tests: $(own_warnings "$full")"
  echo "--- Swift sources compiled for arm64 in target SylviaRecoveryTests"; compiled_in SylviaRecoveryTests | tr '\n' ' '; echo
  echo "--- Swift sources compiled for arm64 in target SylviaRecovery"; compiled_in SylviaRecovery | tr '\n' ' '; echo
  echo "--- products (Debug-iphoneos)"
  (cd "$SPIKE/DeviceTests/.build/DerivedData/Build/Products/Debug-iphoneos" 2>/dev/null && ls -d *.app *.app/PlugIns/*.xctest 2>/dev/null)
  echo "--- last 10 lines of the output"; tail -10 "$full" | sed "s#$root/##g"
  footer "$status"
} >> "$log"
compiled=0
for f in BackupTests PrivatePathTests ProtectedCopyTests; do compiled_in SylviaRecoveryTests | grep -qx "$f.swift" && compiled=$((compiled + 1)); done
for f in FileSystem FileProtection Container; do compiled_in SylviaRecovery | grep -qx "$f.swift" && compiled=$((compiled + 1)); done
ok=1
[[ "$status" == 0 ]] && grep -q '\*\* TEST BUILD SUCCEEDED \*\*' "$full" && [[ "$(own_warnings "$full")" == 0 ]] && (( compiled == 6 )) && ok=0
verdict "$log" "$ok" 4 "exit $status; of the six changed files, $compiled compiled for arm64 in their targets"

echo
if (( ${#failures[@]} )); then echo "run-checks.sh: NOT as expected: steps ${failures[*]}"; exit 1; fi
echo "run-checks.sh: every step as expected"
