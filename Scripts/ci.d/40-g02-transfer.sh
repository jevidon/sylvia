#!/usr/bin/env bash
# G0.2 transfer (part 1: pairing, Mac source service, contracts, host fault tests; part 2: the iOS background
# transfer client): every automated check.
#
#   Scripts/ci.sh g02-transfer        (or run this file directly)
#
# Results. Every step logs to <results>/ci/<step>.log, and the tests and runs write their evidence under <results>/,
# where <results> is $G02_EVIDENCE_DIR, by default .build/ci-results/g02-transfer, so a routine run does not rewrite
# the committed evidence (M0 verification finding R1-01). To refresh the committed evidence, run
#   G02_EVIDENCE_DIR="$PWD/Docs/Stage0/evidence/G02-Transfer" Scripts/ci.sh g02-transfer
# G02_LOOPBACK_ONLY=1 binds every test server to loopback only (M0 verification finding R1-02; the agents' network
# rule): cli-lan, cli-tailscale-ip, cli-tailscale-magicdns, simulator-ats-device-recipe and the Bonjour browse test of
# simulator-background (a loopback-only source's Bonjour registration is local to the Mac) are listed as not run,
# and the simulator runs get no LAN, .local, Tailscale or MagicDNS address form, so such a run is not evidence for
# the address-form rows or the Bonjour browse row (the gate's own runs, made with the LAN, are).
#
# Steps:
#   contracts             Scripts/ci.d/10-contracts.sh: schemas, fixtures and the OpenAPI document         [host]
#   fixtures-check        the contract fixture generator reproduces the committed fixtures exactly
#   trust-guards          no ATS key in the harness (ATS keys only in the probe variants Config/ATSVariant-*.plist,
#                         NSAllowsArbitraryLoads nowhere), no server-trust credential outside the pinned
#                         answer, no TLS minimum below 1.2 in the spike (Scripts/trust-guards.py, after its
#                         self-test with planted violations under a path that contains /.build/)     [host]
#   package-locks         the XcodeGen projects' committed Package.resolved (iOS, MacIdentityProbe) pin exactly what
#                         their local package's lock pins (TransferKit, SourceService)              [host]
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
#   cli-qr                sylvia-source --qr draws the pairing QR code on its controlling terminal only: on a
#                         pseudo-terminal with standard output redirected, the drawing is on the terminal and not
#                         in the output; without a controlling terminal it is not drawn at all (round 3 gate gap;
#                         the drawing itself is decoded by PairingQRCodeTests in host-sourceservice)  [host]
#   cli-logging-recipe    the device checklist's logging-source command line (tee to the terminal, redacting sed
#                         into source.log) on a pseudo-terminal: the person sees the code, fingerprint and prompt
#                         and answers it; source.log has the request log and no code, link or QR (finding R3-03) [host]
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
#   simulator-ats-device-recipe  Scripts/device-ats-probe.sh (device checklist step 23) run against the simulator:
#                         the ATS probe with inline inputs and no loopback forms, as on a phone (finding R3-06) [simulator]
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
evidence="${G02_EVIDENCE_DIR:-$SYLVIA_ROOT/.build/ci-results/g02-transfer}"
mkdir -p "$evidence"
evidence="$(cd "$evidence" && pwd)"
export G02_EVIDENCE_DIR="$evidence"
logs="$evidence/ci"
mkdir -p "$logs"
loopback_only="${G02_LOOPBACK_ONLY:-0}"
simulator="${SYLVIA_G02_SIMULATOR:-Sylvia-M0-g02-transfer}"
failed=()
not_run=()
# The simulator steps' scripts boot this job's simulator and leave it booted; shut it down when the drop-in ends,
# however it ends (M0 final review CC-05). It is found by its name and never created here.
shutdown_own_simulator() { sylvia_sim_shutdown "$(sylvia_sim_find "$simulator")"; }
trap shutdown_own_simulator EXIT

