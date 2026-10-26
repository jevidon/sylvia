#!/bin/bash
# The device runbook against the checklists, with the content check of the update of 24 October 2026 (device A, the
# product owner's iPhone 13 mini; the branch m0-sessions). The successor of
# Docs/Stage0/evidence/M0-Decisions/assembly/commands/runbook-content-check.sh, with its controls a-h and p and its
# limits i-m unchanged; its controls n, o and q (the round-2 and Stage 0 versions of the check, and plan 19.1's sentence
# on the iPhone 11 Pro changed in a copy) replaced by n, o and q below, because the update replaced that sentence's
# quotation in the runbook's 1.1 by the owner's words of 24 October 2026 in Section 6.
# Runs, read-only (copies under .build/scratch):
#   1. M0-DeviceA/instructions/commands/runbook-content-check.py on the runbook as it stands: it must pass;
#   2. controls, each of which must fail:
#      a. the runbook the round-2 review read (83ee280);
#      b. the runbook the round-3 review read (dc81fce);
#      c-e. R7-01's three mutations: 4.1's expected pairing status, 4.14's expected message for a changed Mac key, and
#         3.13's `G04Book (4 files)`; each output must name the mutated text;
#      f. a source that no longer says a runbook-only text: in a copy of the files the check reads, the client's message
#         for a changed Mac key (PartResponseValidation.swift) is changed, the runbook is not;
#      g. R8-01's case: a G0.5 AI-only text ("AI failed") added to step 0.8, whose bold heading names G0.5 recovery;
#      h. a G0.3-only text ("Received by Sylvia") added to Session 4's own text before its first step;
#      n. the assembly's version of the check (M0-Decisions/assembly/commands/runbook-content-check.py) on the runbook as
#         it stands: it must fail with exactly the three problems the update explains (the owner's words and the option
#         chosen, quoted in Section 6's D-1, unlisted; plan 19.1's sentence of 22 October 2026, stale), and nothing else;
#      o. the owner's words in Section 6 changed in the runbook: it must fail, naming the changed text;
#      p. 6.1's expected `lockedFailures=0` made `lockedFailures=1`: it must fail, naming both texts;
#      q. the owner's words changed in a copy of the relayed record, the runbook not: it must fail, naming the source;
#   3. the limits the documents state, each of which must PASS, because the check does not compare that kind of text:
#      i. 4.4's `pairing failed: pinMismatch` made `pairing succeeded: pin accepted`;
#      j. 0.7's `RESULT: PASS` made `RESULT: FAIL`;
#      k. 1.4's "pull its 12 tables" made 13;
#      l. 1.4's "the four filters select 1, 4, 4 and 3 tests" made "1, 4, 4 and 5 tests";
#      m. 4.18's "about 300 of 320 parts verified" made 330;
#   4. final-fix/commands/runbook-coverage.py on the runbook as it stands (step numbers: classified and in a session).
#   Docs/Stage0/evidence/M0-DeviceA/instructions/commands/runbook-content-check.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
here=Docs/Stage0/evidence/M0-Integration
check="Docs/Stage0/evidence/M0-DeviceA/instructions/commands/runbook-content-check.py"
assembly="Docs/Stage0/evidence/M0-Decisions/assembly/commands/runbook-content-check.py"
relayed="Docs/Stage0/evidence/M0-DeviceA/instructions/relayed-2026-10-24.md"
scratch="$root/.build/scratch/runbook-content-check-devicea"
rm -rf "$scratch"; mkdir -p "$scratch"
echo "command: Docs/Stage0/evidence/M0-DeviceA/instructions/commands/runbook-content-check.sh"
echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
status=0
echo
echo "== 1. the runbook as it stands"
python3 -I "$check" "$root"
(( $? == 0 )) || status=1

control() {  # label, runbook file, root, text that the output must name
  local label="$1" file="$2" croot="$3" must="$4" out code
  echo
  echo "== 2$label: it must fail"
  out="$(python3 -I "$check" "$croot" "$file" 2>&1)"; code=$?
  printf '%s\n' "$out" | grep -v -E '^  ok |^G0|^runbook:|^  NOT_CARRIED|^  RUNBOOK_OWN|source fragments of' | sed "s#$scratch/##"
  if (( code == 0 )); then echo "PROBLEM: the control passed"; status=1; return; fi
  if [[ -n "$must" ]] && ! grep -q -F -- "$must" <<< "$out"; then
    echo "PROBLEM: the control failed, but its output does not name: $must"; status=1; return
  fi
  echo "control: fails, as it must (exit $code)${must:+, naming: $must}"
}

limit() {  # label, runbook file: the check must pass, since the change is of a kind it does not compare
  local label="$1" file="$2" out code
  echo
  echo "== 3$label: not compared, so it must pass"
  out="$(python3 -I "$check" "$root" "$file" 2>&1)"; code=$?
  printf '%s\n' "$out" | grep -E '^result:|UNLISTED|MISSING|PROBLEM'
  if (( code != 0 )); then
    echo "PROBLEM: the check now compares this kind of text; the documents that list it as not compared need correcting"
    status=1; return
  fi
  echo "limit: passes, as the documents say (exit $code)"
}

