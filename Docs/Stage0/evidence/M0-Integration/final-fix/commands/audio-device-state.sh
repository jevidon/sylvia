#!/bin/bash
# Records, read-only, which audio output device the build Mac uses (the iOS Simulator plays through the Mac's default
# output device): each device's name, its default roles, transport and sample rate, from system_profiler. Changes
# nothing: agents never change the Mac's audio device, volume or mute state. Appends to the log given.
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/audio-device-state.sh <log>
set -u
log="$1"
{
  echo "== $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(sysctl -n vm.loadavg)"
  system_profiler SPAudioDataType 2>/dev/null | awk '
    /^        [^ ].*:$/ { name = $0; sub(/^ +/, "", name); sub(/:$/, "", name); next }
    /Default Output Device: Yes/ { roles[name] = roles[name] " default-output" }
    /Default System Output Device: Yes/ { roles[name] = roles[name] " default-system-output" }
    /Default Input Device: Yes/ { roles[name] = roles[name] " default-input" }
    /Output Channels:/ { out[name] = 1 }
    /Transport:/ { t = $0; sub(/^ *Transport: */, "", t); transport[name] = t }
    /Current SampleRate:/ { r = $0; sub(/^ *Current SampleRate: */, "", r); rate[name] = r }
    END { for (n in out) printf "output device: %s; transport %s; %s Hz;%s\n", n, transport[n], rate[n], (roles[n] == "" ? " no default role" : roles[n]) }' | sort
} >> "$log"
