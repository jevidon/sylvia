#!/bin/bash
# Runbook 0.8 on m0-records-update (26 October 2026; integration log section 41): has anything G0.5 recovery's drop-in
# builds, copies or runs changed since 9cdb0a02, the commit of the run with the screen unlocked whose class-B evidence
# report row 10 rests on? The paths, read from Scripts/ci.d/71-g05-recovery.sh and the two files it runs that name further
# paths (Scripts/lib/env.sh, for sylvia_python, and Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh):
#   Scripts/ci.d/71-g05-recovery.sh; Scripts/lib (env.sh, sim.sh, xcodegen.sh); Scripts/tools (sylvia_python installs
#   its requirements.txt when the virtualenv is missing); in Spikes/G05-Recovery the package (Package.swift,
#   Package.resolved, Sources, Tests with their fixtures, Scripts/check_manifest_contract.py) and LockHarness; and the
#   backup-manifest contract and fixtures (Contracts/schemas/backup-manifest.v1.schema.json,
#   Contracts/fixtures/backup-manifest.v1).
# It prints, for 4c0fa815 (the merge of m0-sessions, after which this branch changes documents and evidence only) and for
# HEAD: the diff stat of those paths with Spikes/G05-Recovery/DeviceTests set apart (it must be empty), and of the whole
# of Spikes/G05-Recovery (it lists DeviceTests alone); then whether any file the drop-in or the lock harness's checks run
# names DeviceTests (none must). Read-only.
#   Docs/Stage0/evidence/M0-RecordsUpdate/commands/step-08-paths.sh > <log>
set -u
root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$root" || exit 1
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
merge=4c0fa815
paths=(Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery
       Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1)
status=0
echo "step-08-paths: HEAD $(git rev-parse HEAD), uncommitted paths: $(git status --porcelain | wc -l | tr -d ' '); $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "the run's commit: $run ($(git log -1 --format='%ad' --date=iso "$run"))"
git merge-base --is-ancestor "$run" HEAD && echo "$run is an ancestor of HEAD" || { echo "PROBLEM: $run is not an ancestor of HEAD"; status=1; }
for to in "$merge" HEAD; do
  echo
  echo "== $run..$to ($(git rev-parse --short "$to"))"
  echo "-- the drop-in's paths, Spikes/G05-Recovery/DeviceTests set apart (must be empty):"
  out="$(git diff --stat "$run" "$to" -- "${paths[@]}" ':(exclude)Spikes/G05-Recovery/DeviceTests')"
  if [[ -z "$out" ]]; then echo "   (no change)"; else echo "$out"; echo "PROBLEM: the drop-in's paths changed"; status=1; fi
  echo "-- the whole of Spikes/G05-Recovery (DeviceTests alone expected):"
  git diff --stat "$run" "$to" -- Spikes/G05-Recovery
  other="$(git diff --name-only "$run" "$to" -- Spikes/G05-Recovery | grep -v '^Spikes/G05-Recovery/DeviceTests/' || true)"
  [[ -z "$other" ]] || { echo "PROBLEM: changed outside DeviceTests: $other"; status=1; }
  echo "-- outside Docs/ (for the record; the drop-in uses none of what is listed unless it is above):"
  git diff --stat "$run" "$to" -- . ':(exclude)Docs' | tail -n 20
done
echo
echo "== files the drop-in runs or reads that name DeviceTests (none expected)"
hits="$(grep -l 'DeviceTests' Scripts/ci.d/71-g05-recovery.sh Scripts/lib/*.sh Spikes/G05-Recovery/Package.swift \
        Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null || true)"
if [[ -z "$hits" ]]; then echo "   none"; else echo "$hits"; echo "PROBLEM: a file the drop-in uses names DeviceTests"; status=1; fi
echo
echo "result: $( ((status == 0)) && echo "row 10's class-B evidence from the run on $run stands; 0.8 needs nothing" || echo FAIL )"
exit $status
