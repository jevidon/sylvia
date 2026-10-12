#!/usr/bin/env bash
# Copies the logs of the last G0.5 AI CI run (Spikes/G05-AI/.build/g05-ci) into Docs/Stage0/evidence/G05-AI/,
# each with a header naming its environment, command and commit. Optionally also files a mutation-check log.
#
#   Spikes/G05-AI/Scripts/collect-evidence.sh [mutation-log]
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
WORK="$SYLVIA_ROOT/Spikes/G05-AI/.build/g05-ci"
OUT="$SYLVIA_ROOT/Docs/Stage0/evidence/G05-AI"
mkdir -p "$OUT"

HOST="host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
XCODE="$(xcodebuild -version | tr '\n' ' ')"
COMMIT="$(git -C "$SYLVIA_ROOT" rev-parse --short HEAD)"
SIM="simulator: Sylvia-M0-g05-ai, $SYLVIA_SIM_DEVICE_TYPE, $SYLVIA_SIM_RUNTIME"

# file <source> <dest name> <environment> <command>
file() {
  local source="$1" dest="$OUT/$2"
  [[ -f "$source" ]] || { echo "missing $source" >&2; return 1; }
  {
    echo "# environment: $3"
    echo "# toolchain: $XCODE"
    echo "# command: $4"
    echo "# commit: $COMMIT (log copied $(date -u +%Y-%m-%dT%H:%MZ))"
    echo
    cat "$source"
  } >"$dest"
  local size
  size="$(wc -c <"$dest")"
  if (( size > 2000000 )); then echo "FAIL: $dest is over 2 MB" >&2; return 1; fi
  echo "wrote $dest ($size bytes)"
}

file "$WORK/host-build.log" host-build.log "$HOST" "swift build --build-tests (Scripts/ci.d/70-g05-ai.sh)"
file "$WORK/host-test.log" host-test.log "$HOST" "swift test, live tests not opted in (Scripts/ci.d/70-g05-ai.sh)"
file "$WORK/live-dry-run.log" live-tests-dry-run-loopback.log "$HOST; loopback fake server, NOT a real provider" "Spikes/G05-AI/Scripts/live-tests-dry-run.sh"
file "$WORK/contract-exports.log" contracts-swift-exports.log "$HOST" "Spikes/G05-AI/Scripts/validate-exports.py on instances exported by ContractExportTests"
{ cat "$WORK/contracts.log"; echo; cat "$WORK/contracts-invalid-reasons.log"; } >"$WORK/contracts-combined.log"
file "$WORK/contracts-combined.log" contracts.log "$HOST" "Scripts/validate-contracts.py Contracts; Spikes/G05-AI/Scripts/explain-invalid-fixtures.py Contracts"
file "$WORK/sim-package-test.log" simulator-package-test.log "$SIM" "xcodebuild test -scheme G05AI-Package (Scripts/ci.d/70-g05-ai.sh)"
file "$WORK/sim-probe-test.log" simulator-ats-keychain-probe.log "$SIM" "xcodebuild test -scheme G05ATSProbe: three ATS variants and the suspension UI test (Scripts/ci.d/70-g05-ai.sh)"
if [[ $# -ge 1 ]]; then
  file "$1" mutation-checks.log "$HOST" "cd Spikes/G05-AI && python3 Scripts/mutation-checks.py"
fi