mutate() {  # name, old text, new text: a copy of the runbook as it stands with that one change
  python3 -I - "$root/Docs/Stage0/M0-device-runbook.md" "$scratch/$1.md" "$2" "$3" <<'EOF'
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit(f"the text to mutate occurs {text.count(old)} times: {old}")
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
EOF
}

earlier() {  # label, check file, expected problems (newline-separated): an earlier version must fail with exactly them
  local label="$1" file="$2" expected="$3" out code problems
  echo
  echo "== 2$label: it must fail, naming exactly the expected problems"
  out="$(python3 -I "$file" "$root" 2>&1)"; code=$?
  # A text's offset in the runbook changes with any edit before it, so offsets are compared as "offset N".
  problems="$(printf '%s\n' "$out" | grep -E '^  MISSING |^  UNLISTED |^PROBLEM ' | sed -e 's/^ *//' -e 's/at offset [0-9]* /at offset N /')"
  printf '%s\n' "$problems"
  if (( code != 0 )) && [[ "$problems" == "$expected" ]]; then
    echo "control: fails, as it must (exit $code), with exactly the $(printf '%s\n' "$expected" | wc -l | tr -d ' ') problems expected"
  else
    echo "PROBLEM: exit $code, and other problems than the ones expected"; status=1
  fi
}

git -C "$root" show 83ee28007517a9e41384a156f2ed647bb68de432:Docs/Stage0/M0-device-runbook.md > "$scratch/runbook-83ee280.md"
control "a. the runbook the round-2 review read (83ee280)" "$scratch/runbook-83ee280.md" "$root" ""
git -C "$root" show dc81fcea885cc1c8c326e541b889090bc5d3df4a:Docs/Stage0/M0-device-runbook.md > "$scratch/runbook-dc81fce.md"
control "b. the runbook the round-3 review read (dc81fce)" "$scratch/runbook-dc81fce.md" "$root" ""

mutate m-4.1 'Expect: "Paired with Device test Mac. Token stored in the Keychain (after first unlock, this device only)."' \
  'Expect: "Paired. Token stored in iCloud Keychain (synced)."' || status=1
control "c. 4.1's expected pairing status changed" "$scratch/m-4.1.md" "$root" "Paired. Token stored in iCloud Keychain (synced)."
mutate m-4.14 'Expect: "The Mac'"'"'s identity changed. Pair again and compare the fingerprint.", with' \
  'Expect: "Trust anyway? The Mac key changed.", with' || status=1
control "d. 4.14's expected message changed" "$scratch/m-4.14.md" "$root" "Trust anyway? The Mac key changed."
mutate m-3.13 'Expect: the Player title `G04Book (4 files)`' 'Expect: the Player title `G04Book (5 files)`' || status=1
control "e. 3.13's file count changed" "$scratch/m-3.13.md" "$root" "G04Book (5 files)"

# A copy of every file the check reads, taken from the working tree (so the runner also works before a commit).
src=Spikes/G02-Transfer/TransferKit/Sources/SylviaTransferCore/PartResponseValidation.swift
mkdir -p "$scratch/copy"
tar -cf - Docs/Stage0/device-checklists Docs/Stage0/evidence/M0-runbook Docs/Stage0/evidence/G01-EPUB/anchor-samples.json \
  Docs/Stage0/G02-Transfer.md Docs/Stage0/G03-Intake.md Docs/Stage0/G05-Recovery.md Docs/Stage0/G06-Design.md Docs/ADRs \
  Docs/Sylvia_v1_iOS_Implementation_Plan.md Spikes/G02-Transfer/iOS Spikes/G02-Transfer/TransferKit/Sources \
  Spikes/G02-Transfer/SourceService/Sources Spikes/G02-Transfer/SourceService/Tests Spikes/G04-Audio/Sources \
  Spikes/G05-AI/ATSProbe/project.yml Spikes/G05-AI/Tests/LiveProviderTests Spikes/G03-Intake/App/Tests/Unit/InAppLayoutTests.swift \
  Apps/DesignCatalog/project.yml Apps/DesignCatalog/Sources/Prototype/StorageAndSettings.swift Scripts/fixtures \
  Scripts/ci.d/71-g05-recovery.sh "$relayed" Docs/Stage0/M0-device-runbook.md 2>/dev/null | tar -x -C "$scratch/copy"
mkdir -p "$scratch/copy-q"
(cd "$scratch/copy" && tar -cf - .) | tar -x -C "$scratch/copy-q"
echo
echo "== the copy controls f and q change, before any change: it must pass, so that each control fails for its change alone"
python3 -I "$check" "$scratch/copy" "$scratch/copy/Docs/Stage0/M0-device-runbook.md" 2>&1 | grep -E '^result:'
python3 -I "$check" "$scratch/copy" "$scratch/copy/Docs/Stage0/M0-device-runbook.md" > /dev/null 2>&1 || { echo "PROBLEM: the copy fails unchanged"; status=1; }
python3 -I - "$scratch/copy/$src" <<'EOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = "\"The Mac's identity changed. Pair again and compare the fingerprint.\""
if text.count(old) != 1:
    sys.exit(f"the message occurs {text.count(old)} times")
