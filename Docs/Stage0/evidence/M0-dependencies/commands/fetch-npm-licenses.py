"""ADR-0014 evidence: the license file of every npm package in the runtime closure of readium/swift-toolkit 3.11.0's
navigator scripts (the closure that readium-js-closure.py lists), as published in that exact package version.

  python3 -I fetch-npm-licenses.py <closure list> <new output dir> <combined text file>

<closure list>: one `name@version` per line. For each, the published file list
(https://unpkg.com/<name>@<version>/?meta) is read and the file named LICENSE, LICENCE, COPYING or license (any
extension, top level) is fetched from https://unpkg.com/<name>@<version>/<file>. Public HTTPS GETs of public package
files only; nothing from this repository is sent. Downloads are data: each is written into the new output directory,
read as text and never executed. Writes <combined text file>: every license text under a header naming the package,
its source URL and SHA-256, and prints one line per package (and the packages that publish no license file).
"""
import hashlib
import json
import os
import re
import sys
import urllib.request

closure_path, out_dir, combined_path = sys.argv[1:4]
if os.path.exists(out_dir):
    sys.exit(f'refusing: {out_dir} already exists; give a new directory')
os.makedirs(out_dir)
specs = [l.strip() for l in open(closure_path) if l.strip()]
NAME = re.compile(r'^/(licen[cs]e|copying)([._-][^/]*)?$', re.I)


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'sylvia-license-inventory'})
    with urllib.request.urlopen(req, timeout=60) as r:
        if not r.geturl().startswith('https://'):
            raise RuntimeError(f'redirected off HTTPS: {r.geturl()}')
        return r.read()


found, missing, failed = [], [], []
parts = []
for spec in specs:
    name, version = spec.rsplit('@', 1)
    base = f'https://unpkg.com/{name}@{version}'
    try:
        meta = json.loads(get(base + '/?meta'))
        files = [f['path'] for f in meta.get('files', []) if NAME.match(f.get('path', ''))]
        if not files:
            missing.append(spec)
            print(f'{spec}: no top-level license file published')
            continue
        url = base + files[0]
        data = get(url)
        digest = hashlib.sha256(data).hexdigest()
        safe = re.sub(r'[^A-Za-z0-9._@-]', '_', spec)
        with open(os.path.join(out_dir, safe + '-' + files[0].lstrip('/')), 'wb') as f:
            f.write(data)
        text = data.decode('utf-8', errors='replace').strip()
        first = next((l.strip() for l in text.splitlines() if re.search(r'copyright|\(c\)|©', l, re.I)), '(no copyright line)')
        print(f'{spec}: {files[0].lstrip("/")} ({len(data)} bytes, sha256 {digest}); {first[:120]}')
        parts.append(f'==== {spec}\nsource: {url}\nsha256: {digest}\n\n{text}\n')
        found.append(spec)
    except Exception as e:  # recorded, never hidden
        failed.append(spec)
        print(f'{spec}: FAILED ({e})')
with open(combined_path, 'w', encoding='utf-8') as f:
    f.write('License files of the npm packages in the runtime closure of readium/swift-toolkit 3.11.0\'s navigator\n'
            'scripts (Sources/Navigator/EPUB/Scripts/pnpm-lock.yaml at d82f44f4), as published in each version.\n'
            'Written by Docs/Stage0/evidence/M0-dependencies/commands/fetch-npm-licenses.py; see\n'
            'Docs/Licenses/third-party-inventory.md. Packages that publish no license file: '
            + (', '.join(missing) or 'none') + '.\n\n')
    f.write('\n'.join(parts))
print(f'\npackages: {len(specs)}; license files fetched: {len(found)}; none published: {len(missing)}; failed: {len(failed)}')
sys.exit(1 if failed else 0)
