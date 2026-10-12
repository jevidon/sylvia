#!/usr/bin/env bash
# Generates the small certificate fixtures used by the G0.2 SPKI pin tests (committed, a few hundred
# bytes each) and the expected pin of each, computed independently with OpenSSL:
#
#   SHA-256( DER(SubjectPublicKeyInfo) ) = openssl x509 -pubkey | openssl pkey -pubin -outform der | sha256
#
# Keys are random, so re-running changes the files; the tests read the expected pin from the
# matching .spki-sha256 file, so any regenerated set stays self-consistent. The private keys are
# discarded: these certificates are test data, not identities.
#
#   Scripts/fixtures/generate-g02-transfer-test-certs.sh [output-dir]
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

out="${1:-$SYLVIA_ROOT/Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/Fixtures/certs}"
mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

make_cert() {
  local name="$1"; shift
  openssl req -x509 -new -nodes -days 3650 -subj "/CN=Sylvia G0.2 test $name" \
    -keyout "$work/$name.key" -out "$work/$name.pem" "$@" 2>/dev/null
  openssl x509 -in "$work/$name.pem" -outform der -out "$out/$name.der"
  openssl x509 -in "$work/$name.pem" -pubkey -noout \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -r | cut -d' ' -f1 > "$out/$name.spki-sha256"
}

make_cert p256 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -sha256
make_cert rsa2048 -newkey rsa:2048 -sha256
make_cert p384 -newkey ec -pkeyopt ec_paramgen_curve:P-384 -sha384

ls -l "$out"
