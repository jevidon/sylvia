#!/usr/bin/env bash
# Mechanical audit of the CLAUDE.md non-negotiable rules (plan 22.2, 22.3; ADR-0015): ATS exceptions outside the
# allowlist, trust-all and disabled certificate checks, TLS below 1.2, disabled file protection, Keychain
# "always" accessibility, committed key-like strings and key files, and TODO/FIXME or stubs in product targets.
#
# Runs the audit's self-test (planted violations in a temporary directory under .build/scratch) and then the
# audit over the whole repository (tracked and untracked files, not ignored ones). Host only; no simulator,
# network or build. Outputs go to $SYLVIA_HARD_RULES_EVIDENCE_DIR (default .build/ci-logs/hard-rules).
# Exits non-zero if the self-test fails or the repository has any finding or a stale allowlist entry.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

EVIDENCE="${SYLVIA_HARD_RULES_EVIDENCE_DIR:-$SYLVIA_ROOT/.build/ci-logs/hard-rules}"
mkdir -p "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd)"

echo "environment: host (macOS $(sw_vers -productVersion) $(sw_vers -buildVersion)), $(/usr/bin/python3 --version 2>&1)"
echo "commit: $(git -C "$SYLVIA_ROOT" rev-parse HEAD)$(git -C "$SYLVIA_ROOT" diff --quiet HEAD -- 2>/dev/null || echo ' (working tree has uncommitted changes)')"

echo
echo "--- self-test (Scripts/audit-hard-rules.sh self-test)"
self_status=0
"$SYLVIA_ROOT/Scripts/audit-hard-rules.sh" self-test >"$EVIDENCE/audit-self-test.log" 2>&1 || self_status=$?
tail -n 12 "$EVIDENCE/audit-self-test.log"
if (( self_status != 0 )); then
  echo "FAIL: the audit self-test failed (exit $self_status); see $EVIDENCE/audit-self-test.log"
  exit 1
fi

echo
echo "--- repository audit (Scripts/audit-hard-rules.sh)"
audit_status=0
"$SYLVIA_ROOT/Scripts/audit-hard-rules.sh" >"$EVIDENCE/audit-repository.log" 2>&1 || audit_status=$?
grep -E '^(root|file list|files scanned|allowlist):' "$EVIDENCE/audit-repository.log"
grep -E '^(FINDING|STALE|ALLOWLIST-ERROR)' "$EVIDENCE/audit-repository.log" || true
sed -n '/^| Rule |/,$p' "$EVIDENCE/audit-repository.log"
if (( audit_status != 0 )); then
  echo "FAIL: the repository audit reported findings (exit $audit_status); see $EVIDENCE/audit-repository.log"
  exit 1
fi
echo "13-hard-rules: self-test and repository audit passed; logs in $EVIDENCE"
