#!/usr/bin/env python3
"""What the Git LFS adoption stores and uploads: distinct LFS objects versus files (ADR-0002, push-time cost).

    /usr/bin/python3 -I lfs_storage.py <evidence-dir> [<lfs-objects-dir>]

Reads image-inventory.tsv (step 1) and prints, for the snapshot and evidence images now stored with LFS, the number of
files and bytes, and the number of distinct objects (identical images share one object) and their bytes: what the first
push of the adoption uploads and what one download of the current set (a clone or a CI checkout with lfs: true)
transfers. With <lfs-objects-dir> (a repository's .git/lfs/objects), it also counts the objects stored there and checks
that every distinct object of the manifest is present with its size and SHA-256. Standard library only; read-only.
"""
import csv
import hashlib
import os
import sys


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    rows = [r for r in csv.DictReader(open(os.path.join(sys.argv[1], 'image-inventory.tsv'), encoding='utf-8'),
                                      delimiter='\t') if r['class'] != 'plain']
    distinct = {}
    for r in rows:
        distinct[r['sha256']] = int(r['bytes'])
    files_bytes = sum(int(r['bytes']) for r in rows)
    print(f'LFS files: {len(rows)} ({files_bytes} bytes, {files_bytes / 2**20:.1f} MiB)')
    print(f'distinct LFS objects: {len(distinct)} ({sum(distinct.values())} bytes, {sum(distinct.values()) / 2**20:.1f} MiB, '
          f'{sum(distinct.values()) / 2**30:.4f} GiB); {len(rows) - len(distinct)} files share an object with another file')
    if len(sys.argv) == 3:
        store = sys.argv[2]
        found = {}
        for dirpath, _, names in os.walk(store):
            for n in names:
                found[n] = os.path.join(dirpath, n)
        good = 0
        for oid, size in distinct.items():
            p = found.get(oid)
            if p and os.path.getsize(p) == size:
                with open(p, 'rb') as fh:
                    if hashlib.sha256(fh.read()).hexdigest() == oid:
                        good += 1
        print(f'objects in {store}: {len(found)}; distinct manifest objects present with their size and SHA-256: '
              f'{good} of {len(distinct)}')
        sys.exit(0 if good == len(distinct) else 1)


if __name__ == '__main__':
    main()
