#!/usr/bin/env bash
# G0.2 transfer (part 1: pairing, Mac source service, contracts, host fault tests; part 2: the iOS background
# transfer client): every automated check.
#
#   Scripts/ci.sh g02-transfer        (or run this file directly)
#
# Steps, each logged to Docs/Stage0/evidence/G02-Transfer/ci/<step>.log:
#   contracts             Scripts/ci.d/10-contracts.sh: schemas, fixtures and the OpenAPI document         [host]
#   fixtures-check        the contract fixture generator reproduces the committed fixtures exactly
#   trust-guards          no ATS key in the harness (ATS keys only in the probe variants Config/ATSVariant-*.plist,
#                         NSAllowsArbitraryLoads nowhere), no server-trust credential outside the pinned
#                         answer, no TLS minimum below 1.2 in the spike                              [host]
#   host-transferkit      swift test, Spikes/G02-Transfer/TransferKit (protocol core, client, background
#                         client: planner, descriptors, importer)                                  [host]
#   host-sourceservice    swift test, Spikes/G02-Transfer/SourceService, all suites but the 5 GiB,
#                         including the background coordinator against the in-process source       [host]
#   captured-payloads     payloads captured by those tests validate against Contracts/schemas      [host]
#   large-5gib            generate the 5 GiB file, then the 5 GiB tests in a process of their own:
#                         the foreground engine (bounded memory) and the background client with a
#                         relaunch half way (launch re-hash and final full-file check: lock not held) [host]
#   cli-*                 scripted runs of sylvia-source with sylvia-fetch: loopback IPv4 and IPv6
#                         always; the LAN (en0) and Tailscale addresses and MagicDNS name when this
#                         Mac has them (a step that cannot run says so and why, and is listed)     [host]
#   mac-identity-signed   the Mac identity store in a signed probe app (team A4KBDX665Z): key in the data
#                         protection keychain, after first unlock, this device only; NOT RUN (listed) when
#                         this Mac cannot sign for the team                                          [host]
#   simulator             TransferKit tests and hosted Keychain tests on the simulator named
#                         Sylvia-M0-g02-transfer (iPhone 17, iOS 26.5 by default)                  [simulator]
#   simulator-pairing     the simulator pairs with sylvia-source on this Mac (pinned TLS, approval,
#                         Keychain token) and downloads the 138 MB LibriVox M4B with verified
#                         16 MiB parts, then revokes itself                                         [simulator]
#   simulator-background  part 2: background-session transfers against sylvia-test-source (full, wrong
#                         digest, source change, revocation and relaunch, address forms, Bonjour, device
#                         inbox) and the ATS probe in the harness and two ATS variants            [simulator]
#   simulator-pairing-entry  XCUITest pairs by pasting the code, by opening a sylvia:// link, and with the
#                         address replaced before pairing by another Mac's (refused on the pin, nothing
#                         sent); the source logs are checked                                        [simulator]
#   simulator-relaunch    part 2: XCUITest terminates the app mid-transfer and relaunches it, with
#                         keep-alive and with Connection: close; event logs checked for refetches  [simulator]
#
# Exits non-zero if any step fails. Needs network access for the pinned Swift packages and the fixture
# downloads (Scripts/fixtures/fetch.sh) on a clean clone.
set -uo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

spike="$SYLVIA_ROOT/Spikes/G02-Transfer"
evidence="$SYLVIA_ROOT/Docs/Stage0/evidence/G02-Transfer"
logs="$evidence/ci"
mkdir -p "$logs"
simulator="${SYLVIA_G02_SIMULATOR:-Sylvia-M0-g02-transfer}"
failed=()
not_run=()

echo "G0.2 transfer CI drop-in, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
sylvia_check_xcode || true
echo "swift: $(xcrun swift --version 2>&1 | head -1)"

run_step() {
  local name="$1"; shift
  local start=$SECONDS
  echo "== $name"
  if "$@" > "$logs/$name.log" 2>&1; then
    echo "   pass ($((SECONDS - start)) s) - ${logs#"$SYLVIA_ROOT"/}/$name.log"
  else
    echo "   FAIL ($((SECONDS - start)) s) - ${logs#"$SYLVIA_ROOT"/}/$name.log"
    tail -n 40 "$logs/$name.log" | sed 's/^/   | /'
    failed+=("$name")
  fi
}

not_run_step() {
  local name="$1" reason="$2"
  echo "== $name"
  echo "   NOT RUN: $reason"
  printf 'NOT RUN on this Mac: %s\n' "$reason" > "$logs/$name.log"
  not_run+=("$name")
}

