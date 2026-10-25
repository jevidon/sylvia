#!/usr/bin/env python3
"""Where the commits the thirteen M0 items' review records cite are kept (the second review of the M0 exit preparation,
26 October 2026, its finding EV-04; integration log section 32).

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/branch-reach.py

Reads the 63 records in Docs/Stage0/evidence/M0-Integration/item-reviews/extracted/ and takes each record's commit as
item-reviews.py does (an author's or a fix's `commit`, a review's `commit_reviewed`, read from the start of the field);
resolves each in this repository; and, for each distinct commit, lists every ref that contains it (git for-each-ref
--contains) and whether it is an ancestor of main, m0-integrate, m0-exit-prep and the remote-tracking refs as last
fetched (origin/main, origin/m0-integrate, origin/m0-decisions). It also lists the remote-tracking refs and tags that
could hold them. Read-only: nothing is fetched or pushed, and no ref is written. Exits 1 if a commit does not resolve,
or if any commit is held by a ref other than the local m0-int-* branches (the claim this log supports).
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", "..", ".."))
EXTRACTED = os.path.join(ROOT, "Docs/Stage0/evidence/M0-Integration/item-reviews/extracted")
HEX = re.compile(r"[0-9a-f]{7,40}")
OTHERS = ["main", "m0-integrate", "m0-exit-prep", "origin/main", "origin/m0-integrate", "origin/m0-decisions"]


def git(*args):
    done = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True, text=True)
    return done.returncode, done.stdout.strip()


def main():
    print("command: python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/branch-reach.py")
    print(f"commit: {git('rev-parse', 'HEAD')[1]} ({git('rev-parse', '--abbrev-ref', 'HEAD')[1]}); uncommitted paths: "
          f"{len([x for x in git('status', '--porcelain')[1].splitlines() if x])}")
    print()
    cited = {}  # full sha -> [item:label]
    unresolved = []
    records = 0
    for name in sorted(os.listdir(EXTRACTED)):
        if not name.endswith(".json.txt") or name.startswith("SUMMARY"):
            continue
        for r in json.loads(open(os.path.join(EXTRACTED, name), "rb").read().decode("utf-8")):
            records += 1
            res = r["result"]
            given = res.get("commit_reviewed") if ":review-" in r["label"] else res.get("commit")
            m = HEX.match(given or "")
            code, full = git("rev-parse", "--verify", "--quiet", (m.group(0) if m else "-") + "^{commit}")
            if not m or code != 0:
                unresolved.append(f"{r['label']}: {given!r}")
                continue
            cited.setdefault(full, []).append(r["label"])
    print(f"== 1. The records and the commits they cite")
    print(f"records read: {records}; distinct commits cited: {len(cited)}; not resolved here: {len(unresolved)}")
    for u in unresolved:
        print(f"PROBLEM not resolved: {u}")
    print()
    print("== 2. The refs that could keep them (read-only; nothing fetched)")
    _, remotes = git("for-each-ref", "--format=%(refname)", "refs/remotes")
    print("remote-tracking refs: " + (", ".join(remotes.splitlines()) or "none"))
    int_remote = [x for x in remotes.splitlines() if re.search(r"/m0-int-", x)]
    print(f"of them an m0-int-* branch: {len(int_remote)}" + (f" ({', '.join(int_remote)})" if int_remote else ""))
    _, tags = git("for-each-ref", "--format=%(refname)", "refs/tags")
    print(f"tags: {len([t for t in tags.splitlines() if t])}" + (f" ({', '.join(tags.splitlines())})" if tags else ""))
    _, branches = git("for-each-ref", "--format=%(refname:short)", "refs/heads/m0-int-*")
    print(f"local m0-int-* branches: {len(branches.splitlines())} ({', '.join(branches.splitlines())})")
    print()
    print("== 3. Each commit: the refs that contain it, and whether the branches the work went on to hold it")
    bad = []
    held_by = {}
    for full, labels in sorted(cited.items(), key=lambda kv: kv[1][0]):
        _, refs = git("for-each-ref", "--contains", full, "--format=%(refname)")
        refs = [x for x in refs.splitlines() if x]
        local_int = [x for x in refs if x.startswith("refs/heads/m0-int-")]
        other = [x for x in refs if not x.startswith("refs/heads/m0-int-")]
        anc = {o: git("merge-base", "--is-ancestor", full, o)[0] == 0 for o in OTHERS}
        held = [o for o, yes in anc.items() if yes]
        for x in local_int:
            held_by.setdefault(x, set()).add(full)
        line = (f"{full[:12]} (cited by {len(labels)}: {', '.join(labels)}): contained by "
                f"{', '.join(x.replace('refs/heads/', '') for x in local_int) or 'no m0-int-* branch'}"
                f"; by any other ref: {', '.join(other) or 'none'}"
                f"; an ancestor of {', '.join(OTHERS)}: {', '.join(held) or 'none of them'}")
        ok = bool(local_int) and not other and not held
        print(("ok      " if ok else "PROBLEM ") + line)
        if not ok:
            bad.append(full)
    print()
    print("== 4. In all")
    print(f"{len(cited)} distinct commits, cited by {sum(len(v) for v in cited.values())} records; each contained by "
          f"a local m0-int-* branch and by no other ref, and an ancestor of none of {', '.join(OTHERS)}: "
          f"{len(cited) - len(bad)} of {len(cited)}")
    for b, commits in sorted(held_by.items()):
        print(f"        {b.replace('refs/heads/', '')}: holds {len(commits)} of them")
    problems = len(bad) + len(unresolved)
    print()
    print(f"result: {'pass' if not problems else 'FAIL'} ({problems} problem(s))")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
