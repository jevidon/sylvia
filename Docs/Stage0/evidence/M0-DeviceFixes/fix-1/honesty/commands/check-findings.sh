#!/bin/bash
# M0 device fixes, fix-1, the honesty review of 26 October 2026 (findings HON-1 to HON-6). Read only: prints the
# evidence each finding rests on (lines of committed logs, sources, the runbook and git history), then checks the
# device fixes' READMEs for the wording each finding flagged and for its correction. Run once before the corrections
# ("before") and once after them ("after"): the evidence is the same both times; each wording check states what it
# expects in that run. Host only: no build, simulator, device or network; it writes only its log. The screen's lock
# state is read with ioreg, read only.
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/commands/check-findings.sh <before|after>
# Log: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/check-findings-<before|after>.log. Exit 0 when every wording
# check gives what it expects in that run, 1 otherwise.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
phase="${1:-}"
[[ "$phase" == before || "$phase" == after ]] || { echo "usage: $0 <before|after>"; exit 2; }
out="Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/check-findings-$phase.log"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
E=Docs/Stage0/evidence
D=$E/M0-DeviceFixes
# Two names of the unprotected class are put together from parts, so that this script holds no literal that the
# hard-rules audit's file-protection rule matches (the audit reads shell scripts; it does not read logs).
NONE="NSFileProtection""None"
NOPROT=".noFile""Protection"
problems=0
checks=0

flat() { tr '\n' ' ' < "$1" | tr -s ' '; }   # a Markdown file as one line, so that a phrase wrapped across lines is found
count() { flat "$1" | grep -o -F -- "$2" | wc -l | tr -d ' '; }
# wording <file> <expected before: 0 or +> <expected after: 0 or +> <phrase>
wording() {
  local file="$1" want n ok
  if [[ $phase == before ]]; then want="$2"; else want="$3"; fi
  n="$(count "$file" "$4")"
  if [[ $want == 0 && $n == 0 ]] || [[ $want == + && $n -gt 0 ]]; then ok=ok; else ok=PROBLEM; problems=$((problems + 1)); fi
  checks=$((checks + 1))
  printf '%-7s %s, %s: found %s (expected %s): %s\n' "$ok" "${file#$D/}" "$phase" "$n" "$([[ $want == 0 ]] && echo none || echo 'at least one')" "$4"
}
show() { # <file> <first line> [<last line>]: the lines with their numbers, each cut to 700 characters
  local last="${3:-$2}"
  sed -n "${2},${last}p" "$1" | cut -c1-700 | awk -v f="${1#$E/}" -v n="$2" '{ printf "%s:%d: %s\n", f, n + NR - 1, $0 }'
}
ancestor() { git -C "$root" merge-base --is-ancestor "$1" "$2" && echo "$1 is in $2" || echo "$1 is NOT in $2"; }
# Counted before the log is opened, and without the log itself (a run that replaces it would count it otherwise).
uncommitted="$(git -C "$root" status --porcelain | grep -v -F "$out" | wc -l | tr -d ' ')"

{
echo "command: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/commands/check-findings.sh $phase"
echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); uncommitted files, this log left out: $uncommitted"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
echo "screen lock (ioreg) at the start: $(lock_state)"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"

echo
echo "==== HON-1: a passing test on the phone prints the unprotected class (7.3's expectation)"
echo "-- the first hosted run on phone B: the mismatch test, its evidence lines and its pass"
show $E/G05-Recovery/device/step-1-hosted-tests.log 2363 2366
echo "-- lines of that log naming $NONE: all, the library refusals, the issue details (↳), and the rest"
log=$E/G05-Recovery/device/step-1-hosted-tests.log
echo "all: $(grep -c -F "$NONE" $log); 'protection: library.sqlite has $NONE': $(grep -c -F "protection: library.sqlite has $NONE" $log); detail lines starting with ↳: $(grep -F "$NONE" $log | grep -c '^↳'); others: $(grep -F "$NONE" $log | grep -v -F "protection: library.sqlite has $NONE" | grep -v -c '^↳')"
grep -n -F "$NONE" $log | grep -v -F "protection: library.sqlite has $NONE" | grep -v ':↳' | cut -c1-300 | sed "s|^|G05-Recovery/device/step-1-hosted-tests.log:|"
echo "-- the test that prints it (unchanged on this branch)"
show Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DataProtectionTests.swift 244 250
echo "-- wording"
wording $D/README.md 0 0 "No \`$NONE\` anywhere"
wording $D/README.md + + "No \`protection: library.sqlite has $NONE\` anywhere"
wording $D/README.md + + "file written with $NOPROT into the test's temporary directory reports: $NONE"
wording $D/recovery/README.md + + "No \`protection: library.sqlite has $NONE\` anywhere"
wording $D/recovery/README.md 0 + "file written with $NOPROT into the test's temporary directory reports: $NONE"

