#!/bin/bash
# M0 final review round 2, contracts R2-01: rule A3 of anchor.v1 checked in linear time.
#   1. a3-linear-check.py: the linear check agrees with the regular expression it replaced on every case of a bounded
#      exhaustive set and on 200,000 random ones; times of both on the review's case; the review's anchor is schema-valid.
#   2. Control: a copy of Scripts/check-spike-anchors.py with the replaced code of 83ee280 put back into
#      anchor_violations fails the checker's new "rule A3 at scale" check (its probe is stopped at the time limit), so
#      the check notices a backtracking matcher instead of hanging.
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/a3-linear-check.sh > <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
python="${SYLVIA_TOOLS_VENV:-$HOME/Library/Caches/SylviaTools/venv}/bin/python"
scratch="$root/.build/scratch/a3-linear-check"
rm -rf "$scratch"; mkdir -p "$scratch/Scripts"
echo "command: Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/a3-linear-check.sh"
echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
status=0
echo
"$python" -I Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/a3-linear-check.py "$root" | sed "s#$root#<repository>#g"
(( PIPESTATUS[0] == 0 )) || status=1

echo
echo "== control: the checker with the replaced A3 code put back"
"$python" -I - "$root/Scripts/check-spike-anchors.py" "$scratch/Scripts/check-spike-anchors.py" <<'PY'
import sys
source = open(sys.argv[1], encoding="utf-8").read()
new = '''        texts = [s["text"] for s in segments]
        page_changes = [b["page_index"] != a["page_index"] for a, b in zip(segments, segments[1:])]
        if not pdf_composition_holds(texts, [False] * len(page_changes), anchor["exact_text"]):
            out.append(("A3", "exact_text is not the segments' texts in order with at most one U+000A between two"))
        elif not pdf_composition_holds(texts, page_changes, anchor["exact_text"]):'''
old = '''        texts = [re.escape(s["text"]) for s in segments]
        breaks = ["\\n" if b["page_index"] != a["page_index"] else "\\n?" for a, b in zip(segments, segments[1:])]
        if not re.fullmatch(texts[0] + "".join("\\n?" + t for t in texts[1:]), anchor["exact_text"]):
            out.append(("A3", "exact_text is not the segments' texts in order with at most one U+000A between two"))
        elif not re.fullmatch(texts[0] + "".join(j + t for j, t in zip(breaks, texts[1:])), anchor["exact_text"]):'''
assert source.count(new) == 1, "the A3 code to replace was not found once"
open(sys.argv[2], "w", encoding="utf-8").write(source.replace(new, old))
print("copy written with the A3 code of 83ee280 in anchor_violations")
PY
started=$SECONDS
"$python" -I "$scratch/Scripts/check-spike-anchors.py" --root "$root" > "$scratch/control.out" 2>&1
control=$?
echo "the copy's exit status: $control after $((SECONDS - started)) s"
grep -E "^(rule A3 at scale|result|error: rule A3)" "$scratch/control.out"
if (( control != 0 )) && grep -q "^error: rule A3 at scale: .* not decided within" "$scratch/control.out"; then
  echo "control: as expected, the copy fails the scale check at its time limit"
else
  echo "PROBLEM: the copy did not fail the scale check at its time limit"; status=1
fi
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
