#!/bin/bash
# The repository-wide checks this branch's changes must pass: Scripts/ci.sh contracts (00-git-lfs, 10-contracts,
# 11-capture-anchor-contracts), Scripts/ci.d/13-hard-rules.sh (the hard-rules audit over every committed and new file)
# and Scripts/ci.d/12-dependency-lock.sh (the lock and license inventory). Host only; no network, simulator or build.
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-shared-checks.sh
# Logs: Docs/Stage0/evidence/M0-DeviceFixes/recovery/shared-checks/
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
out="Docs/Stage0/evidence/M0-DeviceFixes/recovery/shared-checks"
mkdir -p "$out"
source Scripts/lib/env.sh
header() {
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
}
overall=0
{ echo "command: Scripts/ci.sh contracts"; header; } > "$out/ci-contracts.log"
Scripts/ci.sh contracts >> "$out/ci-contracts.log" 2>&1; status=$?
echo "ci.sh contracts exit: $status" >> "$out/ci-contracts.log"
for name in 00-git-lfs 10-contracts 11-capture-anchor-contracts; do
  perl -pe 's/\e\[[0-9;]*m//g' ".build/ci-logs/$name.log" > "$out/$name.log"
done
(( status == 0 )) || overall=1
{ echo "command: Scripts/ci.d/13-hard-rules.sh"; header; } > "$out/13-hard-rules.log"
Scripts/ci.d/13-hard-rules.sh >> "$out/13-hard-rules.log" 2>&1; status=$?
echo "13-hard-rules exit: $status" >> "$out/13-hard-rules.log"
(( status == 0 )) || overall=1
{ echo "command: Scripts/ci.d/12-dependency-lock.sh"; header; } > "$out/12-dependency-lock.log"
Scripts/ci.d/12-dependency-lock.sh >> "$out/12-dependency-lock.log" 2>&1; status=$?
echo "12-dependency-lock exit: $status" >> "$out/12-dependency-lock.log"
(( status == 0 )) || overall=1
exit $overall
