#!/bin/bash
# Why the extracted records are committed as <file>.json.txt: Scripts/audit-hard-rules.sh reads every .json file as a
# configuration file (its ATS, file-protection and Keychain rules), and the reviews' prose names those keys, two of them
# under rules that can never be allowlisted (ats-arbitrary-loads, keychain-accessible-always). This runs the audit,
# unchanged, with --root on two copies of ../extracted/ made under .build/scratch: one with the files named as
# extracted (<file>.json), which must FAIL, and one with the names committed (<file>.json.txt), which must PASS with no
# finding. --allow-stale, because the repository's allowlist entries name files the copies do not hold. The copies are
# removed afterwards. Read-only for the repository.
#   Docs/Stage0/evidence/M0-Integration/item-reviews/commands/audit-probe.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
src=Docs/Stage0/evidence/M0-Integration/item-reviews/extracted
probe=.build/scratch/item-reviews-audit-probe
rm -rf "$probe"
mkdir -p "$probe/as-json/$src" "$probe/as-committed/$src"
for f in "$src"/*.json.txt; do
  base="$(basename "$f" .txt)"
  cp "$f" "$probe/as-json/$src/$base"
  cp "$f" "$probe/as-committed/$src/$base.txt"
done
echo "copies: $(ls "$probe/as-json/$src" | wc -l | tr -d ' ') files named <file>.json, $(ls "$probe/as-committed/$src" | wc -l | tr -d ' ') named <file>.json.txt"
status=0
echo
echo "== the files named as extracted (<file>.json): the audit must FAIL"
Scripts/audit-hard-rules.sh --root "$probe/as-json" --allow-stale > "$probe/as-json.out" 2>&1
json=$?
grep -E '^FINDING ' "$probe/as-json.out" | sed -E 's/^(FINDING [a-z-]+ [^:]+:[0-9]+):.*/\1/'
sed -n '/^| Rule |/,$p' "$probe/as-json.out"
echo "audit exit: $json"
if [[ "$json" == 1 ]] && grep -q '^FINDING ats-arbitrary-loads ' "$probe/as-json.out"; then
  echo "as expected: it fails, among others on rules that can never be allowlisted"
else
  echo "NOT as expected"; status=1
fi
echo
echo "== the files named as committed (<file>.json.txt): the audit must PASS with no finding"
Scripts/audit-hard-rules.sh --root "$probe/as-committed" --allow-stale > "$probe/as-committed.out" 2>&1
txt=$?
sed -n '/^| Rule |/,$p' "$probe/as-committed.out"
echo "audit exit: $txt"
if [[ "$txt" == 0 ]] && grep -q '^result: PASS (0 finding(s)' "$probe/as-committed.out"; then
  echo "as expected"
else
  echo "NOT as expected"; status=1
fi
for f in "$probe/as-json/$src"/*.json; do
  cmp -s "$f" "$src/$(basename "$f").txt" || { echo "PROBLEM: $(basename "$f") differs from its committed file"; status=1; }
done
rm -rf "$probe"
echo
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
