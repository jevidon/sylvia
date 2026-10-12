#!/usr/bin/env bash
# Generates the deterministic files the G0.2 part 2 simulator runs serve from sylvia-test-source, into the
# fixture cache. Never committed.
#
#   $SYLVIA_FIXTURE_CACHE/generated/g02-transfer/sim-<name>.bin
#
# Content of each file: the AES-128-CTR keystream for the key listed below and an all-zero initial counter
# block (AES-CTR encryption of zero bytes), cut to the listed size. Incompressible and never repeating
# within a file, so a part served from the wrong offset cannot hash correctly; reproducible with any
# OpenSSL or LibreSSL. Each file is checked against its pinned SHA-256; an existing file with the pinned
# digest is kept.
#
#   Scripts/fixtures/generate-g02-transfer-sim-files.sh [--print-dir]
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

out_dir="$SYLVIA_FIXTURE_CACHE/generated/g02-transfer"
if [[ "${1:-}" == "--print-dir" ]]; then echo "$out_dir"; exit 0; fi

# name  size-in-bytes  key  pinned-sha256 (identical with OpenSSL 3.6.3 and LibreSSL 3.3.6, 7 Oct 2026)
readonly FILES="
small   20971520  101112131415161718191a1b1c1d1e1f  e76e2ff5c286c57e226dc4b48d0df48454a384641f56b12d1ab88093945d4fa8
faulty  52428800  202122232425262728292a2b2c2d2e2f  999b2aa664588e452824beee0af6ee8084f350b11cd155882d49530377d6bc92
slow    25165824  303132333435363738393a3b3c3d3e3f  ed42f79b57070bbff5b7d24c8a910dbd5ec3d88c7a7b66b0bb2b55f90ded733b
ui      41943040  404142434445464748494a4b4c4d4e4f  c7be91e45e30c3aa59726bd3fb87705c01e2d69d0631d8d371b58b447ab2faab
"

openssl_bin="$(command -v openssl || true)"
[[ -n "$openssl_bin" ]] || openssl_bin=/usr/bin/openssl
digest() { "$openssl_bin" dgst -sha256 -r "$1" | cut -d' ' -f1; }

mkdir -p "$out_dir"
status=0
while read -r name size key pinned; do
  [[ -n "$name" ]] || continue
  out="$out_dir/sim-$name.bin"
  if [[ -f "$out" && "$(stat -f %z "$out")" == "$size" && "$(digest "$out")" == "$pinned" ]]; then
    echo "present and verified: $out"
    continue
  fi
  tmp="$out.partial"
  "$openssl_bin" enc -aes-128-ctr -nosalt -K "$key" -iv 00000000000000000000000000000000 -in /dev/zero 2>/dev/null \
    | head -c "$size" > "$tmp" || true
  actual="$(digest "$tmp")"
  if [[ "$(stat -f %z "$tmp")" != "$size" || "$actual" != "$pinned" ]]; then
    echo "sim-$name.bin: $(stat -f %z "$tmp") bytes, sha256 $actual; pinned $size bytes, $pinned" >&2
    rm -f "$tmp"
    status=1
    continue
  fi
  mv "$tmp" "$out"
  echo "generated and verified: $out ($size bytes, sha256 $actual)"
done <<< "$FILES"
exit "$status"
