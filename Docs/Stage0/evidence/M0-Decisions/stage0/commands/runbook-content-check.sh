#!/bin/bash
# The device runbook against the merged checklists, with the content check of the records of the product owner's M0
# decisions (22 October 2026; integration log section 15). The successor of
# Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2/commands/runbook-content-check.sh, with its controls and limits
# unchanged and two controls more (n, o). Runs, read-only:
#   1. M0-Decisions/stage0/commands/runbook-content-check.py on the runbook as committed: it must pass;
#   2. controls, each of which must fail:
#      a. the runbook the round-2 review read (83ee280);
#      b. the runbook the round-3 review read (dc81fce);
#      c-e. R7-01's three mutations of the runbook as committed: 4.1's expected pairing status, 4.14's expected
#         message for a changed Mac key, and 3.13's `G04Book (4 files)`; each output must name the mutated text;
#      f. a source that no longer says a runbook-only text: in a copy of the files the check reads, the client's
#         message for a changed Mac key (PartResponseValidation.swift) is changed, the runbook is not;
#      g. R8-01's case: a G0.5 AI-only text ("AI failed") added to step 0.8, whose bold heading names G0.5 recovery
#         (the previous check compared 0.8 with every checklist, so this passed it);
#      h. a G0.3-only text ("Received by Sylvia") added to Session 4's own text before its first step: text in a
#         session outside a step is compared with the checklists of that session's steps' gates (G0.2 here), not with
#         every checklist;
#   3. the limits the documents state, each of which must PASS, because the check does not compare that kind of text
#      (the check's docstring, "Not compared"; the runbook's Section 9):
#      i. a status written in backticks without a log field or count: 4.4's `pairing failed: pinMismatch` made
#         `pairing succeeded: pin accepted`;
#      j. the same kind: 0.7's `RESULT: PASS` made `RESULT: FAIL`;
#      k. a count in prose: 1.4's "pull its 12 tables" made 13;
#      l. a count in prose: 1.4's "the four filters select 1, 4, 4 and 3 tests" made "1, 4, 4 and 5 tests";
#      m. a count in prose: 4.18's "about 300 of 320 parts verified" made 330;
#      n. the round-2 version of the check on the runbook as committed: it must fail, and report exactly the changes the
#         decisions made (G0.5 recovery step 3's two markers, now left to the checklist; the three runbook-own texts no
#         longer quoted; the G0.3 checklist no longer saying "Run on both when available"), and nothing else;
#      o. the runbook without the words that leave G0.5 recovery step 3's harness steps to the checklist: it must fail;
#   4. final-fix/commands/runbook-coverage.py on the runbook as committed (step numbers: classified and in a session).
#   Docs/Stage0/evidence/M0-Decisions/stage0/commands/runbook-content-check.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
here=Docs/Stage0/evidence/M0-Integration
check="Docs/Stage0/evidence/M0-Decisions/stage0/commands/runbook-content-check.py"
previous="$here/repin-27.1/round-2/commands/runbook-content-check.py"
scratch="$root/.build/scratch/runbook-content-check-decisions"
rm -rf "$scratch"; mkdir -p "$scratch"
echo "command: Docs/Stage0/evidence/M0-Decisions/stage0/commands/runbook-content-check.sh"
echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
status=0
echo
echo "== 1. the runbook as committed"
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

mutate() {  # name, old text, new text: a copy of the committed runbook with that one change
  python3 -I - "$root/Docs/Stage0/M0-device-runbook.md" "$scratch/$1.md" "$2" "$3" <<'EOF'
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit(f"the text to mutate occurs {text.count(old)} times: {old}")
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
EOF
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

src=Spikes/G02-Transfer/TransferKit/Sources/SylviaTransferCore/PartResponseValidation.swift
mkdir -p "$scratch/copy"
git -C "$root" archive HEAD Docs/Stage0/device-checklists Docs/Stage0/evidence/M0-runbook Docs/Stage0/evidence/G01-EPUB/anchor-samples.json \
  Docs/Stage0/G02-Transfer.md Docs/Stage0/G03-Intake.md Docs/Stage0/G05-Recovery.md Docs/Stage0/G06-Design.md Docs/ADRs \
  Docs/Sylvia_v1_iOS_Implementation_Plan.md Spikes/G02-Transfer Spikes/G04-Audio/Sources Spikes/G05-AI/ATSProbe/project.yml \
  Spikes/G05-AI/Tests/LiveProviderTests Spikes/G03-Intake/App/Tests/Unit/InAppLayoutTests.swift Apps/DesignCatalog/project.yml \
  Apps/DesignCatalog/Sources/Prototype/StorageAndSettings.swift Scripts/fixtures Scripts/ci.d/71-g05-recovery.sh | tar -x -C "$scratch/copy"
cp "$root/Docs/Stage0/M0-device-runbook.md" "$scratch/copy/Docs/Stage0/M0-device-runbook.md"
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
echo "== 2n. the round-2 version of the check ($previous) on the runbook as committed: it must fail, naming exactly the decisions' changes"
out="$(python3 -I "$previous" "$root" 2>&1)"; code=$?
problems="$(printf '%s\n' "$out" | grep -E '^  MISSING |^  UNLISTED |^PROBLEM ' | sed 's/^ *//')"
printf '%s\n' "$problems"
expected=$'MISSING step 3: classA_readable=false\nMISSING step 3: classC_save=ok\nPROBLEM stale RUNBOOK_OWN entry (no longer in the header or Sections 1-7): Run on both when available\nPROBLEM stale RUNBOOK_OWN entry (no longer in the header or Sections 1-7): iPhone 12-class hardware\nPROBLEM stale RUNBOOK_OWN entry (no longer in the header or Sections 1-7): once available\nPROBLEM source no longer says it, for '"'"'Run on both when available'"'"': Docs/Stage0/device-checklists/G03-Intake.md lacks '"'"'Run on both when available'"'"''
if (( code != 0 )) && [[ "$problems" == "$expected" ]]; then
  echo "control: fails, as it must (exit $code), with exactly the six problems the decisions' changes explain"
else
  echo "PROBLEM: the round-2 check gave exit $code and other problems than the six expected"; status=1
fi

# The words occur twice (the header's list of steps that use the checklist's material, and 6.1): both are replaced.
python3 -I - "$root/Docs/Stage0/M0-device-runbook.md" "$scratch/o-6.1.md" <<'EOF' || status=1
import sys
src, dst = sys.argv[1:3]
text = open(src, encoding="utf-8").read()
words = "G0.5 recovery step 3's harness steps"
if text.count(words) != 2:
    sys.exit(f"the words occur {text.count(words)} times, not 2")
open(dst, "w", encoding="utf-8").write(text.replace(words, "the locked-device harness's steps"))
EOF
control "o. the runbook without the words that leave G0.5 recovery step 3 to the checklist" "$scratch/o-6.1.md" "$root" \
  "G05-Recovery.md step 3: listed as left to the checklist, but the runbook no longer says so"

echo
echo "== 4. step coverage of the runbook as committed (final-fix/commands/runbook-coverage.py)"
python3 -I "$here/final-fix/commands/runbook-coverage.py" "$root"
(( $? == 0 )) || status=1
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
