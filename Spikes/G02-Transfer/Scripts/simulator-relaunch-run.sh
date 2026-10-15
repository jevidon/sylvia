#!/usr/bin/env bash
# G0.2 part 2, T41 on the simulator: XCUITest terminates the harness app mid-transfer and launches it again.
#
#   Spikes/G02-Transfer/Scripts/simulator-relaunch-run.sh EVIDENCE-DIR [simulator-name] [wait-seconds]
#
# Two runs, each against its own sylvia-test-source serving a 40 MiB file in 4 MiB parts at about 1 MiB/s per
# response: "keep-alive" (connections reused) and "connection-close" (every request needs a new TLS handshake,
# so the system must get a trust answer from the app for each part, also while the app is not running).
# After each run the app's event log is pulled from the simulator and checked by analyze-relaunch.py (no part
# verified before the termination is fetched again; imported exactly once; source requests while the app was
# not running). Writes EVIDENCE-DIR/relaunch-<variant>.log. Environment: simulator, sources on the host.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"
source "$SYLVIA_ROOT/Spikes/G02-Transfer/Scripts/sim-sources.sh"

out_dir="$1"
name="${2:-Sylvia-M0-g02-transfer}"
wait_seconds="${3:-30}"
spike="$SYLVIA_ROOT/Spikes/G02-Transfer"
work="$SYLVIA_ROOT/.build/scratch/g02-relaunch-run"
bundle=com.jevidon.sylvia.spike.transfer
udid="$(sylvia_sim_udid "$name")"
sylvia_sim_boot "$udid"
rm -rf "$work"
mkdir -p "$work" "$out_dir"
trap 'rc=$?; g02_stop_all; exit $rc' EXIT

"$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-sim-files.sh" >/dev/null
generated="$("$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-sim-files.sh" --print-dir)"
g02_build_test_source
sylvia_generate "$spike/iOS"
status=0

for variant in keep-alive connection-close; do
  if [[ "$variant" == keep-alive ]]; then
    source_name=UI; method=testTerminatedMidTransferResumesFromVerifiedParts; extra=()
  else
    source_name=UICLOSE; method=testTerminatedMidTransferWhenEveryPartNeedsANewConnection; extra=(--test-close-connections)
  fi
  g02_start_source "$source_name" "$work" "sim-ui.bin=$generated/sim-ui.bin" -- \
    --bind 127.0.0.1 --part-size-mib 4 --test-throttle-kib 1024 --test-invitations 1 ${extra[@]+"${extra[@]}"}
  log="$out_dir/relaunch-$variant.log"
  {
    echo "environment: simulator $name ($udid), runtime $SYLVIA_SIM_RUNTIME, device type $SYLVIA_SIM_DEVICE_TYPE; XCUITest"
    echo "  source: sylvia-test-source on 127.0.0.1, 40 MiB file in 4 MiB parts, about 1 MiB/s per response$([[ $variant == connection-close ]] && echo ', Connection: close on every response')"
    echo "  app terminated with XCUIApplication.terminate() after at least 2 verified parts, not running for $wait_seconds s, then launched again"
    echo "  source ready: $(tr -d '\n' < "$work/$source_name/ready.json")"
  } > "$log"
  run_status=0
  (cd "$spike/iOS" && TEST_RUNNER_G02_UI_CODES="$work/UI/codes" TEST_RUNNER_G02_UICLOSE_CODES="$work/UICLOSE/codes" \
    TEST_RUNNER_G02_UI_WAIT_SECONDS="$wait_seconds" \
    xcodebuild test -project G02Transfer.xcodeproj -scheme G02TransferHarness -destination "id=$udid" \
      -derivedDataPath "$spike/iOS/.build/DerivedData" -disableAutomaticPackageResolution -skipPackagePluginValidation \
      "-only-testing:G02TransferUITests/TerminateRelaunchUITests/$method" > "$work/xcodebuild-$variant.log" 2>&1) || run_status=$?
  {
    echo "--- XCUITest (exit $run_status)"
    grep -E "G02-UI|Test Case .*(passed|failed)|error:|\*\* TEST" "$work/xcodebuild-$variant.log" | grep -v '^\[' || true
    echo "--- app event log (pulled from the simulator container), checked by analyze-relaunch.py"
  } >> "$log"
  container="$(xcrun simctl get_app_container "$udid" "$bundle" data 2>/dev/null || true)"
  events="$container/Library/Application Support/Transfers/events.jsonl"
  if [[ -f "$events" ]]; then
    cp "$events" "$work/events-$variant.jsonl"
    analysis_status=0
    /usr/bin/python3 "$spike/Scripts/analyze-relaunch.py" "$events" "$work/$source_name/out.log" >> "$log" 2>&1 || analysis_status=$?
    echo "--- raw app events" >> "$log"
    /usr/bin/python3 -c '
import json, sys
for line in open(sys.argv[1]):
    e = json.loads(line)
    print(e["time"], e["event"], " ".join(f"{k}={v}" for k, v in sorted(e["fields"].items())))
' "$events" >> "$log"
  else
    echo "no event log at $events" >> "$log"
    analysis_status=1
  fi
  echo "--- source output" >> "$log"
  sed "s/^/source> /" "$work/$source_name/out.log" >> "$log"
  g02_stop_all
  if (( run_status != 0 || analysis_status != 0 )); then
    echo "RESULT: FAIL (xcodebuild $run_status, analysis $analysis_status)" >> "$log"
    status=1
  elif ! grep -q "Test Case .*$method.* passed" "$work/xcodebuild-$variant.log"; then
    echo "RESULT: FAIL (the UI test did not run and pass)" >> "$log"
    status=1
  else
    echo "RESULT: PASS" >> "$log"
  fi
  grep -qE 'SYLVIA1-|sylvia://pair/v1#' "$log" && { echo "a pairing code reached $log" >&2; status=1; }
  echo "$variant: $(tail -1 "$log")"
done
trap - EXIT
exit "$status"
