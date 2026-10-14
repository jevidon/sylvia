#!/usr/bin/env bash
# G0.3 review R2-06: overlapping runs of Scripts/fixtures/generate-g03-intake-pack.sh never expose a partial or
# missing fixture, and a run killed mid-rebuild leaves the published files intact.
#
#   Spikes/G03-Intake/scripts/check-generator-overlap.sh <log>
#   GENERATOR=<path> ...   # check another copy of the generator (the before-fix evidence run uses the old script)
#
# Works in a private fixture cache of its own (removed on exit), never in the shared one, so it cannot disturb other
# runs; the LibriVox download is cloned from the shared cache when it is there (else fetch.sh downloads it).
#   1. Run A (--force) builds into the empty private cache; run B (--force) starts 20 s later, while A is still
#      building. A watcher polls both published paths every 0.1 s from the start: once a path has appeared it must
#      never be missing again, and every size it shows must be the final size.
#   2. A third run (--force) is SIGKILLed with its whole process group mid-rebuild; a fourth run must get the lock at
#      once, remove the leftover rebuild folder and find the published files intact (quick check, no rebuild).
# Needs about 18 GiB free while a rebuild runs beside the published files.
set -uo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
log="${1:?usage: check-generator-overlap.sh <log>}"
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1

generator="${GENERATOR:-$SYLVIA_ROOT/Scripts/fixtures/generate-g03-intake-pack.sh}"
shared="$SYLVIA_FIXTURE_CACHE"
private="$(mktemp -d "$SYLVIA_ROOT/.build/g03-generator-overlap.XXXXXX")"
trap 'rm -rf "$private"' EXIT
out="$private/generated/g03-intake"
pack="$out/large.sylviapack"
caf="$out/work/part-01.caf"
pack_size=4846059727
caf_size=4831838986
failures=0
check() { if [[ "$2" == "$3" ]]; then echo "  ok: $1 ($2)"; else echo "  FAIL: $1: got '$2', expected '$3'"; failures=$((failures + 1)); fi; }

echo "# G0.3 generator overlap check (review R2-06)"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "environment: host, $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "load: $(uptime)"
echo "generator: ${generator#"$SYLVIA_ROOT/"}"
echo "private cache: ${private#"$SYLVIA_ROOT/"} (removed on exit)"
mkdir -p "$private/downloads"
mp3="meditationsofmarcusaurelius_01_aurelius_64kb.mp3"
if [[ -f "$shared/downloads/$mp3" ]]; then cp -c "$shared/downloads/$mp3" "$private/downloads/$mp3"; fi
export SYLVIA_FIXTURE_CACHE="$private"
(cd "$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit" && swift build --force-resolved-versions --configuration release --product sylviapack-tool 2>&1 | tail -1)

# Watcher: records every (path, size) state it sees; violations are a missing file after it appeared, or a size
# other than the final one.
watch_log="$private/watch.log"
(
  seen_pack=0; seen_caf=0
  while [[ ! -f "$private/stop-watch" ]]; do
    for entry in "pack:$pack:$pack_size" "caf:$caf:$caf_size"; do
      name="${entry%%:*}"; rest="${entry#*:}"; path="${rest%:*}"; final="${rest##*:}"
      if [[ -f "$path" ]]; then
        size="$(stat -f %z "$path" 2>/dev/null || echo gone)"
        [[ "$name" == pack ]] && seen_pack=1 || seen_caf=1
        if [[ "$size" != "$final" ]]; then echo "$(date -u +%H:%M:%S) VIOLATION $name size=$size"; fi
      else
        if [[ "$name" == pack && "$seen_pack" == 1 ]] || [[ "$name" == caf && "$seen_caf" == 1 ]]; then
          echo "$(date -u +%H:%M:%S) VIOLATION $name missing after it had been published"
        fi
      fi
    done
    sleep 0.1
  done
  echo "watcher stopped; pack seen=$seen_pack caf seen=$seen_caf"
) > "$watch_log" 2>&1 &
watcher=$!

