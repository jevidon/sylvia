"""For every package pinned in a committed Package.resolved, find a checkout at the pinned revision
under the worktree's .build directories and report its license file and first lines.

Run after lockcheck.sh (which leaves the checkouts under each project's and package's .build):
  find Packages Spikes Apps -mindepth 1 -maxdepth 7 -type d \\( -path '*/.build/checkouts/*' \\
       -o -path '*/SourcePackages/checkouts/*' \\) -prune > .build/scratch/checkouts.txt
  python3 -I license_inventory.py <repository root> .build/scratch/checkouts.txt
"""
import json, os, subprocess, sys, glob

root = sys.argv[1]
os.chdir(root)
files = subprocess.run(['git', 'ls-files', '*Package.resolved'], capture_output=True, text=True).stdout.split()
pins = {}
for f in files:
    for p in json.load(open(f))['pins']:
        st = p['state']
        key = p['location'].lower().rstrip('/').removesuffix('.git')
        pins.setdefault(key, {'location': p['location'], 'version': st.get('version'), 'revision': st['revision'], 'locks': set()})
        pins[key]['locks'].add(os.path.dirname(f))
checkouts = [l.strip() for l in open(sys.argv[2]) if l.strip()]
print(f'packages pinned: {len(pins)}; checkouts found: {len(checkouts)}')
missing = 0
for key, p in sorted(pins.items(), key=lambda kv: kv[0].rsplit('/', 1)[-1].lower()):
    found = None
    for d in checkouts:
        try:
            rev = subprocess.run(['git', '-C', d, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
        except Exception:
            continue
        if rev == p['revision']:
            found = d
            break
    print()
    print(f"{p['location']} {p['version']} pinned {p['revision']}")
    print(f"  locks: {', '.join(sorted(p['locks']))}")
    if not found:
        print('  CHECKOUT AT PINNED REVISION NOT FOUND')
        missing += 1
        continue
    lic = sorted(n for n in os.listdir(found) if n.lower().startswith(('license', 'licence', 'copying')))
    notice = sorted(n for n in os.listdir(found) if n.lower().startswith('notice'))
    print(f"  checkout: {found} (HEAD = pinned revision)")
    print(f"  license file: {', '.join(lic) or 'NONE'}; notice: {', '.join(notice) or 'none'}")
    if lic:
        lines = [l.strip() for l in open(os.path.join(found, lic[0]), encoding='utf-8', errors='replace') if l.strip()]
        for l in lines[:2]:
            print(f'  | {l[:160]}')
        extra = [l for l in lines if 'Runtime Library Exception' in l]
        if extra:
            print(f'  | ... {extra[0][:120]}')
print()
print(f'missing checkouts: {missing}')
