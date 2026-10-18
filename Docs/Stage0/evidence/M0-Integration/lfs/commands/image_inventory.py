#!/usr/bin/env python3
"""Step 1 of the Git LFS adoption (ADR-0002): every image file tracked at a commit, classified, with the SHA-256 of
each blob read from git (not from the working tree).

    /usr/bin/python3 -I image_inventory.py <commit> <out-dir>

Image files are those whose extension, in any letter case, is png, jpg, jpeg, gif, heic, tif, tiff or webp. Each is
classified as
  snapshot  inside any directory named __Snapshots__ (a snapshot test reference)
  evidence  under Docs/Stage0/evidence/ (a Stage 0 evidence image)
  plain     anything else (design boards in Docs/Design/images, fixtures, fonts, asset catalogs, app icons and any
            other product asset), which stays in plain git.
Files with other image-like extensions (svg, bmp, ico, icns, heif, avif) are listed as plain too, so that nothing is
missed; PDFs are documents, not images, and are only counted.

Writes, in <out-dir>:
  image-inventory.tsv          class, extension, bytes, sha256, git blob id and path of every image file
  lfs-manifest.sha256          "<sha256>  <path>" for every snapshot and evidence image (shasum -a 256 -c format)
  image-inventory-summary.txt  counts and bytes per class, extension and folder, and the checks below
Checks (the script exits 1 if one fails): every blob is a regular file (mode 100644 or 100755), none is already an
LFS pointer, and every snapshot and evidence image starts with its format's signature (it is a real image).
Standard library only; reads the repository with git; writes nothing else.
"""
import collections
import datetime
import hashlib
import os
import subprocess
import sys

LFS_EXT = ('png', 'jpg', 'jpeg', 'gif', 'heic', 'tif', 'tiff', 'webp')
OTHER_IMAGE_EXT = ('svg', 'bmp', 'ico', 'icns', 'heif', 'avif')
EVIDENCE_PREFIX = 'Docs/Stage0/evidence/'
POINTER_PREFIXES = (b'version https://git-lfs.github.com/spec/', b'version https://hawser.github.com/spec/')


def git(*args, data=None):
    return subprocess.run(['git', *args], input=data, capture_output=True, check=True).stdout


def ext_of(path):
    name = path.rsplit('/', 1)[-1]
    return name.rsplit('.', 1)[1].lower() if '.' in name else ''


