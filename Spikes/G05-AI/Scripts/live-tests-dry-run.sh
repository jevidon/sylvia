#!/usr/bin/env bash
# Dry run of the gated live tests (Tests/LiveProviderTests) against a loopback fake server, so the test code that a
# person will later point at a real local model server, gateway or transcription endpoint is known to work.
# This is NOT a provider test: the fake server is fake-openai-compatible-server.py on 127.0.0.1:<ephemeral>.
# The OpenAI and Anthropic live tests stay skipped (no keys, and none are read here).
#
#   Spikes/G05-AI/Scripts/live-tests-dry-run.sh     # run from anywhere; needs DEVELOPER_DIR (Scripts/lib/env.sh)
set -euo pipefail
SPIKE="$(cd "$(dirname "$0")/.." && pwd)"
PORT_FILE="$(mktemp "${TMPDIR:-/tmp}/g05-fake-port.XXXXXX")"
python3 "$SPIKE/Scripts/fake-openai-compatible-server.py" >"$PORT_FILE" &
SERVER_PID=$!
stop_server() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  rm -f "$PORT_FILE"
}
trap stop_server EXIT
for _ in $(seq 1 100); do
  grep -q '^PORT ' "$PORT_FILE" && break
  /bin/sleep 0.1
done
PORT="$(awk '/^PORT /{print $2}' "$PORT_FILE")"
[[ -n "$PORT" ]] || { echo "FAIL: fake server did not start" >&2; exit 1; }
echo "fake OpenAI-compatible server on 127.0.0.1:$PORT (loopback only)"

cd "$SPIKE"
set +e
env -u OPENAI_API_KEY -u ANTHROPIC_API_KEY \
  SYLVIA_LIVE_PROVIDER_TESTS=1 \
  SYLVIA_LIVE_COMPAT_BASE_URL="http://127.0.0.1:$PORT/v1" SYLVIA_LIVE_COMPAT_MODEL=fake-model \
  SYLVIA_LIVE_TRANSCRIPTION_BASE_URL="http://127.0.0.1:$PORT/v1" SYLVIA_LIVE_TRANSCRIPTION_MODEL=fake-speech \
  swift test --force-resolved-versions --filter LiveProviderTests 2>&1 | grep -E "✔|✘|➜|recorded an issue|LIVE-"
status="${PIPESTATUS[0]}"
set -e
exit "$status"
