#!/bin/bash
# Checks behind Docs/Stage0/M0-gate.md, run on the commit that adds it:
#   Docs/Stage0/evidence/M0-Integration/commands/gate-summary-checks.sh <log>
# 1. No code, script, contract or fixture changed after the second complete CI run (efc9479).
# 2. The Git LFS state of the tree and of the repository configuration (read-only).
# 3. Every path M0-gate.md cites exists, and the status counts of its Section 2 rows (gate-summary-check.py).
# 4. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules, with their summary lines.
# No simulator is created or used, nothing plays audio, and nothing is written outside .build/ and the log.
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
log="$1"
cd "$root"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
status=0
# Counted before the log is created, so the log itself (often written into the evidence folder) is not counted.
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD); uncommitted files before this run: $uncommitted"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. git diff --stat efc9479 HEAD -- Spikes Scripts Packages Apps Contracts Fixtures .github (nothing below = no change)"
  git diff --stat efc9479 HEAD -- Spikes Scripts Packages Apps Contracts Fixtures .github
  echo
  echo "== 2. Git LFS state"
  if [[ -e .gitattributes ]]; then echo ".gitattributes present:"; cat .gitattributes; else echo ".gitattributes: absent"; fi
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' ')"
  echo "git check-attr filter on one snapshot reference and one evidence image:"
  git check-attr filter -- \
    Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests/progressRule.light-default.png \
    Docs/Stage0/evidence/G01-EPUB/highlight-paper.png
  echo
  echo "== 3. M0-gate.md paths and statuses"
} > "$log" 2>&1
python3 -I Docs/Stage0/evidence/M0-Integration/commands/gate-summary-check.py "$root" >> "$log" 2>&1 || status=1
{
  echo
  echo "== 4. Scripts/ci.sh contracts dependency-lock hard-rules"
} >> "$log"
Scripts/ci.sh contracts dependency-lock hard-rules >> "$log" 2>&1 || status=1
{
  echo "summary lines from the drop-ins' own logs (.build/ci-logs/):"
  for name in 10-contracts 11-capture-anchor-contracts 12-dependency-lock 13-hard-rules; do
    echo "-- $name (last 4 lines)"
    tail -n 4 ".build/ci-logs/$name.log"
  done
  echo
  echo "exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log" 2>&1
exit $status
