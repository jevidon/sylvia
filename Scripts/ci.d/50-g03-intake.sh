#!/usr/bin/env bash
# G0.3 intake (share-extension handoff, .sylviapack v1, container layout). ADR-0010; report Docs/Stage0/G03-Intake.md.
#
#   Scripts/ci.d/50-g03-intake.sh            # everything below
#   G03_LOG_DIR=<dir> Scripts/ci.d/50-g03-intake.sh   # where the step logs go (default .build/ci-logs/g03-intake)
#   G03_SIM_NAME=<name> Scripts/ci.d/50-g03-intake.sh # the simulator to use (default Sylvia-M0-g03-intake). Anyone
#                                                       # else running this (a reviewer, a second worktree) passes a name
#                                                       # of their own: ADR-0002, one simulator per job.
#   G03_SKIP_ZIP_EVAL=1 Scripts/ci.d/50-g03-intake.sh # skip step 8's 20-minute library evaluation (the dependency
#                                                       # probe still runs); the clean evidence run never skips it
#
# Steps (each exits non-zero on failure):
#   1. fixtures: the deterministic >4 GiB pack (generate-g03-intake-pack.sh, which downloads the LibriVox file the pack
#      holds with Scripts/fixtures/fetch.sh only when it has to rebuild the pack)
#   2. host: IntakeKit test suite (swift test)
#   3. host: large-pack run (validate, extract, cross-checks, truncation sweep, multi-GiB copy memory)
#   4. host: SIGKILL of the handoff writer at every step and at random moments of a 4.5 GiB copy
#   5. host: current code's handoff.json and pack manifest validate against the contract schemas, and the schemas
#      and the Swift readers give the same verdict on edge inputs except the documented divergences
#   6. simulator: IntakeKit test suite on iOS (xcodebuild, IntakeKit-Package scheme)
#   7. simulator: harness app in-app tests (layout, >4 GiB pack), UI tests through the real share sheet, the Files
#      app and the document picker, and open-in through the system's document handling (sim-open-in.sh)
#   8. host: archive-library evidence for ADR-0010 section 3 (dependency probe; ZIP64 and truncation evaluation)
# Host scripts work in mktemp directories of their own and test sandboxes are removed per test, so parallel runs
# do not collide. The fixture cache ($SYLVIA_FIXTURE_CACHE) is shared by every run on the Mac:
#   - Step 1 is the only step that writes the cache's files. The generator holds an exclusive lock for its whole
#     check-and-build sequence, including the LibriVox download a rebuild needs, and publishes each file with one rename,
#     so a run that overlaps a rebuild in another worktree sees the previous complete file or the new one, never part of
#     one (review R2-06), and two runs of this drop-in never download at the same time (review R4-06; before it, step 1
#     also ran fetch.sh outside the lock).
#   - Steps 2 to 8 only read the cache's files; steps 3 and 8 keep their own work in mktemp folders beside them,
#     removed on exit.
#   - fetch.sh downloads to the fixed path <name>.partial and then renames it. A fetch.sh run outside the lock (another
#     workstream's, or a person fetching every fixture) at the same time as a rebuild's can therefore truncate the other's
#     download or publish a file the other is still writing. The pinned pack digest stops a wrong pack from being
#     published, so here the effect is a failed run; the fix (download to a mktemp name, verify, then rename) is
#     requested from fetch.sh's owner (report, "Requests to the owners of shared files").
# Needs: Xcode 27.0, XcodeGen, Python 3, network for the package and fixture downloads, about 30 GiB free disk.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/sim.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

spike="$SYLVIA_ROOT/Spikes/G03-Intake"
kit="$spike/IntakeKit"
app="$spike/App"
logs="${G03_LOG_DIR:-$SYLVIA_ROOT/.build/ci-logs/g03-intake}"
cache="$SYLVIA_FIXTURE_CACHE/generated/g03-intake"
pack="$cache/large.sylviapack"
bundle_id="com.jevidon.sylvia.spike.intake"
mkdir -p "$logs"

step() { echo; echo "=== $* ($(date -u +%H:%M:%SZ))"; }
# Runs a command with its full output in a log; prints the log's tail on failure.
logged() {
  local log="$1"; shift
  if "$@" >"$log" 2>&1; then return 0; fi
  echo "FAILED: $* (log: $log)"; tail -n 60 "$log"; return 1
}

