#!/bin/bash
# The assembly of the M0 decisions round (22 October 2026; integration log section 17): the lock harness's checks alone
# (Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh: steps 13-15 of Scripts/ci.d/71-g05-recovery.sh) from
# clean, on the current commit of branch m0-decisions, with this job's simulator, Sylvia-M0-dec-assembly: the lock
# against the package's, the unit tests on the iOS 26.5 simulator, and the app built for a generic iOS device with
# automatic signing (build only; nothing installed on or run on a device). This is not a run of the drop-in:
# run-dropin-clean.sh beside it is. The successor, for the assembled branch, of
# Docs/Stage0/evidence/M0-Decisions/harness/commands/run-harness-checks-clean.sh, with the same steps: it deletes the
# harness's build products and derived data first (Spikes/G05-Recovery/LockHarness/.build) and records the commit, the
# screen lock state (ioreg, read-only) and the load at the start and the end.
#   Docs/Stage0/evidence/M0-Decisions/assembly/commands/run-harness-checks-clean.sh <name>
# Logs: Docs/Stage0/evidence/M0-Decisions/assembly/<name>/console.log, and the step logs beside it
# (harness-lock.log, harness-simulator-tests.log, harness-device-build.log, harness-device-signing.txt).
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
out="Docs/Stage0/evidence/M0-Decisions/assembly/$name"
sim=Sylvia-M0-dec-assembly
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
uncommitted="$(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
rm -rf Spikes/G05-Recovery/LockHarness/.build "$out"
mkdir -p "$out"
console="$out/console.log"
{
  echo "command: Docs/Stage0/evidence/M0-Decisions/assembly/commands/run-harness-checks-clean.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files before the run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "deleted before the run: Spikes/G05-Recovery/LockHarness/.build; simulator name $sim (iPhone 17, iOS 26.5)"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$console"
full="$root/.build/scratch/$name-output.log"
mkdir -p "$(dirname "$full")"
G05_LOG_DIR="$root/$out" G05_SIM_NAME="$sim" Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh > "$full" 2>&1
status=$?
{
  echo "---- harness-checks.sh output: step headers, results and verdict lines (the whole output is in the step logs)"
  perl -pe 's/\e\[[0-9;]*m//g' "$full" | grep -vE '^ {4}|^[A-Z][A-Za-z]+ .*\(in target ' \
    | grep -E '^(=== |ok: |originHash|MISMATCH|  [a-z.]+: |simulator |host: |FAIL|# |== |Identifier=|Authority=|TeamIdentifier=|profile |-- |"|[0-9]+ => |\]|no Apple Development|G0\.5 recovery lock harness)|Test run with|\*\* (TEST|BUILD)' || true
  echo "---- end"
  echo "harness-checks.sh exit: $status"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "git status --porcelain lines after the run: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
} >> "$console"
exit $status
