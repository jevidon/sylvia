"""ADR-0014 evidence: a version-exact security advisory search for everything third-party that the inventory records,
in two public advisory databases, so each result can be cited and re-run.

  python3 -I Docs/Stage0/evidence/M0-dependencies/commands/advisories-search.py <npm closure list> <new output dir>
  (from the repository root; <npm closure list> is one `name@version` per line, as fetch-external-licenses.sh writes
  it from readium-js-closure.py)

What is queried, each at its exact version:
  npm        the runtime closure of readium/swift-toolkit 3.11.0's navigator scripts (readium-*.js, shipped in the
             app's resource bundle), and `hypothesis` 1.1763.0, the Hypothesis client whose anchoring code Readium
             vendors (Sources/Navigator/EPUB/Scripts/src/vendor/hypothesis/README.md names v1.1763.0)
  SwiftURL   every package in Docs/Licenses/inventory.json (github.com/<owner>/<repo> at its pinned version)
  PyPI       the CI tooling in the inventory's python_tools (requirements.txt pins, and the virtualenv's installer at
             the version the shared virtualenv holds and at the one a freshly bootstrapped virtualenv holds)
  Actions    each workflow action in the inventory's ci_actions, at the release its movable tag names today
Sources:
  OSV        POST https://api.osv.dev/v1/querybatch: one query per package at its version (does an advisory affect
             this version?), and one per package without a version (which advisories exist for any version, as
             context); then GET https://api.osv.dev/v1/vulns/<id> for each advisory returned. OSV merges the GitHub
             Advisory Database, the OpenSSF malicious-packages feed (MAL-*) and other ecosystem databases.
  GitHub     GET https://api.github.com/advisories?ecosystem=<e>&affects=<name@version,...>&type=<reviewed|malware>
             (`affects` matches advisories whose vulnerable range contains that version).
  Tags       GET https://api.github.com/repos/<owner>/<repo>/tags to find the release a movable action tag names.
  Repository GET https://api.github.com/repos/<owner>/<repo>/security-advisories for every package's repository and the
             upstreams of the three forks (UPSTREAMS): the advisories a project publishes itself, which the Advisory
             Database lists only after GitHub reviews them (review R3-02 found three of Apple's in neither database
             above). Each is printed with its range checked against the pinned version (control: apple/swift-nio
             must list GHSA-r3rc-9hpw-54v9).
  NVD        GET https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=<keyword> for each package's name
             (NVD_PACKAGE_KEYWORDS; control: "Zip Swift" must list CVE-2023-39135), paced to 5 requests in 30 s.
Every advisory the repository and NVD searches list must have a verdict recorded in JUDGED; one without fails the
search until someone judges it against the pinned version and records it there and in advisories.md.
Positive controls: each ecosystem's version queries also carry one or more package versions with a well-known
advisory (listed in CONTROLS), so an empty result for Sylvia's packages means "none listed", not "the query matched
nothing". If GitHub does not return a control's advisory, the search fails. If OSV does not (it evaluates no versions
for the GitHub Actions ecosystem), OSV's version results for that ecosystem are not used: its any-version query must
then list no advisory at all for each package, or the search fails as unable to judge.
Package names: GitHub matches `affects` names case-sensitively and records some PyPI names as published (PyYAML) and
others normalized (pyyaml), so each Python package is sent in every spelling (as requirements.txt writes it, its
normalized form and the underscore form). Both databases record most Swift advisories under the repository URL's form
(github.com/apple/swift-nio) but some under the bare repository name (swift-crypto's GHSA-9m44-rr2w-ppp7 is recorded as
`swift-crypto`), so each Swift package is sent as its URL writes it, in lower case, and by its bare repository name in
both cases; the Swift controls include one advisory of each kind.
Only public package names and versions are sent (they come from public lockfiles and the public package registries);
nothing from this repository's own code, documents or fixtures. Responses are data: each is saved under the new output
directory, parsed as JSON and never executed. A query that fails is a failure (exit status 1), never "none".
GitHub API requests use the gh CLI's token when it has one (the unauthenticated limit, 60 requests an hour, is shared
by every job on this host); the token is never printed or saved.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HYPOTHESIS = ('hypothesis', '1.1763.0')
UA = {'User-Agent': 'sylvia-dependency-inventory (ADR-0014 advisory search)'}
LABELS = {}  # (name, version) -> how to describe a queried version that is not the pinned one
def norm_py(name):
    return re.sub(r'[-_.]+', '-', name).lower()


def swift_spellings(name):
    """github.com/<owner>/<repo> as written, in lower case, and the bare repository name as written and in lower case."""
    repo = name.rsplit('/', 1)[-1]
    return list(dict.fromkeys([name, name.lower(), repo, repo.lower()]))


# ecosystem -> [(name, version, an advisory both databases list for that version, spellings to send)]
CONTROLS = {
    'npm': [('lodash', '4.17.15', 'GHSA-p6mc-m468-83gw', ['lodash'])],  # CVE-2020-8203, prototype pollution
    'SwiftURL': [
        # Recorded under the URL form (and a pinned package: CVE-2023-39135).
        ('github.com/marmelroy/Zip', '2.1.2', 'GHSA-g454-wj9r-jpg4', swift_spellings('github.com/marmelroy/Zip')),
        # Recorded under the bare name `swift-crypto` (CVE-2026-28815, 4.0.0 to 4.3.0).
        ('github.com/apple/swift-crypto', '4.3.0', 'GHSA-9m44-rr2w-ppp7', swift_spellings('github.com/apple/swift-crypto')),
    ],
    'PyPI': [('pyyaml', '5.3', 'GHSA-8q59-q68h-6hv4', ['PyYAML', 'pyyaml'])],  # CVE-2020-14343 (GitHub writes PyYAML)
    'GitHub Actions': [('actions/download-artifact', '4.1.2', 'GHSA-cxww-7g56-2vh6', ['actions/download-artifact'])],
}


_TOKEN = []


def token():
    """The gh CLI's token, when it has one: GitHub's unauthenticated API limit, 60 requests an hour, is shared by every
    job on this host. Only public advisory data is read with it; it is never printed or saved."""
    if not _TOKEN:
        try:
            r = subprocess.run(['gh', 'auth', 'token'], capture_output=True, text=True, timeout=30)
            _TOKEN.append(r.stdout.strip() if r.returncode == 0 else '')
        except (OSError, subprocess.SubprocessError):
            _TOKEN.append('')
    return _TOKEN[0]


def request(url, body=None, accept='application/json'):
    data = json.dumps(body).encode() if body is not None else None
    headers = dict(UA, Accept=accept)
    if url.startswith('https://api.github.com/') and token():
        headers['Authorization'] = 'Bearer ' + token()
    if data is not None:
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=data, headers=headers, method='POST' if data is not None else 'GET')
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                if not r.geturl().startswith('https://'):
                    raise RuntimeError(f'redirected off HTTPS: {r.geturl()}')
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 2:  # rate limited, or a transient server error
                time.sleep(5 * (attempt + 1))
                continue
            return e.code, e.read()
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            raise RuntimeError(f'{url}: {e}')
    raise RuntimeError(f'{url}: no response')


class Search:
    def __init__(self, out):
        self.out = out
        self.failures = 0
        self.records = {}

    def fail(self, text):
        self.failures += 1
        print(f'FAIL {text}')

    def save(self, name, payload):
        with open(os.path.join(self.out, re.sub(r'[^A-Za-z0-9._@-]+', '_', name)), 'wb') as f:
            f.write(payload)

    def vuln(self, vid):
        if vid not in self.records:
            status, body = request(f'https://api.osv.dev/v1/vulns/{urllib.parse.quote(vid)}')
            self.save(f'osv-{vid}.json', body)
            if status != 200:
                self.fail(f'OSV {vid}: status {status}')
                self.records[vid] = None
            else:
                self.records[vid] = json.loads(body)
        return self.records[vid]

    def osv_batch(self, ecosystem, entries, label, with_version):
        """{(name, version): set of advisory ids} for entries [(name, version, spellings)], one query per spelling,
        or None when the query failed."""
        flat = [(n, v, sp) for n, v, sps in entries for sp in sps]
        queries = [{'package': {'name': sp, 'ecosystem': ecosystem}, **({'version': v} if with_version else {})}
                   for _, v, sp in flat]
        status, body = request('https://api.osv.dev/v1/querybatch', {'queries': queries})
        self.save(f'osv-querybatch-{ecosystem}-{label}.json', body)
        if status != 200:
            self.fail(f'OSV querybatch ({ecosystem}, {label}): status {status}: {body[:200]!r}')
            return None
        results = json.loads(body).get('results', [])
        if len(results) != len(queries):
            self.fail(f'OSV querybatch ({ecosystem}, {label}): {len(results)} results for {len(queries)} queries')
            return None
        merged = {}
        for (n, v, sp), r in zip(flat, results):
            if r.get('next_page_token'):
                self.fail(f'OSV {sp}: more advisories than one page (next_page_token); not read')
            merged.setdefault((n, v), set()).update(x['id'] for x in (r.get('vulns') or []))
        return merged

    def github(self, ecosystem, kind, entries, label=''):
        affects = ','.join(dict.fromkeys(f'{sp}@{v}' for _, v, sps in entries for sp in sps))
        url = ('https://api.github.com/advisories?' +
               urllib.parse.urlencode({'ecosystem': ecosystem, 'type': kind, 'affects': affects, 'per_page': 100}))
        status, body = request(url, accept='application/vnd.github+json')
        self.save(f'github-advisories-{ecosystem}-{kind}{label}.json', body)
        if status != 200:
            self.fail(f'GitHub advisories ({ecosystem}, {kind}): status {status}: {body[:200]!r}')
            return None
        advs = json.loads(body)
        if len(advs) >= 100:
            self.fail(f'GitHub advisories ({ecosystem}, {kind}): a full page of 100; results may be truncated')
        return advs


def ranges(rec, names):
    """Affected ranges of an OSV record for the package, under any of its spellings, compactly."""
    names = {x.lower().rstrip('/') for x in names}
    out = []
    for a in rec.get('affected') or []:
        if ((a.get('package') or {}).get('name') or '').lower().rstrip('/') not in names:
            continue
        for r in a.get('ranges') or []:
            out.append(' '.join(f'{k} {v}' for e in r.get('events') or [] for k, v in e.items()))
        if a.get('versions') and not a.get('ranges'):
            out.append('versions ' + ', '.join(a['versions'][:8]) + (' ...' if len(a['versions']) > 8 else ''))
    return '; '.join(out) or '(no range for this package name)'


def describe(rec):
    db = rec.get('database_specific') or {}
    scores = ', '.join(s.get('score', '') for s in rec.get('severity') or [])
    sev = ' '.join(x for x in (db.get('severity') or '', scores) if x) or 'not given'
    text = (rec.get('summary') or rec.get('details') or '').strip().splitlines()
    return (f"{rec['id']} (aliases {', '.join(rec.get('aliases') or []) or 'none'}); severity {sev}; "
            f"published {(rec.get('published') or '?')[:10]}"
            + (f"; WITHDRAWN {rec['withdrawn'][:10]}" if rec.get('withdrawn') else '')
            + f"; {text[0][:160] if text else '(no summary)'}")


def packages(inv, closure_path):
    npm = [tuple(line.strip().rsplit('@', 1)) for line in open(closure_path, encoding='utf-8') if line.strip()]
    npm.append(HYPOTHESIS)
    npm = [(n, v, [n]) for n, v in npm]
    swift = []
    for p in inv['packages']:
        m = re.match(r'^https://(github\.com/[^/]+/[^/]+?)(\.git)?/?$', p['url'])
        name = m.group(1) if m else p['url']
        swift.append((name, p['version'], swift_spellings(name)))
    written = {}
    for line in open('Scripts/tools/requirements.txt', encoding='utf-8'):
        line = line.split('#', 1)[0].strip()
        if '==' in line:
            written[norm_py(line.split('==')[0])] = line.split('==')[0]
    py = []
    for p in inv['python_tools']['packages'] + inv['python_tools'].get('unpinned', []):
        n = norm_py(p['name'])
        spellings = list(dict.fromkeys([written.get(n, p['name']), n, n.replace('-', '_')]))
        py.append((n, p['version'], spellings))
        # An unpinned installer has no one version: it is also asked at the version a freshly bootstrapped virtualenv
        # holds (review R2-01: Python 3.14.6's pip), and labelled so in the results.
        fresh = p.get('fresh_bootstrap_version')
        if fresh and fresh != p['version']:
            py.append((n, fresh, spellings))
            LABELS[(n, fresh)] = 'in a fresh virtualenv'
    return npm, swift, py


def actions_at_release(s, inv):
    print('\n## Workflow actions: the release each movable tag names today (GitHub tags API)')
    out = []
    for a in inv.get('ci_actions', []):
        repo, _, tag = a['uses'].partition('@')
        status, body = request(f'https://api.github.com/repos/{repo}/tags?per_page=100')
        s.save(f'tags-{repo}.json', body)
        if status != 200:
            s.fail(f'{repo}: tags API status {status}: {body[:200]!r}')
            continue
        tags = {t['name']: t['commit']['sha'] for t in json.loads(body)}
        sha = tags.get(tag)
        exact = sorted((n for n, c in tags.items() if c == sha and re.match(r'^v\d+\.\d+\.\d+$', n)),
                       key=lambda n: [int(x) for x in n[1:].split('.')])
        if not sha or not exact:
            s.fail(f'{repo}@{tag}: tag not found, or no vX.Y.Z release tag at its commit {sha}')
            continue
        print(f'{repo}@{tag} -> commit {sha} = release {exact[-1]}')
        out.append((repo, exact[-1].lstrip('v'), [repo]))
    return out


def search_group(s, eco, gh_eco, pkgs):
    controls = CONTROLS[eco]
    keys = {(n, v) for n, v, _ in pkgs}
    extra = [(n, v, sps) for n, v, _, sps in controls if (n, v) not in keys]
    spelled = {n: sps for n, _, sps in pkgs}
    print(f'\n## {eco}: {len(pkgs)} packages; positive controls: '
          + '; '.join(f'{n}@{v} (expects {cid})' for n, v, cid, _ in controls))
    # OSV at each exact version (and the controls). Its version results count only if every control is returned.
    at_version = s.osv_batch(eco, pkgs + extra, 'versions', True)
    usable = False
    if at_version is not None:
        usable = True
        for n, v, cid, _ in controls:
            if cid in at_version.get((n, v), set()):
                print(f'OSV control: {n}@{v} returned {cid}')
            else:
                usable = False
                print(f'OSV control: {n}@{v} did NOT return {cid}')
        if not usable:
            print('OSV version queries are not used for this ecosystem (a control was not returned; for GitHub Actions, '
                  'OSV evaluates no versions): each package must have no OSV advisory at any version')
        else:
            hit = {k: ids for k, ids in at_version.items() if ids and k in keys}
            print(f'OSV version queries: {len(pkgs)} packages; {len(hit)} with an advisory that affects the queried version')
            for (n, v), ids in sorted(hit.items()):
                for vid in sorted(ids):
                    rec = s.vuln(vid)
                    if rec:
                        label = f' ({LABELS[(n, v)]})' if (n, v) in LABELS else ''
                        print(f'  AFFECTS {n}@{v}{label}: {describe(rec)}')
                        print(f'      affected ranges: {ranges(rec, spelled[n])}')
    # OSV at any version: the advisories that exist for these packages (context, and the fallback above).
    any_version = s.osv_batch(eco, pkgs, 'any-version', False)
    if any_version is not None:
        listed = {k: ids for k, ids in any_version.items() if ids}
        print(f'OSV name queries (any version): {len(listed)} of {len(pkgs)} packages have advisories for some version')
        for (n, v), ids in sorted(listed.items()):
            for vid in sorted(ids):
                rec = s.vuln(vid)
                if not rec:
                    continue
                if not usable:
                    s.fail(f'OSV lists {vid} for {n} at some version and cannot evaluate {v}; judge it by hand')
                    verdict = 'NOT JUDGED (OSV cannot evaluate versions here)'
                elif vid in (at_version or {}).get((n, v), set()):
                    verdict = 'AFFECTS the pinned version' if (n, v) not in LABELS else f'AFFECTS {v}'
                else:
                    verdict = f'not {v} (outside the affected range)'
                print(f'  {n} ({LABELS.get((n, v), "pinned")} {v}): {describe(rec)}; {verdict}')
                print(f'      affected ranges: {ranges(rec, spelled[n])}')
        if not usable and not listed and at_version is not None:
            print(f'OSV: no advisory for any version of any of the {len(pkgs)} packages, so none affects the pinned versions')
    # GitHub Advisory Database at each exact version, every spelling. GitHub does not say which name@version matched,
    # so a control that shares a name with one of the packages (pyyaml; swift-crypto) is asked in a request of its own;
    # a control that is itself one of the packages (marmelroy/Zip 2.1.2) is asked with them.
    canon = {sp.lower(): n for n, _, sps in pkgs for sp in sps}
    alone = [c for c in controls if (c[0], c[1]) not in keys and any(sp.lower() in canon for sp in c[3])]
    together = [c for c in controls if c not in alone]
    for n, v, cid, sps in alone:
        advs = s.github(gh_eco, 'reviewed', [(n, v, sps)], label=f'-control-{n}@{v}')
        if advs is not None:
            ids = {a.get('ghsa_id') for a in advs}
            if cid in ids:
                print(f'GitHub control (reviewed, asked alone): {n}@{v} returned {cid}')
            else:
                s.fail(f'GitHub control (reviewed, asked alone): {n}@{v} did not return {cid}; got {sorted(ids)}')
    for kind in ('reviewed', 'malware'):
        entries = pkgs + ([(n, v, sps) for n, v, _, sps in together if (n, v) not in keys] if kind == 'reviewed' else [])
        advs = s.github(gh_eco, kind, entries)
        if advs is None:
            continue
        if kind == 'reviewed':
            ids = {a.get('ghsa_id') for a in advs}
            for n, v, cid, _ in together:
                if cid in ids:
                    print(f'GitHub control (reviewed): {n}@{v} returned {cid}')
                else:
                    s.fail(f'GitHub control (reviewed): {n}@{v} did not return {cid}; got {sorted(ids)}')
        mine = []
        for a in advs:
            vulns = [x for x in a.get('vulnerabilities') or []
                     if ((x.get('package') or {}).get('name') or '').lower() in canon]
            if vulns:
                mine.append((a, vulns))
        print(f'GitHub advisories (ecosystem {gh_eco}, type {kind}, {len(entries)} packages in every spelling): '
              f'{len(advs)} returned; {len(mine)} for these packages')
        for a, vulns in mine:
            where = '; '.join(f"{(x.get('package') or {}).get('name')} {x.get('vulnerable_version_range')} -> "
                              f"{x.get('first_patched_version') or 'no patched version'}" for x in vulns)
            print(f"  AFFECTS: {a.get('ghsa_id')} ({a.get('cve_id') or 'no CVE'}), {a.get('severity')}: "
                  f"{(a.get('summary') or '')[:160]}; {where}")


# Review R3-02: two more sources for every package. The published security advisories of each package repository
# (GitHub's API), which the Advisory Database lists only once GitHub reviews them: in October 2026 three of Apple's were in
# neither database that the version-exact search reads (GHSA-xfxg-9975-pc2j, GHSA-qcc5-f287-vgmq, GHSA-8q93-f6xh-4f6f).
# And NVD's keyword search, for CVEs filed against a project by name. The forks' upstream repositories are read too.
UPSTREAMS = dict([('readium/ZIPFoundation', 'weichsel/ZIPFoundation'), ('readium/Fuzi', 'cezheng/Fuzi'),
                  ('readium/GCDWebServer', 'swisspol/GCDWebServer')])
NVD_PACKAGE_KEYWORDS = ['readium', 'ZIPFoundation', 'Fuzi', 'SwiftSoup', 'CryptoSwift', 'DifferenceKit', 'marmelroy',
                        'Zip Swift', 'GCDWebServer', 'SQLite.swift', 'GRDB', 'pointfreeco', 'swift-snapshot-testing',
                        'swift-custom-dump', 'swift-issue-reporting', 'swift-syntax', 'swift-nio', 'SwiftNIO',
                        'swift-nio-ssl', 'swift-crypto', 'swift-certificates', 'swift-asn1', 'Swift ASN.1',
                        'swift-atomics', 'swift-collections', 'swift-system']
# Verdicts for every advisory those two sources list, against the pinned versions; a verdict that starts with APPLIES
# means the pinned version is affected. An advisory without a verdict fails the search until someone judges it.
JUDGED = dict()
JUDGED['GHSA-qcc5-f287-vgmq'] = 'not swift-nio 2.103.0: 2.100.0 and earlier (CVE-2026-43678, a WebSocket frame length trap); fixed in 2.101.0, which the pin follows; NIOWebSocket is not linked'
JUDGED['CVE-2026-43678'] = JUDGED['GHSA-qcc5-f287-vgmq']
JUDGED['GHSA-r3rc-9hpw-54v9'] = 'not swift-nio 2.103.0: before 2.100.0 (CVE-2026-43671)'
JUDGED['GHSA-rj37-6j9x-74q6'] = 'not swift-nio 2.103.0: before 2.100.0 (CVE-2026-28980)'
JUDGED['GHSA-cq87-8r7h-962v'] = 'not swift-nio 2.103.0: before 2.100.0 (CVE-2026-28970)'
JUDGED['GHSA-7fj7-39wj-c64f'] = 'not swift-nio 2.103.0: before 2.41.2, 2.39.1 and 2.29.1 (CVE-2022-3215)'
JUDGED['GHSA-mgc4-wqv7-4pxm'] = 'not swift-nio 2.103.0: 1.0.0 to 1.14.1 and 2.0.0 to 2.13.0 (the repository record names CVE-2019-15605, the Node.js CVE for the same flaw)'
JUDGED['CVE-2018-4281'] = 'not swift-nio 2.103.0: SwiftNIO before 1.8.0'
JUDGED['GHSA-xfxg-9975-pc2j'] = 'not swift-nio-ssl 2.37.5: 2.18.0 to 2.37.1 (CVE-2026-43820, an out-of-bounds read through a SAN that is not a string); fixed in 2.37.2, which the pin follows'
JUDGED['CVE-2026-43820'] = JUDGED['GHSA-xfxg-9975-pc2j']
JUDGED['GHSA-9556-94c5-c3j8'] = 'not swift-nio-ssl 2.37.5: 2.0.0 to 2.4.0 (CVE-2019-8849)'
JUDGED['CVE-2019-8849'] = JUDGED['GHSA-9556-94c5-c3j8']
JUDGED['GHSA-8q93-f6xh-4f6f'] = 'not swift-crypto 5.0.0: 3.2.0 to 4.5.0 (CVE-2026-43823, a double free when an RSA public key fails to decode); the fix, commit 47d3869a, is in 5.0.0'
JUDGED['CVE-2026-43823'] = JUDGED['GHSA-8q93-f6xh-4f6f']
JUDGED['GHSA-9m44-rr2w-ppp7'] = 'not swift-crypto 5.0.0: 4.0.0 to 4.3.0 (CVE-2026-28815)'
JUDGED['CVE-2026-28815'] = JUDGED['GHSA-9m44-rr2w-ppp7']
JUDGED['GHSA-w8xv-rwgf-4fwh'] = 'not swift-asn1 1.7.3: before 1.3.0, fixed in 1.3.1 (CVE-2025-0343)'
JUDGED['CVE-2025-0343'] = JUDGED['GHSA-w8xv-rwgf-4fwh']
JUDGED['CVE-2023-24720'] = 'not readium/swift-toolkit: readium-js 0.32.0, a different project'
JUDGED['CVE-2023-39138'] = 'not weichsel/ZIPFoundation 0.9.20 or the readium fork 3.0.1: ZIPFoundation 0.9.16, fixed in 0.9.18, which both contain'
JUDGED['CVE-2023-39135'] = 'APPLIES to marmelroy/Zip 2.1.2: path traversal in Zip.unzipFile, which no release fixes; linked but never called (ADR-0014 section 5)'
JUDGED['CVE-2015-4641'] = 'not marmelroy/Zip: the SwiftKey keyboard on Samsung phones'
JUDGED['CVE-2019-14924'] = 'not readium/GCDWebServer 4.0.1 as used: GCDWebUploader before 3.5.3, outside the SwiftPM product and not linked; the fix is in the pinned history'
JUDGED['CVE-2008-0942'] = 'not GRDB: Aeries Browser Interface (Eagle Software)'
JUDGED['CVE-2008-1549'] = 'not GRDB: Aeries Browser Interface (Eagle Software)'
for cve in ('CVE-2022-24666', 'CVE-2022-24667', 'CVE-2022-24668', 'CVE-2022-0618', 'CVE-2026-28898', 'CVE-2026-64785'):
    JUDGED[cve] = 'not a pinned package: swift-nio-http2'
JUDGED['CVE-2026-43798'] = 'not a pinned package: swift-nio-ssh'
JUDGED['CVE-2020-9840'] = 'not a pinned package: SwiftNIO Extras'
JUDGED['CVE-2022-3252'] = 'not a pinned package: SwiftNIO Extras'


def version_key(version):
    parts = [int(x) for x in re.findall(r'\d+', str(version).split('-')[0])][:4]
    return tuple(parts + [0] * (4 - len(parts)))


def in_range(version, text):
    """Whether version is inside a repository advisory's vulnerable_version_range, or None for a form this script does
    not read. Forms read: '< 2.100.0', '<= 2.100.0', '>= 3.2.0, <= 4.5.0' (all must hold); '4.0.0 - 4.3.0' and
    '1.0.0-1.14.1, 2.0.0-2.13.0' (any interval); '2.0.0<=2.4.0' (an interval)."""
    parts = [p.strip() for p in (text or '').split(',') if p.strip()]
    if not parts:
        return None
    v = version_key(version)
    if all(re.match(r'^(<=|>=|<|>|=)\s*\d', p) for p in parts):
        held = []
        for p in parts:
            m = re.match(r'^(<=|>=|<|>|=)\s*(\S+)$', p)
            if not m:
                return None
            b = version_key(m.group(2))
            held.append(dict([('<', v < b), ('<=', v <= b), ('>', v > b), ('>=', v >= b), ('=', v == b)])[m.group(1)])
        return all(held)
    held = []
    for p in parts:
        m = re.match(r'^(\d[\w.]*)\s*(?:-|<=)\s*(\d[\w.]*)$', p)
        if not m:
            return None
        held.append(version_key(m.group(1)) <= v <= version_key(m.group(2)))
    return any(held)



def repository_advisories(s, inv):
    print('\n## Published security advisories of each package repository, and of the upstreams of the forks (GitHub API)')
    status, body = request('https://api.github.com/repos/apple/swift-nio/security-advisories?per_page=100', accept='application/vnd.github+json')
    s.save('repository-control-apple_swift-nio.json', body)
    if status != 200 or not any(a.get('ghsa_id') == 'GHSA-r3rc-9hpw-54v9' for a in json.loads(body)):
        s.fail('control: the repository advisories of apple/swift-nio do not list GHSA-r3rc-9hpw-54v9 (status %s)' % status)
    else:
        print('control: apple/swift-nio lists GHSA-r3rc-9hpw-54v9')
    for p in inv['packages']:
        m = re.match(r'^https://github\.com/([^/]+/[^/]+?)(\.git)?/?$', p['url'])
        if not m:
            s.fail('%s: not a GitHub repository, so its repository advisories cannot be read' % p['name'])
            continue
        own = m.group(1)
        for repo in [own] + ([UPSTREAMS[own]] if own in UPSTREAMS else []):
            status, body = request('https://api.github.com/repos/%s/security-advisories?per_page=100' % repo, accept='application/vnd.github+json')
            s.save('repository-%s.json' % repo.replace('/', '_'), body)
            if status != 200:
                s.fail('%s: repository advisories: status %s: %r' % (repo, status, body[:200]))
                continue
            advs = json.loads(body)
            print('%s (%s %s%s): %d published' % (repo, p['name'], p['version'], '' if repo == own else ', its upstream', len(advs)))
            for a in advs:
                vulns = a.get('vulnerabilities') or []
                ranges = '; '.join('%s: %s, patched %s' % ((x.get('package') or dict()).get('name'), x.get('vulnerable_version_range'),
                                                           x.get('patched_versions')) for x in vulns)
                held = [in_range(p['version'], x.get('vulnerable_version_range')) for x in vulns]
                computed = 'not parsed' if None in held or not held else ('affects ' if any(held) else 'not ') + p['version']
                print('  %s (%s, %s, published %s): %s; range check: %s' % (a.get('ghsa_id'), a.get('cve_id') or 'no CVE', a.get('severity'),
                                                                        (a.get('published_at') or '?')[:10], ranges, computed))
                verdict = JUDGED.get(a.get('ghsa_id'))
                if verdict is None:
                    s.fail('%s lists %s, which has no recorded verdict: judge it against %s %s and record it in JUDGED and advisories.md'
                           % (repo, a.get('ghsa_id'), p['name'], p['version']))
                    continue
                print('      verdict: ' + verdict)
                if repo == own and computed != 'not parsed' and computed.startswith('affects') != verdict.startswith('APPLIES'):
                    s.fail('%s: the recorded verdict disagrees with the range check (%s)' % (a.get('ghsa_id'), computed))



def nvd_keywords(s):
    print('\n## NVD keyword search for each package (paced to 5 requests in 30 seconds, as NVD asks)')
    last = [0.0]

    def query(keyword):
        wait = 6.5 - (time.time() - last[0])
        if wait > 0:
            time.sleep(wait)
        url = 'https://services.nvd.nist.gov/rest/json/cves/2.0?' + urllib.parse.urlencode(dict(keywordSearch=keyword, resultsPerPage=2000))
        status, body = request(url)
        last[0] = time.time()
        s.save('nvd-%s.json' % keyword, body)
        if status != 200:
            s.fail('NVD %r: status %s: %r' % (keyword, status, body[:200]))
            return None
        d = json.loads(body)
        rows = [(v['cve']['id'], ([x['value'] for x in v['cve'].get('descriptions') or [] if x.get('lang') == 'en'] or [''])[0])
                for v in d.get('vulnerabilities') or []]
        if d.get('totalResults', 0) > len(rows):
            s.fail('NVD %r: %s results, more than one page' % (keyword, d.get('totalResults')))
        return rows

    rows = query('Zip Swift')
    if rows is not None and any(c == 'CVE-2023-39135' for c, _ in rows):
        print('control: the keyword Zip Swift lists CVE-2023-39135')
    elif rows is not None:
        s.fail('control: the NVD keyword Zip Swift does not list CVE-2023-39135')
    for keyword in NVD_PACKAGE_KEYWORDS:
        rows = query(keyword)
        if rows is None:
            continue
        print('NVD keyword %r: %d CVEs' % (keyword, len(rows)))
        for cve, text in rows:
            if cve in JUDGED:
                print('  %s: %s' % (cve, JUDGED[cve]))
            else:
                s.fail('NVD keyword %r lists %s, which has no recorded verdict: %s' % (keyword, cve, text[:160].replace('\n', ' ')))


def main():
    closure_path, out = sys.argv[1], sys.argv[2]
    if os.path.exists(out):
        sys.exit(f'refusing: {out} already exists; give a new directory')
    os.makedirs(out)
    s = Search(out)
    inv = json.load(open('Docs/Licenses/inventory.json', encoding='utf-8'))
    print(f'advisory search {time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}; raw responses in {out}')
    print('GitHub API: ' + ('authenticated with the gh CLI token (not shown)' if token() else 'unauthenticated (60 requests an hour, shared by every job on this host)'))
    npm, swift, py = packages(inv, closure_path)
    status, body = request(f'https://registry.npmjs.org/{HYPOTHESIS[0]}/{HYPOTHESIS[1]}')
    s.save('npm-registry-hypothesis.json', body)
    meta = json.loads(body) if status == 200 else {}
    print(f'npm registry {HYPOTHESIS[0]}@{HYPOTHESIS[1]}: status {status}'
          + (f" (published package {meta.get('name')} {meta.get('version')}, repository "
             f"{(meta.get('repository') or {}).get('url')})" if status == 200 else ' (version not published on npm)'))
    # The Hypothesis client's own published repository advisories (one could exist without an npm package mapping).
    status, body = request('https://api.github.com/repos/hypothesis/client/security-advisories?per_page=100',
                           accept='application/vnd.github+json')
    s.save('github-repository-advisories-hypothesis-client.json', body)
    if status != 200:
        s.fail(f'GitHub repository advisories (hypothesis/client): status {status}: {body[:200]!r}')
    else:
        advs = json.loads(body)
        print(f'GitHub repository advisories of hypothesis/client: status {status}; {len(advs)} published'
              + ''.join(f"\n  {a.get('ghsa_id')} ({a.get('cve_id') or 'no CVE'}), {a.get('severity')}: {a.get('summary')}; "
                        f"{[(v.get('package') or {}).get('name') for v in a.get('vulnerabilities') or []]} "
                        f"{[v.get('vulnerable_version_range') for v in a.get('vulnerabilities') or []]}" for a in advs))
    actions = actions_at_release(s, inv)
    for eco, gh_eco, pkgs in (('npm', 'npm', npm), ('SwiftURL', 'swift', swift), ('PyPI', 'pip', py),
                              ('GitHub Actions', 'actions', actions)):
        search_group(s, eco, gh_eco, pkgs)
    repository_advisories(s, inv)
    nvd_keywords(s)
    print(f'\nfinished {time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}; failures: {s.failures}')
    return 1 if s.failures else 0


if __name__ == '__main__':
    sys.exit(main())
