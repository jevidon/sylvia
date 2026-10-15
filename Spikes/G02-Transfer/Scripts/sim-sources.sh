# Helpers for the G0.2 part 2 simulator runs: start sylvia-test-source processes and plain-HTTP controls
# on this Mac. Source after Scripts/lib/env.sh. Every process started here is killed by g02_stop_all.
#
#   g02_build_test_source            build sylvia-test-source; sets G02_TEST_SOURCE
#   g02_network_facts                sets G02_LAN_IP, G02_TAILSCALE_IP, G02_MAGICDNS, G02_TAILNET, G02_LOCAL_HOSTNAME
#                                    (all empty when G02_LOOPBACK_ONLY=1)
#   g02_start_source NAME WORK FILES-SPEC -- [sylvia-test-source options]
#                                    FILES-SPEC is "dest=source,dest=source" (copied with clonefile); waits for
#                                    WORK/NAME/ready.json; codes in WORK/NAME/codes (mode 0600); output WORK/NAME/out.log
#   g02_start_cleartext ADDRESS WORK starts a plain-HTTP control server bound to ADDRESS; sets G02_CLEARTEXT_PORT
#                                    (call it in this shell, not in "$(...)", so g02_stop_all can kill it)
#   g02_stop_all

G02_PIDS=()

g02_build_test_source() {
  local package="$SYLVIA_ROOT/Spikes/G02-Transfer/SourceService"
  xcrun swift build --force-resolved-versions --package-path "$package" --product sylvia-test-source >/dev/null || return 1
  G02_TEST_SOURCE="$(xcrun swift build --force-resolved-versions --package-path "$package" --show-bin-path)/sylvia-test-source"
}

g02_network_facts() {
  G02_LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
  G02_LOCAL_HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || true)"
  [[ -n "$G02_LOCAL_HOSTNAME" ]] && G02_LOCAL_HOSTNAME="$G02_LOCAL_HOSTNAME.local"
  G02_TAILSCALE_IP="$(ifconfig 2>/dev/null | awk '/^utun/ {u=1} /^[a-z]/ && !/^utun/ {u=0} u && $1=="inet" {print $2}' \
    | awk -F. '$1==100 && $2>=64 && $2<=127 {print; exit}')"
  G02_MAGICDNS=""
  G02_TAILNET=""
  local cli=/Applications/Tailscale.app/Contents/MacOS/Tailscale
  if [[ -n "$G02_TAILSCALE_IP" && -x "$cli" ]]; then
    G02_MAGICDNS="$("$cli" status --json 2>/dev/null \
      | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))' 2>/dev/null || true)"
    [[ -n "$G02_MAGICDNS" ]] && G02_TAILNET="${G02_MAGICDNS#*.}"
  fi
  # G02_LOOPBACK_ONLY=1: no LAN, .local, Tailscale or MagicDNS address form, so every server binds to loopback only.
  if [[ "${G02_LOOPBACK_ONLY:-0}" == 1 ]]; then
    G02_LAN_IP=""; G02_LOCAL_HOSTNAME=""; G02_TAILSCALE_IP=""; G02_MAGICDNS=""; G02_TAILNET=""
  fi
}

g02_start_source() {
  local name="$1" work="$2" files="$3"
  shift 3
  [[ "${1:-}" == "--" ]] && shift
  local dir="$work/$name"
  rm -rf "$dir"
  mkdir -p "$dir/library" "$dir/state"
  local spec dest src
  IFS=',' read -r -a spec <<< "$files"
  for entry in "${spec[@]}"; do
    dest="${entry%%=*}"
    src="${entry#*=}"
    cp -c "$src" "$dir/library/$dest" 2>/dev/null || cp "$src" "$dir/library/$dest"
  done
  "$G02_TEST_SOURCE" --root "$dir/library" --state "$dir/state" --ephemeral-identity --name "G02 $name source" \
    --test-auto-approve --test-code-file "$dir/codes" --test-ready-file "$dir/ready.json" --test-log-requests \
    --test-serve-until-killed "$@" > "$dir/out.log" 2>&1 < /dev/null &
  G02_PIDS+=($!)
  local waited=0
  while [[ ! -s "$dir/ready.json" ]]; do
    sleep 0.2
    waited=$((waited + 1))
    if (( waited > 600 )) || ! kill -0 "${G02_PIDS[${#G02_PIDS[@]}-1]}" 2>/dev/null; then
      echo "source $name did not become ready:" >&2
      cat "$dir/out.log" >&2
      return 1
    fi
  done
}

# Sets G02_CLEARTEXT_PORT. Call it directly, never in a command substitution: a subshell would keep the
# server's PID out of G02_PIDS and g02_stop_all would leave the listener running (review finding R1-03).
g02_start_cleartext() {
  local address="$1" work="$2"
  local port_file
  G02_CLEARTEXT_PORT=""
  port_file="$work/cleartext-$(echo "$address" | tr ':.' '__').port"
  rm -f "$port_file"
  /usr/bin/python3 "$SYLVIA_ROOT/Spikes/G02-Transfer/Scripts/cleartext-server.py" "$address" "$port_file" \
    >> "$work/cleartext.log" 2>&1 &
  G02_PIDS+=($!)
  local waited=0
  while [[ ! -s "$port_file" ]]; do
    sleep 0.1
    waited=$((waited + 1))
    (( waited > 100 )) && { echo "cleartext server on $address did not start" >&2; return 1; }
  done
  G02_CLEARTEXT_PORT="$(cat "$port_file")"
}

g02_stop_all() {
  local pid
  for pid in "${G02_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  for pid in "${G02_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
  done
  G02_PIDS=()
}

# Replaces the tailnet name (it identifies the owner's tailnet) in evidence files.
g02_redact() {
  local file
  for file in "$@"; do
    [[ -f "$file" && -n "${G02_TAILNET:-}" ]] || continue
    sed -i '' "s/${G02_TAILNET//./\\.}/[redacted]/g" "$file"
  done
}
