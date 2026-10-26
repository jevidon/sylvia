#!/bin/bash
# G0.2 probe fix: runs the signed identity probe's tests with the xcodebuild command of
# Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh (automatic signing, team A4KBDX665Z, -allowProvisioningUpdates,
# the probe's own DerivedData), optionally narrowed with -only-testing, and writes LOG: a header (commit, uncommitted
# paths, host, Xcode, time, load, screen and login-keychain lock state), then the test lines (G02-DIAG, G02-PROBE,
# results, issues, errors). The full xcodebuild output stays in .build/scratch/probe-fix-tests/.
#   Docs/Stage0/evidence/G02-Transfer/probe-fix/commands/run-probe-tests.sh LOG [xcodebuild test options...]
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
log="$1"; shift
dir="$root/Spikes/G02-Transfer/MacIdentityProbe"
work="$root/.build/scratch/probe-fix-tests"
mkdir -p "$work" "$(dirname "$log")"
lock_state() {
  xcrun swiftc -swift-version 6 -target arm64-apple-macos26.0 -module-cache-path "$work/module-cache" \
    -o "$work/lock-state" "$here/lock-state.swift" 2> /dev/null && "$work/lock-state"
}
{
  echo "command: Docs/Stage0/evidence/G02-Transfer/probe-fix/commands/run-probe-tests.sh <log> $*"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  git status --porcelain | sed 's/^/  uncommitted: /'
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ) ($(date +%Y-%m-%dT%H:%M:%S%z) on the build Mac's clock); load: $(uptime)"
  echo "lock state at start: $(lock_state | tr '\n' ';')"
  echo "xcodebuild test -project G02MacIdentityProbe.xcodeproj -scheme G02MacIdentityProbe -destination platform=macOS"
  echo "  -derivedDataPath Spikes/G02-Transfer/MacIdentityProbe/.build/DerivedData -disableAutomaticPackageResolution"
  echo "  -allowProvisioningUpdates DEVELOPMENT_TEAM=$SYLVIA_TEAM_ID $*"
} > "$log"
sylvia_generate "$dir" || { echo "sylvia_generate failed" >> "$log"; exit 1; }
status=0
(cd "$dir" && xcodebuild test -project G02MacIdentityProbe.xcodeproj -scheme G02MacIdentityProbe -destination platform=macOS \
  -derivedDataPath "$dir/.build/DerivedData" -disableAutomaticPackageResolution -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$SYLVIA_TEAM_ID" "$@" > "$work/xcodebuild.log" 2>&1) || status=$?
{
  echo "--- test output (xcodebuild exit $status; lines matching G02-DIAG, G02-PROBE, results, issues and errors, in order)"
  grep -E 'G02-DIAG|G02-PROBE|✔|✘|recorded an issue|error:|\*\* TEST|Signing Identity|No profiles|No Account' "$work/xcodebuild.log" \
    | grep -v '^\[' | sed "s#$root/##g"
  echo "--- end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "lock state at end: $(lock_state | tr '\n' ';')"
  echo "xcodebuild exit status: $status"
} >> "$log"
exit $status
