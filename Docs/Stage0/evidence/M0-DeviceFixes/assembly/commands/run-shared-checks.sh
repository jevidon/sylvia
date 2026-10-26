#!/bin/bash
# M0 device fixes, assembly: the repository-wide checks of the merged tree (branch m0-device-fixes). Host only; no
# network, simulator or build.
#   Docs/Stage0/evidence/M0-DeviceFixes/assembly/commands/run-shared-checks.sh
# 1. Scripts/ci.sh contracts: 00-git-lfs, 10-contracts and 11-capture-anchor-contracts.
# 2. Scripts/ci.d/13-hard-rules.sh: the hard-rules audit over every committed and new file (so it reads this folder's
#    README and logs too when they exist).
# 3. Scripts/ci.d/12-dependency-lock.sh: the dependency lock and license inventory.
# Logs: Docs/Stage0/evidence/M0-DeviceFixes/assembly/shared-checks/ (ci-contracts.log and the three contract drop-ins'
# own logs, 13-hard-rules.log, 12-dependency-lock.log). Exit 0 only if all three pass.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="Docs/Stage0/evidence/M0-DeviceFixes/assembly/shared-checks"
mkdir -p "$out"
uncommitted="$(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
header() {
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files before these checks: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"
}
overall=0
{ echo "command: Scripts/ci.sh contracts"; header; } > "$out/ci-contracts.log"
Scripts/ci.sh contracts >> "$out/ci-contracts.log" 2>&1; status=$?
echo "ci.sh contracts exit: $status; end: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$out/ci-contracts.log"
for name in 00-git-lfs 10-contracts 11-capture-anchor-contracts; do
  perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' ".build/ci-logs/$name.log" > "$out/$name.log"
done
echo "Scripts/ci.sh contracts: exit $status"
(( status == 0 )) || overall=1
{ echo "command: Scripts/ci.d/13-hard-rules.sh"; header; } > "$out/13-hard-rules.log"
Scripts/ci.d/13-hard-rules.sh >> "$out/13-hard-rules.log" 2>&1; status=$?
echo "13-hard-rules exit: $status; end: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$out/13-hard-rules.log"
echo "Scripts/ci.d/13-hard-rules.sh: exit $status"
(( status == 0 )) || overall=1
{ echo "command: Scripts/ci.d/12-dependency-lock.sh"; header; } > "$out/12-dependency-lock.log"
Scripts/ci.d/12-dependency-lock.sh >> "$out/12-dependency-lock.log" 2>&1; status=$?
echo "12-dependency-lock exit: $status; end: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$out/12-dependency-lock.log"
echo "Scripts/ci.d/12-dependency-lock.sh: exit $status"
(( status == 0 )) || overall=1
exit $overall
