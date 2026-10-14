#!/usr/bin/env bash
# M0 device runbook: runs every check behind the runbook from a clean tree (no build products, no generated
# projects) and keeps one log of the run: the build Mac's state, the help text of the tool options the runbook
# relies on, the device-build check, the test-filter check on this job's own simulator, the check that the texts
# Section 8's corrections replace occur in their files, and Scripts/ci.sh contracts as a consistency check (the
# runbook changes no contract), whose validator output it copies to contracts.log.
# Nothing is installed on, launched on or copied to a physical device. Environment: host and simulator.
# Exit status: 0 only when every step exits 0 (the device-build step exits 0 only when every check ran as
# expected); otherwise 1, after every step has run. The log's last line gives the count.
#
#   Docs/Stage0/evidence/M0-runbook/commands/clean-run.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$ROOT"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh

EVID="Docs/Stage0/evidence/M0-runbook"
LOG="$EVID/clean-run.log"
products() {
  find . -type d \( -name DerivedData -o -name 'DerivedData-*' -o -name '*.xcodeproj' \) -prune -print 2>/dev/null \
    | grep -v '^\./\.build' | sort
  find . -type d -name '.build' -prune -print 2>/dev/null | grep -v '^\./\.build$' | sort
}
{
  echo "# M0 runbook checks: clean run"
  echo "# commit: $(git -C "$ROOT" rev-parse HEAD); changed tracked files before the run: $(git -C "$ROOT" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
  echo "# started $(date -u +%Y-%m-%dT%H:%M:%SZ) on host macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | tr '\n' ' ')"
  echo "# load at start: $(uptime | sed 's/.*load averages*: //'); booted simulators: $(xcrun simctl list devices booted | grep -c Booted)"
  echo "# build products and generated projects at start (expected none):"
  products | sed 's/^/#   /'
  echo "#   (end of list)"
} > "$LOG.header"   # the log is a tracked file: rewrite it only after the change count above
mv "$LOG.header" "$LOG"

FAILED_STEPS=0
step() {
  local name="$1"
  shift
  echo >> "$LOG"
  echo "== $name: $*" >> "$LOG"
  local t0=$SECONDS
  "$@" >> "$LOG" 2>&1
  local rc=$?
  echo "== $name: exit $rc after $((SECONDS - t0)) s; load: $(uptime | sed 's/.*load averages*: //')" >> "$LOG"
  (( rc == 0 )) || FAILED_STEPS=$((FAILED_STEPS + 1))
}

step build-mac-state bash -c "'$EVID/commands/build-mac-state.sh' > '$EVID/build-mac-state.txt' && echo 'written $EVID/build-mac-state.txt'"
step tool-help bash -c "'$EVID/commands/tool-help.sh' > '$EVID/tool-help.txt' && echo 'written $EVID/tool-help.txt'"
step device-builds "$EVID/commands/verify-device-builds.sh"
step test-filters "$EVID/commands/check-only-testing-ids.sh"
step correction-texts bash -c "python3 -I '$EVID/commands/check-correction-texts.py' > '$EVID/correction-texts.log'; rc=\$?; echo 'written $EVID/correction-texts.log'; exit \$rc"
step contracts Scripts/ci.sh contracts
{
  echo "# Scripts/ci.sh contracts (Scripts/ci.d/10-contracts.sh), run as the last step of commands/clean-run.sh"
  echo "# clean run: $(sed -n '2p' "$LOG" | sed 's/^# //'); validator output copied from .build/ci-logs/10-contracts.log"
  cat .build/ci-logs/10-contracts.log
} > "$EVID/contracts.log"

{
  echo
  echo "# finished $(date -u +%Y-%m-%dT%H:%M:%SZ); load at end: $(uptime | sed 's/.*load averages*: //')"
  echo "# steps that exited non-zero: $FAILED_STEPS"
} >> "$LOG"
cat "$LOG"
(( FAILED_STEPS == 0 ))
