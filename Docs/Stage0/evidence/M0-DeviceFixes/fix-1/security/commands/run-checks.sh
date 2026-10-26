#!/bin/bash
# M0 device fixes, fix-1, the security review of 26 October 2026: the checks that the security fix's changes affect, on
# the build Mac. Build Mac and simulator only: no physical device is used or contacted, nothing is installed on a
# device, nothing is pushed. No audio plays: the lock harness, whose tone test plays at the test volume 0.01, is not
# run (the fix does not change it).
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/run-checks.sh
# Steps, each with its log under Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/ and its expectation written into
# the log before it runs:
#  1. host-tests.log: G0.5 recovery's host suite, `xcrun swift test --force-resolved-versions` in Spikes/G05-Recovery,
#     after deleting the spike's build products (the copy guard and PrivatePathTests changed; two source comments).
#  2. simulator-tests.log: the package's tests on this job's simulator, the drop-in's step 11 command
#     (PrivatePathTests runs on iOS too; the guard is built for the Mac only).
#  3. devicetests-ios-build.log: the recovery suite's app host (Spikes/G05-Recovery/DeviceTests, Codex's project,
#     unchanged) generated with sylvia_generate and built for a generic iOS device: build-for-testing, unsigned.
#  4. atsprobe-ios-build.log: the ATS probe (Spikes/G05-AI/ATSProbe) generated and built for a generic iOS device,
#     unsigned, after the change of a comment in ATSProbeTests.swift; and the check that the change touched comment
#     lines only and left the default variant's device expectation at ATSProbeTests.swift:164.
# The screen lock state (ioreg, read only) and the load are recorded at the start and end of each step. Simulator:
# Sylvia-M0-devfix-fix1-sec (iPhone 17, iOS 26.5), this job's own, created if missing and shut down after its step; the
# job deletes it at its end. Exit 0 only if every step showed what its log states before it ran.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh

OUT="$root/Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security"
FULL="$root/.build/scratch/security-fix/checks"
SPIKE="$root/Spikes/G05-Recovery"
PROBE="$root/Spikes/G05-AI/ATSProbe"
SIM_NAME=Sylvia-M0-devfix-fix1-sec
REVIEWED=31e460e643f12113e2f063d775672bdfb7b87ec7
mkdir -p "$OUT" "$FULL"
uncommitted="$(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
commit="$(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
failures=()

