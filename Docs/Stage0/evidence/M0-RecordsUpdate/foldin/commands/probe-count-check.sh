#!/bin/bash
# The G0.5 AI drop-in's own count check of the ATS probe's tests, after the device fixes' request 9 raised its minimum
# from 39 to 42 (27 October 2026, the fold-in of m0-device-fixes into m0-records-update; integration log section 45).
# No device and no simulator: the check is run on committed logs of the probe's simulator runs.
#   Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands/probe-count-check.sh > <log>
# It takes require_tests() and MIN_PROBE_TESTS from Scripts/ci.d/70-g05-ai.sh as the working tree has it, and the
# minimum the drop-in had before the fold-in from 6a510880's copy, without running the drop-in, and runs the function,
# exactly as the drop-in's text gives it, on:
#   a. the drop-in's own probe output on the fixed probe, in the run of m0-device-fixes-ats
#      (Docs/Stage0/evidence/M0-DeviceFixes/ats/ci-70-g05-ai-sim-probe-test.log: 14 tests in each of three variants,
#      42): it must pass with the new minimum, as it did with the old;
#   b. the probe's simulator run of the G0.5 gate, before 907538f5 added a test
#      (Docs/Stage0/evidence/G05-AI/simulator-ats-keychain-probe.log: 13 in each variant, 39): it must fail with the
#      new minimum, standing for a probe that lost three tests, which the old minimum let through;
#   c. a copy of (a) under .build/scratch with one variant's line changed from 14 tests to 13 (41): it must fail with
#      the new minimum, which the old one let through.
# Exit 1 if any result differs from the expected one. Writes only under .build/scratch.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
dropin=Scripts/ci.d/70-g05-ai.sh
fixed=Docs/Stage0/evidence/M0-DeviceFixes/ats/ci-70-g05-ai-sim-probe-test.log
gate=Docs/Stage0/evidence/G05-AI/simulator-ats-keychain-probe.log
scratch="$root/.build/scratch/foldin-probe-count"
rm -rf "$scratch"; mkdir -p "$scratch"
status=0
echo "probe-count-check: HEAD $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "== the drop-in's lines (working tree)"
grep -n 'MIN_PROBE_TESTS=' "$dropin"
new="$(sed -n 's/^MIN_PROBE_TESTS=\([0-9]*\).*/\1/p' "$dropin")"
old="$(git show 6a510880:"$dropin" | sed -n 's/^MIN_PROBE_TESTS=\([0-9]*\).*/\1/p')"
echo "minimum now: $new; at 6a510880, before the fold-in: $old"
[[ "$new" == 42 && "$old" == 39 ]] || { echo "PROBLEM: expected 42 now and 39 before"; status=1; }
# The function, exactly as the drop-in has it: from its first line to the first line that is a lone closing brace.
awk '/^require_tests\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$dropin" > "$scratch/require_tests.sh"
echo "the function, as the drop-in has it ($(wc -l < "$scratch/require_tests.sh" | tr -d ' ') lines):"
sed 's/^/  | /' "$scratch/require_tests.sh"
grep -q 'Test run with \[0-9\]+ tests' "$scratch/require_tests.sh" || { echo "PROBLEM: the function was not found as expected"; status=1; }
source "$scratch/require_tests.sh"
sed 's/Test run with 14 tests in 2 suites passed/Test run with 13 tests in 2 suites passed/' "$fixed" | \
  awk 'BEGIN{n=0} /Test run with 13 tests in 2 suites passed/{n++; if (n>1) sub(/13 tests/, "14 tests")} {print}' > "$scratch/one-variant-13.log"

run() {  # <label> <log> <minimum> <expected exit: 0 or 1>
  local label="$1" log="$2" min="$3" want="$4" out s
  out="$(require_tests "$log" "$min" "simulator probe" 2>&1)"; s=$?
  printf '%s\n' "$out" | sed 's/^/    /'
  if [[ "$s" == "$want" ]]; then echo "ok    $label: exit $s, as expected"; else echo "FAIL  $label: exit $s, $want expected"; status=1; fi
}
echo
echo "== a. the fixed probe's run in the drop-in ($fixed)"
grep -Eo 'Test run with [0-9]+ tests in [0-9]+ suites? (passed|failed)' "$fixed" | sort | uniq -c | sed 's/^/  /'
run "a, minimum $new" "$fixed" "$new" 0
run "a, minimum $old" "$fixed" "$old" 0
echo
echo "== b. the G0.5 gate's probe run, before 907538f5 ($gate)"
grep -Eo 'Test run with [0-9]+ tests in [0-9]+ suites? (passed|failed)' "$gate" | sort | uniq -c | sed 's/^/  /'
run "b, minimum $new" "$gate" "$new" 1
run "b, minimum $old" "$gate" "$old" 0
echo
echo "== c. (a) with one variant's run at 13 tests (a copy under .build/scratch)"
grep -Eo 'Test run with [0-9]+ tests in [0-9]+ suites? (passed|failed)' "$scratch/one-variant-13.log" | sort | uniq -c | sed 's/^/  /'
run "c, minimum $new" "$scratch/one-variant-13.log" "$new" 1
run "c, minimum $old" "$scratch/one-variant-13.log" "$old" 0
rm -rf "$scratch"
echo
echo "result: $( ((status == 0)) && echo "pass: the minimum of 42 passes the fixed probe's 42 tests and fails 39 and 41, which 39 let through" || echo FAIL )"
exit $status
