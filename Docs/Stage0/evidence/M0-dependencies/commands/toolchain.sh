#!/bin/bash
# ADR-0014 evidence: the toolchain, SDKs, simulator runtimes, Homebrew and system tools the scripts require, and the
# Python packages in the CI tooling virtualenv, with versions and (for Homebrew formulae and Python distributions)
# the license each declares. Read-only: installs nothing, updates nothing, changes no setting.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/toolchain.sh > Docs/Stage0/evidence/M0-dependencies/toolchain.log 2>&1
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_INSTALL_FROM_API=1
echo "toolchain inventory $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD)"
echo "load: $(uptime)"

echo
echo "### Host"
sw_vers
sysctl -n machdep.cpu.brand_string

echo
echo "### Xcode (DEVELOPER_DIR=$DEVELOPER_DIR)"
xcodebuild -version
/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$DEVELOPER_DIR/../version.plist" 2>/dev/null | sed 's/^/version.plist ProductBuildVersion: /'
sylvia_check_xcode && echo "sylvia_check_xcode: matches the ADR-0001 pin ($SYLVIA_XCODE_BUILD_PINNED)"
xcrun swift --version 2>&1
echo
echo "SDKs:"
xcodebuild -showsdks 2>/dev/null | grep -E -- '-sdk ' | sed 's/^/  /'
echo
echo "Simulator runtimes:"
xcrun simctl list runtimes | sed 's/^/  /'

echo
echo "### Tools named by Scripts/ and Spikes/ (and by Scripts/ci.d/60-g04-audio.sh and the G0.4 generators on m0-g04-audio)"
for t in xcodegen ffmpeg ffprobe afconvert afinfo python3 openssl shasum unzip rsync sips plutil perl codesign security du curl git git-lfs; do
  p="$(command -v "$t" || true)"
  if [[ -z "$p" ]]; then echo "$t: NOT FOUND"; continue; fi
  real="$(/usr/bin/python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p")"
  case "$t" in
    xcodegen) v="$(xcodegen --version)";;
    ffmpeg) v="$(ffmpeg -hide_banner -version | head -1)";;
    ffprobe) v="$(ffprobe -hide_banner -version | head -1)";;
    afconvert|afinfo|codesign|security|du) v="(macOS system tool; no version flag)";;
    perl) v="$(perl -e 'print "perl $^V"')";;
    python3) v="$(python3 --version 2>&1)";;
    openssl) v="$(openssl version)";;
    shasum) v="$(shasum --version 2>&1)";;
    zip) v="$(zip -v 2>&1 | sed -n 2p)";;
    unzip) v="$(unzip -v 2>&1 | head -1)";;
    rsync) v="$(rsync --version 2>&1 | head -1)";;
    sips) v="$(sips --version 2>&1 | head -1)";;
    plutil) v="(macOS system tool)";;
    curl) v="$(curl --version | head -1)";;
    git) v="$(git --version)";;
    git-lfs) v="$(git-lfs version 2>&1)";;
  esac
  echo "$t: $p -> $real | $v"
done
echo "/usr/bin/python3 (used by scripts that name it): $(/usr/bin/python3 --version 2>&1)"
echo "/usr/bin/openssl (used by the G0.1 EPUB generator): $(/usr/bin/openssl version)"
# Optional applications: Docs/Design/render.py drives headless Google Chrome; Scripts/ci.d/40-g02-transfer.sh uses the
# Tailscale CLI only when a tailnet address is present (its steps are reported as not run otherwise).
for app in "/Applications/Google Chrome.app" "/Applications/Tailscale.app"; do
  if [[ -d "$app" ]]; then
    echo "$(basename "$app" .app) (optional): $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null)"
  else
    echo "$(basename "$app" .app) (optional): not installed"
  fi
done

echo
echo "ffmpeg build configuration (licensing flags):"
ffmpeg -hide_banner -buildconf 2>/dev/null | grep -E -- '--enable-(gpl|version3|nonfree|libmp3lame|libopus|audiotoolbox|libfdk)' | sed 's/^ */  /'
ffmpeg -hide_banner -L 2>/dev/null | head -3 | sed 's/^/  ffmpeg -L: /'

