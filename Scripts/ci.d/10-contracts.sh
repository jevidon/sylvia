#!/usr/bin/env bash
# Validates every JSON Schema, contract fixture, OpenAPI document and listed contract instance.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
sylvia_python "$SYLVIA_ROOT/Scripts/validate-contracts.py" "$SYLVIA_ROOT/Contracts"