open(path, "w", encoding="utf-8").write(text.replace(old, "\"The Mac's key changed. Pair again.\""))
EOF
control "f. the source of 4.14's message changed, the runbook not" "$scratch/copy/Docs/Stage0/M0-device-runbook.md" "$scratch/copy" \
  "source no longer says it"

mutate m-0.8 'Expect: the last line reads `drop-in exit 0`' 'Expect: "AI failed", and the last line reads `drop-in exit 0`' || status=1
control "g. a G0.5 AI-only text in step 0.8, whose heading names G0.5 recovery (R8-01)" "$scratch/m-0.8.md" "$root" \
  "UNLISTED step 0.8 (G05-Recovery.md): AI failed [only in G05-AI.md]"
mutate m-s4 'The Mac and phone B on the same Wi-Fi.' 'The Mac and phone B on the same Wi-Fi ("Received by Sylvia").' || status=1
control "h. a G0.3-only text in Session 4's own text, before its first step" "$scratch/m-s4.md" "$root" \
  "UNLISTED Session 4 (G02-Transfer.md): Received by Sylvia [only in G03-Intake.md]"

earlier "n. the assembly's version of the check ($assembly) on the runbook as it stands" "$assembly" \
"UNLISTED text at offset N (any checklist): 13 mini only (Recommended)
UNLISTED text at offset N (any checklist): iphone 11 pro seems to be no longer charging. i do have a 13 mini that is still working, so update the plan. even better from a screen size.
PROBLEM stale RUNBOOK_OWN entry (no longer in the header or Sections 1-7): is an iPhone 11 Pro: the product owner chose the iPhone 11 family on 22 October 2026"

mutate m-d1 'so update the plan. even better from a screen size."' 'so update the plan. even better for its screen."' || status=1
control "o. the owner's words of 24 October 2026 changed in Section 6, the record not" "$scratch/m-d1.md" "$root" \
  "even better for its screen."

mutate m-6.1 '`result=ended-by-restart`, `lockedFailures=0` and `gaps=0`' '`result=ended-by-restart`, `lockedFailures=1` and `gaps=0`' || status=1
control "p. 6.1's expected lockedFailures=0 (the lock harness, G0.5 recovery step 3) made lockedFailures=1" "$scratch/m-6.1.md" "$root" \
  "lockedFailures=1"
grep -q -F 'MISSING step 3: lockedFailures=0' <<< "$(python3 -I "$check" "$root" "$scratch/m-6.1.md" 2>&1)" \
  && echo "   and names the checklist's lockedFailures=0 as missing from the runbook, so step 3 is compared both ways" \
  || { echo "PROBLEM: control p does not name the checklist's lockedFailures=0 as missing"; status=1; }

python3 -I - "$scratch/copy-q/$relayed" <<'EOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = "so update the plan. even better from a screen size."
if text.count(old) != 1:
    sys.exit(f"the words occur {text.count(old)} times")
open(path, "w", encoding="utf-8").write(text.replace(old, "so update the plan."))
EOF
control "q. the owner's words changed in a copy of the relayed record, the runbook not" \
  "$scratch/copy-q/Docs/Stage0/M0-device-runbook.md" "$scratch/copy-q" \
  "$relayed lacks"

mutate l-4.4 'Expect: `pairing failed: pinMismatch`' 'Expect: `pairing succeeded: pin accepted`' || status=1
limit "i. 4.4's expected status, written in backticks without a field or count, inverted" "$scratch/l-4.4.md"
mutate l-0.7 'Expect: `RESULT: PASS`' 'Expect: `RESULT: FAIL`' || status=1
limit "j. 0.7's expected result line, written in backticks without a field or count, inverted" "$scratch/l-0.7.md"
mutate l-1.4a 'pull its 12 tables' 'pull its 13 tables' || status=1
limit "k. 1.4's count of the release tables, in prose, changed" "$scratch/l-1.4a.md"
mutate l-1.4b 'the four filters select 1, 4, 4 and 3 tests' 'the four filters select 1, 4, 4 and 5 tests' || status=1
limit "l. 1.4's test counts of the filters, in prose, changed" "$scratch/l-1.4b.md"
mutate l-4.18 'about 300 of 320 parts verified' 'about 330 of 320 parts verified' || status=1
limit "m. 4.18's count of parts, in prose, changed" "$scratch/l-4.18.md"

echo
echo "== 4. step coverage of the runbook as it stands (final-fix/commands/runbook-coverage.py)"
python3 -I "$here/final-fix/commands/runbook-coverage.py" "$root"
(( $? == 0 )) || status=1
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
