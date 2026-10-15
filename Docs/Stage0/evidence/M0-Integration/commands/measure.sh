#!/bin/bash
# Measure binary files added by each gate branch (read with git, no checkout).
cd "$(dirname "$0")/../../../../.." || exit 1; mkdir -p .build/scratch
out=.build/scratch/binaries.tsv
: > "$out"
for b in m0-g06-design m0-g05-recovery m0-g01-epub m0-g01-pdf m0-g03-intake m0-g02-transfer m0-g05-ai m0-g04-audio; do
  # numstat shows "-	-" for binary files
  git diff --numstat m0..."$b" | awk -F'\t' '$1=="-" {print $3}' | while IFS= read -r path; do
    size=$(git cat-file -s "$b:$path")
    printf '%s\t%s\t%s\n' "$b" "$size" "$path" >> "$out"
  done
done
echo "per branch and extension: count, bytes, largest"
awk -F'\t' '{n=split($3,a,"."); ext=tolower(a[n]); k=$1"\t"ext; c[k]++; s[k]+=$2; if($2>m[k])m[k]=$2} END {for(k in c) printf "%s\t%d\t%d\t%d\n", k, c[k], s[k], m[k]}' "$out" | sort
echo "totals by extension:"
awk -F'\t' '{n=split($3,a,"."); ext=tolower(a[n]); c[ext]++; s[ext]+=$2; if($2>m[ext])m[ext]=$2} END {for(k in c) printf "%s\t%d\t%d\t%d\n", k, c[k], s[k], m[k]}' "$out" | sort
echo "PNG by top directory:"
awk -F'\t' 'tolower($3) ~ /\.png$/ {split($3,a,"/"); d=a[1]"/"a[2]"/"a[3]; if (a[1]=="Packages") d=a[1]"/"a[2]"/"a[3]"/"a[4]"/"a[5]; c[d]++; s[d]+=$2; if($2>m[d])m[d]=$2} END {for(k in c) printf "%s\t%d\t%d\t%d\n", k, c[k], s[k], m[k]}' "$out" | sort
echo "all binaries total:"
awk -F'\t' '{c++; s+=$2} END {print c, s}' "$out"
echo "existing plain-git binaries in m0:"
git ls-tree -r -l m0 | awk '$5 ~ /\.(png|jpg|pdf|epub|mp3|m4a|m4b|caf|sqlite|bin|der)$/ {c++; s+=$4} END {print c, s}'
