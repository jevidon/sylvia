#!/bin/bash
# The G0.4 drop-in's host audio output guard (M0 final review round 2, CC2-01), checked without changing the Mac's
# audio device (agents never do) and without the drop-in's hour of tests:
#   1. The real probe (Spikes/G04-Audio/Scripts/host_audio_output.swift), compiled as the drop-in compiles it, lists
#      the Mac's output devices with the presentation latency CoreAudio reports (read-only).
#   2. Copies of Scripts/ci.d/60-g04-audio.sh that stop right after the guard, with the probe replaced by stand-ins
#      that report a built-in output (0.027 s), an AirPlay output (2.012 s), no default output, and a probe that
#      prints nothing: the guard passes, stops naming the device, and warns twice, as written.
#   3. The note the drop-in prints on exit when host-load.tsv shows an output above the limit during the run.
# Every copy and stand-in is under .build/scratch/g04-output-guard-check.
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/g04-output-guard-check.sh > <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scratch="$root/.build/scratch/g04-output-guard-check"
rm -rf "$scratch"; mkdir -p "$scratch"
echo "command: Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/g04-output-guard-check.sh"
echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); load: $(uptime)"
status=0

echo
echo "== 1. the real probe (read-only)"
xcrun swiftc -swift-version 6 -warnings-as-errors -O -o "$scratch/host-audio-output" Spikes/G04-Audio/Scripts/host_audio_output.swift
echo "compiled with: xcrun swiftc -swift-version 6 -warnings-as-errors -O (exit $?)"
"$scratch/host-audio-output"; echo "exit $?"
"$scratch/host-audio-output" --tsv; echo "--tsv exit $?"

echo
echo "== 2. the guard with stand-in probes"
stand_in() { # name, tsv line or "", exit status
  printf '#!/bin/bash\nif [[ "${1:-}" == --tsv ]]; then printf %%s "%s"; [[ -n "%s" ]] && echo; exit %s; fi\necho "stand-in listing"\n' \
    "$2" "$2" "$3" > "$scratch/$1"
  chmod +x "$scratch/$1"
}
stand_in built-in $'MacBook Pro Speakers\tBuilt-in\t0.027' 0
stand_in airplay $'AirPlay\tAirPlay\t2.012' 0
stand_in none $'none\tnone\tunknown' 2
stand_in silent "" 1
make_copy() { # stand-in, extra lines after the guard
  local copy="$scratch/60-g04-audio-$1.sh"
  /usr/bin/python3 -I - "$root/Scripts/ci.d/60-g04-audio.sh" "$copy" "$root" "$scratch/$1" "$2" <<'PY'
import sys
source, target, root, probe, tail = sys.argv[1:6]
text = open(source, encoding="utf-8").read()
replacements = [
    ('source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"', f'source "{root}/Scripts/lib/env.sh"'),
    ('OUTPUT_PROBE="$SYLVIA_ROOT/$SPIKE/.build/host-audio-output"', f'OUTPUT_PROBE="{probe}"'),
    ('xcrun swiftc -swift-version 6 -warnings-as-errors -O -o "$OUTPUT_PROBE" "$SPIKE/Scripts/host_audio_output.swift"',
     'true  # the stand-in is the probe'),
]
for old, new in replacements:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
cut = text.index("# Quiet (1 % volume) unless SYLVIA_AUDIBLE_PLAYBACK=1")
text = text[:cut] + tail + "\necho 'stand-in run: the guard let the run go on'\nexit 0\n"
open(target, "w", encoding="utf-8").write(text)
PY
  chmod +x "$copy"
  echo "$copy"
}
check() { # name, expected exit, expected text
  local copy out rc
  copy="$(make_copy "$1" "")"
  out="$("$copy" 2>&1)"; rc=$?
  echo "-- stand-in '$1': exit $rc"
  echo "$out" | grep -E "^(default output|error|latency|WARN|note|the default output|stand-in run)" | sed 's/^/   /'
  if [[ $rc -eq $2 ]] && grep -qF "$3" <<<"$out"; then echo "   as expected"; else echo "   PROBLEM: expected exit $2 and '$3'"; status=1; fi
}
check built-in 0 "the default output 'MacBook Pro Speakers' (Built-in, 0.027 s) is within the limit"
check airplay 1 "error: the Mac's default output device is 'AirPlay' (transport AirPlay), with a presentation"
check none 0 "WARN the default output's presentation latency could not be read"
check silent 0 "WARN the default output's presentation latency could not be read"

echo
echo "== 3. the exit note when host-load.tsv shows a slow output during the run"
tsv="$scratch/host-load.tsv"
{
  echo "# header"
  printf 'utc\tload_1m\tload_5m\tload_15m\tbooted_simulators\tdefault_output\toutput_transport\toutput_latency_s\n'
  printf '2026-10-20T01:00:00Z\t2.0\t2.0\t2.0\t1\tMacBook Pro Speakers\tBuilt-in\t0.027\n'
  printf '2026-10-20T01:00:30Z\t2.0\t2.0\t2.0\t1\tAirPlay\tAirPlay\t2.012\n'
} > "$tsv"
copy="$(make_copy built-in "HOST_LOAD=\"$tsv\"")"
out="$("$copy" 2>&1)"; rc=$?
echo "$out" | grep -E "^(note|      the tests)" | sed 's/^/   /'
if [[ $rc -eq 0 ]] && grep -qF "note: at 2026-10-20T01:00:30Z the default output was AirPlay (AirPlay, presentation latency 2.012 s), above the 0.300 s limit:" <<<"$out"; then
  echo "   as expected"
else
  echo "   PROBLEM: the exit note is missing"; status=1
fi
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
