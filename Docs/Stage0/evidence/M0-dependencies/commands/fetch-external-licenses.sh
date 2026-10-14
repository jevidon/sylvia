#!/bin/bash
# ADR-0014 evidence: license texts for third-party code that ships inside a pinned package but whose license file is not
# in the package checkout, fetched at the exact upstream version or revision the package records. Public HTTPS GETs
# only (GitHub raw files, the BoringSSL source browser, the npm registry); nothing from this repository is sent.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/fetch-external-licenses.sh <out dir> <swift-toolkit checkout>
#
# Writes each file under <out dir> and prints its URL, size and SHA-256. For the npm packages bundled into Readium's
# navigator scripts it reads the registry's version metadata and prints the declared license (metadata, not a license
# file). Downloads are data: nothing fetched is executed.
set -uo pipefail
OUT="$1"; TOOLKIT="$2"
# Downloads are untrusted data: they go into a new, empty directory that holds nothing else.
if [[ -e "$OUT" ]]; then echo "refusing: $OUT already exists; give a new directory" >&2; exit 2; fi
mkdir -p "$OUT/npm-metadata"
echo "fetch-external-licenses $(date -u +%Y-%m-%dT%H:%M:%SZ)"
fails=0
get() { # url file
  if curl --fail --location --silent --show-error --proto '=https' --max-time 60 --output "$OUT/$2" "$1"; then
    echo "$1 -> $2 ($(wc -c < "$OUT/$2" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$OUT/$2" | cut -d' ' -f1))"
  else
    echo "FAIL: $1"; fails=$((fails+1))
  fi
}
# Hypothesis client code vendored by Readium (Sources/Navigator/EPUB/Scripts/src/vendor/hypothesis/README.md names v1.1763.0).
get https://raw.githubusercontent.com/hypothesis/client/v1.1763.0/LICENSE hypothesis-client-v1.1763.0-LICENSE
# BoringSSL at the revisions recorded in swift-nio-ssl 2.37.5 and swift-crypto 5.0.0 (Sources/C*BoringSSL/hash.txt).
for rev in 817ab07ebb53da35afea409ab9328f578492832d 0226f30467f540a3f62ef48d453f93927da199b6; do
  get "https://boringssl.googlesource.com/boringssl/+/$rev/LICENSE?format=TEXT" "boringssl-$rev-LICENSE.base64"
  if [[ -f "$OUT/boringssl-$rev-LICENSE.base64" ]]; then
    base64 -D -i "$OUT/boringssl-$rev-LICENSE.base64" -o "$OUT/boringssl-$rev-LICENSE" && rm "$OUT/boringssl-$rev-LICENSE.base64"
    echo "  decoded: boringssl-$rev-LICENSE ($(wc -c < "$OUT/boringssl-$rev-LICENSE" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$OUT/boringssl-$rev-LICENSE" | cut -d' ' -f1)); first line: $(head -1 "$OUT/boringssl-$rev-LICENSE")"
  fi
done
# swift-crypto 5.0.0 also copies BoringSSL's third_party/fiat (compiled in by the curve25519 and P-256 code) without
# that directory's LICENSE, and BoringSSL's top-level LICENSE at 0226f304 no longer carries fiat's text (at swift-nio-ssl's
# 817ab07e it does). The directory's own LICENSE at that revision.
rev=0226f30467f540a3f62ef48d453f93927da199b6
get "https://boringssl.googlesource.com/boringssl/+/$rev/third_party/fiat/LICENSE?format=TEXT" "boringssl-$rev-third_party-fiat-LICENSE.base64"
if [[ -f "$OUT/boringssl-$rev-third_party-fiat-LICENSE.base64" ]]; then
  base64 -D -i "$OUT/boringssl-$rev-third_party-fiat-LICENSE.base64" -o "$OUT/boringssl-$rev-third_party-fiat-LICENSE" && rm "$OUT/boringssl-$rev-third_party-fiat-LICENSE.base64"
  echo "  decoded: boringssl-$rev-third_party-fiat-LICENSE ($(wc -c < "$OUT/boringssl-$rev-third_party-fiat-LICENSE" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$OUT/boringssl-$rev-third_party-fiat-LICENSE" | cut -d' ' -f1)); first line: $(head -1 "$OUT/boringssl-$rev-third_party-fiat-LICENSE")"
