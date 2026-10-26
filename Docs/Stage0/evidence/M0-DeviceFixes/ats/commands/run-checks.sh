#!/usr/bin/env bash
# M0 device fixes, the ATS probe's address (G0.5 AI checklist step 1, runbook 1.3; ../README.md): the checks of the
# fix on the build Mac. Build and simulator only: no physical device is used or contacted, nothing is signed, nothing
# is pushed, and no test plays audio (the suspension UI test streams text from the probe app's in-app fake server).
#
#   Docs/Stage0/evidence/M0-DeviceFixes/ats/commands/run-checks.sh          # steps 1-3, from clean
#   Docs/Stage0/evidence/M0-DeviceFixes/ats/commands/run-checks.sh audit    # step 4 only, once the README is written
#
# 1. device-build-for-testing.log: the probe's scheme built for a generic iOS device, build only (xcodebuild
#    build-for-testing, as Docs/Stage0/evidence/M0-runbook/commands/verify-device-builds.sh checks the checklist's
#    device command), unsigned (CODE_SIGNING_ALLOWED=NO). The device branch of the fix (#if !targetEnvironment(simulator))
#    compiles only for a device; the fix changes no signing setting, and this job uses no signing identity. A summary:
#    the whole xcodebuild output stays in .build/scratch/m0-devfix-ats/ (gitignored, not committed).
# 2. simulator-probe-test.log: the probe's tests in each variant on this job's simulator: the checklist's step 1 command
#    with the simulator as its destination and without the signing flags, as Scripts/ci.d/70-g05-ai.sh runs it; the
#    whole output, then its result lines.
# 3. ci-run.log: Scripts/ci.sh g05-ai hard-rules (00-git-lfs runs first): the G0.5 AI drop-in, which runs the probe again
#    with every other G0.5 AI check, and the audit that reads every committed and new file; then the three drop-ins'
#    logs. ci-70-g05-ai-sim-probe-test.log: the drop-in's whole probe output.
# 4. ci-hard-rules-final.log: Scripts/ci.sh hard-rules again, once the README and these logs exist, so the audit has
#    read them too.
# Steps 1-3 first delete the spike's build products (Spikes/G05-AI/.build, Spikes/G05-AI/ATSProbe/.build, the
# generated G05ATSProbe.xcodeproj) and .build/ci-logs, so everything is built again from the commit.
# The committed logs have the private IPv4 addresses (10/8, 172.16/12, 192.168/16) and the shared-address ones that
# Tailscale uses (100.64/10) masked beyond their first two octets, as the G0.5 AI device checklist's Recording paragraph
# keeps addresses, this checkout's absolute path shortened to
# paths relative to its root, and terminal colour codes removed; nothing else is changed. Simulator:
# Sylvia-M0-devfix-ats (iPhone 17, iOS 26.5), this job's own, created if missing and deleted at the end. Exit status 0
# only if every step showed what is stated for it before it runs.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$ROOT" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh

OUT="Docs/Stage0/evidence/M0-DeviceFixes/ats"
FULL="$ROOT/.build/scratch/m0-devfix-ats"
PROBE="Spikes/G05-AI/ATSProbe"
SIM_NAME="Sylvia-M0-devfix-ats"
mkdir -p "$OUT" "$FULL"
mode="${1:-all}"
# Counted before this run writes anything.
uncommitted="$(git -C "$ROOT" status --porcelain | wc -l | tr -d ' ')"
commit="$(git -C "$ROOT" rev-parse HEAD) ($(git -C "$ROOT" rev-parse --abbrev-ref HEAD))"
failures=0

mask() {
  perl -pe 's/\e\[[0-9;]*[A-Za-z]//g; s/\b(10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])|192\.168|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b/$1.x.x/g' \
    | sed -e "s#$ROOT/##g"
}

header() {  # header <title> <expected>
  echo "# $1"
  echo "# expected (stated before the run): $2"
  echo "# commit: $commit; uncommitted files before this run: $uncommitted"
  echo "# host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "# started: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //') (other jobs share this Mac: timings are indicative only)"
}

verdict() {  # verdict <log> <ok 0|1> <what>
  if [[ "$2" == 0 ]]; then
    echo "# result: as expected ($3)" >> "$1"
    echo "$1: as expected ($3)"
  else
    echo "# result: NOT as expected ($3)" >> "$1"
    echo "$1: NOT as expected ($3)"
    failures=$((failures + 1))
  fi
}

