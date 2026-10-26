#!/bin/bash
# G0.5 recovery's host tests (xcrun swift test in Spikes/G05-Recovery), all of them or those a filter selects, with
# the context a reader needs: the commit, the uncommitted changes the run includes (git diff --stat and new files), the
# host, the screen lock state (ioreg, read-only: the class-B tests skip while the screen is locked) and the load at the
# start and the end. Used for the before-and-after runs of the M0 device fixes (recovery).
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-host-tests.sh <log name> [<swift test --filter regex>]
# Log: Docs/Stage0/evidence/M0-DeviceFixes/recovery/<log name>.log
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
filter="${2:-}"
out="Docs/Stage0/evidence/M0-DeviceFixes/recovery/$name.log"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-host-tests.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "uncommitted changes in Spikes/G05-Recovery included in this run:"
  git -C "$root" diff --stat HEAD -- Spikes/G05-Recovery | sed 's/^/  /'
  git -C "$root" ls-files --others --exclude-standard -- Spikes/G05-Recovery | sed 's/^/  new: /'
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "---- xcrun swift test --force-resolved-versions${filter:+ --filter '$filter'} (in Spikes/G05-Recovery)"
} > "$out"
if [[ -n "$filter" ]]; then
  (cd Spikes/G05-Recovery && xcrun swift test --force-resolved-versions --filter "$filter") >> "$out" 2>&1
else
  (cd Spikes/G05-Recovery && xcrun swift test --force-resolved-versions) >> "$out" 2>&1
fi
status=$?
perl -pi -e 's/\e\[[0-9;]*m//g' "$out"
{
  echo "---- swift test exit: $status"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$out"
exit $status
