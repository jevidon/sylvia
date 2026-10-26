#!/usr/bin/env python3
"""The review of m0-records-update, its completeness findings CMP-01 to CMP-07 (relayed 27 October 2026 on the build
Mac's clock; integration log section 43): does every line they cite hold the text they quote at 832a3636, the commit
the review read, and do their claims about other commits hold? Read-only, with git (`git show <commit>:<path>`,
`git diff`, `git log`); the findings as relayed are in ../relayed-findings.md. Where a finding quotes loosely, the check
reads the exact text and says so. Run from the repository root:
    python3 -I Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/commands/finding-lines.py
Prints one line per citation or claim and exits 1 if any does not hold.
"""
import re
import subprocess
import sys

REVIEWED = "832a3636"
results = []


def git(*args):
    out = subprocess.run(["git", *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def line(commit, path, number):
    lines = git("show", f"{commit}:{path}").splitlines()
    return lines[number - 1] if 0 < number <= len(lines) else ""


def holds(finding, label, ok, detail=""):
    results.append(ok)
    print(f"{'ok  ' if ok else 'FAIL'} {finding} {label}" + (f" ({detail})" if detail else ""))


def cites(finding, commit, path, number, *texts, absent=()):
    text = line(commit, path, number)
    missing = [t for t in texts if t not in text]
    present = [t for t in absent if t in text]
    holds(finding, f"{commit}:{path}:{number}", not missing and not present,
          "; ".join(["lacks: " + t[:90] for t in missing] + ["has: " + t[:90] for t in present]))


def cites_lines(finding, commit, path, first, last, *texts):
    """A text wrapped over lines first..last (the evidence README is wrapped at 120 characters)."""
    joined = " ".join(line(commit, path, n) for n in range(first, last + 1))
    missing = [t for t in texts if t not in joined]
    holds(finding, f"{commit}:{path}:{first}-{last}", not missing, "; ".join("lacks: " + t[:90] for t in missing))


RB, GATE, README = "Docs/Stage0/M0-device-runbook.md", "Docs/Stage0/M0-gate.md", "Docs/Stage0/README.md"
EV = "Docs/Stage0/evidence/M0-RecordsUpdate/README.md"
LOG = "Docs/Stage0/integration-log.md"
print(f"reviewed commit: {git('rev-parse', REVIEWED).strip()}")
print()

# CMP-01
holds("CMP-01", "git diff 6cede84a 832a3636 -- CLAUDE.md prints nothing",
      git("diff", "6cede84a", REVIEWED, "--", "CLAUDE.md") == "")
cites("CMP-01", REVIEWED, "CLAUDE.md", 5, "Since 24 October 2026 the M0 work is on `m0-sessions`",
      "the product owner builds the device sessions from it",
      "Further M0 work goes on a branch of its own made from `m0-sessions`",
      "Never build on `m0-integrate` or `m0-decisions`: both are behind `main`.")
cites("CMP-01", REVIEWED, "CLAUDE.md", 16, "awaits a check of Apple's release notes")
cites("CMP-01", REVIEWED, RB, 126, "step 2, `CLAUDE.md`, yours (0.3)")
cites("CMP-01", REVIEWED, RB, 166, "2. **`CLAUDE.md`'s milestone paragraph: yours to correct**",
      "so `m0-records-update` leaves it as merged")
cites("CMP-01", REVIEWED, GATE, 17, "2. **`CLAUDE.md`'s milestone paragraph: yours to correct, before you ask an agent "
      "for anything.**", "so `m0-records-update` leaves it as merged")
cites("CMP-01", REVIEWED, GATE, 846, "185. **`CLAUDE.md`, left for you**")
cites_lines("CMP-01", REVIEWED, EV, 46, 52, "**Left for the owner:** `CLAUDE.md`.",
            "the paragraph `6cede84a` wrote there")
owner = git("show", "c72247a6:CLAUDE.md")
holds("CMP-01", "c72247a6:CLAUDE.md has no such sentence",
      "m0-sessions" not in owner and "Never build on" not in owner and "are combined on `m0-integrate`" in owner)
holds("CMP-01", "m0-decisions is at c72247a6 (read-only), so the merge would fast-forward",
      git("rev-parse", "m0-decisions").strip() == git("rev-parse", "c72247a6").strip()
      and git("merge-base", "--is-ancestor", "c72247a6", REVIEWED) == "")
message = git("log", "-1", "--format=%B", "4c0fa815")
holds("CMP-01", "the message of merge 4c0fa815 says the next commit rewrites CLAUDE.md's paragraph",
      "the next commit rewrites it" in message)
holds("CMP-01", "git diff 4c0fa815 d1fb3dd4 -- CLAUDE.md prints nothing (d1fb3dd4 left it as merged)",
      git("diff", "4c0fa815", "d1fb3dd4", "--", "CLAUDE.md") == "")
cites("CMP-01", REVIEWED, README, 5, "*(corrected at the product owner's request on 24 October 2026, `5aec2518`",
      absent=("6cede84a",))
cites("CMP-01", REVIEWED, EV, 67, "A conflict can come only where")
cites("CMP-01", REVIEWED, EV, 72, "- **After the merge:** apply `CLAUDE.md`'s texts (above) and commit them on "
      "`m0-decisions`")

# CMP-02
cites("CMP-02", REVIEWED, RB, 210, "Record: commit the regenerated log on `m0-sessions` (0.3, step 6; until 24 October "
      "2026 this said `m0-decisions`)")
cites("CMP-02", "c72247a6", RB, 207, "commit the regenerated log on `m0-decisions` (0.3, step 6)")
cites("CMP-02", "6a72ce8c", RB, 208, "Record: commit the regenerated log on `m0-sessions` (0.3, step 6")
setup = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-runbook/2026-10-26-setup.txt")
holds("CMP-02", "the owner's setup record: 0.7's Keychain test not run",
      "The Keychain test itself has NOT run; this is not a pass for step 0.7" in setup)
cites("CMP-02", REVIEWED, GATE, 466, "The same holds for the records and evidence of your sessions, committed on "
      "`m0-sessions` (Section 1, item 1, step 6). Not needed for the exit: until you say so, build from `m0-sessions`.")
cites("CMP-02", REVIEWED, GATE, 471, "ADR-0001 records the same evidence on `m0-exit-prep`, merged into `m0-sessions` "
      "once reviewed")
cites("CMP-02", REVIEWED, GATE, 482, "**The branch the sessions use: `m0-decisions`, as the runbook said, settled on 26 "
      "October 2026.**")
cites("CMP-02", REVIEWED, EV, 28, "2. **The branch model, restated everywhere the records give it:**")

# CMP-03
cites("CMP-03", REVIEWED, GATE, 890, "**Your instructions brought up to date (24 October 2026).**",
      "(Section 6.3, items 104-110;", "the integration log, section 28)", "(Section 6.3, items 111-115)")
cites("CMP-03", REVIEWED, GATE, 870, "this line dated it 24 October alone: Section 6.3, item 146)")
item = {int(m.group(1)): m.group(2) for m in re.finditer(r"(?m)^(\d+)\. \*\*(.+?)\*\*",
                                                          git("show", f"{REVIEWED}:{GATE}"))}
holds("CMP-03", "at 832a3636 items 104-110 are m0-exit-prep's and 131 begins m0-sessions's instructions",
      item[104].startswith("`CLAUDE.md`'s milestone paragraph") and item[131].startswith("Run 1 and the branch"),
      f"104: {item[104][:50]}; 131: {item[131][:50]}")
holds("CMP-03", "at 832a3636 item 146 is FID-DA-04's and 173 OWN-DA-06's (pull request #6's dates)",
      "update's dates" in item[146] and "pull request #6" in item[173], f"146: {item[146][:40]}; 173: {item[173][:60]}")
sections = dict(re.findall(r"(?m)^## (\d+)\. (.*)$", git("show", f"{REVIEWED}:{LOG}")))
holds("CMP-03", "at 832a3636 integration log section 28 is R4-01 and R4-02, 36 the device-A change",
      "R4-01 and R4-02" in sections["28"] and "iPhone 13 mini" in sections["36"],
      f"28: {sections['28'][:50]}; 36: {sections['36'][:50]}")
cites("CMP-03", REVIEWED, LOG, 2396, "were renumbered by hand")
dry = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-RecordsUpdate/checks/renumber-sessions-dry-run.log")
holds("CMP-03", "the renumbering's dry run at 4c0fa815: 206 lines, 6 dangling, 27 mixed, 852 and 871 among them",
      "206 line(s) to rewrite; 6 dangling; 27 mixed line(s) listed" in dry and "M0-gate.md:852:" in dry
      and "M0-gate.md:871:" in dry)
cites("CMP-03", "4c0fa815", GATE, 852, "Section 6.3, item 146")
cites("CMP-03", "4c0fa815", GATE, 871, "(Section 6.3, items 104-110;")

# CMP-04
changed = [l for l in git("diff", "--name-status", "c72247a6", REVIEWED, "--", "Docs/Stage0/evidence/").splitlines()
           if not l.startswith("A")]
holds("CMP-04", "git diff --name-status c72247a6 832a3636 -- Docs/Stage0/evidence/ | grep -v '^A' lists one file",
      changed == ["M\tDocs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"], "; ".join(changed))
commits = git("log", "--format=%h", "c72247a6.." + REVIEWED, "--",
              "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py").split()
holds("CMP-04", "m0-exit-prep rewrote it in 83ed5ff3, 944a6302, f95de709 and 9f5edab1",
      sorted(c[:8] for c in commits) == sorted(["83ed5ff3", "944a6302", "f95de709", "9f5edab1"]), " ".join(commits))
script = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py").splitlines()
holds("CMP-04", "its lines 144-174 hold the row 76 entry, with its comment on the earlier texts",
      "Before 24 October 2026 this entry read" in script[143] and script[172].strip().startswith("+ file_has("),
      script[143].strip()[:70])
cites("CMP-04", REVIEWED, EV, 96, "the version it replaces (`../M0-Integration/commands/gate-refresh-check.py`)")
log = git("show", f"{REVIEWED}:{LOG}")
holds("CMP-04", "integration log 41.7 calls it the gate summary's old checker", "**The gate summary's old checker**"
      in log)

# CMP-05
cites("CMP-05", REVIEWED, RB, 137, "*(done by an agent on 24 October 2026, reviewed next: Section 6)*")
for n in (855, 856, 857):
    cites("CMP-05", REVIEWED, GATE, n, "*(done by an agent on 24 October 2026, reviewed next)*")
cites("CMP-05", REVIEWED, RB, 1003, "and that branch's review accepted it, as relayed")
cites("CMP-05", REVIEWED, GATE, 122, "*(24 October 2026: pull request #6 made that merge (`96bdc7e9`), and the M0 work "
      "continues on `m0-sessions`, made from `main` that day;", absent=("*(26 October 2026",))
s855 = line(REVIEWED, GATE, 855)
holds("CMP-05", f"{REVIEWED}:{GATE}:855 the note of 26 October 2026, then the one of 24 October 2026",
      0 <= s855.find("*(closed: the change of 24 October 2026") < s855.find("so a review that accepts it is still to "
                                                                             "come"))
s463 = line(REVIEWED, GATE, 463)
holds("CMP-05", f"{REVIEWED}:{GATE}:463 the note of 26 October 2026, then the one of 24 October 2026, last",
      0 <= s463.find("*(26 October 2026: done: R4-01 and R4-02 are closed") < s463.find(
          "so this item stays open until a review accepts the change") and s463.rstrip().endswith("item 119.)*"))
cites("CMP-05", REVIEWED, README, 41, "*(26 October 2026: the M0 work continues on `m0-decisions`")

# CMP-06
cites("CMP-06", REVIEWED, RB, 171, "they are what it lists against your first sittings' commits, with nothing under "
      "`Apps`, `Packages`, `Spikes`, `Fixtures` or `Contracts`")
paths = ["Apps", "Packages", "Spikes", "Fixtures", "Scripts", "Contracts", "Docs/Stage0/device-checklists"]
for commit in ("96bdc7e9", "8404f342", "432acc13", "d5336111", "c72247a6"):
    stat = git("diff", "--stat", commit, REVIEWED, "--", *paths)
    code = [l.split("|")[0].strip() for l in stat.splitlines() if "|" in l
            and l.split("|")[0].strip().split("/")[0] in ("Apps", "Packages", "Spikes", "Fixtures", "Contracts", "...")]
    recovery = re.search(r"device-checklists/G05-Recovery\.md\s*\|\s*(\d+)", stat)
    early = commit in ("96bdc7e9", "8404f342", "432acc13")
    ok = (len(code) == 4 and all("DeviceTests" in c for c in code) and recovery and recovery.group(1) == "25") if early \
        else (not code and recovery and recovery.group(1) == "7")
    holds("CMP-06", f"git diff --stat {commit} {REVIEWED} -- <the step's paths>: "
          + ("the four DeviceTests files and 25 lines of the G0.5 recovery checklist" if early
             else "nothing under Apps, Packages, Spikes, Fixtures or Contracts; 7 lines of the recovery checklist"),
          bool(ok), f"code paths: {len(code)}; recovery checklist: {recovery.group(1) if recovery else 'none'}")
rows = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-runbook/sessions.md")
holds("CMP-06", "the session log's rows 3a-3c name 96bdc7e9, 8404f342 and 432acc13, row 3d d5336111",
      all(re.search(r"\| " + r + r" \|[^\n]*`" + c, rows) for r, c in
          (("3a", "96bdc7e9"), ("3b", "8404f342"), ("3c", "432acc13"), ("3d", "d5336111"))))

# CMP-07
cites("CMP-07", REVIEWED, EV, 79, "Each log's header names its commit, the uncommitted")
cites("CMP-07", REVIEWED, EV, 80, "paths, the host and Xcode, the time and the load.")
no_header = []
for name in ("owner-records-intact", "check-records", "check-records-devicea", "check-amendments",
             "check-amendments-accuracy", "mutation-checks", "runbook-coverage", "gate-refresh-check",
             "gate-refresh-check-old"):
    first = git("show", f"{REVIEWED}:Docs/Stage0/evidence/M0-RecordsUpdate/checks/{name}.log").splitlines()[0]
    if not re.match(r"(command|commit|step-08-paths|correction-texts-compare|renumber-sessions)", first):
        no_header.append(name)
holds("CMP-07", "nine of the branch's logs start with their results, with no header", len(no_header) == 9,
      ", ".join(no_header))
cites_lines("CMP-07", REVIEWED, EV, 67, 68, "A conflict can come only where",
            "both changed the same lines: the gate reports, the checklists, the runbook, the gate summary or the ADRs.")
modified = [l.split("\t")[1] for l in git("diff", "--name-status", "c72247a6", REVIEWED).splitlines()
            if l.startswith("M")]
others = [p for p in modified if not re.match(r"Docs/(ADRs/|Stage0/(G0|device-checklists/|M0-device-runbook|M0-gate))",
                                                p)]
holds("CMP-07", "relative to c72247a6 the branch also changes CLAUDE.md, the READMEs, the plan, the amendments, the "
      "integration log, the inventory's Markdown, M0-contracts.md and the Zip guard's two scripts",
      all(p in others for p in ("CLAUDE.md", "README.md", "Docs/Stage0/README.md", "Docs/Sylvia_v1_iOS_Implementation_Plan.md",
                                "Docs/Stage0/M0-plan-amendments.md", LOG, "Docs/Licenses/third-party-inventory.md",
                                "Docs/Stage0/M0-contracts.md", "Scripts/check-dependency-lock.py",
                                "Scripts/ci.d/12-dependency-lock.sh")), ", ".join(others))

print()
print(f"summary: {len(results)} citations and claims, {results.count(True)} hold, {results.count(False)} do not")
sys.exit(0 if all(results) else 1)
