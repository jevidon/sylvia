#!/usr/bin/env bash
# Pairs the iOS simulator with the command-line Mac source on this Mac and downloads a file through the
# shared TransferKit code (foreground URLSession), with pinning, Keychain token storage and part
# verification on iOS. Environment: simulator (the named device) talking to sylvia-source on the host.
#
#   Spikes/G02-Transfer/Scripts/simulator-pairing-run.sh LOG [simulator-name] [bind-address]
#
# The simulator shares the Mac's network stack, so this exercises the iOS TLS stack, ATS and the
# Keychain, not Wi-Fi between two devices. The pairing code is written to a file readable only by this
# user, passed to the test by path, and deleted afterwards; lines containing a code are redacted in LOG.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

log="$1"
name="${2:-Sylvia-M0-g02-transfer}"
bind="${3:-127.0.0.1}"
spike="$SYLVIA_ROOT/Spikes/G02-Transfer"
udid="$(sylvia_sim_udid "$name")"
sylvia_sim_boot "$udid"

source_pkg="$spike/SourceService"
xcrun swift build --package-path "$source_pkg" --product sylvia-source >/dev/null
bin="$(xcrun swift build --package-path "$source_pkg" --show-bin-path)"

work="$SYLVIA_ROOT/.build/scratch/g02-sim-run"
rm -rf "$work"
mkdir -p "$work/library" "$work/state"
# The LibriVox M4B (138 MB, public domain) from the fixture cache: 9 parts at the default 16 MiB.
"$SYLVIA_ROOT/Scripts/fixtures/fetch.sh" m4b >/dev/null
cp -c "$SYLVIA_FIXTURE_CACHE/downloads/MeditationsMarcusAurelius_librivox.m4b" "$work/library/meditations-librivox.m4b"
title="meditations-librivox"
expected="$(openssl dgst -sha256 -r "$work/library/$title.m4b" | cut -d' ' -f1)"

: > "$log"
redact() { sed -E 's/(SYLVIA1-|sylvia:\/\/pair\/v1#)[A-Za-z0-9_-]+/[pairing code redacted]/g'; }
note() { printf '%s\n' "$*" | redact >> "$log"; }
fail() { note "FAIL: $*"; echo "FAIL: $*" >&2; exit 1; }
note "environment: simulator $name ($udid), runtime $SYLVIA_SIM_RUNTIME, device type $SYLVIA_SIM_DEVICE_TYPE;"
note "  sylvia-source on the host (macOS $(sw_vers -productVersion)), bound to $bind; file MeditationsMarcusAurelius_librivox.m4b from the fixture cache (sha256 $expected)"

mkfifo "$work/to-source" "$work/from-source"
"$bin/sylvia-source" --root "$work/library" --state "$work/state" --ephemeral-identity --name "Simulator run Mac" \
  --bind "$bind" < "$work/to-source" > "$work/from-source" 2>&1 &
src_pid=$!
exec 3> "$work/to-source"
exec 4< "$work/from-source"
trap 'kill "$src_pid" 2>/dev/null || true; rm -f "$work/code"' EXIT

expect_line() {
  local pattern="$1" line
  while IFS= read -r -t 300 line <&4; do
    note "source> $line"
    if [[ "$line" =~ $pattern ]]; then printf '%s\n' "$line"; return 0; fi
  done
  fail "source never printed /$pattern/"
}
send() { note "script> $*"; printf '%s\n' "$*" >&3; }

code_line="$(expect_line '^pairing code: ')"
umask 077
printf '%s\n' "${code_line#pairing code: }" > "$work/code"
expect_line '^ready$' >/dev/null

sylvia_generate "$spike/iOS"
note "script> xcodebuild test -only-testing:G02TransferHostedTests/SimulatorTransferTests (destination id=$udid)"
(cd "$spike/iOS" && TEST_RUNNER_G02_PAIRING_CODE_FILE="$work/code" TEST_RUNNER_G02_TITLE="$title" \
  TEST_RUNNER_G02_EXPECTED_SHA256="$expected" xcodebuild test \
  -project G02Transfer.xcodeproj -scheme G02TransferHarness -destination "id=$udid" \
  -derivedDataPath "$spike/iOS/.build/DerivedData" -disableAutomaticPackageResolution -skipPackagePluginValidation \
  -only-testing:G02TransferHostedTests/SimulatorTransferTests > "$work/xcodebuild.log" 2>&1) &
test_pid=$!

# The Mac user's approval: the script answers the terminal prompt once.
expect_line '^approve\? \[y/N\]$' >/dev/null
send y
expect_line '^approved ' >/dev/null
test_status=0
wait "$test_pid" || test_status=$?
rm -f "$work/code"
grep -E 'G02-SIM:|✔|✘|➜ Test|\*\* TEST|error:' "$work/xcodebuild.log" | redact >> "$log" || true
send devices
expect_line '^end$' >/dev/null
send quit
expect_line '^stopped$' >/dev/null
wait "$src_pid" || true
exec 3>&- 4<&-
trap - EXIT

(( test_status == 0 )) || fail "xcodebuild test exited $test_status (full log: $work/xcodebuild.log)"
grep -q 'pairsPinsStoresTheTokenAndDownloadsVerifiedBytes() passed' "$work/xcodebuild.log" \
  || fail "the simulator test did not run and pass"
if grep -Eq '➜ Test .* skipped|✘' "$work/xcodebuild.log"; then fail "a test was skipped or failed"; fi
grep -qE 'SYLVIA1-|sylvia://pair/v1#' "$log" && fail "a pairing code reached the log"
note "check: exactly one approval prompt (the forged-pin attempt never reached the Mac); no pairing code in this log"
[[ "$(grep -c '^source> approve? \[y/N\]$' "$log")" == 1 ]] || fail "expected exactly one approval prompt"
note "RESULT: PASS"
rm -rf "$work"
