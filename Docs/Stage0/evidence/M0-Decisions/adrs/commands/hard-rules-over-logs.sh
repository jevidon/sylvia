#!/usr/bin/env bash
# Runs Scripts/ci.d/13-hard-rules.sh while this folder's new logs are present and not yet committed, so that the audit,
# which reads committed and new (untracked, not ignored) files, covers them. Prints which paths were uncommitted first:
# the drop-in's own header marks only changed tracked files. Host only; writes nothing in the repository.
#   Docs/Stage0/evidence/M0-Decisions/adrs/commands/hard-rules-over-logs.sh > <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
echo "command: Docs/Stage0/evidence/M0-Decisions/adrs/commands/hard-rules-over-logs.sh"
echo "commit: $(git rev-parse HEAD)"
echo "date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "uncommitted paths (git status --porcelain --untracked-files=all): $(git status --porcelain --untracked-files=all | wc -l | tr -d ' ')"
git status --porcelain --untracked-files=all | sed 's/^/  /'
echo
Scripts/ci.d/13-hard-rules.sh
echo "exit status: $?"
