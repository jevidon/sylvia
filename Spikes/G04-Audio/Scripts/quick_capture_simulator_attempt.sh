#!/usr/bin/env bash
# Runs the quick-capture intent through the system on the (unlocked) simulator, from the two surfaces the simulator can
# drive: the App Shortcut in the Shortcuts app and the control in Control Center (ADR-0007; review gaps of rounds 1 and
# 5). It records which process performed CaptureMomentIntent and fails when a result the G0.4 report relies on is
# missing (review R5-06). Run by Scripts/ci.d/60-g04-audio.sh after the other tests, with the G04QuickCaptureUI scheme
# built for testing in <derived data>:
#
#   quick_capture_simulator_attempt.sh <simulator udid> <G04Audio.xcodeproj> <derived data> <multi-file book dir> <output file> <adhoc|signed>
#
# The last argument names how the installed harness is signed, which decides what is required:
#   adhoc   as Xcode signs a simulator build. Required: the control's press is performed in the harness app's process
#           and saved (process=<app>, result=saved, then "Audio excerpt saved"). Recorded, not required: the App
#           Shortcut (the system refused it in every ad-hoc run so far) and the origin's surface (the control's AppEnum
#           parameter arrived as an unknown case in the ad-hoc runs).
#   signed  re-signed with the host's Apple Development identity (team A4KBDX665Z), as on a device. Required: the App
#           Shortcut run saves origin=intent@<app> process=<app> result=saved, the control's press saves
#           origin=intent.control@<app> process=<app> result=saved, each followed by "Audio excerpt saved".
#   both    the control pressed when nothing has been heard (review R6-01): with the harness not running, the system
#           launches it and the intent answers result=nothing_to_capture; with the harness running its restored book,
#           not played since launch, the same; no record in either. And in every phase the capture records the UI test
#           counted change by exactly the number of captures the harness logged as saved (review R6-06).
#
# Steps:
# 1. Installs the harness (the script prints its code signature) with the four-file MP3 book.
# 2. Asks the Shortcuts app to run "Capture moment" by name through its URL scheme. That URL runs a user shortcut of
#    that name, not an App Shortcut, so it is expected to fail; the attempt and its result are recorded.
# 3. UI test QuickCaptureThroughShortcutsUITests: the harness plays (-g04AutoPlay YES), the test opens the Shortcuts
#    app and taps the harness's App Shortcut tile "Capture moment", as a person would.
# 4. UI test QuickCaptureThroughControlCenterUITests/testControlInControlCenterRunsTheCaptureIntent: the harness plays,
#    the test opens Control Center, removes any copy of the control an earlier run left, adds "Capture the last 30
#    seconds" from the controls gallery, reopens Control Center and presses the control, as a person would.
# 5. .../testControlPressedWhileTheHarnessIsNotRunningCapturesNothing (review R6-01; device checklist step 12): the
#    harness is terminated and the placed control pressed. The system launches the harness to perform the intent; its
#    restored book has not played in that process, so the intent must answer result=nothing_to_capture and write no
#    record, whether the restore finished before the intent arrived or not.
# 6. .../testControlPressedWhileTheRestoredBookHasNotPlayedCapturesNothing (review R6-01): the same press with the
#    harness running its restored book, never played since launch: result=nothing_to_capture, no record.
# 7. For each, reports every `capture` and `export` line the harness logged meanwhile (`origin` and `process` name the
#    entry point and the process that performed the intent), what the system logged about running the intent (linkd,
#    chronod, and the App Intents runtime in the harness), and the UI tests' screenshots (<output>-*.png), and checks that
#    the number of capture records the UI test read before and after changed by exactly the number of captures the
#    harness logged as saved (review R6-06: the tests had counted the visible rows of a lazy list).
# The harness plays at 1 % volume unless SYLVIA_AUDIBLE_PLAYBACK=1 (every launch passes -g04AudiblePlayback NO, which
# overrides the harness's persisted full-volume toggle; the UI tests do the same; the harness the system launches in
# phase 5 gets no argument, logs the quiet default and plays nothing); the script fails if the harness log says
# otherwise. Nothing here says anything about a locked device, the Lock Screen placement or the Action button
# (device checklist steps 9-13).
# Exits non-zero if the harness cannot be installed, a UI test fails (harness not playing, tile or control not found),
# a required result is missing, or a launch did not log the quiet volume.
set -uo pipefail
source "$(cd "$(dirname "$0")/../../.." && pwd)/Scripts/lib/env.sh"
UDID="$1"; PROJECT="$2"; DERIVED="$3"; BOOK="$4"; OUT="$5"; SIGNING="${6:-}"
[[ "$SIGNING" == "adhoc" || "$SIGNING" == "signed" ]] || { echo "error: the last argument must be adhoc or signed" >&2; exit 2; }
BUNDLE=com.jevidon.sylvia.spike.g04audio
if [[ "${SYLVIA_AUDIBLE_PLAYBACK:-0}" == "1" ]]; then AUDIBLE=YES; WANT_VOLUME=1.0; else AUDIBLE=NO; WANT_VOLUME=0.01; fi
APP="$DERIVED/Build/Products/Debug-iphonesimulator/G04AudioHarness.app"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/g04-quick-capture.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl terminate "$UDID" com.apple.shortcuts >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" || { echo "error: install failed" >&2; exit 1; }
# The data container can change while an install settles (seen here: the path returned right after `install` was gone
# a few seconds later), so launch once first and always look the path up again before using it.
xcrun simctl launch "$UDID" "$BUNDLE" -g04AudiblePlayback "$AUDIBLE" >/dev/null || { echo "error: launch failed" >&2; exit 1; }
sleep 3
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
data() { xcrun simctl get_app_container "$UDID" "$BUNDLE" data; }
hlog() { echo "$(data)/Documents/g04-harness.log"; }
lines() { local f; f="$(hlog)"; if [[ -f "$f" ]]; then wc -l < "$f" | tr -d ' '; else echo 0; fi; }
since() { local f; f="$(hlog)"; [[ -f "$f" ]] && tail -n +"$(( $1 + 1 ))" "$f"; }
mkdir -p "$(data)/Documents/G04Book"
cp "$BOOK"/*.mp3 "$(data)/Documents/G04Book/"
start=$(lines)

# The system log of the simulator from a local time on, filtered, one line per event (multi-line messages joined).
syslog_since() {
  xcrun simctl spawn "$UDID" log show --start "$1" --style ndjson --predicate "$2" 2>/dev/null | /usr/bin/python3 -c '
import json, sys
for line in sys.stdin:
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if "eventMessage" not in e:
        continue
    proc = e.get("processImagePath", "").rsplit("/", 1)[-1]
    msg = " ".join(e["eventMessage"].split())
    print("  " + e.get("timestamp", "")[:23] + " " + proc + ": " + msg[:700])
' | tail -n "${3:-12}"
}

{
  echo "# Quick capture through the system on the simulator (unlocked): $(xcrun simctl list devices | grep "$UDID" | sed 's/^ *//')"
  echo "# Started $(date -u +%Y-%m-%dT%H:%M:%SZ). Harness signing: $SIGNING. The harness's capture log line names the process that performed CaptureMomentIntent."
  echo "## Harness code signature (as installed)"
  codesign -dvv "$APP" 2>&1 | grep -E '^(Signature|Authority|TeamIdentifier)=' | sed 's/^/  /'
  echo "## Shortcuts-related apps installed on the simulator"
  xcrun simctl listapps "$UDID" | grep -oE 'CFBundleIdentifier = "com.apple.(shortcuts|ShortcutsActions|SystemIntents)"' | sort -u | sed 's/^/  /'
} > "$OUT"