# Compiler warnings in our own Swift sources fail the step; third-party checkouts are ignored.
check_warnings() {
  local own
  own="$(grep -E '\.swift:[0-9]+:[0-9]+: warning' "$1" | grep -v -E '/(\.build/checkouts|SourcePackages/checkouts)/' | sort -u || true)"
  if [[ -n "$own" ]]; then echo "compiler warnings in our sources:"; echo "$own"; return 1; fi
  echo "  no compiler warnings in our sources"
}

# For scripts that write their own log (given as their last argument).
own_log() {
  local log="$1" script="$2"
  if "$script" "$log" >/dev/null 2>&1; then return 0; fi
  echo "FAILED: $script (log: $log)"; tail -n 60 "$log"; return 1
}
# The same for a script that takes arguments before its log: own_log_args <log> <script> <args>...
own_log_args() {
  local log="$1"; shift
  if "$@" "$log" >/dev/null 2>&1; then return 0; fi
  echo "FAILED: $* (log: $log)"; tail -n 60 "$log"; return 1
}

echo "G0.3 intake CI drop-in"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "git: $(git -C "$SYLVIA_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "logs: $logs"

step "1. fixtures"
"$SYLVIA_ROOT/Scripts/fixtures/generate-g03-intake-pack.sh"

step "2. host: IntakeKit tests (swift test)"
logged "$logs/host-intakekit-tests.log" bash -c "cd '$kit' && swift test --force-resolved-versions"
grep -E 'Test run with|contract fixtures:|in-memory plain-text|direct file URL provider|uncoordinated writer|coordinated writer|short deflate stream|aggregate expansion:|slow but moving provider|progress then stall:|load progress follows|EPUB folder|insufficient space:|cancel |coordinator cancelled|raw file|raw Finder file|non-ASCII paths|canonical equivalence:|canonical twins of ASCII|contract names checked:|entry limit:|manifest size limit:|handoff.json size:|stall timeout vs|created_at continuity:' \
  "$logs/host-intakekit-tests.log" | grep -v '^◇' | sed 's/^/  /'
check_warnings "$logs/host-intakekit-tests.log"

step "3. host: large-pack run"
own_log "$logs/host-large-pack.log" "$spike/scripts/host-large-pack.sh"
grep -E 'ACCEPTED|memory:|truncation-sweep:|copy-measure:|extracted=|source   =' "$logs/host-large-pack.log" | sed 's/^/  /'

step "4. host: kill the handoff writer at every step and at random moments"
own_log "$logs/host-handoff-kill.log" "$spike/scripts/host-handoff-kill.sh"
grep -E '^failures=|^kills that landed|^uninterrupted copy' "$logs/host-handoff-kill.log" | sed 's/^/  /'

step "5. host: current output validates against the contract schemas; schema and reader agree on edge inputs"
logged "$logs/host-contract-instances.log" "$spike/scripts/check-contract-instances.sh"
grep -v -E '^  ok: ' "$logs/host-contract-instances.log" | sed 's/^/  /'

step "6. simulator: IntakeKit tests on iOS"
sim_name="${G03_SIM_NAME:-Sylvia-M0-g03-intake}"
udid="$(sylvia_sim_udid "$sim_name")"
sylvia_sim_boot "$udid"
# Shut it down when this script ends, however it ends (M0 final review CC-05).
trap 'sylvia_sim_shutdown "$udid"' EXIT
runtime="$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == sys.argv[1]:
            print(runtime.rsplit(".", 1)[-1], d["name"])
' "$udid")"
devtype="$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["udid"] == sys.argv[1]:
            print(d.get("deviceTypeIdentifier", "?").rsplit(".", 1)[-1])
' "$udid")"
echo "simulator: $runtime ($devtype), $udid"
logged "$logs/sim-intakekit-tests.log" bash -c "cd '$kit' && xcodebuild test -scheme IntakeKit-Package \
  -destination 'id=$udid' -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution"
grep -E 'Test run with|contract fixtures:|in-memory plain-text|direct file URL provider|aggregate expansion:|slow but moving provider|progress then stall:|load progress follows|cancel |coordinator cancelled|raw file|non-ASCII paths|canonical equivalence:|canonical twins of ASCII|contract names checked:|entry limit:|manifest size limit:|handoff.json size:|stall timeout vs|created_at continuity:|\*\* TEST' \
  "$logs/sim-intakekit-tests.log" | grep -v '^◇' | sed 's/^/  /'
