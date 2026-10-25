#!/bin/bash
# The two merges m0-sessions waits for, computed and not made, at the fix of the completeness findings of the review of
# the update of 24 October 2026 (26 October 2026 on the build Mac's clock; findings DA-01 and DA-05): git merge-tree
# --write-tree, which writes the merged trees' objects to the object store and nothing else; no ref, index or
# working-tree file is written, and neither branch is changed.
#   1. m0-decisions (the owner's first sittings, to be merged before the sessions' checkout moves) into HEAD: it must
#      merge without a conflict, as it did into ec91f66a, the head this fix started from;
#   2. m0-exit-prep (the agent run on ADR-0014's R4-01 and R4-02, the final-review records and the Xcode 27.1 evidence,
#      merged into m0-sessions once reviewed), as it stands when read, into HEAD and into ec91f66a: the files that
#      conflict must be the same for both, so this fix adds no conflict to that merge, and ADR-0014, whose open items
#      this fix's note heads (DA-05), must not be among them. The branch is another run's: it is read here, not changed.
#   Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/merges.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, completeness, fix-1, M0-DeviceA, evidence, Stage0, Docs
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
start=ec91f66a863c70980533f27f53d8e6b44f234485
adr14=Docs/ADRs/0014-dependency-lock-and-license-inventory.md
status=0
merge() {  # into, branch: prints the conflicting files after the tree line; returns merge-tree's status
  git merge-tree --write-tree --name-only --no-messages "$1" "$2"
}
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/merges.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "m0-decisions: $(git rev-parse m0-decisions); m0-exit-prep: $(git rev-parse m0-exit-prep) ($(git log -1 --format='%ci' m0-exit-prep))"
  echo "merge bases: HEAD and m0-decisions $(git merge-base HEAD m0-decisions); HEAD and m0-exit-prep $(git merge-base HEAD m0-exit-prep)"
  echo
} > "$log" 2>&1
out_d="$(merge HEAD m0-decisions)"; st_d=$?
out_d0="$(merge "$start" m0-decisions)"; st_d0=$?
{
  echo "== 1. m0-decisions into HEAD"
  echo "   merge-tree exit: $st_d (0: no conflict); merged tree: $(printf '%s\n' "$out_d" | head -n 1)"
  printf '%s\n' "$out_d" | tail -n +2 | sed 's/^/   conflicting: /'
  echo "   into ${start:0:8}, as a control: exit $st_d0; merged tree: $(printf '%s\n' "$out_d0" | head -n 1)"
} >> "$log"
[[ "$st_d" == 0 && "$st_d0" == 0 ]] || { echo "   PROBLEM: a conflict" >> "$log"; status=1; }
out_e="$(merge HEAD m0-exit-prep)"; st_e=$?
out_e0="$(merge "$start" m0-exit-prep)"; st_e0=$?
files_e="$(printf '%s\n' "$out_e" | tail -n +2 | sort)"
files_e0="$(printf '%s\n' "$out_e0" | tail -n +2 | sort)"
{
  echo
  echo "== 2. m0-exit-prep, as it stands when read, into HEAD and into ${start:0:8}"
  echo "   into HEAD: merge-tree exit $st_e; files that conflict: $(printf '%s\n' "$files_e" | grep -c .)"
  printf '%s\n' "$files_e" | grep . | sed 's/^/     /'
  echo "   into ${start:0:8}: merge-tree exit $st_e0; files that conflict: $(printf '%s\n' "$files_e0" | grep -c .)"
  printf '%s\n' "$files_e0" | grep . | sed 's/^/     /'
} >> "$log"
if [[ "$files_e" == "$files_e0" ]]; then
  echo "   the same files: this fix adds no file that conflicts" >> "$log"
else
  { echo "   PROBLEM: the files differ:"; diff <(printf '%s\n' "$files_e0") <(printf '%s\n' "$files_e") | sed 's/^/     /'; } >> "$log"
  status=1
fi
if printf '%s\n' "$files_e" | grep -qx "$adr14"; then
  echo "   PROBLEM: $adr14 conflicts" >> "$log"; status=1
else
  echo "   $adr14 does not conflict: this fix's note at the head of its open items merges with that run's changes" >> "$log"
fi
echo "   (the conflicts listed are in files both this branch and that run changed before this fix; resolving them is the merge's, between sittings)" >> "$log"
{
  echo
  echo "exit: $status"
} >> "$log"
exit $status
