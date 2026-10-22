#!/bin/bash
# The checks the lock harness's files feed (PO-23 option (b), 22 October 2026), on the current commit, host only:
#   1. Scripts/ci.sh contracts (00-git-lfs, 10-contracts, 11-capture-anchor-contracts)
#   2. Scripts/ci.d/13-hard-rules.sh (the audit of every committed and new file, the harness's included)
#   3. the runbook content check and the step coverage (the checklist's step 3 changed):
#      a. on the runbook as committed. Expected to FAIL, and only on G0.5 recovery step 3: the checklist's new step 3
#         markers are not in the runbook yet, and the runbook's 6.1 still has the XCTest probe's two markers; the runbook
#         is another owner's, and the text it needs is requested (requested/runbook-6.1.md, apply-requested.py);
#      b. on a copy of the runbook with the requested changes applied: expected to pass;
#   4. Scripts/ci.d/12-dependency-lock.sh (the harness adds a project.yml and its Package.resolved):
#      a. on the repository as committed. Expected to FAIL, and only because Docs/Licenses/inventory.json, another
#         owner's file, does not register Spikes/G05-Recovery/LockHarness/Package.resolved yet;
#      b. the same check on a copy of the tracked files with the requested inventory changes applied: expected to pass;
#   5. the harness app's SQLite linkage (information for the requested inventory note): otool and nm of the Debug
#      device build, when it exists.
# Each "expected to FAIL" check passes this script only when it fails for exactly the stated reason.
#   Docs/Stage0/evidence/M0-Decisions/harness/commands/checks.sh <name>
# Logs: Docs/Stage0/evidence/M0-Decisions/harness/<name>/*.log; the copies are made under .build/scratch.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
here="Docs/Stage0/evidence/M0-Decisions/harness"
out="$here/$name"
scratch="$root/.build/scratch/requested"
source Scripts/lib/env.sh
rm -rf "$out"; mkdir -p "$out"
problems=0
note() { echo "$*" | tee -a "$out/summary.log"; }
header() {
  echo "command: $here/commands/checks.sh $name ($1)"
  echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"
  echo
}
: > "$out/summary.log"

# 1
{ header "Scripts/ci.sh contracts"; Scripts/ci.sh contracts; echo "exit: $?"; } > "$out/ci-contracts.log" 2>&1
if grep -q "^exit: 0$" "$out/ci-contracts.log"; then note "1 Scripts/ci.sh contracts: passed"; else note "1 Scripts/ci.sh contracts: FAILED"; problems=$((problems + 1)); fi

# 2
{ header "Scripts/ci.d/13-hard-rules.sh"; Scripts/ci.d/13-hard-rules.sh; echo "exit: $?"; } > "$out/13-hard-rules.log" 2>&1
if grep -q "^exit: 0$" "$out/13-hard-rules.log"; then note "2 13-hard-rules: passed"; else note "2 13-hard-rules: FAILED"; problems=$((problems + 1)); fi

# The copies with the requested changes.
python3 -I "$here/commands/apply-requested.py" "$root" "$scratch" > "$out/apply-requested.log" 2>&1 \
  || { note "apply-requested.py: FAILED (see apply-requested.log)"; problems=$((problems + 1)); }

# 3
content="Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2/commands/runbook-content-check.py"
coverage="Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.py"
{
  header "runbook content check and step coverage, the runbook as committed"
  python3 -I "$content" "$root"; echo "content exit: $?"
  echo
  python3 -I "$coverage" "$root"; echo "coverage exit: $?"
} > "$out/runbook-checks-committed.log" 2>&1
problem_lines="$(grep -E '^  (MISSING|UNLISTED)|^PROBLEM' "$out/runbook-checks-committed.log")"
unexpected="$(grep -vE '^  MISSING step 3: |^  UNLISTED step 6\.1 \(G05-Recovery\.md\): (classA_readable=false|classC_save=ok)$' <<<"$problem_lines" | grep -v '^$' || true)"
if grep -q "^content exit: 1$" "$out/runbook-checks-committed.log" && [[ -z "$unexpected" ]] \
   && grep -q "^G05-Recovery.md: 5 steps, .* missing$" "$out/runbook-checks-committed.log" \
   && grep -q "^coverage exit: 0$" "$out/runbook-checks-committed.log"; then
  note "3a runbook as committed: content check FAILED as expected, only on G0.5 recovery step 3 ($(grep -c '^  MISSING step 3: ' <<<"$problem_lines") checklist markers not in the runbook yet, $(grep -c '^  UNLISTED step 6.1' <<<"$problem_lines") XCTest-probe markers left in its 6.1); step coverage passed"