fi
# Minizip in marmelroy/Zip 2.1.2 says it is "distributed under the terms of the same license as zlib" but ships no
# license file; the zlib license text from zlib's own repository.
get https://raw.githubusercontent.com/madler/zlib/v1.3.1/LICENSE zlib-v1.3.1-LICENSE
# Minizip's crypt.h (compiled into the app: decrypt_byte, init_keys and update_keys are linked, linkage.log) is
# "a modified version of crypting code in Info-ZIP distribution" under "the Info-ZIP LICENSE file version 2000-Apr-09
# or later". The current version: the page as plain text (infozip-convert.py: tags removed, list items numbered,
# entities decoded) and the license itself cut from it (from "This is version" to its last condition).
get https://infozip.sourceforge.net/license.html infozip-license.html
if [[ -f "$OUT/infozip-license.html" ]]; then
  /usr/bin/python3 -I "$(dirname "$0")/infozip-convert.py" "$OUT/infozip-license.html" "$OUT/infozip-license-page.txt" "$OUT/infozip-license.txt"
  echo "  converted: infozip-license.txt ($(wc -c < "$OUT/infozip-license.txt" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$OUT/infozip-license.txt" | cut -d' ' -f1)); $(grep -m1 -o 'version [0-9A-Za-z-]* of the Info-ZIP license' "$OUT/infozip-license.txt")"
fi
# swift-nio 2.103.0 vendors uSHET's cpp_magic.h in Sources/CNIOAtomics/src (compiled and linked into the Mac source
# service); its header names the file at commit c09e0aca and "LICENSE: MIT" but the checkout holds no license for it
# (review R2-03). uSHET's own LICENSE at that commit.
get https://raw.githubusercontent.com/18sg/uSHET/c09e0acafd86720efe42dc15c63e0cc228244c32/LICENSE uSHET-c09e0acafd86720efe42dc15c63e0cc228244c32-LICENSE
# CryptoSwift 1.10.0 vendors Károly Lőrentey's BigInt as CS_BigInt ("Copyright © 2016-2017 Károly Lőrentey") and
# ships no license for it; the upstream project's license file at its 5.3.0 tag (same copyright years).
get https://raw.githubusercontent.com/attaswift/BigInt/v5.3.0/LICENSE.md attaswift-BigInt-v5.3.0-LICENSE.md
# OpenDyslexic 2.001 (bundled by Readium) names "http://opendyslexic.org/legal/" for the Bitstream license of the
# original glyphs. Try it over HTTPS; the result is recorded either way.
get https://opendyslexic.org/legal/ opendyslexic-legal.html
# The four npm runtime dependencies of Readium's navigator scripts, at the versions in its pnpm-lock.yaml.
# approx-string-match 1.1.0 publishes no LICENSE file in its npm package (README.md, package.json and dist/ only), so
# read package.json's declaration and look for the file in the source repository at the release tag.
get https://unpkg.com/approx-string-match@1.1.0/package.json approx-string-match-1.1.0-package.json
found=0
for tag in v1.1.0 1.1.0; do
  for name in LICENSE LICENSE.md LICENSE.txt; do
    url="https://raw.githubusercontent.com/robertknight/approx-string-match-js/$tag/$name"
    if curl --fail --location --silent --proto '=https' --max-time 60 --output "$OUT/approx-string-match-1.1.0-$name" "$url"; then
      echo "$url -> approx-string-match-1.1.0-$name ($(wc -c < "$OUT/approx-string-match-1.1.0-$name" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$OUT/approx-string-match-1.1.0-$name" | cut -d' ' -f1))"
      found=1; break 2
    else
      echo "not found: $url"
    fi
  done
done
(( found )) || echo "approx-string-match 1.1.0: no license file found at the release tag; license known only from package.json"
get https://unpkg.com/css-selector-generator@3.9.2/LICENSE css-selector-generator-3.9.2-LICENSE
get https://unpkg.com/@juggle/resize-observer@3.4.0/LICENSE juggle-resize-observer-3.4.0-LICENSE
get https://unpkg.com/string.prototype.matchall@4.0.12/LICENSE string.prototype.matchall-4.0.12-LICENSE

echo
echo "npm registry metadata (declared license) for the runtime closure of Readium's navigator scripts:"
"${SYLVIA_TOOLS_VENV:-$HOME/Library/Caches/SylviaTools/venv}/bin/python" -I "$(dirname "$0")/readium-js-closure.py" "$TOOLKIT" \
  | sed -n 's/^  \([^ ]*@[0-9][^ ]*\) *$/\1/p' > "$OUT/npm-closure.txt"
while read -r spec; do
  name="${spec%@*}"; ver="${spec##*@}"
  f="npm-metadata/$(echo "$name" | tr / _)-$ver.json"
  if curl --fail --location --silent --show-error --proto '=https' --max-time 60 --output "$OUT/$f" "https://registry.npmjs.org/$name/$ver"; then
    /usr/bin/python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1])); lic=d.get("license")
if isinstance(lic,dict): lic=lic.get("type")
print("  %s@%s: %s; repository %s" % (d.get("name"), d.get("version"), lic or d.get("licenses"), (d.get("repository") or {}).get("url") if isinstance(d.get("repository"),dict) else d.get("repository")))
' "$OUT/$f"
  else
    echo "  FAIL: $spec"; fails=$((fails+1))
  fi
done < "$OUT/npm-closure.txt"
echo
echo "finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
exit $fails
