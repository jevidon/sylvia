#!/usr/bin/env bash
# Scripted end-to-end run of the command-line Mac source (sylvia-source) with a command-line client
# (sylvia-fetch) standing in for the phone. Environment: host (macOS), real TLS between two processes.
#
#   Spikes/G02-Transfer/Scripts/scripted-cli-run.sh LOG [--advertise-host NAME] [--client-host HOST]
#                                                   [--redact TEXT] [EXTRA_BIND_ADDRESS ...]
#
# --advertise-host NAME adds a host name (for example a Tailscale MagicDNS name) to the pairing payload;
# --client-host HOST makes both clients use only the payload endpoints with that host, so one address
# form is exercised end to end; --redact TEXT replaces TEXT (for example the tailnet name) in LOG.
#
# The source shares a temporary folder holding the committed Walden EPUB and the two LibriVox excerpts
# (as a group). The run: pair client A from the printed code (the script answers the terminal prompt
# with "y"), download Walden by title and compare its SHA-256 with the original; check that reusing the
# same code fails without a prompt; issue a new code, pair client B, queue the excerpt group for B with
# "send", let B download it from its inbox and post receipts; check the queue shows the three
# acknowledgements; revoke A; quit.
#
# EXTRA_BIND_ADDRESS (for example the Mac's LAN or Tailscale address) is bound in addition to 127.0.0.1
# and listed first in the pairing payload, so the clients connect through it. From the same Mac this
# exercises address handling, not the network path between two devices.
#
# Pairing codes contain the invitation secret: every line containing one is replaced with
# "[pairing code redacted]" before it reaches LOG.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"

log="$1"; shift
advertise_hosts=()
client_host=""
redactions=()
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --advertise-host) advertise_hosts+=("$2"); shift 2 ;;
    --client-host) client_host="$2"; shift 2 ;;
    --redact) redactions+=("$2"); shift 2 ;;
    *) echo "unknown option $1" >&2; exit 64 ;;
  esac
done
extra_binds=("$@")
client_args=()
[[ -n "$client_host" ]] && client_args=(--only-host "$client_host")
spike="$SYLVIA_ROOT/Spikes/G02-Transfer/SourceService"
bin="$(xcrun swift build --package-path "$spike" --show-bin-path)"
xcrun swift build --package-path "$spike" --product sylvia-source >/dev/null
xcrun swift build --package-path "$spike" --product sylvia-fetch >/dev/null

work="$SYLVIA_ROOT/.build/scratch/g02-cli-run"
rm -rf "$work"
mkdir -p "$work/library/Meditations excerpts" "$work/state" "$work/outA" "$work/outB"
cp "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" "$work/library/walden.epub"
cp "$SYLVIA_ROOT/Fixtures/audio/meditations-01-first180s.mp3" "$work/library/Meditations excerpts/01.mp3"
cp "$SYLVIA_ROOT/Fixtures/audio/meditations-02-first150s.mp3" "$work/library/Meditations excerpts/02.mp3"

: > "$log"
redact() {
  local text
  text="$(sed -E 's/(SYLVIA1-|sylvia:\/\/pair\/v1#)[A-Za-z0-9_-]+/[pairing code redacted]/g')"
  for secret in "${redactions[@]:-}"; do
    [[ -n "$secret" ]] && text="${text//"$secret"/[redacted]}"
  done
  printf '%s\n' "$text"
}
note() { printf '%s\n' "$*" | redact >> "$log"; }
fail() { note "FAIL: $*"; echo "FAIL: $*" >&2; exit 1; }

note "environment: host (macOS $(sw_vers -productVersion) $(sw_vers -buildVersion)); sylvia-source and sylvia-fetch as separate processes"
note "binds: ${extra_binds[*]:-} 127.0.0.1; advertised host names: ${advertise_hosts[*]:-none}; clients use: ${client_host:-every payload endpoint, in order}"

args=(--root "$work/library" --state "$work/state" --ephemeral-identity --name "Scripted Mac" --part-size-mib 1)
for address in "${extra_binds[@]:-}"; do [[ -n "$address" ]] && args+=(--bind "$address"); done
for host in "${advertise_hosts[@]:-}"; do [[ -n "$host" ]] && args+=(--advertise-host "$host"); done
args+=(--bind 127.0.0.1)

# The source talks to this script through two FIFOs (macOS ships bash 3.2, which has no coproc).
mkfifo "$work/to-source" "$work/from-source"
"$bin/sylvia-source" "${args[@]}" < "$work/to-source" > "$work/from-source" 2>&1 &
src_pid=$!
exec 3> "$work/to-source"
exec 4< "$work/from-source"
trap 'kill "$src_pid" 2>/dev/null || true' EXIT

# Reads source lines (logging them, redacted) until one matches the pattern; prints that line.
expect_line() {
  local pattern="$1" line
  while IFS= read -r -t 60 line <&4; do
    note "source> $line"
    if [[ "$line" =~ $pattern ]]; then printf '%s\n' "$line"; return 0; fi
  done
  fail "source never printed /$pattern/"
}
send() { note "script> $*"; printf '%s\n' "$*" >&3; }

