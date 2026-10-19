#!/bin/bash
# Runs the 60-g04-audio drop-in alone, from clean, in the fresh clone of the second round's complete run (M0 final review
# round 2, CC2-01 and evidence R2-03). In that run the drop-in stopped at its audio output guard, because the Mac's
# default output was AirPlay (2.012 s); this runner is for a later moment when the default output is a short-latency
# device (the drop-in's own guard decides, as in any run). Agents never change the Mac's audio device, volume or mute
# state: this runner only reads them.
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/ci-60-g04-audio-clone.sh <clone> <console log>
# The clone must be at the commit the complete run tested, with no uncommitted file (both recorded). Deletes the clone's
# Spikes/G04-Audio/.build and .build/ci-results/g04-audio first, so the drop-in builds and writes from clean. Records the
# commit, the screen lock state and the default audio output (both read-only) and the load at the start and the end;
# the drop-in itself records the output device and the load each minute (host-load.tsv in its results folder). Every
# player plays at test volume 0.01 (SYLVIA_AUDIBLE_PLAYBACK unset). Simulator: Sylvia-M0-final-fix (iPhone 17, iOS 26.5).
set -u
clone="$1"; console="$2"
lock_state() {
  ioreg -n Root -d1 -a | /usr/bin/python3 -I -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
users = [u for u in d.get("IOConsoleUsers", []) if u.get("kCGSSessionOnConsoleKey")]
print("IOConsoleLocked=%s CGSSessionScreenIsLocked=%s" % (bool(d.get("IOConsoleLocked")), any(u.get("CGSSessionScreenIsLocked", False) for u in users)))'
}
audio_output() {
  system_profiler SPAudioDataType 2>/dev/null | awk '
    /^        [^ ].*:$/ { name = $0; sub(/^ +/, "", name); sub(/:$/, "", name); next }
    /Default Output Device: Yes/ { d = name }
    /Transport:/ { t = $0; sub(/^ *Transport: */, "", t); transport[name] = t }
    END { print (d == "" ? "none" : d " (transport " transport[d] ")") }'
}
cd "$clone" || exit 1
source Scripts/lib/env.sh
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
rm -rf Spikes/G04-Audio/.build .build/ci-results/g04-audio
mkdir -p "$(dirname "$console")"
{
  echo "command: Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/ci-60-g04-audio-clone.sh $*"
  echo "clone: $clone; commit: $(git rev-parse HEAD); uncommitted files: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "Spikes/G04-Audio/.build and .build/ci-results/g04-audio deleted in the clone before the run"
  echo "simulator: Sylvia-M0-final-fix; SYLVIA_AUDIBLE_PLAYBACK unset (every player at test volume 0.01)"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "default audio output (system_profiler, read-only) at the start: $(audio_output)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} > "$console"
G04_SIM_NAME=Sylvia-M0-final-fix Scripts/ci.sh g04-audio >> "$console" 2>&1
status=$?
{
  echo "ci.sh exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "default audio output (system_profiler, read-only) at the end: $(audio_output)"
  echo "git status --porcelain lines in the clone after the run: $(git status --porcelain | wc -l | tr -d ' ')"
} >> "$console"
exit $status
