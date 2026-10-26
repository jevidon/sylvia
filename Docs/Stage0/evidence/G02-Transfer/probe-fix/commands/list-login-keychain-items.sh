#!/bin/bash
# G0.2 probe fix: runs list-login-keychain-items.swift unsigned with the pinned toolchain and records, around its
# output, the commit, the uncommitted paths, the host, the time and the load. Lists only; deletes nothing.
#   Docs/Stage0/evidence/G02-Transfer/probe-fix/commands/list-login-keychain-items.sh [service-prefix] > <log> 2>&1
# (The prefix argument was added after the first listing; without it the output is as before.)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
work="$root/.build/scratch/probe-fix-listing"
mkdir -p "$work"
echo "command: Docs/Stage0/evidence/G02-Transfer/probe-fix/commands/list-login-keychain-items.sh $*"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
git status --porcelain | sed 's/^/  uncommitted: /'
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ) ($(date +%Y-%m-%dT%H:%M:%S%z) on the build Mac's clock); load: $(uptime)"
echo
# Compiled (deprecation warnings of the SecKeychain calls left out of the log), then run.
xcrun swiftc -swift-version 6 -target arm64-apple-macos26.0 -module-cache-path "$work/module-cache" \
  -o "$work/list-login-keychain-items" "$here/list-login-keychain-items.swift" 2> "$work/compile.log" \
  || { cat "$work/compile.log"; echo "exit status: compile failed"; exit 1; }
"$work/list-login-keychain-items" "$@"
status=$?
echo
echo "exit status: $status"
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
exit $status
