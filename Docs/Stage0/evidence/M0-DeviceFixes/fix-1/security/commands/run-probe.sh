#!/bin/bash
# M0 device fixes, fix-1, the security review of 26 October 2026 (finding S7): runs the recovery job's host-facts probe
# (Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/probe-host-facts.swift, as it is in the working tree) with the
# context a reader needs: the commit and any uncommitted change to the probe, the screen lock state (ioreg, read only;
# the probe's sections 3 and 4 need the screen unlocked), the load, and the probe's own folders
# (g05-devicefix-probe-*) in the temporary folder before and after the run. Writes nothing itself; the probe writes only
# in a folder of its own there. Build Mac only.
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/run-probe.sh <log name>
# Log: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/<log name>.log
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
out="Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/$name.log"
probe="Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/probe-host-facts.swift"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
# FileManager.temporaryDirectory, where the probe makes its folder, is TMPDIR when it is set.
tmp="${TMPDIR:-$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)}"
leftovers() {
  local found
  found="$(cd "$tmp" && ls -d g05-devicefix-probe-* 2>/dev/null)"
  if [[ -n "$found" ]]; then echo "$found" | sed 's/^/  /'; else echo "  none"; fi
}
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/run-probe.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "uncommitted change to the probe in this run (git diff --stat):"
  git -C "$root" diff --stat HEAD -- "$probe" | sed 's/^/  /'
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "temporary folder: $tmp"
  echo "the probe's folders there before the run:"
  leftovers
  echo "---- xcrun swift $probe"
} > "$out"
xcrun swift "$probe" >> "$out" 2>&1
status=$?
{
  echo "---- exit: $status"
  echo "the probe's folders there after the run:"
  leftovers
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$out"
exit $status
