"""ADR-0014 evidence: security advisory searches for the third-party code that pinned packages vendor (review R3-02),
which the per-package searches in advisories-search.py do not reach by a package's own name:

  llhttp in swift-nio 2.103.0 (Sources/CNIOLLHTTP): at the version its header's LLHTTP_VERSION_ macros give
  BoringSSL in swift-nio-ssl 2.37.5 and swift-crypto 5.0.0: at the revisions their hash.txt files record
  BigInt in CryptoSwift 1.10.0 (Sources/CryptoSwift/CS_BigInt), from attaswift/BigInt: at the upstream releases closest
      to the copy, found here by comparing every file with each 5.x and 6.x release
  cpp_magic.h from uSHET in swift-nio, fiat-crypto in both BoringSSL copies, Minizip and the Info-ZIP decryption code
      in marmelroy/Zip, and ReadiumCSS in readium/swift-toolkit: by keyword and repository

  python3 -I vendored-advisories.py <swift-nio> <swift-nio-ssl> <swift-crypto> <CryptoSwift> <new output dir>
  (package checkouts at their pinned revisions, as commands/resolve-locks.sh leaves them)

Sources, each with a positive control, so that an empty result means "none listed", not "the query matched nothing":
  OSV         POST https://api.osv.dev/v1/querybatch: by package and version where the component has a registry
              identity (npm llhttp; SwiftURL github.com/attaswift/BigInt in every spelling), at the version and at any
              version; and by commit for BoringSSL, which OSV indexes from OSS-Fuzz as git ranges. Controls: lodash
              4.17.15 (npm) and marmelroy/Zip 2.1.2 (SwiftURL) must return their advisories, and the commit that
              OSV-2023-41 names as introducing a BoringSSL bug must return OSV-2023-41.
  GitHub      the Advisory Database API at those versions (reviewed advisories; the same controls), and the published
              security advisories of nodejs/llhttp, attaswift/BigInt, 18sg/uSHET, mit-plv/fiat-crypto and
              readium/readium-css (control: apple/swift-nio must list GHSA-r3rc-9hpw-54v9)
  GitHub web  https://github.com/advisories?query=<keyword>, every page (reviewed and unreviewed advisories), for
              WEB_KEYWORDS (control: swift-nio must list three of its known advisories)
  NVD         https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=<keyword> for NVD_KEYWORDS (control:
              "Zip Swift" must list CVE-2023-39135), at most 5 requests in 30 seconds, as NVD asks
Every advisory that a keyword or repository search lists must have a verdict in JUDGED below, made against the
component's version or revision; one without fails the search until someone judges it and records it here and in
advisories.md. A query that fails is a failure (exit status 1), never "none". Only public names, versions and commits
are sent, nothing from this repository. Responses are saved under the output directory as data and never run.
GitHub API requests use the gh CLI's token when it has one (the unauthenticated limit, 60 an hour, is shared by every
job on this host); the token is never printed or saved.
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

UA = 'sylvia-dependency-inventory (ADR-0014 advisory search)'
API = 'https://api.github.com'
GHSA = re.compile(r'GHSA(?:-[0-9a-z]{4}){3}')
WEB_KEYWORDS = ['llhttp', 'boringssl', 'attaswift', 'BigInt swift', 'minizip', 'uSHET', 'cpp_magic', '18sg', 'fiat-crypto',
                'readium-css']
NVD_KEYWORDS = ['llhttp', 'boringssl', 'attaswift', 'BigInt Swift', 'minizip', 'Info-ZIP', 'uSHET', 'cpp_magic',
                'fiat-crypto', 'readium-css']
REPOSITORIES = ['nodejs/llhttp', 'attaswift/BigInt', '18sg/uSHET', 'mit-plv/fiat-crypto', 'readium/readium-css']
BORINGSSL_CONTROL = ('33b569282ca124c81d9ba74df696a013cb9a80ae', 'OSV-2023-41')

# Verdicts for every advisory the keyword and repository searches list (13 October 2026 and later), made against the
# vendored version or revision: llhttp 9.3.0; BoringSSL 817ab07e (28 January 2025) and 0226f304 (7 September 2025);
# BigInt as vendored by CryptoSwift; Minizip 1.1 with Moinvaziri's changes and Info-ZIP's decryption functions in its
# crypt.h (decrypt_byte, update_keys, init_keys, crypthead). A verdict starting with APPLIES means the code is present.
JUDGED = dict()
LL = 'llhttp 9.3.0 is outside the range: '
JUDGED['GHSA-5689-v88g-g6rv'] = LL + 'llhttp before 6.0.7 (and 2.1.5), CVE-2022-32213'
JUDGED['CVE-2022-32213'] = JUDGED['GHSA-5689-v88g-g6rv']
JUDGED['GHSA-q5vx-44v4-gch4'] = LL + 'llhttp before 6.0.7 (and 2.1.5), CVE-2022-32214'
JUDGED['CVE-2022-32214'] = JUDGED['GHSA-q5vx-44v4-gch4']
JUDGED['GHSA-5492-mr68-4m2h'] = LL + 'the llhttp in Node.js before 14.20.1, 16.17.1 and 18.9.1 (July 2022 releases, llhttp 6.0.x), CVE-2022-32215'
JUDGED['CVE-2022-32215'] = JUDGED['GHSA-5492-mr68-4m2h']
JUDGED['GHSA-rc2m-q589-vpqx'] = LL + 'the llhttp in Node.js 18.7.0 (2022), CVE-2022-35256'
JUDGED['CVE-2022-35256'] = JUDGED['GHSA-rc2m-q589-vpqx']
JUDGED['GHSA-cggh-pq45-6h9x'] = LL + 'llhttp before 8.1.1, CVE-2023-30589'
JUDGED['CVE-2023-30589'] = JUDGED['GHSA-cggh-pq45-6h9x']
JUDGED['GHSA-mhxq-vjjq-pcvf'] = LL + 'llhttp before 2.1.4 and 6.0.6, CVE-2021-22959'
JUDGED['CVE-2021-22959'] = JUDGED['GHSA-mhxq-vjjq-pcvf']
JUDGED['GHSA-px8h-5r3g-hj68'] = LL + 'llhttp before 2.1.4 and 6.0.6, CVE-2021-22960'
JUDGED['CVE-2021-22960'] = JUDGED['GHSA-px8h-5r3g-hj68']
JUDGED['GHSA-hchw-qwx7-4w4c'] = LL + 'Node.js 20 before its upgrade to llhttp 9, which fixed it (CVE-2025-23167)'
JUDGED['CVE-2025-23167'] = JUDGED['GHSA-hchw-qwx7-4w4c']
JUDGED['GHSA-45c4-8wx5-qw6w'] = LL + 'aiohttp 3.8.4 and earlier, which bundle llhttp 6.0.6 (CVE-2023-30589, fixed in llhttp 8.1.1); CVE-2023-37276'
JUDGED['CVE-2023-37276'] = JUDGED['GHSA-45c4-8wx5-qw6w']
JUDGED['GHSA-pjjw-qhg8-p2p9'] = LL + 'aiohttp before 3.8.6, which bundled llhttp 8.1.1; the advisory says llhttp 9 resolves it'
JUDGED['GHSA-63hf-3vf5-4wqf'] = 'not an llhttp advisory: aiohttp 3.13.3 and earlier (CVE-2026-34520); its patch (aio-libs/aiohttp 9370b97) changes aiohttp\'s own header validation, and no llhttp version is listed'
JUDGED['GHSA-8qpw-xqxj-h4r2'] = 'not llhttp: aiohttp\'s pure-Python HTTP parser (CVE-2024-23829)'
JUDGED['GHSA-gfw2-4jvh-wgfg'] = 'not llhttp: aiohttp\'s pure-Python HTTP parser (CVE-2023-47627)'
JUDGED['GHSA-f52w-8j3h-j724'] = 'not llhttp: Traefik (Go), CVE-2026-88009'
JUDGED['CVE-2026-69244'] = 'not an llhttp advisory: aiohttp before 3.14.3 misused an llhttp error-position pointer in its own aiohttp/_http_parser.pyx'
BS = 'not BoringSSL at 817ab07e or 0226f304: '
JUDGED['GHSA-r5xm-3hfm-w636'] = BS + 'Conscrypt and BoringSSL in Android 6.x and 7.0 before 2016-11-01 (CVE-2016-6709)'
JUDGED['CVE-2016-6709'] = JUDGED['GHSA-r5xm-3hfm-w636']
JUDGED['GHSA-7gr4-mrjx-cjx9'] = BS + 'LibreSSL 2.7.0 (CVE-2018-8970); BoringSSL is named only for its documentation'
JUDGED['CVE-2018-8970'] = JUDGED['GHSA-7gr4-mrjx-cjx9']
JUDGED['GHSA-mwrj-3qqh-xprh'] = BS + 'BoringSSL through 2018-06-14 (CVE-2018-12440); both revisions are from 2025'
JUDGED['CVE-2018-12440'] = JUDGED['GHSA-mwrj-3qqh-xprh']
JUDGED['GHSA-c95q-mpxc-wgf9'] = BS + 'BoringSSL SPAKE2 in Chrome before 63.0.3239.84, 2017 (CVE-2017-15423); both revisions are from 2025'
JUDGED['CVE-2017-15423'] = JUDGED['GHSA-c95q-mpxc-wgf9']
JUDGED['GHSA-g762-h86w-8749'] = BS + 'netty-incubator-codec-ohttp, Java code that calls BoringSSL (CVE-2024-36121)'
JUDGED['CVE-2024-36121'] = JUDGED['GHSA-g762-h86w-8749']
JUDGED['GHSA-32hf-8jw3-v4qq'] = BS + 'netty-incubator-codec-ohttp, Java code that calls BoringSSL (CVE-2026-48040)'
JUDGED['CVE-2026-48040'] = JUDGED['GHSA-32hf-8jw3-v4qq']
JUDGED['GHSA-2mc4-j865-9q4r'] = BS + 'netty-incubator-codec-ohttp, Java code that calls BoringSSL (CVE-2026-61798)'
JUDGED['GHSA-2mjx-qc3c-rqvc'] = BS + 'rustls (Rust)'
JUDGED['GHSA-g6cj-pr64-35w5'] = BS + 'pyca/cryptography (CVE-2026-69247)'
JUDGED['CVE-2026-69247'] = JUDGED['GHSA-g6cj-pr64-35w5']
JUDGED['CVE-2026-43823'] = BS + 'swift-crypto 3.2.0 to 4.5.0 (GHSA-8q93-f6xh-4f6f), a double free in its own Swift code; the pinned swift-crypto 5.0.0 contains the fix, commit 47d3869a'
JUDGED['CVE-2026-100665'] = BS + 'Netty QUIC (Java), CVE-2026-100665'
MZ = 'the Minizip in marmelroy/Zip 2.1.2: '
JUDGED['GHSA-jx5r-f949-99mv'] = 'not in ' + MZ + 'miniunz.c, the miniunzip program, which it does not contain (CVE-2014-9485)'
JUDGED['CVE-2014-9485'] = JUDGED['GHSA-jx5r-f949-99mv']
JUDGED['CVE-2023-45853'] = 'APPLIES to ' + MZ + 'its zip.c has the zipOpenNewFileInZip4_64 pattern, in a write path that Readium never calls (recorded in advisories.md)'
JUDGED['GHSA-mq29-j5xf-cjwr'] = JUDGED['CVE-2023-45853'] + '; this record is for pyminizip'
JUDGED['GHSA-q5fm-55c2-v6j9'] = JUDGED['CVE-2023-45853'] + '; this record is for Fiona'
JUDGED['GHSA-4jvx-jmjp-xmq4'] = 'not ' + MZ + 'minizip-ng 4.0.2, a different project (CVE-2023-48106)'
JUDGED['CVE-2023-48106'] = JUDGED['GHSA-4jvx-jmjp-xmq4']
JUDGED['GHSA-j5rw-m6xg-866q'] = 'not ' + MZ + 'minizip-ng 4.0.2, a different project (CVE-2023-48107)'
JUDGED['CVE-2023-48107'] = JUDGED['GHSA-j5rw-m6xg-866q']
IZ = 'not the Info-ZIP decryption functions in Minizip\'s crypt.h (decrypt_byte, update_keys, init_keys, crypthead): '
for cve, what in [('CVE-2001-1268', 'UnZip 5.42 extraction of .. paths'), ('CVE-2001-1269', 'UnZip 5.42 extraction of absolute paths'),
                  ('CVE-2004-1010', 'Zip 2.3 recursive compression'), ('CVE-2015-1315', 'UnZip 6.10b charset conversion in unix/unix.c'),
                  ('CVE-2015-7696', 'UnZip 6.0 extra-field handling when extracting password-protected archives'),
                  ('CVE-2015-7697', 'UnZip 6.0 bzip2 handling'), ('CVE-2014-9913', 'UnZip 6.0 list.c'),
                  ('CVE-2016-9844', 'UnZip 6.0 zipinfo.c'), ('CVE-2018-1000031', 'UnZip 6.10c22 program code'),
                  ('CVE-2018-1000032', 'UnZip 6.10c22 program code'), ('CVE-2018-1000033', 'UnZip 6.10c22 program code'),
                  ('CVE-2018-1000034', 'UnZip 6.10c22 program code'),
                  ('CVE-2018-1000035', 'UnZip 6.00 password handling (its password buffer); crypt.h\'s functions copy no password'),
                  ('CVE-2018-13410', 'Zip 3.0 -T and -TT options'), ('CVE-2018-18384', 'UnZip 6.0 list.c'),
                  ('CVE-2019-13232', 'UnZip 6.0 overlapping entries'), ('CVE-2014-8139', 'UnZip 6.0 CRC32 verification with -t'),
                  ('CVE-2014-8140', 'UnZip 6.0 test_compr_eb'), ('CVE-2014-8141', 'UnZip 6.0 getZip64Data'),
                  ('CVE-2026-48961', 'Perl IO::Compress zipdetails'), ('CVE-2026-87794', 'bestzip (npm), which runs the zip program')]:
    JUDGED[cve] = IZ + what

_TOKEN = []


def token():
    """The gh CLI's token, when it has one; never printed or saved."""
    if not _TOKEN:
        try:
            r = subprocess.run(['gh', 'auth', 'token'], capture_output=True, text=True, timeout=30)
            _TOKEN.append(r.stdout.strip() if r.returncode == 0 else '')
        except (OSError, subprocess.SubprocessError):
            _TOKEN.append('')
    return _TOKEN[0]