echo "G0.2 transfer CI drop-in, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
sylvia_check_xcode || true
echo "results: ${evidence#"$SYLVIA_ROOT"/}; loopback only: $([[ "$loopback_only" == 1 ]] && echo yes || echo no)"
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
  xcrun swift test --force-resolved-versions --package-path "$spike/$package" "$@" 2>&1
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
# rogue-host and wrong-pin tests; these catch configuration that would weaken it. Spikes/G02-Transfer/Scripts/
# trust-guards.py reads the spike's files by their paths relative to the spike, skipping build directories by name, so
# the guards see the same files wherever the checkout lies (M0 final review CC-01: the earlier grep dropped every hit
# whose absolute path contained /.build/, so in a clone under .build/scratch/ they printed ok lines having seen
# nothing). Its self-test runs first, from a copy under a path that contains /.build/, with one planted violation per
# guard.
step_guards() {
  local scratch="$SYLVIA_ROOT/.build/scratch/g02-trust-guards"
  rm -rf "$scratch"
  mkdir -p "$scratch"
  /usr/bin/python3 -I "$spike/Scripts/trust-guards.py" --self-test "$spike" "$scratch" || { rm -rf "$scratch"; return 1; }
  rm -rf "$scratch"
  /usr/bin/python3 -I "$spike/Scripts/trust-guards.py" "$spike"
}

# The two XcodeGen projects resolve their local packages themselves, so each commits its own lock (ADR-0002); it must
# pin exactly what its package's lock pins (one version per package across the repository; M0 integration open item:
# without a lock the probe's transitive packages followed swift-nio's version ranges).
step_package_locks() {
  echo "environment: host; static comparison of the committed Package.resolved files"
  /usr/bin/python3 -I - "$spike" <<'PY'
import json, os, sys

spike = sys.argv[1]
pairs = [("MacIdentityProbe/Package.resolved", "SourceService/Package.resolved"), ("iOS/Package.resolved", "TransferKit/Package.resolved")]


def pins(path):
    with open(os.path.join(spike, path)) as handle:
        data = json.load(handle)
    return {pin["identity"]: (pin["location"], pin["state"].get("revision"), pin["state"].get("version")) for pin in data["pins"]}


failed = False
for project, package in pairs:
    mine, theirs = pins(project), pins(package)
    if mine == theirs:
        print("ok: %s pins exactly what %s pins: %s" % (project, package, ", ".join("%s %s" % (k, v[2]) for k, v in sorted(mine.items()))))
    else:
        failed = True
        print("MISMATCH: %s does not pin what %s pins" % (project, package))
        for name in sorted(set(mine) | set(theirs)):
            if mine.get(name) != theirs.get(name):
                print("  %s: %s vs %s" % (name, mine.get(name), theirs.get(name)))
sys.exit(1 if failed else 0)
PY
}

step_host_transferkit() {
  echo "environment: host (macOS $(sw_vers -productVersion)), swift test"
  checked_swift_test "$logs/host-transferkit" TransferKit
}

# Payloads the host-sourceservice tests write to $evidence/captured/ (one per file, all required).
captured_expected=(
  capabilities catalog-page device-inbox-page error-precondition-failed error-rate-limited error-unsupported-version
  pair-request pair-response pairing-payload receipt-ack-catalog-download receipt-ack-duplicate receipt-downloaded
  receipt-imported transfer-manifest
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
  # The tests write their own logs, also when an expectation fails; logs from an earlier run must never be taken for
  # this run's, and a failing run's logs are kept here (round 3: the first clean run's were overwritten and lost).
  local name status=0
  rm -f "$evidence/faults/large-5GiB-transfer.log" "$evidence/faults/large-5GiB-background-client.log"
  echo "load before: $(uptime)"
  SYLVIA_G02_LARGE_FILE="$file" SYLVIA_G02_LARGE_SHA256="$sha" \
    checked_swift_test "$logs/large-5gib" SourceService --filter LargeTransferTests || status=1
  echo "load after: $(uptime)"
  for name in large-5GiB-transfer large-5GiB-background-client; do
    echo "--- faults/$name.log (written by the test in this run)"
    cat "$evidence/faults/$name.log" 2>/dev/null || echo "(not written)"
  done
  (( status == 0 )) || return 1
  grep -q 'fiveGiBTransferSurvivesInterruptionsWithBoundedMemory() passed' "$logs/large-5gib.log" \
    || { echo "CHECK FAILED: the 5 GiB test did not run and pass"; return 1; }
  grep -q 'fiveGiBThroughTheBackgroundClientWithARelaunch() passed' "$logs/large-5gib.log" \
    || { echo "CHECK FAILED: the 5 GiB background-client test did not run and pass"; return 1; }
}

step_cli() {
  local out="$1"; shift
  "$spike/Scripts/scripted-cli-run.sh" "$evidence/$out" "$@" || { cat "$evidence/$out"; return 1; }
  cat "$evidence/$out"
}

