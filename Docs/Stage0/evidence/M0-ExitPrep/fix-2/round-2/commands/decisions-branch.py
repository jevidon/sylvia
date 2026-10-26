#!/usr/bin/env python3
"""The branch `m0-decisions` in this repository, read-only, against what the records of the M0 exit preparation say of
it (the fifth review of the M0 exit preparation, 26 October 2026, its finding HON-EP-06; integration log section 35).

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/round-2/commands/decisions-branch.py

The records said that `main` (96bdc7e9) and `m0-decisions` (044ed3cf) have the same tree, that `m0-decisions` is
behind `main`, and that no device step has run. This prints what the repository holds, each part ending with what the
records now state, and a PROBLEM line wherever the repository differs from that:
  1. the refs: main, origin/main, m0-decisions, origin/m0-decisions, m0-integrate and HEAD, their trees, and how each
     branch stands to `main` (nothing is fetched: the remote-tracking refs are as last fetched);
  2. the commits on `m0-decisions` that `main` lacks, oldest first: each one's hash, author time (UTC and the build
     Mac's NZDT), author name, subject and files; none of them is in `main`, HEAD or `origin/m0-decisions`;
  3. what they change, as recorded there and not judged here: the code and the license inventory outside the gate
     reports, the status cells of the gate reports' rows that changed (old and new), the checklists and the runbook (line
     counts), the session log's new rows (their first cells), the new evidence files, and what G0.5 recovery's drop-in
     builds, copies or runs that changed there since 9cdb0a02, the commit its whole run was made on;
  4. the files both branches changed since their common tree, and what a merge of the two would meet (git merge-tree
     --write-tree, which writes objects but no ref), at `941ac9a2`, the commit the fifth review read, and at HEAD: the
     fix must add no conflict;
  5. the gate summary's checker (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py) on a copy of
     HEAD's tree whose gate reports are those of `m0-decisions` where it changed them: which Section 2 rows would then
     disagree;
  6. what the earlier rounds' gate checks logged at their part 1g, the refs read-only, with each log's start time.
The copy of part 5 is made under .build/scratch/ and removed. Standard library only; reads git and files; writes no
ref. Exits 1 if any fact is not as the records state it: then the records are to be brought up to date with the branch.
"""
import os
import re
import shutil
import subprocess
import sys
import tarfile
import io
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", "..", ".."))
# What the records state (the gate summary's Section 5.4 and Section 6.3, item 127; integration log section 35).
MAIN = "96bdc7e996f99fcd2571ea983cc32a04076a5a07"            # pull request #6
MERGED = "044ed3cf86db838c93cda7e2ca4829474b234ae5"          # m0-decisions as pull request #6 merged it
TIP = "c72247a69a374ce361834550b92689b4abab95ee"             # m0-decisions as the fix of the fifth review read it
FIRST = "8404f3426bca692b1a302f165a82d13f2b03ed6d"           # the first of the eight
REVIEWED = "941ac9a298730b7cf46a44faf1db1274166cb930"        # m0-exit-prep as the fifth review read it
RUN = "9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e"             # the run of G0.5 recovery's whole drop-in, screen unlocked
COUNT = 8
CONFLICTS = ["Docs/Stage0/evidence/M0-runbook/sessions.md"]
LOGS = ["assembly", "fix-1", "fix-1/round-2", "fix-1/round-3", "fix-2"]
EXIT = "Docs/Stage0/evidence/M0-ExitPrep"
CHECKER = "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
NZDT = timezone(timedelta(hours=13))

problems = 0


def git(*args, ok=(0,)):
    done = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True)
    if done.returncode not in ok:
        raise SystemExit(f"git {' '.join(args)}: exit {done.returncode}: {done.stderr.decode(errors='replace')}")
    return done.returncode, done.stdout.decode("utf-8", errors="replace")


def out(*args):
    return git(*args)[1].strip()


def is_ancestor(a, b):
    return git("merge-base", "--is-ancestor", a, b, ok=(0, 1))[0] == 0


def expect(ok, text):
    global problems
    if not ok:
        problems += 1
    print(("   as the records state it: " if ok else "   PROBLEM, not as the records state it: ") + text)


