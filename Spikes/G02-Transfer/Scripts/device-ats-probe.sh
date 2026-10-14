#!/usr/bin/env bash
# G0.2: the App Transport Security probe (ATSProbeTests) on a phone, against a source on this Mac's LAN address
# (device checklist step 23; review finding R3-06). The simulator results in ADR-0008's ATS table come from the
# same test run by simulator-background-run.sh; this script gives the device run the same inputs without host
# paths, which a phone cannot read.
#
#   Spikes/G02-Transfer/Scripts/device-ats-probe.sh LOG VARIANT DESTINATION [xcodebuild arguments...]
#
#   VARIANT       none (the harness, no ATS key), local-networking or tailnet-exception (G02TransferATSVariant)
#   DESTINATION   an xcodebuild destination: 'platform=iOS,name=<the iPhone>' for the phone (add
#                 -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z), or 'id=<simulator UDID>' to try the
#                 recipe on a simulator (the CI drop-in does that, step simulator-ats-device-recipe)
#   G02_INCLUDE_TAILSCALE=1   also probe the Mac's Tailscale address and MagicDNS name (the phone must have
#                 Tailscale connected); otherwise only the LAN address and the .local name are probed
#
# Starts sylvia-test-source bound to the LAN address (and the Tailscale address when included), with an ephemeral
# identity, and plain-HTTP control servers on the same addresses; passes their details inline
# (TEST_RUNNER_G02_MAIN_READY_JSON, TEST_RUNNER_G02_CLEARTEXT_JSON) with TEST_RUNNER_G02_DEVICE_RUN=1, which leaves
# out the loopback forms (on a phone they are the phone itself) and makes the probe print its log
# ("G02-ATS-PROBE ..." lines). LOG gets that log, the Swift Testing result lines and the run's environment. No
# pairing happens (the probe calls only the unauthenticated GET /v1/capabilities), so no code or token exists.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"
source "$SYLVIA_ROOT/Spikes/G02-Transfer/Scripts/sim-sources.sh"

log="$1"
variant="$2"
destination="$3"
extra=("${@:4}")
spike="$SYLVIA_ROOT/Spikes/G02-Transfer"
work="$SYLVIA_ROOT/.build/scratch/g02-device-ats-$variant"
case "$variant" in
  none) scheme=(-scheme G02TransferHarness); only=-only-testing:G02TransferHostedTests/ATSProbeTests ;;
  local-networking|tailnet-exception)
    scheme=(-scheme G02TransferATSVariant "G02_ATS_VARIANT=$variant"); only=-only-testing:G02TransferATSVariantTests/ATSProbeTests ;;
  *) echo "unknown variant $variant (none, local-networking, tailnet-exception)" >&2; exit 64 ;;
esac

rm -rf "$work"
mkdir -p "$work" "$(dirname "$log")"
trap 'rc=$?; g02_stop_all; exit $rc' EXIT
g02_build_test_source
g02_network_facts
[[ -n "$G02_LAN_IP" ]] || { echo "this Mac has no LAN (en0) IPv4 address; the probe needs one" >&2; exit 2; }
include_tailscale="${G02_INCLUDE_TAILSCALE:-0}"
if [[ "$include_tailscale" == 1 && -z "$G02_TAILSCALE_IP" ]]; then
  echo "G02_INCLUDE_TAILSCALE=1 but this Mac has no Tailscale address" >&2; exit 2
fi

binds=(--bind "$G02_LAN_IP")
[[ -n "$G02_LOCAL_HOSTNAME" ]] && binds+=(--advertise-host "$G02_LOCAL_HOSTNAME")
if [[ "$include_tailscale" == 1 ]]; then
  binds+=(--bind "$G02_TAILSCALE_IP")
  [[ -n "$G02_MAGICDNS" ]] && binds+=(--advertise-host "$G02_MAGICDNS")
fi
printf 'ats probe\n' > "$work/probe.bin"
g02_start_source MAIN "$work" "probe.bin=$work/probe.bin" -- "${binds[@]}"

