#!/bin/bash
# Re-runs, in the clone of the M0 final fix's complete run, the G0.4 simulator tests that failed there, with the build
# products that run made (test-without-building), the same simulator, the same environment the drop-in passes
# (fixture cache, results and excerpt folders, booted-simulator list) and test volume (SYLVIA_AUDIBLE_PLAYBACK unset).
# Before and after, it records the Mac's audio output devices read-only (commands/audio-device-state.sh) and the load.
# Writes only under the clone's .build/ and the log; shuts the simulator down at the end.
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/g04-rerun-failed.sh <clone> <log> <test id>...
#   test id: as for -only-testing, for example G04AudioTests/RealAV/MutedRenderingTests/quietPlayerRenders()
set -u
here="$(cd "$(dirname "$0")" && pwd)"
clone="$1"; log="$2"; shift 2
cd "$clone" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
sim=Sylvia-M0-final-fix
udid="$(sylvia_sim_find "$sim")"
[[ -n "$udid" ]] || { echo "no simulator named $sim" > "$log"; exit 1; }
results="$clone/.build/ci-results/g04-audio-rerun"
excerpts="$clone/.build/ci-results/g04-excerpts-rerun"
rm -rf "$results" "$excerpts"
mkdir -p "$results" "$excerpts"
only=()
for t in "$@"; do only+=("-only-testing:$t"); done
{
  echo "clone: $clone at $(git rev-parse HEAD); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "simulator: $sim ($udid); test volume (SYLVIA_AUDIBLE_PLAYBACK unset)"
  echo "tests: $*"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$log"
"$here/audio-device-state.sh" "$log"
trap 'sylvia_sim_shutdown "$udid"' EXIT
sylvia_sim_boot "$udid" >> "$log" 2>&1
booted="$(xcrun simctl list devices booted | grep -c '(Booted)' || true)"
status=0
TEST_RUNNER_SYLVIA_FIXTURE_CACHE="$SYLVIA_FIXTURE_CACHE" TEST_RUNNER_G04_RESULTS_DIR="$results" \
TEST_RUNNER_G04_EXCERPTS_DIR="$excerpts" TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK=0 TEST_RUNNER_G04_BOOTED_SIMULATORS="$booted" \
xcodebuild test-without-building -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness \
  -destination "id=$udid" -derivedDataPath Spikes/G04-Audio/.build/DerivedData \
  -resultBundlePath "$clone/.build/ci-results/g04-audio-rerun.xcresult" "${only[@]}" \
  > "$clone/.build/ci-results/g04-audio-rerun-xcodebuild.log" 2>&1 || status=$?
rm -rf "$clone/.build/ci-results/g04-audio-rerun.xcresult"
grep -E '^(✔|✘) Test |^✘ Suite|^✔ Suite|↳ media advance|Test run with|\*\* TEST' "$clone/.build/ci-results/g04-audio-rerun-xcodebuild.log" >> "$log"
for table in "$results"/*; do
  [[ -f "$table" ]] || continue
  echo "-- result table $(basename "$table")" >> "$log"
  cat "$table" >> "$log"
done
{
  echo "xcodebuild exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log"
"$here/audio-device-state.sh" "$log"
exit $status
