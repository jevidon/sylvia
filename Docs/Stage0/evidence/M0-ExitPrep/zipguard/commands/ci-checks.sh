#!/bin/bash
# The CI drop-ins that the fix of ADR-0014's review round 4 feeds, on this checkout's commit with no uncommitted file:
#
#   Docs/Stage0/evidence/M0-ExitPrep/zipguard/commands/ci-checks.sh <folder under Docs/Stage0/evidence/M0-ExitPrep/zipguard>
#
# 1. `Scripts/ci.sh contracts hard-rules`: 00-git-lfs (which ci.sh runs first in every run), 10-contracts,
#    11-capture-anchor-contracts and 13-hard-rules (the hard-rule audit reads every committed and new file, the check and
#    the new evidence scripts among them). Console: <folder>/ci-contracts-hard-rules.log; each drop-in's log in
#    <folder>/ci-logs/.
# 2. `Scripts/ci.sh dependency-lock` from a clean tree, as Docs/Stage0/evidence/M0-dependencies/commands/ci-clean.sh does
#    it (that script writes over the committed Xcode 27.0-era log, so this one writes here instead): every build
#    product under Apps/, Packages/ and Spikes/ (.build, DerivedData, the generated .xcodeproj bundles) is deleted
#    first, refusing if one holds a tracked file, then the drop-in runs its self-test and `check --toolchain`.
#    Console, the drop-in's whole log, its time and the load before and after: <folder>/12-dependency-lock.log.
# Host only; no network, no simulator.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
OUT="Docs/Stage0/evidence/M0-ExitPrep/zipguard/${1:?usage: ci-checks.sh <folder>}"
mkdir -p "$OUT/ci-logs"
status=0
header() {
  echo "$1, $(date -u +%Y-%m-%dT%H:%M:%SZ), at commit $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD))"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "uncommitted tracked files: $(git status --porcelain --untracked-files=no | wc -l | tr -d ' '); LFS files still pointer files: $(git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' ')"
  echo "load before: $(uptime)"
}
{
  header "Scripts/ci.sh contracts hard-rules"
  echo
  start=$SECONDS
  Scripts/ci.sh contracts hard-rules
  code=$?
  echo "ci.sh exit: $code ($((SECONDS - start)) s)"
  echo "load after: $(uptime)"
} > "$OUT/ci-contracts-hard-rules.log" 2>&1
(( code != 0 )) && status=1
for name in 00-git-lfs 10-contracts 11-capture-anchor-contracts 13-hard-rules; do
  [[ -f ".build/ci-logs/$name.log" ]] && cp ".build/ci-logs/$name.log" "$OUT/ci-logs/$name.log"
done
victims=$(find Apps Packages Spikes \( -name .build -o -name '*.xcodeproj' -o -name DerivedData \) -prune -print | sort)
for v in $victims; do
  if [[ -n "$(git ls-files -- "$v" | head -1)" ]]; then echo "refusing: $v has tracked files" >&2; exit 2; fi
done
{
  header "Scripts/ci.sh dependency-lock from a clean tree"
  echo "build products deleted before the run (none tracked): $(echo $victims | wc -w | tr -d ' ')"
  rm -rf $victims "$ROOT/.build/ci-logs"
  echo "build products under Apps/, Packages/ and Spikes/ now: $(find Apps Packages Spikes \( -name .build -o -name '*.xcodeproj' -o -name DerivedData \) -prune -print | wc -l | tr -d ' ')"
  echo
  echo "=== Scripts/ci.sh dependency-lock"
  start=$SECONDS
  Scripts/ci.sh dependency-lock
  code=$?
  echo "ci.sh exit: $code ($((SECONDS - start)) s)"
  echo "load after: $(uptime)"
  echo
  echo "=== .build/ci-logs/12-dependency-lock.log"
  cat "$ROOT/.build/ci-logs/12-dependency-lock.log"
} > "$OUT/12-dependency-lock.log" 2>&1
(( code != 0 )) && status=1
tail -n 3 "$OUT/ci-contracts-hard-rules.log"
grep -E '^ci.sh exit|^dependency lock check|^self-test:' "$OUT/12-dependency-lock.log" | cut -c 1-200
exit $status
