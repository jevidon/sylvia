#!/usr/bin/env bash
# G0.3 clean CI run for the evidence folder: deletes this checkout's G0.3 build products, runs
# `Scripts/ci.sh contracts g03-intake`, and writes one log with the CI summary and every drop-in log. Afterwards
# Spikes/G03-Intake/scripts/collect-evidence.sh copies the step logs into Docs/Stage0/evidence/G03-Intake/.
#
#   G03_SIM_NAME=<your own simulator> Spikes/G03-Intake/scripts/clean-ci-run.sh <log>
#
# The shared fixture cache is not deleted (its files are verified against their pinned digests by step 1).
set -uo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
log="${1:?usage: clean-ci-run.sh <log>}"
mkdir -p "$(dirname "$log")"
cd "$SYLVIA_ROOT"
products=(.build/DerivedData .build/ci-logs Spikes/G03-Intake/IntakeKit/.build Spikes/G03-Intake/App/.build
          Spikes/G03-Intake/App/G03Intake.xcodeproj Spikes/G03-Intake/ZipEval/Readium/.build
          Spikes/G03-Intake/ZipEval/Upstream/.build Spikes/G03-Intake/ZipEval/IdentityProbe/.build
          Spikes/G03-Intake/ZipEval/Common/.build)
clean="$([[ -z "$(git status --porcelain)" ]] && echo yes || echo no)"
{
  echo "# G0.3 clean CI run"
  echo "# started: $(date -u +%Y-%m-%dT%H:%M:%SZ), commit $(git rev-parse --short HEAD), working tree clean: $clean"
  echo "# build products deleted first: ${products[*]}"
  echo "# command: G03_SIM_NAME=${G03_SIM_NAME:-Sylvia-M0-g03-intake} Scripts/ci.sh contracts g03-intake"
  echo "# load at start: $(uptime)"
  echo "# timings below are indicative only: other agents may be building and testing on this Mac"
  echo
} > "$log"
rm -rf "${products[@]}"
"$SYLVIA_ROOT/Scripts/ci.sh" contracts g03-intake >> "$log" 2>&1
status=$?
{
  echo
  echo "# Scripts/ci.sh exit status: $status"
  for f in .build/ci-logs/10-contracts.log .build/ci-logs/50-g03-intake.log; do
    echo
    echo "################ $f"
    cat "$f"
  done
  echo
  echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# load at end: $(uptime)"
  echo "clean-run finished"
} >> "$log"
exit "$status"