# swift test exits 0 when nothing ran; also require a test run that executed tests and skipped none.
swift_test() {
  local package="$1"; shift
  xcrun swift test --package-path "$spike/$package" "$@" 2>&1
}

checked_swift_test() {
  local log="$1" package="$2"; shift 2
  swift_test "$package" "$@" | tee "$log.raw"
  local status=${PIPESTATUS[0]}
  if (( status != 0 )); then rm -f "$log.raw"; return "$status"; fi
  if ! grep -Eq '✔ Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed' "$log.raw"; then
    echo "CHECK FAILED: no passing Swift Testing run with at least one test"; rm -f "$log.raw"; return 1
  fi
  if grep -Eq '➜ Test .* skipped|✘' "$log.raw"; then
    echo "CHECK FAILED: a test was skipped or failed"; rm -f "$log.raw"; return 1
  fi
  rm -f "$log.raw"
}

step_fixtures() { "$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-contract-fixtures.sh" --check; }

# Static guards against a trust bypass creeping in (plan 14.3, 22.3). The behavior itself is proven by the
# rogue-host and wrong-pin tests; these catch configuration that would weaken it.
step_guards() {
  echo "environment: host; static checks over Spikes/G02-Transfer (sources, project files, plists)"
  local hits count
  hits="$(grep -rn 'NSAllowsArbitraryLoads' "$spike" --include='*.swift' --include='*.yml' --include='*.plist' \
    | grep -v '/\.build/' || true)"
  if [[ -n "$hits" ]]; then echo "NSAllowsArbitraryLoads found:"; echo "$hits"; return 1; fi
  echo "ok: NSAllowsArbitraryLoads appears nowhere"
  # ATS keys may appear only in the probe variants' plists, which build G02TransferATSVariant (never shipped).
  hits="$(grep -rn -E 'NSAppTransportSecurity|NSExceptionAllowsInsecureHTTPLoads|NSExceptionMinimumTLSVersion|NSExceptionDomains|NSAllowsLocalNetworking|NSExceptionRequiresForwardSecrecy' \
    "$spike" --include='*.swift' --include='*.yml' --include='*.plist' | grep -v '/\.build/' \
    | grep -v '/iOS/Config/ATSVariant-[a-z-]*\.plist:' \
    | grep -v -E '\.swift:[0-9]+:[[:space:]]*//' \
    | grep -v -E '/iOS/Config/Harness-Info\.plist:[0-9]+:  Deliberately absent: NSAppTransportSecurity\.' \
    | grep -v -E '/iOS/Tests/HostedUnit/ATSProbeTests\.swift:.*(forInfoDictionaryKey: "NSAppTransportSecurity"|Info.plist NSAppTransportSecurity|no NSAppTransportSecurity key)' || true)"
  if [[ -n "$hits" ]]; then echo "ATS keys outside the probe variants:"; echo "$hits"; return 1; fi
  echo "ok: no App Transport Security key in the harness; ATS keys only in iOS/Config/ATSVariant-*.plist (probe app); Swift comment lines that name a key are not configuration and are ignored"
  if grep -q 'Config/ATSVariant' "$spike/iOS/project.yml" && \
    awk '/^  G02TransferHarness:/{h=1} /^  G02TransferHostedTests:/{h=0} h' "$spike/iOS/project.yml" | grep -q 'ATSVariant'; then
    echo "the harness target uses an ATS variant plist"; return 1
  fi
  echo "ok: G02TransferHarness uses Config/Harness-Info.plist only"
  hits="$(grep -rn 'URLCredential(trust:' "$spike" --include='*.swift' | grep -v '/\.build/' || true)"
  count="$(printf '%s' "$hits" | grep -c . || true)"
  if [[ "$count" != 1 || "$hits" != *"/SylviaTransferClient/PinnedSession.swift:"* ]]; then
    echo "a server-trust credential is created outside the pinned answer:"; echo "$hits"; return 1
  fi
  echo "ok: URLCredential(trust:) appears once, in PinnedTrustEvaluator.answer (PinnedSession.swift), used by every session"
  hits="$(grep -rn -E 'tlsMinimumSupportedProtocolVersion *= *\.TLSv1[01]|minimumTLSVersion *= *\.tlsv1[01]?\b' "$spike" --include='*.swift' \
    | grep -v '/\.build/' || true)"
  if [[ -n "$hits" ]]; then echo "TLS below 1.2 allowed:"; echo "$hits"; return 1; fi
  echo "ok: no TLS minimum below 1.2"
}