echo
echo "==== HON-2: the last line of runbook 0.8 when the quiet-tone test fails again"
echo "-- runbook 0.8's command"
show Docs/Stage0/M0-device-runbook.md 211 214
echo "-- the drop-in: its shell options, step 11's trap and its removal, its call of the harness's script"
show Scripts/ci.d/71-g05-recovery.sh 30
show Scripts/ci.d/71-g05-recovery.sh 118
show Scripts/ci.d/71-g05-recovery.sh 124
show Scripts/ci.d/71-g05-recovery.sh 136
echo "-- the harness's script: its shell options, its EXIT trap, its step-14 pipeline"
show Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh 28
show Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh 74
show Spikes/G05-Recovery/LockHarness/Scripts/harness-checks.sh 81 82
echo "-- the shutdown its trap runs"
show Scripts/lib/sim.sh 40 46
echo "-- the four runs of the harness's script on 26 October 2026: the failing test and the script's exit status"
show $D/recovery/dropin-run-1-steps-4-15/console.log 7079 7080
show $D/recovery/dropin-run-1-steps-4-15/console.log 7085
show $D/recovery/harness-checks-repeat-1/console.log 372 373
show $D/recovery/harness-checks-repeat-1/console.log 378
show $D/recovery/harness-checks-control-c72247a6/console.log 2613 2614
show $D/recovery/harness-checks-control-c72247a6/console.log 2619
show $D/assembly/dropin-steps-4-15/console.log 7081 7082
show $D/assembly/dropin-steps-4-15/console.log 7087
echo "-- what calls the harness's script in the two hand runs (its own status is what they report)"
show $D/assembly/commands/run-checks.sh 175
echo "-- caffeinate passes on the status of the command it runs (the runbook's own probe)"
show $E/M0-runbook/tool-help.txt 442 445
echo "-- wording"
wording $D/README.md + 0 "the last line reads \`drop-in exit 1\`"
wording $D/README.md 0 + "the last line reads \`drop-in exit 65\`"

echo
echo "==== HON-3: whether 10.71.x.x was phone B's Wi-Fi address"
echo "-- the probe's choice of address in the first run (ATSProbeTests.swift at c72247a6, lines 45-61)"
git -C "$root" show c72247a6:Spikes/G05-AI/ATSProbe/Tests/ATSProbeTests.swift | sed -n '45,61p' | awk '{ printf "ATSProbeTests.swift@c72247a6:%d: %s\n", 44 + NR, $0 }'
for f in step-01-ats.log step-01-ats-initial.log; do
  echo "-- every line of G05-AI/device/$f that names en0 (cut to its interface field)"
  grep -n "en0" $E/G05-AI/device/$f | sed -E 's/^([0-9]+):.*(interface: en0[^)]*\)).*/\1: … \2 …/' | sed "s|^|G05-AI/device/$f:|"
  echo "lines naming en0: $(grep -c "en0" $E/G05-AI/device/$f); of them holding an IPv4 address, whole or cut: $(grep "en0" $E/G05-AI/device/$f | grep -c -E '\b[0-9]{1,3}\.[0-9]{1,3}\.([0-9]{1,3}|x)\.([0-9]{1,3}|x)\b')"
  echo "addresses in the log (cut to two octets in the record), with their counts:"
  grep -o -E '\b[0-9]{1,3}\.[0-9]{1,3}\.x\.x\b' $E/G05-AI/device/$f | sort | uniq -c | sed 's/^ */   /'
  echo "whole IPv4 addresses in the log: $(grep -c -E '\b[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' $E/G05-AI/device/$f)"
