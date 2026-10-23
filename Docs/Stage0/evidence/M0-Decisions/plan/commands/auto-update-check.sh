#!/bin/bash
# Read-only check of the build Mac's App Store automatic-updates setting, the key the toolchain re-pin round read on
# 20 October 2026 (Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/toolchain-state.sh, line "defaults read
# /Library/Preferences/com.apple.commerce AutoUpdate", which then printed 1). The product owner reported on 22 October
# 2026 that the updates are now turned off (PO-35's note); this records what the key says. It reads and changes
# nothing else, and no agent operates the Mac's settings. Whether this key is what the App Store's settings show on
# this macOS version was not checked against the settings window.
#   Docs/Stage0/evidence/M0-Decisions/plan/commands/auto-update-check.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
echo "command: Docs/Stage0/evidence/M0-Decisions/plan/commands/auto-update-check.sh"
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
echo "defaults read /Library/Preferences/com.apple.commerce AutoUpdate: $(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>&1)"
echo "Xcode.app modified: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S %Z' /Applications/Xcode.app 2>&1)"
