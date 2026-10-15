#!/usr/bin/env bash
# G0.6 design package (plan 4.4, 20.1, 22.2; ADR-0013): design lint and its self-test, token export
# drift check, design-token fixture check, contrast checks over the export (Python) and the token
# definitions (Swift), then the SylviaDesign tests on the macOS host and on the iOS simulator
# Sylvia-M0-g06-design (iPhone 17, iOS 26.5; $SYLVIA_G06_SIM overrides the name). On the simulator this includes the component snapshot
# suite in verify mode (a missing or different reference fails), the T53 grayscale proxies, the T51
# layout audit and the accessibility-tree checks, followed by a negative check that changed
# references (one color, one grayscale) really fail the snapshot suite.
#
# Outputs (logs, contrast tables, T51/T53 tables, accessibility tree, symbol renders) go to
# $SYLVIA_G06_EVIDENCE_DIR, default .build/ci-logs/g06-design. Set it to
# Docs/Stage0/evidence/G06-Design to refresh the committed evidence. Exits non-zero on any failure,
# any skipped test, a run with no tests or a compiler warning in Packages/Design.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"

EVIDENCE="${SYLVIA_G06_EVIDENCE_DIR:-$SYLVIA_ROOT/.build/ci-logs/g06-design}"
mkdir -p "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd)"
PACKAGE="$SYLVIA_ROOT/Packages/Design"
DERIVED="$PACKAGE/.build/DerivedData"
SNAPSHOTS="$PACKAGE/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests"
# Each job uses its own simulator (ADR-0002): set SYLVIA_G06_SIM to run on another one. The
# snapshot references compare only on an iPhone 17 with iOS 26.5 (RecordingDevice), whatever its name.
SIM_NAME="${SYLVIA_G06_SIM:-Sylvia-M0-g06-design}"

step() { echo; echo "--- $* ($(date -u +%Y-%m-%dT%H:%M:%SZ))"; }

step "toolchain"
sylvia_check_xcode || true
xcodebuild -version
xcrun swift --version 2>&1 | head -1

step "design lint self-test (Scripts/lint-design.py self-test)"
sylvia_python "$SYLVIA_ROOT/Scripts/lint-design.py" self-test | tee "$EVIDENCE/lint-self-test.log"

step "design lint over product UI targets (Scripts/lint-design.py lint)"
sylvia_python "$SYLVIA_ROOT/Scripts/lint-design.py" lint | tee "$EVIDENCE/lint-repository.log"

step "token export drift check (sylvia-design-export check)"
xcrun swift build --force-resolved-versions --package-path "$PACKAGE" --product sylvia-design-export 2>&1 | tail -1
EXPORTER="$(xcrun swift build --force-resolved-versions --package-path "$PACKAGE" --show-bin-path)/sylvia-design-export"
"$EXPORTER" check "$SYLVIA_ROOT" | tee "$EVIDENCE/export-check.log"

step "design-token fixtures: one reason per invalid fixture (Scripts/lint-design.py fixtures)"
sylvia_python "$SYLVIA_ROOT/Scripts/lint-design.py" fixtures | tee "$EVIDENCE/fixtures-check.log"

step "contrast over the exported JSON (Python, Scripts/lint-design.py contrast)"
sylvia_python "$SYLVIA_ROOT/Scripts/lint-design.py" contrast --out "$EVIDENCE/contrast-export.md"

step "contrast over the token definitions (Swift, sylvia-design-export contrast-table)"
"$EXPORTER" contrast-table "$SYLVIA_ROOT" "$EVIDENCE/contrast-tokens.md"

step "snapshot references present"
reference_count="$(find "$SNAPSHOTS" -name '*.png' | wc -l | tr -d ' ')"
reference_size="$(du -sk "$SNAPSHOTS" | cut -f1)"
echo "$reference_count reference images, ${reference_size} KiB"
# 31 samples (22 Section 4.4.7 components, 9 screen parts for the catalog) x (8 color +
# 8 grayscale + 1 Bold Text) = 527.
if [[ "$reference_count" != 527 ]]; then
  echo "FAIL: expected 527 snapshot references, found $reference_count"; exit 1
fi

# Runs xcodebuild test, saves the full log, and fails on build/test failure, zero tests, skips or
# warnings. Snapshot references are compared, never recorded (SNAPSHOT_TESTING_RECORD=never).
run_tests() {
  local label="$1" destination="$2" log="$EVIDENCE/test-$1.log"
  shift 2
  step "SylviaDesign tests on $label ($destination)"
  local status=0
  (cd "$PACKAGE" && TEST_RUNNER_SYLVIA_EVIDENCE_DIR="$EVIDENCE" TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never \
      xcodebuild test -scheme SylviaDesign-Package -destination "$destination" -derivedDataPath "$DERIVED" \
      -disableAutomaticPackageResolution "$@") >"$log" 2>&1 || status=$?
  grep -E "Test run with|TEST (SUCCEEDED|FAILED)|Packages/Design/(Sources|Tests)/.*: warning:" "$log" || true
  if (( status != 0 )); then
    echo "FAIL: xcodebuild test on $label exited $status; see $log"
    grep -E "error:|✘" "$log" | head -40 || true
    return 1
  fi
  if grep -qE "Test run with 0 tests" "$log" || ! grep -qE "Test run with [1-9][0-9]* tests? .*passed" "$log"; then
    echo "FAIL: no tests ran on $label"; return 1
  fi
  # Swift Testing marks failures with ✘ and reports "Test ... skipped"; XCTest "Test Case ... skipped".
  if grep -qE "✘|Test .*skipped" "$log"; then
    echo "FAIL: a test failed or was skipped on $label"; grep -E "✘|Test .*skipped" "$log" | head; return 1
  fi
  if grep -qE "Packages/Design/(Sources|Tests)/.*: warning:" "$log"; then
    echo "FAIL: compiler warnings in Packages/Design on $label"; return 1
  fi
}

