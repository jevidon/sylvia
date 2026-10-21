#!/bin/bash
# The complete CI run of the M0 final fix's second round (integration log section 12): Scripts/ci.sh in a new clone of
# this repository at one commit, so the tree is clean (no build products, DerivedData or CI outputs of any earlier run)
# and lies under a directory named .build (the case of final review CC-01). As the first round's
# final-fix/commands/ci-final-clone.sh, with the screen lock state and the Mac's default audio output recorded at the
# start and the end (read-only: agents never change either). Every drop-in uses this agent's one simulator name, G0.2's
# servers bind to loopback only (G02_LOOPBACK_ONLY=1), every player plays at test volume (SYLVIA_AUDIBLE_PLAYBACK
# unset) and no evidence-folder variable is set, so every drop-in writes under the clone's .build/. A sampler records the
# 1-minute load and the booted simulators every 60 seconds while the run lasts.
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/ci-final-clone.sh <commit> <clone dir> <log> <load tsv>
# The clone is made with `git clone --no-local` from the repository's main checkout (its LFS objects are copied from
# that repository's own LFS storage; nothing comes from the network), then `Scripts/setup-repo.sh` sets up Git LFS in
# the clone's own configuration. The fixtures are checked first (commands/prep-fixtures.sh of M0 assembly, run from
# the clone). Nothing is written outside the clone, the log, the load table and the shared fixture cache.
set -u
commit="$1"; clone="$2"; log="$3"; load_tsv="$4"
source_repo=/Users/jevidon/Git/sylvia
sim=Sylvia-M0-final-fix
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
{
  echo "command: Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/ci-final-clone.sh $commit $clone"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "default audio output (system_profiler, read-only) at the start: $(audio_output)"
} > "$log"
rm -rf "$clone"
mkdir -p "$(dirname "$clone")"
{
  echo "== clone"
  git clone --no-local --quiet "$source_repo" "$clone" && git -C "$clone" checkout --quiet --detach "$commit"
  echo "clone HEAD: $(git -C "$clone" rev-parse HEAD); expected $commit"
  [[ "$(git -C "$clone" rev-parse HEAD)" == "$(git -C "$clone" rev-parse "$commit")" ]] || { echo "PROBLEM: wrong commit"; exit 1; }
  echo "git status --porcelain lines: $(git -C "$clone" status --porcelain | wc -l | tr -d ' ')"
  echo "== Scripts/setup-repo.sh"
  (cd "$clone" && Scripts/setup-repo.sh) 2>&1 | tail -n 6
} >> "$log" 2>&1 || exit 1
cd "$clone" || exit 1
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
export SYLVIA_G06_SIM=$sim G01_EPUB_SIM_NAME=$sim G01_PDF_SIM_NAME=$sim G03_SIM_NAME=$sim \
  SYLVIA_G02_SIMULATOR=$sim G04_SIM_NAME=$sim SYLVIA_G05_SIM_NAME=$sim G05_SIM_NAME=$sim
export G02_LOOPBACK_ONLY=1
unset G04_RESULTS_DIR G04_DEVICE_FIXTURES G04_SKIP_REALAV G04_KEEP_SIM G02_EVIDENCE_DIR G05_LOG_DIR \
  SYLVIA_AUDIBLE_PLAYBACK SYLVIA_LIVE_PROVIDER_TESTS G01_PDF_EVIDENCE_DIR SYLVIA_HARD_RULES_EVIDENCE_DIR \
  G05_ALLOW_MISSING_CLASS_B

echo -e "utc\tload_1min\tbooted_simulators\tbooted_of_this_job" > "$load_tsv"
(
  while true; do
    booted="$(xcrun simctl list devices booted 2>/dev/null | grep -c '(Booted)' || true)"
    mine="$(xcrun simctl list devices booted 2>/dev/null | grep -c "$sim" || true)"
    load="$(sysctl -n vm.loadavg | awk '{print $2}')"
    echo -e "$(date -u +%Y-%m-%dT%H:%M:%SZ)\t$load\t$booted\t$mine" >> "$load_tsv"
    sleep 60
  done
) &
sampler=$!
trap 'kill "$sampler" 2>/dev/null || true' EXIT

{
  echo "== fixtures (commands/prep-fixtures.sh)"
  Docs/Stage0/evidence/M0-Integration/commands/prep-fixtures.sh 2>&1 | grep -E '^(==>|    exit|start|end)'
  echo "== Scripts/ci.sh"
  echo "commit: $(git rev-parse HEAD); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "clone path: $clone"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "simulator name for every drop-in: $sim; G02_LOOPBACK_ONLY=1; SYLVIA_AUDIBLE_PLAYBACK unset (test volume 0.01); G05_ALLOW_MISSING_CLASS_B unset"
  echo "ci start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log" 2>&1
Scripts/ci.sh >> "$log" 2>&1
status=$?
{
  echo "ci.sh exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "default audio output (system_profiler, read-only) at the end: $(audio_output)"
  echo "git status --porcelain lines after the run: $(git status --porcelain | wc -l | tr -d ' ')"
  git status --porcelain | head -n 20
} >> "$log" 2>&1
exit $status
