#!/usr/bin/env bash
# Local CI entry point. Runs every executable drop-in in Scripts/ci.d/ in name order.
#
#   Scripts/ci.sh                 # run everything
#   Scripts/ci.sh contracts g04   # run only drop-ins whose file name contains one of the words
#
# Each drop-in is self-contained, idempotent and exits non-zero on failure. Logs go to
# .build/ci-logs/<drop-in>.log. GitHub Actions runs this same script (ADR-0002).
set -uo pipefail
source "$(cd "$(dirname "$0")/lib" && pwd)/env.sh"

LOG_DIR="$SYLVIA_ROOT/.build/ci-logs"
mkdir -p "$LOG_DIR"
filters=("$@")
failed=()
ran=0

for step in "$SYLVIA_ROOT"/Scripts/ci.d/*.sh; do
  [[ -x "$step" ]] || continue
  name="$(basename "$step" .sh)"
  if (( ${#filters[@]} )); then
    match=0
    for f in "${filters[@]}"; do [[ "$name" == *"$f"* ]] && match=1; done
    (( match )) || continue
  fi
  ran=$((ran + 1))
  echo "==> $name"
  start=$SECONDS
  if "$step" >"$LOG_DIR/$name.log" 2>&1; then
    echo "    pass ($((SECONDS - start))s)"
  else
    echo "    FAIL ($((SECONDS - start))s) - see $LOG_DIR/$name.log"
    tail -n 30 "$LOG_DIR/$name.log" | sed 's/^/    | /'
    failed+=("$name")
  fi
done

if (( ran == 0 )); then
  echo "no CI steps matched: ${filters[*]:-}" >&2
  exit 2
fi
if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all $ran steps passed"
