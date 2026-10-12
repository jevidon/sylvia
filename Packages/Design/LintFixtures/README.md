# Lint samples for Scripts/lint-design.py

`Scripts/lint-design.py self-test` lints these files as if they were in a product UI target.
Every line of a file under `violating/` that carries a `lint-expect: <rule>` comment must produce
exactly that finding, and nothing else may be reported; a `.colorset` must produce `color-asset`;
files under `clean/` must produce no finding. These are samples, not compiled code: no target
includes this directory.