def classify(path):
    ext = ext_of(path)
    if ext in LFS_EXT:
        if '__Snapshots__' in path.split('/')[:-1]:
            return 'snapshot', 'inside a __Snapshots__ directory'
        if path.startswith(EVIDENCE_PREFIX):
            return 'evidence', 'under Docs/Stage0/evidence/'
    if path.startswith('Docs/Design/images/'):
        why = 'design board image (Docs/Design/images)'
    elif path.startswith('Fixtures/'):
        why = 'fixture'
    elif '.xcassets/' in path:
        why = 'asset catalog image' + (' (app icon)' if '.appiconset/' in path else '')
    elif ext == 'svg':
        why = 'SVG (text) product or document asset'
    else:
        why = 'other product or document asset'
    return 'plain', why


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


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    commit, out = sys.argv[1], sys.argv[2]
    full = git('rev-parse', '--verify', commit + '^{commit}').decode().strip()
    os.makedirs(out, exist_ok=True)

    entries = []
    for rec in git('ls-tree', '-r', '-l', '-z', full).split(b'\0'):
        if not rec:
            continue
        meta, path = rec.split(b'\t', 1)
        mode, kind, oid, size = meta.decode().split()
        entries.append((mode, kind, oid, size, path.decode('utf-8', 'surrogateescape')))
    images = [e for e in entries if ext_of(e[4]) in LFS_EXT + OTHER_IMAGE_EXT]
    pdfs = [e for e in entries if ext_of(e[4]) == 'pdf']

    # Read every image blob through one `git cat-file --batch` process.
    request = ''.join(e[2] + '\n' for e in images).encode()
    raw = git('cat-file', '--batch', data=request)
    blobs, pos = {}, 0
    for e in images:
        header_end = raw.index(b'\n', pos)
        oid, kind, size = raw[pos:header_end].decode().split()
        size = int(size)
        start = header_end + 1
        blobs[e[2]] = raw[start:start + size]
        pos = start + size + 1  # the content is followed by a line feed

    problems = []
    rows = []
    for mode, kind, oid, size, path in images:
        content = blobs[oid]
        cls, why = classify(path)
        ext = ext_of(path)
        digest = hashlib.sha256(content).hexdigest()
        if kind != 'blob' or mode not in ('100644', '100755'):
            problems.append(f'{path}: mode {mode} type {kind} is not a regular file')
        if len(content) != int(size):
            problems.append(f'{path}: blob is {len(content)} bytes, ls-tree says {size}')
        if content.startswith(POINTER_PREFIXES):
            problems.append(f'{path}: already an LFS pointer at {full}')
        if cls != 'plain' and not is_real_image(ext, content[:16]):
            problems.append(f'{path}: does not start with the {ext} signature')
        rows.append((cls, ext, len(content), digest, oid, path, why))

    with open(os.path.join(out, 'image-inventory.tsv'), 'w', encoding='utf-8') as fh:
        fh.write('class\textension\tbytes\tsha256\tblob\tpath\treason\n')
        for r in rows:
            fh.write('\t'.join(str(x) for x in r) + '\n')
    tracked = [r for r in rows if r[0] != 'plain']
    with open(os.path.join(out, 'lfs-manifest.sha256'), 'w', encoding='utf-8') as fh:
        for r in tracked:
            fh.write(f'{r[3]}  {r[5]}\n')

    lines = []
    p = lines.append
    p(f'# Image inventory at {full}')
    p(f'written {datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")} by '
      f'Docs/Stage0/evidence/M0-Integration/lfs/commands/image_inventory.py; {git("--version").decode().strip()}')
    p(f'tracked files at the commit: {len(entries)}; image files (png, jpg, jpeg, gif, heic, tif, tiff, webp, any case): '
      f'{sum(1 for r in rows if r[1] in LFS_EXT)}; other image-like files ({", ".join(OTHER_IMAGE_EXT)}): '
      f'{sum(1 for r in rows if r[1] in OTHER_IMAGE_EXT)}; PDFs (documents, not images, plain git): {len(pdfs)}')
    p('')
    p('| Class | Files | Bytes | Largest | Stored |')
    p('| --- | --- | --- | --- | --- |')
    for cls, stored in (('snapshot', 'Git LFS'), ('evidence', 'Git LFS'), ('plain', 'plain git')):
        sel = [r for r in rows if r[0] == cls]
        p(f'| {cls} | {len(sel)} | {sum(r[2] for r in sel)} | {max((r[2] for r in sel), default=0)} | {stored} |')
    p(f'| to be tracked by LFS (snapshot + evidence) | {len(tracked)} | {sum(r[2] for r in tracked)} | '
      f'{max((r[2] for r in tracked), default=0)} | Git LFS |')
    p('')
    p('By extension (class, extension: files, bytes):')
    by_ext = collections.OrderedDict()
    for r in rows:
        k = (r[0], r[1])
        n, b = by_ext.get(k, (0, 0))
        by_ext[k] = (n + 1, b + r[2])
    for (cls, ext), (n, b) in sorted(by_ext.items()):
        p(f'  {cls}, {ext}: {n} files, {b} bytes')
    p('')
    p('By folder (class, folder: files, bytes):')
    by_dir = collections.OrderedDict()
    for r in rows:
        parts = r[5].split('/')
        if r[0] == 'snapshot':
            folder = '/'.join(parts[:parts.index('__Snapshots__') + 2])
        elif r[0] == 'evidence':
            folder = '/'.join(parts[:4])
        else:
            folder = '/'.join(parts[:-1])
        k = (r[0], folder)
        n, b = by_dir.get(k, (0, 0))
        by_dir[k] = (n + 1, b + r[2])
    for (cls, folder), (n, b) in sorted(by_dir.items()):
        p(f'  {cls}, {folder}: {n} files, {b} bytes')
    p('')
    p('Plain git (not tracked by LFS), each with its reason:')
    for r in rows:
        if r[0] == 'plain':
            p(f'  {r[5]} ({r[2]} bytes): {r[6]}')
    p('')
    p('Checks: every image is a regular file blob; none is already an LFS pointer; every snapshot and evidence image '
      'starts with its format signature.')
    if problems:
        p(f'FAILED: {len(problems)} problem(s):')
        for x in problems:
            p('  ' + x)
    else:
        p(f'passed: {len(rows)} image files checked, {len(tracked)} real images to be tracked by LFS, 0 LFS pointers '
          f'at the commit')
    p('')
    p(f'manifest: lfs-manifest.sha256, {len(tracked)} lines, SHA-256 of each blob at {full} '
      f'(verify a checkout with: shasum -a 256 -c lfs-manifest.sha256, from the repository root)')
    text = '\n'.join(lines) + '\n'
    with open(os.path.join(out, 'image-inventory-summary.txt'), 'w', encoding='utf-8') as fh:
        fh.write(text)
    sys.stdout.write(text)
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
