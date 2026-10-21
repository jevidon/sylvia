#!/bin/bash
# Rule A3 before and after the M0 final fix (final review R1-02): extracts Scripts/check-spike-anchors.py as reviewed
# (fea12c38dea8373e71cfd9708367d12129c7a698) into .build/scratch and runs a3-composed-check.py beside this script with
# the tools virtualenv (the checker needs jsonschema). Host only.
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/a3-composed-check.sh <log>
set -uo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root" || exit 1
source Scripts/lib/env.sh
log="$1"
reviewed=fea12c38dea8373e71cfd9708367d12129c7a698
mkdir -p .build/scratch/a3-check
git show "$reviewed:Scripts/check-spike-anchors.py" > .build/scratch/a3-check/check-spike-anchors-fea12c3.py
{
  echo "commit: $(git rev-parse HEAD); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  sylvia_python -I "$root/Docs/Stage0/evidence/M0-Integration/final-fix/commands/a3-composed-check.py" "$root" \
    "$root/.build/scratch/a3-check/check-spike-anchors-fea12c3.py" "$root/Scripts/check-spike-anchors.py"
  echo "exit: $?"
} > "$log" 2>&1
tail -n 1 "$log"
