#!/bin/bash
# Runs one command from the repository root and records, around its output, the commit, the uncommitted paths, the
# host and Xcode, the time and the load, and the command's exit status. Used at the toolchain re-pin round
# (20 October 2026) for `Scripts/ci.sh contracts` and `Scripts/ci.d/13-hard-rules.sh`.
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh <command> [args...] > <log> 2>&1
set -uo pipefail
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
echo "command: $*"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
git status --porcelain | sed 's/^/  uncommitted: /'
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo
"$@"
status=$?
echo
echo "exit status: $status"
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
exit $status
