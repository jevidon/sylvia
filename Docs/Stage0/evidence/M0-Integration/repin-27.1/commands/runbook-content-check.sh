#!/bin/bash
# The device runbook against the merged checklists, with the content check of the re-pin round (M0 final review round
# 3, owner readability R7-01: the previous check's reverse pass compared four count forms only, against all eight
# checklists joined, while the documents said it compared quoted texts and counts both ways). Runs, read-only:
#   1. commands/runbook-content-check.py on the runbook as committed: it must pass;
#   2. controls, each of which must fail:
#      a. the runbook the round-2 review read (83ee280), as the previous check's control;
#      b. the runbook the round-3 review read (dc81fce), which the previous check passed;
#      c-e. R7-01's three mutations of the runbook as committed: 4.1's expected pairing status, 4.14's expected
#         message for a changed Mac key, and 3.13's `G04Book (4 files)`; each output must name the mutated text;
#      f. a source that no longer says a runbook-only text: in a copy of the files the check reads, the client's
#         message for a changed Mac key (PartResponseValidation.swift) is changed, the runbook is not; the check must
#         report that source;
#   3. final-fix/commands/runbook-coverage.py on the runbook as committed (step numbers: classified and in a session).
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/runbook-content-check.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
here=Docs/Stage0/evidence/M0-Integration
check="$here/repin-27.1/commands/runbook-content-check.py"
scratch="$root/.build/scratch/runbook-content-check-repin"
rm -rf "$scratch"; mkdir -p "$scratch"
echo "command: $here/repin-27.1/commands/runbook-content-check.sh"
echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
status=0
echo
echo "== 1. the runbook as committed"
python3 -I "$check" "$root"
(( $? == 0 )) || status=1

control() {  # label, runbook file, [root], text that the output must name
  local label="$1" file="$2" croot="$3" must="$4" out code
  echo
  echo "== 2$label: it must fail"
  out="$(python3 -I "$check" "$croot" "$file" 2>&1)"; code=$?
  printf '%s\n' "$out" | grep -v -E '^  ok |^G0|^runbook:' | sed "s#$scratch/##"
  if (( code == 0 )); then echo "PROBLEM: the control passed"; status=1; return; fi
  if [[ -n "$must" ]] && ! grep -q -F -- "$must" <<< "$out"; then
    echo "PROBLEM: the control failed, but its output does not name: $must"; status=1; return
  fi
  echo "control: fails, as it must (exit $code)${must:+, naming: $must}"
}

git -C "$root" show 83ee28007517a9e41384a156f2ed647bb68de432:Docs/Stage0/M0-device-runbook.md > "$scratch/runbook-83ee280.md"
control "a. the runbook the round-2 review read (83ee280)" "$scratch/runbook-83ee280.md" "$root" ""
git -C "$root" show dc81fcea885cc1c8c326e541b889090bc5d3df4a:Docs/Stage0/M0-device-runbook.md > "$scratch/runbook-dc81fce.md"
control "b. the runbook the round-3 review read (dc81fce)" "$scratch/runbook-dc81fce.md" "$root" ""

mutate() {  # name, old text, new text
  python3 -I - "$root/Docs/Stage0/M0-device-runbook.md" "$scratch/$1.md" "$2" "$3" <<'EOF'
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit(f"the text to mutate occurs {text.count(old)} times: {old}")
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
EOF
}
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

echo
echo "== 3. step coverage of the runbook as committed (final-fix/commands/runbook-coverage.py)"
python3 -I "$here/final-fix/commands/runbook-coverage.py" "$root"
(( $? == 0 )) || status=1
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
