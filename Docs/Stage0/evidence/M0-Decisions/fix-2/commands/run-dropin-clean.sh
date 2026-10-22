#!/bin/bash
# The second fix of the decisions round (23 October 2026 on the build Mac's clock; integration log section 19): G0.5
# recovery's drop-in (Scripts/ci.d/71-g05-recovery.sh, with its steps 13-15 for the lock harness, the UI smoke test of
# step 14 among them) from clean, through Scripts/ci.sh, on the current commit of branch m0-decisions, with this
# round's simulator, Sylvia-M0-dec-fix-2 (iPhone 17, iOS 26.5; created by the drop-in if missing, and deleted at the
# end of the round). The successor of Docs/Stage0/evidence/M0-Decisions/fix-1/commands/run-dropin-clean.sh, with the
# same steps: it deletes the spike's and the harness's build products and derived data first
# (Spikes/G05-Recovery/.build, Spikes/G05-Recovery/LockHarness/.build, .build/g05-recovery) and records the commit, the
# screen lock state (ioreg, read-only), the load at the start and the end, and the drop-in's step headers and verdict
# lines. Never sets G05_ALLOW_MISSING_CLASS_B: with the screen locked the drop-in stops at its row-10 guard after its
# host tests, and this run then says so. Every player in the harness's tests and its app plays at the test volume
# (0.01) the harness's configuration sets.
#   Docs/Stage0/evidence/M0-Decisions/fix-2/commands/run-dropin-clean.sh <name>
# Logs: Docs/Stage0/evidence/M0-Decisions/fix-2/<name>/console.log, the drop-in's step logs in <name>/logs/ and its
# whole output in <name>/71-g05-recovery.log.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
out="Docs/Stage0/evidence/M0-Decisions/fix-2/$name"
sim=Sylvia-M0-dec-fix-2
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
# Counted before this run deletes or writes anything, so its own logs are not counted.
uncommitted="$(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
rm -rf Spikes/G05-Recovery/.build Spikes/G05-Recovery/LockHarness/.build .build/g05-recovery "$out"
mkdir -p "$out/logs"
console="$out/console.log"
{
  echo "command: Docs/Stage0/evidence/M0-Decisions/fix-2/commands/run-dropin-clean.sh $*"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files before the run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "deleted before the run: Spikes/G05-Recovery/.build Spikes/G05-Recovery/LockHarness/.build .build/g05-recovery"
  echo "simulator name $sim (iPhone 17, iOS 26.5; created by the drop-in if missing); G05_LOG_DIR=$out/logs"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$console"
G05_LOG_DIR="$root/$out/logs" G05_SIM_NAME="$sim" Scripts/ci.sh g05-recovery >> "$console" 2>&1
status=$?
perl -pe 's/\e\[[0-9;]*m//g' .build/ci-logs/71-g05-recovery.log > "$out/71-g05-recovery.log"
{
  echo "ci.sh exit: $status"
  echo "---- 71-g05-recovery.log: step headers, warnings and verdict lines (the step logs hold the rest)"
  grep -E "^(=== |WARNING|FAIL|row 10|G0\.5 recovery|simulator |ok: |ok    |originHash|result: |== G05LockHarness)|Test run with|Test Suite 'LockHarnessSmokeUITests' (passed|failed)|\*\* (TEST|BUILD)" "$out/71-g05-recovery.log" || true
  echo "---- end"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "git status --porcelain lines after the run: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
} >> "$console"
exit $status
