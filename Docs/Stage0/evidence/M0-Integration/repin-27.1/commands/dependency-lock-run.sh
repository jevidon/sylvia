#!/bin/bash
# Runs Scripts/ci.d/12-dependency-lock.sh (ADR-0014: the checker's self-test, then the repository against
# Docs/Licenses/inventory.json and, with --toolchain, the installed Xcode build, Swift, XcodeGen and tools virtualenv)
# from this worktree and records the commit, the uncommitted paths, the host and the result. Host only: no network,
# simulator or build. Used twice in the re-pin round of 20 October 2026: before the pins changed (the control: the
# toolchain check fails on Xcode 27.1 against the 27A266a pin) and on the round's last commit (it must pass).
#
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/dependency-lock-run.sh > <log> 2>&1
set -uo pipefail
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh

echo "command: Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/dependency-lock-run.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
git status --porcelain | sed 's/^/  uncommitted: /'
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "pin in Scripts/lib/env.sh: $SYLVIA_XCODE_BUILD_PINNED; inventory: $(python3 -I -c 'import json,sys; t=json.load(open(sys.argv[1]))["toolchain"]; print(t["xcode"]["version"], t["xcode"]["build"])' Docs/Licenses/inventory.json)"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo
mkdir -p .build/scratch
out="$(mktemp .build/scratch/dependency-lock-run.XXXXXX)"
Scripts/ci.d/12-dependency-lock.sh 2>&1 | tee "$out"
status=${PIPESTATUS[0]}
echo
echo "12-dependency-lock exit status: $status"
echo "FAIL lines in its output: $(grep -c -E '^FAIL ' "$out")"
grep -E '^FAIL ' "$out" | sed 's/^/  /'
rm -f "$out"
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
exit $status
