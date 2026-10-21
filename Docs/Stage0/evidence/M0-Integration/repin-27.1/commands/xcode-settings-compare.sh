#!/bin/bash
# ADR-0014 section 6: "A toolchain change follows ADR-0001 and updates the inventory's toolchain and
# SYLVIA_XCODE_BUILD_PINNED together, and runs xcode-settings.py to see whether the new Xcode passes a setting to the
# compiler or linker that the check's setting lists should hold." Runs that script, unchanged, against the installed
# Xcode (27.1, 27A9275), writes its output beside this folder's logs, and compares it line by line with the committed
# output for Xcode 27.0 (27A266a), Docs/Stage0/evidence/M0-dependencies/xcode-settings.log. Read-only: the script reads
# Xcode's specification files and imports Scripts/check-dependency-lock.py to read its lists.
#
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/xcode-settings-compare.sh > <log> 2>&1
set -uo pipefail
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
here=Docs/Stage0/evidence/M0-Integration/repin-27.1
old=Docs/Stage0/evidence/M0-dependencies/xcode-settings.log
new="$here/xcode-settings-27.1.log"

echo "command: $here/commands/xcode-settings-compare.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo
"$SYLVIA_TOOLS_VENV/bin/python" -I Docs/Stage0/evidence/M0-dependencies/commands/xcode-settings.py > "$new" 2>&1
status=$?
echo "xcode-settings.py exit status: $status; output: $new ($(wc -l < "$new" | tr -d ' ') lines)"
echo "committed output for Xcode 27.0: $old ($(wc -l < "$old" | tr -d ' ') lines)"
echo "first line of each: $(head -n 1 "$old") | $(head -n 1 "$new")"
echo
echo "== diff (27.0 committed, then 27.1)"
if diff "$old" "$new"; then
  echo "(no difference: Xcode 27.1's specifications give the same settings, types, flags and treatments as 27.0's)"
  result=same
else
  result=different
fi
echo
echo "result: $result"
[[ $status -eq 0 ]] || exit 1
exit 0