echo; echo "## 1. Two overlapping forced rebuilds"
start=$SECONDS
"$generator" --force > "$private/run-a.log" 2>&1 &
run_a=$!
sleep 20
echo "run B starts at +$((SECONDS - start)) s (run A still running: $(kill -0 "$run_a" 2>/dev/null && echo yes || echo no))"
"$generator" --force > "$private/run-b.log" 2>&1 &
run_b=$!
wait "$run_a"; status_a=$?
inode_a="$(stat -f %i "$pack" 2>/dev/null || echo none)"
echo "run A finished at +$((SECONDS - start)) s, exit $status_a (published pack inode $inode_a)"
wait "$run_b"; status_b=$?
echo "run B finished at +$((SECONDS - start)) s, exit $status_b (published pack inode $(stat -f %i "$pack" 2>/dev/null || echo none))"
for run in a b; do echo "--- run $(tr a-z A-Z <<<"$run") output"; sed 's/^/  /' "$private/run-$run.log"; done
check "run A exit status" "$status_a" 0
check "run B exit status" "$status_b" 0
check "run B waited for run A's lock" "$(grep -c '^waiting for another run' "$private/run-b.log")" 1
check "run A matched the pinned digest" "$(grep -c '^matches the pinned digest' "$private/run-a.log")" 1
check "run B matched the pinned digest" "$(grep -c '^matches the pinned digest' "$private/run-b.log")" 1
check "run B replaced run A's published pack (a new file under the same name)" "$([[ "$(stat -f %i "$pack")" != "$inode_a" ]] && echo yes || echo no)" yes
check "published pack digest" "$(shasum -a 256 "$pack" | awk '{print $1}')" 982562b020ea7213721661fa0a6adf4d7a81c9bf68e5eda498bc417beebf0268
check "published part-01.caf digest" "$(shasum -a 256 "$caf" | awk '{print $1}')" b4e3eac6d299ef937eb52a103187a2847a63cc0084e9ab2d4c18d41bfa91bcc1

echo; echo "## 2. A rebuild killed mid-way, then a normal run"
before_inode="$(stat -f %i "$pack")"
set -m   # the killed run gets its own process group, so SIGKILL reaches its children (gen-pack) too
"$generator" --force > "$private/run-c.log" 2>&1 &
run_c=$!
set +m
for _ in $(seq 1 300); do
  partial="$(find "$out" -maxdepth 3 -path '*/.rebuild.*/work/part-01.caf' 2>/dev/null | head -1)"
  [[ -n "$partial" && "$(stat -f %z "$partial" 2>/dev/null || echo 0)" -gt 1000000000 ]] && break
  sleep 0.2
done
echo "run C's rebuild had written $(stat -f %z "$partial" 2>/dev/null || echo 0) bytes of part-01.caf when it was killed"
kill -9 -- "-$run_c" 2>/dev/null; wait "$run_c" 2>/dev/null
check "a rebuild folder was left behind by the killed run" "$(find "$out" -maxdepth 1 -name '.rebuild.*' | wc -l | tr -d ' ')" 1
started_d=$SECONDS
"$generator" > "$private/run-d.log" 2>&1; status_d=$?
echo "--- run D output ($((SECONDS - started_d)) s)"; sed 's/^/  /' "$private/run-d.log"
check "run D exit status" "$status_d" 0
check "run D did not wait for a lock (the kernel released the killed run's)" "$(grep -c '^waiting for another run' "$private/run-d.log")" 0
check "run D removed the leftover rebuild folder" "$(grep -c '^removing the leftovers of an interrupted rebuild' "$private/run-d.log")" 1
check "run D took the quick check (published files intact, nothing rebuilt)" "$(grep -c '^ok ' "$private/run-d.log")" 1
check "no rebuild folder remains" "$(find "$out" -maxdepth 1 -name '.rebuild.*' | wc -l | tr -d ' ')" 0
check "the published pack is the same file as before the killed run" "$(stat -f %i "$pack")" "$before_inode"

echo; echo "## Watcher (both sections)"
touch "$private/stop-watch"; wait "$watcher"
sed 's/^/  /' "$watch_log"
check "watcher violations (a published file missing after it appeared, or not at its final size)" "$(grep -c VIOLATION "$watch_log")" 0
check "watcher saw both files published" "$(grep -c 'pack seen=1 caf seen=1' "$watch_log")" 1

echo
echo "load: $(uptime)"
echo "failures=$failures"
exit $(( failures > 0 ))
