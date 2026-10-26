#!/bin/bash
# The lock harness's checks alone (Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh: the drop-in's steps 13-15,
# which it says is not a run of the drop-in when run alone), with this job's simulator and a log folder of its own, and
# the context: commit, screen lock state (ioreg, read only) and load at the start and the end. Used to repeat step 14
# once after its quiet-tone test failed. The harness plays its tone at the test volume 0.01 (its configuration); this
# command changes nothing on the Mac's audio.
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-harness-checks.sh <name>
# Logs: Docs/Stage0/evidence/M0-DeviceFixes/recovery/<name>/console.log and the harness's logs in <name>/logs/.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
out="$root/Docs/Stage0/evidence/M0-DeviceFixes/recovery/$name"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
rm -rf "$out"
mkdir -p "$out/logs"
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-harness-checks.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$out/console.log"
G05_LOG_DIR="$out/logs" G05_SIM_NAME=Sylvia-M0-devfix-recovery Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh >> "$out/console.log" 2>&1
status=$?
{
  echo "harness-checks.sh exit: $status"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$out/console.log"
exit $status
