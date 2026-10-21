#!/usr/bin/env python3
"""Step 5 of the Git LFS adoption (ADR-0002): verify the adoption commit, the working tree and the history.

    /usr/bin/python3 -I verify_adoption.py <adoption-commit> <base-commit> <evidence-dir>

<evidence-dir> holds the step 1 and 2 records: lfs-manifest.sha256, image-inventory.tsv, branches-before.tsv and
history-before.log. Run from the repository root of a checkout of the adoption commit or a later commit of the same
branch. Checks, each printed with its result:
  1. the adoption commit's only parent is <base-commit>;
  2. `git diff --name-status <base> <adoption>` touches only .gitattributes (added) and the manifest paths (modified);
  3. every manifest path in the adoption commit's tree is an LFS pointer blob in canonical form whose oid is the
     manifest's SHA-256 and whose size is the inventory's byte count, and no other path in that tree is a pointer;
  4. `git lfs ls-files --long <adoption>` lists exactly the manifest paths with the manifest's SHA-256, each marked
     "*" (the working tree holds the full object), and `git lfs fsck <adoption>` passes (objects and pointers);
  5. every manifest path in the working tree is a real image (format signature) whose SHA-256 is the manifest's;
  6. the history is intact: the base commit's tree listing and history listing have the SHA-256 recorded before the
     change, every image blob of the base commit is still the plain image (SHA-256 as in the manifest), every
     branch of branches-before.tsv except m0-integrate is unchanged, and m0-integrate contains the base commit and
     the adoption commit, with every commit after the base a descendant of the adoption commit.
Exits 1 if any check fails. Standard library only; read-only (git lfs fsck may move a corrupt object to
.git/lfs/bad, which is what it is for).
"""
import hashlib
import os
import re
import subprocess
import sys

POINTER = re.compile(rb'\Aversion https://git-lfs\.github\.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize ([0-9]+)\n\Z')
failures = []


def is_real_image(ext, head):
    if ext == 'png':
        return head.startswith(b'\x89PNG\r\n\x1a\n')
    if ext in ('jpg', 'jpeg'):
        return head.startswith(b'\xff\xd8\xff')
    if ext == 'gif':
        return head[:6] in (b'GIF87a', b'GIF89a')
    if ext in ('tif', 'tiff'):
        return head[:4] in (b'II*\x00', b'MM\x00*')
    if ext == 'webp':
        return head[:4] == b'RIFF' and head[8:12] == b'WEBP'
    if ext == 'heic':
        return head[4:8] == b'ftyp'
    return False


def git(*args, data=None, check=True):
    r = subprocess.run(['git', *args], input=data, capture_output=True)
    if check and r.returncode != 0:
        raise SystemExit(f'git {" ".join(args)} failed ({r.returncode}): {r.stderr.decode()}')
    return r


def result(n, ok, text):
    print(f'{n}. {"PASS" if ok else "FAIL"}: {text}')
    if not ok:
        failures.append(n)


def batch(oids):
    raw = git('cat-file', '--batch', data=''.join(o + '\n' for o in oids).encode()).stdout
    out, pos = {}, 0
    for oid in oids:
        end = raw.index(b'\n', pos)
        header = raw[pos:end].decode().split()
        size = int(header[2])
        out[oid] = raw[end + 1:end + 1 + size]
        pos = end + 1 + size + 1
    return out


