#!/usr/bin/env bash
# Creates or refreshes the shared Python virtualenv used by contract and lint tooling.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

if [[ ! -x "$SYLVIA_TOOLS_VENV/bin/python" ]]; then
  mkdir -p "$(dirname "$SYLVIA_TOOLS_VENV")"
  python3 -m venv "$SYLVIA_TOOLS_VENV"
fi
"$SYLVIA_TOOLS_VENV/bin/pip" install --quiet --disable-pip-version-check -r "$SYLVIA_ROOT/Scripts/tools/requirements.txt"
echo "tools venv ready: $SYLVIA_TOOLS_VENV"
