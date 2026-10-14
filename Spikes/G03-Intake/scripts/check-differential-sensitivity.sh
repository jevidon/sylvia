#!/usr/bin/env bash
# G0.3: shows that the differential check (contract_differential.py, CI step 5) catches reader regressions, which a
# passing run alone cannot show (reviews R3-01, R3-02 and R4-01 to R4-05; report findings F16 and F18).
#
#   Spikes/G03-Intake/scripts/check-differential-sensitivity.sh <log>
#
# Each case builds sylviapack-tool from a private copy of IntakeKit with one deliberate defect and runs the current
# check against it. The check must fail, and its failures must name the cases the defect affects:
#   pack-dates-iso8601        the pack reader reads created_at with JSONDecoder's .iso8601 strategy (the R3-02 case)
#   handoff-dates-iso8601     the same in the handoff reader
#   nulls-accepted            the pack reader reads an explicit null in an optional member as absent (R3-01)
#   text-not-checked          the pack reader skips the strict JSON text check (R3-01)
#   uuid-not-canonical        the readers accept whatever UUID(uuidString:) accepts (R3-01)
#   separators-as-characters  every PathBytes test done with Swift String's Character-based operations (split, hasPrefix,
#                             contains, ==), as the readers did before F18
#   group-id-lookup-unchecked a file's group_id looked up without the pattern check, as before R4-01 (U+212A finds K)
#   dates-julian              created_at converted with Foundation's Gregorian Calendar, Julian before 1582-10-15 (R4-03)
#   manifest-size-unchecked   both readers without their manifest size limits (R4-02)
# Two earlier versions of the check run against a defect they missed, to show the blind spot each review found: the
# round 2 check against pack-dates-iso8601 (R3-02: it keyed reader verdicts by case name only, so the pack's date cases
# took the handoff reader's verdicts), and the round 3 check against group-id-lookup-unchecked (R4-01: none of its cases
# held a canonically equivalent identifier). Both are committed as files under sensitivity/, byte for byte as they
# were at commits 4b8c634 and 937d53a (their SHA-256 is checked below), so this script needs no git history and still
# runs after a squash merge (review R4-05).
# Copies, builds and outputs live in a mktemp directory under .build, removed on exit. Needs the large pack in the
# fixture cache (CI step 1) and network or a SwiftPM cache for the pinned ZIPFoundation.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
log="${1:?usage: check-differential-sensitivity.sh <log>}"
mkdir -p "$(dirname "$log")"
log="$(cd "$(dirname "$log")" && pwd)/$(basename "$log")"
spike="$SYLVIA_ROOT/Spikes/G03-Intake"
kit="$spike/IntakeKit"
frozen="$spike/scripts/sensitivity"
round2_check="$frozen/check-contract-instances-round2.sh"         # Spikes/G03-Intake/scripts/check-contract-instances.sh at 4b8c634
round2_sha="090b11f48fd8caf0af7a093c7ef2ffc97a1dd2e1c5c40a0d7612eae65982b25b"   # git blob a4376f494a0309a469753467d157ede052c9fd46
round3_check="$frozen/contract_differential-round3.py"            # Spikes/G03-Intake/scripts/contract_differential.py at 937d53a
round3_sha="00315308781cd3dd69baa3b1ee9b45757dee0c6eec0c9621ba07f2418fa96787"   # git blob 946db2553f4dc071d8088e6b2588b9c7f90557aa
mkdir -p "$SYLVIA_ROOT/.build"
work="$(mktemp -d "$SYLVIA_ROOT/.build/g03-sensitivity.XXXXXX")"
trap 'rm -rf "$work"' EXIT