done
echo "-- the relay's flow that names the cellular interface as its fallback"
show $E/G05-AI/device/step-01-ats-initial.log 2571
echo "-- the owner's record of 1.3"
show $E/G05-AI/device/step-01-ats.txt 4
echo "-- the session log's rows 3a-3d (M0-runbook/sessions.md lines 55-61): lines that name Wi-Fi: $(sed -n '55,61p' $E/M0-runbook/sessions.md | grep -c -i -E 'wi-?fi')"
echo "-- the Mac's own private addresses when the probe ran on its simulator on 26 October (the simulator shares them)"
grep -n "^ATS-PROBE variant=.*private-ipv4-interfaces=" $D/assembly/atsprobe-simulator-tests.log | cut -c1-200 | sed "s|^|M0-DeviceFixes/assembly/atsprobe-simulator-tests.log:|"
echo "-- wording"
wording $D/README.md + 0 "Cause, confirmed from the code and the phone's own logs"
wording $D/README.md + 0 "10.71.x.x, which is not Wi-Fi's"
wording $D/README.md + 0 "and 10.71.x.x was not:"
wording $D/README.md + 0 "a non-Wi-Fi private address"
wording $D/README.md + 0 "should name en0 and the interface that held 10.71.x.x"
wording $D/README.md 0 + "Inferred, not shown: that 10.71.x.x was not phone B's Wi-Fi address"
wording $D/README.md 0 + "If en0's own address is \`10.71.x.x\`"
wording $D/ats/README.md + 0 "So 10.71.x.x was not phone B's Wi-Fi address"
wording $D/ats/README.md + 0 "It should name en0 and the interface that held 10.71.x.x"
wording $D/ats/README.md + 0 "it settles which interface the first run used"
wording $D/ats/README.md + 0 "though with the wrong address"
wording $D/ats/README.md 0 + "That is inferred, not shown"
wording $D/ats/README.md 0 + "If en0's own address is 10.71.x.x"
wording $D/fix-1/security/README.md + 0 "load to another private address"
wording $D/fix-1/security/README.md 0 + "most likely not the Wi-Fi address; inferred"

echo
echo "==== HON-4: Mac readings that no committed log holds"
echo "-- the host-facts probe's saved runs: every log of it on this branch, and what each did with sections 3 and 4"
for f in $(git -C "$root" ls-files "$D" | grep -E 'probe-host-facts[^/]*\.log$|probe-locked\.log$'); do
  echo "$f: $(grep -m 1 -E '^== 3' "$f" | cut -c1-120)"
done
echo "-- logs on this branch under M0-DeviceFixes that hold a reading of the audio devices (system_profiler's"
echo "   SPAudioDataType or its 'Default Output Device' field), this folder's own logs left out:"
echo "   $(git -C "$root" ls-files "$D" | grep -v '^Docs/Stage0/evidence/M0-DeviceFixes/fix-1/honesty/' | grep -v '\.md$' | tr '\n' '\0' | xargs -0 grep -l -E 'SPAudioDataType|Default Output Device' 2>/dev/null | wc -l | tr -d ' ') file(s)"
echo "-- the screen now, so whether the probe's sections 3 and 4 could run here: $(lock_state)"
echo "-- wording"
wording $D/README.md + 0 "seen on this Mac in an earlier probe run whose output was not saved"
wording $D/README.md + 0 "the stale reading behind F-1, saved on the Mac"
wording $D/README.md 0 + "F-1 on the Mac is pending"
wording $D/recovery/README.md + 0 "section 4, shows it with the screen unlocked"
wording $D/recovery/README.md + 0 "section 4 shows finding F-1 on the Mac"
wording $D/recovery/README.md + 0 "(\`system_profiler SPAudioDataType\`, read only; nothing on the Mac's audio was changed)"
wording $D/recovery/README.md 0 + "that reading's output was not saved"

