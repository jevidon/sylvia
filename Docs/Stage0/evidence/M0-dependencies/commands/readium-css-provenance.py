"""ADR-0014 evidence: where the ReadiumCSS stylesheets that readium/swift-toolkit 3.11.0 bundles come from, and their
license, read at that source (review R3-03: it had been inferred from the toolkit's own license).

  python3 -I readium-css-provenance.py <swift-toolkit checkout> <new output dir>

The stylesheets (Sources/Navigator/EPUB/Assets/Static/readium-css, 13 files) name their repository,
https://github.com/readium/readium-css, but no version and no license. Each one's git blob id is compared with the files
under css/dist in every commit of readium/readium-css that touched css/dist, and in each release tag: the commit where
the most files are identical is their source. Each file that differs there is shown as a diff against that commit, and
readium-css's LICENSE at that commit is fetched and compared with the toolkit's LICENSE. GitHub API requests use the gh
CLI's token when it has one (never printed or saved); only public data are read; responses are saved under the output
directory as data and never run.
"""
import difflib
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = 'sylvia-dependency-inventory (ADR-0014 license provenance)'
API = 'https://api.github.com/repos/readium/readium-css'
RAW = 'https://raw.githubusercontent.com/readium/readium-css/'
_TOKEN = []


def token():
    if not _TOKEN:
        try:
            r = subprocess.run(['gh', 'auth', 'token'], capture_output=True, text=True, timeout=30)
            _TOKEN.append(r.stdout.strip() if r.returncode == 0 else '')
        except (OSError, subprocess.SubprocessError):
            _TOKEN.append('')
    return _TOKEN[0]


def get(url):
    headers = dict(Accept='application/vnd.github+json' if url.startswith(API) else '*/*')
    headers['User-Agent'] = UA
    if url.startswith(API) and token():
        headers['Authorization'] = 'Bearer ' + token()
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=90) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (403, 429, 500, 502, 503, 504) and attempt < 3:  # rate limited, or a transient server error
                time.sleep(20 * (attempt + 1))
                continue
            raise SystemExit('FAIL %s: status %s' % (url, e.code))
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < 3:
                time.sleep(10 * (attempt + 1))
                continue
            raise SystemExit('FAIL %s: %s' % (url, e))


def blob_id(data):
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


def main():
    toolkit, out = sys.argv[1], sys.argv[2]
    if os.path.exists(out):
        sys.exit('refusing: %s already exists; give a new directory' % out)
    os.makedirs(out)
    print('readium-css provenance %s; GitHub API %s' % (time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                                                       'authenticated with the gh CLI token (not shown)' if token() else 'unauthenticated'))
    base = os.path.join(toolkit, 'Sources/Navigator/EPUB/Assets/Static/readium-css')
    local = dict()
    for dp, _, fns in os.walk(base):
        for fn in fns:
            if fn.endswith('.css'):
                rel = os.path.relpath(os.path.join(dp, fn), base)
                local[rel] = blob_id(open(os.path.join(dp, fn), 'rb').read())
    print('%d stylesheets bundled by the toolkit, with their blob ids:' % len(local))
    for rel in sorted(local):
        print('  %s %s' % (local[rel], rel))
    commits, page = [], 1
    while True:
        batch = json.loads(get(API + '/commits?path=css/dist&per_page=100&page=%d' % page))
        commits += batch
        if len(batch) < 100:
            break
        page += 1
    tags = json.loads(get(API + '/tags?per_page=100'))
    candidates = [(c['sha'], c['commit']['committer']['date'], c['commit']['message'].splitlines()[0]) for c in commits]
    candidates += [(t['commit']['sha'], 'tag ' + t['name'], '') for t in tags]
    print('%d commits touch css/dist; %d release tags' % (len(commits), len(tags)))
    best = None
    for sha, when, subject in candidates:
        tree = json.loads(get(API + '/git/trees/%s?recursive=1' % sha))
        blobs = dict((t['path'], t['sha']) for t in tree.get('tree') or [] if t['type'] == 'blob')
        same = sorted(rel for rel, bid in local.items() if blobs.get('css/dist/' + rel) == bid)
        if same or when.startswith('tag'):
            print('  %s %s: %d of %d identical%s' % (sha[:12], when, len(same), len(local), ('  (' + subject[:60] + ')') if subject else ''))
        if best is None or len(same) > len(best[1]):
            best = (sha, same, when)
    sha, same, when = best
    print('source: readium/readium-css %s (%s): %d of %d stylesheets identical by blob id' % (sha, when, len(same), len(local)))
    for rel in sorted(set(local) - set(same)):
        up = get(RAW + sha + '/css/dist/' + rel).decode('utf-8').splitlines()
        lo = open(os.path.join(base, rel), encoding='utf-8').read().splitlines()
        d = list(difflib.unified_diff(up, lo, 'readium-css %s css/dist/%s' % (sha[:12], rel), 'swift-toolkit 3.11.0 %s' % rel, lineterm='', n=1))
        print('differs: %s (%d lines), diff against the source:' % (rel, sum(1 for x in d if x[:1] in '+-' and x[:3] not in ('+++', '---'))))
        for x in d:
            print('    ' + x)
    lic = get(RAW + sha + '/LICENSE')
    path = os.path.join(out, 'LICENSE-' + sha)
    open(path, 'wb').write(lic)
    digest = hashlib.sha256(lic).hexdigest()
    toolkit_digest = hashlib.sha256(open(os.path.join(toolkit, 'LICENSE'), 'rb').read()).hexdigest()
    print('readium-css LICENSE at %s: %d bytes, sha256 %s (saved as %s); first line: %s' % (sha, len(lic), digest, path, lic.decode('utf-8').splitlines()[0]))
    print('the toolkit LICENSE: sha256 %s: %s' % (toolkit_digest, 'byte-identical' if digest == toolkit_digest else 'DIFFERENT'))
    for line in lic.decode('utf-8').splitlines():
        if line.strip().lower().startswith('copyright'):
            print('copyright line: ' + line.strip())
    return 0


if __name__ == '__main__':
    sys.exit(main())
