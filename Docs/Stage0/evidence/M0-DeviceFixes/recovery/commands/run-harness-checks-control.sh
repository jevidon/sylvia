#!/bin/bash
# Control for the lock harness's quiet-tone failure: the same harness checks (harness-checks.sh, the drop-in's steps
# 13-15 alone) on the code before this branch's changes, in the same environment. The files of
# Scripts/lib and Spikes/G05-Recovery at <commit> (default c72247a6, m0-decisions when this branch was made) are
# taken with git archive into .build/scratch/control-<commit>/ (no checkout, no change to this worktree), and that
# copy's harness-checks.sh runs with this job's simulator and a log folder of its own.
#   Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-harness-checks-control.sh <name> [<commit>]
# Logs: Docs/Stage0/evidence/M0-DeviceFixes/recovery/<name>/console.log and the harness's logs in <name>/logs/.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
commit="${2:-c72247a69a374ce361834550b92689b4abab95ee}"
out="$root/Docs/Stage0/evidence/M0-DeviceFixes/recovery/$name"
control="$root/.build/scratch/control-${commit:0:8}"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
rm -rf "$out" "$control"
mkdir -p "$out/logs" "$control"
git -C "$root" archive --format=tar -o "$control.tar" "$commit" Scripts/lib Spikes/G05-Recovery || exit 1
tar -xf "$control.tar" -C "$control" && rm -f "$control.tar"
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/run-harness-checks-control.sh $*"
  echo "control tree: Scripts/lib and Spikes/G05-Recovery of $commit, in .build/scratch/control-${commit:0:8}/"
  echo "this worktree: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$out/console.log"
G05_LOG_DIR="$out/logs" G05_SIM_NAME=Sylvia-M0-devfix-recovery "$control/Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh" >> "$out/console.log" 2>&1
status=$?
{
  echo "harness-checks.sh (control) exit: $status"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$out/console.log"
exit $status