def short(h):
    return h[:8]


def main():
    print("command: python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/round-2/commands/decisions-branch.py")
    print(f"HEAD: {out('rev-parse', 'HEAD')} ({out('rev-parse', '--abbrev-ref', 'HEAD')}); uncommitted paths: "
          f"{len([l for l in out('status', '--porcelain').splitlines() if l])}")
    print(f"start: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}; nothing is fetched, no ref is written")

    print()
    print("== 1. The refs, read-only (the remote-tracking ones as last fetched)")
    refs = {}
    for name in ("main", "origin/main", "m0-decisions", "origin/m0-decisions", "m0-integrate", "origin/m0-integrate",
                 "HEAD"):
        code, h = git("rev-parse", "--verify", "--quiet", name, ok=(0, 1))
        refs[name] = h.strip() if code == 0 else ""
        tree = out("rev-parse", f"{name}^{{tree}}") if refs[name] else "-"
        print(f"   {name:21} {refs[name] or '(no such ref)'}  tree {tree}")
    dec, mn = refs["m0-decisions"], refs["main"]
    ahead = int(out("rev-list", "--count", "main..m0-decisions"))
    behind = out("rev-list", "main", "^m0-decisions").split()
    base = out("merge-base", "main", "m0-decisions")
    print(f"   commits on m0-decisions that main lacks: {ahead}; on main that m0-decisions lacks: {len(behind)} "
          f"({', '.join(short(b) + ' ' + out('log', '-1', '--format=%s', b) for b in behind)})")
    print(f"   their merge base: {base}; main is an ancestor of m0-decisions: "
          f"{'yes' if is_ancestor('main', 'm0-decisions') else 'no'}")
    same_main_merged = out("rev-parse", "main^{tree}") == out("rev-parse", f"{MERGED}^{{tree}}")
    same_now = out("rev-parse", "main^{tree}") == out("rev-parse", "m0-decisions^{tree}")
    print(f"   main's tree is {short(MERGED)}'s: {'yes' if same_main_merged else 'no'}; is m0-decisions': "
          f"{'yes' if same_now else 'no'}")
    integ_behind = int(out("rev-list", "--count", "m0-integrate..main"))
    integ_ahead = int(out("rev-list", "--count", "main..m0-integrate"))
    print(f"   m0-integrate: an ancestor of main: {'yes' if is_ancestor('m0-integrate', 'main') else 'no'}, "
          f"{integ_behind} commits behind it, {integ_ahead} ahead")
    expect(mn == MAIN and refs["origin/main"] == MAIN, f"main and origin/main are {short(MAIN)}, pull request #6")
    expect(dec == TIP, f"m0-decisions is {short(TIP)}")
    expect(refs["origin/m0-decisions"] == MERGED, f"origin/m0-decisions, as last fetched, is {short(MERGED)}, the "
                                                  "commit pull request #6 merged")
    expect(ahead == COUNT and base == MERGED and not is_ancestor("main", "m0-decisions"),
           f"m0-decisions holds {COUNT} commits main lacks, made on {short(MERGED)}, and main, whose merge commit it "
           "lacks, is not an ancestor of it: neither branch is behind the other")
    expect(same_main_merged and not same_now, f"main's tree is {short(MERGED)}'s and no longer m0-decisions'")
    expect(is_ancestor("m0-integrate", "main") and integ_ahead == 0, "m0-integrate is behind main")

    print()
    print("== 2. The commits on m0-decisions that main lacks, oldest first")
    commits = out("rev-list", "--reverse", "main..m0-decisions").split()
    for c in commits:
        meta = out("log", "-1", "--format=%at%x09%an%x09%s", c).split("\t")
        when = datetime.fromtimestamp(int(meta[0]), timezone.utc)
        print(f"-- {c}  {when.strftime('%Y-%m-%d %H:%M:%S')} UTC ({when.astimezone(NZDT).strftime('%d %B %H:%M')} on "
              f"the build Mac's clock)  {meta[1]}: {meta[2]}")
        for line in out("show", "--format=", "--name-status", c).splitlines():
            print(f"      {line}")
    held = [c for c in commits if is_ancestor(c, "main") or is_ancestor(c, "HEAD")
            or is_ancestor(c, refs["origin/m0-decisions"])]
    first = datetime.fromtimestamp(int(out("log", "-1", "--format=%at", commits[0])), timezone.utc) if commits else None
    last = datetime.fromtimestamp(int(out("log", "-1", "--format=%at", commits[-1])), timezone.utc) if commits else None
    if commits:
        print(f"   from {first.strftime('%H:%M')} to {last.strftime('%H:%M')} UTC on {first.strftime('%d %B %Y')}; "
              f"held by main, HEAD or origin/m0-decisions: {len(held)}")
    expect(commits[:1] == [FIRST] and commits[-1:] == [TIP] and not held,
           f"the {COUNT}, {short(FIRST)} to {short(TIP)}, from 17:12 to 17:33 UTC on 25 October 2026, are in none of "
           "main, HEAD and origin/m0-decisions")

    print()
    print(f"== 3. What they change, from {short(MERGED)} to m0-decisions (as recorded there; not judged here)")
    names = out("diff", "--name-status", MERGED, "m0-decisions").splitlines()
    outside = [l.split("\t")[-1] for l in names if not l.split("\t")[-1].startswith("Docs/Stage0/")]
    print(f"   outside Docs/Stage0/: {', '.join(outside)}")
    print("   Docs/Licenses/inventory.json, the lines added:")
    for line in out("diff", "-U0", MERGED, "m0-decisions", "--", "Docs/Licenses/inventory.json").splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            print(f"      {line[1:].strip()[:170]}")
    print("   the gate reports' rows whose status cell changed (first cell; old -> new):")
    changed_rows = []
    for rel in [l.split("\t")[-1] for l in names]:
        if not re.match(r"^Docs/Stage0/G0[0-9][-A-Za-z0-9]*\.md$", rel):
            continue
        old = {r.split(" | ")[0]: r for r in git("show", f"{MERGED}:{rel}")[1].split("\n") if r.startswith("| ")}
        for r in git("show", f"m0-decisions:{rel}")[1].split("\n"):
            if not r.startswith("| "):
                continue
            key = r.split(" | ")[0]
            if key in old and old[key] != r:
                cells_old, cells_new = old[key].split(" | "), r.split(" | ")
                status_old = next((c for c in cells_old[1:] if re.match(r"^(passed|failed|partial|pending)", c)), "?")
                status_new = next((c for c in cells_new[1:] if re.match(r"^(passed|failed|partial|pending)", c)), "?")
                if status_old != status_new:
                    changed_rows.append((rel, key, status_old, status_new))
                    print(f"      {rel}: {key[2:72]}: {status_old} -> {status_new[:60]}")
    sections = [l for l in out("diff", "-U0", MERGED, "m0-decisions", "--", "Docs/Stage0/G05-Recovery.md").splitlines()
                if l.startswith("+### ")]
    for s in sections:
        print(f"      Docs/Stage0/G05-Recovery.md, a section added: {s[5:]}")
    for rel in ("Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/device-checklists/G05-Recovery.md"):
        stat = out("diff", "--numstat", MERGED, "m0-decisions", "--", rel).split("\t")
        print(f"   {rel}: {stat[0]} lines added, {stat[1]} removed" if len(stat) > 1 else f"   {rel}: unchanged")
    print("   the session log (Docs/Stage0/evidence/M0-runbook/sessions.md), its first sentence and the rows added "
          "(cells 1-5 and 7, each cut at 90 characters):")
    log_lines = out("diff", "-U0", MERGED, "m0-decisions", "--", "Docs/Stage0/evidence/M0-runbook/sessions.md")
    rows = []
    for line in log_lines.splitlines():
        if line.startswith("+No device") or line.startswith("+Device testing"):
            print(f"      first sentence now: {line[1:].split('. ')[0][:150]}.")
        if line.startswith("+| "):
            cells = [c.strip() for c in line[1:].strip().strip("|").split("|")]
            rows.append(cells[0])
            print("      " + " | ".join(c[:90] for i, c in enumerate(cells) if i in (0, 1, 2, 3, 4, 6)))
    added = [l.split("\t")[-1] for l in names if l.startswith("A\t") and l.split("\t")[-1].startswith(
        "Docs/Stage0/evidence/")]
    print(f"   new evidence files ({len(added)}):")
    for a in added:
        print(f"      {a}")
    expect(outside == ["Docs/Licenses/inventory.json", "Spikes/G05-Recovery/DeviceTests/App/TestHost.swift",
                       "Spikes/G05-Recovery/DeviceTests/Package.resolved",
                       "Spikes/G05-Recovery/DeviceTests/Support/Bundle+Module.swift",
                       "Spikes/G05-Recovery/DeviceTests/project.yml"],
           "outside the Stage 0 records they add Spikes/G05-Recovery/DeviceTests (a test host for the recovery suite) "
           "and change Docs/Licenses/inventory.json")
    expect(sorted((r[0], r[2], r[3].split(";")[0]) for r in changed_rows) == sorted([
        ("Docs/Stage0/G02-Transfer.md", "passed-simulator", "passed-device"),
        ("Docs/Stage0/G05-AI.md", "pending-device", "failed"),
        ("Docs/Stage0/G05-AI.md", "pending-device", "passed-device"),
        ("Docs/Stage0/G05-Recovery.md", "passed-simulator (SIGKILL drill: passed-host)", "failed (device)"),
        ("Docs/Stage0/G05-Recovery.md", "passed-simulator", "failed (device)")]),
        "five report rows changed status: G0.2's device-token row to passed-device, G0.5 AI's D1 to failed and D4 to "
        "passed-device, G0.5 recovery's rows 6 and 7 to failed (device)")
    expect(rows == ["3a", "3b", "3c", "3d"], "the session log has four rows more, 3a to 3d")
    dropin = out("diff", "--name-only", RUN, "m0-decisions", "--", "Spikes/G05-Recovery", "Scripts/lib", "Contracts",
                 "Scripts/ci.d/71-g05-recovery.sh", "Scripts/ci.sh").split()
    names_it = [f for f in git("grep", "-l", "DeviceTests", "m0-decisions", "--", "Scripts/ci.d/71-g05-recovery.sh",
                               "Spikes/G05-Recovery/Package.swift", "Scripts/lib", ok=(0, 1))[1].split() if f]
    print(f"   what G0.5 recovery's drop-in builds, copies or runs (Spikes/G05-Recovery, Scripts/lib, Contracts, "
          f"Scripts/ci.d/71-g05-recovery.sh, Scripts/ci.sh), changed from {short(RUN)}, the commit its whole run was "
          f"made on, to m0-decisions: {', '.join(dropin) or 'none'}; of the drop-in, the package's manifest and "
          f"Scripts/lib there, the files that name DeviceTests: {', '.join(names_it) or 'none'}")
    expect(dropin == [f"Spikes/G05-Recovery/DeviceTests/{f}" for f in
                      ("App/TestHost.swift", "Package.resolved", "Support/Bundle+Module.swift", "project.yml")]
           and not names_it,
           "of what the drop-in builds, copies or runs, only the new Spikes/G05-Recovery/DeviceTests changed there, a "
           "folder beside the recovery package that neither the drop-in, the package's manifest nor Scripts/lib names")

    print()
    print("== 4. The files both branches changed since their common tree, and a merge of the two (git merge-tree)")
    dec_files = set(out("diff", "--name-only", MERGED, "m0-decisions").split())
    both = {}
    for side in (REVIEWED, "HEAD"):
        prep = set(out("diff", "--name-only", MAIN, side).split())
        both[side] = sorted(dec_files & prep)
        code, text = git("merge-tree", "--write-tree", side, "m0-decisions", ok=(0, 1))
        tree = text.split("\n")[0].strip()
        conflicted = sorted({l.split("\t")[-1] for l in text.split("\n")[1:] if re.match(r"^[0-7]{6} [0-9a-f]{40} [123]\t",
                                                                                         l)})
        markers = 0
        for f in conflicted:
            markers += sum(1 for l in git("cat-file", "-p", f"{tree}:{f}")[1].split("\n") if l.startswith("<<<<<<< "))
        label = short(REVIEWED) if side == REVIEWED else "HEAD"
        print(f"   {label}: files both changed: {', '.join(both[side])}")
        print(f"   {label}: merge-tree exit {code}; conflicted files: {', '.join(conflicted) or 'none'}; conflict hunks: "
              f"{markers}")
        both[side + "-conflicts"] = (conflicted, markers)
    expect(both[REVIEWED + "-conflicts"][0] == CONFLICTS and both["HEAD-conflicts"] == both[REVIEWED + "-conflicts"],
           "a merge would meet one conflict, in the session log, at both commits: this fix adds none")

    print()
    print("== 5. The gate summary's checker with m0-decisions' gate reports in place of this tree's")
    scratch = os.path.join(ROOT, ".build", "scratch", "fix-2-round-2-overlay")
    shutil.rmtree(scratch, ignore_errors=True)
    os.makedirs(scratch)
    archive = subprocess.run(["git", "-C", ROOT, "archive", "HEAD"], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(scratch, filter="data")
    reports = sorted({r[0] for r in changed_rows})
    for rel in reports:
        with open(os.path.join(scratch, rel), "w", encoding="utf-8") as fh:
            fh.write(git("show", f"m0-decisions:{rel}")[1])
    done = subprocess.run([sys.executable, "-I", os.path.join(ROOT, CHECKER), scratch], capture_output=True, text=True)
    disagree = sorted({int(m.group(1)) for m in re.finditer(r"^row ([0-9]+):.*-> DISAGREES$", done.stdout, re.M)})
    summary = next((l for l in done.stdout.splitlines() if l.startswith("== summary:")), "(no summary line)")
    # The copy is HEAD's tree, which lacks the logs this fix writes after its documents commit and the gate summary
    # cites (this log, and the gate checks' while they run): their paths are missing in it, and that is not a status.
    own_logs = ("evidence/M0-ExitPrep/fix-2/round-2/decisions-branch.log",
                "evidence/M0-ExitPrep/fix-2/round-2/gate-checks.log")
    probs = [l for l in done.stdout.splitlines() if l.startswith("PROBLEM")]
    allowed = [l for l in probs if l.startswith("PROBLEM: missing path: ") and l.split(": ", 2)[2] in own_logs]
    other = [l for l in probs if l not in allowed]
    print(f"   reports taken from m0-decisions: {', '.join(reports)}")
    print(f"   checker exit {done.returncode}; rows disagreeing: {', '.join(map(str, disagree)) or 'none'}")
    print(f"   {summary}")
    for l in allowed:
        print(f"   (not a status: {l[len('PROBLEM: '):]}, a log this fix writes after its documents commit)")
    for l in other:
        print(f"   {l}")
    shutil.rmtree(scratch, ignore_errors=True)
    expect(done.returncode in (0, 1) and summary != "(no summary line)" and not disagree and not other,
           "the checker finds every Section 2 status as it is here with those reports")

    print()
    print("== 6. The earlier rounds' gate checks, their part 1g")
    seen = []
    for rel in LOGS:
        path = os.path.join(ROOT, EXIT, rel, "gate-checks.log")
        text = open(path, encoding="utf-8").read() if os.path.isfile(path) else ""
        start = re.search(r"^start: ([0-9T:Z-]+)", text, re.M)
        line = next((l.strip() for l in text.split("\n") if l.strip().startswith("m0-decisions: ")), "(none)")
        number = next((i for i, l in enumerate(text.split("\n"), 1) if l.strip().startswith("m0-decisions: ")), 0)
        verdict = "yes" if line.endswith("its tree is main's: yes") else "no" if line.endswith("its tree is main's: no") \
            else "?"
        seen.append(verdict)
        print(f"   {EXIT}/{rel}/gate-checks.log (start {start.group(1) if start else '?'}), line {number}: {line}")
    expect(seen == ["yes", "no", "no", "no", "no"],
           "the assembly's run read the two trees as the same, and each of the four fixes' runs, all after 17:33 UTC, "
           "as different")

    print()
    print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} fact(s) not as the records state them)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
