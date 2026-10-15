#!/bin/bash
# Binary files (git numstat "-") added or modified between two commits, with their sizes at the second, grouped
# by top folder, plus a check that none is an LFS pointer and none has a git attribute.
#   binary-delta.sh <from> <to>
set -u
mkdir -p "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.build/scratch"
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
from="$1"; to="$2"
echo "binary files changed from $from to $to ($(git rev-parse --short "$to"))"
git diff --numstat --no-renames --diff-filter=AM "$from" "$to" | awk -F'\t' '$1=="-"{print $3}' > .build/scratch/binary-delta.txt
total=0; n=0; png=0; pngbytes=0; largest=0; pointers=0
while IFS= read -r f; do
  size=$(git cat-file -s "$to:$f")
  n=$((n+1)); total=$((total+size))
  if [[ "$f" == *.png ]]; then png=$((png+1)); pngbytes=$((pngbytes+size)); (( size > largest )) && largest=$size; fi
  if git cat-file -p "$to:$f" | head -c 40 | grep -q "version https://git-lfs"; then pointers=$((pointers+1)); fi
  echo "$size	$f"
done < .build/scratch/binary-delta.txt > .build/scratch/binary-delta-sizes.tsv
echo "files: $n, bytes: $total; PNG: $png, bytes $pngbytes, largest $largest; LFS pointers: $pointers"
awk -F'\t' '{split($2,a,"/"); k=a[1]"/"a[2]"/"a[3]"/"a[4]; c[k]++; s[k]+=$1} END{for(k in c) printf "  %s: %d files, %d bytes\n", k, c[k], s[k]}' .build/scratch/binary-delta-sizes.tsv | sort
echo "added (not modified):"
git diff --numstat --no-renames --diff-filter=A "$from" "$to" | awk -F'\t' '$1=="-"{print "  "$3}'
echo ".gitattributes present: $(git ls-tree --name-only "$to" .gitattributes | wc -l | tr -d ' ')"
