#!/usr/bin/env bash
# The clean evidence run for the capture-envelope and anchor contracts (ADR-0016, M0-contracts.md).
#
#   Docs/Stage0/evidence/M0-contracts/commands/clean-run.sh
#
# From a committed tree: deletes the CI logs and this work's scratch directories, runs `Scripts/ci.sh contracts`
# (10-contracts and 11-capture-anchor-contracts, which includes the mutation pass) and copies both drop-in logs into the
# output, extracts the mutation pass into mutation-pass.log, writes the checker's report to check-spike-anchors.txt,
# runs the negative controls (negative-controls.log) and the cross-dialect pattern check with node
# (check-patterns.log). Output: Docs/Stage0/evidence/M0-contracts/ci-clean-run.log. Host only; no simulator, no
# network, no audio. The G0.4 probe and its head check need Swift and the G0.4 fixture cache and run separately
# (run-g04-capture-probe.sh, check-g04-head.sh).
set -uo pipefail
source "$(cd "$(dirname "$0")/../../../../../Scripts/lib" && pwd)/env.sh"

evidence="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts"
commands="$evidence/commands"
# Taken before this run writes its own logs; the steps below report this count, not the logs this run rewrites.
uncommitted="$(git -C "$SYLVIA_ROOT" status --porcelain | wc -l | tr -d ' ')"
export SYLVIA_CLEAN_RUN_UNCOMMITTED="$uncommitted"
exec > >(tee "$evidence/ci-clean-run.log") 2>&1

echo "command: Docs/Stage0/evidence/M0-contracts/commands/clean-run.sh"
echo "commit: $(git -C "$SYLVIA_ROOT" rev-parse HEAD) (branch $(git -C "$SYLVIA_ROOT" rev-parse --abbrev-ref HEAD); uncommitted files before the run: $uncommitted)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "python: $("$SYLVIA_TOOLS_VENV/bin/python" --version), jsonschema $("$SYLVIA_TOOLS_VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("jsonschema"))')"
echo "node: $(command -v node > /dev/null && node --version || echo 'not installed')"
echo "load: $(uptime)"
echo "audio: none (no step here plays audio)"

echo "==> clean: .build/ci-logs and this work's scratch directories"
rm -rf "$SYLVIA_ROOT/.build/ci-logs" "$SYLVIA_ROOT/.build/scratch/ci-11-capture-anchor-contracts" \
  "$SYLVIA_ROOT/.build/scratch/m0-contracts/controls"
ls -d "$SYLVIA_ROOT/.build/DerivedData" 2>/dev/null && echo "note: a DerivedData directory exists (not created by this work)" || echo "no DerivedData in this checkout"

echo "==> Scripts/ci.sh contracts"
"$SYLVIA_ROOT/Scripts/ci.sh" contracts
ci_status=$?
for name in 10-contracts 11-capture-anchor-contracts; do
  echo "---- .build/ci-logs/$name.log"
  cat "$SYLVIA_ROOT/.build/ci-logs/$name.log"
done

echo "==> mutation pass (run by 11-capture-anchor-contracts): Docs/Stage0/evidence/M0-contracts/mutation-pass.log"
{
  echo "command: Scripts/contracts/mutation-pass.py --jobs 4 (run by Scripts/ci.d/11-capture-anchor-contracts.sh)"
  echo "commit: $(git -C "$SYLVIA_ROOT" rev-parse HEAD) (uncommitted files before the clean run: $uncommitted)"
  echo "(the time below was measured while other agents shared this Mac: indicative only)"
  sed -n '/^==> mutation pass/,$p' "$SYLVIA_ROOT/.build/ci-logs/11-capture-anchor-contracts.log" | tail -n +2
} > "$evidence/mutation-pass.log"
grep -E '^(load|part|noticed|time|result)' "$evidence/mutation-pass.log"
grep -q '^result: pass' "$evidence/mutation-pass.log"
mutations_status=$?

echo "==> checker report: Docs/Stage0/evidence/M0-contracts/check-spike-anchors.txt"
sylvia_python -I "$SYLVIA_ROOT/Scripts/check-spike-anchors.py" --root "$SYLVIA_ROOT" --report "$evidence/check-spike-anchors.txt" | tail -1
report_status=${PIPESTATUS[0]}

echo "==> negative controls: Docs/Stage0/evidence/M0-contracts/negative-controls.log"
"$commands/negative-controls.sh" > /dev/null
controls_status=$?
tail -1 "$evidence/negative-controls.log"

echo "==> patterns in Python and ECMA-262 (node): Docs/Stage0/evidence/M0-contracts/check-patterns.log"
sylvia_python -I "$commands/check-patterns.py" --log "$evidence/check-patterns.log" > /dev/null
patterns_status=$?
grep -E '^(node|result)' "$evidence/check-patterns.log"

echo "exit: ci.sh $ci_status, mutation pass $mutations_status, checker $report_status, negative controls $controls_status, patterns $patterns_status"
exit $(( ci_status != 0 || mutations_status != 0 || report_status != 0 || controls_status != 0 || patterns_status != 0 ))
