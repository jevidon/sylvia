#!/bin/bash
# The second fix of the decisions round (23 October 2026 on the build Mac's clock; integration log section 19):
# controls for its changes to the lock harness, each made on a copy of the committed harness and recovery package
# (git archive HEAD Spikes/G05-Recovery, into .build/scratch/fix2-controls; the working tree is never changed), on this
# round's simulator, Sylvia-M0-dec-fix-2 (iPhone 17, iOS 26.5). The copy's unit tests run first, unchanged, and must
# all pass; then each control changes one thing in the copy, runs, and puts the file back:
#   A. FileLogSink without the cut-back of a failed append (its `try? handle.truncate(atOffset: length)` line removed):
#      its lines are then in the file when it throws, the case of review R2-H-04. Exactly the two R2-H-04 unit tests
#      must fail, and no other.
#   B. TonePlayer.start with the ambient category in place of playback. Exactly the tone's unit test must fail, on the
#      category it reads back (review R2-H-03: the start line records the category, and the smoke check requires it).
#   C. The app with a player that plays nothing (a SilentPlayer in place of TonePlayer in the production
#      environment), and the UI smoke test with 90 s in the background in place of 14 s. Nothing is required of it: it
#      shows, from the app's own log, whether the simulator keeps the app making its attempts in the background without
#      the tone, which review R2-H-03 reported from a reviewer's control, so whether the smoke test can tell the tone's
#      effect at all.
# No audio is played by A or C (C's player plays nothing); B's tone plays at the test volume 0.01, in the unit test.
#   Docs/Stage0/evidence/M0-Decisions/fix-2/commands/harness-controls.sh
# Logs in Docs/Stage0/evidence/M0-Decisions/fix-2/harness-controls/: console.log (the summary), baseline.log, A.log,
# B.log, C.log (each the xcodebuild output, without the compiler's command lines) and C-harness.log (the app's own log
# of control C, copied out of the simulator). Exit status 1 if the baseline or control A or B is not as required.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
out=Docs/Stage0/evidence/M0-Decisions/fix-2/harness-controls
copy="$root/.build/scratch/fix2-controls"
H="$copy/Spikes/G05-Recovery/LockHarness"
bundle=com.jevidon.sylvia.spike.g05lockharness
rm -rf "$out" "$copy"
mkdir -p "$out" "$copy"
console="$out/console.log"
status=0
{
  echo "command: Docs/Stage0/evidence/M0-Decisions/fix-2/commands/harness-controls.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "copy: git archive HEAD Spikes/G05-Recovery into .build/scratch/fix2-controls (the working tree is not changed)"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$console"
git archive HEAD Spikes/G05-Recovery | tar -x -C "$copy"
sylvia_generate "$H" >/dev/null || { echo "FAIL: xcodegen on the copy" >> "$console"; exit 1; }
UDID="$(sylvia_sim_udid Sylvia-M0-dec-fix-2)"
sylvia_sim_boot "$UDID"
trap 'sylvia_sim_shutdown "$UDID"' EXIT
echo "simulator: Sylvia-M0-dec-fix-2 $UDID ($SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME)" >> "$console"

# Replaces exactly one occurrence of a text in a file of the copy, or fails.
edit() {
  /usr/bin/python3 -I - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit("expected exactly one occurrence in %s, found %d: %r" % (path, text.count(old), old))
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
}

# Runs the copy's unit tests; writes the output without the compiler's command lines; prints the failed tests' names.
unit_tests() {
  local log="$1"
  xcodebuild test -project "$H/G05LockHarness.xcodeproj" -scheme G05LockHarness -destination "id=$UDID" \
    -derivedDataPath "$H/.build/DerivedData" -disableAutomaticPackageResolution -only-testing:G05LockHarnessTests \
    > "$log.full" 2>&1
  local code=$?
  perl -pe 's/\e\[[0-9;]*m//g' "$log.full" | grep -vE '^ {4}|^\s*$' > "$log"
  rm -f "$log.full"
  echo "xcodebuild exit: $code" >> "$log"
  grep -E '^✘ Test ".*" failed after ' "$log" | sed -E 's/^✘ Test "(.*)" failed after .*/\1/' | sort -u
}

expect_failures() {  # <name> <log> <expected failed test names, one per line>
  local name="$1" log="$2" expected="$3" got
  got="$(unit_tests "$log")"
  {
    echo "-- $name: tests that failed:"
    if [[ -n "$got" ]]; then printf '%s\n' "$got" | sed 's/^/   /'; else echo "   (none)"; fi
    grep -E '^(✔|✘) Test run with' "$log" | sed 's/^/   /'
  } >> "$console"
  if [[ "$got" == "$expected" ]]; then
    echo "   as required" >> "$console"
  else
    echo "   NOT as required; expected exactly:" >> "$console"
    printf '%s\n' "$expected" | sed 's/^/   /' >> "$console"
    status=1
  fi
}

echo >> "$console"
expect_failures "baseline (the copy unchanged; every test must pass)" "$out/baseline.log" ""

files="$H/Core/HarnessFiles.swift"
cp "$files" "$copy/HarnessFiles.swift.orig"
edit "$files" "            try? handle.truncate(atOffset: length)
" "" || { echo "FAIL: control A's edit" >> "$console"; exit 1; }
expect_failures "A (FileLogSink keeps the lines of a failed append in the file: review R2-H-04)" "$out/A.log" \
  "$(printf '%s\n' \
    "a run whose log file fails to flush at three attempts writes every line once: those three later, marked written-late, none twice (review R2-H-04)" \
    "an append whose flush fails is cut back out of the log file and throws; nothing of it stays, and the retry writes it once (review R2-H-04)" | sort)"
cp "$copy/HarnessFiles.swift.orig" "$files"

tone="$H/Core/TonePlayer.swift"
cp "$tone" "$copy/TonePlayer.swift.orig"
edit "$tone" "        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        category = session.category.rawValue" "        try session.setCategory(.ambient, mode: .default, options: [])
        try session.setActive(true)
        category = session.category.rawValue" || { echo "FAIL: control B's edit" >> "$console"; exit 1; }
expect_failures "B (TonePlayer in the ambient category: review R2-H-03)" "$out/B.log" \
  "the player plays the tone at the test volume 0.01, unmuted, in the playback category, and stops (simulator; plays through the Mac's output at 1 %)"
cp "$copy/TonePlayer.swift.orig" "$tone"

# Control C: a player that plays nothing, and 90 s in the background.
cat >> "$H/App/SystemAdapters.swift" <<'SWIFT'

/// Control C of the second fix of the decisions round (harness-controls.sh): a player that plays nothing.
@MainActor
final class SilentPlayer: KeepAlivePlayer {
    var onEvent: (@MainActor (String) -> Void)?
    var isPlaying: Bool { false }
    var category: String? { nil }
    func start(volume: Float) throws {}
    func stop() {}
}
SWIFT
edit "$H/App/SystemAdapters.swift" "player: TonePlayer()," "player: SilentPlayer()," || { echo "FAIL: control C's edit" >> "$console"; exit 1; }
edit "$H/UITests/LockHarnessSmokeUITests.swift" "        pause(14)
" "        pause(90)
" || { echo "FAIL: control C's edit of the UI test" >> "$console"; exit 1; }
xcrun simctl uninstall "$UDID" "$bundle" >/dev/null 2>&1 || true
xcodebuild test -project "$H/G05LockHarness.xcodeproj" -scheme G05LockHarness -destination "id=$UDID" \
  -derivedDataPath "$H/.build/DerivedData" -disableAutomaticPackageResolution -only-testing:G05LockHarnessUITests \
  > "$out/C.log.full" 2>&1
c_code=$?
perl -pe 's/\e\[[0-9;]*m//g' "$out/C.log.full" | grep -vE '^ {4}|^\s*$' > "$out/C.log"
rm -f "$out/C.log.full"
echo "xcodebuild exit: $c_code" >> "$out/C.log"
container="$(xcrun simctl get_app_container "$UDID" "$bundle" data 2>/dev/null)"
if [[ -n "$container" && -f "$container/Library/Application Support/G05LockHarness/harness.log" ]]; then
  cp "$container/Library/Application Support/G05LockHarness/harness.log" "$out/C-harness.log"
fi
xcrun simctl uninstall "$UDID" "$bundle" >/dev/null 2>&1 || true
{
  echo
  echo "-- C (a player that plays nothing; 90 s in the background): xcodebuild exit $c_code; $(grep -E "Test Suite 'LockHarnessSmokeUITests' (passed|failed)" "$out/C.log" | head -1)"
} >> "$console"
if [[ -f "$out/C-harness.log" ]]; then
  /usr/bin/python3 -I - "$out/C-harness.log" >> "$console" <<'PY'
import sys
lines = []
for raw in open(sys.argv[1], encoding="utf-8").read().splitlines():
    parts = raw.split(" ")
    fields = {"time": parts[0], "event": parts[1] if len(parts) > 1 else ""}
    for part in parts[2:]:
        if "=" in part and not part.startswith('reason="'):
            key, value = part.split("=", 1)
            fields[key] = value
    lines.append(fields)
start = next((l for l in lines if l["event"] == "start"), {})
attempts = [l for l in lines if l["event"] == "attempt"]
background = [a for a in attempts if a.get("app") == "background"]
times = [float(a["t"]) for a in attempts]
deltas = [b - a for a, b in zip(times, times[1:])]
bdeltas = [float(b["t"]) - float(a["t"]) for a, b in zip(background, background[1:])]
print("   the start line: audio=%s audioCategory=%s volume=%s" % (start.get("audio"), start.get("audioCategory"), start.get("volume")))
print("   attempts: %d, %d of them with app=background (n=%s to n=%s), every attempt save=%s"
      % (len(attempts), len(background), background[0]["n"] if background else "-", background[-1]["n"] if background else "-",
         ",".join(sorted({a.get("save", "?") for a in attempts}))))
print("   seconds between attempts: %.1f to %.1f; in the background: %.1f to %.1f; gap lines: %d"
      % (min(deltas or [0]), max(deltas or [0]), min(bdeltas or [0]), max(bdeltas or [0]), sum(1 for l in lines if l["event"] == "gap")))
print("   reading: %s" % ("the simulator kept the app making its attempts in the background, 2 s apart, with no tone"
      if len(background) >= 30 and not any(l["event"] == "gap" for l in lines) and start.get("audio") == "not-playing"
      else "not the pattern review R2-H-03 reported; see C-harness.log"))
PY
else
  echo "   no harness.log was copied out of the simulator" >> "$console"
fi
{
  echo
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "git status --porcelain lines after the run: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "exit: $status"
} >> "$console"
rm -rf "$copy"
exit $status
