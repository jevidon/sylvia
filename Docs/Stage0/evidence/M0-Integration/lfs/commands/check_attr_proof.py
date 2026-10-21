#!/usr/bin/env python3
"""Steps 1 and 5 of the Git LFS adoption (ADR-0002): the LFS attributes match exactly the files in the manifest.

    /usr/bin/python3 -I check_attr_proof.py <list-commit> <manifest> [<attr-source>]

Runs `git check-attr -z --stdin filter diff merge text` over every path tracked at <list-commit> (plus
.gitattributes), once with core.ignorecase=true (as on this Mac) and once with core.ignorecase=false (as on Linux),
reading the attributes from the working tree's .gitattributes, or from <attr-source> (a commit) with
`git check-attr --source`. Passes only if, in both runs, the paths with filter=lfs are exactly the manifest's paths,
each of them has diff=lfs, merge=lfs and text unset, and no other path has any of these attributes set.
Prints the .gitattributes it used and the result; exits 1 on any difference. Standard library only; read-only.
"""
import hashlib
import subprocess
import sys


def git(*args, data=None):
    return subprocess.run(['git', *args], input=data, capture_output=True, check=True).stdout


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    list_commit, manifest = sys.argv[1], sys.argv[2]
    source = sys.argv[3] if len(sys.argv) == 4 else None
    list_full = git('rev-parse', '--verify', list_commit + '^{commit}').decode().strip()
    paths = [p for p in git('ls-tree', '-r', '--name-only', '-z', list_full).decode('utf-8', 'surrogateescape').split('\0') if p]
    if '.gitattributes' not in paths:
        paths.append('.gitattributes')
    want = []
    with open(manifest, encoding='utf-8') as fh:
        for line in fh:
            digest, path = line.rstrip('\n').split('  ', 1)
            want.append(path)
    want_set = set(want)

    if source:
        source_full = git('rev-parse', '--verify', source + '^{commit}').decode().strip()
        attributes = git('show', f'{source_full}:.gitattributes')
        where = f'.gitattributes at {source_full} (git check-attr --source {source_full})'
    else:
        with open('.gitattributes', 'rb') as fh:
            attributes = fh.read()
        where = '.gitattributes in the working tree (not yet committed)'
    print(f'# git check-attr over every tracked path at {list_full} ({len(paths)} paths, .gitattributes included)')
    print(f'attributes from: {where}; sha256 {hashlib.sha256(attributes).hexdigest()}')
    for line in attributes.decode().splitlines():
        if line and not line.startswith('#'):
            print(f'  {line}')
    print(f'manifest: {manifest}, {len(want)} paths ({len(want_set)} distinct)')
    print(f'{git("--version").decode().strip()}')

    failed = False
    for ignorecase in ('true', 'false'):
        args = ['-c', f'core.ignorecase={ignorecase}', 'check-attr', '-z', '--stdin']
        if source:
            args += ['--source', source_full]
        args += ['filter', 'diff', 'merge', 'text']
        out = git(*args, data=('\0'.join(paths) + '\0').encode('utf-8', 'surrogateescape'))
        fields = out.decode('utf-8', 'surrogateescape').split('\0')
        attrs = {}
        for i in range(0, len(fields) - 1, 3):
            path, name, value = fields[i], fields[i + 1], fields[i + 2]
            attrs.setdefault(path, {})[name] = value
        lfs = {p for p, a in attrs.items() if a.get('filter') == 'lfs'}
        wrong = [p for p in lfs if (attrs[p].get('diff'), attrs[p].get('merge'), attrs[p].get('text')) != ('lfs', 'lfs', 'unset')]
        others = [p for p, a in attrs.items() if p not in lfs and any(a.get(k) != 'unspecified' for k in ('filter', 'diff', 'merge', 'text'))]
        missing = sorted(want_set - lfs)
        extra = sorted(lfs - want_set)
        ok = not (wrong or others or missing or extra) and len(attrs) == len(paths)
        failed |= not ok
        print()
        print(f'core.ignorecase={ignorecase}: {len(attrs)} paths answered; filter=lfs on {len(lfs)}; '
              f'manifest paths without it: {len(missing)}; paths with it outside the manifest: {len(extra)}; '
              f'LFS paths without diff=lfs, merge=lfs and -text: {len(wrong)}; other paths with any of these attributes: {len(others)}'
              f' -> {"PASS" if ok else "FAIL"}')
        for label, items in (('missing', missing), ('extra', extra), ('wrong', sorted(wrong)), ('others', sorted(others))):
            for p in items[:50]:
                print(f'  {label}: {p} {attrs.get(p)}')
    print()
    print('RESULT: ' + ('FAIL' if failed else f'PASS: the LFS attributes match exactly the {len(want_set)} manifest paths, '
                                            'with either core.ignorecase setting, and nothing else'))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
