#!/bin/bash
# The fix of the review of the decisions round (22 October 2026): devicectl's own help for listing a device's files,
# which documents the --search option the G0.5 recovery checklist's step 3 and runbook 6.1 now use to record only the
# lock harness's crash reports (review finding H-06). Read-only: prints help text and contacts no device.
#   Docs/Stage0/evidence/M0-Decisions/fix-1/commands/devicectl-files-help.sh > <file> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
echo "command: xcrun devicectl device info files --help ($(date -u +%Y-%m-%dT%H:%M:%SZ); $(xcodebuild -version | tr '\n' ' '))"
echo
xcrun devicectl device info files --help
