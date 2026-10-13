#!/usr/bin/env bash
# G0.4 merge (M0 integration): the binary files the G0.4 squash commit adds (read with git, no checkout), their sizes,
# the git attributes that apply to them, and whether each is a real PNG rather than a Git LFS pointer.
#   Docs/Stage0/evidence/M0-Integration/commands/g04-binary-files.sh <squash commit> > Docs/Stage0/evidence/M0-Integration/g04-binary-files.txt
set -euo pipefail
cd "$(dirname "$0")/../../../../.."
squash="${1:?usage: g04-binary-files.sh <G0.4 squash commit>}"
echo "# Command: Docs/Stage0/evidence/M0-Integration/commands/g04-binary-files.sh $squash; $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# Binary files (git diff --numstat shows - -) added by $(git log -1 --format='%h %s' "$squash" | cut -c1-80)..."
echo "# .gitattributes in the tree: $(git ls-tree --name-only "$squash" -- .gitattributes | grep -c . || true); filter.lfs configured: $(git config --get-regexp '^filter\.lfs\.' | grep -c . || true)"
printf 'bytes\tfirst bytes\tattributes\tpath\n'
count=0; total=0; largest=0
while IFS= read -r path; do
  size="$(git cat-file -s "$squash:$path")"
  magic="$(git cat-file blob "$squash:$path" | head -c 8 | xxd -p || true)"  # head closes the pipe early (SIGPIPE)
  attrs="$(git check-attr -a -- "$path" | sed "s|^$path: ||" | paste -sd ',' -)"
  printf '%s\t%s\t%s\t%s\n' "$size" "$magic" "${attrs:-none}" "$path"
  count=$((count + 1)); total=$((total + size)); (( size > largest )) && largest=$size
done < <(git diff --numstat "$squash^" "$squash" | awk -F'\t' '$1 == "-" {print $3}')
echo "# $count binary files, $total bytes, largest $largest (89504e470d0a1a0a is the PNG signature; an LFS pointer starts with 'version https://git-lfs')"

# With a base (the main merge on m0-integrate, cf88104): every binary file the eight gate merges added up to the
# squash, for the ADR-0002 measurement.
base="${2:-}"
[[ -n "$base" ]] || exit 0
echo
echo "# All binary files added from $base to $squash (the eight gate squash merges and the integration commits):"
git diff --numstat "$base" "$squash" | awk -F'\t' '$1 == "-" {print $3}' | while IFS= read -r path; do
  printf '%s\t%s\n' "$(git cat-file -s "$squash:$path")" "$path"
done | awk -F'\t' '
  { n = split($2, part, "."); ext = tolower(part[n]); c[ext]++; s[ext] += $1; total += $1; files++
    if (ext == "png") { area = ($2 ~ /^Docs\/Stage0\/evidence\//) ? "evidence " (split($2, d, "/") ? d[4] : "") : (($2 ~ /\/__Snapshots__\//) ? "snapshot references" : "other")
                        a[area]++; as[area] += $1; if ($1 > largest) largest = $1 } }
  END { printf "total\t%d files\t%d bytes\n", files, total
        for (e in c) printf "extension %s\t%d files\t%d bytes\n", e, c[e], s[e]
        for (k in a) printf "png %s\t%d files\t%d bytes\n", k, a[k], as[k]
        printf "largest png\t%d bytes\n", largest }' | LC_ALL=C sort