exec >"$log" 2>&1
echo "G0.3 differential-check sensitivity"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); commit $(git -C "$SYLVIA_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown); load: $(uptime)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
for pair in "$round2_check $round2_sha" "$round3_check $round3_sha"; do
  read -r file sha <<<"$pair"
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$actual" == "$sha" ]] || { echo "frozen check changed: $file ($actual, expected $sha)"; exit 1; }
  echo "frozen check: $(basename "$file") sha256 $actual (as committed; unchanged)"
done

# Replaces `old` with `new` in `file`: exactly once, or every occurrence with "all". Fails if `old` is absent, so a
# defect that no longer applies to the code is reported instead of silently testing nothing.
mutate() {
  local file="$1" old="$2" new="$3" mode="${4:-once}"
  /usr/bin/python3 - "$file" "$old" "$new" "$mode" <<'PY'
import pathlib, sys
path, old, new, mode = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text(encoding="utf-8")
count = text.count(old)
if count == 0 or (mode == "once" and count != 1):
    sys.exit(f"defect not applicable: {old!r} occurs {count} times in {path}")
path.write_text(text.replace(old, new), encoding="utf-8")
print(f"  defect: {path.name}: {count} x {old!r} -> {new!r}")
PY
}

build_tool() {
  (cd "$1" && swift build --force-resolved-versions --configuration release --product sylviapack-tool 2>&1 | tail -1)
}

failures=0
# run_case <name> <kit copy> <regex of the failing lines that must appear>
run_case() {
  local name="$1" copy="$2" expected="$3" out status=0
  out="$work/out-$name"
  build_tool "$copy"
  sylvia_python "$spike/scripts/contract_differential.py" "$SYLVIA_ROOT/Contracts" "$out" "$copy/.build/release/sylviapack-tool" \
    > "$out.log" 2>&1 || status=$?
  local bad hit
  bad="$(grep -c -E '^  (MISMATCH|UNSOUND|UNEXPLAINED|INSTANT)' "$out.log" || true)"
  hit="$(grep -E '^  (MISMATCH|UNSOUND|UNEXPLAINED|INSTANT)' "$out.log" | grep -c -E "$expected" || true)"
  grep -E '^named (pack|handoff):|^random (pack|handoff):|^instants:|^differential:' "$out.log" | sed 's/^/  /'
  # Every failing case: named ones by name with both verdicts, random ones by file name, instants by date.
  grep -E '^  (MISMATCH|UNSOUND|UNEXPLAINED|INSTANT)' "$out.log" | cut -c1-200 | sed 's/^  /  failed: /'
  if (( status != 0 && hit > 0 )); then
    echo "  CAUGHT: exit status $status, $bad failing cases, $hit of them matching /$expected/"
  else
    echo "  MISSED: exit status $status, $bad failing cases, $hit matching /$expected/"
    failures=$((failures + 1))
  fi
}

# report_old_check <label> <output> <exit status>: an earlier check that the review found passing against a defect.
report_old_check() {
  local label="$1" output="$2" status="$3"
  grep -E '^differential:' "$output" | sed 's/^/  /'
  local bad
  bad="$(grep -c -E '^  (MISMATCH|UNSOUND|UNEXPLAINED)' "$output" || true)"
  echo "  the $label check's exit status: $status; failing cases: $bad"
  if (( status == 0 && bad == 0 )); then
    echo "  as the review found: the $label check passed against this defect"
  else
    echo "  NOTE: the $label check did not behave as the review described"
  fi
}

copy="$work/kit"
rsync -a --exclude .build --exclude .swiftpm "$kit/" "$copy/"
pristine() { cp "$kit/Sources/$1" "$copy/Sources/$1"; }

echo; echo "== pack-dates-iso8601"
mutate "$copy/Sources/SylviaPack/PackManifest.swift" "decoder.dateDecodingStrategy = RFC3339.decodingStrategy" \
  "decoder.dateDecodingStrategy = .iso8601"
run_case pack-dates-iso8601 "$copy" '^  [A-Z]+: pack created_at-'

echo; echo "== the round 2 check (commit 4b8c634; review R3-02), against the same pack-dates-iso8601 tool"
cp "$round2_check" "$work/old-check.sh"
mutate "$work/old-check.sh" 'source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"' "source \"$SYLVIA_ROOT/Scripts/lib/env.sh\""
mutate "$work/old-check.sh" 'kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"' "kit=\"$copy\""
mutate "$work/old-check.sh" 'work="$SYLVIA_ROOT/.build/g03-contract-check"' "work=\"$work/old-check-work\""
old_status=0
bash "$work/old-check.sh" > "$work/old-check.log" 2>&1 || old_status=$?
grep -E '^differential:' "$work/old-check.log" | sed 's/^/  /'
old_bad="$(grep -c -E '^  MISMATCH: pack created_at-' "$work/old-check.log" || true)"
echo "  the round 2 check's exit status: $old_status; MISMATCH lines for pack created_at cases: $old_bad"
if (( old_status == 0 && old_bad == 0 )); then
  echo "  as review R3-02 found: the round 2 check passed against a pack reader that reads created_at with .iso8601"
else
  echo "  NOTE: the round 2 check did not behave as review R3-02 described"
fi
pristine SylviaPack/PackManifest.swift

echo; echo "== handoff-dates-iso8601"
mutate "$copy/Sources/SylviaImportHandoff/HandoffManifest.swift" "decoder.dateDecodingStrategy = RFC3339.decodingStrategy" \
  "decoder.dateDecodingStrategy = .iso8601"
run_case handoff-dates-iso8601 "$copy" '^  [A-Z]+: handoff created_at-'
pristine SylviaImportHandoff/HandoffManifest.swift

echo; echo "== nulls-accepted"
mutate "$copy/Sources/SylviaPack/PackManifest.swift" "decodeIfPresentRejectingNull(" "decodeIfPresent(" all
run_case nulls-accepted "$copy" '^  [A-Z]+: pack null-'
pristine SylviaPack/PackManifest.swift

echo; echo "== text-not-checked"
mutate "$copy/Sources/SylviaPack/PackManifest.swift" "    public static func decode(_ data: Data) throws -> PackManifest {
        try StrictJSON.check(data)" "    public static func decode(_ data: Data) throws -> PackManifest {"
run_case text-not-checked "$copy" '^  [A-Z]+: pack (text|duplicate)-'
pristine SylviaPack/PackManifest.swift

echo; echo "== uuid-not-canonical"
mutate "$copy/Sources/SylviaIntakeCore/ContractDecoding.swift" "        let bytes = Array(text.utf8)
        guard bytes.count == 36 else { return nil }" "        return UUID(uuidString: text)
        let bytes = Array(text.utf8)
        guard bytes.count == 36 else { return nil }"
run_case uuid-not-canonical "$copy" '^  [A-Z]+: (pack pack_id|handoff (handoff|item)_id)-nul'
pristine SylviaIntakeCore/ContractDecoding.swift

echo; echo "== separators-as-characters (every PathBytes test with Swift String's Character-based operations, as before F18)"
pathbytes="$copy/Sources/SylviaIntakeCore/PathBytes.swift"
mutate "$pathbytes" 'path.utf8.split(separator: separator, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }' \
  'path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)'
mutate "$pathbytes" 'text.utf8.contains(separator)' 'text.contains("/")'
mutate "$pathbytes" 'text.utf8.first == separator' 'text.hasPrefix("/")'
mutate "$pathbytes" 'text.utf8.last == separator' 'text.hasSuffix("/")'
mutate "$pathbytes" 'let bytes = Array(component.utf8)
        return bytes == [dot] || bytes == [dot, dot]' 'return component == "." || component == ".."'
mutate "$pathbytes" 'text.utf8.starts(with: prefix.utf8)' 'text.hasPrefix(prefix)'
mutate "$pathbytes" 'text.utf8.reversed().starts(with: suffix.utf8.reversed())' 'text.hasSuffix(suffix)'
mutate "$pathbytes" 'a.utf8.elementsEqual(b.utf8)' 'a == b'
run_case separators-as-characters "$copy" '^  [A-Z]+: (pack path-hidden-separator|handoff original_filename-hidden-separator|handoff original_filename-separator-after)'
pristine SylviaIntakeCore/PathBytes.swift

echo; echo "== group-id-lookup-unchecked (a file's group_id looked up without the pattern check, as before R4-01)"
mutate "$copy/Sources/SylviaPack/PackManifest.swift" \
  '                guard PackManifest.isValidGroupID(groupID) else { throw PackRejection(.manifestInvalid, "files.group_id") }
' ''
run_case group-id-lookup-unchecked "$copy" '(^  [A-Z]+: pack group_id-kelvin-sign-on-(the-file|audiobook-members))|(^  UNSOUND: .*: pack fuzz-)'

echo; echo "== the round 3 check (commit 937d53a; review R4-01), against the same group-id-lookup-unchecked tool"
round3_status=0
sylvia_python "$round3_check" "$SYLVIA_ROOT/Contracts" "$work/out-round3" "$copy/.build/release/sylviapack-tool" \
  > "$work/round3.log" 2>&1 || round3_status=$?
report_old_check "round 3" "$work/round3.log" "$round3_status"
pristine SylviaPack/PackManifest.swift

echo; echo "== dates-julian (created_at converted with Foundation's Gregorian Calendar, as before R4-03)"
mutate "$copy/Sources/SylviaIntakeCore/RFC3339.swift" '        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)' '        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let local = calendar.date(from: components) else { return nil }
        return local.addingTimeInterval(fraction - Double(offsetSeconds))'
run_case dates-julian "$copy" '^  INSTANT: (pack|handoff) created_at-proleptic-'
pristine SylviaIntakeCore/RFC3339.swift

echo; echo "== manifest-size-unchecked (both readers without their manifest size limits, as before R4-02)"
mutate "$copy/Sources/SylviaPack/PackManifest.swift" 'guard data.count <= limits.maxManifestBytes else {' 'guard data.count <= Int.max else {'
mutate "$copy/Sources/SylviaImportHandoff/HandoffManifest.swift" 'data = try AtomicFile.readSmall(url, limit: maxBytes)' \
  'data = try AtomicFile.readSmall(url, limit: Int.max)'
run_case manifest-size-unchecked "$copy" '^  [A-Z]+: (pack|handoff) size-one-byte-over-the-limit'
pristine SylviaPack/PackManifest.swift
pristine SylviaImportHandoff/HandoffManifest.swift

echo
echo "defects missed: $failures of 9"
exit $(( failures == 0 ? 0 : 1 ))
