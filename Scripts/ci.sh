#!/usr/bin/env bash
# Local CI entry point. Runs every executable drop-in in Scripts/ci.d/ in name order.
#
#   Scripts/ci.sh                 # run everything
#   Scripts/ci.sh contracts g04   # run only drop-ins whose file name contains one of the words
#
# The 00-* drop-ins check the checkout itself (00-git-lfs: the Git LFS files are present, ADR-0002). They run first in
# every run, also when the filter words do not name them (a run whose words match no drop-in still stops with "no CI
# steps matched"); if one fails, the run stops there, because every later result would come from an incomplete
# checkout.
#
# Each drop-in is self-contained, idempotent and exits non-zero on failure. Logs go to
# .build/ci-logs/<drop-in>.log. GitHub Actions runs this same script (ADR-0002).
set -uo pipefail
source "$(cd "$(dirname "$0")/lib" && pwd)/env.sh"

LOG_DIR="$SYLVIA_ROOT/.build/ci-logs"
mkdir -p "$LOG_DIR"
filters=("$@")
failed=()
steps=()
matched=0
ran=0

for step in "$SYLVIA_ROOT"/Scripts/ci.d/*.sh; do
  [[ -x "$step" ]] || continue
  name="$(basename "$step" .sh)"
  match=1
  if (( ${#filters[@]} )); then
    match=0
    for f in "${filters[@]}"; do [[ "$name" == *"$f"* ]] && match=1; done
  fi
  (( match )) && matched=$((matched + 1))
  if (( match )) || [[ "$name" == 00-* ]]; then steps+=("$step"); fi
done

if (( matched == 0 )); then
  echo "no CI steps matched: ${filters[*]:-}" >&2
  exit 2
fi

for step in "${steps[@]}"; do
  name="$(basename "$step" .sh)"
  ran=$((ran + 1))
  echo "==> $name"
  start=$SECONDS
  if "$step" >"$LOG_DIR/$name.log" 2>&1; then
    echo "    pass ($((SECONDS - start))s)"
    # A passing drop-in's warnings are shown too, not only kept in its log (ADR-0014, review R3-05).
    grep -E "^WARN " "$LOG_DIR/$name.log" | sed "s/^/    | /"
  else
    echo "    FAIL ($((SECONDS - start))s) - see $LOG_DIR/$name.log"
    tail -n 30 "$LOG_DIR/$name.log" | sed 's/^/    | /'
    failed+=("$name")
    if [[ "$name" == 00-* ]]; then
      echo "FAILED: $name, a check of the checkout itself; no other drop-in was run. Fix the checkout as its message says."
      exit 1
    fi
  fi
done

if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all $ran steps passed"
