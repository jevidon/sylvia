#!/bin/zsh -f
# M0 device runbook, Session 0.8: what zsh (the macOS default shell, which the owner uses) reports for a
# command run by caffeinate whose output goes through tee. A stand-in for the CI drop-in exits with 3.
# Nothing is written anywhere: tee writes to /dev/null. Environment: host (macOS).
#
#   /bin/zsh -f Docs/Stage0/evidence/M0-runbook/commands/zsh-exit-status.zsh

caffeinate -i /bin/sh -c 'exit 3' | tee /dev/null
statuses=(${pipestatus[@]})
echo "pipestatus after 'caffeinate -i sh -c exit-3 | tee': ${statuses[*]} (the first is the stand-in's status)"

caffeinate -i /bin/sh -c 'exit 3' | tee /dev/null
echo "status of the same pipeline (\$?): $? (the status of tee)"

setopt pipefail
caffeinate -i /bin/sh -c 'exit 3' | tee /dev/null
echo "status of the same pipeline with setopt pipefail: $?"
