#!/bin/bash
# G0.2 probe fix: runs runbook 0.7's command, Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh LOG, unchanged,
# and writes beside LOG a console log (LOG with .console.log for .log) holding what the script's own log does not:
# the commit, the uncommitted paths, the time, the load, the screen and login-keychain lock state, the script's exit
# status, and the diagnostic test's G02-DIAG lines from the full xcodebuild output (which the script does not copy).
#   Docs/Stage0/evidence/G02-Transfer/probe-fix/commands/run-probe-script.sh LOG
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
log="$1"
console="${log%.log}.console.log"
work="$root/.build/scratch/probe-fix-tests"
mkdir -p "$work" "$(dirname "$log")"
lock_state() {
  xcrun swiftc -swift-version 6 -target arm64-apple-macos26.0 -module-cache-path "$work/module-cache" \
    -o "$work/lock-state" "$here/lock-state.swift" 2> /dev/null && "$work/lock-state"
}
{
  echo "command: Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh $log (runbook 0.7), through probe-fix/commands/run-probe-script.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  git status --porcelain | sed 's/^/  uncommitted: /'
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ) ($(date +%Y-%m-%dT%H:%M:%S%z) on the build Mac's clock); load: $(uptime)"
  echo "lock state at start: $(lock_state | tr '\n' ';')"
  echo "--- the script's own output"
} > "$console"
status=0
Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh "$log" >> "$console" 2>&1 || status=$?
{
  echo "--- the script's exit status: $status (0 passed, 1 failed, 2 not run: signing unavailable)"
  echo "--- G02-DIAG lines and test results from the full xcodebuild output (.build/scratch/g02-identity-probe/xcodebuild.log)"
  grep -E 'G02-DIAG|✔|✘|recorded an issue' "$root/.build/scratch/g02-identity-probe/xcodebuild.log" | grep -v '^\[' \
    | sed "s#$root/##g"
  echo "--- end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "lock state at end: $(lock_state | tr '\n' ';')"
} >> "$console"
exit $status
