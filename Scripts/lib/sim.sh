# Simulator helpers. Source after env.sh.
#
# Every agent or job uses its own named simulator so parallel runs never share a device:
#   UDID="$(sylvia_sim_udid Sylvia-G04-Audio)"
#   sylvia_sim_boot "$UDID"
#   xcodebuild ... -destination "id=$UDID"

# Prints the UDID of the named simulator on the runtime, or nothing if there is none; never creates one.
# Args: name [runtime-id]
sylvia_sim_find() {
  local name="$1"
  local runtime="${2:-$SYLVIA_SIM_RUNTIME}"
  xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
devices = json.load(sys.stdin)["devices"].get(runtime, [])
for d in devices:
    if d["name"] == name and d.get("isAvailable", True):
        print(d["udid"]); break
' "$name" "$runtime"
}

# Prints the UDID of the named simulator, creating it if needed.
# Args: name [device-type-id] [runtime-id]
sylvia_sim_udid() {
  local name="$1"
  local devtype="${2:-$SYLVIA_SIM_DEVICE_TYPE}"
  local runtime="${3:-$SYLVIA_SIM_RUNTIME}"
  local udid
  udid="$(sylvia_sim_find "$name" "$runtime")"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$name" "$devtype" "$runtime")"
  fi
  echo "$udid"
}

# Shuts the given simulators down, each one only if it is booted; never boots, erases or deletes one. A job calls it
# for its own simulators when it ends (an EXIT trap), so an idle booted simulator does not go on loading the shared
# Mac while other jobs measure timing (M0 final review CC-05; G0.4 review R4-04). Empty arguments are skipped.
sylvia_sim_shutdown() {
  local udid
  for udid in "$@"; do
    [[ -n "$udid" ]] || continue
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  done
}

# Boots the simulator and waits until it is ready.
sylvia_sim_boot() {
  local udid="$1"
  xcrun simctl bootstatus "$udid" -b >/dev/null
}

# Shuts down and deletes the named simulator (only ones you created).
sylvia_sim_delete() {
  local udid
  udid="$(sylvia_sim_udid "$1" "${2:-$SYLVIA_SIM_DEVICE_TYPE}" "${3:-$SYLVIA_SIM_RUNTIME}")"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid"
}