code_line="$(expect_line '^pairing code: ')"
code_a="${code_line#pairing code: }"
expect_line '^ready$' >/dev/null

# Client A: catalog download by title.
printf '%s\n' "$code_a" | "$bin/sylvia-fetch" ${client_args[@]+"${client_args[@]}"} --out "$work/outA" --device-name "Scripted client A" --title walden > "$work/fetchA.log" 2>&1 &
fetch_a=$!
expect_line '^approve\? \[y/N\]$' >/dev/null
send y
approved_a="$(expect_line '^approved ')"
device_a="${approved_a#approved }"
wait "$fetch_a" || { redact < "$work/fetchA.log" >> "$log"; fail "client A failed"; }
while IFS= read -r line; do note "clientA> $line"; done < "$work/fetchA.log"
expected_walden="$(openssl dgst -sha256 -r "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" | cut -d' ' -f1)"
grep -q "verified sha256 $expected_walden " "$work/fetchA.log" || fail "client A's verified digest differs from the original's ($expected_walden)"
cmp -s "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" "$work/outA/"0-* || fail "client A's copy differs from the original"
note "check: client A's file is byte-identical to Fixtures/epub/se-walden.epub (sha256 $expected_walden)"
if [[ -n "$client_host" ]]; then
  grep -qF -e "connected via $client_host:" -e "connected via [$client_host]:" "$work/fetchA.log" \
    || fail "client A did not connect through $client_host"
  note "check: client A paired and downloaded through the requested endpoint host only"
fi

# The same code again: refused by the Mac without asking the user.
if printf '%s\n' "$code_a" | "$bin/sylvia-fetch" ${client_args[@]+"${client_args[@]}"} --out "$work/outA2" --device-name "Replay" --title walden > "$work/replay.log" 2>&1; then
  fail "a used invitation paired again"
fi
while IFS= read -r line; do note "replay> $line"; done < "$work/replay.log"
grep -q 'invitation_used' "$work/replay.log" || fail "reused invitation did not fail with invitation_used"
note "check: reused invitation refused with invitation_used; no approval prompt was shown"

# Client B: pairs with a new code, then waits for its inbox.
send invite
code_line="$(expect_line '^pairing code: ')"
code_b="${code_line#pairing code: }"
printf '%s\n' "$code_b" | "$bin/sylvia-fetch" ${client_args[@]+"${client_args[@]}"} --out "$work/outB" --device-name "Scripted client B" --inbox 60 > "$work/fetchB.log" 2>&1 &
fetch_b=$!
expect_line '^approve\? \[y/N\]$' >/dev/null
send y
approved_b="$(expect_line '^approved ')"
device_b="${approved_b#approved }"

send items
group_line="$(expect_line '^item .* Meditations excerpts$')"
expect_line '^end$' >/dev/null
group_id="$(awk '{print $2}' <<< "$group_line")"
send send "$group_id" "$device_b"
expect_line '^queued ' >/dev/null
wait "$fetch_b" || { redact < "$work/fetchB.log" >> "$log"; fail "client B failed"; }
while IFS= read -r line; do note "clientB> $line"; done < "$work/fetchB.log"
for n in 01 02; do
  original="$work/library/Meditations excerpts/$n.mp3"
  digest="$(openssl dgst -sha256 -r "$original" | cut -d' ' -f1)"
  grep -q "verified sha256 $digest " "$work/fetchB.log" || fail "client B did not verify excerpt $n ($digest)"
done
cmp -s "$work/library/Meditations excerpts/01.mp3" "$work/outB/"0-* || fail "excerpt 01 differs"
cmp -s "$work/library/Meditations excerpts/02.mp3" "$work/outB/"1-* || fail "excerpt 02 differs"
note "check: client B received both group members byte-identical, in order"

send queue
entry_line="$(expect_line '^entry ')"
expect_line '^end$' >/dev/null
[[ "$entry_line" == *"state imported_into_sylvia"* ]] || fail "queue entry did not reach imported_into_sylvia: $entry_line"
note "check: queue entry passed queued_on_mac -> observed_by_phone -> downloaded_to_phone -> imported_into_sylvia"

send revoke "$device_a"
expect_line "^revoked $device_a\$" >/dev/null
send devices
expect_line '^end$' >/dev/null
send quit
expect_line '^stopped$' >/dev/null
wait "$src_pid" || true
exec 3>&- 4<&-
trap - EXIT

# The original folder was never modified.
[[ "$(ls "$work/library")" == $'Meditations excerpts\nwalden.epub' ]] || fail "source folder changed"
cmp -s "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" "$work/library/walden.epub" || fail "source file changed"
grep -qE 'SYLVIA1-|sylvia://pair/v1#' "$log" && fail "a pairing code reached the log"
note "check: source folder unchanged; no pairing code in this log"
note "RESULT: PASS"
rm -rf "$work"
