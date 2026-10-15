"""ADR-0014 evidence: for every package pinned in a committed Package.resolved, find a checkout whose HEAD is the
pinned revision (left by resolve-locks.sh under each project's or package's .build), and report every license,
notice and copyright file in it, with its SHA-256 and opening lines. With --copy DIR, also copy each package's
license and notice files into DIR/<slug>/ (the texts the acknowledgements reproduce).

Run from the repository root after resolve-locks.sh:
  python3 -I Docs/Stage0/evidence/M0-dependencies/commands/read-licenses.py [--copy Docs/Licenses/texts]
Reads files only; no network.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

LICENSE_NAME = re.compile(r'^(licen[cs]e|copying|notice|copyright|unlicense)([._-].*)?$', re.I)
SKIP_DIRS = {'.git', '.build', 'node_modules'}


def git(*args, cwd):
    return subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True).stdout.strip()


def origin(d):
    """The upstream URL of a SwiftPM checkout: its origin is a local mirror whose own origin is the package URL."""
    url = git('config', '--get', 'remote.origin.url', cwd=d)
    for _ in range(3):
        if url.startswith('/') and os.path.isdir(url):
            url = git('config', '--get', 'remote.origin.url', cwd=url)
        else:
            break
    return url


def norm(url):
    u = url.strip().lower().rstrip('/')
    return u[:-4] if u.endswith('.git') else u


def slug(url):
    owner, repo = norm(url).split('/')[-2:]
    return f'{owner}__{repo}'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 16), b''):
            h.update(b)
    return h.hexdigest()


def main():
    copy_to = None
    if '--copy' in sys.argv:
        copy_to = sys.argv[sys.argv.index('--copy') + 1]
    files = git('ls-files', '*Package.resolved', cwd='.').split()
    pins = {}
    for f in files:
        for p in json.load(open(f))['pins']:
            st = p['state']
            k = norm(p['location'])
            e = pins.setdefault(k, {'location': p['location'], 'identity': p['identity'], 'version': st.get('version'),
                                    'revision': st['revision'], 'locks': set()})
            if (e['version'], e['revision']) != (st.get('version'), st['revision']):
                print(f'CONFLICT: {k} pinned at {e["version"]} {e["revision"]} and {st.get("version")} {st["revision"]} ({f})')
            e['locks'].add(os.path.dirname(f))
    checkouts = []
    for top in ('Packages', 'Spikes', 'Apps'):
        for dp, dns, _ in os.walk(top):
            if dp.endswith(('/.build/checkouts', '/SourcePackages/checkouts')):
                checkouts += [os.path.join(dp, d) for d in sorted(dns)]
                dns[:] = []
            else:
                dns[:] = [d for d in dns if d not in {'.git', 'DerivedData'} and not d.endswith('.xcodeproj')]
    heads = {}
    for d in checkouts:
        heads.setdefault(git('rev-parse', 'HEAD', cwd=d), []).append(d)
    print(f'locks: {len(files)}; packages pinned: {len(pins)}; checkouts found: {len(checkouts)}')
    missing = 0
    for k, p in sorted(pins.items(), key=lambda kv: kv[0].rsplit('/', 1)[-1].lower()):
        print()
        print(f'## {p["location"]} {p["version"]} (identity {p["identity"]}) pinned {p["revision"]}')
        print(f'   locks: {", ".join(sorted(p["locks"]))}')
        cands = [d for d in heads.get(p['revision'], []) if norm(origin(d)) == k]
        if not cands:
            print('   CHECKOUT AT PINNED REVISION NOT FOUND')
            missing += 1
            continue
        d = cands[0]
        dirty = git('status', '--porcelain', '--untracked-files=no', cwd=d)
        tags = git('tag', '--points-at', 'HEAD', cwd=d).split()
        version_tags = [t for t in tags if t in (p['version'], f'v{p["version"]}')]
        tag_note = ', '.join(version_tags) or 'NO TAG FOR THE PINNED VERSION'
        if len(tags) > len(version_tags):
            tag_note += f' (+{len(tags) - len(version_tags)} other tags)'
        print(f'   checkout: {d}; HEAD = pinned revision; upstream = {origin(d)};'
              f' tracked files modified: {"YES" if dirty else "no"}; version tag at HEAD: {tag_note}')
        found = []
        for dp, dns, fns in os.walk(d):
            dns[:] = sorted(x for x in dns if x not in SKIP_DIRS)
            for fn in sorted(fns):
                if LICENSE_NAME.match(fn):
                    found.append(os.path.join(dp, fn))
        if not found:
            print('   license files: NONE')
        for path in found:
            rel = os.path.relpath(path, d)
            text = open(path, encoding='utf-8', errors='replace').read()
            lines = [l.strip() for l in text.splitlines() if l.strip()]
            print(f'   - {rel} ({os.path.getsize(path)} bytes, sha256 {sha256(path)})')
            for l in lines[:3]:
                print(f'     | {l[:150]}')
            for marker in ('Runtime Library Exception', 'LLVM Exceptions', 'OpenSSL License', 'ISC license', 'BoringSSL',
                           'GNU General Public', 'GNU Lesser', 'Mozilla Public', 'zlib', 'Info-ZIP'):
                if marker.lower() in text.lower():
                    print(f'     mentions: {marker}')
            if copy_to and (os.path.dirname(rel) == '' or 'boringssl' in rel.lower() or 'minizip' in rel.lower()
                            or 'llhttp' in rel.lower() or '/fonts/' in rel.lower()):
                dest = os.path.join(copy_to, slug(p['location']), rel.replace('/', '__'))
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copyfile(path, dest)
                print(f'     copied to {dest}')
    print()
    print(f'missing checkouts: {missing}')
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
