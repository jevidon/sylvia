#!/usr/bin/env bash
# M0 device runbook: records the help text of the tool options the runbook relies on, and one shell
# behaviour, read-only. No device is listed, contacted or used: only `--help` output, a man page, a zsh
# probe that writes nothing (commands/zsh-exit-status.zsh), two devicectl argument-parsing runs that name no
# device (so devicectl stops at parsing; runbook 3.15) and the redaction one-liner on sample lines are read. Environment: host (macOS).
#
#   Docs/Stage0/evidence/M0-runbook/commands/tool-help.sh > Docs/Stage0/evidence/M0-runbook/tool-help.txt
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$ROOT"
source Scripts/lib/env.sh

echo "# tool help read for the M0 device runbook"
echo "# recorded $(date -u +%Y-%m-%dT%H:%M:%SZ) on host macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | tr '\n' ' ')"
echo "# commit: $(git -C "$ROOT" rev-parse HEAD)"

section() {
  echo
  echo "## $*"
  "$@" 2>&1 | sed -n '1,/^OUTPUT OPTIONS:/p' | sed '$d'
}

# Which xcodebuild flag registers a device (runbook 1.5, 0.4 and 0.7; corrections C45 and C46): the lines of
# `xcodebuild -help` that describe the two provisioning flags, verbatim apart from leading spaces.
echo
echo "## xcodebuild -help: the provisioning flags"
xcodebuild -help 2>&1 | grep -E -e '-allowProvisioning(Updates|DeviceRegistration) ' | sed -E 's/^[[:space:]]+//'

# What the Identifier column of `devicectl list devices` shows (runbook 1.5, correction C1).
section xcrun devicectl list devices --help
# --device accepts a UDID; copy to: --remove-existing-content and its documented scope (runbook 1.5, Session 3).
section xcrun devicectl device copy to --help
section xcrun devicectl device copy from --help
# Finding a test runner's bundle ID (runbook 6.3, correction C42).
section xcrun devicectl device info apps --help
# Launch arguments (G0.4 step 16's -g04AutoPlay YES) and the signal options of the same step.
section xcrun devicectl device process launch --help
section xcrun devicectl device process signal --help
section xcrun devicectl device install app --help

# How devicectl reads the app's arguments in G0.4 step 16 (runbook 3.15, correction C53). Parse-only: no --device
# is given, so devicectl stops at argument parsing and contacts nothing; its error shows how it read the line.
echo
echo "## devicectl device process launch: the app's arguments (parse-only, no --device; runbook 3.15)"
echo "# as the checklist writes it: xcrun devicectl device process launch com.jevidon.sylvia.spike.g04audio -g04AutoPlay YES"
xcrun devicectl device process launch com.jevidon.sylvia.spike.g04audio -g04AutoPlay YES 2>&1
echo "# exit status $?"
echo "# with -- before them: xcrun devicectl device process launch com.jevidon.sylvia.spike.g04audio -- -g04AutoPlay YES"
xcrun devicectl device process launch com.jevidon.sylvia.spike.g04audio -- -g04AutoPlay YES 2>&1
echo "# exit status $?"
echo "# devicectl version: $(xcrun devicectl --version 2>&1)"

# The address redaction of runbook Section 2 and Session 4, on made-up sample lines (no real address).
echo
echo "## perl: redaction of IPv4 addresses and tailnet names (runbook Section 2 and Session 4), on sample lines"
SAMPLE="$ROOT/.build/scratch/m0-redaction-sample.txt"; mkdir -p "$ROOT/.build/scratch"
printf '%s\n' 'listening: 192.168.1.20:47800 100.101.102.103:47800' 'endpoints in pairing payload: mac.tail1a2b3.ts.net:47800' \
  '{"event":"endpoint_preferred","host":"10.0.0.5","port":"47800"}' 'iOS 26.7 (23H24); Xcode 27.0; part 3 of 320' > "$SAMPLE"
echo "# before:"; cat "$SAMPLE"
perl -pi -e 's/\b(\d{1,3}\.\d{1,3})\.\d{1,3}\.\d{1,3}\b/$1.x.x/g; s/\.[A-Za-z0-9-]+\.ts\.net\b/.[tailnet].ts.net/g' "$SAMPLE"
echo "# after (perl -pi -e, as the runbook gives it):"; cat "$SAMPLE"
rm -f "$SAMPLE"

echo
echo "## man cp: the -c option (APFS clones; runbook Session 4)"
man cp 2>/dev/null | col -b | grep -A4 -E '^ +-c +copy files using clonefile'

# The exit status the owner sees in Session 0.8, where the drop-in's output goes through tee in zsh.
echo
echo "## zsh: the exit status of a command run by caffeinate, through tee (runbook 0.8; commands/zsh-exit-status.zsh)"
"$ROOT/Docs/Stage0/evidence/M0-runbook/commands/zsh-exit-status.zsh" 2>&1
