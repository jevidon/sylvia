#!/bin/bash
# Runs 71-g05-recovery from clean on the current commit with G05_ALLOW_MISSING_CLASS_B=1 (M0 final review, round 2:
# evidence R2-02, clean clone CC2-02 and contracts R2-04). With the Mac's screen locked the drop-in's row-10 guard stops
# it after its host tests; the switch turns that stop into its printed "row 10 evidence missing" warning, so steps 4-12
# (the crash, latency, restore and migration drills, the backup-manifest contract check, the simulator tests and the
# iOS device build) run on the code the M0 final fix changed. Such a run is never evidence for report row 10 (the class-B
# readback on the Mac), which needs the screen unlocked; the drop-in says so itself.
# Deletes Spikes/G05-Recovery/.build and .build/g05-recovery first, so the drop-in builds from clean. Records the commit,
# the lock state (ioreg, read-only), the load at the start and the end, and the drop-in's own console output.
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/ci-71-allow-missing-class-b.sh <log dir> <console log>
# Both paths are taken from the repository root. The drop-in's step logs go to <log dir> (G05_LOG_DIR).
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
logs="$root/$1"; console="$root/$2"
source Scripts/lib/env.sh
lock_state() {
  ioreg -n Root -d1 -a | /usr/bin/python3 -I -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
users = [u for u in d.get("IOConsoleUsers", []) if u.get("kCGSSessionOnConsoleKey")]
print("IOConsoleLocked=%s CGSSessionScreenIsLocked=%s" % (bool(d.get("IOConsoleLocked")), any(u.get("CGSSessionScreenIsLocked", False) for u in users)))'
}
rm -rf Spikes/G05-Recovery/.build .build/g05-recovery "$logs"
mkdir -p "$logs" "$(dirname "$console")"
{
  echo "command: Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/ci-71-allow-missing-class-b.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "Spikes/G05-Recovery/.build and .build/g05-recovery deleted before the run; simulator name Sylvia-M0-final-fix (iPhone 17, iOS 26.5)"
  echo "G05_ALLOW_MISSING_CLASS_B=1; G05_LOG_DIR=$1"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$console"
G05_ALLOW_MISSING_CLASS_B=1 G05_LOG_DIR="$logs" G05_SIM_NAME=Sylvia-M0-final-fix Scripts/ci.sh g05-recovery >> "$console" 2>&1
status=$?
{
  echo "ci.sh exit: $status"
  echo "---- .build/ci-logs/71-g05-recovery.log (the drop-in's console output)"
  cat .build/ci-logs/71-g05-recovery.log
  echo "---- end of the drop-in's console output"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "git status --porcelain lines after the run: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
} >> "$console"
exit $status
