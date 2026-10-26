#!/bin/bash
# Waits, read-only, for the build Mac's screen to be unlocked: reads the lock state with ioreg (lock-state.sh of the
# M0 decisions round) every <seconds> for at most <readings> readings, appends each reading to <log>, and exits 0 at
# the first unlocked reading (1 if none). No agent unlocks the Mac: the class-B steps of G0.5 recovery (its drop-in's
# row-10 guard and the class-B tests) wait for a person to unlock it.
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/wait-for-unlock.sh <log> <readings> <seconds>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
source "$root/Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh"
log="$1"; readings="$2"; pause="$3"
for ((i = 0; i < readings; i++)); do
  state="$(lock_state)"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $state" >> "$log"
  [[ "$state" == unlocked* ]] && exit 0
  (( i + 1 < readings )) && sleep "$pause"
done
exit 1
