#!/bin/bash
# The build Mac's screen lock state, read-only with ioreg (IOConsoleLocked, CGSSessionScreenIsLocked), as one line.
# Sourced by the other commands here; run alone with a count and an interval it appends one line per reading to a log:
#   Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh [<log> <readings> <seconds between them>]
# G0.5 recovery's class-B protection tests skip while the screen is locked, and the drop-in then stops at its row-10
# guard; no agent unlocks the Mac, so a run that needs it waits for a reading that shows it unlocked.
lock_state() {
  ioreg -n Root -d1 -a | /usr/bin/python3 -I -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
users = [u for u in d.get("IOConsoleUsers", []) if u.get("kCGSSessionOnConsoleKey")]
locked = bool(d.get("IOConsoleLocked")) or any(u.get("CGSSessionScreenIsLocked", False) for u in users)
print("%s IOConsoleLocked=%s CGSSessionScreenIsLocked=%s" % ("locked" if locked else "unlocked", bool(d.get("IOConsoleLocked")),
      any(u.get("CGSSessionScreenIsLocked", False) for u in users)))'
}

if [[ "${BASH_SOURCE[0]}" == "$0" && $# -eq 3 ]]; then
  log="$1"; readings="$2"; pause="$3"
  for ((i = 0; i < readings; i++)); do
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $(lock_state)" >> "$log"
    (( i + 1 < readings )) && sleep "$pause"
  done
fi
