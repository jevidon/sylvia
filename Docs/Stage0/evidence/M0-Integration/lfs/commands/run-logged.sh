#!/bin/bash
# Runs a command from a checkout's root and records it: the commit, uncommitted files, start and end time with the
# load (uptime), the command, its output and its exit status. Used for the Git LFS adoption's CI evidence.
#   run-logged.sh <log-file> <checkout-dir> <command> [args...]
set -uo pipefail
log="$1"; dir="$2"; shift 2
mkdir -p "$(dirname "$log")"
cd "$dir" || exit 2
{
  echo "checkout: $(pwd); commit: $(git rev-parse HEAD) ($(git branch --show-current || true)); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "command: $*"
  echo
} > "$log"
status=0
"$@" >> "$log" 2>&1 || status=$?
{
  echo
  echo "exit status: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log"
exit "$status"
