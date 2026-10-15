#!/usr/bin/env bash
# G0.3 review round 4: runs the tests added for each finding against the code with that finding's fix reverted, to
# show the tests fail without the fix (and so would have caught the defect). Evidence only; CI runs the tests against
# the fixed code (step 2 on host, step 6 on the simulator).
#
#   Spikes/G03-Intake/scripts/check-round4-before-fix.sh <log>
#
# Each case copies IntakeKit privately, reverts one fix (the code as it was at commit 937d53a, which the review
# examined; R4-04 keeps the new test seam so its test can run), runs the named tests with `swift test --filter`, and
# expects at least one of them to fail:
#   R4-01  a file group_id looked up without the pattern check (PackCanonicalEquivalenceTests)
#   R4-01  the writer's cleanFilename with Foundation's replacingOccurrences, found in the R4-01 audit (slash test)
#   R4-02  the 1 MiB pack manifest limit, and the share extension committing a handoff.json the app's scan refuses
#   R4-03  created_at converted with Foundation's Gregorian Calendar (the RFC 3339 tests)
#   R4-04  the stall timeout finishing the gate after work has begun (the stall-window test)
# Copies and builds live in a mktemp directory under .build, removed on exit.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
log="${1:?usage: check-round4-before-fix.sh <log>}"
mkdir -p "$(dirname "$log")"
log="$(cd "$(dirname "$log")" && pwd)/$(basename "$log")"
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"
mkdir -p "$SYLVIA_ROOT/.build"
work="$(mktemp -d "$SYLVIA_ROOT/.build/g03-before-fix.XXXXXX")"
trap 'rm -rf "$work"' EXIT

exec >"$log" 2>&1
echo "G0.3 review round 4: the new tests against the code with each fix reverted"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); commit $(git -C "$SYLVIA_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown); load: $(uptime)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"

mutate() {
  local file="$1" old="$2" new="$3"
  /usr/bin/python3 - "$file" "$old" "$new" <<'PY'
import pathlib, sys
path, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
count = text.count(old)
if count != 1:
    sys.exit(f"revert not applicable: {old!r} occurs {count} times in {path}")
path.write_text(text.replace(old, new), encoding="utf-8")
print(f"  reverted: {path.name}: {old!r} -> {new!r}")
PY
}

copy="$work/kit"
rsync -a --exclude .build --exclude .swiftpm "$kit/" "$copy/"
pristine() { for f in "$@"; do cp "$kit/Sources/$f" "$copy/Sources/$f"; done; }
failures=0

# run_tests <label> <swift test filter>: the tests must fail against the reverted code.
run_tests() {
  local label="$1" filter="$2" status=0
  (cd "$copy" && swift build --force-resolved-versions --build-tests 2>&1 | grep -E 'error:' | grep -v checkouts) && { echo "  build failed"; exit 1; }
  (cd "$copy" && swift test --force-resolved-versions --skip-build --filter "$filter") > "$work/$label.log" 2>&1 || status=$?
  grep -E '^(✘|✔) Test |recorded an issue|^[A-Za-z].*: .*(after|bytes|refused|accepted|received|apart)|Test run with' "$work/$label.log" \
    | grep -v -E '^◇' | cut -c1-400 | sed 's/^/  /' || true
  if (( status != 0 )); then
    echo "  FAILS WITHOUT THE FIX, as it should (swift test exit status $status)"
  else
    echo "  PASSED WITHOUT THE FIX: the tests do not show this defect"
    failures=$((failures + 1))
  fi
}

echo; echo "== R4-01: a file group_id looked up without the pattern check"
mutate "$copy/Sources/SylviaPack/PackManifest.swift" \
  '                guard PackManifest.isValidGroupID(groupID) else { throw PackRejection(.manifestInvalid, "files.group_id") }
' ''
run_tests r4-01-group-id 'PackCanonicalEquivalenceTests'
pristine SylviaPack/PackManifest.swift

echo; echo "== R4-01 audit: the writer's cleanFilename with Foundation's replacingOccurrences"
mutate "$copy/Sources/SylviaImportHandoff/HandoffWriter.swift" '        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars where scalar != "\u{0}" {
            scalars.append(scalar == "/" ? "_" : scalar)
        }
        var cleaned = String(scalars)' '        var cleaned = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\u{0}", with: "")'
run_tests r4-01-clean-filename 'slashBeforeCombiningMarkInName'
pristine SylviaImportHandoff/HandoffWriter.swift

echo; echo "== R4-02: the 1 MiB pack manifest limit"
mutate "$copy/Sources/SylviaPack/PackRules.swift" 'public var maxManifestBytes = 16 << 20' 'public var maxManifestBytes = 1 << 20'
run_tests r4-02-pack-limit 'entryLimitReachable'
pristine SylviaPack/PackRules.swift

echo; echo "== R4-02: the share extension commits a handoff.json the app's scan refuses"
mutate "$copy/Sources/SylviaImportHandoff/HandoffWriter.swift" \
  '        guard encoded.count <= HandoffManifest.maxBytes else { throw HandoffFailure.manifestTooLarge }
' ''
run_tests r4-02-handoff-limit 'HandoffWriterTests/manifestSize'
pristine SylviaImportHandoff/HandoffWriter.swift

echo; echo "== R4-03: created_at converted with Foundation's Gregorian Calendar"
mutate "$copy/Sources/SylviaIntakeCore/RFC3339.swift" '        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)' '        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let local = calendar.date(from: components) else { return nil }
        return local.addingTimeInterval(fraction - Double(offsetSeconds))'
run_tests r4-03-dates 'ContractFixtureTests/rfc3339'
pristine SylviaIntakeCore/RFC3339.swift

echo; echo "== R4-04: the stall timeout finishes the gate even after work has begun (the seam kept)"
mutate "$copy/Sources/SylviaImportHandoff/ItemProviderIntake.swift" \
  '                    if self.finish(.failure(HandoffFailure.providerTimedOut), onlyBeforeWork: true) { probe.cancel() }' \
  '                    probe.cancel()
                    self.finish(.failure(HandoffFailure.providerTimedOut))'
run_tests r4-04-stall 'stallTimeoutLosesToADeliveryInItsWindow'
pristine SylviaImportHandoff/ItemProviderIntake.swift

echo
echo "fixes whose tests passed without them: $failures of 6"
exit $(( failures == 0 ? 0 : 1 ))
