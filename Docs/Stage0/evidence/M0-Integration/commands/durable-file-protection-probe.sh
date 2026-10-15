#!/bin/bash
# Host check of G0.4's DurableFile after the M0 assembly's TM-F2 fix (ADR-0015): builds DurableFile.swift with the
# probe below and checks that classes A, B and C each read back as requested and an unmapped class is refused before
# any directory is created. Writes only under .build/scratch/durable-probe/.
#   Docs/Stage0/evidence/M0-Integration/commands/durable-file-protection-probe.sh > Docs/Stage0/evidence/M0-Integration/durable-file-protection-probe.log
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root"
source Scripts/lib/env.sh
out=.build/scratch/durable-probe
mkdir -p "$out"
echo "# command: Docs/Stage0/evidence/M0-Integration/commands/durable-file-protection-probe.sh"
echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ); commit $(git rev-parse --short HEAD) (plus uncommitted: $(git status --porcelain -- Spikes/G04-Audio | wc -l | tr -d ' ') G0.4 files)"
echo "# host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcrun swiftc --version 2>&1 | head -1)"
cp Docs/Stage0/evidence/M0-Integration/commands/durable-file-protection-probe.swift "$out/main.swift"  # top-level code needs main.swift
xcrun swiftc -swift-version 6 -o "$out/probe" Spikes/G04-Audio/Sources/G04AudioKit/Persistence/DurableFile.swift \
  "$out/main.swift" || exit 1
"$out/probe" "$out/out"
