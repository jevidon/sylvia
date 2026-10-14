"""ADR-0014 evidence: cross-check Fixtures/LICENSES.md against the committed files (read-only; requests for corrections
go to the file's owner, this script changes nothing).

  python3 -I Docs/Stage0/evidence/M0-dependencies/commands/fixtures-crosscheck.py      (from the repository root)

1. Every SHA-256 the file states next to a file name is recomputed from that file (the name is resolved against
   `git ls-files`; it must match exactly one tracked path).
2. The G0.1 EPUB MANIFEST.tsv digests and sizes are recomputed.
3. Every count and size the file states for committed fixtures is recounted.
4. Every tracked fixture-like binary (EPUB, PDF, audio, SQLite, certificates, fonts, archives) is checked to be named
   in the file, and every name in the fetched-into-cache table is checked against Scripts/fixtures/manifest.tsv.
Prints one line per check and a summary; exits 1 if any check fails. No network.
"""
import hashlib
import os
import re
import subprocess
import sys

LIC = 'Fixtures/LICENSES.md'
failures = 0


def check(ok, text):
    global failures
    print(('ok    ' if ok else 'FAIL  ') + text)
    if not ok:
        failures += 1


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


tracked = subprocess.run(['git', 'ls-files'], capture_output=True, text=True, check=True).stdout.split('\n')
tracked = [t for t in tracked if t]
text = open(LIC, encoding='utf-8').read()
print(f'{LIC}: {len(text.splitlines())} lines; tracked files in the repository: {len(tracked)}')

print('\n## 1. Stated SHA-256 values')
pairs = []
for line in text.splitlines():
    if line.startswith('|'):
        names = re.findall(r'`([^`]+\.[A-Za-z0-9]+)`', line)
        digests = re.findall(r'`([0-9a-f]{64})`', line)
        if names and len(digests) == 1:
            if names[0].startswith('generated/'):
                # A file generated into the cache (never tracked): the row says its digest is pinned in the generator
                # it names, so the check is that the generator holds exactly that digest.
                generators = [n for n in names if n.startswith('Scripts/fixtures/generate-')]
                held = bool(generators) and digests[0] in open(generators[0], encoding='utf-8').read()
                check(held, f'{names[0]} (cache, not tracked): digest {digests[0][:12]}... pinned in {generators[:1]}')
                continue
            pairs.append((names[0], digests[0]))
for name, digest in re.findall(r'`([^`]+\.ttf)`, SHA-256 `([0-9a-f]{64})`', text):
    pairs.append((name, digest))
for name, digest in pairs:
    matches = [t for t in tracked if t == name or t.endswith('/' + name)]
    if len(matches) != 1:
        check(False, f'{name}: resolves to {len(matches)} tracked paths {matches[:3]}')
        continue
    actual = sha256(matches[0])
    check(actual == digest, f'{matches[0]}: stated {digest[:12]}..., actual {actual[:12]}...')

print('\n## 2. G0.1 EPUB MANIFEST.tsv')
base = 'Spikes/G01-EPUB/Fixtures/generated'
rows = [l.split('\t') for l in open(f'{base}/MANIFEST.tsv', encoding='utf-8') if l.strip() and not l.startswith('#')]
for row in rows:
    path = f'{base}/{row[0]}'
    ok = os.path.exists(path) and os.path.getsize(path) == int(row[1]) and sha256(path) == row[2]
    check(ok, f'{path}: size {row[1]} and SHA-256 {row[2][:12]}... as MANIFEST.tsv states')
epubs = sorted(t for t in tracked if t.startswith(base + '/') and t.endswith('.epub'))
check(len(epubs) == 17 and len(rows) == 17, f'{base}: {len(epubs)} tracked EPUBs, {len(rows)} manifest rows (LICENSES.md says 17)')
listed = re.search(r'17 EPUBs: (.+?) \(`\.epub`', text)
stems = re.findall(r'`(g01-[a-z0-9-]+)`', listed.group(1)) if listed else []
check(sorted(f'{base}/{s}.epub' for s in stems) == epubs, f'the 17 EPUB names listed in LICENSES.md equal the tracked EPUBs ({len(stems)} listed)')
sizes = [os.path.getsize(e) for e in epubs]
check(sizes and min(sizes) == 1299 and max(sizes) == 205767, f'EPUB sizes {min(sizes)} to {max(sizes)} bytes (LICENSES.md: 1,299 to 205,767)')


