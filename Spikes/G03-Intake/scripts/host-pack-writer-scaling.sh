#!/usr/bin/env bash
# G0.3 review R4-02: how the spike's PackWriter scales with the number of entries, now that the reader accepts the
# 10,000-entry limit (9,998 files plus the two manifest entries). Evidence only; not run by CI.
#
#   Spikes/G03-Intake/scripts/host-pack-writer-scaling.sh <log>
#
# sylviapack-tool gen-many writes one-byte cover files with PackWriter (ZIPFoundation's Archive.addEntry for each
# entry, then a full sync and the writer's self-validation with PackReader) at several entry counts, with paths of
# 20 bytes and of 512 bytes (the limit). Work files live in a mktemp directory under .build, removed on exit. Timings
# are taken while other jobs share the Mac: indicative only, with the load recorded before and after.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
log="${1:?usage: host-pack-writer-scaling.sh <log>}"
mkdir -p "$(dirname "$log")"
log="$(cd "$(dirname "$log")" && pwd)/$(basename "$log")"
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"
mkdir -p "$SYLVIA_ROOT/.build"
work="$(mktemp -d "$SYLVIA_ROOT/.build/g03-writer-scaling.XXXXXX")"
trap 'rm -rf "$work"' EXIT

exec >"$log" 2>&1
echo "G0.3 PackWriter time against the number of entries"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); commit $(git -C "$SYLVIA_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
echo "load before: $(uptime)"
(cd "$kit" && swift build --force-resolved-versions --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"
for bytes in 20 512; do
  for files in 1000 2000 4000 9998; do
    "$tool" gen-many "$work/pack-$bytes-$files.sylviapack" "$work/src" "$files" "$bytes"
    rm -f "$work/pack-$bytes-$files.sylviapack"
  done
done
echo "load after: $(uptime)"
echo "writer scaling finished"
