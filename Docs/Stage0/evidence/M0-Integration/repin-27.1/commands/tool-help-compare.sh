#!/bin/bash
# The device runbook relies on the help text and argument parsing of xcodebuild's provisioning flags and of devicectl
# (runbook Section 1.5, 3.15, Section 9; corrections C1, C45, C46, C53), read under Xcode 27.0 on 14 October 2026
# (Docs/Stage0/evidence/M0-runbook/tool-help.txt). With the pin moved to Xcode 27.1 (27A9275), this runs the same
# read-only command, Docs/Stage0/evidence/M0-runbook/commands/tool-help.sh, unchanged, writes its output beside this
# folder's logs and compares it with the committed one. No device is listed, contacted or used: the command reads help
# texts, a man page, a zsh probe and two devicectl runs that name no device and so stop at argument parsing.
#
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/tool-help-compare.sh > <log> 2>&1
set -uo pipefail
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
here=Docs/Stage0/evidence/M0-Integration/repin-27.1
old=Docs/Stage0/evidence/M0-runbook/tool-help.txt
new="$here/tool-help-27.1.txt"
echo "command: $here/commands/tool-help-compare.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
Docs/Stage0/evidence/M0-runbook/commands/tool-help.sh > "$new" 2>&1
status=$?
echo "tool-help.sh exit status: $status; output: $new"
echo
echo "== diff (the committed output under Xcode 27.0, then this one under 27.1)"
diff "$old" "$new"
echo "diff exit status: $? (1: the outputs differ; each difference is listed above)"
exit $status
