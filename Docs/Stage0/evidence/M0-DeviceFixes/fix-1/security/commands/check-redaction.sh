#!/bin/bash
# M0 device fixes, fix-1, the security review of 26 October 2026 (finding S6): checks the two commands that the
# owner's README, Section 7.4, now gives for the ATS re-run's log, before that log is committed:
#   redact: the runbook's own one-liner (Docs/Stage0/M0-device-runbook.md, Session 4, "Addresses"), which cuts every
#           IPv4 address to its first two octets and the tailnet part of a MagicDNS name;
#   check:  a perl line that prints every line still holding a whole IPv4 address (nothing, once redacted).
# 1. The first run's log, Docs/Stage0/evidence/G05-AI/device/step-01-ats.log (the owner's record, read only): the check
#    prints nothing for it, as committed.
# 2. A round trip on that log's own address lines, in a scratch file under .build/scratch (never in the evidence
#    folder): each masked address <a.b>.x.x is given two made-up last octets, the redact command is run over the
#    scratch file, and the result is compared with the original lines. The made-up addresses are not written to the
#    log; only their count is.
# 3. Sample lines with RFC 5737 documentation addresses only (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24), shown
#    before and after: a URLError, a CFNetwork connection line, the probe's public-ip line, an IPv4-mapped IPv6
#    address, a MagicDNS name, and an iOS version that must stay as it is.
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/check-redaction.sh
# Log: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/redaction-check.log. Build Mac only; no network.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
out="Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/redaction-check.log"
scratch="$root/.build/scratch/security-fix/redaction"
first_run="Docs/Stage0/evidence/G05-AI/device/step-01-ats.log"
mkdir -p "$scratch"
redact() { perl -pi -e 's/\b(\d{1,3}\.\d{1,3})\.\d{1,3}\.\d{1,3}\b/$1.x.x/g; s/\.[A-Za-z0-9-]+\.ts\.net\b/.[tailnet].ts.net/g' "$@"; }
check() { perl -ne 'print if /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/' "$@"; }
status=0
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/check-redaction.sh"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD)); time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "redact (the runbook's command, M0-device-runbook.md line $(grep -n 'perl -pi -e' Docs/Stage0/M0-device-runbook.md | head -1 | cut -d: -f1)):"
  echo "  perl -pi -e 's/\\b(\\d{1,3}\\.\\d{1,3})\\.\\d{1,3}\\.\\d{1,3}\\b/\$1.x.x/g; s/\\.[A-Za-z0-9-]+\\.ts\\.net\\b/.[tailnet].ts.net/g' <file>"
  echo "  (the runbook's text: $(grep -o "perl -pi -e '[^']*'" Docs/Stage0/M0-device-runbook.md | head -1))"
  echo "check: perl -ne 'print if /\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b/' <file>"
  echo
  echo "== 1. the check on the first run's log, $first_run, as committed"
  found="$(check "$first_run" | wc -l | tr -d ' ')"
  echo "lines with a whole IPv4 address: $found (expected 0)"
  [[ "$found" == 0 ]] || status=1
  echo
  echo "== 2. round trip on the first run's address lines (scratch copy)"
  grep -E '[0-9]{1,3}\.[0-9]{1,3}\.x\.x' "$first_run" > "$scratch/masked.txt"
  perl -pe 'my $n = 0; s/\b(\d{1,3}\.\d{1,3})\.x\.x\b/$1 . "." . (17 + $n) . "." . (200 + $n++)/ge' "$scratch/masked.txt" > "$scratch/unmasked.txt"
  echo "address lines taken: $(wc -l < "$scratch/masked.txt" | tr -d ' '); whole addresses written into the scratch copy: $(perl -ne '$c += () = /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g; END { print $c + 0 }' "$scratch/unmasked.txt"); lines with one before redaction: $(check "$scratch/unmasked.txt" | wc -l | tr -d ' ')"
  cp "$scratch/unmasked.txt" "$scratch/redacted.txt"
  redact "$scratch/redacted.txt"
  echo "after redact: lines with a whole IPv4 address: $(check "$scratch/redacted.txt" | wc -l | tr -d ' ') (expected 0)"
  if cmp -s "$scratch/redacted.txt" "$scratch/masked.txt"; then
    echo "after redact: identical to the first run's masked lines: yes"
  else
    echo "after redact: identical to the first run's masked lines: NO"; status=1
    diff "$scratch/masked.txt" "$scratch/redacted.txt" | head -10
  fi
  [[ "$(check "$scratch/redacted.txt" | wc -l | tr -d ' ')" == 0 ]] || status=1
  echo
  echo "== 3. sample lines, documentation addresses only (RFC 5737)"
  cat > "$scratch/samples.txt" <<'EOF'
), NSLocalizedDescription=Could not connect to the server., NSErrorFailingURLStringKey=http://192.0.2.23:58688/v1/models, NSErrorFailingURLKey=http://192.0.2.23:58688/v1/models, _kCFStreamErrorDomainKey=1}
[connection] nw_endpoint_flow_failed_with_error [C3.1.1 198.51.100.7:58688 in_progress socket-flow (satisfied (Path is satisfied), viable, interface: en0[802.11])] already failing, returning
ATS-PROBE variant=default public-ip=192.0.2.1 result=URLError -1022 ats-blocked=true
local: ::ffff:203.0.113.9.58688, remote: [::ffff:203.0.113.10]:443
connecting to mac.example-tailnet.ts.net:47800
[evidence] [device (Version 27.0.1 (Build 24A446))] iOS 27.0.1 stays as it is
EOF
  cp "$scratch/samples.txt" "$scratch/samples-redacted.txt"
  redact "$scratch/samples-redacted.txt"
  echo "-- before"; cat "$scratch/samples.txt"
  echo "-- after redact"; cat "$scratch/samples-redacted.txt"
  echo "-- check after redact (prints nothing when every address is cut):"
  check "$scratch/samples-redacted.txt"
  [[ "$(check "$scratch/samples-redacted.txt" | wc -l | tr -d ' ')" == 0 ]] || status=1
  grep -q 'Version 27.0.1 (Build 24A446)' "$scratch/samples-redacted.txt" || status=1
  echo
  echo "exit: $status"
} > "$out" 2>&1
cat "$out"
exit $status
