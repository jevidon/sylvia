#!/bin/bash
# The GitHub workflow's Xcode guard after the re-pin to Xcode 27.1 (27A9275), checked on the build Mac without GitHub
# (the workflow runs only on manual dispatch, and no agent dispatches it). Takes the guard step's run script out of
# .github/workflows/ci.yml with PyYAML (commands/workflow-guard.py) and runs exactly that text with bash, as the
# runner's shell would (`bash -e {0}`, the script setting -euo pipefail itself), three times, each with its own
# GITHUB_ENV file:
#   1. as this Mac is: /Applications/Xcode.app is 27.1 (27A9275), so the guard must pass and write that DEVELOPER_DIR;
#   2. a runner with another Xcode: a stand-in `xcodebuild` first on PATH prints Xcode 27.0's version lines, so the
#      guard must fail with exit 1, print its error naming 27.1 (27A9275), and write nothing to GITHUB_ENV;
#   3. a build whose number only contains the pinned one ("27A9275a", made up): the guard compares the whole line,
#      so it must fail too.
# Read-only apart from its scratch folder (.build/scratch/workflow-guard-check), which it removes.
#
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/workflow-guard-check.sh > <log> 2>&1
set -uo pipefail
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
here=Docs/Stage0/evidence/M0-Integration/repin-27.1
scratch="$root/.build/scratch/workflow-guard-check"
rm -rf "$scratch"; mkdir -p "$scratch/stub-27.0" "$scratch/stub-contains"
echo "command: $here/commands/workflow-guard-check.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "== the workflow parses (PyYAML from the tools virtualenv), and its guard step"
"$SYLVIA_TOOLS_VENV/bin/python" -I "$here/commands/workflow-guard.py" .github/workflows/ci.yml > "$scratch/guard.sh"
parse=$?
echo "parse exit status: $parse"
echo "-- the guard's run script, as the workflow holds it:"
sed 's/^/   | /' "$scratch/guard.sh"
status=0
(( parse == 0 )) || status=1

printf '#!/bin/bash\nprintf "Xcode 27.0\\nBuild version 27A266a\\n"\n' > "$scratch/stub-27.0/xcodebuild"
printf '#!/bin/bash\nprintf "Xcode 27.1\\nBuild version 27A9275a\\n"\n' > "$scratch/stub-contains/xcodebuild"
chmod +x "$scratch/stub-27.0/xcodebuild" "$scratch/stub-contains/xcodebuild"

run_case() {  # label, expected exit status, PATH prefix ("" for none)
  local label="$1" want="$2" prefix="$3" env_file="$scratch/github_env.$RANDOM" got
  : > "$env_file"
  echo
  echo "== $label (expected exit status $want)"
  if [[ -n "$prefix" ]]; then
    PATH="$prefix:$PATH" GITHUB_ENV="$env_file" bash "$scratch/guard.sh" 2>&1 | sed 's/^/   /'
    got=${PIPESTATUS[0]}
  else
    GITHUB_ENV="$env_file" bash "$scratch/guard.sh" 2>&1 | sed 's/^/   /'
    got=${PIPESTATUS[0]}
  fi
  echo "exit status: $got; GITHUB_ENV: $(cat "$env_file" | tr '\n' ' ')"
  if [[ "$got" == "$want" ]]; then echo "as expected"; else echo "NOT as expected"; status=1; fi
  if [[ "$want" == 0 && "$(cat "$env_file")" != "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" ]]; then
    echo "NOT as expected: the guard did not write the selected DEVELOPER_DIR"; status=1
  fi
  if [[ "$want" != 0 && -s "$env_file" ]]; then
    echo "NOT as expected: a failed guard wrote to GITHUB_ENV"; status=1
  fi
}
run_case "1. this Mac (Xcode 27.1, 27A9275)" 0 ""
run_case "2. a runner whose Xcode is 27.0 (27A266a): stand-in xcodebuild" 1 "$scratch/stub-27.0"
run_case "3. a build number that only contains the pinned one (27A9275a, made up): stand-in xcodebuild" 1 "$scratch/stub-contains"
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
