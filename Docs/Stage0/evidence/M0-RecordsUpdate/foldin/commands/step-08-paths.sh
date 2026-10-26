#!/bin/bash
# Runbook 0.8 after the fold-in of m0-device-fixes into m0-records-update (27 October 2026; integration log section 45):
# a new version of Docs/Stage0/evidence/M0-RecordsUpdate/commands/step-08-paths.sh, which expects nothing the drop-in
# builds, copies or runs to have changed since 9cdb0a02 and so fails on this tree by design. The paths are that
# script's, read from Scripts/ci.d/71-g05-recovery.sh and the two files it runs that name further paths: the drop-in,
# Scripts/lib, Scripts/tools, Spikes/G05-Recovery (the package and its lock harness) and the backup-manifest contract
# and fixtures, Spikes/G05-Recovery/DeviceTests set apart, as runbook 0.8's command sets it apart.
#   Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands/step-08-paths.sh > <log>
# It prints runbook 0.8's command from 9cdb0a02 to 6a510880 (m0-records-update before the fold-in), to a60aa922
# (m0-device-fixes) and to HEAD, and requires: no change to 6a510880 (as m0-records-update's checks found); and, to
# a60aa922 and to HEAD, exactly the eleven files of the recovery package's Sources and Tests that the device fixes
# changed, each as a60aa922 has it at HEAD, so 0.8 runs again on that code; and no file the drop-in or the lock
# harness's checks run naming DeviceTests. Exit 1 otherwise. Read-only.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
before=6a510880c34f7936c972b6ace9a18c126ecab13d
fixes=a60aa92274d209bff6e1727ed36c078cd94ed8b2
paths=(Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery
       Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1)
expected="Spikes/G05-Recovery/Sources/SylviaRecovery/Backup/Container.swift
Spikes/G05-Recovery/Sources/SylviaRecovery/FileProtection.swift
Spikes/G05-Recovery/Sources/SylviaRecovery/FileSystem.swift
Spikes/G05-Recovery/Sources/SylviaRecovery/MigrationCrashDrill.swift
Spikes/G05-Recovery/Sources/SylviaRecovery/RestoreCrashDrill.swift
Spikes/G05-Recovery/Tests/SylviaRecoveryTests/BackupTests.swift
Spikes/G05-Recovery/Tests/SylviaRecoveryTests/MigrationTests.swift
Spikes/G05-Recovery/Tests/SylviaRecoveryTests/PrivatePathTests.swift
Spikes/G05-Recovery/Tests/SylviaRecoveryTests/ProtectedCopyTests.swift
Spikes/G05-Recovery/Tests/SylviaRecoveryTests/PutBackTests.swift
Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Support.swift"
status=0
echo "step-08-paths (fold-in): HEAD $(git rev-parse HEAD), uncommitted paths: $(git status --porcelain | wc -l | tr -d ' '); $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "the unlocked run's commit: $run ($(git log -1 --format='%ad' --date=iso "$run"))"
for to in "$before" "$fixes" HEAD; do
  echo
  echo "== git diff --stat $run $to -- <runbook 0.8's paths> ':(exclude)Spikes/G05-Recovery/DeviceTests'"
  git diff --stat "$run" "$to" -- "${paths[@]}" ':(exclude)Spikes/G05-Recovery/DeviceTests' | cat
  names="$(git diff --name-only "$run" "$to" -- "${paths[@]}" ':(exclude)Spikes/G05-Recovery/DeviceTests')"
  if [[ "$to" == "$before" ]]; then
    [[ -z "$names" ]] && echo "ok    nothing changed at $to: before the fold-in, 0.8 needed nothing" \
      || { echo "PROBLEM: changes at $to"; status=1; }
  else
    [[ "$names" == "$expected" ]] && echo "ok    exactly the eleven files of the recovery package that the device fixes changed: 0.8 runs again" \
      || { echo "PROBLEM: not the expected eleven files"; status=1; }
  fi
done
echo
echo "== those files at HEAD, as a60aa922 has them"
same="$(git diff --name-only "$fixes" HEAD -- $expected)"
[[ -z "$same" ]] && echo "ok    each is as m0-device-fixes has it" || { echo "PROBLEM: differ at HEAD: $same"; status=1; }
echo
echo "== files the drop-in runs or reads that name DeviceTests (none expected)"
hits="$(grep -l 'DeviceTests' Scripts/ci.d/71-g05-recovery.sh Scripts/lib/*.sh Spikes/G05-Recovery/Package.swift \
        Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null || true)"
if [[ -z "$hits" ]]; then echo "   none"; else echo "$hits"; echo "PROBLEM: a file the drop-in uses names DeviceTests"; status=1; fi
echo
echo "result: $( ((status == 0)) && echo "pass: row 10's class-B evidence is of the code before the device fixes; 0.8 runs again on theirs, with the screen unlocked" || echo FAIL )"
exit $status
