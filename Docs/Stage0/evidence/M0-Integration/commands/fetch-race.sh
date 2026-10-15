#!/bin/bash
# Two concurrent Scripts/fixtures/fetch.sh runs of the same missing file into an empty scratch cache (G0.3 review
# R2-06, applied at M0 assembly): both must succeed, the file must have its pinned SHA-256 and mode 0644, and no
# temporary file may remain. Downloads one 6.4 MB public-domain file (the LibriVox Meditations section 02 MP3).
#   Docs/Stage0/evidence/M0-Integration/commands/fetch-race.sh > Docs/Stage0/evidence/M0-Integration/fetch-race.log
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cache="$root/.build/scratch/fetch-race-cache"
rm -rf "$cache"; mkdir -p "$cache"
echo "command: Docs/Stage0/evidence/M0-Integration/commands/fetch-race.sh"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); commit $(git -C "$root" rev-parse --short HEAD); cache: .build/scratch/fetch-race-cache (empty)"
name=meditationsofmarcusaurelius_02_aurelius_64kb
SYLVIA_FIXTURE_CACHE="$cache" "$root/Scripts/fixtures/fetch.sh" "$name" > "$cache/a.log" 2>&1 & a=$!
SYLVIA_FIXTURE_CACHE="$cache" "$root/Scripts/fixtures/fetch.sh" "$name" > "$cache/b.log" 2>&1 & b=$!
wait $a; sa=$?; wait $b; sb=$?
echo "run A exit $sa:"; sed 's/^/  /' "$cache/a.log"
echo "run B exit $sb:"; sed 's/^/  /' "$cache/b.log"
f="$cache/downloads/$name.mp3"
echo "sha256: $(shasum -a 256 "$f" | awk '{print $1}') (pinned df8a02987dd93dfed2147cc09b3d6bfadd8828e06f2aa438edc12a5f1ba56ded)"
echo "size: $(stat -f %z "$f"); mode: $(stat -f %Lp "$f")"
echo "other files in downloads/: $(ls -A "$cache/downloads" | grep -v "^$name.mp3$" | wc -l | tr -d ' ')"
rm -rf "$cache"
