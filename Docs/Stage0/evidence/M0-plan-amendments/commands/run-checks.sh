#!/usr/bin/env bash
# Runs the M0 plan-amendment checks and prints a header naming the environment.
# Usage, from the repository root, on a clean tree whose HEAD is the commit under test:
#   Docs/Stage0/evidence/M0-plan-amendments/commands/run-checks.sh <commit under test>
set -uo pipefail
commit="${1:?usage: run-checks.sh <commit under test>}"
echo "# M0 plan amendments: consistency checks"
echo "command: Docs/Stage0/evidence/M0-plan-amendments/commands/run-checks.sh $commit"
echo "commit under test: $commit"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
echo "HEAD: $head; uncommitted paths: $dirty"
if [[ "$(git rev-parse "$commit")" != "$head" || "$dirty" != "0" ]]; then
  echo "refused: run on a clean tree whose HEAD is the commit under test"
  exit 2
fi
echo "date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m); $(python3 --version 2>&1)"
echo "load: $(uptime)"
echo "environment: host only; no simulator or device is used by these checks"
echo
echo "== Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py"
python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py
status=$?
echo "exit status: $status"
echo
echo "== Docs/Stage0/evidence/M0-plan-amendments/commands/mutation-checks.py (each mutation must make the checker fail)"
python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/mutation-checks.py
mutation=$?
echo "exit status: $mutation"
echo "tree after the mutation checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths"
echo
echo "== control, not required (this work changes no contract): Scripts/ci.sh contracts"
Scripts/ci.sh contracts
control=$?
echo "exit status: $control"
if [[ $status -ne 0 || $mutation -ne 0 || $control -ne 0 ]]; then exit 1; fi
exit 0