# 2. URL scheme attempt.
xcrun simctl launch "$UDID" "$BUNDLE" -g04AutoPlay YES -g04AudiblePlayback "$AUDIBLE" >/dev/null
sleep 6
url="shortcuts://run-shortcut?name=Capture%20moment"
xcrun simctl openurl "$UDID" "$url"; rc=$?
sleep 6
{
  echo "## 1. URL scheme: openurl $url (exit $rc)"
  echo "capture lines after the URL: $(since "$start" | grep -c ' capture ')"
  echo "log:"
  xcrun simctl spawn "$UDID" log show --last 1m --style compact \
    --predicate '(process == "Shortcuts" OR process == "CoreSimulatorBridge") AND (eventMessage CONTAINS[c] "run-shortcut" OR eventMessage CONTAINS[c] "Capture moment")' \
    2>/dev/null | grep -E '^[0-9]{4}-' | cut -c1-300 | tail -n 5 | sed 's/^/  /'
} >> "$OUT"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl terminate "$UDID" com.apple.shortcuts >/dev/null 2>&1

# Runs one UI test of the G04QuickCaptureUI scheme; its screenshots are exported next to the output file.
shots=()
ui_failed=0
run_ui_test() {  # <test id> <result bundle name>
  local rc=0
  TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK="${SYLVIA_AUDIBLE_PLAYBACK:-0}" \
  xcodebuild test-without-building -project "$PROJECT" -scheme G04QuickCaptureUI -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" -resultBundlePath "$WORK/$2.xcresult" -only-testing:"G04QuickCaptureUITests/$1" \
    > "$WORK/$2.log" 2>&1 || rc=$?
  local dir="$WORK/$2-shots"
  mkdir -p "$dir"
  xcrun xcresulttool export attachments --path "$WORK/$2.xcresult" --output-path "$dir" >/dev/null 2>&1 || true
  if [[ -f "$dir/manifest.json" ]]; then
    while IFS=$'\t' read -r file name; do
      local dest="${OUT%.*}-${name}.png"
      # Downscaled to 900 px high: legible, and small enough to keep as evidence.
      cp "$dir/$file" "$dest" && sips -Z 900 "$dest" >/dev/null && shots+=("$(basename "$dest")")
    done < <(/usr/bin/python3 -c '
import json, sys
for test in json.load(open(sys.argv[1])):
    for a in test.get("attachments", []):
        print(a["exportedFileName"] + "\t" + a["suggestedHumanReadableName"].split("_0_")[0])
' "$dir/manifest.json")
  fi
  (( rc == 0 )) || ui_failed=1
  return "$rc"
}

# Prints the capture and export lines of a phase and checks them. Required (see the header): every capture line
# carries the expected origin, process and result, and each saved capture is followed by "Audio excerpt saved".
problems=()
check_phase() {  # <phase name> <first log line> <required origin regex, or "" when only process and result are required> <required: yes|no>
  local name="$1" from="$2" origin="$3" required="$4" captures exports n
  captures="$(since "$from" | grep ' capture ' || true)"
  exports="$(since "$from" | grep ' export ' || true)"
  n=$(grep -c . <<<"$captures" || true)
  echo "capture lines: $n"
  if (( n > 0 )); then
    grep -oE 'origin=[^ ]+ process=[^ ]+ app_state=[0-9]+|was_playing=[a-z]+|result=[a-z_]+|record_protection=[A-Za-z]+' <<<"$captures" | paste -sd ' ' - | sed 's/^/  /'
    grep -oE 'id=[^ ]+ status=.*' <<<"$exports" | sed 's/^/  export /'
  else
    echo "result: the system did not perform the intent; no capture was made"
  fi
  [[ "$required" == "yes" ]] || { echo "requirement: none for this build (recorded result)"; return 0; }
  local want="process=$BUNDLE "
  local bad=0
  if (( n == 0 )); then bad=1; fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    grep -q "$want" <<<"$line" || bad=1
    grep -q ' result=saved ' <<<"$line" || bad=1
    if [[ -n "$origin" ]]; then grep -qE " origin=$origin " <<<"$line" || bad=1; fi
    local id; id="$(grep -oE ' id=[^ ]+' <<<"$line" | head -1 | cut -c5-)"
    if [[ -z "$id" ]] || ! grep -q "id=$id status=Audio excerpt saved" <<<"$exports"; then bad=1; fi
  done <<<"$captures"
  if (( bad )); then
    problems+=("$name: required capture missing or wrong (want process=$BUNDLE${origin:+ origin=$origin} result=saved and Audio excerpt saved)")
    echo "requirement: FAILED (process=$BUNDLE${origin:+, origin $origin}, result=saved, Audio excerpt saved)"
  else
    echo "requirement: met (process=$BUNDLE${origin:+, origin $origin}, result=saved, Audio excerpt saved)"
  fi
}

# Review R6-06: the capture records the UI test counted before and after the press (the harness line
# `captures=<n> newest=<origin>`) must change by exactly the number of distinct captures the harness logged as saved.
check_counts() {  # <phase name> <UI test log> <before key> <after key> <first harness log line>
  local name="$1" log="$2" bkey="$3" akey="$4" from="$5" before after saved
  before="$(grep -oE "$bkey=[0-9]+" "$log" | tail -1 | cut -d= -f2)"
  after="$(grep -oE "$akey=[0-9]+" "$log" | tail -1 | cut -d= -f2)"
  saved="$(since "$from" | grep ' capture ' | grep -oE ' result=saved id=[^ ]+' | sort -u | grep -c . || true)"
  if [[ -z "$before" || -z "$after" ]]; then
    problems+=("$name: the UI test printed no capture-record counts")
    echo "capture records: not printed by the UI test"
  elif (( after - before != saved )); then
    problems+=("$name: the UI test read $before then $after capture records, but the harness logged $saved saved capture(s)")
    echo "capture records: FAILED ($before before, $after after; $saved saved capture(s) in the harness log)"
  else
    echo "capture records: $before before, $after after; $saved saved capture(s) in the harness log (consistent)"
  fi
}

# Review R6-01: a press when nothing has been heard in the harness process saves nothing. Every capture line of the
# phase must say result=nothing_to_capture (with loaded= and played_since_load=); with <required> yes, there must be one.
check_nothing() {  # <phase name> <first harness log line> <required: yes|no>
  local name="$1" from="$2" required="$3" captures n nothing
  captures="$(since "$from" | grep ' capture ' || true)"
  n=$(grep -c . <<<"$captures" || true)
  nothing=$(grep -c ' result=nothing_to_capture ' <<<"$captures" || true)
  echo "capture lines: $n ($nothing with result=nothing_to_capture)"
  if (( n > 0 )); then
    grep -oE 'origin=[^ ]+ process=[^ ]+ app_state=[0-9]+|was_playing=[a-z]+|result=[a-z_]+|loaded=[a-z]+|played_since_load=[a-z]+' <<<"$captures" | paste -sd ' ' - | sed 's/^/  /'
  fi
  if (( n != nothing )); then
    problems+=("$name: a capture line says something other than result=nothing_to_capture")
    echo "requirement: FAILED (every capture line result=nothing_to_capture, nothing saved)"
  elif [[ "$required" == "yes" ]] && (( nothing == 0 )); then
    problems+=("$name: the intent was not performed (no capture line)")
    echo "requirement: FAILED (the intent performed in the harness, answering result=nothing_to_capture)"
  elif (( nothing == 0 )); then
    echo "requirement: met (nothing saved; the intent left no capture line: the system did not launch the harness to perform it)"
  else
    echo "requirement: met (result=nothing_to_capture, nothing saved)"
  fi
}

# 3. App Shortcut tile in the Shortcuts app.
start2=$(lines)
t2="$(date '+%Y-%m-%d %H:%M:%S')"
run_ui_test QuickCaptureThroughShortcutsUITests shortcuts; ui_rc=$?
{
  echo "## 2. UI test: open the Shortcuts app and tap the App Shortcut tile 'Capture moment' while the harness plays"
  echo "xcodebuild exit $ui_rc"
  # The tests' own lines, their assertion failures and runtime issues (`error: -[...]`, `warning: -[...]`), and results.
  grep -E 'g04-quick-capture-ui|(error|warning): -\[|Test Case .*(passed|failed)' "$WORK/shortcuts.log" | sed 's/^/  /'
  echo "linkd, Shortcuts and harness log about the App Shortcut:"
  syslog_since "$t2" '(process == "linkd" OR process == "Shortcuts" OR process == "G04AudioHarness") AND NOT subsystem == "com.apple.dt.xctest" AND (eventMessage CONTAINS[c] "App Shortcut" OR eventMessage CONTAINS[c] "AppShortcutsProvider" OR eventMessage CONTAINS[c] "requiresValidBundle" OR eventMessage CONTAINS[c] "bundleIdentity" OR eventMessage CONTAINS[c] "UILinkConnectionAction")' 12
  echo "harness log lines during the UI test:"
  since "$start2" | grep -E ' (launch|output|loaded|member|autoplay|capture|export) ' | sed 's/^/  /'
  if [[ "$SIGNING" == "signed" ]]; then
    check_phase "App Shortcut ($SIGNING)" "$start2" "intent@$BUNDLE" yes
  else
    check_phase "App Shortcut ($SIGNING)" "$start2" "" no
  fi
  check_counts "App Shortcut ($SIGNING)" "$WORK/shortcuts.log" harness_captures_before harness_captures_after "$start2"
} >> "$OUT"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl terminate "$UDID" com.apple.shortcuts >/dev/null 2>&1

# 4. The control in Control Center.
start3=$(lines)
t3="$(date '+%Y-%m-%d %H:%M:%S')"
run_ui_test QuickCaptureThroughControlCenterUITests/testControlInControlCenterRunsTheCaptureIntent control; cc_rc=$?
{
  echo "## 3. UI test: add the control 'Capture the last 30 seconds' to Control Center and press it while the harness plays"
  echo "xcodebuild exit $cc_rc"
  grep -E 'g04-quick-capture-control-ui|(error|warning): -\[|Test Case .*(passed|failed)' "$WORK/control.log" | sed 's/^/  /'
  # The harness's own `Prepared surface ... (nil)` line at launch belongs to its App Shortcut parameter update (the
  # `Beginning updateAppShortcutsParameters` line after it); the one after chronod's lines is the control's action.
  echo "chronod (performs the control's action) and the App Intents runtime in the harness:"
  syslog_since "$t3" '(process == "chronod" AND (eventMessage CONTAINS "Performing control action" OR eventMessage CONTAINS "Starting to run action" OR eventMessage CONTAINS "UILinkConnectionAction")) OR (process == "G04AudioHarness" AND (eventMessage CONTAINS "Prepared surface" OR eventMessage CONTAINS "caseDisplayRepresentations" OR eventMessage CONTAINS "Invoking CaptureMomentIntent" OR eventMessage CONTAINS "Beginning updateAppShortcutsParameters")) OR (process == "G04CaptureControl" AND eventMessage CONTAINS[c] "intent")' 12
  echo "harness log lines during the UI test:"
  since "$start3" | grep -E ' (launch|output|loaded|member|autoplay|capture|export) ' | sed 's/^/  /'
  if [[ "$SIGNING" == "signed" ]]; then
    check_phase "Control ($SIGNING)" "$start3" "intent\\.control@$BUNDLE" yes
  else
    check_phase "Control ($SIGNING)" "$start3" "" yes
  fi
  check_counts "Control ($SIGNING)" "$WORK/control.log" harness_captures_before harness_captures_after "$start3"
} >> "$OUT"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl terminate "$UDID" com.apple.shortcuts >/dev/null 2>&1

# The system and harness log lines about running the control intent (phases 4 and 5).
CONTROL_LOG='(process == "chronod" AND (eventMessage CONTAINS "Performing control action" OR eventMessage CONTAINS "Starting to run action" OR eventMessage CONTAINS "UILinkConnectionAction")) OR (process == "G04AudioHarness" AND (eventMessage CONTAINS "Prepared surface" OR eventMessage CONTAINS "caseDisplayRepresentations" OR eventMessage CONTAINS "Invoking CaptureMomentIntent")) OR (process == "G04CaptureControl" AND eventMessage CONTAINS[c] "intent")'

# 5. The control pressed while the harness is not running (review R6-01; device checklist step 12).
start4=$(lines)
t4="$(date '+%Y-%m-%d %H:%M:%S')"
run_ui_test QuickCaptureThroughControlCenterUITests/testControlPressedWhileTheHarnessIsNotRunningCapturesNothing cold; cold_rc=$?
{
  echo "## 4. UI test: press the control while the harness is not running (review R6-01; device checklist step 12)"
  echo "xcodebuild exit $cold_rc"
  grep -E 'g04-quick-capture-control-ui|(error|warning): -\[|Test Case .*(passed|failed)' "$WORK/cold.log" | sed 's/^/  /'
  echo "chronod and the App Intents runtime in the harness:"
  syslog_since "$t4" "$CONTROL_LOG" 12
  echo "harness log lines during the UI test:"
  since "$start4" | grep -E ' (launch|output|loaded|member|autoplay|capture|export) ' | sed 's/^/  /'
  check_nothing "Control, harness not running ($SIGNING)" "$start4" yes
  check_counts "Control, harness not running ($SIGNING)" "$WORK/cold.log" cold_captures_before cold_captures_after "$start4"
} >> "$OUT"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1

# 6. The control pressed while the harness runs its restored book, not played since launch (review R6-01).
start5=$(lines)
t5="$(date '+%Y-%m-%d %H:%M:%S')"
run_ui_test QuickCaptureThroughControlCenterUITests/testControlPressedWhileTheRestoredBookHasNotPlayedCapturesNothing restored; restored_rc=$?
{
  echo "## 5. UI test: press the control while the harness runs its restored book, not played since launch (review R6-01)"
  echo "xcodebuild exit $restored_rc"
  grep -E 'g04-quick-capture-control-ui|(error|warning): -\[|Test Case .*(passed|failed)' "$WORK/restored.log" | sed 's/^/  /'
  echo "chronod and the App Intents runtime in the harness:"
  syslog_since "$t5" "$CONTROL_LOG" 12
  echo "harness log lines during the UI test:"
  since "$start5" | grep -E ' (launch|output|loaded|member|autoplay|capture|export) ' | sed 's/^/  /'
  check_nothing "Control, restored book not played ($SIGNING)" "$start5" yes
  check_counts "Control, restored book not played ($SIGNING)" "$WORK/restored.log" restored_captures_before restored_captures_after "$start5"
  echo "screenshots: ${shots[*]:-none}"
} >> "$OUT"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl terminate "$UDID" com.apple.shortcuts >/dev/null 2>&1

# Every harness launch in this script (from $start: the URL attempt and the UI tests) must have logged the expected
# output volume (1 % unless SYLVIA_AUDIBLE_PLAYBACK=1). A harness the system launches to perform the intent (phase 4)
# has no launch argument: it logs the quiet volume with reason=default and plays nothing, so such a line is accepted
# in every mode.
outputs="$(since "$start" | grep ' output ' || true)"
launches="$(since "$start" | grep -c ' launch ' || true)"
bad="$(grep -v "volume=$WANT_VOLUME preview_volume=$WANT_VOLUME " <<<"$outputs" | grep -v ' reason=default$' | grep . || true)"
echo "harness output: $launches launches, $(grep -c . <<<"$outputs") output lines, expected volume=$WANT_VOLUME preview_volume=$WANT_VOLUME" >> "$OUT"
if (( ${#problems[@]} == 0 )); then
  echo "requirements for a $SIGNING build: all met" >> "$OUT"
else
  printf 'requirements for a %s build: FAILED: %s\n' "$SIGNING" "${problems[*]}" >> "$OUT"
fi
cat "$OUT"
(( ui_failed == 0 )) || { echo "error: a UI test failed (see above)" >&2; exit 1; }
if [[ -n "$bad" || "$(grep -c . <<<"$outputs")" -lt "$launches" || "$launches" -lt 3 ]]; then
  echo "error: a harness launch did not log output volume=$WANT_VOLUME: $outputs" >&2
  exit 1
fi
(( ${#problems[@]} == 0 )) || { echo "error: ${problems[*]}" >&2; exit 1; }