# Fails unless every named suite reported "passed" in the log.
require_suites() {
  local log="$1"; shift
  local suite
  for suite in "$@"; do
    if ! grep -qE "✔ Suite \"$suite\" passed" "$log"; then
      echo "FAIL: suite \"$suite\" did not pass in $log"; return 1
    fi
  done
}

run_tests host "platform=macOS"
require_suites "$EVIDENCE/test-host.log" "Component logic"

UDID="$(sylvia_sim_udid "$SIM_NAME")"
echo "simulator $SIM_NAME: $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)"
SIM_REPORTS=(t51-layout-audit-simulator.md t53-marker-pairs-simulator.md t53-pill-pairs-simulator.md
             t53-availability-badges-simulator.md t53-generated-frame-simulator.md
             t53-buttons-grayscale-simulator.md t53-rating-grayscale-simulator.md accessibility-tree-simulator.md)
for report in "${SIM_REPORTS[@]}"; do rm -f "$EVIDENCE/$report"; done
run_tests simulator "id=$UDID"
require_suites "$EVIDENCE/test-simulator.log" "Component logic" "Component snapshots \\(T51, T53\\)" \
  "T53 grayscale proxies" "T51 layout at the largest accessibility size" "Accessibility tree"
for report in "${SIM_REPORTS[@]}"; do
  if [[ ! -s "$EVIDENCE/$report" ]]; then
    echo "FAIL: $report was not written by this run"; exit 1
  fi
done
echo "simulator reports written: ${SIM_REPORTS[*]}"

step "negative check: changed references fail the snapshot suite"
# Replaces the light color reference and the light grayscale reference of the rating sample with
# the dark ones (same pixel size, different pixels), runs the snapshot suite, expects it to fail on
# exactly that sample (one issue per changed file), then restores both files.
negative_targets=("$SNAPSHOTS/rating.light-default.png" "$SNAPSHOTS/rating.light-default-gray.png")
negative_sources=("$SNAPSHOTS/rating.dark-default.png" "$SNAPSHOTS/rating.dark-default-gray.png")
backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/g06-references.XXXXXX")"
for t in "${negative_targets[@]}"; do cp "$t" "$backup_dir/"; done
restore() { for t in "${negative_targets[@]}"; do cp "$backup_dir/$(basename "$t")" "$t"; done; rm -rf "$backup_dir"; }
trap restore EXIT
for i in 0 1; do cp "${negative_sources[$i]}" "${negative_targets[$i]}"; done
negative_log="$EVIDENCE/snapshot-negative-check-simulator.log"
negative_status=0
(cd "$PACKAGE" && TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never xcodebuild test-without-building \
    -scheme SylviaDesign-Package -destination "id=$UDID" -derivedDataPath "$DERIVED" \
    -disableAutomaticPackageResolution -only-testing:SylviaDesignSnapshotTests/ComponentSnapshotTests) \
    >"$negative_log" 2>&1 || negative_status=$?
restore
trap - EXIT
failures="$(grep -E "✘ Test .*recorded an issue" "$negative_log" | grep -c '"rating"' || true)"
others="$(grep -E "✘ Test .*recorded an issue" "$negative_log" | grep -vc '"rating"' || true)"
echo "xcodebuild exit $negative_status; issues on the changed sample: $failures; on other samples: $others"
if (( negative_status == 0 )) || (( failures != 2 )) || (( others != 0 )); then
  echo "FAIL: the snapshot suite did not fail on exactly the two changed references"; exit 1
fi
grep -E "grey pixels differ|Snapshot does not match|does not match reference|pixels? differ" "$negative_log" | sort -u | head -5

step "snapshot reference inventory"
# The recording device comes from RecordingDevice (the suite compares only there), not from the
# simulator this run used.
RENDERING="$PACKAGE/Tests/SylviaDesignSnapshotTests/Rendering.swift"
recording_model="$(sed -nE 's/.*static let modelIdentifier = "([^"]+)".*/\1/p' "$RENDERING")"
recording_runtime="$(sed -nE 's/.*static let runtimePrefix = "([^"]+)".*/\1/p' "$RENDERING")"
if [[ -z "$recording_model" || -z "$recording_runtime" ]]; then
  echo "FAIL: could not read RecordingDevice from $RENDERING"; exit 1
fi
{
  echo "# Snapshot references"
  echo
  echo "Directory: \`Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests\`."
  echo "Recorded on the reference device of \`RecordingDevice\` (model $recording_model, iOS $recording_runtime; the suite refuses to compare on any other). Compared in this run on the simulator $SIM_NAME ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME). $reference_count PNG files, ${reference_size} KiB on disk."
  echo
  echo "| Sample | Files | KiB |"
  echo "| --- | --- | --- |"
  for prefix in $(find "$SNAPSHOTS" -name '*.png' -exec basename {} \; | sed -E 's/\.[a-z-]+(-ax5|-default)(-bold|-gray)?\.png$//' | sort -u); do
    n="$(find "$SNAPSHOTS" -name "$prefix.*.png" | wc -l | tr -d ' ')"
    k="$(find "$SNAPSHOTS" -name "$prefix.*.png" -exec stat -f %z {} \; | awk '{s+=$1} END {printf "%d", s/1024}')"
    echo "| $prefix | $n | $k |"
  done
} > "$EVIDENCE/snapshot-references.md"
cat "$EVIDENCE/snapshot-references.md"

step "generated files unchanged by the builds"
"$EXPORTER" check "$SYLVIA_ROOT"

echo
echo "20-design: all checks passed; outputs in $EVIDENCE"
