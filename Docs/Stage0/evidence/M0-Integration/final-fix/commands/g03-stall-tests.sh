#!/bin/bash
# The G0.3 stall tests after the M0 final fix (final review CC-02), on the host:
#   1. the suite "NSItemProvider intake and fallback" alone, five times, and the whole IntakeKit host suite three
#      times (the full suite is where two of thirteen runs failed under Xcode 27.1 before the fix), with the load and
#      the stall tests' own lines;
#   2. a control: a copy of IntakeKit (under .build/scratch, sources only) whose progress probe ignores the fraction
#      completed, the defect of report finding F13, must fail both stall tests.
# The tests play no audio. Writes only under .build/scratch and the log.
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/g03-stall-tests.sh <log>
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root" || exit 1
source Scripts/lib/env.sh
log="$1"
kit=Spikes/G03-Intake/IntakeKit
status=0
lines='Test run with|slow but moving provider:|progress then stall:|load progress follows|✘ Test "'
{
  echo "commit: $(git rev-parse HEAD); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$log"
for i in 1 2 3 4 5; do
  echo "== the suite alone, run $i ($(date -u +%H:%M:%SZ); load: $(sysctl -n vm.loadavg))" >> "$log"
  (cd "$kit" && xcrun swift test --force-resolved-versions --filter ItemProviderIntakeTests) > .build/scratch/g03-stall-run.log 2>&1 || status=1
  grep -E "$lines" .build/scratch/g03-stall-run.log | grep -v '^◇' >> "$log"
done
for i in 1 2 3; do
  echo "== the whole IntakeKit host suite, run $i ($(date -u +%H:%M:%SZ); load: $(sysctl -n vm.loadavg))" >> "$log"
  (cd "$kit" && xcrun swift test --force-resolved-versions) > .build/scratch/g03-stall-run.log 2>&1 || status=1
  grep -E "$lines" .build/scratch/g03-stall-run.log | grep -v '^◇' >> "$log"
done
copy=.build/scratch/g03-f13-mutant/IntakeKit
rm -rf "$(dirname "$copy")"
mkdir -p "$copy"
rsync -a --exclude .build --exclude .swiftpm "$kit/" "$copy/"
sed -i '' 's/fraction: progress.fractionCompleted)/fraction: 0)/' "$copy/Sources/SylviaImportHandoff/ItemProviderIntake.swift"
{
  echo "== control: the F13 defect (the probe ignores fractionCompleted) in a copy; both stall tests must fail"
  echo "changed lines in the copy: $(diff "$kit/Sources/SylviaImportHandoff/ItemProviderIntake.swift" "$copy/Sources/SylviaImportHandoff/ItemProviderIntake.swift" | grep -c '^>')"
} >> "$log"
(cd "$copy" && xcrun swift test --force-resolved-versions --filter ItemProviderIntakeTests) > .build/scratch/g03-f13-mutant.log 2>&1
mutant=$?
grep -E "$lines" .build/scratch/g03-f13-mutant.log | grep -v '^◇' >> "$log"
slow="$(grep -c '✘ Test "a provider whose progress keeps moving' .build/scratch/g03-f13-mutant.log || true)"
stop="$(grep -c '✘ Test "a provider that makes progress and then stops' .build/scratch/g03-f13-mutant.log || true)"
if [[ $mutant != 0 && $slow -gt 0 && $stop -gt 0 ]]; then
  echo "control: both stall tests failed against the F13 defect, as required" >> "$log"
else
  echo "control: NOT as required (exit $mutant; slow-but-moving failures $slow, progress-then-stall failures $stop)" >> "$log"
  status=1
fi
rm -rf "$(dirname "$copy")"
{
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "exit: $status"
} >> "$log"
exit $status
