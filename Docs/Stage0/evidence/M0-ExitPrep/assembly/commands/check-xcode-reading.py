#!/usr/bin/env python3
"""How the relayed reading of Apple's pages for Xcode 27.1 stands against the repository (the M0 exit preparation,
24 October 2026; integration log section 30; ../xcode-27.1-release.md).

The orchestrating session read Apple's pages and relayed what they say; this check reads none of them (no network).
It reads, in the repository and on the build Mac, read-only, each fact ../xcode-27.1-release.md sets the relay against:

1. The build the relay names, 27A9275, is the pin: ADR-0001's Xcode row, SYLVIA_XCODE_BUILD_PINNED in
   Scripts/lib/env.sh, the inventory's toolchain pin, the workflow's Xcode guard and CLAUDE.md's toolchain line; and
   the installed Xcode, through xcodebuild -version with env.sh's DEVELOPER_DIR, is that build.
2. What the notes state, against the records: Swift 6.4 (ADR-0001's Swift row and `xcrun swift --version`); the iOS 27.1
   SDK (ADR-0001's SDK row and `xcodebuild -showsdks`); macOS Tahoe 26.6 or later (the build Mac's `sw_vers`, and
   ADR-0001's build host row).
3. The known issues, against the repository: no project.yml or Package.swift of Apps/, Packages/ or Spikes/ names Mac
   Catalyst, and the word appears in no tracked file but Scripts/check-dependency-lock.py and the records of this
   reading; no drop-in names an iPhone Duo simulator.
4. The records carry the relay with the confirmation pending: ADR-0001's open item and status line, and the gate
   summary's item 1, step 7, each say it was read by the orchestrating session and relayed, and that the technical
   lead's confirmation is still pending; neither says the confirmation is given.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/assembly/commands/check-xcode-reading.py <repository root or tree>

<tree> may be an extracted tree (git archive), which the gate checks beside this file use as the control: the files are
read there, and git's listings of tracked files (parts 1 and 3) are read in the repository that holds this script, whose
tracked paths are the same.

Host only; no simulator, no device, no network. Exits 1 if any fact does not hold.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
REPO = Path(__file__).resolve().parents[6]  # commands, assembly, M0-ExitPrep, evidence, Stage0, Docs, the root
problems = 0


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def report(ok, label):
    global problems
    print(f"{'ok      ' if ok else 'PROBLEM '}{label}")
    if not ok:
        problems += 1


def env_with_developer_dir():
    env = dict(os.environ)
    m = re.search(r'^export DEVELOPER_DIR="?\$\{DEVELOPER_DIR:-([^}"]+)\}"?', read("Scripts/lib/env.sh"), re.M)
    if m:
        env.setdefault("DEVELOPER_DIR", m.group(1))
    return env


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, env=env_with_developer_dir(),
                              cwd=REPO if cmd[0] == "git" else ROOT, timeout=120).stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"cannot run: {e}"


adr1 = read("Docs/ADRs/0001-platform-baseline-and-toolchain.md")
gate = read("Docs/Stage0/M0-gate.md")

print("== 1. The build the relay names is the pin, and installed")
xcode_row = next((l for l in adr1.splitlines() if l.startswith("| Xcode |")), "")
report("27.1, build 27A9275" in xcode_row, f"ADR-0001's Xcode row: {xcode_row[:90]}")
pinned = re.search(r'SYLVIA_XCODE_BUILD_PINNED="?([0-9A-Za-z]+)', read("Scripts/lib/env.sh"))
report(bool(pinned) and pinned.group(1) == "27A9275",
       f"Scripts/lib/env.sh SYLVIA_XCODE_BUILD_PINNED: {pinned.group(1) if pinned else 'not found'}")
inventory = read("Docs/Licenses/inventory.json")
report('"27A9275"' in inventory or "27A9275" in json.dumps(json.loads(inventory).get("toolchain", {})),
       "Docs/Licenses/inventory.json's toolchain names 27A9275")
report("27A9275" in read(".github/workflows/ci.yml"), ".github/workflows/ci.yml's Xcode guard names 27A9275")
claude_toolchain = next((l for l in read("CLAUDE.md").splitlines() if l.startswith("- Xcode 27.1 (27A9275)")), "")
report(bool(claude_toolchain), "CLAUDE.md's toolchain line begins 'Xcode 27.1 (27A9275)'")
version = run("xcodebuild", "-version")
report("Build version 27A9275" in version, f"xcodebuild -version: {' '.join(version.split())}")

print()
print("== 2. What the notes state, against the records and the build Mac")
swift_row = next((l for l in adr1.splitlines() if l.startswith("| Swift compiler |")), "")
report("Apple Swift 6.4" in swift_row, f"ADR-0001's Swift row: {swift_row[:80]}")
swift = run("xcrun", "swift", "--version")
report("Apple Swift version 6.4" in swift, f"xcrun swift --version: {swift.splitlines()[0] if swift else '(none)'}")
sdk_row = next((l for l in adr1.splitlines() if l.startswith("| SDKs |")), "")
report("iOS 27.1" in sdk_row, f"ADR-0001's SDK row: {sdk_row[:80]}")
sdks = run("xcodebuild", "-showsdks")
report(bool(re.search(r"-sdk iphoneos27\.1\b", sdks)), "xcodebuild -showsdks lists iphoneos27.1")
host_row = next((l for l in adr1.splitlines() if l.startswith("| Build host |")), "")
product = run("sw_vers", "-productVersion").strip()
build = run("sw_vers", "-buildVersion").strip()
parts = [int(x) for x in product.split(".")[:2]] if re.match(r"^\d+\.\d+", product) else [0, 0]
report(parts >= [26, 6], f"the build Mac's macOS {product} ({build}) meets macOS Tahoe 26.6 or later")
report(f"macOS {product} ({build})" in host_row, f"ADR-0001's build host row: {host_row[:80]}")

print()
print("== 3. The known issues, against the repository")
manifests = run("git", "ls-files", "--", "Apps/*project.yml", "Packages/*Package.swift", "Spikes/*project.yml",
                "Spikes/*Package.swift").split()
catalyst_manifests = [m for m in manifests if re.search(r"catalyst", read(m), re.I)]
report(not catalyst_manifests, f"no project.yml or Package.swift of Apps/, Packages/ or Spikes/ ({len(manifests)} "
       f"read) names Mac Catalyst{': ' + ', '.join(catalyst_manifests) if catalyst_manifests else ''}")
catalyst_files = [f for f in run("git", "grep", "-l", "-i", "catalyst").split()
                  if not f.startswith(("Docs/ADRs/0001-", "Docs/Stage0/"))]
report(catalyst_files == ["Scripts/check-dependency-lock.py"],
       f"tracked files outside the records that name Mac Catalyst: {', '.join(catalyst_files) or 'none'} (the "
       "dependency check counts it as iOS when it reads a target's platforms)")
duo = run("git", "grep", "-l", "-i", "iphone duo", "--", "Scripts", "Apps", "Packages", "Spikes").split()
report(not duo, f"no drop-in, app, package or spike names an iPhone Duo simulator{': ' + ', '.join(duo) if duo else ''}")

print()
print("== 4. The records carry the relay, with the confirmation pending")
open_item = next((l for l in adr1.splitlines() if l.startswith("- Technical lead, before or with the pin's confirmation")),
                 "")
report("Apple's pages were read by the orchestrating session that day and relayed" in open_item
       and "what remains is the technical lead's confirmation" in open_item,
       "ADR-0001's open item records the relay and leaves the confirmation pending")
status = next((l for l in adr1.splitlines() if l.startswith("- **Status:**")), "")
report("relayed, show 27A9275 as the release build" in status and "technical-lead confirmation pending the M0 gate"
       in status and "the technical lead's confirmation is still pending" in status,
       "ADR-0001's status line records the relay, and the confirmation as pending")
report("xcode-27.1-release.md" in adr1, "ADR-0001's Evidence cites the relay's file")
step7 = next((l for l in gate.splitlines() if l.startswith("7. **As technical lead, read Apple's release notes")), "")
report("relayed them" in step7 and "What remains yours is the confirmation" in step7,
       "the gate summary's item 1, step 7, records the relay and leaves the confirmation to the owner")
confirmed = re.findall(r"[^.]*\b(?:confirmed|confirms) that 27A9275 is the release[^.]*\.", adr1 + gate)
report(not confirmed, "neither record says the technical lead has confirmed it"
       + (f": {confirmed[0][:120]}" if confirmed else ""))

print()
print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
sys.exit(1 if problems else 0)
