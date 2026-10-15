#!/bin/bash
# Checks Scripts/validate-contracts.py's load_json change at M0 assembly (G0.3 request c): on a scratch copy of
# Contracts/ with one valid fixture replaced by Latin-1 bytes and one by an integer of 5,000 digits, the validator
# reports an error line for each and exits 1, with no traceback; on the unchanged copy it passes.
#   Docs/Stage0/evidence/M0-Integration/commands/validator-load-errors.sh > Docs/Stage0/evidence/M0-Integration/validator-load-errors.log
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root"
source Scripts/lib/env.sh
work=.build/scratch/validator-load-errors
rm -rf "$work"; mkdir -p "$work"
cp -R Contracts "$work/Contracts"
echo "# command: Docs/Stage0/evidence/M0-Integration/commands/validator-load-errors.sh; $(date -u +%Y-%m-%dT%H:%M:%SZ); commit $(git rev-parse --short HEAD)"
echo "== unchanged copy"
sylvia_python Scripts/validate-contracts.py "$work/Contracts" 2>&1 | tail -2; echo "exit ${PIPESTATUS[0]}"
printf '{"schema_version": 1, "title": "Caf\xe9"}' > "$work/Contracts/fixtures/error.v1/valid/latin1.json"
python3 -c 'print("{\"schema_version\": " + "9" * 5000 + "}")' > "$work/Contracts/fixtures/error.v1/valid/huge-integer.json"
echo "== copy with a Latin-1 fixture and a 5,000-digit integer"
sylvia_python Scripts/validate-contracts.py "$work/Contracts" > "$work/out.txt" 2>&1; status=$?
grep -E "latin1|huge-integer|Traceback" "$work/out.txt" | cut -c1-200
echo "exit $status; traceback lines: $(grep -c Traceback "$work/out.txt")"
rm -rf "$work"
