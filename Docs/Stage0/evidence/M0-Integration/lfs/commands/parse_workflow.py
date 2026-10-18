"""Parses .github/workflows/ci.yml with PyYAML (run with the tools virtualenv's python) and prints its checkout step,
its triggers and its steps, to show that the Git LFS change kept the workflow valid, manual-dispatch only, and with
the Xcode guard in place.

    ~/Library/Caches/SylviaTools/venv/bin/python -I parse_workflow.py .github/workflows/ci.yml
"""
import json
import sys

import yaml

d = yaml.safe_load(open(sys.argv[1]))
print(json.dumps(d['jobs']['ci']['steps'][0]))
on = d.get('on', d.get(True))
print('triggers:', list(on.keys()))
print('steps:', [s.get('name', s.get('uses')) for s in d['jobs']['ci']['steps']])
