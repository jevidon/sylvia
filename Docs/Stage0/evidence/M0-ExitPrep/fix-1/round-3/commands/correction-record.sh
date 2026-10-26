#!/bin/bash
# The record of the product owner's request for CLAUDE.md's correction (the third review of the M0 exit preparation,
# its finding HON-EP-03; integration log section 33): the records say that the orchestrating session made 5aec2518 at
# the owner's request, and the only record of that request in the repository is that commit's message, which the
# session wrote. This prints the commit's metadata and whole message, what it changed and on top of what, whether main
# holds it, and, for the relays of the owner's words and of Apple's pages that are committed, whether either names the
# correction. Read-only; git and grep only; no network.
#   Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands/correction-record.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, round-3, fix-1, M0-ExitPrep, evidence, Stage0, Docs
cd "$root" || exit 1
correction=5aec2518c90427a283d9c8195e11bb9ab23e5d12
pr6=96bdc7e996f99fcd2571ea983cc32a04076a5a07
relays="Docs/Stage0/evidence/M0-Decisions/followup/owner-answers-2026-10-23.md Docs/Stage0/evidence/M0-Decisions/fix-1/decision-page-record.json Docs/Stage0/evidence/M0-ExitPrep/assembly/xcode-27.1-release.md"
status=0
echo "command: Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands/correction-record.sh"
echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' '); date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "== 1. The commit, as git records it (git show --no-patch --format=fuller)"
git show --no-patch --format=fuller "$correction"
echo
echo "== 2. What it changed, and on top of what"
parent="$(git rev-parse "$correction^")"
echo "parent: $parent ($( [[ "$parent" == "$pr6" ]] && echo "main after pull request #6" || echo "PROBLEM: not $pr6"))"
echo "files changed: $(git diff --name-only "$pr6" "$correction" | tr '\n' ' ')($(git diff --numstat "$pr6" "$correction" | tr '\t' ' '))"
[[ "$parent" == "$pr6" && "$(git diff --name-only "$pr6" "$correction")" == "CLAUDE.md" ]] || status=1
main="$(git rev-parse main)"
held=no; git merge-base --is-ancestor "$correction" main && held=yes
echo "main is $main; it holds $correction: $held"
echo "HEAD holds it: $(git merge-base --is-ancestor "$correction" HEAD && echo yes || echo no); commits on HEAD that main lacks: $(git rev-list --count main..HEAD)"
echo
echo "== 3. The message's sentence on the request"
sentence="$(git show --no-patch --format=%B "$correction" | tr '\n' ' ' | grep -o -E 'The owner asked the orchestrating session to make it on 24 October 2026[^.]*\.' || true)"
echo "${sentence:-PROBLEM: not found}"
[[ -n "$sentence" ]] || status=1
echo
echo "== 4. The committed relays: does either name the correction or the request?"
for f in $relays; do
  if [[ -f "$f" ]]; then
    c1="$(grep -c -F '5aec2518' "$f")"; c2="$(grep -c -i -E 'milestone paragraph|asked the orchestrating session' "$f")"
    c3="$(grep -c -F 'CLAUDE.md' "$f")"
    echo "$f: lines naming 5aec2518: $c1; naming the milestone paragraph or the request: $c2; lines naming CLAUDE.md at all: $c3"
    grep -n -F 'CLAUDE.md' "$f" | cut -c1-200 | sed 's/^/   /'
    [[ "$c1" == 0 && "$c2" == 0 ]] || status=1
  else
    echo "$f: PROBLEM, absent"; status=1
  fi
done
echo
echo "result: $( ((status == 0)) && echo "pass: the commit message is the only record of the request among them" || echo FAIL)"
exit $status
