"""ADR-0014 evidence: the npm packages bundled into readium/swift-toolkit 3.11.0's navigator scripts.

ReadiumNavigator copies Sources/Navigator/EPUB/Assets into its resource bundle, including the webpack bundles
Assets/Static/scripts/readium-*.js built from Sources/Navigator/EPUB/Scripts. This script lists the runtime npm
imports of that source and their transitive closure from the committed pnpm-lock.yaml (dev dependencies excluded),
so the third-party JavaScript that ships inside Readium's resources is known by name and version.

  $SYLVIA_TOOLS_VENV/bin/python -I readium-js-closure.py <swift-toolkit checkout>
Reads files only; no network.
"""
import os
import re
import sys

import yaml

root = sys.argv[1]
scripts = os.path.join(root, 'Sources/Navigator/EPUB/Scripts')
imports = set()
for dp, _, fns in os.walk(os.path.join(scripts, 'src')):
    for fn in fns:
        if fn.endswith(('.js', '.ts')):
            text = open(os.path.join(dp, fn), encoding='utf-8').read()
            for m in re.finditer(r'''(?:from|require\()\s*["']([^"'.][^"']*)["']''', text):
                name = m.group(1)
                name = '/'.join(name.split('/')[:2]) if name.startswith('@') else name.split('/')[0]
                imports.add((name, os.path.relpath(os.path.join(dp, fn), scripts)))
lock = yaml.safe_load(open(os.path.join(scripts, 'pnpm-lock.yaml'), encoding='utf-8'))
print(f'pnpm-lock lockfileVersion: {lock.get("lockfileVersion")}')
runtime = lock.get('dependencies', {})
dev = lock.get('devDependencies', {})
print('imports in src/ (package <- file):')
for name, f in sorted(imports):
    kind = 'dependency' if name in runtime else ('devDependency (test only, not bundled)' if name in dev else 'NOT IN LOCK')
    print(f'  {name} <- {f}: {kind}')
packages = lock.get('packages', {})


def key(name, version):
    version = str(version).split('(')[0]
    return f'/{name}@{version}'


closure = {}
stack = [(n, v['version'] if isinstance(v, dict) else v) for n, v in runtime.items()]
while stack:
    name, version = stack.pop()
    k = key(name, version)
    if k in closure:
        continue
    entry = packages.get(k)
    if entry is None:
        print(f'  MISSING lock entry {k}')
        continue
    closure[k] = entry
    for n, v in (entry.get('dependencies') or {}).items():
        stack.append((n, v))
print(f'runtime closure (packages bundled, at most): {len(closure)}')
for k in sorted(closure):
    e = closure[k]
    flags = []
    if e.get('dev'):
        flags.append('dev')
    print(f'  {k.lstrip("/")} {"(" + ", ".join(flags) + ")" if flags else ""}')