step_host_transferkit() {
  echo "environment: host (macOS $(sw_vers -productVersion)), swift test"
  checked_swift_test "$logs/host-transferkit" TransferKit
}

# Payloads the host-sourceservice tests write to $evidence/captured/ (one per file, all required).
captured_expected=(
  capabilities catalog-page device-inbox-page error-precondition-failed error-rate-limited error-unsupported-version
  pair-request pair-response pairing-payload receipt-downloaded receipt-imported transfer-manifest
)

step_host_sourceservice() {
  echo "environment: host (macOS $(sw_vers -productVersion)), swift test; in-process source on 127.0.0.1, ephemeral ports, real TLS"
  echo "the 5 GiB suite runs separately in step large-5gib"
  # Captures from an earlier run must never satisfy step captured-payloads (review finding R1-02).
  rm -f "$evidence"/captured/*.json
  echo "removed earlier captures from ${evidence#"$SYLVIA_ROOT"/}/captured/"
  checked_swift_test "$logs/host-sourceservice" SourceService --skip LargeTransferTests
}

step_captured() {
  echo "environment: host; payloads written by the host-sourceservice step of this run"
  local name missing=0
  for name in ${failed[@]+"${failed[@]}"}; do
    if [[ "$name" == host-sourceservice ]]; then
      echo "host-sourceservice failed in this run, so its captures are incomplete; not validated"; return 1
    fi
  done
  for name in "${captured_expected[@]}"; do
    if [[ ! -f "$evidence/captured/$name.json" ]]; then echo "missing capture: captured/$name.json"; missing=1; fi
  done
  (( missing == 0 )) || return 1
  echo "all ${#captured_expected[@]} expected captures were written by this run (the folder is emptied before host-sourceservice)"
  sylvia_python "$spike/Scripts/validate-captured.py" "$evidence/captured" "$SYLVIA_ROOT/Contracts/schemas"
}

step_large() {
  echo "environment: host (macOS $(sw_vers -productVersion)); 5 GiB test in a process of its own"
  "$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-large.sh" || return 1
  local file sha
  file="$("$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-large.sh" --print-path)"
  sha="$(awk -F'"' '/^readonly EXPECTED_SHA256=/ {print $2}' "$SYLVIA_ROOT/Scripts/fixtures/generate-g02-transfer-large.sh")"
  [[ -n "$sha" ]] || { echo "could not read the pinned digest"; return 1; }
  SYLVIA_G02_LARGE_FILE="$file" SYLVIA_G02_LARGE_SHA256="$sha" \
    checked_swift_test "$logs/large-5gib" SourceService --filter LargeTransferTests || return 1
  grep -q 'fiveGiBTransferSurvivesInterruptionsWithBoundedMemory() passed' "$logs/large-5gib.log" \
    || { echo "CHECK FAILED: the 5 GiB test did not run and pass"; return 1; }
  grep -q 'fiveGiBThroughTheBackgroundClientWithARelaunch() passed' "$logs/large-5gib.log" \
    || { echo "CHECK FAILED: the 5 GiB background-client test did not run and pass"; return 1; }
  echo "--- faults/large-5GiB-transfer.log (written by the test)"
  cat "$evidence/faults/large-5GiB-transfer.log"
  echo "--- faults/large-5GiB-background-client.log (written by the test)"
  cat "$evidence/faults/large-5GiB-background-client.log"
}

step_cli() {
  local out="$1"; shift
  "$spike/Scripts/scripted-cli-run.sh" "$evidence/$out" "$@" || { cat "$evidence/$out"; return 1; }
  cat "$evidence/$out"
}

step_simulator() {
  "$spike/Scripts/test-ios.sh" "$simulator"
}

step_simulator_pairing() {
  "$spike/Scripts/simulator-pairing-run.sh" "$evidence/simulator-pairing-run.log" "$simulator" 127.0.0.1 \
    || { cat "$evidence/simulator-pairing-run.log"; return 1; }
  cat "$evidence/simulator-pairing-run.log"
}

step_simulator_background() {
  "$spike/Scripts/simulator-background-run.sh" "$evidence/simulator-background-run.log" "$simulator" \
    || { cat "$evidence/simulator-background-run.log"; return 1; }
  cat "$evidence/simulator-background-run.log"
}

step_simulator_pairing_entry() {
  "$spike/Scripts/simulator-pairing-entry-run.sh" "$evidence/simulator/pairing-entry.log" "$simulator" \
    || { cat "$evidence/simulator/pairing-entry.log"; return 1; }
  cat "$evidence/simulator/pairing-entry.log"
}

step_simulator_relaunch() {
  "$spike/Scripts/simulator-relaunch-run.sh" "$evidence/simulator" "$simulator" 60 || {
    cat "$evidence"/simulator/relaunch-*.log; return 1; }
  cat "$evidence"/simulator/relaunch-*.log
}

run_step contracts "$SYLVIA_ROOT/Scripts/ci.d/10-contracts.sh"
run_step fixtures-check step_fixtures
run_step trust-guards step_guards
run_step host-transferkit step_host_transferkit
run_step host-sourceservice step_host_sourceservice
run_step captured-payloads step_captured
run_step large-5gib step_large

run_step cli-loopback-ipv4 step_cli cli-run-loopback-ipv4.log --client-host 127.0.0.1
run_step cli-loopback-ipv6 step_cli cli-run-loopback-ipv6.log --client-host ::1 ::1

lan="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ -n "$lan" ]]; then
  run_step cli-lan step_cli cli-run-lan.log --client-host "$lan" "$lan"
else
  not_run_step cli-lan "en0 has no IPv4 address"
fi

# Tailscale: an address in 100.64.0.0/10 on a utun interface, and the MagicDNS name from the Tailscale CLI.
tailscale_ip="$(ifconfig 2>/dev/null | awk '/^utun/ {u=1} /^[a-z]/ && !/^utun/ {u=0} u && $1=="inet" {print $2}' \
  | awk -F. '$1==100 && $2>=64 && $2<=127 {print; exit}')"
tailscale_cli=/Applications/Tailscale.app/Contents/MacOS/Tailscale
magicdns=""
if [[ -n "$tailscale_ip" && -x "$tailscale_cli" ]]; then
  magicdns="$("$tailscale_cli" status --json 2>/dev/null \
    | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))' 2>/dev/null || true)"
fi
if [[ -n "$tailscale_ip" ]]; then
  run_step cli-tailscale-ip step_cli cli-run-tailscale-ip.log --client-host "$tailscale_ip" "$tailscale_ip"
else
  not_run_step cli-tailscale-ip "no Tailscale (100.64.0.0/10) address on a utun interface"
fi
if [[ -n "$magicdns" ]]; then
  # The tailnet name identifies the owner's tailnet; it is replaced in the log.
  tailnet="${magicdns#*.}"
  run_step cli-tailscale-magicdns step_cli cli-run-tailscale-magicdns.log \
    --advertise-host "$magicdns" --client-host "$magicdns" --redact "$tailnet" "$tailscale_ip"
else
  not_run_step cli-tailscale-magicdns "no MagicDNS name (Tailscale CLI not found or not logged in)"
fi

# The Mac identity key from a signed app (data protection keychain). Needs code signing for the team on this
# Mac; when the account cannot sign (for example an unaccepted Program License Agreement), the step is listed
# as not run with that reason, and the report keeps the criterion pending.
echo "== mac-identity-signed"
identity_start=$SECONDS
identity_status=0
"$spike/Scripts/mac-identity-probe-run.sh" "$evidence/keychain-identity-signed.log" > "$logs/mac-identity-signed.log" 2>&1 \
  || identity_status=$?
cat "$evidence/keychain-identity-signed.log" >> "$logs/mac-identity-signed.log" 2>/dev/null || true
case "$identity_status" in
  0) echo "   pass ($((SECONDS - identity_start)) s) - ${logs#"$SYLVIA_ROOT"/}/mac-identity-signed.log" ;;
  2) echo "   NOT RUN: code signing for team $SYLVIA_TEAM_ID is unavailable on this Mac (${evidence#"$SYLVIA_ROOT"/}/keychain-identity-signed.log)"
     not_run+=(mac-identity-signed) ;;
  *) echo "   FAIL ($((SECONDS - identity_start)) s) - ${logs#"$SYLVIA_ROOT"/}/mac-identity-signed.log"
     tail -n 40 "$logs/mac-identity-signed.log" | sed 's/^/   | /'
     failed+=(mac-identity-signed) ;;
esac

run_step simulator step_simulator
run_step simulator-pairing step_simulator_pairing
run_step simulator-background step_simulator_background
run_step simulator-pairing-entry step_simulator_pairing_entry
run_step simulator-relaunch step_simulator_relaunch

echo
if (( ${#not_run[@]} )); then echo "not run on this Mac (see each log for the reason): ${not_run[*]}"; fi
if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all G0.2 transfer steps passed"
