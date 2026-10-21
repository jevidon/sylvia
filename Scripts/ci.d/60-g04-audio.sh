#!/usr/bin/env bash
# G0.4 audio spike (plan 10, 21.1; ADR-0006, ADR-0007): fixtures (including 3- and 10-hour files of every
# provisional format, and stereo files with distinct channels), project generation, a signed device build for testing (team A4KBDX665Z, automatic signing;
# unsigned when the host has no Apple Development identity), every automated test on this job's own simulator, a
# process-kill trial of the harness app, an ffmpeg decode of exported excerpts, and the quick-capture intent run through
# the system from the Shortcuts app (App Shortcut) and from Control Center (the control), as UI tests.
#
#   Scripts/fixtures/fetch.sh                          # once: LibriVox sources (SHA-256 pinned)
#   Scripts/ci.sh g04                                  # this drop-in (generates the G0.4 fixtures if needed)
#   G04_RESULTS_DIR=Docs/Stage0/evidence/G04-Audio/results Scripts/ci.sh g04   # write the evidence tables there
#
# Environment (all optional):
#   G04_RESULTS_DIR   where the result tables go (default .build/ci-results/g04-audio). A relative path is taken
#                     from the repository root. The directory is emptied first; every table the run must produce
#                     is checked at the end, and a missing one fails the run.
#   G04_SIM_NAME      simulator name (default Sylvia-M0-g04-audio; created on the iOS 26.5 runtime if missing)
#   G04_SKIP_REALAV=1 run only the fast unit suites (fakes, no AVFoundation playback, no trial, no test tables);
#                     for quick local loops only, never a gate run
#   G04_KEEP_SIM=1    leave this job's simulator booted when the drop-in exits (local debugging). By default the drop-in
#                     shuts down the simulator it booted, on success or failure (review R4-04: simulators left booted
#                     load the shared Mac and distort other jobs' timing measurements).
#   G04_DEVICE_FIXTURES=1  also build the device test bundle with the fixtures bundled (about 8.7 GB copied into the
#                     derived data), the configuration device checklist step 1 installs, and verify its signature and
#                     contents (device-build-fixtures.txt). Off by default: it needs the disk space and several minutes.
#   SYLVIA_AUDIBLE_PLAYBACK=1  play at full volume. Without it every test, probe and harness launch plays at 1 %
#                     volume (the host's speakers are shared): the tests create their players through TestAudio, the
#                     harness is launched with -g04AudiblePlayback NO and its log must say volume=0.01. The volume is
#                     applied after decoding, the time-pitch stage and the analysis taps, and the clocks are unaffected
#                     (MutedRenderingTests, audio-output.txt; isMuted is not used because it changes the rendering).
#
# Host precondition (M0 final review round 2, CC2-01): the iOS Simulator plays through the Mac's default output device,
# and an AVPlayer's clock includes that device's output latency. The drop-in reads that device and the presentation
# latency CoreAudio reports for it (Spikes/G04-Audio/Scripts/host_audio_output.swift, read-only), records them in its log
# and in every row of host-load.tsv, and stops at once, naming the device, when the latency is above 0.3 s: the tests
# that compare the player's clock with the rendered audio or with wall time tolerate at most 0.5 s, and with an AirPlay
# default output (2.012 s) seven of them failed after 77 minutes. The built-in speakers or wired headphones are well
# below it (the built-in speakers 0.027 s on the build Mac). A person changes the output; agents never change the Mac's
# audio device, volume or mute state, and the tests' tolerances are never widened for it.
#
# Exits non-zero when fixture generation, generation, a build, any test, the process-kill trial, the portability
# check or a quick-capture UI test fails, when a quick-capture result the G0.4 report relies on is missing (the control's
# press performed and saved in the app's process; with the team-signed build also the App Shortcut run, and the
# control's surface in the origin; review R5-06; and the control pressed when nothing has been heard, with the harness
# not running and with its restored book not played, answering nothing_to_capture with no record; review R6-01), when
# the capture records a UI test counted disagree with the captures the harness logged (review R6-06), or when a result
# table is missing. A missing fixture is a test failure, never a skip.
# On exit, success or failure, it shuts down the simulator it booted (unless G04_KEEP_SIM=1). A full run takes about
# 90 minutes on the M5 Max (the two-hour-of-media soak alone is 40 minutes; the codec matrix, the 10-hour files of
# every format and the cold-resume sweeps most of the rest; longer when the host is loaded), plus about 2 minutes with
# G04_DEVICE_FIXTURES=1 and about 30 minutes the first time for the fixtures (about 8.5 GB).
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"
cd "$SYLVIA_ROOT"