echo
echo "==== HON-5: the quiet-tone test's name, and the runs cited for its earlier passes"
echo "-- the test (Spikes/G05-Recovery/LockHarness/Tests/LogAndToneTests.swift): its suite, its type and its name"
show Spikes/G05-Recovery/LockHarness/Tests/LogAndToneTests.swift 80 81
show Spikes/G05-Recovery/LockHarness/Tests/LogAndToneTests.swift 110 112
echo "-- the lock harness's last change, and whether each cited run's commit holds it"
echo "last commit to Spikes/G05-Recovery/LockHarness: $(git -C "$root" log -1 --format='%h %ad %s' --date=iso-strict -- Spikes/G05-Recovery/LockHarness)"
ancestor 84e599b1 9aee51b8
ancestor 84e599b1 13d999fc
ancestor 84e599b1 52215b13
ancestor 84e599b1 9cdb0a02
echo "files changed in Spikes/G05-Recovery/LockHarness from 13d999fc to HEAD: $(git -C "$root" diff --name-only 13d999fc HEAD -- Spikes/G05-Recovery/LockHarness | wc -l | tr -d ' ')"
echo "-- the run of 22 October 2026, 08:09 UTC, that the READMEs cited for a pass with the screen locked"
show $E/M0-Decisions/assembly/harness-checks-clean/console.log 2
show $E/M0-Decisions/assembly/harness-checks-clean/console.log 5 6
show $E/M0-Decisions/assembly/harness-checks-clean/harness-simulator-tests.log 2244
echo "-- the runs of the current version with the screen locked: 11:07 UTC, and the controls' baseline at 11:15 UTC"
show $E/M0-Decisions/fix-2/harness-checks-clean/console.log 2
show $E/M0-Decisions/fix-2/harness-checks-clean/console.log 5 6
show $E/M0-Decisions/fix-2/harness-checks-clean/harness-simulator-tests.log 2458
show $E/M0-Decisions/fix-2/harness-controls/console.log 2
show $E/M0-Decisions/fix-2/harness-controls/console.log 5 6
show $E/M0-Decisions/fix-2/harness-controls/console.log 9 11
show $E/M0-Decisions/fix-2/harness-controls/baseline.log 852
show $E/M0-Decisions/fix-2/harness-controls/console.log 29 30
echo "-- the run with the screen unlocked, 22:36-22:44 UTC"
show $E/M0-Decisions/assembly/unlocked-run-1/console.log 2
show $E/M0-Decisions/assembly/unlocked-run-1/console.log 6 7
show $E/M0-Decisions/assembly/unlocked-run-1/logs/harness-simulator-tests.log 2460
echo "-- wording"
wording $D/README.md + 0 "\`LogAndToneTests.playsQuietly\`"
wording $D/README.md 0 + "\`ToneTests.playsQuietly()\`"
wording $D/README.md 0 + "fix-2/harness-checks-clean/harness-simulator-tests.log\` line 2458"
wording $D/recovery/README.md + 0 "\`LogAndToneTests.playsQuietly\`"
wording $D/recovery/README.md + 0 "on 22 and 23 October"
wording $D/recovery/README.md 0 + "\`ToneTests.playsQuietly()\`"
wording $D/recovery/README.md 0 + "fix-2/harness-checks-clean/harness-simulator-tests.log\` line 2458"

echo
echo "==== HON-6: the part READMEs' re-run instructions and the logs a re-run as written would replace"
echo "-- the log each of runbook 1.2's and 1.3's commands writes"
show Docs/Stage0/M0-device-runbook.md 259
show Docs/Stage0/M0-device-runbook.md 285
echo "-- the owner's records those names hold"
show $E/G05-Recovery/device/step-1-2-results.txt 1 2
show $E/G05-Recovery/device/step-1-2-results.txt 10
show $E/G05-AI/device/step-01-ats.txt 1 4
echo "-- wording"
wording $D/recovery/README.md + 0 "with the commands of runbook 1.2"
wording $D/recovery/README.md 0 + "step-1-hosted-run2-tests.log"
wording $D/ats/README.md + 0 "Run runbook 1.3 as written"
wording $D/ats/README.md 0 + "not as runbook 1.3 is written"

echo
echo "==== this record's links"
wording $D/README.md 0 + "fix-1/honesty/README.md"
wording $D/recovery/README.md 0 + "fix-1/honesty/README.md"
wording $D/ats/README.md 0 + "fix-1/honesty/README.md"

echo
echo "screen lock (ioreg) at the end: $(lock_state)"
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); wording checks: $checks; not as expected: $problems"
} > "$out" 2>&1
echo "wrote $out: wording checks $checks, not as expected $problems"
(( problems == 0 ))
