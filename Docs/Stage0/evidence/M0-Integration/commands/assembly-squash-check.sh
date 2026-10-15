#!/bin/bash
# For each item: branch head == stated final commit; every path changed on the branch
# (relative to its merge base with the squash commit's parent) is identical in the squash commit.
set -u
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
while read -r item branch final squash; do
  head=$(git rev-parse "$branch" 2>/dev/null || echo missing)
  parent=$(git rev-parse "$squash^")
  base=$(git merge-base "$branch" "$parent")
  n=0; bad=0
  while IFS= read -r p; do
    n=$((n+1))
    a=$(git ls-tree "$branch" -- "$p" | awk '{print $1,$3}')
    b=$(git ls-tree "$squash" -- "$p" | awk '{print $1,$3}')
    [ "$a" == "$b" ] || { bad=$((bad+1)); echo "  DIFF $p branch=[$a] squash=[$b]"; }
  done < <(git diff --name-only --no-renames "$base" "$branch")
  sq=$(git diff --name-only --no-renames "$parent" "$squash" | wc -l | tr -d ' ')
  echo "$item head=$head final=$final match=$([ "$head" == "$final" ] && echo yes || echo NO) base=${base:0:9} branch_paths=$n differing=$bad squash_paths=$sq"
done <<'LIST'
contracts m0-int-contracts ef0d5de68f3bd7bdd301275796611e857bf663fb 5670e3a
deps m0-int-deps 67682c2394d7d6ed488cf2902c944efd2e12d539 358a5bc
threat m0-int-threat 6bb2b9e8811d4ce1d7786c9c2f971ce4416facfe 10d758f
minors-g06-design m0-int-minors-g06-design 98125421e27490aa11c7c4151c8457ce36bd2c34 8a59a16
minors-g05-recovery m0-int-minors-g05-recovery cd3e42b0345b3f1fb21e21a109deff0c4a2e26d6 740aa46
minors-g01-epub m0-int-minors-g01-epub d31705419c15da68cd4208dc243e696b2f6d8346 b7b3ae9
minors-g01-pdf m0-int-minors-g01-pdf a44b746c6a83f77aa20cf8cc43f399fe1d628717 483ca01
minors-g03-intake m0-int-minors-g03-intake 77ceaf3f5228b91c1e000047014618a9f783a6b1 932d08c
minors-g02-transfer m0-int-minors-g02-transfer c83a3b9ff051aa023391c16904ca075de4ab52dd 41e918a
minors-g05-ai m0-int-minors-g05-ai 4090d590e1c09335b3c2124bda18598bb3797d18 7060c10
runbook m0-int-runbook 6f339473eec57fd4dc6b989efde195519c019f5b 6be1cb7
amendments m0-int-amendments 694518f2e189ed4a7424a466d24533c106f686d3 8d34e8c
minors-g04-audio m0-int-minors-g04-audio d0c612031d2e0e625ea3a26fef134876d390cd54 70f6f54
LIST