def count(prefix, suffix=''):
    return len([t for t in tracked if t.startswith(prefix) and t.endswith(suffix)])


print('\n## 3. Stated counts and sizes')
pdfs = count('Spikes/G01-PDF/Fixtures/', '.pdf')
check(pdfs == 10, f'Spikes/G01-PDF/Fixtures: {pdfs} PDFs (LICENSES.md table lists 10)')
g02 = ['transfer-manifest', 'pairing-payload', 'pair-request', 'pair-response', 'capabilities', 'catalog-page',
       'device-inbox-page', 'receipt', 'error']
n = sum(count(f'Contracts/fixtures/{s}.v1/', '.json') for s in g02)
check(n == 60, f'G0.2 contract fixtures: {n} files (LICENSES.md: 60)')
n = count('Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/Fixtures/manifests/semantic-invalid/', '.json')
check(n == 14, f'G0.2 semantic-invalid manifests: {n} (LICENSES.md: 14)')
certs = 'Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/Fixtures/certs/'
n_der, n_pin = count(certs, '.der'), count(certs, '.spki-sha256')
check(n_der == 3 and n_pin == 3, f'G0.2 certificates: {n_der} DER and {n_pin} pins (LICENSES.md: p256, p384, rsa2048)')
keys = [t for t in tracked if re.search(r'\.(p12|key|pem)$', t) or 'PRIVATE KEY' in t]
check(not keys, f'no private key files tracked ({len(keys)} found)')
for schema, valid, invalid in [('import-handoff-manifest', 3, 17), ('sylviapack-manifest', 4, 22), ('backup-manifest', 2, 20),
                               ('context-pack', 8, 21), ('provider-config', 5, 12), ('design-tokens', 2, 12)]:
    v = count(f'Contracts/fixtures/{schema}.v1/valid/', '.json')
    i = count(f'Contracts/fixtures/{schema}.v1/invalid/', '.json')
    check((v, i) == (valid, invalid), f'{schema}.v1: {v} valid, {i} invalid (LICENSES.md: {valid}, {invalid})')
for path, size in [('Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite', 352256),
                   ('Spikes/G05-AI/Tests/SylviaContextTests/EvaluationSet/eval-set.v0.json', 15795),
                   ('Contracts/design/marginalia.v1.json', 65683)]:
    actual = os.path.getsize(path) if os.path.exists(path) else -1
    check(actual == size, f'{path}: {actual} bytes (LICENSES.md: {size:,})')
snaps = [t for t in tracked if t.startswith('Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests/') and t.endswith('.png')]
total = sum(os.path.getsize(s) for s in snaps)
largest = max((os.path.getsize(s) for s in snaps), default=0)
check((len(snaps), total, largest) == (527, 37703582, 368357),
      f'snapshot references: {len(snaps)} files, {total:,} bytes, largest {largest:,} (LICENSES.md: 527, 37,703,582, 368,357)')
n = count('Packages/Design/LintFixtures/')
check(n == 9, f'Packages/Design/LintFixtures: {n} files (LICENSES.md: 9)')

print('\n## 4. Fixture-like files named in LICENSES.md, and the fetch manifest')
binary = re.compile(r'\.(epub|pdf|mp3|m4a|m4b|aac|caf|wav|flac|ogg|opus|sqlite|db|der|ttf|otf|woff2?|zip|sylviapack)$', re.I)
for t in tracked:
    if binary.search(t):
        name = os.path.basename(t)
        stem = name.rsplit('.', 1)[0]
        named = (f'`{name}`' in text or f'/{name}`' in text or f'`{stem}`' in text
                 or (t.startswith(certs) and stem in ('p256', 'p384', 'rsa2048') and '{p256,p384,rsa2048}' in text))
        check(named, f'{t}: named in LICENSES.md')
manifest = [l.split('\t')[0] for l in open('Scripts/fixtures/manifest.tsv', encoding='utf-8') if l.strip() and not l.startswith('#')]
section = text.split('## Fetched into the cache', 1)[1].split('\n## ', 1)[0]
fetched = re.findall(r'^\| `([^`]+)`', section, re.M)
check(sorted(fetched) == sorted(manifest), f'fetched-into-cache table {sorted(fetched)} equals Scripts/fixtures/manifest.tsv {sorted(manifest)}')

print(f'\nchecks failed: {failures}')
sys.exit(1 if failures else 0)