else
  note "3a runbook as committed: NOT as expected (see runbook-checks-committed.log)"; problems=$((problems + 1))
fi
{
  header "runbook content check and step coverage, the runbook with the requested changes (a copy)"
  python3 -I "$content" "$root" "$scratch/runbook/M0-device-runbook.md"; echo "content exit: $?"
  echo
  python3 -I "$coverage" "$root" "$scratch/runbook/M0-device-runbook.md"; echo "coverage exit: $?"
} > "$out/runbook-checks-requested.log" 2>&1
if grep -q "^content exit: 0$" "$out/runbook-checks-requested.log" && grep -q "^coverage exit: 0$" "$out/runbook-checks-requested.log"; then
  note "3b runbook with the requested changes: content check and step coverage passed"
else
  note "3b runbook with the requested changes: FAILED (see runbook-checks-requested.log)"; problems=$((problems + 1))
fi

# 4
{ header "Scripts/ci.d/12-dependency-lock.sh, the repository as committed"; Scripts/ci.d/12-dependency-lock.sh; echo "exit: $?"; } > "$out/12-dependency-lock-committed.log" 2>&1
fails="$(grep -E '^FAIL ' "$out/12-dependency-lock-committed.log" || true)"
other="$(grep -vF 'Spikes/G05-Recovery/LockHarness/Package.resolved' <<<"$fails" | grep -v '^$' || true)"
if grep -q "^exit: 1$" "$out/12-dependency-lock-committed.log" && [[ -n "$fails" && -z "$other" ]]; then
  note "4a 12-dependency-lock as committed: FAILED as expected, only on the harness's lock not yet registered in the inventory ($(grep -c . <<<"$fails") failure lines)"
else
  note "4a 12-dependency-lock as committed: NOT as expected (see 12-dependency-lock-committed.log)"; problems=$((problems + 1))
fi
{
  header "check-dependency-lock.py check --toolchain on a copy of the tracked files with the requested inventory changes"
  sylvia_python Scripts/check-dependency-lock.py check --root "$scratch/tree" --toolchain; echo "exit: $?"
} > "$out/12-dependency-lock-requested.log" 2>&1
if grep -q "^exit: 0$" "$out/12-dependency-lock-requested.log"; then
  note "4b dependency lock with the requested inventory changes: passed"
else
  note "4b dependency lock with the requested inventory changes: FAILED (see 12-dependency-lock-requested.log)"; problems=$((problems + 1))
fi

# 5
app="Spikes/G05-Recovery/LockHarness/.build/DerivedData/Build/Products/Debug-iphoneos/G05LockHarness.app"
{
  header "the harness app's SQLite linkage (information)"
  if [[ -d "$app" ]]; then
    echo "otool -L G05LockHarness.debug.dylib, SQLite lines:"
    otool -L "$app/G05LockHarness.debug.dylib" | grep -i sqlite
    echo "sqlite3_* symbols the dylib defines (nm -m, __TEXT,__text external): $(xcrun --sdk iphoneos nm -m "$app/G05LockHarness.debug.dylib" | grep -cE '\(__TEXT,__text\) external _sqlite3_')"
    echo "two of its undefined sqlite3_* references:"
    xcrun --sdk iphoneos nm -m "$app/G05LockHarness.debug.dylib" | grep -E 'undefined.*_sqlite3_(open_v2|prepare_v3)'
  else
    echo "no Debug device build of the harness in $app; run the harness checks first"
  fi
} > "$out/harness-linkage.log" 2>&1
note "5 harness linkage: recorded (information)"

note "problems: $problems"
exit $(( problems > 0 ))
