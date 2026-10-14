#!/bin/bash
# ADR-0014 evidence: run the dependency-lock CI drop-in from a clean tree and write its log.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/ci-clean.sh
#
# Deletes this checkout's build products (every .build directory, DerivedData included, and the generated .xcodeproj
# bundles under Apps/, Packages/ and Spikes/; it refuses if any holds a tracked file), then runs
# `Scripts/ci.sh dependency-lock` and writes the run, the drop-in's own log and the load before and after to
# Docs/Stage0/evidence/M0-dependencies/ci-12-dependency-lock.log. Host only; no network, no simulator.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
source "$ROOT/Scripts/lib/sim.sh"
source "$ROOT/Scripts/lib/xcodegen.sh"
cd "$ROOT" || exit 1
LOG=Docs/Stage0/evidence/M0-dependencies/ci-12-dependency-lock.log

victims=$(find Apps Packages Spikes \( -name .build -o -name '*.xcodeproj' -o -name DerivedData \) -prune -print | sort)
for v in $victims; do
  if [[ -n "$(git ls-files -- "$v" | head -1)" ]]; then echo "refusing: $v has tracked files" >&2; exit 2; fi
done
(
  echo "Scripts/ci.sh dependency-lock from a clean tree, $(date -u +%Y-%m-%dT%H:%M:%SZ), at commit $(git rev-parse HEAD) (commands/ci-clean.sh)"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "load before: $(uptime)"
  echo "build products deleted before the run (none tracked): ${victims:-none present}"
  rm -rf $victims "$ROOT/.build/ci-logs"
  others="$(git status --porcelain --untracked-files=no | grep -v -F "$LOG" || true)"
  echo "tracked files modified, other than this log (which this run rewrites): ${others:-none}"
  echo
  echo "=== Scripts/ci.sh dependency-lock"
  Scripts/ci.sh dependency-lock
  status=$?
  echo "exit status: $status"
  echo "load after: $(uptime)"
  echo
  echo "=== .build/ci-logs/12-dependency-lock.log"
  cat "$ROOT/.build/ci-logs/12-dependency-lock.log"
  echo
  echo "after the run, build products under Apps/, Packages/ and Spikes/: $(find Apps Packages Spikes \( -name .build -o -name '*.xcodeproj' \) -prune -print | wc -l | tr -d ' ')"
  exit $status
) > "$LOG" 2>&1
status=$?
tail -n 5 "$LOG"
exit $status
