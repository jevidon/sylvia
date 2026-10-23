#!/usr/bin/env python3
"""Applies the shared-file changes this job requests of other owners to copies, never to the files themselves, so the
checks those files feed can be run as they will stand once the owners apply them (the lock harness, PO-23 option (b),
22 October 2026). The same old and new texts are in the job's shared_changes_requested.

    apply-requested.py <repository root> <output directory>

Writes, under the output directory:
  runbook/M0-device-runbook.md   the device runbook with Session 6's step 6.1 replaced by requested/runbook-6.1.md
                                 (G0.5 recovery step 3 now uses the lock harness) and its times and Section 1.5 note
  tree/                          a copy of every tracked file (no .git) with Docs/Licenses/inventory.json and
                                 Docs/Licenses/third-party-inventory.md registering the harness's lock
Each change must match its old text exactly once, or the script stops: a request that no longer fits its file fails.
Standard library only; reads the repository and writes only under the output directory.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
HERE = Path(__file__).resolve().parent


def replace_once(text: str, old: str, new: str, where: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"{where}: the old text occurs {count} times: {old[:120]!r}")
    print(f"{where}: replaced {old[:100]!r}")
    return text.replace(old, new)


def runbook_changes(text: str) -> str:
    where = "Docs/Stage0/M0-device-runbook.md"
    start = text.index("**6.1 Writes continue while locked** (G0.5 recovery step 3, T50;")
    end = text.index("**6.2 Keychain while locked**")
    new_61 = (HERE / "requested" / "runbook-6.1.md").read_text(encoding="utf-8")
    print(f"{where}: replaced step 6.1 ({end - start} characters) with requested/runbook-6.1.md ({len(new_61)} characters)")
    text = text[:start] + new_61.rstrip("\n") + "\n\n" + text[end:]
    text = replace_once(
        text,
        "### Session 6 · AI and recovery on phone B and the Mac (about 1 h; live AI 1.5 h more; the gateway 30 min until correction C49 is accepted)",
        "### Session 6 · AI and recovery on phone B and the Mac (about 1 h 15 min; live AI 1.5 h more; the gateway 30 min until correction C49 is accepted)",
        where)
    text = replace_once(
        text,
        "| 1 h (live AI: 1.5 h more; 8: 30 min) |",
        "| 1 h 15 min (live AI: 1.5 h more; 8: 30 min) |",
        where)
    text = replace_once(
        text,
        "| G0.5 recovery | 3 and 4, as 6.1 and 6.3's recovery items | M1 | 35 min |",
        "| G0.5 recovery | 3 and 4, as 6.1 and 6.3's recovery items | M1 | 50 min |",
        where)
    text = replace_once(
        text,
        "Whether `xcodebuild test` signs it for the phone is only known when Session 1 runs it.",
        "Whether `xcodebuild test` signs it for the phone is only known when Session 1 runs it. Its lock harness (an app, "
        "since 22 October 2026; 6.1) builds for a generic iOS device and signs with what is on the Mac "
        "([record](evidence/M0-Decisions/harness/harness-checks-clean/harness-device-signing.txt)).",
        where)
    return text


LOCK = "Spikes/G05-Recovery/LockHarness/Package.resolved"


def inventory_changes(text: str) -> str:
    where = "Docs/Licenses/inventory.json"
    text = replace_once(
        text,
        '    {"path": "Spikes/G05-Recovery/Package.resolved", "manifest": "Spikes/G05-Recovery/Package.swift"}\n',
        '    {"path": "Spikes/G05-Recovery/Package.resolved", "manifest": "Spikes/G05-Recovery/Package.swift"},\n'
        '    {"path": "Spikes/G05-Recovery/LockHarness/Package.resolved", "manifest": "Spikes/G05-Recovery/LockHarness/project.yml", '
        '"note": "A copy of Spikes/G05-Recovery/Package.resolved, which sylvia_generate installs into the generated project: '
        'Xcode writes no lock for a project whose only package is the local .. (the G0.5 recovery package). Committed for the '
        'G0.5 recovery lock harness (PO-23 option (b), product owner, 22 October 2026; ADR-0014 request); step 13 of '
        'Scripts/ci.d/71-g05-recovery.sh checks that it pins exactly what that lock pins."}\n',
        where)
    text = replace_once(
        text,
        '"locks": ["Spikes/G05-AI/Package.resolved", "Spikes/G05-AI/ATSProbe/Package.resolved", "Spikes/G05-Recovery/Package.resolved"],',
        '"locks": ["Spikes/G05-AI/Package.resolved", "Spikes/G05-AI/ATSProbe/Package.resolved", "Spikes/G05-Recovery/Package.resolved", '
        '"Spikes/G05-Recovery/LockHarness/Package.resolved"],',
        where)
    text = replace_once(
        text,
        '"linked": "No M0 iOS app links GRDB yet (the G0.5 ATS probe apps link SylviaAI, which does not use it).',
        '"linked": "One Stage 0 iOS app links GRDB since 22 October 2026: the G0.5 recovery lock harness '
        '(Spikes/G05-Recovery/LockHarness, never shipped), through SylviaRecovery; its Debug device build loads the '
        'system\'s /usr/lib/libsqlite3.dylib and defines no sqlite3_* symbol of its own (otool and nm, '
        'Docs/Stage0/evidence/M0-Decisions/harness/checks/harness-linkage.log; linkage.sh was not run for it, so its '
        'GRDB symbols were not counted). The G0.5 ATS probe apps link SylviaAI, which does not use GRDB.',
        where)
    return text


def human_inventory_changes(text: str) -> str:
    where = "Docs/Licenses/third-party-inventory.md"
    text = replace_once(
        text,
        "iOS: recovery test bundle only (4); no M0 iOS app links it yet | MIT | G05-AI, G05-AI/ATSProbe, G05-Recovery |",
        "iOS: recovery test bundle (4), and since 22 October 2026 the G0.5 recovery lock harness app (never shipped; not "
        "measured) | MIT | G05-AI, G05-AI/ATSProbe, G05-Recovery, G05-Recovery/LockHarness |",
        where)
    text = replace_once(
        text,
        "`Spikes/G05-AI/ATSProbe`, `Spikes/G05-Recovery`, each `Package.resolved` beside its manifest.",
        "`Spikes/G05-AI/ATSProbe`, `Spikes/G05-Recovery`, `Spikes/G05-Recovery/LockHarness`, each `Package.resolved` beside "
        "its manifest.",
        where)
    text = replace_once(
        text,
        "when their exemptions below were removed.",
        "when their exemptions below were removed. The G0.5 recovery lock harness's lock (`Spikes/G05-Recovery/LockHarness`, "
        "22 October 2026) is a copy of `Spikes/G05-Recovery`'s for the same reason.",
        where)
    text = replace_once(
        text,
        "| Other project files (G01-PDF, G02 iOS and MacIdentityProbe, G03 App, G05 ATSProbe) and `ZipEval/Common` | none remote | |",
        "| Other project files (G01-PDF, G02 iOS and MacIdentityProbe, G03 App, G05 ATSProbe, G05 recovery LockHarness) and "
        "`ZipEval/Common` | none remote | |",
        where)
    return text


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "runbook").mkdir(parents=True)
    runbook = (ROOT / "Docs/Stage0/M0-device-runbook.md").read_text(encoding="utf-8")
    (OUT / "runbook" / "M0-device-runbook.md").write_text(runbook_changes(runbook), encoding="utf-8")

    listed = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, check=True).stdout
    tree = OUT / "tree"
    copied = 0
    for rel in (p for p in listed.decode("utf-8").split("\0") if p):
        source = ROOT / rel
        if not source.is_file() and not source.is_symlink():
            continue
        target = tree / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_symlink():
            target.symlink_to(source.readlink())
        else:
            shutil.copy2(source, target)
        copied += 1
    print(f"tree: copied {copied} tracked files into {tree.relative_to(ROOT) if tree.is_relative_to(ROOT) else tree}")
    inventory = tree / "Docs/Licenses/inventory.json"
    inventory.write_text(inventory_changes(inventory.read_text(encoding="utf-8")), encoding="utf-8")
    human = tree / "Docs/Licenses/third-party-inventory.md"
    human.write_text(human_inventory_changes(human.read_text(encoding="utf-8")), encoding="utf-8")


if __name__ == "__main__":
    main()
