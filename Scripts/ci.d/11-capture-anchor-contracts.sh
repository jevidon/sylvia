#!/usr/bin/env bash
# Capture-envelope and anchor contracts against real spike output (ADR-0016).
#   1. The committed anchor.v1 and capture-envelope.v1 fixtures are exactly what their generator writes.
#   2. Scripts/check-spike-anchors.py: the capture kinds agree with the design package's kind mapping and the saved
#      answer's endpoint with the context-pack contract; every pattern in every contract compiles in Python and as
#      ECMA-262 with the u flag (two recorded exceptions in other owners' contracts); every valid fixture passes the
#      code-checked rules; every invalid fixture is its base with the listed operations and fails the schema with
#      exactly its listed errors, and every semantic-invalid fixture breaks exactly its rule; G0.1 EPUB, G0.1 PDF and
#      G0.4 audio output is adapted and validated; and G0.5 recovery's capture and note rows are mapped into envelopes
#      with each difference a recorded deviation.
#   3. The mutation pass: deleting any protected schema constraint, or disabling any branch of a code-checked rule,
#      changes a fixture outcome (so every rule has a fixture that breaks it alone).
# Host only; no simulator, no network, no audio. JSON Schema validation of the fixtures is 10-contracts.sh.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

# The fixture generator and the mutation pass. ADR-0016 records that they belong beside the checker
# (Scripts/contracts/, requested in Docs/Stage0/M0-contracts.md); moving them changes only this line.
tools="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/commands"
scratch="$SYLVIA_ROOT/.build/scratch/ci-11-capture-anchor-contracts"
rm -rf "$scratch"
mkdir -p "$scratch/fixtures"

echo "==> fixtures regenerate byte for byte"
sylvia_python -I "$tools/make-contract-fixtures.py" "$scratch/fixtures"
for stem in anchor.v1 capture-envelope.v1; do
  diff -r "$SYLVIA_ROOT/Contracts/fixtures/$stem" "$scratch/fixtures/$stem"
done
echo "identical: Contracts/fixtures/anchor.v1 and Contracts/fixtures/capture-envelope.v1"

echo "==> related contracts, patterns, fixtures and their expected failures, spike output and code-checked rules"
sylvia_python -I "$SYLVIA_ROOT/Scripts/check-spike-anchors.py" --root "$SYLVIA_ROOT"

echo "==> mutation pass: every protected schema constraint and every code-rule branch has a fixture that notices it"
echo "load: $(uptime)"
sylvia_python -I "$tools/mutation-pass.py" --jobs 4
rm -rf "$scratch"