def request(url, body=None, accept='application/json'):
    headers = dict(Accept=accept)
    headers['User-Agent'] = UA
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    if url.startswith(API + '/') and token():
        headers['Authorization'] = 'Bearer ' + token()
    req = urllib.request.Request(url, data=data, headers=headers, method='POST' if data is not None else 'GET')
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                if not r.geturl().startswith('https://'):
                    raise RuntimeError('redirected off HTTPS: ' + r.geturl())
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            if e.code in (403, 429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(20 * (attempt + 1))  # rate limited or busy
                continue
            return e.code, e.read()
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < 3:
                time.sleep(10 * (attempt + 1))
                continue
            raise RuntimeError('%s: %s' % (url, e))
    raise RuntimeError(url + ': no response')


class Search:
    def __init__(self, out):
        self.out = out
        self.failures = 0
        self.nvd_last = 0.0

    def fail(self, text):
        self.failures += 1
        print('FAIL ' + text)

    def save(self, name, payload):
        with open(os.path.join(self.out, re.sub(r'[^A-Za-z0-9._@-]+', '_', name)), 'wb') as f:
            f.write(payload)

    def get_json(self, url, name, body=None, accept='application/json'):
        status, payload = request(url, body, accept)
        self.save(name, payload)
        if status != 200:
            self.fail('%s: status %s: %r' % (url, status, payload[:200]))
            return None
        return json.loads(payload)

    def web(self, keyword):
        """The advisory ids that the Advisory Database's keyword search lists, over every page; None on failure."""
        ids, page = [], 1
        while True:
            url = 'https://github.com/advisories?' + urllib.parse.urlencode(dict(query=keyword, page=page))
            status, payload = request(url, accept='text/html')
            self.save('web-%s-page%d.html' % (keyword, page), payload)
            text = payload.decode('utf-8', 'replace')
            if status != 200:
                self.fail('advisory keyword search %r, page %d: status %s' % (keyword, page, status))
                return None
            found = sorted(set(GHSA.findall(text)))
            if not found and 'No results matched your search' not in text:
                self.fail('advisory keyword search %r, page %d: lists nothing and does not say so (an error page?)' % (keyword, page))
                return None
            ids += [x for x in found if x not in ids]
            if 'rel="next"' not in text or page >= 20:
                return ids
            page += 1

    def nvd(self, keyword):
        """[(CVE id, description)] that NVD's keyword search lists; None on failure. Paced to 5 requests in 30 s."""
        wait = 6.5 - (time.time() - self.nvd_last)
        if wait > 0:
            time.sleep(wait)
        url = 'https://services.nvd.nist.gov/rest/json/cves/2.0?' + urllib.parse.urlencode(dict(keywordSearch=keyword, resultsPerPage=2000))
        d = self.get_json(url, 'nvd-%s.json' % keyword)
        self.nvd_last = time.time()
        if d is None:
            return None
        rows = []
        for v in d.get('vulnerabilities') or []:
            c = v['cve']
            text = [x['value'] for x in c.get('descriptions') or [] if x.get('lang') == 'en']
            rows.append((c['id'], (text[0] if text else '').replace('\n', ' ')))
        if d.get('totalResults', 0) > len(rows):
            self.fail('NVD %r: %s results, more than one page' % (keyword, d.get('totalResults')))
        return rows

    def osv_batch(self, queries, name):
        """[advisory ids per query] from OSV's batch query; None on failure."""
        d = self.get_json('https://api.osv.dev/v1/querybatch', 'osv-%s.json' % name, body=dict(queries=queries))
        if d is None:
            return None
        results = d.get('results') or []
        if len(results) != len(queries):
            self.fail('OSV %s: %d results for %d queries' % (name, len(results), len(queries)))
            return None
        for r in results:
            if r.get('next_page_token'):
                self.fail('OSV %s: a result has more than one page' % name)
        return [[v['id'] for v in r.get('vulns') or []] for r in results]

    def affects(self, ecosystem, specs, name):
        """The reviewed advisories (records) whose range holds any name@version in specs; None on failure."""
        url = API + '/advisories?' + urllib.parse.urlencode(dict(ecosystem=ecosystem, type='reviewed', affects=','.join(specs), per_page=100))
        d = self.get_json(url, 'affects-%s.json' % name, accept='application/vnd.github+json')
        return d

    def repository(self, repo):
        """The published security advisories of a repository; None on failure."""
        return self.get_json(API + '/repos/%s/security-advisories?per_page=100' % repo,
                             'repository-%s.json' % repo.replace('/', '_'), accept='application/vnd.github+json')

    def judge(self, source, ids):
        """Print each listed advisory with its recorded verdict; one without a verdict fails."""
        for i in ids:
            if i in JUDGED:
                print('  %s: %s' % (i, JUDGED[i]))
            else:
                self.fail('%s lists %s, which has no recorded verdict: judge it against the vendored version or revision, then record it in JUDGED and in advisories.md' % (source, i))


def llhttp_version(nio):
    text = open(os.path.join(nio, 'Sources/CNIOLLHTTP/include/c_nio_llhttp.h'), encoding='utf-8').read()
    found = [re.search(r'#define LLHTTP_VERSION_%s (\d+)' % k, text) for k in ('MAJOR', 'MINOR', 'PATCH')]
    if not all(found):
        sys.exit('cannot read the llhttp version from ' + nio)
    return '.'.join(m.group(1) for m in found)


def boringssl_revision(package, target):
    text = open(os.path.join(package, 'Sources', target, 'hash.txt'), encoding='utf-8').read()
    m = re.search(r'at revision ([0-9a-f]{40})', text)
    if not m:
        sys.exit('cannot read the BoringSSL revision from %s/Sources/%s/hash.txt' % (package, target))
    return m.group(1)


def normalized(text):
    """A Swift file's lines without its header comment, blank lines, indentation and the changes CryptoSwift made in
    copying BigInt: the `extension CS {` wrapper and the CS. prefix on BigInt and BigUInt."""
    lines, body = [], False
    for line in text.splitlines():
        s = line.strip()
        if not body:
            if s.startswith('//') or not s:
                continue
            body = True
        if not s or s == 'extension CS {':
            continue
        s = s.replace('CS.BigUInt', 'BigUInt').replace('CS.BigInt', 'BigInt')
        lines.append(re.sub(r'\s+', ' ', s))
    return lines


def bigint_releases(s, cryptoswift):
    """Compare CryptoSwift's CS_BigInt files with every 5.x and 6.x release of attaswift/BigInt, print how close each
    is, and return the releases' versions (every one is searched, since none matches the copy exactly)."""
    local_dir = os.path.join(cryptoswift, 'Sources/CryptoSwift/CS_BigInt')
    names = sorted(n for n in os.listdir(local_dir) if n.endswith('.swift') and n != 'CS.swift')
    local = dict((n, normalized(open(os.path.join(local_dir, n), encoding='utf-8').read())) for n in names)
    tags = s.get_json(API + '/repos/attaswift/BigInt/tags?per_page=100', 'bigint-tags.json', accept='application/vnd.github+json') or []
    releases = sorted((t['name'] for t in tags if re.match(r'^v[56]\.\d+\.\d+$', t['name'])),
                      key=lambda n: [int(x) for x in n[1:].split('.')])
    print('CryptoSwift 1.10.0 vendors %d BigInt files (Sources/CryptoSwift/CS_BigInt besides CS.swift); each compared with '
          'the same file in every attaswift/BigInt 5.x and 6.x release, ignoring blank lines, indentation, header '
          'comments and the CS wrapper and CS. prefix that CryptoSwift adds:' % len(names))
    text = 'Docs/Licenses/texts/krzyzanowskim__cryptoswift/external__attaswift-BigInt-v5.3.0__LICENSE.md'
    committed = hashlib.sha256(open(text, 'rb').read()).hexdigest()
    best = None
    for tag in releases:
        tree = s.get_json(API + '/repos/attaswift/BigInt/git/trees/%s?recursive=1' % tag, 'bigint-tree-%s.json' % tag,
                          accept='application/vnd.github+json')
        if tree is None:
            continue
        paths = dict((os.path.basename(t['path']).replace(' ', '').lower(), t['path']) for t in tree.get('tree') or []
                     if t['path'].startswith('Sources/') and t['path'].endswith('.swift'))
        same, differing, missing = 0, 0, []
        for n in names:
            p = paths.get(n.lower())
            if not p:
                missing.append(n)
                continue
            status, data = request('https://raw.githubusercontent.com/attaswift/BigInt/%s/%s' % (tag, urllib.parse.quote(p)))
            s.save('bigint-%s-%s' % (tag, os.path.basename(p)), data)
            if status != 200:
                s.fail('attaswift/BigInt %s %s: status %s' % (tag, p, status))
                continue
            up, loc = normalized(data.decode('utf-8', 'replace')), local[n]
            if loc and loc[-1] == '}' and len(loc) == len(up) + 1:
                loc = loc[:-1]  # the closing brace of CryptoSwift's wrapper
            d = [x for x in difflib.unified_diff(up, loc, lineterm='', n=0) if x[:1] in '+-' and x[:3] not in ('+++', '---')]
            same += 0 if d else 1
            differing += len(d)
        status, lic = request('https://raw.githubusercontent.com/attaswift/BigInt/%s/LICENSE.md' % tag)
        s.save('bigint-%s-LICENSE.md' % tag, lic)
        digest = hashlib.sha256(lic).hexdigest()
        note = ('LICENSE.md sha256 %s, %s' % (digest[:12], 'identical to the committed text' if digest == committed else 'NOT the committed text')
                if status == 200 else 'LICENSE.md: status %s' % status)
        print('  %s: %d of %d files identical; %d lines differ in the others%s; %s'
              % (tag, same, len(names), differing, ('; not in that release: ' + ', '.join(missing)) if missing else '', note))
        if best is None or differing < best[0]:
            best = (differing, tag)
    if best:
        print('  closest: %s (%d differing lines); no release matches exactly, so every release above is searched' % (best[1], best[0]))
    return [t[1:] for t in releases]


def package_names(advisory):
    return [((v.get('package') or dict()).get('name') or '').lower() for v in advisory.get('vulnerabilities') or []]


def main():
    nio, nio_ssl, crypto, cryptoswift, out = sys.argv[1:6]
    if os.path.exists(out):
        sys.exit('refusing: %s already exists; give a new directory' % out)
    os.makedirs(out)
    s = Search(out)
    print('vendored-advisories %s; raw responses in %s' % (time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), out))
    print('GitHub API: ' + ('authenticated with the gh CLI token (not shown)' if token() else
                           'unauthenticated (60 requests an hour, shared by every job on this host)'))
    llhttp = llhttp_version(nio)
    boring = [('swift-nio-ssl 2.37.5', boringssl_revision(nio_ssl, 'CNIOBoringSSL')),
              ('swift-crypto 5.0.0', boringssl_revision(crypto, 'CCryptoBoringSSL'))]
    print('llhttp in swift-nio 2.103.0: %s (the LLHTTP_VERSION_ macros in Sources/CNIOLLHTTP/include/c_nio_llhttp.h)' % llhttp)
    for who, rev in boring:
        print('BoringSSL in %s: %s (its hash.txt)' % (who, rev))

    print('\n## Keyword searches: the GitHub Advisory Database (every page; reviewed and unreviewed) and NVD')
    control = s.web('swift-nio')
    if control is not None:
        for want in ('GHSA-rj37-6j9x-74q6', 'GHSA-r3rc-9hpw-54v9', 'GHSA-cq87-8r7h-962v'):
            if want in control:
                print('control: the GitHub keyword swift-nio lists ' + want)
            else:
                s.fail('control: the GitHub keyword swift-nio does not list ' + want)
    rows = s.nvd('Zip Swift')
    if rows is not None:
        if any(c == 'CVE-2023-39135' for c, _ in rows):
            print('control: the NVD keyword Zip Swift lists CVE-2023-39135')
        else:
            s.fail('control: the NVD keyword Zip Swift does not list CVE-2023-39135')
    for keyword in WEB_KEYWORDS:
        ids = s.web(keyword)
        if ids is not None:
            print('GitHub keyword %r: %d advisories%s' % (keyword, len(ids), '' if ids else ' (the page says: No results matched your search)'))
            s.judge('the GitHub keyword search %r' % keyword, ids)
    for keyword in NVD_KEYWORDS:
        rows = s.nvd(keyword)
        if rows is not None:
            print('NVD keyword %r: %d CVEs' % (keyword, len(rows)))
            s.judge('the NVD keyword search %r' % keyword, [c for c, _ in rows])

    print('\n## llhttp %s: OSV (npm) and the GitHub Advisory Database, at that version and at any version' % llhttp)
    res = s.osv_batch([dict(package=dict(name='llhttp', ecosystem='npm'), version=llhttp),
                       dict(package=dict(name='llhttp', ecosystem='npm')),
                       dict(package=dict(name='lodash', ecosystem='npm'), version='4.17.15')], 'llhttp')
    if res is not None:
        at, anyv, ctl = res
        if 'GHSA-p6mc-m468-83gw' in ctl:
            print('OSV control: lodash 4.17.15 returned GHSA-p6mc-m468-83gw')
        else:
            s.fail('OSV control: lodash 4.17.15 did not return GHSA-p6mc-m468-83gw')
        print('OSV, llhttp %s: %s' % (llhttp, ', '.join(at) or 'none'))
        print('OSV, llhttp at any version: %s' % (', '.join(anyv) or 'none'))
        s.judge('OSV (llhttp, any version)', anyv)
        if at:
            s.fail('OSV lists advisories for llhttp %s itself: %s' % (llhttp, ', '.join(at)))
    advs = s.affects('npm', ['llhttp@' + llhttp, 'lodash@4.17.15'], 'npm-llhttp')
    if advs is not None:
        if any(a.get('ghsa_id') == 'GHSA-p6mc-m468-83gw' for a in advs):
            print('GitHub control: lodash@4.17.15 returned GHSA-p6mc-m468-83gw')
        else:
            s.fail('GitHub control: lodash@4.17.15 did not return GHSA-p6mc-m468-83gw')
        mine = [a.get('ghsa_id') for a in advs if 'llhttp' in package_names(a)]
        print('GitHub reviewed advisories affecting llhttp@%s: %s' % (llhttp, ', '.join(mine) or 'none'))
        if mine:
            s.fail('GitHub lists reviewed advisories for llhttp %s itself: %s' % (llhttp, ', '.join(mine)))

    print('\n## BoringSSL by revision: OSV, which indexes BoringSSL from OSS-Fuzz as git ranges')
    res = s.osv_batch([dict(commit=rev) for _, rev in boring] + [dict(commit=BORINGSSL_CONTROL[0])], 'boringssl-commits')
    if res is not None:
        if BORINGSSL_CONTROL[1] in res[-1]:
            print('OSV control: commit %s, where %s begins, returned it' % (BORINGSSL_CONTROL[0][:12], BORINGSSL_CONTROL[1]))
        else:
            s.fail('OSV control: commit %s did not return %s' % (BORINGSSL_CONTROL[0][:12], BORINGSSL_CONTROL[1]))
        for (who, rev), ids in zip(boring, res[:-1]):
            print('OSV, commit %s (BoringSSL in %s): %s' % (rev[:12], who, ', '.join(ids) or 'none'))
            if ids:
                s.fail('OSV lists advisories for BoringSSL at %s: %s; judge them' % (rev, ', '.join(ids)))
    res = s.osv_batch([dict(package=dict(name='boringssl', ecosystem='OSS-Fuzz'))], 'boringssl-ossfuzz')
    if res is not None:
        print('OSV, OSS-Fuzz boringssl at any revision: %s (the commit queries above say whether a revision is in their ranges)'
              % (', '.join(res[0]) or 'none'))

    print('\n## BigInt (attaswift/BigInt), as vendored by CryptoSwift 1.10.0')
    versions = bigint_releases(s, cryptoswift)
    spellings = ['github.com/attaswift/BigInt', 'github.com/attaswift/bigint', 'BigInt', 'bigint']
    queries = [dict(package=dict(name=sp, ecosystem='SwiftURL'), version=v) for v in versions for sp in spellings]
    queries += [dict(package=dict(name=sp, ecosystem='SwiftURL')) for sp in spellings]
    queries.append(dict(package=dict(name='github.com/marmelroy/Zip', ecosystem='SwiftURL'), version='2.1.2'))
    res = s.osv_batch(queries, 'bigint')
    if res is not None:
        if 'GHSA-g454-wj9r-jpg4' in res[-1]:
            print('OSV control: github.com/marmelroy/Zip 2.1.2 returned GHSA-g454-wj9r-jpg4')
        else:
            s.fail('OSV control: github.com/marmelroy/Zip 2.1.2 did not return GHSA-g454-wj9r-jpg4')
        n = len(versions) * len(spellings)
        at = sorted(set(i for r in res[:n] for i in r))
        anyv = sorted(set(i for r in res[n:-1] for i in r))
        print('OSV, at the %d releases above (every spelling): %s; at any version: %s'
              % (len(versions), ', '.join(at) or 'none', ', '.join(anyv) or 'none'))
        s.judge('OSV (attaswift/BigInt)', sorted(set(at + anyv)))
    advs = s.affects('swift', ['%s@%s' % (sp, v) for v in versions for sp in spellings[:2]] + ['github.com/marmelroy/Zip@2.1.2'],
                     'swift-bigint')
    if advs is not None:
        if any(a.get('ghsa_id') == 'GHSA-g454-wj9r-jpg4' for a in advs):
            print('GitHub control: github.com/marmelroy/Zip@2.1.2 returned GHSA-g454-wj9r-jpg4')
        else:
            s.fail('GitHub control: github.com/marmelroy/Zip@2.1.2 did not return GHSA-g454-wj9r-jpg4')
        mine = [a.get('ghsa_id') for a in advs if set(package_names(a)) & set(x.lower() for x in spellings)]
        print('GitHub reviewed advisories affecting those releases: %s' % (', '.join(mine) or 'none'))
        s.judge('GitHub (attaswift/BigInt)', mine)

    print('\n## Published security advisories of the vendored projects repositories')
    control = s.repository('apple/swift-nio')
    if control is not None:
        if any(a.get('ghsa_id') == 'GHSA-r3rc-9hpw-54v9' for a in control):
            print('control: apple/swift-nio lists GHSA-r3rc-9hpw-54v9 (%d published)' % len(control))
        else:
            s.fail('control: apple/swift-nio does not list GHSA-r3rc-9hpw-54v9')
    for repo in REPOSITORIES:
        advs = s.repository(repo)
        if advs is not None:
            print('%s: %d published' % (repo, len(advs)))
            s.judge('the repository advisories of ' + repo, [a.get('ghsa_id') for a in advs])

    print('\nfinished %s; failures: %d' % (time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), s.failures))
    return 1 if s.failures else 0


if __name__ == '__main__':
    sys.exit(main())
