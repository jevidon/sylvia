#!/bin/bash
# The two merges m0-sessions waits for, computed and not made, at the fix of the owner-readability findings of the review
# of the update of 24 October 2026 (26 October 2026 on the build Mac's clock; findings OWN-DA-01 and OWN-DA-04): git
# merge-tree --write-tree, which writes the merged trees' objects to the object store and nothing else; no ref, index or
# working-tree file is written, and neither branch is changed. The successor of
# Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/merges.sh, with this fix's start, caf75a84:
#   1. m0-decisions (the owner's first sittings, to be merged before the sessions' checkout moves) into HEAD: it must
#      merge without a conflict, as it did into caf75a84, the head this fix started from; and m0-decisions must still be
#      where the earlier fixes read it, c72247a6, with nothing committed on it since (else this fix's records of it are
#      out of date);
#   2. m0-exit-prep (the agent run on ADR-0014's R4-01 and R4-02, the final-review records and the Xcode 27.1 evidence,
#      merged into m0-sessions once reviewed), as it stands when read, into HEAD and into caf75a84: the files that conflict
#      must be the same for both, so this fix adds no file that conflicts to that merge (it changes ADR-0001's Status line
#      and its open item for the technical lead, in a file that already conflicts). The branch is another run's: it is
#      read here, not changed.
#   Docs/Stage0/evidence/M0-DeviceA/fix-1/owner/commands/merges.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, owner, fix-1, M0-DeviceA, evidence, Stage0, Docs
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
start=caf75a8447597efa5076b53b9a0d36be0fdcc901
read_at=c72247a69a374ce361834550b92689b4abab95ee
adr01=Docs/ADRs/0001-platform-baseline-and-toolchain.md
status=0
merge() {  # into, branch: prints the conflicting files after the tree line; returns merge-tree's status
  git merge-tree --write-tree --name-only --no-messages "$1" "$2"
}
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/fix-1/owner/commands/merges.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "m0-decisions: $(git rev-parse m0-decisions) ($(git log -1 --format='%ci, %s' m0-decisions)); m0-exit-prep: $(git rev-parse m0-exit-prep) ($(git log -1 --format='%ci' m0-exit-prep))"
  echo "merge bases: HEAD and m0-decisions $(git merge-base HEAD m0-decisions); HEAD and m0-exit-prep $(git merge-base HEAD m0-exit-prep)"
  echo
} > "$log" 2>&1
if [[ "$(git rev-parse m0-decisions)" == "$read_at" ]]; then
  echo "m0-decisions is still at ${read_at:0:8}, where the first three fixes read it: nothing committed on it since" >> "$log"
else
  echo "PROBLEM: m0-decisions has moved from ${read_at:0:8} (commits since: $(git rev-list --count "$read_at"..m0-decisions)); this fix's records of it are out of date" >> "$log"
  status=1
fi
out_d="$(merge HEAD m0-decisions)"; st_d=$?
out_d0="$(merge "$start" m0-decisions)"; st_d0=$?
{
  echo
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
if printf '%s\n' "$files_e0" | grep -qx "$adr01"; then
  echo "   $adr01, whose Status line and technical-lead item this fix changes, already conflicts into ${start:0:8}: the fix adds to a conflict that is there, not a new one" >> "$log"
else
  echo "   $adr01 does not conflict into ${start:0:8}" >> "$log"
fi
echo "   (the conflicts listed are in files both this branch and that run changed before this fix; resolving them is the merge's, between sittings)" >> "$log"
{
  echo
  echo "exit: $status"
} >> "$log"
exit $status
