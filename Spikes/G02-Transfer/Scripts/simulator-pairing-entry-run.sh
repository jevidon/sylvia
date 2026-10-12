#!/usr/bin/env bash
# G0.2: pairing entry paths on the simulator (review findings R1-09, R1-10): paste, sylvia:// link, and an
# address replaced before pairing that leads to another Mac (pin mismatch, nothing sent).
#
#   Spikes/G02-Transfer/Scripts/simulator-pairing-entry-run.sh LOG [simulator-name]
#
# Starts two sylvia-test-source processes on 127.0.0.1: ENTRY (the genuine Mac, three single-use codes in a
# file) and ROGUE (another identity, the "other Mac"). Runs G02TransferUITests/PairingEntryUITests, then checks
# the source logs: ENTRY answered exactly three successful POST /v1/pair; ROGUE accepted at least one TCP
# connection, answered no request and decrypted no application byte. Environment: simulator, sources on the host.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"
source "$SYLVIA_ROOT/Spikes/G02-Transfer/Scripts/sim-sources.sh"

log="$1"
name="${2:-Sylvia-M0-g02-transfer}"
spike="$SYLVIA_ROOT/Spikes/G02-Transfer"
work="$SYLVIA_ROOT/.build/scratch/g02-entry-run"
udid="$(sylvia_sim_udid "$name")"
sylvia_sim_boot "$udid"
rm -rf "$work"
mkdir -p "$work" "$(dirname "$log")"
trap 'rc=$?; g02_stop_all; exit $rc' EXIT

"$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-sim-files.sh" >/dev/null
generated="$("$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-sim-files.sh" --print-dir)"
g02_build_test_source
g02_start_source ENTRY "$work" "sim-small.bin=$generated/sim-small.bin" -- --bind 127.0.0.1 --test-invitations 3
g02_start_source ROGUE "$work" "sim-small.bin=$generated/sim-small.bin" -- --bind 127.0.0.1 --test-invitations 1
rogue_port="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "$work/ROGUE/ready.json")"
sylvia_generate "$spike/iOS"

: > "$log"
note() { printf '%s\n' "$*" >> "$log"; }
note "environment: simulator $name ($udid), runtime $SYLVIA_SIM_RUNTIME, device type $SYLVIA_SIM_DEVICE_TYPE; XCUITest"
note "  host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); sources: sylvia-test-source on 127.0.0.1 (auto-approve, codes in a file)"
note "  ENTRY (genuine Mac) ready: $(tr -d '\n' < "$work/ENTRY/ready.json")"
note "  ROGUE (another identity) ready: $(tr -d '\n' < "$work/ROGUE/ready.json")"
note "script> xcodebuild test -scheme G02TransferHarness -only-testing:G02TransferUITests/PairingEntryUITests (destination id=$udid)"
status=0
(cd "$spike/iOS" && TEST_RUNNER_G02_ENTRY_CODES="$work/ENTRY/codes" TEST_RUNNER_G02_ROGUE_PORT="$rogue_port" \
  xcodebuild test -project G02Transfer.xcodeproj -scheme G02TransferHarness -destination "id=$udid" \
    -derivedDataPath "$spike/iOS/.build/DerivedData" -disableAutomaticPackageResolution -skipPackagePluginValidation \
    -only-testing:G02TransferUITests/PairingEntryUITests > "$work/xcodebuild.log" 2>&1) || status=$?
note "--- XCUITest (exit $status)"
grep -E "G02-UI|Test Case .*(passed|failed)|error:|\*\* TEST|Executed [0-9]+ tests?" "$work/xcodebuild.log" | grep -v '^\[' >> "$log" || true
g02_stop_all
trap - EXIT

note "--- ENTRY source output (requests carry IDs and paths only; codes were written to a file, never printed)"
sed "s/^/ENTRY> /" "$work/ENTRY/out.log" >> "$log"
note "--- ROGUE source output"
sed "s/^/ROGUE> /" "$work/ROGUE/out.log" >> "$log"

checks=0
fail_check() { note "CHECK FAILED: $*"; checks=1; }
passed="$(grep -cE 'Test Case .*PairingEntryUITests.* passed' "$work/xcodebuild.log" || true)"
[[ "$passed" == 3 ]] || fail_check "expected 3 passing UI tests, found $passed"
pairs="$(grep -cE '^request .* POST /v1/pair range=- -> 200' "$work/ENTRY/out.log" || true)"
[[ "$pairs" == 3 ]] || fail_check "expected 3 successful POST /v1/pair at ENTRY, found $pairs"
note "ENTRY: successful POST /v1/pair: $pairs (paste, link, and the genuine address after the rogue attempt)"
rogue_requests="$(grep -c '^request ' "$work/ROGUE/out.log" || true)"
rogue_last="$(grep '^connections ' "$work/ROGUE/out.log" | tail -1 || true)"
rogue_accepted="$(sed -nE 's/.* accepted=([0-9]+).*/\1/p' <<< "$rogue_last")"
rogue_bytes="$(sed -nE 's/.* decrypted_bytes=([0-9]+).*/\1/p' <<< "$rogue_last")"
note "ROGUE: requests answered: $rogue_requests; TCP connections accepted: ${rogue_accepted:-0}; decrypted application bytes: ${rogue_bytes:-0}"
[[ "$rogue_requests" == 0 ]] || fail_check "the rogue source answered a request"
(( ${rogue_accepted:-0} >= 1 )) || fail_check "the phone never connected to the rogue address (the test did not exercise it)"
[[ "${rogue_bytes:-0}" == 0 ]] || fail_check "the rogue source decrypted application bytes"
grep -qE 'SYLVIA1-|sylvia://pair/v1#' "$log" && fail_check "a pairing code reached the log"
leaked="$(pgrep -fl -- "$work/" || true)"
[[ -z "$leaked" ]] || fail_check "processes started by this run are still running: $leaked"
if (( status != 0 || checks != 0 )); then
  note "RESULT: FAIL (xcodebuild $status, checks $checks; full log: $work/xcodebuild.log)"
  exit 1
fi
note "RESULT: PASS"
