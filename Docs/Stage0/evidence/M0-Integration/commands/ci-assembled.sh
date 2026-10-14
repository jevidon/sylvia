#!/bin/bash
# The M0 assembly's complete CI run (integration log section 7.6): Scripts/ci.sh with one simulator name of this
# agent's own for every drop-in, loopback-only G0.2 servers, test volume (SYLVIA_AUDIBLE_PLAYBACK unset) and every
# drop-in's results under .build/ (no evidence-folder variable set). Run from a clean tree after deleting every
# .build/DerivedData and the CI outputs, and after Scripts/fixtures/fetch.sh and the cache generators.
#   Docs/Stage0/evidence/M0-Integration/commands/ci-assembled.sh <log> [ci.sh filters...]
# The run itself used an identical copy under .build/scratch/run-ci.sh (only the root line differs).
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
log="$1"; shift
cd "$root"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
sim=Sylvia-M0-assemble
export SYLVIA_G06_SIM=$sim G01_EPUB_SIM_NAME=$sim G01_PDF_SIM_NAME=$sim G03_SIM_NAME=$sim \
  SYLVIA_G02_SIMULATOR=$sim G04_SIM_NAME=$sim SYLVIA_G05_SIM_NAME=$sim G05_SIM_NAME=$sim
export G02_LOOPBACK_ONLY=1
unset G04_RESULTS_DIR G04_DEVICE_FIXTURES G04_SKIP_REALAV G04_KEEP_SIM G02_EVIDENCE_DIR G05_LOG_DIR SYLVIA_AUDIBLE_PLAYBACK SYLVIA_LIVE_PROVIDER_TESTS
{
  echo "commit: $(git rev-parse HEAD); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "simulator name for every drop-in: $sim; G02_LOOPBACK_ONLY=1; SYLVIA_AUDIBLE_PLAYBACK unset (test volume 0.01)"
  echo "command: Scripts/ci.sh $*"
} > "$log"
Scripts/ci.sh "$@" >> "$log" 2>&1
status=$?
{
  echo "ci.sh exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log"
exit $status