def tree(commit):
    entries = {}
    for rec in git('ls-tree', '-r', '-z', commit).stdout.split(b'\0'):
        if rec:
            meta, path = rec.split(b'\t', 1)
            mode, kind, oid = meta.decode().split()
            entries[path.decode('utf-8', 'surrogateescape')] = (mode, kind, oid)
    return entries


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    adoption = git('rev-parse', '--verify', sys.argv[1] + '^{commit}').stdout.decode().strip()
    base = git('rev-parse', '--verify', sys.argv[2] + '^{commit}').stdout.decode().strip()
    ev = sys.argv[3]
    manifest = {}
    with open(os.path.join(ev, 'lfs-manifest.sha256'), encoding='utf-8') as fh:
        for line in fh:
            digest, path = line.rstrip('\n').split('  ', 1)
            manifest[path] = digest
    sizes = {}
    with open(os.path.join(ev, 'image-inventory.tsv'), encoding='utf-8') as fh:
        next(fh)
        for line in fh:
            cls, ext, size, digest, blob, path, why = line.rstrip('\n').split('\t')
            sizes[path] = (int(size), blob, cls)
    head = git('rev-parse', 'HEAD').stdout.decode().strip()
    print(f'# Verification of the Git LFS adoption commit {adoption}')
    print(f'base {base}; HEAD {head}; branch {git("branch", "--show-current").stdout.decode().strip() or "(detached)"}; '
          f'{git("--version").stdout.decode().strip()}; {git("lfs", "version").stdout.decode().strip()}')
    print(f'manifest: {len(manifest)} paths, {sum(sizes[p][0] for p in manifest)} bytes')
    print()

    # 1. parent
    parents = git('rev-list', '--parents', '-n', '1', adoption).stdout.decode().split()[1:]
    result(1, parents == [base], f'parents of {adoption[:12]}: {" ".join(parents)} (expected only {base})')

    # 2. diff scope
    changes = {}
    fields =[f for f in git('diff', '--name-status', '--no-renames', '-z', base, adoption).stdout.decode('utf-8', 'surrogateescape').split('\0') if f]
    for i in range(0, len(fields), 2):
        changes[fields[i + 1]] = fields[i]
    expected = dict({p: 'M' for p in manifest}, **{'.gitattributes': 'A'})
    stat = git('diff', '--shortstat', base, adoption).stdout.decode().strip()
    result(2, changes == expected, f'git diff {base[:12]} {adoption[:12]}: {len(changes)} paths ({stat}); '
           f'{sum(1 for s in changes.values() if s == "M")} modified, all manifest paths: '
           f'{set(p for p, s in changes.items() if s == "M") == set(manifest)}; added: '
           f'{sorted(p for p, s in changes.items() if s == "A")}; other statuses: '
           f'{sorted((p, s) for p, s in changes.items() if s not in ("M", "A"))}')

    # 3. pointer blobs in the adoption tree
    t = tree(adoption)
    blobs = batch([o for (m, k, o) in t.values() if k == 'blob'])
    bad, pointers_elsewhere = [], []
    for path, (mode, kind, oid) in sorted(t.items()):
        m = POINTER.match(blobs.get(oid, b''))
        if path in manifest:
            if not m or m.group(1).decode() != manifest[path] or int(m.group(2)) != sizes[path][0] or mode != '100644':
                bad.append(path)
        elif m or blobs.get(oid, b'').startswith(b'version https://git-lfs'):
            pointers_elsewhere.append(path)
    missing = sorted(set(manifest) - set(t))
    result(3, not bad and not pointers_elsewhere and not missing,
           f'{len(manifest) - len(bad) - len(missing)} of {len(manifest)} manifest paths are canonical LFS pointer blobs '
           f'(oid = manifest SHA-256, size = inventory bytes, mode 100644); not pointers or wrong: {bad[:10]}; '
           f'missing from the tree: {missing[:10]}; pointers outside the manifest: {pointers_elsewhere[:10]} '
           f'({len(t)} paths in the tree)')

    # 4. git lfs ls-files and fsck
    listed = {}
    marks = {}
    for line in git('lfs', 'ls-files', '--long', adoption).stdout.decode().splitlines():
        oid, mark, path = line.split(' ', 2)
        listed[path] = oid
        marks[path] = mark
    same = listed == manifest
    allfull = all(m == '*' for m in marks.values())
    fsck = git('lfs', 'fsck', adoption, check=False)
    fsck_text = (fsck.stdout + fsck.stderr).decode().strip().replace('\n', ' | ')
    result(4, same and allfull and fsck.returncode == 0,
           f'git lfs ls-files --long {adoption[:12]}: {len(listed)} files, equal to the manifest (paths and SHA-256): '
           f'{same}; all marked "*" (full object in the working tree): {allfull} '
           f'({sum(1 for m in marks.values() if m != "*")} not); git lfs fsck {adoption[:12]}: exit {fsck.returncode}, '
           f'"{fsck_text}"')

    # 5. working tree images
    wrong, notimage = [], []
    for path, digest in manifest.items():
        try:
            with open(path, 'rb') as fh:
                content = fh.read()
        except OSError:
            wrong.append(path)
            continue
        if hashlib.sha256(content).hexdigest() != digest:
            wrong.append(path)
        if not is_real_image(path.rsplit('.', 1)[1].lower(), content[:16]):
            notimage.append(path)
    result(5, not wrong and not notimage,
           f'working tree: {len(manifest) - len(wrong)} of {len(manifest)} files have the manifest SHA-256 '
           f'(differing or unreadable: {wrong[:10]}); real images by format signature: '
           f'{len(manifest) - len(notimage)} (not: {notimage[:10]})')

    # 6. history intact
    text = open(os.path.join(ev, 'history-before.log'), encoding='utf-8').read()
    tree_before = re.search(r"sha256 of 'git ls-tree -r [0-9a-f]+': ([0-9a-f]{64})", text).group(1)
    list_before = re.search(r"sha256 of 'git rev-list --parents [0-9a-f]+' \((\d+) commits\): ([0-9a-f]{64})", text)
    tree_now = hashlib.sha256(git('ls-tree', '-r', base).stdout).hexdigest()
    list_now = hashlib.sha256(git('rev-list', '--parents', base).stdout).hexdigest()
    base_tree = tree(base)
    base_blobs = batch([base_tree[p][2] for p in manifest])
    plain_ok = sum(1 for p in manifest if hashlib.sha256(base_blobs[base_tree[p][2]]).hexdigest() == manifest[p]
                   and base_tree[p][2] == sizes[p][1])
    branch_lines = []
    unchanged = True
    with open(os.path.join(ev, 'branches-before.tsv'), encoding='utf-8') as fh:
        for line in fh:
            name, before = line.rstrip('\n').split('\t')
            now = git('rev-parse', '--verify', '--quiet', f'refs/heads/{name}', check=False).stdout.decode().strip()
            if name == 'm0-integrate':
                after = git('rev-list', '--count', f'{before}..{now}').stdout.decode().strip()
                anc = git('merge-base', '--is-ancestor', adoption, now, check=False).returncode == 0
                desc = git('rev-list', f'{before}..{now}').stdout.decode().split()
                not_desc = [c for c in desc if git('merge-base', '--is-ancestor', adoption, c, check=False).returncode != 0]
                ok = git('merge-base', '--is-ancestor', before, now, check=False).returncode == 0 and anc and not not_desc
                unchanged &= ok
                branch_lines.append(f'   m0-integrate: {before[:12]} -> {now[:12]}; {after} new commits, all descendants '
                                    f'of the adoption commit: {not not_desc}; contains the base: '
                                    f'{git("merge-base", "--is-ancestor", before, now, check=False).returncode == 0}')
            else:
                same_ref = now == before
                unchanged &= same_ref
                branch_lines.append(f'   {name}: {before} {"unchanged" if same_ref else "CHANGED to " + (now or "(deleted)")}')
    ok6 = (tree_now == tree_before and list_now == list_before.group(2) and plain_ok == len(manifest) and unchanged)
    result(6, ok6, f'base tree listing sha256 {tree_now} (before: {tree_before}); base history listing sha256 '
           f'{list_now} (before: {list_before.group(2)}, {list_before.group(1)} commits; now '
           f'{git("rev-list", "--count", base).stdout.decode().strip()}); image blobs of the base commit that are still '
           f'the plain images of the manifest: {plain_ok} of {len(manifest)}; branches:')
    for line in branch_lines:
        print(line)
    count_before = re.search(r'git rev-list --count m0-integrate: (\d+)', text).group(1)
    count_now = git('rev-list', '--count', 'm0-integrate').stdout.decode().strip()
    print(f'   git rev-list --count m0-integrate: {count_now} (before: {count_before})')
    print()
    print('RESULT: ' + (f'FAIL (checks {failures})' if failures else 'PASS (all 6 checks)'))
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
