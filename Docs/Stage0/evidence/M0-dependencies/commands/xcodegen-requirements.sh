#!/bin/bash
# ADR-0014 evidence: how the pinned XcodeGen maps each `packages:` requirement key of a project.yml into the generated
# project (XCRemoteSwiftPackageReference.requirement). Scripts/check-dependency-lock.py accepts exactly the keys that
# produce `kind = exactVersion` here.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/xcodegen-requirements.sh > Docs/Stage0/evidence/M0-dependencies/xcodegen-requirements.log 2>&1
#
# The probe project lives under .build/scratch and points at example.invalid URLs; generating a project resolves
# nothing, so no network is used. Host only.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
source "$ROOT/Scripts/lib/sim.sh"
source "$ROOT/Scripts/lib/xcodegen.sh"
P="$ROOT/.build/scratch/xcodegen-requirements"
rm -rf "$P"; mkdir -p "$P/Sources"
touch "$P/Sources/main.swift"
cat > "$P/project.yml" <<'EOF'
name: Probe
options:
  deploymentTarget:
    iOS: "26.0"
packages:
  KeyExactVersion:
    url: https://example.invalid/a/exactversion.git
    exactVersion: 1.2.3
  KeyVersion:
    url: https://example.invalid/a/version.git
    version: 1.2.3
  KeyFrom:
    url: https://example.invalid/a/from.git
    from: 1.2.3
  KeyMajorVersion:
    url: https://example.invalid/a/majorversion.git
    majorVersion: 1.2.3
  KeyMinorVersion:
    url: https://example.invalid/a/minorversion.git
    minorVersion: 1.2.3
  KeyBranch:
    url: https://example.invalid/a/branch.git
    branch: main
  KeyRevision:
    url: https://example.invalid/a/revision.git
    revision: 0123456789abcdef0123456789abcdef01234567
  KeyRange:
    url: https://example.invalid/a/range.git
    minVersion: 1.2.3
    maxVersion: 2.0.0
  KeyGithub:
    github: example/github-shorthand
    exactVersion: 1.2.3
targets:
  Probe:
    type: application
    platform: iOS
    sources: [Sources]
EOF
echo "xcodegen-requirements $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git -C "$ROOT" rev-parse HEAD); $(xcodegen --version)"
(cd "$P" && xcodegen generate --quiet) || { echo "FAIL: xcodegen generate"; exit 1; }
echo "key in project.yml -> requirement written to the generated project"
/usr/bin/python3 -I - "$P/Probe.xcodeproj/project.pbxproj" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
rows = []
for m in re.finditer(r'XCRemoteSwiftPackageReference "([^"]+)" \*/ = \{(.*?)\n\t\t\};', text, re.S):
    body = " ".join(m.group(2).split())
    url = re.search(r'repositoryURL = "?([^";]+)"?;', body).group(1)
    req = re.search(r'requirement = \{(.*?)\};', body).group(1).strip()
    rows.append((url, req))
for url, req in sorted(rows):
    print(f"  {url:50s} {req}")
exact = sorted(u for u, r in rows if "kind = exactVersion" in r)
print("exact requirements:", ", ".join(exact))
PY
