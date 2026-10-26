#!/usr/bin/env python3
"""Check that the product owner's session commits survive a merge exactly.

The owner's commits on m0-decisions (with Codex, from 26 October 2026 NZDT) are
BASE..OWNER_HEAD. For every file they touched, this check compares the merged
tree (the working tree, or the commit given with --rev) with OWNER_HEAD:

- a file the owner added, any evidence file under Docs/Stage0/evidence/, any
  file under Spikes/ and Docs/Licenses/inventory.json must be byte-identical;
- in every other file (records an agent may also edit: reports, checklists,
  the runbook), every line the owner added must still be there verbatim, at
  least as many times as in OWNER_HEAD, and no line the owner removed may
  occur more often than in OWNER_HEAD.

It prints one line per file and exits 1 on any difference. It reads git only;
it writes nothing.
"""

import argparse
import collections
import subprocess
import sys

BASE = "044ed3cf86db838c93cda7e2ca4829474b234ae5"   # m0-decisions before the sessions; tree == main's
OWNER_HEAD = "c72247a69a374ce361834550b92689b4abab95ee"  # m0-decisions on 26 October 2026


def git(*args, check=True):
    return subprocess.run(["git", *args], check=check, capture_output=True).stdout


def blob(rev, path):
    r = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def current(rev, path):
    if rev is None:
        try:
            with open(path, "rb") as f:
                return f.read()
        except FileNotFoundError:
            return None
    return blob(rev, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rev", help="commit to check (default: the working tree)")
    args = ap.parse_args()

    names = git("diff", "--name-status", "--no-renames", BASE, OWNER_HEAD).decode().splitlines()
    failures = 0
    for line in names:
        status, path = line.split("\t", 1)
        owner = blob(OWNER_HEAD, path)
        now = current(args.rev, path)
        exact = (status == "A" or path.startswith("Docs/Stage0/evidence/")
                 or path.startswith("Spikes/") or path == "Docs/Licenses/inventory.json")
        if owner is None:
            print(f"note  {path}: removed by the owner; {'absent' if now is None else 'PRESENT AGAIN'}")
            failures += now is not None
            continue
        if now is None:
            print(f"FAIL  {path}: missing")
            failures += 1
            continue
        if exact:
            ok = now == owner
            print(f"{'ok   ' if ok else 'FAIL '} {path}: {'byte-identical to' if ok else 'differs from'} {OWNER_HEAD[:8]}")
            failures += not ok
            continue
        diff = git("diff", "-U0", "--no-renames", BASE, OWNER_HEAD, "--", path).decode("utf-8", "replace").splitlines()
        added = collections.Counter(l[1:] for l in diff if l.startswith("+") and not l.startswith("+++"))
        removed = collections.Counter(l[1:] for l in diff if l.startswith("-") and not l.startswith("---"))
        owner_lines = collections.Counter(owner.decode("utf-8", "replace").split("\n"))
        now_lines = collections.Counter(now.decode("utf-8", "replace").split("\n"))
        missing = [l for l in added if now_lines[l] < owner_lines[l]]
        back = [l for l in removed if now_lines[l] > owner_lines[l]]
        ok = not missing and not back
        print(f"{'ok   ' if ok else 'FAIL '} {path}: {sum(added.values())} owner-added line(s) kept verbatim, "
              f"{len(missing)} missing; {sum(removed.values())} owner-removed line(s), {len(back)} back")
        for l in missing:
            print(f"        missing: {l[:160]}")
        for l in back:
            print(f"        back:    {l[:160]}")
        failures += not ok
    print(f"owner records intact: {'yes' if failures == 0 else 'NO'} ({failures} failure(s)); "
          f"owner commits {BASE[:8]}..{OWNER_HEAD[:8]}, checked {'working tree' if args.rev is None else args.rev}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
