#!/bin/bash
# Runbook 0.8, as the fix of the completeness findings of the review of the update of 24 October 2026 checks it (26
# October 2026 on the build Mac's clock; finding DA-07): has anything G0.5 recovery's drop-in builds, copies or runs
# changed since 9cdb0a02, the commit of the agent's passing run with the screen unlocked (22 October 2026 UTC), and does
# the merge of m0-decisions, which adds Spikes/G05-Recovery/DeviceTests, change any of it? The successor of
# Docs/Stage0/evidence/M0-DeviceA/fix-1/commands/dropin-paths.sh (the first fix's), whose reading of the paths it keeps:
#   1. the paths, read from the drop-in itself (Scripts/ci.d/71-g05-recovery.sh) and from the two files it runs that name
#      further paths (the lock harness's checks and the backup-manifest checker); and, for DA-07, what in
#      Spikes/G05-Recovery they use: the package's manifest (its targets, at SwiftPM's default folders, Sources/<target>
#      and Tests/<target>, since none names a path), its lock, the manifest checker and the lock harness; and whether
#      either names DeviceTests;
#   2. git diff --stat 9cdb0a02 <commit> -- <paths> for 6cede84a, 5e455f70, 8082bdb6, ec91f66a (the head this fix
#      started from) and HEAD: each must print nothing; each commit named in full;
#   3. m0-decisions, whose commits after 044ed3cf are to be merged into m0-sessions before the sessions' checkout moves:
#      what it changes under those paths (it must be under Spikes/G05-Recovery/DeviceTests only), and the same with
#      ':(exclude)Spikes/G05-Recovery/DeviceTests', runbook 0.8's check that sets it apart (it must print nothing);
#   4. a merge of m0-decisions into HEAD, computed and not made (git merge-tree --write-tree, which writes the merged
#      tree's objects to the object store and nothing else): the same two checks on the merged tree, as runbook 0.8 has
#      the owner run them after that merge;
#   5. whether the drop-in, or a file it runs, names Scripts/check-dependency-lock.py or Scripts/ci.d/12-dependency-lock.sh,
#      the two files the m0-exit-prep run changes (as relayed; that branch is not read here).
# Read-only: no ref, index or working-tree file is written.
#   Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/dropin-paths.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, completeness, fix-1, M0-DeviceA, evidence, Stage0, Docs
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
dropin=Scripts/ci.d/71-g05-recovery.sh
harness=Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh
manifest=Spikes/G05-Recovery/Scripts/check_manifest_contract.py
paths=(Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery
       Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1)
apart=':(exclude)Spikes/G05-Recovery/DeviceTests'
status=0
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/dropin-paths.sh"
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
  grep -n -E 'SPIKE=|"\$SPIKE/|HARNESS=|cd "\$SPIKE"' "$dropin" "$harness" | sed 's/^/   /'
  echo "-- Contracts: the backup-manifest schema and fixtures (step 10's checker; the host tests' ManifestContractTests):"
  grep -n 'Contracts/' "$manifest" Spikes/G05-Recovery/Tests/SylviaRecoveryTests/ManifestContractTests.swift | sed 's/^/   /'
  echo "-- any other repository path the drop-in or the harness checks name (SYLVIA_ROOT/...):"
  grep -n -o -E '\$SYLVIA_ROOT/[A-Za-z0-9_./-]+' "$dropin" "$harness" | sort -u | sed 's/^/   /'
  echo
  echo "== 1b. What in Spikes/G05-Recovery the drop-in uses (DA-07)"
  echo "-- the package's commands in the drop-in, run in Spikes/G05-Recovery (cd \"\$SPIKE\"): swift build, swift test and"
  echo "   xcodebuild with the package's scheme G05Recovery-Package and no -project or -workspace:"
  grep -n -E 'swift (build|test)|xcodebuild (test|build)|-scheme ' "$dropin" | sed 's/^/   /'
  echo "-- the package's targets (Package.swift); a target with no path: argument is built from SwiftPM's default folder,"
  echo "   Sources/<target> or Tests/<target>:"
  grep -n -E '^\s*\.(target|executableTarget|testTarget)\(|name: "|path:' Spikes/G05-Recovery/Package.swift | sed 's/^/   /'
  echo "   path: arguments in Package.swift: $(grep -c 'path:' Spikes/G05-Recovery/Package.swift)"
  echo "-- the lock the drop-in reads (step 1) and the lock harness's checks compare (step 13):"
  grep -n -E 'Package\.resolved' "$dropin" "$harness" | sed 's/^/   /'
  echo "-- the files of Spikes/G05-Recovery at HEAD, by top-level entry:"
  git ls-files Spikes/G05-Recovery | awk -F/ '{print $3}' | sort | uniq -c | sed 's/^/   /'
  echo "-- lines naming DeviceTests in the drop-in, the harness checks, the manifest checker, Package.swift and Scripts/lib:"
  hits="$(grep -n 'DeviceTests' "$dropin" "$harness" "$manifest" Spikes/G05-Recovery/Package.swift Scripts/lib/*.sh 2>/dev/null || true)"
  if [[ -z "$hits" ]]; then echo "   none"; else printf '%s\n' "$hits" | sed 's/^/   NAMED: /'; fi
} > "$log" 2>&1
[[ -z "$hits" ]] || status=1
{
  echo
  echo "== 2. git diff --stat $run <commit> -- ${paths[*]}"
} >> "$log"
for commit in 6cede84a6f6ac610976b233d875e26dd89419dbd 5e455f706c20d46711030a8b030c9dbf87dd4acd \
              8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22 ec91f66a863c70980533f27f53d8e6b44f234485 HEAD; do
  full="$(git rev-parse "$commit")"
  out="$(git diff --stat "$run" "$full" -- "${paths[@]}")"
  if [[ -z "$out" ]]; then
    echo "-- $commit ($full): no change: the run of $run stands for what the drop-in builds, copies or runs" >> "$log"
  else
    { echo "-- $commit ($full): CHANGED, so 0.8 runs again:"; printf '%s\n' "$out" | sed 's/^/   /'; } >> "$log"
    status=1
  fi
