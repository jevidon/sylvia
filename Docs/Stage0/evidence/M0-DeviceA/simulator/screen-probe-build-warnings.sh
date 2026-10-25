#!/bin/bash
# Lists the compiler warnings and errors in the full xcodebuild output that screen-probe.sh beside this file wrote under
# .build/scratch (not committed): the probe's test reads UIScreen.main, which iOS 26 deprecates, and the README says that
# this is a warning only. Read-only.
#   Docs/Stage0/evidence/M0-DeviceA/simulator/screen-probe-build-warnings.sh > Docs/Stage0/evidence/M0-DeviceA/simulator/screen-probe-build-warnings.txt
set -u
root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$root" || exit 1
logs=.build/scratch/m0-devicea-screen-probe
echo "command: Docs/Stage0/evidence/M0-DeviceA/simulator/screen-probe-build-warnings.sh"
echo "run: $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC), on the xcodebuild logs screen-probe.sh wrote in $logs"
status=0
for name in 13mini 11Pro 11 11ProMax SE2; do
  log="$logs/xcodebuild-Sylvia-M0-DeviceA-$name.log"
  echo
  if [[ ! -f "$log" ]]; then
    echo "== $log: missing"
    status=1
    continue
  fi
  echo "== $log ($(wc -l < "$log" | tr -d ' ') lines; its result line: $(grep -E '\*\* TEST (SUCCEEDED|FAILED) \*\*' "$log"))"
  echo "lines with \"error:\": $(grep -c 'error:' "$log")"
  echo "lines with \"warning:\": $(grep -c 'warning:' "$log")"
  grep -n 'warning:' "$log"
done
exit $status