SPIKE=Spikes/G04-Audio
PROJECT="$SPIKE/G04Audio.xcodeproj"
DERIVED="$SPIKE/.build/DerivedData"
RESULTS="${G04_RESULTS_DIR:-.build/ci-results/g04-audio}"
# The test process resolves paths against its own working directory, so everything passed to it is absolute.
[[ "$RESULTS" == /* ]] || RESULTS="$SYLVIA_ROOT/$RESULTS"
RESULTS="${RESULTS%/}"
# The directory is emptied below: refuse the repository root, any directory above it, and paths with . or .. parts.
if [[ -z "$RESULTS" || "$SYLVIA_ROOT/" == "$RESULTS/"* || "$RESULTS" =~ (^|/)\.\.?(/|$) ]]; then
  echo "error: G04_RESULTS_DIR resolves to '$RESULTS', which this script would empty; use a dedicated directory" >&2
  exit 1
fi
EXCERPTS="$SYLVIA_ROOT/.build/ci-results/g04-excerpts"
SIM_NAME="${G04_SIM_NAME:-Sylvia-M0-g04-audio}"
BUNDLE="$SYLVIA_ROOT/.build/ci-results/g04-audio.xcresult"
PORTABILITY_BUNDLE="$SYLVIA_ROOT/.build/ci-results/g04-audio-portability.xcresult"
# The host precondition (header): the default output's presentation latency, in seconds, above which the drop-in stops.
MAX_OUTPUT_LATENCY_S=0.300
OUTPUT_PROBE="$SYLVIA_ROOT/$SPIKE/.build/host-audio-output"
HOST_LOAD=""

# Every table a full run writes. The run fails if one is missing or older than the run.
EXPECTED_TABLES=(
  audio-session.txt budgets.txt codec-matrix-detail.tsv codec-matrix.tsv container-probes.txt device-build-signing.txt excerpt-portability.tsv
  estimated-timing-capture.tsv estimated-timing-decoder.tsv
  excerpt-timing-cross-file.tsv excerpt-timing-single-file-detail.tsv excerpt-timing-single-file.tsv
  excerpt-timing-three-formats.txt host-load.tsv librivox-m4b.txt long-long-aac-10h.m4b.txt long-long-mp3-cbr-10h.mp3.txt
  long-long-mp3-vbr-10h.mp3.txt long-formats-capture.tsv long-formats-cold-resume.tsv long-formats-open.tsv
  long-formats-remux.tsv long-seek-latency.txt mp3-cbr-detection.tsv now-playing.txt preview-end-formats.tsv preview-interruption.txt
  preview-load-edition.txt
  preview.txt process-kill-relaunch.txt audio-output.txt quick-capture-simulator-adhoc.txt quick-capture-simulator-signed.txt rate-pitch.txt
  real-engine-boundary.txt real-engine-error-states.txt real-engine-relaunch.txt real-engine-seek-rate.txt soak.txt
  stereo-channels.tsv t23-source-removal.txt
)
if [[ "${G04_DEVICE_FIXTURES:-0}" == "1" ]]; then EXPECTED_TABLES+=(device-build-fixtures.txt); fi

# On exit (success or failure): stop the host-load sampler and shut down this job's simulator (review R4-04), unless
# G04_KEEP_SIM=1.
UDID=""
SAMPLER_PID=""
cleanup() {
  if [[ -n "$SAMPLER_PID" ]]; then kill "$SAMPLER_PID" >/dev/null 2>&1 || true; fi
  # Name the output device if it changed to a slow one during the run (CC2-01): the clock tests fail with it.
  if [[ -s "${HOST_LOAD:-}" ]]; then
    awk -F'\t' -v limit="$MAX_OUTPUT_LATENCY_S" 'NR > 2 && $8 != "unknown" && $8 + 0 > limit + 0 {
        print "note: at " $1 " the default output was " $6 " (" $7 ", presentation latency " $8 " s), above the " limit " s limit:"
        print "      the tests that compare the player clock with the rendered audio fail with such an output"; exit }' "$HOST_LOAD"
  fi
  if [[ -n "$UDID" && "${G04_KEEP_SIM:-0}" != "1" ]]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    echo "simulator $SIM_NAME ($UDID) shut down on exit (G04_KEEP_SIM=1 keeps it booted)"
  fi
}
trap cleanup EXIT
booted_simulators() { xcrun simctl list devices booted 2>/dev/null | grep -c '(Booted)' || true; }

step() { echo; echo "== $* ($(date -u +%H:%M:%SZ))"; }

step "toolchain"
echo "host: $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(uptime | sed 's/^ *//'); simulators booted: $(booted_simulators)"
sylvia_check_xcode || true
xcodebuild -version
xcodegen --version
ffmpeg -version | head -1

step "host audio output (read-only): the device the simulator plays through, and its presentation latency (limit $MAX_OUTPUT_LATENCY_S s)"
mkdir -p "$(dirname "$OUTPUT_PROBE")"
xcrun swiftc -swift-version 6 -warnings-as-errors -O -o "$OUTPUT_PROBE" "$SPIKE/Scripts/host_audio_output.swift"
"$OUTPUT_PROBE" || true
IFS=$'\t' read -r OUTPUT_NAME OUTPUT_TRANSPORT OUTPUT_LATENCY < <("$OUTPUT_PROBE" --tsv || true) || true
if [[ -z "${OUTPUT_LATENCY:-}" || "$OUTPUT_LATENCY" == "unknown" ]]; then
  echo "WARN the default output's presentation latency could not be read; the clock tests' result depends on it (header)"
elif awk -v latency="$OUTPUT_LATENCY" -v limit="$MAX_OUTPUT_LATENCY_S" 'BEGIN { exit !(latency + 0 > limit + 0) }'; then
  if [[ "${G04_SKIP_REALAV:-0}" == "1" ]]; then
    echo "note: the default output's latency is above the limit; G04_SKIP_REALAV=1 runs none of the clock tests"
  else
    echo "error: the Mac's default output device is '$OUTPUT_NAME' (transport $OUTPUT_TRANSPORT), with a presentation"
    echo "latency of $OUTPUT_LATENCY s, above the $MAX_OUTPUT_LATENCY_S s this drop-in accepts. The iOS Simulator plays through that"
    echo "device and an AVPlayer's clock includes its latency, so the tests that compare the player's clock with the"
    echo "rendered audio or with wall time would fail after more than an hour (seven did with an AirPlay output, 2.012 s,"
    echo "in the M0 final fix's complete run). A person sets the Mac's sound output to the built-in speakers or wired"
    echo "headphones (System Settings > Sound > Output) and runs it again; agents never change the Mac's audio device."
    exit 1
  fi
else
  echo "the default output '$OUTPUT_NAME' ($OUTPUT_TRANSPORT, $OUTPUT_LATENCY s) is within the limit"
fi

# Quiet (1 % volume) unless SYLVIA_AUDIBLE_PLAYBACK=1 (passed to the test processes and the harness launches below).
if [[ "${SYLVIA_AUDIBLE_PLAYBACK:-0}" == "1" ]]; then AUDIBLE=1; else AUDIBLE=0; fi
export SYLVIA_AUDIBLE_PLAYBACK="$AUDIBLE"

step "playback output: $( (( AUDIBLE )) && echo 'full volume (SYLVIA_AUDIBLE_PLAYBACK=1)' || echo 'quiet, 1 % volume (set SYLVIA_AUDIBLE_PLAYBACK=1 for full volume)')"
# Every player a test creates must come from TestAudio (1 % volume unless SYLVIA_AUDIBLE_PLAYBACK=1); a line that
# creates one directly is allowed only when it says why (`full-volume-by-design`, the test of the engines' full-volume
# default).
direct="$(grep -rnE 'AVPlayer\(|AVQueuePlayer\(|AVQueuePlayerEngine\(|AVPreviewPlayer\(|AVAudioPlayer|AVAudioEngine|AudioServicesPlay' \
  "$SPIKE/Tests" | grep -v '/Support/TestAudio.swift:' | grep -v 'full-volume-by-design' || true)"
if [[ -n "$direct" ]]; then
  echo "error: test code creates a player outside TestAudio (it would play at full volume):"
  echo "$direct"
  exit 1
fi
echo "every test player is created through TestAudio"

step "fixtures (Scripts/fixtures/generate-g04-audio-fixtures.sh, generate-g04-audio-long-formats.sh, generate-g04-audio-probes.sh and generate-g04-audio-stereo.sh; idempotent)"
"$SYLVIA_ROOT/Scripts/fixtures/generate-g04-audio-fixtures.sh" | tail -n 3
"$SYLVIA_ROOT/Scripts/fixtures/generate-g04-audio-long-formats.sh" | tail -n 3
"$SYLVIA_ROOT/Scripts/fixtures/generate-g04-audio-probes.sh" | tail -n 3
"$SYLVIA_ROOT/Scripts/fixtures/generate-g04-audio-stereo.sh" | tail -n 3

step "generate the Xcode project"
sylvia_generate "$SPIKE"

rm -rf "$RESULTS" "$BUNDLE" "$PORTABILITY_BUNDLE" "$EXCERPTS"
mkdir -p "$RESULTS" "$EXCERPTS"
RUN_STAMP="$(mktemp "${TMPDIR:-/tmp}/g04-run.XXXXXX")"  # tables must be newer than this

# Builds print warnings and errors only (-quiet). Swift warnings are errors (project.yml); any other warning from
# these builds (for example Info.plist checks) fails the step too.
quiet_build() {
  local out rc=0
  out="$(mktemp "${TMPDIR:-/tmp}/g04-build.XXXXXX")"
  xcodebuild build-for-testing -project "$PROJECT" -scheme "${SCHEME:-G04AudioHarness}" -derivedDataPath "$DERIVED" \
    -disableAutomaticPackageResolution -quiet "$@" >"$out" 2>&1 || rc=$?
  cat "$out"
  if (( rc == 0 )) && grep -q 'warning:' "$out"; then
    echo "error: the build printed warnings (see above)"
    rc=1
  fi
  rm -f "$out"
  return "$rc"
}

step "device build for testing (generic iOS, automatic signing with team $SYLVIA_TEAM_ID; installing and running it are device-checklist items)"
# Automatic signing as on a device run, without -allowProvisioningUpdates: it uses the identity and the team
# provisioning profile already on this host. Without an Apple Development identity (another host, a CI runner) the
# step falls back to an unsigned compile check and records the signing as pending (review R3-05).
SIGNING="$RESULTS/device-build-signing.txt"
DEVICE_PRODUCTS="$DERIVED/Build/Products/Debug-iphoneos"
{
  echo "# Device build for testing (generic/platform=iOS, Debug, automatic signing). Environment: host $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | head -1)"
  echo "# Signing only: the products are not installed or run here (device checklist steps 1 and 1.5)."
} > "$SIGNING"
if security find-identity -v -p codesigning | grep -q '"Apple Development: '; then
  quiet_build -destination 'generic/platform=iOS' DEVELOPMENT_TEAM="$SYLVIA_TEAM_ID" G04_SKIP_DEVICE_FIXTURES=YES
  echo "signed device build-for-testing succeeded"
  for product in "G04AudioHarness.app" "G04AudioHarness.app/PlugIns/G04CaptureControl.appex" \
                 "G04AudioHarness.app/Frameworks/G04AudioKit.framework" "G04AudioHarness.app/PlugIns/G04AudioTests.xctest"; do
    path="$DEVICE_PRODUCTS/$product"
    codesign --verify --strict "$path"
    details="$(codesign -dvv "$path" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Signed Time)=' || true)"
    grep -q "^TeamIdentifier=$SYLVIA_TEAM_ID\$" <<<"$details" || { echo "error: $product is not signed by team $SYLVIA_TEAM_ID: $details"; exit 1; }
    {
      echo "== $product: codesign --verify --strict ok"
      echo "$details"
      if [[ -f "$path/embedded.mobileprovision" ]]; then
        security cms -D -i "$path/embedded.mobileprovision" > "$RESULTS/.profile.plist"
        for key in Name TeamIdentifier:0 ExpirationDate; do
          echo "profile $key=$(/usr/libexec/PlistBuddy -c "Print :$key" "$RESULTS/.profile.plist")"
        done
        rm -f "$RESULTS/.profile.plist"
      fi
    } >> "$SIGNING"
  done
else
  quiet_build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO G04_SKIP_DEVICE_FIXTURES=YES
  echo "unsigned device build-for-testing succeeded"
  echo "no Apple Development identity on this host: unsigned compile check only; signing pending (device checklist step 1)" >> "$SIGNING"
fi
cat "$SIGNING"

if [[ "${G04_DEVICE_FIXTURES:-0}" == "1" ]]; then
  # The configuration device checklist step 1 installs: the test bundle with every fixture inside (the post-build
  # script copies them), signed (gate gap of review round 4: the step above skips the copy).
  step "device build for testing with the fixtures bundled (G04_DEVICE_FIXTURES=1; about 8.7 GB)"
  FIXTURED="$RESULTS/device-build-fixtures.txt"
  security find-identity -v -p codesigning | grep -q '"Apple Development: ' \
    || { echo "error: G04_DEVICE_FIXTURES=1 needs an Apple Development identity on this host"; exit 1; }
  started=$SECONDS
  quiet_build -destination 'generic/platform=iOS' DEVELOPMENT_TEAM="$SYLVIA_TEAM_ID"
  XCTEST="$DEVICE_PRODUCTS/G04AudioHarness.app/PlugIns/G04AudioTests.xctest"
  BUNDLED="$XCTEST/G04Fixtures/generated/g04-audio"
  {
    echo "# Device build for testing with the fixtures bundled (generic/platform=iOS, Debug, automatic signing; G04_DEVICE_FIXTURES=1). Environment: host $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | head -1)"
    echo "# Not installed or run here (device checklist step 1). Build and checks took $((SECONDS - started)) s before this line."
    echo "test bundle size: $(du -sh "$XCTEST" | cut -f1)"
    echo "audio files in the bundle: $(find "$BUNDLED" -type f \( -name '*.mp3' -o -name '*.m4a' -o -name '*.m4b' -o -name '*.flac' -o -name '*.ogg' -o -name '*.opus' -o -name '*.webm' -o -name '*.caf' -o -name '*.wav' \) | wc -l | tr -d ' ') (+ $(ls "$XCTEST/G04Fixtures/downloads" | wc -l | tr -d ' ') download)"
  } > "$FIXTURED"
  # Every file of both fixture manifests is in the bundle with the manifest's SHA-256.
  checked=0
  for manifest in "$SYLVIA_FIXTURE_CACHE/generated/g04-audio/manifest.tsv" "$SYLVIA_FIXTURE_CACHE/generated/g04-audio/long-formats/manifest.tsv" \
                  "$SYLVIA_FIXTURE_CACHE/generated/g04-audio/probes/manifest.tsv" "$SYLVIA_FIXTURE_CACHE/generated/g04-audio/stereo/manifest.tsv"; do
    base="$BUNDLED"
    [[ "$manifest" == */long-formats/manifest.tsv ]] && base="$BUNDLED/long-formats"
    [[ "$manifest" == */probes/manifest.tsv ]] && base="$BUNDLED/probes"
    [[ "$manifest" == */stereo/manifest.tsv ]] && base="$BUNDLED/stereo"
    while IFS=$'\t' read -r f sha _; do
      [[ -z "$f" || "$f" == \#* ]] && continue
      got="$(shasum -a 256 "$base/$f" | awk '{print $1}')"
      [[ "$got" == "$sha" ]] || { echo "error: bundled $f has SHA-256 $got, the manifest says $sha" | tee -a "$FIXTURED"; exit 1; }
      checked=$((checked + 1))
    done < "$manifest"
  done
  echo "manifest digests verified in the bundle: $checked files" >> "$FIXTURED"
  for product in "G04AudioHarness.app" "G04AudioHarness.app/PlugIns/G04AudioTests.xctest"; do
    codesign --verify --strict "$DEVICE_PRODUCTS/$product"
    echo "== $product: codesign --verify --strict ok" >> "$FIXTURED"
    codesign -dvv "$DEVICE_PRODUCTS/$product" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)=' >> "$FIXTURED"
  done
  cat "$FIXTURED"
fi

step "simulator $SIM_NAME"
UDID="$(sylvia_sim_udid "$SIM_NAME")"
sylvia_sim_boot "$UDID"
xcrun simctl list devices | grep "$UDID"

# Host load for the whole run (review R4-02): MP3 cold-resume times on the simulator grow with the host's load (other
# jobs' simulators). One row every 30 s until the drop-in exits; the timing tables also record the load per trial.
HOST_LOAD="$RESULTS/host-load.tsv"
{
  echo "# Host load during this run of Scripts/ci.d/60-g04-audio.sh: one sample every 30 s (uptime load averages; simulators booted on the host, this job's included; the Mac's default output device, its transport and CoreAudio's presentation latency in seconds, read-only, M0 final review round 2 CC2-01)."
  printf 'utc\tload_1m\tload_5m\tload_15m\tbooted_simulators\tdefault_output\toutput_transport\toutput_latency_s\n'
} > "$HOST_LOAD"
(
  while true; do
    read -r l1 l5 l15 < <(sysctl -n vm.loadavg | tr -d '{}')
    output="$("$OUTPUT_PROBE" --tsv 2>/dev/null || true)"
    [[ -n "$output" ]] || output="$(printf 'unknown\tunknown\tunknown')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$l1" "$l5" "$l15" "$(booted_simulators)" "$output" >> "$HOST_LOAD"
    sleep 30
  done
) &
SAMPLER_PID=$!
disown "$SAMPLER_PID"  # the shell does not report the sampler's end when cleanup stops it

step "build for testing (simulator)"
quiet_build -destination "id=$UDID"
echo "simulator build-for-testing succeeded"

step "app bundle contents (control extension and App Intents metadata)"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/G04AudioHarness.app"
ls "$APP/PlugIns"
# What the system will read about the quick-capture intent (ADR-0007): its system protocols decide the process.
for meta in "$APP/Metadata.appintents" "$APP/PlugIns/G04CaptureControl.appex/Metadata.appintents"; do
  /usr/bin/python3 - "$meta/extract.actionsdata" <<'EOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for name, a in sorted(data.get("actions", {}).items()):
    keys = ["authenticationPolicy", "openAppWhenRun", "supportedModes", "systemProtocols"]
    info = {k: a.get(k) for k in keys}
    info["parameters"] = [p.get("name") for p in a.get("parameters") or []]
    print(path.split("Products/")[-1] + ": " + name + " " + json.dumps(info, sort_keys=True))
shortcuts = [s.get("actionIdentifier") for s in (data.get("autoShortcuts") or [])]
print("  app shortcuts: " + (", ".join(shortcuts) if shortcuts else "none"))
EOF
done

skip=()
if [[ "${G04_SKIP_REALAV:-0}" == "1" ]]; then
  skip=(-skip-testing:G04AudioTests/RealAV)
  echo "G04_SKIP_REALAV=1: real-AVFoundation suites, the process-kill trial and the portability check skipped (not a gate run)"
fi

step "tests on the simulator (results in $RESULTS)"
BOOTED="$(booted_simulators)"
echo "host: $(uptime | sed 's/^ *//'); simulators booted: $BOOTED"
# TEST_RUNNER_* variables reach the test process without the prefix.
TEST_RUNNER_SYLVIA_FIXTURE_CACHE="$SYLVIA_FIXTURE_CACHE" TEST_RUNNER_G04_RESULTS_DIR="$RESULTS" \
TEST_RUNNER_G04_EXCERPTS_DIR="$EXCERPTS" TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK="$AUDIBLE" TEST_RUNNER_G04_BOOTED_SIMULATORS="$BOOTED" \
xcodebuild test-without-building -project "$PROJECT" -scheme G04AudioHarness -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" -resultBundlePath "$BUNDLE" ${skip[@]+"${skip[@]}"}

if [[ "${G04_SKIP_REALAV:-0}" == "1" ]]; then
  rm -f "$RUN_STAMP"
  echo "g04 audio: unit suites passed (G04_SKIP_REALAV=1; no result tables, not a gate run)"
  exit 0
fi

step "process-kill trial: the harness app plays, is killed with SIGKILL and relaunched (simulator)"
python3 "$SPIKE/Scripts/process_kill_trial.py" "$UDID" "$APP" "$SYLVIA_FIXTURE_CACHE/generated/g04-audio/multi" \
  "$RESULTS/process-kill-relaunch.txt"

step "excerpt portability: ffmpeg decodes the kept excerpts, the simulator measures the decodes"
ffmpeg -version | head -1 > "$EXCERPTS/decoder.txt"
kept=0
for m4a in "$EXCERPTS"/*.m4a; do
  [[ -e "$m4a" ]] || continue
  ffmpeg -nostdin -hide_banner -v error -y -i "$m4a" -map 0:a:0 -c:a pcm_f32le -f wav "${m4a%.m4a}.ffmpeg.wav"
  kept=$((kept + 1))
done
echo "decoded $kept excerpts with $(cat "$EXCERPTS/decoder.txt")"
TEST_RUNNER_SYLVIA_FIXTURE_CACHE="$SYLVIA_FIXTURE_CACHE" TEST_RUNNER_G04_RESULTS_DIR="$RESULTS" \
TEST_RUNNER_G04_PORTABILITY_DIR="$EXCERPTS" TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK="$AUDIBLE" TEST_RUNNER_G04_BOOTED_SIMULATORS="$(booted_simulators)" \
xcodebuild test-without-building -project "$PROJECT" -scheme G04AudioHarness -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" -resultBundlePath "$PORTABILITY_BUNDLE" \
  -only-testing:G04AudioTests/RealAV/PortabilityTests

step "quick capture through the system: the App Shortcut from the Shortcuts app and the control from Control Center (simulator, unlocked; ADR-0007)"
SCHEME=G04QuickCaptureUI quiet_build -destination "id=$UDID"
QC="$SPIKE/Scripts/quick_capture_simulator_attempt.sh"
BOOK="$SYLVIA_FIXTURE_CACHE/generated/g04-audio/multi"
# As built for the simulator (ad-hoc signature), then re-signed with this host's Apple Development identity (team
# A4KBDX665Z, as on a device): the system's App Intents service treats the two differently, so both are recorded.
"$QC" "$UDID" "$PROJECT" "$DERIVED" "$BOOK" "$RESULTS/quick-capture-simulator-adhoc.txt" adhoc
IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development: / {print $2; exit}')"
if [[ -n "$IDENTITY" ]]; then
  for bundle in "$APP/Frameworks/G04AudioKit.framework" "$APP/PlugIns/G04CaptureControl.appex" "$APP"; do
    codesign --force --sign "$IDENTITY" --preserve-metadata=identifier,entitlements "$bundle"
  done
  "$QC" "$UDID" "$PROJECT" "$DERIVED" "$BOOK" "$RESULTS/quick-capture-simulator-signed.txt" signed
else
  echo "no Apple Development signing identity on this host: the team-signed run was not made (pending)" \
    | tee "$RESULTS/quick-capture-simulator-signed.txt"
fi

step "results"
echo "host: $(uptime | sed 's/^ *//'); simulators booted: $(booted_simulators)"
missing=0
for table in "${EXPECTED_TABLES[@]}"; do
  if [[ ! -s "$RESULTS/$table" || ! "$RESULTS/$table" -nt "$RUN_STAMP" ]]; then
    echo "error: result table $table was not written by this run"
    missing=1
  fi
done
rm -f "$RUN_STAMP"
ls -l "$RESULTS"
(( missing == 0 )) || exit 1
echo "g04 audio: all builds, tests, the process-kill trial, the portability check and the quick-capture runs passed; ${#EXPECTED_TABLES[@]} result tables written"
