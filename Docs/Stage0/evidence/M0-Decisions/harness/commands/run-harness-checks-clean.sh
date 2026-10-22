#!/bin/bash
# Runs the lock harness's checks alone (Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh: steps 13-15 of
# Scripts/ci.d/71-g05-recovery.sh) from clean, on the current commit, with this job's simulator: the lock against the
# package's, the unit tests on the iOS 26.5 simulator, and the app built for a generic iOS device with automatic
# signing (build only). This is not a run of the drop-in: run-dropin-clean.sh is. It deletes the harness's build
# products and derived data first (Spikes/G05-Recovery/LockHarness/.build) and records the commit, the screen lock
# state (ioreg, read-only) and the load at the start and the end.
#   Docs/Stage0/evidence/M0-Decisions/harness/commands/run-harness-checks-clean.sh <name>
# Logs: Docs/Stage0/evidence/M0-Decisions/harness/<name>/console.log and the step logs beside it.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
out="Docs/Stage0/evidence/M0-Decisions/harness/$name"
source Scripts/lib/env.sh
source "$(dirname "$0")/lock-state.sh"
uncommitted="$(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
rm -rf Spikes/G05-Recovery/LockHarness/.build "$out"
mkdir -p "$out"
console="$out/console.log"
{
  echo "command: Docs/Stage0/evidence/M0-Decisions/harness/commands/run-harness-checks-clean.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files before the run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "deleted before the run: Spikes/G05-Recovery/LockHarness/.build; simulator name Sylvia-M0-dec-harness (iPhone 17, iOS 26.5)"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$console"
G05_LOG_DIR="$root/$out" G05_SIM_NAME=Sylvia-M0-dec-harness Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh >> "$console" 2>&1
status=$?
perl -pi -e 's/\e\[[0-9;]*m//g' "$console"
{
  echo "harness-checks.sh exit: $status"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "git status --porcelain lines after the run: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
} >> "$console"
exit $status
