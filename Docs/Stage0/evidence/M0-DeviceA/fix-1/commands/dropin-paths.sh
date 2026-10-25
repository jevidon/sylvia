#!/bin/bash
# Runbook 0.8, as the fix of the fidelity findings of the review of the update of 24 October 2026 checks it (26 October
# 2026 on the build Mac's clock; finding FID-DA-03): has anything G0.5 recovery's drop-in builds, copies or runs changed
# since 9cdb0a02, the commit of the agent's passing run with the screen unlocked (22 October 2026 UTC)? The successor of
# Docs/Stage0/evidence/M0-DeviceA/instructions/commands/dropin-paths.sh, which checked 6cede84a and the HEAD it ran on:
# the paths are read the same way, from the drop-in itself (Scripts/ci.d/71-g05-recovery.sh) and from the two files it
# runs that name further paths (the lock harness's checks and the backup-manifest checker), and each commit checked is
# named in full:
#   6cede84a (m0-sessions on 24 October 2026), 5e455f70 (the assembly's merge, which its log checked), 8082bdb6 (the
#   head the review read) and HEAD: git diff --stat 9cdb0a02 <commit> -- <paths> must print nothing;
#   m0-decisions, whose commits after 044ed3cf are to be merged into m0-sessions before the sessions' checkout moves:
#   what that merge would bring under those paths is printed, and is not a failure of this check (0.8 runs again after
#   that merge);
# then whether the drop-in, or a file it runs, names Scripts/check-dependency-lock.py or Scripts/ci.d/12-dependency-lock.sh,
# the two files the m0-exit-prep run changes (as relayed; that branch is not read here). Read-only.
#   Docs/Stage0/evidence/M0-DeviceA/fix-1/commands/dropin-paths.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
dropin=Scripts/ci.d/71-g05-recovery.sh
harness=Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh
manifest=Spikes/G05-Recovery/Scripts/check_manifest_contract.py
paths=(Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery
       Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1)
status=0
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/fix-1/commands/dropin-paths.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "== 1. What the drop-in builds, copies or runs, read from it (lines as at HEAD)"
  echo "-- the drop-in itself: $dropin"
  echo "-- Scripts/lib: it sources env.sh and sim.sh; the lock harness's checks it runs source xcodegen.sh too:"
  grep -n -E 'Scripts/lib|/\.\./lib|lib/(sim|env|xcodegen)\.sh' "$dropin" "$harness" | sed 's/^/   /'
  echo "-- Scripts/tools: sylvia_python (Scripts/lib/env.sh) runs Scripts/tools/bootstrap.sh, which installs"
  echo "   Scripts/tools/requirements.txt, when the tools virtualenv is missing; the drop-in calls it in step 10:"
  grep -n 'sylvia_python' "$dropin" Scripts/lib/env.sh | sed 's/^/   /'
  echo "-- Spikes/G05-Recovery: the package it builds and tests, the lock harness and its checks, the manifest checker:"
  grep -n -E 'SPIKE=|"\$SPIKE/|HARNESS=' "$dropin" "$harness" | sed 's/^/   /'
  echo "-- Contracts: the backup-manifest schema and fixtures (step 10's checker; the host tests' ManifestContractTests):"
  grep -n 'Contracts/' "$manifest" Spikes/G05-Recovery/Tests/SylviaRecoveryTests/ManifestContractTests.swift | sed 's/^/   /'
  echo "-- any other repository path the drop-in or the harness checks name (SYLVIA_ROOT/...):"
  grep -n -o -E '\$SYLVIA_ROOT/[A-Za-z0-9_./-]+' "$dropin" "$harness" | sort -u | sed 's/^/   /'
  echo "-- DeviceTests named by the drop-in or the harness checks: $(grep -c 'DeviceTests' "$dropin" "$harness" | tr '\n' ' ')"
  echo
  echo "== 2. git diff --stat $run <commit> -- ${paths[*]}"
} > "$log" 2>&1
for commit in 6cede84a6f6ac610976b233d875e26dd89419dbd 5e455f706c20d46711030a8b030c9dbf87dd4acd \
              8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22 HEAD; do
  full="$(git rev-parse "$commit")"
  out="$(git diff --stat "$run" "$full" -- "${paths[@]}")"
  if [[ -z "$out" ]]; then
    echo "-- $commit ($full): no change: the run of $run stands for what the drop-in builds, copies or runs" >> "$log"
  else
    { echo "-- $commit ($full): CHANGED, so 0.8 runs again:"; printf '%s\n' "$out" | sed 's/^/   /'; } >> "$log"
    status=1
  fi
done
{
  echo "-- m0-decisions ($(git rev-parse m0-decisions)), whose commits after 044ed3cf are to be merged into m0-sessions before"
  echo "   the sessions' checkout moves (not a failure of this check; after that merge 0.8 runs again):"
  git diff --stat "$run" m0-decisions -- "${paths[@]}" | sed 's/^/   /'
  echo
  echo "== 3. Does the drop-in, or a file it runs, name the files the m0-exit-prep run changes?"
} >> "$log"
for file in Scripts/check-dependency-lock.py Scripts/ci.d/12-dependency-lock.sh; do
  base="$(basename "$file")"
  hits="$(grep -n -F -e "$base" -e "${base%.*}" "$dropin" "$harness" "$manifest" Scripts/lib/env.sh Scripts/lib/sim.sh Scripts/lib/xcodegen.sh Scripts/tools/bootstrap.sh 2>/dev/null || true)"
  if [[ -z "$hits" ]]; then
    echo "-- $file: named by none of them (the drop-in, the harness checks, the manifest checker, Scripts/lib, Scripts/tools/bootstrap.sh): the drop-in does not use it" >> "$log"
  else
    { echo "-- $file: NAMED:"; printf '%s\n' "$hits" | sed 's/^/   /'; } >> "$log"
    status=1
  fi
done
echo "   (12-dependency-lock is the drop-in Scripts/ci.sh runs as dependency-lock; runbook 0.8 runs 71-g05-recovery.sh alone, not through ci.sh)" >> "$log"
{
  echo
  echo "exit: $status"
} >> "$log"
exit $status
