#!/usr/bin/env bash
# G0.3 T07 host run with real process death: the share extension's write sequence (the same HandoffSession code)
# runs in a separate process that is SIGKILLed (1) at every step of the sequence and (2) at random moments while
# copying a 4.5 GiB file. After each kill the main app's scan must accept nothing incomplete, and the cleanup
# policy must remove the leftovers once they are stale.
#
#   Spikes/G03-Intake/scripts/host-handoff-kill.sh [log]
set -uo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
log="${1:-$SYLVIA_ROOT/Docs/Stage0/evidence/G03-Intake/host-handoff-kill.log}"
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1

cache="$SYLVIA_FIXTURE_CACHE/generated/g03-intake"
kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"
# This run's own working directory, removed on exit (parallel runs never share or delete each other's files).
run="$(mktemp -d "$cache/kill-run.XXXXXX")"
trap 'rm -rf "$run"' EXIT
echo "# G0.3 host kill test"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "environment: host, $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
"$SYLVIA_ROOT/Scripts/fixtures/generate-g03-intake-pack.sh" >/dev/null || exit 1
(cd "$kit" && swift build --force-resolved-versions --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"
mkdir -p "$run/src"
head -c 3000001 "$cache/work/part-01.caf" > "$run/src/a.epub"
head -c 2000003 "$cache/work/part-01.caf" > "$run/src/b.mp3"

failures=0
check() { if [[ "$1" != "$2" ]]; then echo "  FAIL: $3 (got '$1', want '$2')"; failures=$((failures + 1)); fi; }
count_manifests() { find "$1" -name handoff.json 2>/dev/null | wc -l | tr -d ' '; }
field() { sed -n "s/.*[ :]$1=\([0-9]*\).*/\1/p" <<<"$2" | head -1; }   # [ :] so "accepted" never matches "already_accepted"

echo; echo "## 1. SIGKILL at every step of the write sequence"
steps="checkSpace:1 createStagingDirectory:1 openSource:1 createDestination:1 readChunk:2 writeChunk:2 syncItem:1 closeItem:1 verifyItem:1 checkSpace:2 openSource:2 createDestination:2 readChunk:5 writeChunk:5 syncItem:2 closeItem:2 verifyItem:2 syncItemsDirectory:1 writeManifestTemporary:1 syncManifestTemporary:1 renameManifest:1 syncHandoffDirectory:1"
for spec in $steps; do
  step="${spec%%:*}"; occ="${spec##*:}"
  inbox="$run/$step-$occ/inbox"; staging="$run/$step-$occ/staging"
  mkdir -p "$inbox"
  out="$("$tool" handoff-kill "$inbox" "$step" "$occ" "$run/src/a.epub" "$run/src/b.mp3" 2>&1)"; status=$?
  manifests="$(count_manifests "$inbox")"
  fresh="$("$tool" scan "$inbox" "$staging")"
  stale="$("$tool" scan "$inbox" "$staging" 7300)"
  printf '%-26s exit=%-3s receipt_printed=%-3s manifests=%s | fresh scan: %s | +2h scan: %s\n' "$step#$occ" "$status" \
    "$([[ "$out" == *RECEIVED* ]] && echo yes || echo no)" "$manifests" "$(head -1 <<<"$fresh")" "$(head -1 <<<"$stale")"
  check "$status" 137 "$step#$occ: process should die by SIGKILL"
  check "$([[ "$out" == *RECEIVED* ]] && echo yes || echo no)" no "$step#$occ: no receipt"
  if [[ "$step" == syncHandoffDirectory ]]; then
    check "$manifests" 1 "after the commit rename the handoff is complete"
    check "$(field accepted "$fresh")" 1 "complete handoff accepted"
  else
    check "$manifests" 0 "$step#$occ: no manifest for incomplete bytes"
    check "$(field accepted "$fresh")" 0 "$step#$occ: nothing accepted"
    check "$(field accepted "$stale")" 0 "$step#$occ: nothing accepted later"
    check "$(ls "$inbox" | wc -l | tr -d ' ')" 0 "$step#$occ: stale leftovers removed"
  fi
done

echo; echo "## 2. SIGKILL at random moments while copying the 4.5 GiB file"
big="$cache/work/part-01.caf"
# Measure one uninterrupted copy first, so the kill times are drawn from inside the copy (10 % to 90 % of its time)
# rather than from a fixed range that a fast disk can outrun. The clock is read in one process around the child: an
# earlier version read time.monotonic_ns() in two separate Python processes, whose clocks start at each process's
# own launch on macOS, measured -0.00 s and so killed every writer at launch, before it copied anything.
mkdir -p "$run/measure/inbox"
big_size="$(stat -f %z "$big")"
copy_seconds="$(/usr/bin/python3 - "$tool" "$run/measure/inbox" "$big" <<'PY'
import subprocess, sys, time
start = time.monotonic()
done = subprocess.run([sys.argv[1], "handoff", sys.argv[2], sys.argv[3]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
elapsed = time.monotonic() - start
print(f"{elapsed:.2f}" if done.returncode == 0 else "failed")
PY
)"
rm -rf "$run/measure"
[[ "$copy_seconds" != failed ]] || { echo "measurement copy failed"; exit 1; }
echo "uninterrupted copy of $big_size bytes (process start to exit): ${copy_seconds}s"
if ! /usr/bin/python3 -c "import sys; sys.exit(0 if float('$copy_seconds') >= 0.5 else 1)"; then
  echo "FAIL: the measured copy time is implausibly short; kill times would not land inside the copy"; exit 1
fi
mid_copy=0
for i in $(seq 1 12); do
  inbox="$run/random-$i/inbox"; staging="$run/random-$i/staging"; mkdir -p "$inbox"
  delay="$(/usr/bin/python3 -c "import random; random.seed($i); print(f'{random.uniform(0.1, 0.9) * $copy_seconds:.2f}')")"
  "$tool" handoff "$inbox" "$big" > "$run/random-$i.out" 2>&1 &
  pid=$!
  sleep "$delay"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; status=$?
  received="$([[ "$(cat "$run/random-$i.out")" == *RECEIVED* ]] && echo yes || echo no)"
  manifests="$(count_manifests "$inbox")"
  bytes="$(find "$inbox" -type f -path '*items*' -exec stat -f %z {} \; 2>/dev/null | head -1)"
  fresh="$("$tool" scan "$inbox" "$staging")"
  stale="$("$tool" scan "$inbox" "$staging" 7300)"
  printf 'kill after %ss: exit=%s receipt=%s manifests=%s copied=%s bytes | fresh: %s | +2h: %s\n' "$delay" "$status" "$received" "$manifests" "${bytes:-0}" "$(head -1 <<<"$fresh")" "$(head -1 <<<"$stale")"
  # Mid-copy: killed, no manifest, and part of the file (more than nothing, less than all of it) was copied.
  if [[ "$status" == 137 && "$manifests" == 0 && "${bytes:-0}" -gt 0 && "${bytes:-0}" -lt "$big_size" ]]; then
    mid_copy=$((mid_copy + 1))
  fi
  if [[ "$received" == yes ]]; then
    # The copy finished before the kill: receipt printed means a complete manifest exists and is accepted.
    check "$manifests" 1 "receipt implies a manifest"
    check "$(field accepted "$fresh")" 1 "received handoff accepted"
  else
    if [[ "$manifests" == 1 ]]; then
      echo "  (killed after the commit rename but before printing: the complete handoff is accepted)"
      check "$(field accepted "$fresh")" 1 "complete handoff accepted"
    else
      check "$(field accepted "$fresh")" 0 "incomplete copy not accepted"
      check "$(ls "$inbox" | wc -l | tr -d ' ')" 0 "stale leftovers removed"
    fi
  fi
done
echo
echo "kills that landed mid-copy (killed, no manifest, 0 < copied bytes < $big_size): $mid_copy of 12"
# The random phase is only evidence if most kills land inside the copy; the others (before the first byte, or after
# the copy finished) are still checked above, but do not count.
check "$(( mid_copy >= 8 ? 1 : 0 ))" 1 "at least 8 of 12 random kills land mid-copy"
echo "failures=$failures"
exit $(( failures > 0 ))
