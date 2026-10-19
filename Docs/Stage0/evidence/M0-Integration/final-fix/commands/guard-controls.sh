#!/bin/bash
# Controls for two fixes of the M0 final fix, on the host, each with its defect put back in a copy under .build/scratch:
#   1. G0.2's trust guards (final review CC-01): Spikes/G02-Transfer/Scripts/trust-guards.py --self-test must pass, and
#      a copy that skips any directory whose absolute path holds "/.build/" (the old filter's behaviour) must fail it.
#   2. G0.5 recovery's protector (final review SEC-06): DataProtectionTests.unsupportedClassRefused must pass, and a copy
#      of the package without the two `try requireSupportedClass()` calls (in ensureDirectory and protect) must fail it.
# Nothing plays audio and no simulator is used. Writes only under .build/scratch and the log.
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/guard-controls.sh <log>
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root" || exit 1
source Scripts/lib/env.sh
log="$1"
status=0
work=.build/scratch/guard-controls
rm -rf "$work"
mkdir -p "$work"
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD); uncommitted files: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. G0.2 trust guards: the self-test, then a copy with the absolute-path filter"
} > "$log"
spike="$root/Spikes/G02-Transfer"
/usr/bin/python3 -I "$spike/Scripts/trust-guards.py" --self-test "$spike" "$root/$work/tg" > "$work/tg.out" 2>&1
tg=$?
grep -E '^(ok|FAIL|self-test)' "$work/tg.out" >> "$log"
echo "exit: $tg" >> "$log"
(( tg != 0 )) && status=1
mutant="$work/trust-guards-absolute-filter.py"
awk '{print} /subdirectories\[:\] = sorted\(d for d in subdirectories if d not in SKIPPED_DIRECTORIES\)/ {print "        if \"/.build/\" in directory + \"/\": continue"}' \
  "$spike/Scripts/trust-guards.py" > "$mutant"
echo "-- the copy differs in $(diff "$spike/Scripts/trust-guards.py" "$mutant" | grep -c '^>') added line: $(diff "$spike/Scripts/trust-guards.py" "$mutant" | grep '^>' | sed 's/^> *//')" >> "$log"
/usr/bin/python3 -I "$mutant" --self-test "$spike" "$root/$work/tg-mutant" > "$work/tg-mutant.out" 2>&1
tgm=$?
grep -E '^(ok|FAIL|self-test)' "$work/tg-mutant.out" >> "$log"
echo "exit: $tgm" >> "$log"
if (( tgm == 0 )); then
  echo "control: NOT as required (the copy with the old filter passed the self-test)" >> "$log"; status=1
else
  echo "control: the copy with the old filter fails the self-test, as required" >> "$log"
fi
{
  echo
  echo "== 2. G0.5 recovery protector: unsupportedClassRefused, then a copy without the guard on the directory and protect paths"
} >> "$log"
pkg=Spikes/G05-Recovery
(cd "$pkg" && xcrun swift test --force-resolved-versions --filter unsupportedClassRefused) > "$work/g05.out" 2>&1
g05=$?
grep -E '✔ Test "|✘ Test "|Test run with' "$work/g05.out" | grep -v '^◇' >> "$log"
echo "exit: $g05" >> "$log"
(( g05 != 0 )) && status=1
copy="$work/G05-Recovery"
rsync -a --exclude .build --exclude .swiftpm "$pkg/" "$copy/"
source_file="$copy/Sources/SylviaRecovery/FileProtection.swift"
calls_before="$(grep -c 'try requireSupportedClass()' "$source_file")"
sed -i '' '/^        try requireSupportedClass()$/d' "$source_file"
calls_after="$(grep -c 'try requireSupportedClass()' "$source_file" || true)"
echo "-- the copy: 'try requireSupportedClass()' calls $calls_before before, $calls_after after" >> "$log"
(cd "$copy" && xcrun swift test --force-resolved-versions --filter unsupportedClassRefused) > "$work/g05-mutant.out" 2>&1
g05m=$?
grep -E '✘ Test "|Test run with' "$work/g05-mutant.out" | grep -v '^◇' | sed -E 's/(recorded an issue at [^:]+:[0-9]+:[0-9]+): .*/\1/' | sort -u >> "$log"
echo "exit: $g05m" >> "$log"
if (( g05m == 0 )) || [[ "$calls_before" != 2 || "$calls_after" != 0 ]]; then
  echo "control: NOT as required" >> "$log"; status=1
else
  echo "control: the copy without the guard fails unsupportedClassRefused, as required" >> "$log"
fi
rm -rf "$work"
{
  echo
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "exit: $status"
} >> "$log"
exit $status
