#!/bin/bash
# Runs probe-host-facts.swift (beside this file) with the context a reader needs: commit, screen lock state (ioreg,
# read only; the probe's sections 3 and 4 need the screen unlocked) and load.
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-probe.sh [<log name>]
# Log: Docs/Stage0/evidence/M0-DeviceFixes/recovery/<log name, default probe-host-facts>.log
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
out="Docs/Stage0/evidence/M0-DeviceFixes/recovery/${1:-probe-host-facts}.log"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-probe.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "---- xcrun swift Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/probe-host-facts.swift"
} > "$out"
xcrun swift Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/probe-host-facts.swift >> "$out" 2>&1
status=$?
{
  echo "---- exit: $status"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$out"
exit $status