step_cli_qr() {
  echo "environment: host (macOS $(sw_vers -productVersion)); sylvia-source built from this checkout"
  local package="$spike/SourceService" bin
  xcrun swift build --force-resolved-versions --package-path "$package" --product sylvia-source || return 1
  bin="$(xcrun swift build --force-resolved-versions --package-path "$package" --show-bin-path)/sylvia-source"
  /usr/bin/python3 "$spike/Scripts/qr-terminal-check.py" "$bin" "$SYLVIA_ROOT/.build/scratch/g02-qr-check" "$evidence/cli-qr-terminal.log" || return 1
}

step_cli_logging_recipe() {
  echo "environment: host (macOS $(sw_vers -productVersion)); sylvia-test-source and sylvia-fetch built from this checkout"
  local package="$spike/SourceService" bin
  xcrun swift build --force-resolved-versions --package-path "$package" --product sylvia-test-source || return 1
  xcrun swift build --force-resolved-versions --package-path "$package" --product sylvia-fetch || return 1
  bin="$(xcrun swift build --force-resolved-versions --package-path "$package" --show-bin-path)"
  /usr/bin/python3 "$spike/Scripts/logging-source-recipe-check.py" "$bin/sylvia-test-source" "$bin/sylvia-fetch" \
    "$SYLVIA_ROOT/.build/scratch/g02-recipe-check" "$evidence/cli-logging-source-recipe.log" || return 1
}

step_simulator_ats_device_recipe() {
  local udid
  udid="$(sylvia_sim_udid "$simulator")"
  sylvia_sim_boot "$udid"
  echo "environment: simulator $simulator ($udid); the device recipe of checklist step 23, variant none"
  "$spike/Scripts/device-ats-probe.sh" "$evidence/ats/device-recipe-on-simulator.log" none "id=$udid" \
    || { cat "$evidence/ats/device-recipe-on-simulator.log"; return 1; }
  cat "$evidence/ats/device-recipe-on-simulator.log"
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
run_step package-locks step_package_locks
run_step host-transferkit step_host_transferkit
run_step host-sourceservice step_host_sourceservice
run_step captured-payloads step_captured
run_step large-5gib step_large

run_step cli-loopback-ipv4 step_cli cli-run-loopback-ipv4.log --client-host 127.0.0.1
run_step cli-loopback-ipv6 step_cli cli-run-loopback-ipv6.log --client-host ::1 ::1

loopback_reason="G02_LOOPBACK_ONLY=1: every test server binds to loopback only"
lan="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ "$loopback_only" == 1 ]]; then
  not_run_step cli-lan "$loopback_reason"
elif [[ -n "$lan" ]]; then
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
if [[ "$loopback_only" == 1 ]]; then
  not_run_step cli-tailscale-ip "$loopback_reason"
elif [[ -n "$tailscale_ip" ]]; then
  run_step cli-tailscale-ip step_cli cli-run-tailscale-ip.log --client-host "$tailscale_ip" "$tailscale_ip"
else
  not_run_step cli-tailscale-ip "no Tailscale (100.64.0.0/10) address on a utun interface"
fi
if [[ "$loopback_only" == 1 ]]; then
  not_run_step cli-tailscale-magicdns "$loopback_reason"
elif [[ -n "$magicdns" ]]; then
  # The tailnet name identifies the owner's tailnet; it is replaced in the log.
  tailnet="${magicdns#*.}"
  run_step cli-tailscale-magicdns step_cli cli-run-tailscale-magicdns.log \
    --advertise-host "$magicdns" --client-host "$magicdns" --redact "$tailnet" "$tailscale_ip"
else
  not_run_step cli-tailscale-magicdns "no MagicDNS name (Tailscale CLI not found or not logged in)"
fi

run_step cli-qr step_cli_qr
run_step cli-logging-recipe step_cli_logging_recipe

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
if [[ "$loopback_only" == 1 ]]; then
  # simulator-background-run.sh leaves the Bonjour browse test out: a loopback-only source advertises to this Mac only.
  echo "   NOT RUN within simulator-background: bonjourBrowseFindsResolvesAndPinsTheSource ($loopback_reason; the Bonjour registration is then local to this Mac, which the simulator does not browse)"
  not_run+=("simulator-bonjour-browse")
fi
run_step simulator-pairing-entry step_simulator_pairing_entry
if [[ "$loopback_only" == 1 ]]; then
  not_run_step simulator-ats-device-recipe "$loopback_reason (the device recipe probes the LAN address)"
else
  run_step simulator-ats-device-recipe step_simulator_ats_device_recipe
fi
run_step simulator-relaunch step_simulator_relaunch

echo
if (( ${#not_run[@]} )); then echo "not run on this Mac (see each log for the reason): ${not_run[*]}"; fi
if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all G0.2 transfer steps passed"
