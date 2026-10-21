"""Parses .github/workflows/ci.yml with PyYAML (run with the tools virtualenv's python) and prints the run script of its
Xcode guard step, "Select pinned Xcode (ADR-0001)", so workflow-guard-check.sh can run exactly that text; also prints
the workflow's triggers and step names to stderr, to show the file still parses, runs only on manual dispatch and has
its guards before the checkout. Read-only.

    ~/Library/Caches/SylviaTools/venv/bin/python -I workflow-guard.py .github/workflows/ci.yml > guard.sh
"""
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    d = yaml.safe_load(f)
steps = d["jobs"]["ci"]["steps"]
on = d.get("on", d.get(True))
print("triggers: %s" % list(on.keys()), file=sys.stderr)
print("steps: %s" % [s.get("name", s.get("uses")) for s in steps], file=sys.stderr)
guard = [s for s in steps if s.get("name") == "Select pinned Xcode (ADR-0001)"]
if len(guard) != 1:
    sys.exit("the Xcode guard step was not found exactly once")
print("guard step position: %d of %d (the checkout is step %d)" % (
    steps.index(guard[0]) + 1, len(steps),
    [i for i, s in enumerate(steps) if str(s.get("uses", "")).startswith("actions/checkout@")][0] + 1), file=sys.stderr)
sys.stdout.write(guard[0]["run"])
