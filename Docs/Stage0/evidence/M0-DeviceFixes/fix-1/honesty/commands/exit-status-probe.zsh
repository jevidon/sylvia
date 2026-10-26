#!/bin/zsh -f
# M0 device fixes, fix-1, the honesty review of 26 October 2026, finding HON-2: what the last line of runbook 0.8
# reads when the lock harness's step 14 fails, as its quiet-tone test did in all four runs on this Mac on 26 October
# 2026. The real chain: zsh runs `caffeinate … Scripts/ci.d/71-g05-recovery.sh 2>&1 | tee …; echo "drop-in exit
# ${pipestatus[1]}"` (runbook 0.8); the drop-in (bash, `set -euo pipefail`, its line 30; no EXIT trap at its steps
# 13-15, line 124 removes step 11's) calls Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh as a plain
# command (line 136); that script (bash, `set -euo pipefail`, its line 28, with an EXIT trap that shuts its simulator
# down, line 74) runs `xcodebuild test … 2>&1 | tee -a …` (lines 81-82), and xcodebuild test exits with 65 when a test
# fails. Here two stand-ins with the same shell constructs replace the two scripts, and a command that exits with a
# given status replaces xcodebuild: 65 (a failed test), and 0 as the control. caffeinate is run with -i only, as the
# runbook's own probe of this line ran it (Docs/Stage0/evidence/M0-runbook/commands/zsh-exit-status.zsh); runbook 0.8
# adds -d. Writes only under .build/scratch/honesty/exit-status in this checkout; builds nothing, and uses no
# simulator, device or network.
#   /bin/zsh -f Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/commands/exit-status-probe.zsh
# Output: standard output, saved as Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/exit-status-probe.log. Exit 0 when
# the two runs give what the header expects, 1 otherwise.
root=${0:A:h:h:h:h:h:h:h:h}
cd "$root" || exit 1
scratch="$root/.build/scratch/honesty/exit-status"
rm -rf "$scratch"
mkdir -p "$scratch"

print "command: /bin/zsh -f Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/commands/exit-status-probe.zsh"
print "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files, this probe's log left out: $(git -C "$root" status --porcelain | grep -v -F 'fix-1/honesty/exit-status-probe.log' | wc -l | tr -d ' ')"
print "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); zsh $ZSH_VERSION; the bash that '#!/usr/bin/env bash' finds here (the stand-ins' and the two real scripts' first line): $(command -v bash), $(bash --version | head -1)"
print "start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
print "expected: with the stand-in xcodebuild exiting 65, the harness stand-in exits 65, the drop-in stand-in exits 65"
print "  before its closing line, and runbook 0.8's line reads 'drop-in exit 65'; with 0 (the control), every closing line"
print "  is printed and the line reads 'drop-in exit 0'"

cat > "$scratch/harness-standin.sh" <<'EOF'
#!/usr/bin/env bash
# Stand-in for Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh: its shell options (line 28), an EXIT trap like
# its simulator shutdown (line 74; sylvia_sim_shutdown runs `xcrun simctl shutdown … || true`, Scripts/lib/sim.sh), and
# its step-14 pipeline (lines 81-82), with a command that exits with $STANDIN_XCODEBUILD_STATUS in place of xcodebuild.
set -euo pipefail
LOGS="${G05_LOG_DIR:?}"
shutdown_standin() { /usr/bin/false >/dev/null 2>&1 || true; }
trap 'shutdown_standin' EXIT
echo "=== 14. stand-in: the harness's tests, the stand-in xcodebuild exiting with ${STANDIN_XCODEBUILD_STATUS:?}"
/bin/sh -c 'echo "stand-in xcodebuild test: exit $1"; exit "$1"' sh "$STANDIN_XCODEBUILD_STATUS" 2>&1 | tee -a "$LOGS/harness-simulator-tests.log"
echo "after the step-14 pipeline (printed only if it succeeded)"
trap - EXIT
shutdown_standin
echo "G0.5 recovery lock harness: steps 13-15 passed (stand-in)"
EOF

cat > "$scratch/dropin-standin.sh" <<'EOF'
#!/usr/bin/env bash
# Stand-in for Scripts/ci.d/71-g05-recovery.sh at its steps 13-15: its shell options (line 30), no EXIT trap (line 124
# removed step 11's), and its call of the harness's script (line 136).
set -euo pipefail
LOGS="${G05_LOG_DIR:?}"
SIM_NAME="${G05_SIM_NAME:?}"
G05_LOG_DIR="$LOGS" G05_SIM_NAME="$SIM_NAME" "$(dirname "$0")/harness-standin.sh"
echo
echo "G0.5 recovery: all steps passed (stand-in; logs in $LOGS)"
EOF
chmod +x "$scratch/harness-standin.sh" "$scratch/dropin-standin.sh"

print "\n---- the harness stand-in (.build/scratch/honesty/exit-status/harness-standin.sh)"
cat "$scratch/harness-standin.sh"
print "\n---- the drop-in stand-in (.build/scratch/honesty/exit-status/dropin-standin.sh)"
cat "$scratch/dropin-standin.sh"

problems=0
typeset -A expected
expected=(65 "drop-in exit 65" 0 "drop-in exit 0")
for st in 65 0; do
  rm -rf "$scratch/logs"
  mkdir -p "$scratch/logs"
  print "\n---- the harness stand-in alone, the stand-in xcodebuild exiting with $st"
  STANDIN_XCODEBUILD_STATUS=$st G05_LOG_DIR="$scratch/logs" G05_SIM_NAME=Sylvia-standin "$scratch/harness-standin.sh"
  print "harness stand-in exit: $?"
  rm -rf "$scratch/logs"
  mkdir -p "$scratch/logs"
  print "\n---- runbook 0.8's line with the drop-in stand-in, caffeinate -i, the stand-in xcodebuild exiting with $st"
  STANDIN_XCODEBUILD_STATUS=$st G05_LOG_DIR="$scratch/logs" G05_SIM_NAME=Sylvia-standin \
    caffeinate -i "$scratch/dropin-standin.sh" 2>&1 | tee "$scratch/console-$st.log"; \
    last="drop-in exit ${pipestatus[1]}"
  print "$last"
  if [[ "$last" == "${expected[$st]}" ]]; then
    print "as expected: '${expected[$st]}'"
  else
    print "NOT as expected: '${expected[$st]}' expected"
    problems=$((problems + 1))
  fi
done

rm -rf "$scratch"
print "\nend: $(date -u +%Y-%m-%dT%H:%M:%SZ); problems: $problems; the stand-ins' scratch folder was removed"
(( problems == 0 ))
