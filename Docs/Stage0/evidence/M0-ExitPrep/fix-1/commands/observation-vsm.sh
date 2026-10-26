#!/bin/bash
# An observation of the fix of the review of the M0 exit preparation (26 October 2026; integration log section 31.5),
# outside the two findings the workflow relayed and not fixed here: SwiftPM evaluates a version-specific manifest
# (Package@swift-<version>.swift) instead of the Package.swift beside it, and the check's manifest-input rule (review
# round 4's R4-01, for SwiftPM) reads the raw text of Package.swift alone.
#
#   Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands/observation-vsm.sh > Docs/Stage0/evidence/M0-ExitPrep/fix-1/observation-vsm.log 2>&1
#
# In a copy of this checkout's tree (git archive HEAD), Packages/Design/Package.swift is copied to
# Packages/Design/Package@swift-6.4.swift (Swift 6.4 is the pinned toolchain's), which then imports Foundation and takes
# the SylviaDesign target's path from the environment variable SYLVIA_EXTRA; Package.swift is left as it is. Then:
# 1. `swift package dump-package`, the call the check makes, with and without SYLVIA_EXTRA: which manifest it evaluates
#    (the SylviaDesign target's path in its output);
# 2. Scripts/check-dependency-lock.py, as in this checkout, `check --root <copy>` without the variable, as CI would run
#    it: whether it reports the version-specific manifest's import and environment read.
# Read-only for the checkout; everything under .build/scratch/fix-1-vsm. No network, no simulator; host only.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
WORK="$ROOT/.build/scratch/fix-1-vsm"
rm -rf "$WORK"; mkdir -p "$WORK/copy"
echo "observation started $(date -u +%Y-%m-%dT%H:%M:%SZ); tree of $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' '), of them under Docs/: $(git status --porcelain -- Docs | wc -l | tr -d ' ')"
echo "the check run: Scripts/check-dependency-lock.py $(git diff --quiet HEAD -- Scripts/check-dependency-lock.py && echo 'as committed' || echo 'MODIFIED'), sha256 $(shasum -a 256 Scripts/check-dependency-lock.py | cut -c1-64)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); $(xcrun swift --version 2>&1 | head -1)"
echo "load: $(uptime)"
git archive HEAD | tar -x -C "$WORK/copy"
m="$WORK/copy/Packages/Design/Package@swift-6.4.swift"
cp "$WORK/copy/Packages/Design/Package.swift" "$m"
/usr/bin/python3 -I - "$m" <<'EOF'
import sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read()
t = t.replace('import PackageDescription\n', 'import PackageDescription\nimport Foundation\n'
              'let designPath = ProcessInfo.processInfo.environment["SYLVIA_EXTRA"] ?? "Sources/SylviaDesign"\n', 1)
t = t.replace('            path: "Sources/SylviaDesign",\n', '            path: designPath,\n', 1)
open(p, 'w', encoding='utf-8').write(t)
EOF
echo
echo "=== The planted version-specific manifest: its lines that differ from Packages/Design/Package.swift"
diff "$WORK/copy/Packages/Design/Package.swift" "$m" | sed 's/^/  /'
echo
echo "=== 1. swift package dump-package of Packages/Design, without and with SYLVIA_EXTRA"
for value in '' Sources/Elsewhere; do
  if [[ -n "$value" ]]; then export SYLVIA_EXTRA="$value"; else unset SYLVIA_EXTRA; fi
  xcrun swift package --package-path "$WORK/copy/Packages/Design" --scratch-path "$WORK/dump-scratch" dump-package > "$WORK/dump.json" 2> "$WORK/dump.err"
  code=$?
  path="$(/usr/bin/python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next(t.get("path") for t in d["targets"] if t["name"] == "SylviaDesign"))' "$WORK/dump.json" 2>&1)"
  echo "  SYLVIA_EXTRA ${value:-unset}: exit $code; the SylviaDesign target's path: $path"
done
unset SYLVIA_EXTRA
echo
echo "=== 2. The check as in this checkout, on the copy, SYLVIA_EXTRA unset (as CI runs it)"
sylvia_python Scripts/check-dependency-lock.py check --root "$WORK/copy" > "$WORK/check.log" 2>&1
code=$?
grep -E '^(FAIL|WARN|dependency lock check)' "$WORK/check.log" | cut -c1-300 | sed 's/^/  /'
echo "  exit $code"
echo
echo "observation finished $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
