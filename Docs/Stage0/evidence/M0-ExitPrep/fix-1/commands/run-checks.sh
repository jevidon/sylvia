#!/bin/bash
# The checks of the fix of the review of the M0 exit preparation (26 October 2026; integration log section 31), run on
# its last documents commit with no uncommitted file. Every log goes into <out-dir>, outside the tree, so that the tree
# stays clean while they run (the amendments' runner refuses an unclean tree); the logs are then committed in this
# folder (its README lists them), and this fix's gate checks (gate-checks.sh beside this file) run on that commit.
#   Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands/run-checks.sh <out-dir> [<extraction dir of the review records>]
# 1. The drop-ins the fix feeds: `Scripts/ci.sh contracts hard-rules` (00-git-lfs, 10-contracts,
#    11-capture-anchor-contracts and 13-hard-rules, whose audit reads every committed and new file, this fix's scripts
#    and logs among them), each drop-in's log copied; and `Scripts/ci.sh dependency-lock` from a clean tree, as the Zip
#    guard's ci-checks.sh ran it: every build product under Apps/, Packages/ and Spikes/ (.build, DerivedData, generated
#    .xcodeproj bundles) deleted first, refusing if one holds a tracked file, then the drop-in's self-test and
#    `check --toolchain`; its log holds the console, the drop-in's whole log, its time and the load before and after.
# 2. The checks under Docs/Stage0/evidence/ that read what this fix changed, unchanged: the assembly's runbook content
#    check (the runbook's Who wrote it has a note) with its controls, limits and step coverage; the follow-up's fix's
#    amendments checks with their mutations and controls (ADR-0014's Consequences); the review records' own checks
#    (the gate summary's Section 6.2 last row and ADR-0014's pointer line among the texts they read); and the
#    assembly's check-xcode-reading.py and recheck-exit-prep.py, which must report exactly its group R6, by design (the
#    State line no longer says that the exit preparation has not been reviewed; the gate checks check the report).
# 3. This fix's recheck (recheck-fix-1.py beside this file).
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>. Exit 1 if any check is not as
# expected.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:?usage: run-checks.sh <out-dir> [<extraction dir>]}"
extraction="${2:-}"
here=Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands
asm=Docs/Stage0/evidence/M0-ExitPrep/assembly/commands
items=Docs/Stage0/evidence/M0-Integration/item-reviews/commands
logged=Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh
dec=Docs/Stage0/evidence/M0-Decisions
mkdir -p "$out/ci-logs"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
echo "run-checks: HEAD $head, uncommitted paths: $dirty; logs in $out; start $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
[[ "$dirty" == 0 ]] || { echo "refused: run on a clean tree"; exit 2; }
status=0
run() {  # <log name> <command...>
  local name="$1"; shift
  "$@" > "$out/$name" 2>&1
  local s=$?
  echo "$name: exit $s"
  return $s
}
header() {
  echo "$1, $(date -u +%Y-%m-%dT%H:%M:%SZ), at commit $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD))"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "uncommitted paths: $(git status --porcelain | wc -l | tr -d ' '); LFS files still pointer files: $(git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' ')"
  echo "load before: $(uptime)"
}

# 1. The drop-ins.
{
  header "Scripts/ci.sh contracts hard-rules"
  echo
  start=$SECONDS
  Scripts/ci.sh contracts hard-rules
  code=$?
  echo "ci.sh exit: $code ($((SECONDS - start)) s)"
  echo "load after: $(uptime)"
} > "$out/ci-contracts-hard-rules.log" 2>&1
echo "ci-contracts-hard-rules.log: exit $code"
(( code != 0 )) && status=1
for name in 00-git-lfs 10-contracts 11-capture-anchor-contracts 13-hard-rules; do
  [[ -f ".build/ci-logs/$name.log" ]] && cp ".build/ci-logs/$name.log" "$out/ci-logs/$name.log"
done
victims=$(find Apps Packages Spikes \( -name .build -o -name '*.xcodeproj' -o -name DerivedData \) -prune -print | sort)
for v in $victims; do
  if [[ -n "$(git ls-files -- "$v" | head -1)" ]]; then echo "refusing: $v has tracked files"; exit 2; fi
done
{
  header "Scripts/ci.sh dependency-lock from a clean tree"
  echo "build products deleted before the run (none tracked): $(echo $victims | wc -w | tr -d ' ')"
  rm -rf $victims "$root/.build/ci-logs"
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
  cat "$root/.build/ci-logs/12-dependency-lock.log"
} > "$out/12-dependency-lock.log" 2>&1
echo "12-dependency-lock.log: exit $code"
(( code != 0 )) && status=1

# 2. The documents checks that read what this fix changed.
run runbook-content-check.log "$logged" "$dec/assembly/commands/runbook-content-check.sh" || status=1
run check-amendments.log "$dec/followup/round-2/commands/run-checks.sh" "$head" || status=1
if [[ -n "$extraction" ]]; then
  run check-item-reviews.log "$logged" python3 -I "$items/item-reviews.py" check --extraction "$extraction" || status=1
else
  run check-item-reviews.log "$logged" python3 -I "$items/item-reviews.py" check || status=1
fi
run render-check.log "$logged" python3 -I "$items/item-reviews.py" render --check || status=1
run audit-probe.log "$logged" "$items/audit-probe.sh" || status=1
run check-xcode-reading.log "$logged" python3 -I "$asm/check-xcode-reading.py" "$root" || status=1
"$logged" python3 -I "$asm/recheck-exit-prep.py" "$root" > "$out/recheck-exit-prep.log" 2>&1
code=$?
reported="$(grep -E '^PROBLEM ' "$out/recheck-exit-prep.log" | sed -E 's/^PROBLEM +([A-Z0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
echo "recheck-exit-prep.log: exit $code (1 expected, reporting exactly R6, by design); reported: ${reported:-none}"
[[ $code == 1 && "$reported" == R6 ]] || status=1

# 3. This fix's recheck.
run recheck-fix-1.log "$logged" python3 -I "$here/recheck-fix-1.py" "$root" || status=1
echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths; end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
