#!/usr/bin/env bash
# The checks that read the ADRs and CLAUDE.md, run for the record of the product owner's M0 decisions of
# 22 October 2026 in those files (branch m0-dec-adrs). Read-only on the repository: every output goes to the
# directory given, which must be outside the evidence folders while the runs happen (the logs are copied in and
# committed afterwards). Host only: no simulator, device, network, build of an app or audio.
#
#   Docs/Stage0/evidence/M0-Decisions/adrs/commands/adr-checks.sh <output directory>
#
# Parts (each part's own exit status is printed; the script exits 0 even when a part fails, because two of the
# parts are expected to change their output when the ADRs change, which is what the comparison afterwards shows):
#   1. Scripts/ci.sh contracts dependency-lock hard-rules: 00-git-lfs, 10-contracts, 11-capture-anchor-contracts,
#      12-dependency-lock (it reads ADR-0001's toolchain table, ADR-0014's package names and versions and
#      CLAUDE.md's toolchain line) and 13-hard-rules (it scans every committed and new file); each drop-in's log is
#      copied beside this script's output.
#   2. The plan amendments' checker, check-amendments.py (its Section 3.2 check counts each ADR's Consequences
#      bullets; run directly, because its runner run-checks.sh refuses a HEAD other than the commit under test).
#   3. The runbook content check and step coverage, repin-27.1/round-2/commands/runbook-content-check.sh (the
#      content check reads seven texts the runbook quotes from ADR-0001, ADR-0002, ADR-0005, ADR-0009, ADR-0010,
#      ADR-0011 and ADR-0013).
#   4. The runbook's correction-text check, M0-runbook/commands/check-correction-texts.py (corrections C47, C49,
#      C50 and C56 quote the ADR texts they replace).
#   5. The gate summary's status check, M0-Integration/commands/gate-refresh-check.py (it reads the ADR status
#      lines for rows 66, 71, 76-78 and 82-92 of Docs/Stage0/M0-gate.md, which another agent owns).
set -uo pipefail
out="${1:?usage: adr-checks.sh <output directory>}"
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh; source Scripts/lib/sim.sh; source Scripts/lib/xcodegen.sh
mkdir -p "$out"
out="$(cd "$out" && pwd)"

header() {
  echo "command: Docs/Stage0/evidence/M0-Decisions/adrs/commands/adr-checks.sh"
  echo "part: $1"
  echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m); $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
  echo "load: $(uptime)"
  echo "environment: host only; no simulator or device"
  echo
}

{
  header "1. Scripts/ci.sh contracts dependency-lock hard-rules"
  rm -f .build/ci-logs/00-git-lfs.log .build/ci-logs/10-contracts.log .build/ci-logs/11-capture-anchor-contracts.log \
        .build/ci-logs/12-dependency-lock.log .build/ci-logs/13-hard-rules.log
  Scripts/ci.sh contracts dependency-lock hard-rules
  echo "exit status: $?"
  echo "load at the end: $(uptime)"
} > "$out/1-ci-contracts-lock-hard-rules.log" 2>&1
for name in 00-git-lfs 10-contracts 11-capture-anchor-contracts 12-dependency-lock 13-hard-rules; do
  [[ -f ".build/ci-logs/$name.log" ]] && cp ".build/ci-logs/$name.log" "$out/1-$name.log"
done

{
  header "2. Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py"
  python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py
  echo "exit status: $?"
} > "$out/2-check-amendments.log" 2>&1

{
  header "3. Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2/commands/runbook-content-check.sh"
  Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2/commands/runbook-content-check.sh
  echo "exit status: $?"
} > "$out/3-runbook-content-check.log" 2>&1

{
  header "4. Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py"
  python3 -I Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py
  echo "exit status: $?"
} > "$out/4-correction-texts.log" 2>&1

{
  header "5. Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
  python3 -I Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py "$root"
  echo "exit status: $?"
} > "$out/5-gate-status-check.log" 2>&1

grep -H "^exit status" "$out"/[1-5]-*.log
exit 0