echo
echo "### Homebrew formulae (installed versions and declared licenses, from the local Homebrew metadata)"
brew --version | head -1
brew info --json=v2 --installed 2>/dev/null | /usr/bin/python3 -I -c '
import json,sys
d=json.load(sys.stdin)
want={"ffmpeg","xcodegen","git-lfs","lame","opus","x264","openssl@3","python@3.13","python@3.14","python@3.12","git"}
for f in d.get("formulae",[]):
    if f["name"] in want:
        inst=", ".join(i["version"] for i in f.get("installed",[]))
        deps=", ".join(f.get("dependencies",[])) or "none"
        print("  %s %s (tap %s): license %s; declared dependencies: %s" % (f["name"], inst, f.get("tap"), f.get("license"), deps))
'
ffbin="$(/usr/bin/python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v ffmpeg)")"
echo "libraries linked by ffmpeg's libavcodec (otool -L, non-system):"
otool -L "$(dirname "$ffbin")/../lib/libavcodec.dylib" | sed 1d | grep -v -E '^\s*/(usr/lib|System)/' | sed 's/^[[:space:]]*/  /'

echo
echo "### Python CI tooling (Scripts/tools/requirements.txt in \$SYLVIA_TOOLS_VENV=$SYLVIA_TOOLS_VENV)"
if [[ -x "$SYLVIA_TOOLS_VENV/bin/python" ]]; then
  "$SYLVIA_TOOLS_VENV/bin/python" --version
  "$SYLVIA_TOOLS_VENV/bin/python" -I - "$ROOT/Scripts/tools/requirements.txt" <<'EOF'
import sys, re
from importlib import metadata
req = {}
for line in open(sys.argv[1]):
    line = line.split('#')[0].strip()
    if line:
        n, v = line.split('==')
        req[re.sub(r'[-_.]+', '-', n).lower()] = v
installed = {re.sub(r'[-_.]+', '-', d.metadata['Name']).lower(): d for d in metadata.distributions()}
for n, v in sorted(req.items()):
    d = installed.get(n)
    if not d:
        print(f"  {n}: required {v}; NOT INSTALLED"); continue
    m = d.metadata
    lic = m.get('License-Expression') or m.get('License') or ''
    lic = lic.splitlines()[0][:80] if lic else ''
    cls = [c.split('::')[-1].strip() for c in (m.get_all('Classifier') or []) if c.startswith('License ::')]
    files = [str(f) for f in (d.files or []) if re.search(r'(LICEN[CS]E|COPYING|NOTICE)', str(f).split('/')[-1], re.I)]
    status = 'ok' if d.version == v else f'MISMATCH (installed {d.version})'
    print(f"  {n} {v}: {status}; license field: {lic or '-'}; classifiers: {', '.join(cls) or '-'}; files: {', '.join(files) or '-'}")
extra = sorted(set(installed) - set(req))
print(f"  installed but not in requirements.txt (every distribution, none excluded): "
      f"{', '.join(f'{n} {installed[n].version}' for n in extra) or 'none'}")
import datetime, ensurepip, os
def when(path):
    return datetime.datetime.fromtimestamp(os.path.getmtime(path)).astimezone().strftime('%Y-%m-%d %H:%M %Z')
cfg = os.path.join(sys.prefix, 'pyvenv.cfg')
print(f"  virtualenv: {sys.prefix}; pyvenv.cfg written {when(cfg)}: "
      + '; '.join(l.strip() for l in open(cfg) if l.split('=')[0].strip() in ('version', 'command')))
print(f"  pip bundled with this Python (ensurepip, what `python3 -m venv` installs): {ensurepip.version()}")
if 'pip' in installed:
    d = installed['pip']
    print(f"  pip in the virtualenv: {d.version}, its dist-info written {when(d._path)}; requested explicitly: "
          f"{'yes' if (d.read_text('REQUESTED') is not None) else 'no'}; pinned by requirements.txt: {'yes' if 'pip' in req else 'no'}")
EOF
else
  echo "  venv not present (Scripts/tools/bootstrap.sh creates it); not inspected"
fi
echo
echo "finished $(date -u +%Y-%m-%dT%H:%M:%SZ)"
