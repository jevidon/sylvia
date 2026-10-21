#!/bin/bash
# Re-runs 71-g05-recovery alone in the clone of the M0 final fix's complete run, after deleting that spike's build
# products there, so the drop-in builds from clean: the complete run stopped at the drop-in's row-10 guard because the
# Mac's screen had locked and the class-B protection tests skip while it is locked. Records the lock state (ioreg,
# read-only) before and after; the drop-in itself checks that the class-B evidence lines are present.
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/ci-71-rerun.sh <clone> <log>
set -u
clone="$1"; log="$2"
cd "$clone" || exit 1
source Scripts/lib/env.sh
lock_state() {
  ioreg -n Root -d1 -a | /usr/bin/python3 -I -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
users = [u for u in d.get("IOConsoleUsers", []) if u.get("kCGSSessionOnConsoleKey")]
print("IOConsoleLocked=%s CGSSessionScreenIsLocked=%s" % (bool(d.get("IOConsoleLocked")), any(u.get("CGSSessionScreenIsLocked", False) for u in users)))'
}
rm -rf Spikes/G05-Recovery/.build
{
  echo "clone: $clone at $(git rev-parse HEAD); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "Spikes/G05-Recovery/.build deleted before the run; simulator name Sylvia-M0-final-fix"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$log"
G05_SIM_NAME=Sylvia-M0-final-fix Scripts/ci.sh g05-recovery >> "$log" 2>&1
status=$?
{
  echo "ci.sh exit: $status"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "git status --porcelain lines after the run: $(git status --porcelain | wc -l | tr -d ' ')"
} >> "$log"
exit $status
