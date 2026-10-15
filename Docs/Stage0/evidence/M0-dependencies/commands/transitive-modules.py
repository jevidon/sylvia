"""ADR-0014 evidence: the module names and public C headers of every package the inventory admits only as transitive
(role product-transitive), read from each package's manifest at its pinned checkout, and compared with the inventory's
`modules` and `headers`, which Scripts/check-dependency-lock.py bans from product code.

  python3 -I Docs/Stage0/evidence/M0-dependencies/commands/transitive-modules.py   (from the repository root)

For each package: the checkout (left by resolve-locks.sh) whose HEAD is the pinned revision, read from the checkout's
.git/HEAD file (a 40-character commit names one commit of one repository; no git command runs); `swift package
dump-package` of its manifest; every target that is not a test, executable, plugin or macro target (each is a module a
product file could import once the package is in its build graph); and, for each of those targets, the .h files under
its public headers directory (publicHeadersPath, default `include`). Fails when the inventory's lists differ. Reads
files only; no network (dump-package evaluates the manifest locally, as resolution does).
"""
import json
import os
import subprocess
import sys
import tempfile

SKIP_TYPES = {'test', 'executable', 'plugin', 'macro'}


def head(d):
    """The commit a checkout's HEAD names (detached, as SwiftPM and Xcode leave it), or '' if it names a branch."""
    try:
        text = open(os.path.join(d, '.git', 'HEAD'), encoding='utf-8').read().strip()
    except OSError:
        return ''
    return text if len(text) == 40 and all(c in '0123456789abcdef' for c in text) else ''


inventory = json.load(open('Docs/Licenses/inventory.json', encoding='utf-8'))
checkouts = []
for top in ('Packages', 'Spikes', 'Apps'):
    for dp, dns, _ in os.walk(top):
        if dp.endswith(('/.build/checkouts', '/SourcePackages/checkouts')):
            checkouts += [os.path.join(dp, d) for d in sorted(dns)]
            dns[:] = []
        else:
            dns[:] = [d for d in dns if d not in {'.git', 'DerivedData'} and not d.endswith('.xcodeproj')]
swift = ['xcrun', 'swift']
failures = 0
for p in inventory['packages']:
    if p['role'] != 'product-transitive':
        continue
    print(f"## {p['name']} {p['version']} (pinned {p['revision']})")
    found = [d for d in checkouts if head(d) == p['revision']]
    if not found:
        print('   FAIL: no checkout at the pinned revision (run resolve-locks.sh first)')
        failures += 1
        continue
    d = found[0]
    with tempfile.TemporaryDirectory(prefix='transitive-modules-') as tmp:
        r = subprocess.run(swift + ['package', '--package-path', d, '--scratch-path', tmp, 'dump-package'],
                           capture_output=True, text=True)
    if r.returncode != 0:
        print(f'   FAIL: dump-package: {r.stderr.strip()[-300:]}')
        failures += 1
        continue
    dump = json.loads(r.stdout)
    modules, headers = [], []
    for t in dump.get('targets', []):
        if t.get('type') in SKIP_TYPES:
            continue
        modules.append(t['name'])
        tdir = os.path.join(d, t.get('path') or os.path.join('Sources', t['name']))
        inc = os.path.join(tdir, t.get('publicHeadersPath') or 'include')
        if os.path.isdir(inc):
            for hp, _, fns in os.walk(inc):
                headers += [fn for fn in fns if fn.endswith('.h')]
        print(f"   target {t['name']} ({t.get('type')}), {os.path.relpath(tdir, d)}"
              + (f"; public headers in {os.path.relpath(inc, d)}" if os.path.isdir(inc) else ''))
    modules, headers = sorted(set(modules)), sorted(set(headers))
    print(f'   checkout: {d}')
    print(f"   modules from the manifest: {', '.join(modules)}")
    print(f"   public headers: {', '.join(headers) or 'none'}")
    for key, have in (('modules', modules), ('headers', headers)):
        want = sorted(p.get(key, []))
        if want == have:
            print(f'   inventory {key}: identical')
        else:
            print(f'   FAIL inventory {key}: {want}; the manifest gives {have}')
            failures += 1
print()
print(f'failures: {failures}')
sys.exit(1 if failures else 0)
