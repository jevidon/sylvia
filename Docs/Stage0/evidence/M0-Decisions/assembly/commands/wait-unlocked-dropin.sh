#!/bin/bash
# The assembly of the M0 decisions round (22 October 2026): waits for the build Mac's screen to be unlocked, reading its
# lock state read-only (ioreg, lock-state.sh) every <seconds>, at most <readings> times, appending each reading to
# .build/scratch/assembly-lock-state.log (outside the tracked tree, so the checks that need a clean tree can run while
# it waits; the assembly copies it to Docs/Stage0/evidence/M0-Decisions/assembly/lock-state.log at its end); at the first reading that shows the screen unlocked it runs
# run-dropin-clean.sh <name> (G0.5 recovery's drop-in from clean, which needs the unlocked screen for its class-B tests)
# and stops. No agent unlocks the Mac; if no reading shows it unlocked, nothing runs, and the log says so. The state
# file .build/scratch/dropin-waiter.state reads "waiting", "running <name>" or "done <exit status>", so other CI runs in
# this checkout can wait for it instead of sharing .build/ci-logs with it.
#   Docs/Stage0/evidence/M0-Decisions/assembly/commands/wait-unlocked-dropin.sh <name> <readings> <seconds>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"; readings="$2"; pause="$3"
log=.build/scratch/assembly-lock-state.log
state=.build/scratch/dropin-waiter.state
mkdir -p .build/scratch
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
echo "waiting" > "$state"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ) wait-unlocked-dropin.sh $*: up to $readings readings, $pause s apart" >> "$log"
for ((i = 0; i < readings; i++)); do
  reading="$(lock_state)"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $reading" >> "$log"
  if [[ "$reading" == unlocked* ]]; then
    echo "running $name" > "$state"
    echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ) unlocked: running run-dropin-clean.sh $name" >> "$log"
    Docs/Stage0/evidence/M0-Decisions/assembly/commands/run-dropin-clean.sh "$name"
    status=$?
    echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ) run-dropin-clean.sh $name exit $status" >> "$log"
    echo "done $status" > "$state"
    exit "$status"
  fi
  (( i + 1 < readings )) && sleep "$pause"
done
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ) no reading showed the screen unlocked; the drop-in was not run" >> "$log"
echo "done not-run" > "$state"
exit 3