check_warnings "$logs/sim-intakekit-tests.log"

step "7. simulator: harness app, share extension, in-app and UI tests"
# Fresh containers every run: uninstalling removes the app's data and its App Group container.
xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true
sylvia_generate "$app"
logged "$logs/sim-app-build.log" bash -c "cd '$app' && xcodebuild build-for-testing -project G03Intake.xcodeproj \
  -scheme IntakeHarness -destination 'id=$udid' -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution"
check_warnings "$logs/sim-app-build.log"
grep -E 'missing a dependency' "$logs/sim-app-build.log" | sort -u | sed 's/^/  Xcode build-system warning (package targets; see report): /' || true
# Files app probe (FilesAppUITests): an EPUB in Files > On My iPhone, placed through the simulator's local
# file-provider storage (the same content each run).
files_storage() {
  xcrun simctl get_app_container "$udid" com.apple.DocumentsApp groups 2>/dev/null \
    | awk -F'\t' '$1 == "group.com.apple.FileProvider.LocalStorage" {print $2}'
}
local_storage="$(files_storage)"
if [[ -z "$local_storage" ]]; then
  # A simulator whose Files app has never run may not have the group container yet: run Files once.
  xcrun simctl launch "$udid" com.apple.DocumentsApp >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    local_storage="$(files_storage)"; [[ -n "$local_storage" ]] && break; sleep 2
  done
  xcrun simctl terminate "$udid" com.apple.DocumentsApp >/dev/null 2>&1 || true
fi
[[ -n "$local_storage" ]] || { echo "Files probe: On My iPhone storage not found in simulator $udid"; exit 1; }
mkdir -p "$local_storage/File Provider Storage"
cp "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" "$local_storage/File Provider Storage/G03 Files Share.epub"
echo "  Files probe: se-walden.epub placed in On My iPhone as 'G03 Files Share.epub'"
status=0
TEST_RUNNER_G03_FILES_PROBE=placed TEST_RUNNER_G03_LARGE_PACK="$pack" logged "$logs/sim-app-tests.log" bash -c "cd '$app' && xcodebuild test-without-building \
  -project G03Intake.xcodeproj -scheme IntakeHarness -destination 'id=$udid' -derivedDataPath .build/DerivedData" || status=1
grep -E 'G03-EVIDENCE|Test run with|Test Case .*(passed|failed|skipped)|\*\* TEST' "$logs/sim-app-tests.log" | sed 's/^/  /'
# The UI tests leave multi-GiB files in the simulator's containers; free them.
xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true
(( status == 0 )) || { echo "simulator app tests FAILED"; exit 1; }
# Open-in through the system's own document handling (simctl openurl -> Documents/Inbox -> onOpenURL).
open_in_status=0
own_log_args "$logs/sim-open-in.log" "$spike/scripts/sim-open-in.sh" "$udid" \
  "$app/.build/DerivedData/Build/Products/Debug-iphonesimulator/IntakeHarness.app" || open_in_status=1
grep -E '^  (ok|FAIL):|harness:|^failures=' "$logs/sim-open-in.log" | sed 's/^/  /'
xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true
(( open_in_status == 0 )) || { echo "simulator open-in FAILED"; exit 1; }

step "8. host: archive-library evidence (ADR-0010 section 3)"
own_log "$logs/zip-dependency-probe.log" "$spike/ZipEval/dependency-probe.sh"
grep -E '^ok:|^CHANGED:|exit status of the resolve' "$logs/zip-dependency-probe.log" | sed 's/^/  /'
if [[ "${G03_SKIP_ZIP_EVAL:-0}" == 1 ]]; then
  echo "  ZIP library evaluation skipped (G03_SKIP_ZIP_EVAL=1)"
else
  own_log "$logs/zip-eval.log" "$spike/ZipEval/run-eval.sh"
  grep -E 'write ok|read ok entries|ACCEPTED|did not finish|^-- |eval finished' "$logs/zip-eval.log" | cut -c1-160 | sed 's/^/  /'
fi

echo
echo "G0.3 intake CI drop-in passed"
