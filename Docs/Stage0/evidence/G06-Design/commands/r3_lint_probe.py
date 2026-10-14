"""Writes lint-r3-probe-host.log: the review round 3 (R3-01) lint probe for G0.6.

Run from anywhere in the worktree, with the tools virtualenv of ADR-0002:

    ~/Library/Caches/SylviaTools/venv/bin/python Docs/Stage0/evidence/G06-Design/commands/r3_lint_probe.py

It lints three probe trees with the lint at the integration commit b354dc7 (review round 2 rules,
read with `git show`) and with the current Scripts/lint-design.py:
  1. the R3-01 reviewer's four probe lines, verbatim;
  2. Packages/Design/LintFixtures/violating/Styles.swift (every round 3 spelling, one per marked line);
  3. spellings ADR-0013 Section 8 lists as not caught (0 findings expected from both);
and then compares both versions over every Swift file of Packages/Design (sources and tests, not
LintFixtures) and Spikes/, copied into a scratch tree under Apps/ so the lint scans them as if they
were product UI: a finding only the new rules report would be a false positive or a new true
positive in code that uses tokens (the package) or is exempt harness code (the spikes).
Scratch trees go under .build/scratch/ (gitignored).
"""
import datetime
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
SCRATCH = ROOT / ".build" / "scratch" / "r3-lint-probe"
OUT = ROOT / "Docs/Stage0/evidence/G06-Design/lint-r3-probe-host.log"
NEW = ROOT / "Scripts" / "lint-design.py"
EXPORT = "Contracts/design/marginalia.v1.json"
BASE_COMMIT = "b354dc7"

REVIEWER_PROBE = """import SwiftUI

struct Probe2: View {
    var body: some View {
        Circle().fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
        Circle().fill(Gradient(colors: [.red, .blue]))
        Text("x").listItemTint(.red)
    }
}

let q: some ShapeStyle = .red
"""

GAPS_PROBE = """import SwiftUI

// Spellings ADR-0013 Section 8 lists as not caught (review round 3): each must produce no finding.
struct Gaps: View {
    var body: some View {
        Text("x").background(.ultraThinMaterial)
        Text("x").background(.bar)
        Circle().fill(LinearGradient(colors: [ColorToken.pine.color, ColorToken.ink.color], startPoint: .top, endPoint: .bottom))
        MyView(highlights: [.red])
    }
}

let colorSet: Set<Color> = [.red, .blue]
let namesByColor: [Color: String] = [.red: "a"]
"""


def tree(name: str) -> Path:
    base = SCRATCH / name
    if base.exists():
        shutil.rmtree(base)
    (base / "Apps" / "Probe" / "Sources").mkdir(parents=True)
    return base


def lint(lint_path: Path, root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(lint_path), "lint", "--root", str(root), "--export", str(ROOT / EXPORT)],
                          capture_output=True, text=True, cwd=ROOT)


SCRATCH.mkdir(parents=True, exist_ok=True)
old = SCRATCH / f"lint-design-{BASE_COMMIT}.py"
old.write_text(subprocess.run(["git", "-C", str(ROOT), "show", f"{BASE_COMMIT}:Scripts/lint-design.py"],
                              capture_output=True, text=True, check=True).stdout, encoding="utf-8")

reviewer = tree("reviewer")
(reviewer / "Apps/Probe/Sources/Probe2.swift").write_text(REVIEWER_PROBE, encoding="utf-8")
styles = tree("styles")
source = ROOT / "Packages/Design/LintFixtures/violating/Styles.swift"
shutil.copy2(source, styles / "Apps/Probe/Sources/Styles.swift")
marked = sum("lint-expect:" in line for line in source.read_text(encoding="utf-8").split("\n"))
gaps = tree("gaps")
(gaps / "Apps/Probe/Sources/Gaps.swift").write_text(GAPS_PROBE, encoding="utf-8")

lines = [
    "# R3-01 probe: round 3 spellings linted with the review round 2 lint and with the current lint",
    f"# Environment: host, macOS {platform.mac_ver()[0]}, Python {platform.python_version()}",
    f"# Date: {datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
    "# Command: Docs/Stage0/evidence/G06-Design/commands/r3_lint_probe.py (scratch trees under .build/scratch/r3-lint-probe)",
    "# Probe 1 is the reviewer's four lines verbatim (Apps/Probe/Sources/Probe2.swift in a scratch tree);",
    f"# probe 2 is Packages/Design/LintFixtures/violating/Styles.swift ({marked} marked lines) copied to a scratch tree;",
    "# probe 3 holds spellings that ADR-0013 Section 8 lists as not caught (materials, a token gradient, a list",
    "# passed to an unnamed parameter, a Set<Color>, a dictionary keyed by colors): 0 findings expected.",
    f"# 'Before' is Scripts/lint-design.py at {BASE_COMMIT} (integration commit, review round 2 rules);",
    "# 'After' is Scripts/lint-design.py in the commit that adds this log.",
    "# Probe 3 source (Apps/Probe/Sources/Gaps.swift):",
]
lines += ["#   " + line for line in GAPS_PROBE.rstrip("\n").split("\n")]
for label, base in [("Probe 1: the reviewer's four lines", reviewer), ("Probe 2: Styles.swift", styles),
                    ("Probe 3: documented gaps", gaps)]:
    for when, lint_path in [("Before", old), ("After", NEW)]:
        shown = f"lint-design.py ({BASE_COMMIT})" if lint_path == old else "Scripts/lint-design.py"
        result = lint(lint_path, base)
        lines += ["", f"## {label}; {when}",
                  f"$ {shown} lint --root .build/scratch/r3-lint-probe/{base.name} --export {EXPORT}"]
        lines += result.stdout.rstrip("\n").split("\n")
        lines.append(f"# exit {result.returncode}")

# False-positive comparison over the package and the spikes.
corpus = SCRATCH / "corpus"
if corpus.exists():
    shutil.rmtree(corpus)
count = 0
for base in [ROOT / "Packages" / "Design", ROOT / "Spikes"]:
    for f in sorted(base.rglob("*.swift")):
        rel = f.relative_to(ROOT)
        if any(p in {".build", "DerivedData", "LintFixtures"} for p in rel.parts):
            continue
        # "Tests" directory names are renamed so the lint's test-directory exclusion does not apply.
        dest = corpus / "Apps" / Path(*[p.replace("Tests", "Tst") for p in rel.parts])
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, dest)
        count += 1
code_rules = (": named-color:", ": font-size:", ": hex-color:", ": color-")
findings = {}
for when, lint_path in [("old", old), ("new", NEW)]:
    out = lint(lint_path, corpus).stdout
    findings[when] = {line for line in out.splitlines() if any(rule in line for rule in code_rules)}
lines += ["", "## False-positive check: the new rules over Packages/Design and Spikes/",
          f"# {count} Swift files copied to .build/scratch/r3-lint-probe/corpus/Apps and linted with both versions;",
          "# the code findings (colors and font sizes) only one version reports are listed.",
          f"old lint: {len(findings['old'])} code findings; new lint: {len(findings['new'])}"]
only_new = sorted(findings["new"] - findings["old"])
only_old = sorted(findings["old"] - findings["new"])
lines.append(f"reported only by the new rules: {len(only_new)}")
lines += [f"  {line}" for line in only_new]
lines.append(f"reported only by the old rules: {len(only_old)}")
lines += [f"  {line}" for line in only_old]
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(OUT.read_text(encoding="utf-8"))