cleartext="{"
g02_start_cleartext "$G02_LAN_IP" "$work"
cleartext+="\"$G02_LAN_IP\": $G02_CLEARTEXT_PORT"
[[ -n "$G02_LOCAL_HOSTNAME" ]] && cleartext+=", \"$G02_LOCAL_HOSTNAME\": $G02_CLEARTEXT_PORT"
tailscale_ip=""
magicdns=""
if [[ "$include_tailscale" == 1 ]]; then
  g02_start_cleartext "$G02_TAILSCALE_IP" "$work"
  cleartext+=", \"$G02_TAILSCALE_IP\": $G02_CLEARTEXT_PORT"
  tailscale_ip="$G02_TAILSCALE_IP"
  if [[ -n "$G02_MAGICDNS" ]]; then
    cleartext+=", \"$G02_MAGICDNS\": $G02_CLEARTEXT_PORT"
    magicdns="$G02_MAGICDNS"
  fi
fi
cleartext+="}"

: > "$log"
note() { printf '%s\n' "$*" >> "$log"; }
note "G0.2 ATS probe through Scripts/device-ats-probe.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note "destination: $destination; variant: $variant; Mac: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); uptime: $(uptime)"
note "address forms: LAN $G02_LAN_IP, .local ${G02_LOCAL_HOSTNAME:-none}; Tailscale ${tailscale_ip:-not included}, MagicDNS ${magicdns:-not included}"
note "source: sylvia-test-source (ephemeral identity; no pairing in this run); cleartext controls: $cleartext"

sylvia_generate "$spike/iOS" >/dev/null
status=0
(cd "$spike/iOS" && \
  TEST_RUNNER_G02_DEVICE_RUN=1 TEST_RUNNER_G02_MAIN_READY_JSON="$(tr -d '\n' < "$work/MAIN/ready.json")" \
  TEST_RUNNER_G02_CLEARTEXT_JSON="$cleartext" TEST_RUNNER_G02_LAN_IP="$G02_LAN_IP" \
  TEST_RUNNER_G02_LOCAL_HOSTNAME="$G02_LOCAL_HOSTNAME" TEST_RUNNER_G02_TAILSCALE_IP="$tailscale_ip" \
  TEST_RUNNER_G02_MAGICDNS="$magicdns" \
  xcodebuild test -project G02Transfer.xcodeproj "${scheme[@]}" -destination "$destination" \
    -derivedDataPath "$spike/iOS/.build/DerivedData-device-ats-$variant" -disableAutomaticPackageResolution \
    -skipPackagePluginValidation "$only" ${extra[@]+"${extra[@]}"} > "$work/xcodebuild.log" 2>&1) || status=$?

note ""
note "--- the probe's log (printed by the test on the destination)"
grep -o 'G02-ATS-PROBE .*' "$work/xcodebuild.log" | sed 's/^G02-ATS-PROBE //' >> "$log" || true
note ""
note "--- test result (xcodebuild exit status $status; full output: ${work#"$SYLVIA_ROOT"/}/xcodebuild.log)"
grep -E '✔|✘|recorded an issue|\*\* TEST|error:' "$work/xcodebuild.log" | grep -v '^\[' >> "$log" || true
note ""
note "--- source output (requests carry IDs and ranges only)"
sed 's/^/MAIN> /' "$work/MAIN/out.log" >> "$log"
g02_stop_all
trap - EXIT
g02_redact "$log"
probe_lines="$(grep -c 'G02-ATS-PROBE' "$work/xcodebuild.log" || true)"
if (( probe_lines == 0 )); then
  note "RESULT: NO PROBE OUTPUT (the test did not run on the destination; see the full output)"
  exit 1
fi
if (( status != 0 )); then
  note "RESULT: the probe ran, and at least one expectation (the simulator's results) did not hold on this destination: record each differing line as a finding"
  exit 1
fi
note "RESULT: PASS (every form behaved as on the simulator)"
