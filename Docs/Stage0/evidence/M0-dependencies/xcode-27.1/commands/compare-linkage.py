#!/usr/bin/env python3
"""ADR-0014 evidence: compare two linkage.sh logs section by section (what ships under Xcode 27.0 and under 27.1).

  /usr/bin/python3 -I Docs/Stage0/evidence/M0-dependencies/xcode-27.1/commands/compare-linkage.py \
      Docs/Stage0/evidence/M0-dependencies/linkage.log Docs/Stage0/evidence/M0-dependencies/xcode-27.1/run-2/linkage.log \
      > Docs/Stage0/evidence/M0-dependencies/xcode-27.1/linkage-compare.log

For each of linkage.sh's six sections it prints:
  - every symbol marker (a third-party module or vendored C library, or one of Sylvia's own modules) with its count in
    each log, and whether it is present (non-zero) in one log and absent (zero) in the other: that is a change in what
    ships, which ADR-0014 section 4 must follow;
  - the lines that name a file or library and appear in one log only (Mach-O files of the app, the files of its
    resource bundles, its fonts, licenses, scripts, styles and privacy manifests, the libraries it loads), with sizes,
    versions and build times left out, so that only a file or library that came or went is listed.
It exits 1 if a section is missing from either log, a build failed in either, or a third-party marker changed from
present to absent or back; a count that changed while staying non-zero is listed but is not a change in what ships.
The two logs come from different commits as well as different Xcode builds, so a count of Sylvia's own modules may
differ because its code changed; the markers of Sylvia's own modules are listed apart.
"""
import re
import sys

OWN = re.compile(r'Swift module (Sylvia\w*|G01EPUBCore)\b')
MARKER = re.compile(r'^\s+(\d+)\s{2}(\S.*)$')
GRDB_LINE = re.compile(r'^\s+(defined symbols of Swift module GRDB|defined sqlite3_\* symbols[^:]*): (\d+)$')


def sections(path):
    out, name = {}, None
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.rstrip('\n')
        m = re.match(r'^### (\d+)\. ', line)
        if m:
            name = m.group(1)
            out[name] = {'title': line, 'markers': {}, 'lines': set(), 'build': None}
            continue
        if name is None:
            continue
        s = out[name]
        if line.startswith('build: ') or line.startswith('FAIL'):
            s['build'] = s['build'] or line
            if line.startswith('FAIL'):
                s['failed'] = True
            continue
        m = GRDB_LINE.match(line)
        if m:
            s['markers'][m.group(1)] = int(m.group(2))
            continue
        m = MARKER.match(line)
        if m and not line.strip().startswith('('):
            s['markers'][m.group(2)] = int(m.group(1))
            continue
        if line.startswith('  ') and not line.strip().startswith('(') and line.strip():
            # A file or library line: drop sizes, versions and other parenthesised numbers.
            s['lines'].add(re.sub(r'\s*\([^)]*\d[^)]*\)', '', line.strip()))
    return out


def main(old_path, new_path):
    old, new = sections(old_path), sections(new_path)
    bad = 0
    print(f'old: {old_path}')
    print(f'new: {new_path}')
    for key in sorted(set(old) | set(new), key=int):
        o, n = old.get(key), new.get(key)
        print()
        print((n or o)['title'])
        if not o or not n:
            print(f'  MISSING from the {"old" if not o else "new"} log')
            bad += 1
            continue
        print(f'  old {o["build"]}')
        print(f'  new {n["build"]}')
        if o.get('failed') or n.get('failed'):
            print('  FAILED build in one of the logs')
            bad += 1
        third, own = [], []
        for name in sorted(set(o['markers']) | set(n['markers'])):
            a, b = o['markers'].get(name), n['markers'].get(name)
            flip = (a or 0) > 0 and (b or 0) == 0 or (a or 0) == 0 and (b or 0) > 0 or a is None or b is None
            row = (name, a, b, flip)
            (own if OWN.search(name) else third).append(row)
        changed_presence = [r for r in third if r[3]]
        for title, rows in (('third-party code and its vendored libraries', third), ("Sylvia's own modules", own)):
            if not rows:
                continue
            print(f'  {title}: old count -> new count')
            for name, a, b, flip in rows:
                mark = '  PRESENCE CHANGED' if flip else ('  (count changed, present in both)' if a != b and a and b else '')
                print(f'    {str(a):>6} -> {str(b):<6} {name}{mark}')
        if changed_presence:
            bad += len(changed_presence)
        print(f'  third-party markers whose presence changed: {len(changed_presence)}')
        gone, came = sorted(o['lines'] - n['lines']), sorted(n['lines'] - o['lines'])
        print(f'  file and library lines in the old log only: {len(gone)}')
        for x in gone:
            print(f'    - {x}')
        print(f'  file and library lines in the new log only: {len(came)}')
        for x in came:
            print(f'    + {x}')
    print()
    print(f'compare-linkage: {bad} problem(s) (a missing section, a failed build or a third-party marker whose presence changed)')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:3]))