done
decisions="$(git rev-parse m0-decisions)"
names="$(git diff --name-only "$run" "$decisions" -- "${paths[@]}")"
outside="$(printf '%s\n' "$names" | grep . | grep -v '^Spikes/G05-Recovery/DeviceTests/' || true)"
apart_out="$(git diff --stat "$run" "$decisions" -- "${paths[@]}" "$apart")"
{
  echo
  echo "== 3. m0-decisions ($decisions), whose commits after 044ed3cf are to be merged into m0-sessions before the sessions' checkout moves"
  echo "-- git diff --stat $run m0-decisions -- <the paths>:"
  git diff --stat "$run" "$decisions" -- "${paths[@]}" | sed 's/^/   /'
  echo "   of them, outside Spikes/G05-Recovery/DeviceTests: $( [[ -z "$outside" ]] && echo none || echo "PROBLEM: $outside")"
  echo "-- the same with '$apart' (runbook 0.8's check that sets DeviceTests apart): $( [[ -z "$apart_out" ]] && echo "prints nothing" || echo "PROBLEM, it prints:"; printf '%s\n' "$apart_out" | grep . | sed 's/^/   /')"
} >> "$log"
[[ -z "$outside" && -z "$apart_out" ]] || status=1
merge_out="$(git merge-tree --write-tree --name-only --no-messages HEAD m0-decisions)"
merge_status=$?
tree="$(printf '%s\n' "$merge_out" | head -n 1)"
{
  echo
  echo "== 4. a merge of m0-decisions into HEAD, computed and not made (git merge-tree --write-tree --name-only --no-messages HEAD m0-decisions)"
  echo "   merge-tree exit: $merge_status (0: no conflict); merged tree: $tree"
  printf '%s\n' "$merge_out" | tail -n +2 | sed 's/^/   conflicting: /'
} >> "$log"
if [[ "$merge_status" == 0 ]]; then
  m_names="$(git diff --name-only "$run" "$tree" -- "${paths[@]}")"
  m_outside="$(printf '%s\n' "$m_names" | grep . | grep -v '^Spikes/G05-Recovery/DeviceTests/' || true)"
  m_apart="$(git diff --stat "$run" "$tree" -- "${paths[@]}" "$apart")"
  {
    echo "-- git diff --stat $run <the merged tree> -- <the paths>, as runbook 0.8 has the owner run it after that merge:"
    git diff --stat "$run" "$tree" -- "${paths[@]}" | sed 's/^/   /'
    echo "   of them, outside Spikes/G05-Recovery/DeviceTests: $( [[ -z "$m_outside" ]] && echo none || echo "PROBLEM: $m_outside")"
    echo "-- the same with '$apart': $( [[ -z "$m_apart" ]] && echo "prints nothing, so 0.8 still needs nothing after that merge" || echo "PROBLEM, it prints:"; printf '%s\n' "$m_apart" | grep . | sed 's/^/   /')"
  } >> "$log"
  [[ -z "$m_outside" && -z "$m_apart" ]] || status=1
else
  echo "   PROBLEM: the merge conflicts" >> "$log"; status=1
fi
{
  echo
  echo "== 5. Does the drop-in, or a file it runs, name the files the m0-exit-prep run changes?"
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
