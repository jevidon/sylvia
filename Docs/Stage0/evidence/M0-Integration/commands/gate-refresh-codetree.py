#!/usr/bin/env python3
"""Part 1 of the 19 October 2026 gate summary checks (run by gate-refresh-checks.sh).

Since <base>, the commit of the second complete CI run (efc9479), may code, scripts, contracts, fixtures or the
workflow have changed only through the Git LFS adoption? This lists every path that differs between <base> and HEAD
under Spikes, Scripts, Packages, Apps, Contracts, Fixtures and .github, and .gitattributes, and requires that:
  - apart from the snapshot references, exactly the adoption's five files changed, added or modified:
    .gitattributes, .github/workflows/ci.yml, Scripts/ci.d/00-git-lfs.sh, Scripts/ci.sh and Scripts/setup-repo.sh;
  - every other changed path is a modified snapshot reference (a png under a __Snapshots__ directory) whose blob at
    HEAD is a canonical Git LFS pointer (version line, "oid sha256:" with 64 lowercase hex digits, "size", nothing
    else) whose oid is the SHA-256 of the path's blob at <base> and whose size is that blob's length, and whose file
    in this working tree is those bytes again (the checkout was smudged);
  - nothing was deleted, renamed or changed in type.
Read-only: git cat-file and git diff on the repository, and reads of the working tree.
    python3 -I gate-refresh-codetree.py <repository root> <base>
"""
import hashlib
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
base = sys.argv[2]
ADOPTION_FILES = {".gitattributes", ".github/workflows/ci.yml", "Scripts/ci.d/00-git-lfs.sh", "Scripts/ci.sh",
                  "Scripts/setup-repo.sh"}
POINTER = re.compile(rb"\Aversion https://git-lfs\.github\.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize (\d+)\n\Z")

def git(*args, data=None):
    return subprocess.run(["git", "-C", str(root), *args], input=data, capture_output=True, check=True).stdout

def blobs(specs):
    """The contents of each '<rev>:<path>' in specs, through one git cat-file --batch."""
    out = git("cat-file", "--batch", data="".join(s + "\n" for s in specs).encode())
    result, i = [], 0
    for spec in specs:
        header_end = out.index(b"\n", i)
        header = out[i:header_end].split()
        if header[-1] == b"missing":
            raise SystemExit(f"missing blob: {spec}")
        size = int(header[2])
        start = header_end + 1
        result.append(out[start:start + size])
        i = start + size + 1
    return result

head = git("rev-parse", "HEAD").decode().strip()
base_full = git("rev-parse", base + "^{commit}").decode().strip()
print(f"base {base_full}; HEAD {head}")
status_lines = git("diff", "--no-renames", "--name-status", base_full, head, "--", "Spikes", "Scripts", "Packages",
                   "Apps", "Contracts", "Fixtures", ".github", ".gitattributes").decode().splitlines()
changes = [line.split("\t", 1) for line in status_lines]
problems = 0
def problem(message):
    global problems
    problems += 1
    print("PROBLEM: " + message)

others = sorted(p for s, p in changes if "/__Snapshots__/" not in p)
snapshots = sorted(p for s, p in changes if "/__Snapshots__/" in p)
for s, p in changes:
    if "/__Snapshots__/" in p and s != "M":
        problem(f"{s} {p}: a snapshot reference may only be modified (turned into a pointer)")
    elif s not in ("A", "M"):
        problem(f"{s} {p}: nothing may be deleted, renamed or retyped")
print("changed outside __Snapshots__, with their status: "
      + ", ".join(f"{s} {p}" for s, p in changes if "/__Snapshots__/" not in p))
print(f"changed paths: {len(changes)}; outside __Snapshots__: {len(others)}: {', '.join(others)}")
if set(others) != ADOPTION_FILES:
    problem(f"outside the snapshot references the changed paths are not exactly the adoption's five files: "
            f"extra {sorted(set(others) - ADOPTION_FILES)}, missing {sorted(ADOPTION_FILES - set(others))}")

before = blobs([f"{base_full}:{p}" for p in snapshots])
after = blobs([f"{head}:{p}" for p in snapshots])
ok = 0
for path, old, new in zip(snapshots, before, after):
    if not path.lower().endswith(".png"):
        problem(f"{path}: not a png")
        continue
    match = POINTER.match(new)
    if not match:
        problem(f"{path}: the blob at HEAD is not a canonical LFS pointer")
        continue
    oid, size = match.group(1).decode(), int(match.group(2))
    if oid != hashlib.sha256(old).hexdigest() or size != len(old):
        problem(f"{path}: the pointer names {oid[:12]}... ({size} bytes), not the base blob")
        continue
    on_disk = (root / path).read_bytes()
    if hashlib.sha256(on_disk).hexdigest() != oid:
        problem(f"{path}: the working-tree file is not the pointer's object")
        continue
    ok += 1
print(f"snapshot references changed: {len(snapshots)}; each an LFS pointer to its bytes at the base, "
      f"and those bytes in the working tree: {ok}")
print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
sys.exit(1 if problems else 0)
