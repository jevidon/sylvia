#!/bin/bash
# The fold-in of m0-device-fixes into m0-records-update (27 October 2026; integration log section 45): what the merge
# brought, read from git alone.
#   Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands/merge-check.sh > <log>
# 1. The merge commit cbdb63bc: its parents are 6a510880 (m0-records-update before the fold-in) and a60aa922
#    (m0-device-fixes), both made from c72247a6, their merge base; m0-device-fixes, read only, is still at a60aa922.
# 2. The two sides changed different files since c72247a6 (no file in both lists), so the merge could not conflict.
# 3. At the merge commit, every file m0-device-fixes changed is as a60aa922 has it, and every file m0-records-update
#    changed is as 6a510880 has it: the merge took each side's files and wrote nothing of its own.
# 4. At HEAD (or the commit given), every file m0-device-fixes changed is as a60aa922 has it, but its README, whose diff
#    from a60aa922 only adds lines (the fold-in's dated notes); the device fixes' code (Spikes/) is a60aa922's.
# 5. What the merge brought outside Docs/: the files under Spikes/ (none elsewhere).
# Exit 1 if any of these does not hold. Read-only. With --worktree, part 4 reads the working tree instead of HEAD (a
# dry run before the documents commit).
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
merge=cbdb63bc265b98955cc4a297e92c689fb1a9d410
ours=6a510880c34f7936c972b6ace9a18c126ecab13d
theirs=a60aa92274d209bff6e1727ed36c078cd94ed8b2
base=c72247a69a374ce361834550b92689b4abab95ee
readme=Docs/Stage0/evidence/M0-DeviceFixes/README.md
rev=HEAD
to=(HEAD)
if [[ "${1:-}" == "--worktree" ]]; then to=(); fi
status=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; status=1; }
scratch="$root/.build/scratch/foldin-merge-check"
rm -rf "$scratch"; mkdir -p "$scratch"
echo "merge-check: checked commit $(git rev-parse "$rev"); HEAD $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

echo "== 1. the merge commit"
git log -1 --format='%H %P%n%s' "$merge"
parents="$(git log -1 --format=%P "$merge")"
[[ "$parents" == "$ours $theirs" ]] && ok "its parents are $ours (first) and $theirs" || bad "its parents are $parents"
[[ "$(git merge-base "$ours" "$theirs")" == "$base" ]] && ok "the merge base of the two sides is $base" || bad "merge base $(git merge-base "$ours" "$theirs")"
[[ "$(git rev-parse m0-device-fixes)" == "$theirs" ]] && ok "m0-device-fixes (read only) is at $theirs" || bad "m0-device-fixes is at $(git rev-parse m0-device-fixes)"
git merge-base --is-ancestor "$merge" "$rev" && ok "the merge commit is in the history of $rev" || bad "the merge commit is not in the history of $rev"
echo

echo "== 2. the files each side changed since $base"
git diff --name-only "$base" "$ours" | sort > "$scratch/ours.txt"
git diff --name-only "$base" "$theirs" | sort > "$scratch/theirs.txt"
echo "m0-records-update ($ours): $(wc -l < "$scratch/ours.txt" | tr -d ' ') files; m0-device-fixes ($theirs): $(wc -l < "$scratch/theirs.txt" | tr -d ' ') files"
both="$(comm -12 "$scratch/ours.txt" "$scratch/theirs.txt")"
[[ -z "$both" ]] && ok "no file is in both lists, so the merge could not conflict" || { bad "files in both lists:"; echo "$both"; }
echo

echo "== 3. at the merge commit, each side's files as that side has them"
git diff --name-only "$ours" "$merge" | sort > "$scratch/merge-vs-ours.txt"
git diff --name-only "$theirs" "$merge" | sort > "$scratch/merge-vs-theirs.txt"
cmp -s "$scratch/merge-vs-ours.txt" "$scratch/theirs.txt" && ok "against $ours the merge differs in exactly m0-device-fixes's files" || bad "against $ours the merge differs elsewhere"
cmp -s "$scratch/merge-vs-theirs.txt" "$scratch/ours.txt" && ok "against $theirs the merge differs in exactly m0-records-update's files" || bad "against $theirs the merge differs elsewhere"
echo

where="${to[*]:-the working tree}"
echo "== 4. at $where, m0-device-fixes's files as a60aa922 has them, but for the dated notes added to its README"
changed="$(git diff --name-only "$theirs" ${to[@]+"${to[@]}"} -- $(cat "$scratch/theirs.txt"))"
echo "files of m0-device-fixes that differ at $where from $theirs: ${changed:-none}"
[[ "$changed" == "$readme" ]] && ok "only its README differs" || bad "other files differ: ${changed:-none}"
removed="$(git diff -U0 "$theirs" ${to[@]+"${to[@]}"} -- "$readme" | grep -c '^-[^-]' || true)"
added="$(git diff -U0 "$theirs" ${to[@]+"${to[@]}"} -- "$readme" | grep -c '^+[^+]' || true)"
echo "its README: $added line(s) added, $removed line(s) removed"
[[ "$removed" == 0 && "$added" -gt 0 ]] && ok "the README's diff only adds lines" || bad "the README's diff removes or changes lines"
git diff -U0 "$theirs" ${to[@]+"${to[@]}"} -- "$readme" | grep '^+[^+]' | cut -c1-160 | sed 's/^/   /'
spikes="$(git diff --name-only "$theirs" ${to[@]+"${to[@]}"} -- Spikes)"
[[ -z "$spikes" ]] && ok "nothing under Spikes/ differs from $theirs at $where" || bad "Spikes/ differs: $spikes"
echo

echo "== 5. what the merge brought outside Docs/"
git diff --stat "$ours" "$merge" -- . ':(exclude)Docs' | cat
other="$(git diff --name-only "$ours" "$merge" -- . ':(exclude)Docs' ':(exclude)Spikes')"
[[ -z "$other" ]] && ok "outside Docs/ only files under Spikes/" || bad "outside Docs/ and Spikes/: $other"
echo
rm -rf "$scratch"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
