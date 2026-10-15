#!/usr/bin/env bash
# Generates the 5 GiB deterministic file for the G0.2 bounded-memory transfer test (plan T38) into the
# fixture cache. Never committed.
#
#   $SYLVIA_FIXTURE_CACHE/generated/g02-transfer/large-5GiB.bin   5,368,709,120 bytes
#
# Content: the AES-128-CTR keystream for key 000102030405060708090a0b0c0d0e0f and an all-zero initial
# counter block, i.e. AES-CTR encryption of 5 GiB of zero bytes. It is incompressible, never repeats
# within the file (so a part served from the wrong offset cannot hash correctly), and any OpenSSL or
# LibreSSL build reproduces it exactly. The script verifies the result against the pinned SHA-256
# below and is idempotent: an existing file with the pinned digest is kept.
#
#   Scripts/fixtures/generate-g02-transfer-large.sh [--print-path]
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

readonly KEY="000102030405060708090a0b0c0d0e0f"
readonly IV="00000000000000000000000000000000"
readonly SIZE_MIB=5120
readonly SIZE_BYTES=$((SIZE_MIB * 1048576))
readonly EXPECTED_SHA256="d2383fe38d8033b62ef9e6222756369fab813d2c64b2bce41e86ad9494af16d9"  # identical with LibreSSL 3.3.6 and OpenSSL 3.6.3

out_dir="$SYLVIA_FIXTURE_CACHE/generated/g02-transfer"
out="$out_dir/large-5GiB.bin"
if [[ "${1:-}" == "--print-path" ]]; then echo "$out"; exit 0; fi

openssl_bin="$(command -v openssl || true)"
[[ -n "$openssl_bin" ]] || openssl_bin=/usr/bin/openssl

digest() { "$openssl_bin" dgst -sha256 -r "$1" | cut -d' ' -f1; }

if [[ -f "$out" ]] && [[ "$(stat -f %z "$out")" == "$SIZE_BYTES" ]]; then
  if [[ "$(digest "$out")" == "$EXPECTED_SHA256" ]]; then
    echo "present and verified: $out"
    exit 0
  fi
  echo "existing file has the wrong digest; regenerating" >&2
fi

mkdir -p "$out_dir"
tmp="$out.partial"
rm -f "$tmp"
dd if=/dev/zero bs=1048576 count="$SIZE_MIB" 2>/dev/null \
  | "$openssl_bin" enc -aes-128-ctr -nosalt -K "$KEY" -iv "$IV" > "$tmp"
size="$(stat -f %z "$tmp")"
if [[ "$size" != "$SIZE_BYTES" ]]; then
  echo "generated $size bytes, expected $SIZE_BYTES" >&2
  rm -f "$tmp"
  exit 1
fi
actual="$(digest "$tmp")"
if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
  echo "generated file SHA-256 $actual does not match the pinned $EXPECTED_SHA256" >&2
  rm -f "$tmp"
  exit 1
fi
mv "$tmp" "$out"
echo "generated and verified: $out ($SIZE_BYTES bytes, sha256 $actual)"
