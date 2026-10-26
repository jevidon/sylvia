#!/bin/bash
# Runs probe-paths.swift (beside this file) with the context a reader needs: commit, host, toolchain and time.
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/commands/run-probe.sh
# Log: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/probe-paths.log
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
out="Docs/Stage0/evidence/M0-DeviceFixes/fix-1/probe-paths.log"
source Scripts/lib/env.sh
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/commands/run-probe.sh"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "---- xcrun swift Docs/Stage0/evidence/M0-DeviceFixes/fix-1/commands/probe-paths.swift"
} > "$out"
xcrun swift Docs/Stage0/evidence/M0-DeviceFixes/fix-1/commands/probe-paths.swift >> "$out" 2>&1
status=$?
{
  echo "---- exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$out"
exit $status