if [[ "$mode" == audit ]]; then
  log="$OUT/ci-hard-rules-final.log"
  {
    header "Scripts/ci.sh hard-rules, after the README and the logs of steps 1-3 were written (they are among the files it reads)" \
      "\"all 2 steps passed\" (00-git-lfs and 13-hard-rules)"
    echo "# command: G02_LOOPBACK_ONLY=1 Scripts/ci.sh hard-rules"
    echo "## Scripts/ci.sh console"
  } > "$log"
  G02_LOOPBACK_ONLY=1 Scripts/ci.sh hard-rules 2>&1 | mask >> "$log"
  status="${PIPESTATUS[0]}"
  for name in 00-git-lfs 13-hard-rules; do
    { echo; echo "## .build/ci-logs/$name.log"; mask < ".build/ci-logs/$name.log"; } >> "$log"
  done
  echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ); exit status $status; load: $(uptime | sed 's/.*load averages*: //')" >> "$log"
  ok=1; [[ "$status" == 0 ]] && grep -q '^all 2 steps passed' "$log" && ok=0
  verdict "$log" "$ok" "ci.sh exit $status"
  exit "$failures"
fi

rm -rf Spikes/G05-AI/.build "$PROBE/.build" "$PROBE/G05ATSProbe.xcodeproj" .build/ci-logs "$FULL"
mkdir -p "$FULL"
echo "deleted before the run: Spikes/G05-AI/.build $PROBE/.build $PROBE/G05ATSProbe.xcodeproj .build/ci-logs"

# This Mac's own IPv4 addresses by interface, loopback left out, each masked beyond its first two octets: the simulator
# shares them, so they say what step 2 should pick.
mac_addresses="$(ifconfig | awk '/^[a-z0-9]+:/ {name = $1; sub(":", "", name)} $1 == "inet" && $2 !~ /^127\./ {split($2, o, "."); print name " " o[1] "." o[2] ".x.x"}' | tr '\n' ';')"

# 1. Generic iOS device, build only, unsigned.
log="$OUT/device-build-for-testing.log"
header "the ATS probe's scheme for a generic iOS device: xcodebuild build-for-testing, unsigned (build only; no device)" \
  "exit 0, TEST BUILD SUCCEEDED, ATSProbeTests.swift compiled for arm64 in each of the three test targets, no warning in Spikes/G05-AI code" > "$log"
