#!/bin/bash
# Host check of G0.4's DurableFile after the M0 assembly's TM-F2 fix (ADR-0015): builds DurableFile.swift with the
# probe below and checks that classes A, B and C each read back as requested and an unmapped class is refused before
# any directory is created. Writes only under .build/scratch/durable-probe/.
#   Docs/Stage0/evidence/M0-Integration/commands/durable-file-protection-probe.sh > <log>
# Since the M0 final fix (review R1-09) the header records the screen lock state, read with ioreg as the G0.5
# recovery drop-in's guard does, and the probe writes each class into a directory of its own; with the screen locked
# a failure of class A or B is reported as not checkable and the result is INCONCLUSIVE, not PASS.
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root"
source Scripts/lib/env.sh
out=.build/scratch/durable-probe
mkdir -p "$out"
lock_state="$(ioreg -n Root -d1 -a | /usr/bin/python3 -I -c '
import plistlib, sys
root = plistlib.loads(sys.stdin.buffer.read())
users = [u for u in root.get("IOConsoleUsers", []) if u.get("kCGSSessionOnConsoleKey")]
screen = any(u.get("CGSSessionScreenIsLocked", False) for u in users)
console = root.get("IOConsoleLocked")
print("IOConsoleLocked=%s CGSSessionScreenIsLocked=%s" % (console, screen))
')"
echo "# command: Docs/Stage0/evidence/M0-Integration/commands/durable-file-protection-probe.sh"
echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ); commit $(git rev-parse --short HEAD) (plus uncommitted: $(git status --porcelain -- Spikes/G04-Audio | wc -l | tr -d ' ') G0.4 files)"
echo "# host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcrun swiftc --version 2>&1 | head -1)"
echo "# screen lock (ioreg): $lock_state"
cp Docs/Stage0/evidence/M0-Integration/commands/durable-file-protection-probe.swift "$out/main.swift"  # top-level code needs main.swift
xcrun swiftc -swift-version 6 -o "$out/probe" Spikes/G04-Audio/Sources/G04AudioKit/Persistence/DurableFile.swift \
  "$out/main.swift" || exit 1
if [[ "$lock_state" == *"CGSSessionScreenIsLocked=True"* || "$lock_state" == *"IOConsoleLocked=True"* ]]; then
  "$out/probe" "$out/out" locked
else
  "$out/probe" "$out/out"
fi
