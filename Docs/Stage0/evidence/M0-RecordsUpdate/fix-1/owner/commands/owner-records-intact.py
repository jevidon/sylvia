#!/usr/bin/env python3
"""Check that the product owner's commits on m0-decisions survive a merge exactly: the new version of
Docs/Stage0/evidence/M0-RecordsUpdate/commands/owner-records-intact.py (27 October 2026; the fix of the owner-readability
findings of the review of m0-records-update, its finding OWN-RU-03; integration log section 44).

The version it replaces reads the owner's commits BASE..OWNER_HEAD with OWNER_HEAD written into it as c72247a6, so a run
after an agent's merge of a m0-decisions that has moved on would not check the owner's later commits. This one takes the
owner's head as --owner-head (default c72247a6, the head that version names, so that run without it, it checks what that
version checks) and the base as --base (default 044ed3cf, m0-decisions before the sessions). Give --owner-head the commit
m0-decisions is at (`git rev-parse m0-decisions`, read-only): every commit of m0-decisions after the base is then
checked, the owner's and Codex's records, and any branch the owner merged into m0-decisions, which is the owner's line
too. For every file those commits changed, it compares the merged tree (the working tree, or the commit given with
--rev) with the owner's head, as the version it replaces does:

- a file they added, any evidence file under Docs/Stage0/evidence/, any file under Spikes/ and
  Docs/Licenses/inventory.json must be byte-identical;
- in every other file (records an agent may also edit: reports, checklists, the runbook), every line they added must
  still be there verbatim, at least as many times as at the owner's head, and no line they removed may occur more often
  than there.

It also says whether the owner's head is in the checked commit's history (with --rev), which a fast-forward merge of the
checked commit into m0-decisions needs. It prints one line per file and exits 1 on any difference. It reads git only;
it writes nothing.
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/owner-records-intact.py \
        [--owner-head <commit>] [--base <commit>] [--rev <commit>]
"""

import argparse
import collections
import subprocess
import sys

BASE = "044ed3cf86db838c93cda7e2ca4829474b234ae5"   # m0-decisions before the sessions; tree == main's
OWNER_HEAD = "c72247a69a374ce361834550b92689b4abab95ee"  # m0-decisions on 26 October 2026, the earlier version's head


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
    ap.add_argument("--owner-head", default=OWNER_HEAD, help="the owner's head: the commit m0-decisions is at")
    ap.add_argument("--base", default=BASE, help="m0-decisions before the sessions")
    args = ap.parse_args()
    head = git("rev-parse", "--verify", args.owner_head + "^{commit}").decode().strip()
    base = git("rev-parse", "--verify", args.base + "^{commit}").decode().strip()
    commits = git("log", "--format=%h %s", f"{base}..{head}").decode().splitlines()
    print(f"owner's commits {base[:8]}..{head[:8]}: {len(commits)}")
    for c in commits:
        print(f"  {c[:100]}")

    names = git("diff", "--name-status", "--no-renames", base, head).decode().splitlines()
    failures = 0
    for line in names:
        status, path = line.split("\t", 1)
        owner = blob(head, path)
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
            print(f"{'ok   ' if ok else 'FAIL '} {path}: {'byte-identical to' if ok else 'differs from'} {head[:8]}")
            failures += not ok
            continue
        diff = git("diff", "-U0", "--no-renames", base, head, "--", path).decode("utf-8", "replace").splitlines()
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
    if args.rev is not None:
        held = subprocess.run(["git", "merge-base", "--is-ancestor", head, args.rev]).returncode == 0
        print(f"{'ok   ' if held else 'FAIL '} the owner's head {head[:8]} is {'' if held else 'NOT '}in the history of "
              f"{args.rev} ({'a fast-forward merge of it is possible' if held else 'no fast-forward merge of it'})")
        failures += not held
    print(f"owner records intact: {'yes' if failures == 0 else 'NO'} ({failures} failure(s)); "
          f"owner commits {base[:8]}..{head[:8]}, checked {'working tree' if args.rev is None else args.rev}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