sylvia_generate "$PROBE" > "$FULL/generate-1.log" 2>&1 || echo "sylvia_generate failed: $(cat "$FULL/generate-1.log")" >> "$log"
cmd=(xcodebuild build-for-testing -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination generic/platform=iOS
  -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO)
{ echo "# command (in $PROBE, after sylvia_generate $PROBE):"; echo "#   ${cmd[*]}"; } >> "$log"
(cd "$PROBE" && "${cmd[@]}") > "$FULL/device-build-for-testing.out" 2>&1
status=$?
full="$FULL/device-build-for-testing.out"
{
  echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ); exit status $status; load: $(uptime | sed 's/.*load averages*: //')"
  echo "--- result lines"
  grep -E '\*\* (BUILD|TEST BUILD|CLEAN) (SUCCEEDED|FAILED|INTERRUPTED) \*\*' "$full" | sort -u
  echo "--- error lines ($(grep -c 'error:' "$full") in all)"
  grep -E 'error:' "$full" | mask | sort -u | head -40
  echo "--- warning lines ($(grep -c 'warning:' "$full") in all; unique)"
  grep -E 'warning:' "$full" | mask | sort -u | head -20
  echo "--- warnings in Spikes/G05-AI code (the G0.5 AI drop-in fails on any): $(grep -cE 'Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:' "$full")"
  echo "--- ATSProbeTests.swift compiled for a device (arm64), by target"
  grep -E '^SwiftCompile normal arm64 Compiling\\? ATSProbeTests\.swift' "$full" | grep -oE "in target '[A-Za-z]+'" | sort -u
  echo "--- products (Debug-iphoneos)"
  (cd "$PROBE/.build/DerivedData/Build/Products/Debug-iphoneos" 2>/dev/null && ls -d *.app *.app/PlugIns/*.xctest 2>/dev/null)
  echo "--- last 10 lines of the output"
  tail -10 "$full" | mask
} >> "$log"
targets="$(grep -E '^SwiftCompile normal arm64 Compiling\\? ATSProbeTests\.swift' "$full" | grep -oE "in target '[A-Za-z]+'" | sort -u | wc -l | tr -d ' ')"
ok=1
[[ "$status" == 0 ]] && grep -q '\*\* TEST BUILD SUCCEEDED \*\*' "$full" && [[ "$targets" == 3 ]] \
  && ! grep -qE 'Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:' "$full" && ok=0
verdict "$log" "$ok" "exit $status; ATSProbeTests.swift compiled for arm64 in $targets test targets"

# 2. The probe's simulator tests in each variant, as the checklist's command runs them, on this job's simulator.
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
log="$OUT/simulator-probe-test.log"
header "the ATS probe's tests in each variant on the simulator: the checklist's step 1 command, destination this job's simulator, no signing flags (Scripts/ci.d/70-g05-ai.sh runs the same)" \
  "exit 0; three 'Test run with 14 tests in 2 suites passed' (one per variant); in each variant a 'private-ipv4-interfaces=' line with the simulator's rule and a 'private-ip=<a.b>.x.x interface=<name> result=URLError -1004' line for the Mac's own address; no failure; the suspension UI test passes" > "$log"
{
  echo "# simulator: $SIM_NAME ($UDID), $SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME; state $(xcrun simctl list devices | grep "$UDID" | grep -oE '\((Booted|Shutdown)\)')"
  echo "# this Mac's IPv4 addresses by interface, loopback left out (the simulator shares them): ${mac_addresses:-none}"
} >> "$log"
sylvia_generate "$PROBE" > "$FULL/generate-2.log" 2>&1 || echo "sylvia_generate failed: $(cat "$FULL/generate-2.log")" >> "$log"
cmd=(xcodebuild test -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination "id=$UDID"
  -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution)
{ echo "# command (in $PROBE):"; echo "#   ${cmd[*]}"; echo; } >> "$log"
(cd "$PROBE" && "${cmd[@]}") > "$FULL/simulator-probe-test.out" 2>&1
status=$?
sylvia_sim_shutdown "$UDID"
full="$FULL/simulator-probe-test.out"
mask < "$full" >> "$log"
{
  echo
  echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ); exit status $status; load: $(uptime | sed 's/.*load averages*: //')"
  echo "--- result lines"
  grep -E "✔ Test run|✘|recorded an issue|ATS-PROBE|SUSPENSION-PROBE|Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)" "$full" | mask | cut -c1-400
  echo "--- warnings in Spikes/G05-AI code: $(grep -cE 'Spikes/G05-AI/(Sources|Tests|ATSProbe)/.*warning:' "$full")"
} >> "$log"
runs="$(grep -c 'Test run with 14 tests in 2 suites passed' "$full")"
# The probe prints the address masked (a.b.x.x) and the interface beside it.
refused="$(grep -cE '^ATS-PROBE variant=[a-z_]+ private-ip=[0-9]+\.[0-9]+\.x\.x interface=[a-z0-9_]+ result=URLError -1004 ' "$full")"
listed="$(grep -cE '^ATS-PROBE variant=[a-z_]+ private-ipv4-interfaces=.* rule=simulator: the first of any interface$' "$full")"
ok=1
[[ "$status" == 0 ]] && [[ "$runs" == 3 ]] && [[ "$refused" == 3 ]] && [[ "$listed" == 3 ]] \
  && grep -q "testLeavingTheForegroundMidStreamLeavesAnInterruptedPartialAnswer\]' passed" "$full" \
  && ! grep -qE '✘|recorded an issue' "$full" && ok=0
verdict "$log" "$ok" "exit $status; $runs variant runs of 14 tests passed; $refused private-ip lines refused locally (-1004) with their interface; $listed interface lists"

# 3. The drop-ins that read these files: the G0.5 AI drop-in (the probe again, with every other G0.5 AI check) and the
#    hard-rules audit, through Scripts/ci.sh (00-git-lfs first).
log="$OUT/ci-run.log"
{
  header "Scripts/ci.sh g05-ai hard-rules: 00-git-lfs, 13-hard-rules and 70-g05-ai (the G0.5 AI drop-in runs the probe on the simulator named by SYLVIA_G05_SIM_NAME)" \
    "\"all 3 steps passed\"; the drop-in's probe log has three 'Test run with 14 tests in 2 suites passed'"
  echo "# command: SYLVIA_G05_SIM_NAME=$SIM_NAME G02_LOOPBACK_ONLY=1 Scripts/ci.sh g05-ai hard-rules"
  echo "## Scripts/ci.sh console"
} > "$log"
SYLVIA_G05_SIM_NAME="$SIM_NAME" G02_LOOPBACK_ONLY=1 Scripts/ci.sh g05-ai hard-rules 2>&1 | mask >> "$log"
status="${PIPESTATUS[0]}"
for name in 00-git-lfs 13-hard-rules 70-g05-ai; do
  { echo; echo "## .build/ci-logs/$name.log"; [[ -f ".build/ci-logs/$name.log" ]] && mask < ".build/ci-logs/$name.log"; } >> "$log"
done
echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ); exit status $status; load: $(uptime | sed 's/.*load averages*: //')" >> "$log"
probe_log="Spikes/G05-AI/.build/g05-ci/sim-probe-test.log"
{
  echo "# the G0.5 AI drop-in's probe output ($probe_log), from the run recorded in ci-run.log"
  echo "# commit: $commit"
  echo
  [[ -f "$probe_log" ]] && mask < "$probe_log"
} > "$OUT/ci-70-g05-ai-sim-probe-test.log"
dropin_runs="$(grep -c 'Test run with 14 tests in 2 suites passed' "$probe_log" 2>/dev/null)"
ok=1
[[ "$status" == 0 ]] && grep -q '^all 3 steps passed' "$log" && [[ "$dropin_runs" == 3 ]] && ok=0
verdict "$log" "$ok" "ci.sh exit $status; the drop-in's probe log has ${dropin_runs:-0} variant runs of 14 tests passed"

sylvia_sim_delete "$SIM_NAME" >/dev/null 2>&1 && echo "deleted simulator $SIM_NAME"
exit "$failures"