plain() { perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' "$@"; }
# Private (10/8, 172.16/12, 192.168/16) and shared (100.64/10) IPv4 addresses beyond their first two octets.
mask() { perl -pe 's/\e\[[0-9;]*[A-Za-z]//g; s/\b(10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])|192\.168|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b/$1.x.x/g'; }
header() {  # header <title> <expected>
  echo "# $1"
  echo "# expected (stated before the run): $2"
  echo "# commit: $commit; uncommitted files before this run: $uncommitted"
  echo "# uncommitted changes in Spikes/ included in this run:"
  git -C "$root" diff --stat HEAD -- Spikes | sed 's/^/#   /'
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
    "exit 0 and 'Test run with 79 tests in 13 suites passed' (no test added), no compiler warning in the spike; skipped: the 2 device probes, and with the screen locked the 4 class-B tests; the widened copy guard passes with its 15 pattern samples and reports 'copy guard: 61 source files in Sources, Tests, DeviceTests and LockHarness; calls that keep the source's class: 0'; containmentFollowsLinks passes with its new isInside expectations; the evidence lines of fix-1 unchanged (missing file both ways, copyTree's inside refusal under /var and through /private, the dangling link refused as a link)"
  echo "---- xcrun swift test --force-resolved-versions"
} > "$log"
(cd "$SPIKE" && xcrun swift test --force-resolved-versions) > "$FULL/host-tests.out" 2>&1
status=$?
plain "$FULL/host-tests.out" | grep -vE '^\[[0-9]+/[0-9]+\] (Compiling|Write|Emitting|Linking|Applying)' >> "$log"
{
  echo "---- summary"
  echo "compiler warnings in Spikes/G05-Recovery sources and tests: $(own_warnings "$FULL/host-tests.out")"
  echo "skipped tests:"; plain "$FULL/host-tests.out" | grep -E 'Test ".*" skipped' | sed 's/^/  /'
  echo "the guard's and containmentFollowsLinks's results:"
  plain "$FULL/host-tests.out" | grep -E 'Test "(no code in the recovery spike|the containment check follows links).*" (passed|failed)' | sed 's/^/  /'
  echo "evidence lines of the suites the fix touches:"
  plain "$FULL/host-tests.out" | grep -E '\] (copy guard|missing listed file|containment check|v1 library installed|class-B tree|copyTree, |rejected unlisted-dangling-link|rejected missing-blob-file)' | sed 's/^/  /'
  footer "$status"
} >> "$log"
ok=1
[[ "$status" == 0 ]] && grep -q 'Test run with 79 tests in 13 suites passed' "$log" && [[ "$(own_warnings "$FULL/host-tests.out")" == 0 ]] \
  && grep -q "copy guard: 61 source files in Sources, Tests, DeviceTests and LockHarness; calls that keep the source's class: 0" "$log" \
  && grep -qE 'Test "no code in the recovery spike copies or links a file.*" passed' "$log" \
  && grep -qE 'Test "the containment check follows links.*" passed' "$log" \
  && grep -q 'missing listed file, bundle .*through /private, as an iPhone.s folders are named: missing file:' "$log" \
  && grep -q 'copyTree, a destination inside the source: under /var, as the Mac names its temporary folder: copy Copy is inside Template: .*; through /private, as an iPhone.s folders are named: copy Copy is inside Template: ' "$log" \
  && grep -q 'rejected unlisted-dangling-link: symbolic link in bundle: export/markdown/dangling.md' "$log" && ok=0
verdict "$log" "$ok" 1 "swift test exit $status; $(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites (passed|failed)[^.]*' "$log" | tail -1)"

# 2. The package's tests on this job's simulator.
log="$OUT/simulator-tests.log"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
{
  header "G0.5 recovery's tests on the simulator: the drop-in's step 11 command (xcodebuild test -scheme G05Recovery-Package), destination this job's simulator" \
    "exit 0 and 'Test run with 73 tests in 13 suites passed'; containmentFollowsLinks, with its new isInside expectations, passes in its one form there (the simulator's folders are in the Mac's home folder, which has no /private form); the class-B, device-only and macOS-only tests skipped or not built, as before"
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
  plain "$FULL/simulator-tests.out" | grep -E 'Test run with|TEST (SUCCEEDED|FAILED)|Test "the containment check follows links.*" (passed|failed)|\] (containment check|copyTree, |rejected unlisted-dangling-link|rejected missing-blob-file|missing listed file)' | sed "s#$root/##g"
  footer "$status"
} >> "$log"
ok=1
[[ "$status" == 0 ]] && grep -q 'Test run with 73 tests in 13 suites passed' "$log" \
  && grep -qE 'Test "the containment check follows links.*" passed' "$log" \
  && grep -q 'rejected unlisted-dangling-link: symbolic link in bundle: export/markdown/dangling.md' "$log" && ok=0
verdict "$log" "$ok" 2 "xcodebuild exit $status; $(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites (passed|failed)[^.]*' "$log" | tail -1)"

# 3. The recovery suite's app host for a generic iOS device.
log="$OUT/devicetests-ios-build.log"
rm -rf "$SPIKE/DeviceTests/.build" "$SPIKE/DeviceTests/G05RecoveryDeviceTests.xcodeproj"
cmd=(xcodebuild build-for-testing -project DeviceTests/G05RecoveryDeviceTests.xcodeproj -scheme G05RecoveryDeviceTests
  -destination generic/platform=iOS -derivedDataPath DeviceTests/.build/DerivedData -disableAutomaticPackageResolution
  CODE_SIGNING_ALLOWED=NO)
{
  header "the recovery suite's app host (Spikes/G05-Recovery/DeviceTests) for a generic iOS device: sylvia_generate, then xcodebuild build-for-testing, unsigned (build only; no device)" \
    "exit 0, TEST BUILD SUCCEEDED; PrivatePathTests.swift and ProtectedCopyTests.swift compiled for arm64 in SylviaRecoveryTests, and FileProtection.swift and Container.swift in SylviaRecovery; no warning in Spikes/G05-Recovery sources and tests"
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
for f in PrivatePathTests ProtectedCopyTests; do compiled_in SylviaRecoveryTests | grep -qx "$f.swift" && compiled=$((compiled + 1)); done
for f in FileProtection Container; do compiled_in SylviaRecovery | grep -qx "$f.swift" && compiled=$((compiled + 1)); done
ok=1
[[ "$status" == 0 ]] && grep -q '\*\* TEST BUILD SUCCEEDED \*\*' "$full" && [[ "$(own_warnings "$full")" == 0 ]] && (( compiled == 4 )) && ok=0
verdict "$log" "$ok" 3 "exit $status; of the four changed files, $compiled compiled for arm64 in their targets"

# 4. The ATS probe for a generic iOS device, and the extent of its change.
log="$OUT/atsprobe-ios-build.log"
rm -rf "$PROBE/.build" "$PROBE/G05ATSProbe.xcodeproj" "$root/Spikes/G05-AI/.build"
cmd=(xcodebuild build-for-testing -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination generic/platform=iOS
  -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO)
probe_file="Spikes/G05-AI/ATSProbe/Tests/ATSProbeTests.swift"
{
  header "the ATS probe (Spikes/G05-AI/ATSProbe) for a generic iOS device: sylvia_generate, then xcodebuild build-for-testing, unsigned (build only; no device); and the change to $probe_file against $REVIEWED" \
    "the change replaces 2 comment lines (88-90 stay 3 lines) and nothing else, so the file keeps its 289 lines and line 164 is still the default variant's device expectation; exit 0, TEST BUILD SUCCEEDED; ATSProbeTests.swift compiled for arm64 in each of the three test targets; no warning in Spikes/G05-AI code"
  echo "# command (in Spikes/G05-AI/ATSProbe, after sylvia_generate Spikes/G05-AI/ATSProbe):"
  echo "#   ${cmd[*]}"
  echo "--- git diff $REVIEWED -- $probe_file"
  git -C "$root" diff "$REVIEWED" -- "$probe_file"
  echo "--- changed lines that are not comments: $(git -C "$root" diff -U0 "$REVIEWED" -- "$probe_file" | grep -E '^[+-] ' | grep -cvE '^[+-][[:space:]]*///')"
  echo "--- lines in the file: $(wc -l < "$root/$probe_file" | tr -d ' ') (at $REVIEWED: $(git -C "$root" show "$REVIEWED:$probe_file" | wc -l | tr -d ' '))"
  echo "--- line 164 now:"; sed -n 164p "$root/$probe_file"
  echo "--- line 164 at $REVIEWED:"; git -C "$root" show "$REVIEWED:$probe_file" | sed -n 164p
} > "$log"
sylvia_generate "$PROBE" > "$FULL/atsprobe-generate.out" 2>&1 || { echo "sylvia_generate failed:"; cat "$FULL/atsprobe-generate.out"; } >> "$log"
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
noncomment="$(git -C "$root" diff -U0 "$REVIEWED" -- "$probe_file" | grep -E '^[+-] ' | grep -cvE '^[+-][[:space:]]*///')"
same164="$( [[ "$(sed -n 164p "$root/$probe_file")" == "$(git -C "$root" show "$REVIEWED:$probe_file" | sed -n 164p)" ]] && echo yes || echo no)"
ok=1
[[ "$status" == 0 ]] && grep -q '\*\* TEST BUILD SUCCEEDED \*\*' "$full" && [[ "$targets" == 3 ]] \
  && ! grep -qE 'Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:' "$full" && [[ "$noncomment" == 0 ]] && [[ "$same164" == yes ]] && ok=0
verdict "$log" "$ok" 4 "exit $status; ATSProbeTests.swift compiled for arm64 in $targets test targets; non-comment lines changed: $noncomment; line 164 unchanged: $same164"

echo
if (( ${#failures[@]} )); then echo "run-checks.sh: NOT as expected: steps ${failures[*]}"; exit 1; fi
echo "run-checks.sh: every step as expected"
