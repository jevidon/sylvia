#!/usr/bin/env bash
# G0.2 part 2: hosted simulator tests of the background-session client against sylvia-test-source on this Mac.
#
#   Spikes/G02-Transfer/Scripts/simulator-background-run.sh LOG [simulator-name] [-only-testing:...]
#
# Starts three sources (MAIN: the LibriVox M4B and a 20 MiB file, bound to loopback, the LAN address and the
# Tailscale address when present, advertised by Bonjour and by .local and MagicDNS names, queueing the 20 MiB file
# for every device that pairs so the device-inbox test finds it; FAULTY: one corrupted
# part and Connection: close; SLOW: 4 MiB parts at about 4 MiB/s) and plain-HTTP controls for the ATS probe,
# then runs G02TransferHostedTests/BackgroundSessionTests and ATSProbeTests. Each test writes its own log under
# $G02_EVIDENCE_DIR (default Docs/Stage0/evidence/G02-Transfer)/{simulator,ats}/; LOG gets the run summary and each source's request log.
# Environment: simulator (the named device) talking to the host's sources; the simulator shares the Mac's
# network stack, so this is not Wi-Fi between two devices.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"
source "$SYLVIA_ROOT/Spikes/G02-Transfer/Scripts/sim-sources.sh"

log="$1"
name="${2:-Sylvia-M0-g02-transfer}"
only=("${@:3}")
default_selection=0
if [[ ${#only[@]} -eq 0 ]]; then
  only=(-only-testing:G02TransferHostedTests/BackgroundSessionTests -only-testing:G02TransferHostedTests/ATSProbeTests)
  default_selection=1
fi
spike="$SYLVIA_ROOT/Spikes/G02-Transfer"
evidence="${G02_EVIDENCE_DIR:-$SYLVIA_ROOT/Docs/Stage0/evidence/G02-Transfer}"
work="$SYLVIA_ROOT/.build/scratch/g02-bg-run"
udid="$(sylvia_sim_udid "$name")"
sylvia_sim_boot "$udid"
rm -rf "$work"
mkdir -p "$work"
trap 'rc=$?; g02_stop_all; exit $rc' EXIT

"$SYLVIA_ROOT/Scripts/fixtures/fetch.sh" m4b >/dev/null
"$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-sim-files.sh" >/dev/null
generated="$("$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-sim-files.sh" --print-dir)"
m4b="$SYLVIA_FIXTURE_CACHE/downloads/MeditationsMarcusAurelius_librivox.m4b"
g02_build_test_source
g02_network_facts

main_binds=(--bind 127.0.0.1 --bind ::1)
[[ -n "$G02_LAN_IP" ]] && main_binds+=(--bind "$G02_LAN_IP")
[[ -n "$G02_TAILSCALE_IP" ]] && main_binds+=(--bind "$G02_TAILSCALE_IP")
[[ -n "$G02_MAGICDNS" ]] && main_binds+=(--advertise-host "$G02_MAGICDNS")
[[ -n "$G02_LOCAL_HOSTNAME" ]] && main_binds+=(--advertise-host "$G02_LOCAL_HOSTNAME")

g02_start_source MAIN "$work" "meditations-librivox.m4b=$m4b,sim-small.bin=$generated/sim-small.bin" -- \
  "${main_binds[@]}" --bonjour --test-invitations 5 --test-send-on-pair sim-small
g02_start_source FAULTY "$work" "sim-faulty.bin=$generated/sim-faulty.bin" -- \
  --bind 127.0.0.1 --test-corrupt-part 1 --test-close-connections --test-invitations 2
g02_start_source SLOW "$work" "mutable.bin=$generated/sim-slow.bin,revocable.bin=$generated/sim-slow.bin" -- \
  --bind 127.0.0.1 --part-size-mib 4 --test-throttle-kib 4096 --test-invitations 3

# Plain-HTTP controls for the ATS probe: one per address form (a name uses the server of its address).
cleartext="{"
add_cleartext() { cleartext+="\"$1\": $2, "; }
# g02_start_cleartext runs in this shell (not in "$(...)") so g02_stop_all kills every control server.
g02_start_cleartext 127.0.0.1 "$work"; add_cleartext 127.0.0.1 "$G02_CLEARTEXT_PORT"; add_cleartext localhost "$G02_CLEARTEXT_PORT"
g02_start_cleartext ::1 "$work"; add_cleartext ::1 "$G02_CLEARTEXT_PORT"
if [[ -n "$G02_LAN_IP" ]]; then
  g02_start_cleartext "$G02_LAN_IP" "$work"; add_cleartext "$G02_LAN_IP" "$G02_CLEARTEXT_PORT"
  [[ -n "$G02_LOCAL_HOSTNAME" ]] && add_cleartext "$G02_LOCAL_HOSTNAME" "$G02_CLEARTEXT_PORT"
fi
if [[ -n "$G02_TAILSCALE_IP" ]]; then
  g02_start_cleartext "$G02_TAILSCALE_IP" "$work"; add_cleartext "$G02_TAILSCALE_IP" "$G02_CLEARTEXT_PORT"
  [[ -n "$G02_MAGICDNS" ]] && add_cleartext "$G02_MAGICDNS" "$G02_CLEARTEXT_PORT"
fi
cleartext="${cleartext%, }}"
echo "$cleartext" > "$work/cleartext.json"

: > "$log"
note() { printf '%s\n' "$*" >> "$log"; }
fail() { note "FAIL: $*"; echo "FAIL: $*" >&2; exit 1; }
note "environment: simulator $name ($udid), runtime $SYLVIA_SIM_RUNTIME, device type $SYLVIA_SIM_DEVICE_TYPE"
note "  host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); sources: sylvia-test-source (auto-approve, codes in files)"
note "  address forms: LAN ${G02_LAN_IP:-none}, .local ${G02_LOCAL_HOSTNAME:-none}, Tailscale ${G02_TAILSCALE_IP:-none}, MagicDNS ${G02_MAGICDNS:-none}"
for source in MAIN FAULTY SLOW; do note "  $source ready: $(tr -d '\n' < "$work/$source/ready.json")"; done
note "  cleartext controls: $cleartext"

sylvia_generate "$spike/iOS"
mkdir -p "$evidence/simulator" "$evidence/ats"
run_tests() {
  local out="$1"; shift
  (cd "$spike/iOS" && \
    TEST_RUNNER_G02_MAIN_READY="$work/MAIN/ready.json" TEST_RUNNER_G02_MAIN_CODES="$work/MAIN/codes" \
    TEST_RUNNER_G02_FAULTY_READY="$work/FAULTY/ready.json" TEST_RUNNER_G02_FAULTY_CODES="$work/FAULTY/codes" \
    TEST_RUNNER_G02_SLOW_READY="$work/SLOW/ready.json" TEST_RUNNER_G02_SLOW_CODES="$work/SLOW/codes" \
    TEST_RUNNER_G02_EVIDENCE_DIR="$evidence" TEST_RUNNER_G02_LAN_IP="$G02_LAN_IP" \
    TEST_RUNNER_G02_LOCAL_HOSTNAME="$G02_LOCAL_HOSTNAME" TEST_RUNNER_G02_TAILSCALE_IP="$G02_TAILSCALE_IP" \
    TEST_RUNNER_G02_MAGICDNS="$G02_MAGICDNS" TEST_RUNNER_G02_CLEARTEXT="$work/cleartext.json" \
    xcodebuild test -project G02Transfer.xcodeproj -destination "id=$udid" -disableAutomaticPackageResolution \
      -skipPackagePluginValidation "$@" > "$out" 2>&1)
}
check_run() {
  local out="$1"
  grep -E '✔|✘|➜ Test|\*\* TEST|error:|warning:|recorded an issue' "$out" | grep -v '^\[' >> "$log" || true
  grep -q 'Test run with [1-9][0-9]* tests\? in [0-9]* suites\? passed' "$out" || return 1
  if grep -Eq '➜ Test .* skipped|✘' "$out"; then return 1; fi
}

# G02_LOOPBACK_ONLY=1 (an agent's run): MAIN binds loopback only, so BonjourAdvertiser registers the service local to
# this Mac (kDNSServiceInterfaceIndexLocalOnly), which the simulator's NWBrowser does not see: the browse test finds
# nothing in 20 s at any load (M0 assembly, integration log section 7). It is left out and listed as not run, like the
# LAN and Tailscale steps; without G02_LOOPBACK_ONLY it runs as before. The test itself is unchanged.
bonjour_test='G02TransferHostedTests/BackgroundSessionTests/bonjourBrowseFindsResolvesAndPinsTheSource()'
if [[ "${G02_LOOPBACK_ONLY:-0}" == 1 && "$default_selection" == 1 ]]; then
  only+=("-skip-testing:$bonjour_test")
  note "NOT RUN: $bonjour_test (G02_LOOPBACK_ONLY=1: the source's Bonjour registration is local to this Mac, which the simulator's browser does not see)"
fi
note "script> xcodebuild test -scheme G02TransferHarness ${only[*]} (destination id=$udid)"
test_status=0
run_tests "$work/xcodebuild.log" -scheme G02TransferHarness -derivedDataPath "$spike/iOS/.build/DerivedData" "${only[@]}" || test_status=$?
check_run "$work/xcodebuild.log" || test_status=${test_status/#0/1}

# ATS probe variants (Config/ATSVariant-*.plist): the same probe in an app that declares an ATS key.
variant_status=0
if [[ "${G02_SKIP_ATS_VARIANTS:-0}" != 1 ]]; then
  for variant in local-networking tailnet-exception; do
    note "script> xcodebuild test -scheme G02TransferATSVariant G02_ATS_VARIANT=$variant (ATS probe variant)"
    status=0
    run_tests "$work/xcodebuild-ats-$variant.log" -scheme G02TransferATSVariant G02_ATS_VARIANT="$variant" \
      -derivedDataPath "$spike/iOS/.build/DerivedData-ats-$variant" \
      -only-testing:G02TransferATSVariantTests/ATSProbeTests || status=$?
    check_run "$work/xcodebuild-ats-$variant.log" || status=${status/#0/1}
    (( status == 0 )) || variant_status=$status
  done
fi
for source in MAIN FAULTY SLOW; do
  note "--- $source source output (requests carry IDs and ranges only; codes were written to a file, never printed)"
  sed "s/^/$source> /" "$work/$source/out.log" >> "$log"
done
g02_stop_all
trap - EXIT
g02_redact "$log" "$evidence"/simulator/*.log "$evidence"/ats/*.log
# Nothing this run started may still be listening (review finding R1-03: cleartext controls used to leak).
leaked="$(pgrep -fl -- "$work/" || true)"
[[ -z "$leaked" ]] || fail "processes started by this run are still running: $leaked"
note "after the run: no process started by this run is still running (pgrep over $work/ found none)"

(( test_status == 0 )) || fail "harness tests failed or did not run (status $test_status; full log: $work/xcodebuild.log)"
(( variant_status == 0 )) || fail "ATS probe variant tests failed or did not run (logs: $work/xcodebuild-ats-*.log)"
grep -qE 'SYLVIA1-|sylvia://pair/v1#' "$log" "$evidence"/simulator/*.log && fail "a pairing code reached a log"
note "RESULT: PASS"
