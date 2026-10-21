#!/bin/bash
# Controls for the M0 final review round 2 finding CC2-03 (the G0.2 trust guards and the hard-rule audit missed a
# server-trust credential whose type Swift infers, and TLS minimums below 1.2 set through Network.framework, passed as a
# NIOSSL argument or written with the deprecated SSLProtocol values):
#   1. The planted Swift forms compile in Swift 6 (host typecheck; the NIOSSL argument form needs the package and is a
#      text form only), so the guards must catch them.
#   2. The current trust guards' and audit's self-tests pass.
#   3. Copies with the patterns of 83ee280 (the commit the round-2 review read) put back fail those self-tests in
#      exactly the new cases: the self-tests notice the gap the fix closes.
# Read-only for the repository: every copy and planted file is under .build/scratch/guard-controls-2.
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/guard-controls.sh > <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scratch="$root/.build/scratch/guard-controls-2"
rm -rf "$scratch"; mkdir -p "$scratch"
base=83ee28007517a9e41384a156f2ed647bb68de432
echo "command: Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/guard-controls.sh"
echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); load: $(uptime)"
status=0

echo
echo "== 1. the planted forms typecheck in Swift 6 (xcrun swiftc -typecheck -swift-version 6, host)"
# Assembled here so that this script holds none of the forms literally (the audit reads shell scripts).
init_trust=".in""it(trust:"
min_tls="sec_protocol_options_set_min_tls""_protocol_version"
old_protocol=".tls""Protocol1"
cat > "$scratch/planted.swift" <<SWIFT
import Foundation
import Network
final class InferredTrustAll: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, ${init_trust} c.protectionSpace.serverTrust!))
    }
}
func lowerNetwork(_ options: NWProtocolTLS.Options) {
    ${min_tls}(options.securityProtocolOptions, .TLSv10)
}
func legacy(_ configuration: URLSessionConfiguration) {
    configuration.tlsMinimumSupportedProtocol = ${old_protocol}
}
SWIFT
if xcrun swiftc -typecheck -swift-version 6 "$scratch/planted.swift" > "$scratch/typecheck.out" 2>&1; then
  echo "typecheck: exit 0 (each form compiles)"
else
  echo "typecheck: FAILED"; status=1
fi
sed -e "s#$scratch/##" "$scratch/typecheck.out" | grep -E "error|warning" | sed 's/^/  /' || true

echo
echo "== 2. the self-tests of the current guards"
python3 -I Spikes/G02-Transfer/Scripts/trust-guards.py --self-test Spikes/G02-Transfer "$scratch/tg-current" > "$scratch/tg-current.out" 2>&1
tg=$?
sed -e "s#$scratch/##" "$scratch/tg-current.out"
echo "trust-guards.py --self-test exit: $tg"
(( tg == 0 )) || status=1
Scripts/audit-hard-rules.sh self-test > "$scratch/audit-current.out" 2>&1
au=$?
grep -E "^(ok|FAIL|self-test)" "$scratch/audit-current.out"
echo "audit-hard-rules.sh self-test exit: $au"
(( au == 0 )) || status=1

echo
echo "== 3a. trust-guards.py with the patterns of ${base:0:7} put back: the new cases must fail the self-test"
mkdir -p "$scratch/old-tg/Spikes/G02-Transfer/Scripts"
python3 -I - "$root/Spikes/G02-Transfer/Scripts/trust-guards.py" "$scratch/old-tg/Spikes/G02-Transfer/Scripts/trust-guards.py" \
  "$(git -C "$root" show "$base:Spikes/G02-Transfer/Scripts/trust-guards.py")" <<'PY'
import re, sys
current, target, old = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2], sys.argv[3]
def block(text, name):
    # The definition, which may span lines, up to the next top-level assignment or comment line.
    return re.search(rf"\n{name} = re\.compile\(.*?(?=\n(?:[A-Z_]+ = |# ))", text, re.S).group(0)
for name in ("CREDENTIAL", "WEAK_TLS"):
    new_block, old_block = block(current, name), block(old, name)
    assert new_block != old_block, name
    current = current.replace(new_block, old_block)
open(target, "w", encoding="utf-8").write(current)
PY
python3 -I "$scratch/old-tg/Spikes/G02-Transfer/Scripts/trust-guards.py" --self-test Spikes/G02-Transfer "$scratch/tg-old" \
  > "$scratch/tg-old.out" 2>&1
tgo=$?
sed -e "s#$scratch/##" "$scratch/tg-old.out"
echo "self-test exit with the old patterns: $tgo"
failing="$(grep -c '^FAIL: ' "$scratch/tg-old.out")"
want=4
for case in "a server-trust credential whose type Swift infers" "a TLS 1.0 minimum set through Network.framework" \
            "a TLS 1.1 minimum passed as an argument" "a deprecated SSLProtocol minimum"; do
  grep -q "^FAIL: $case" "$scratch/tg-old.out" || { echo "PROBLEM: the old patterns did not fail '$case'"; status=1; }
done
if (( tgo != 0 && failing == want )); then
  echo "control: as expected, exactly the $want new cases fail with the old patterns"
else
  echo "PROBLEM: expected exactly $want failing cases, got $failing"; status=1
fi

echo
echo "== 3b. audit-hard-rules.sh with the patterns of ${base:0:7} put back: the new planted lines must be missing"
mkdir -p "$scratch/old-audit/Scripts"
python3 -I - "$root/Scripts/audit-hard-rules.sh" "$scratch/old-audit/Scripts/audit-hard-rules.sh" \
  "$(git -C "$root" show "$base:Scripts/audit-hard-rules.sh")" <<'PY'
import sys
current, target, old = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2], sys.argv[3]
def block(text, start_marker, end_marker):
    start = text.index(start_marker)
    return text[start:text.index(end_marker, start)]
for start_marker, end_marker in (("TRUST = [", "\nWEAK_TLS = ["), ("WEAK_TLS = [", "\nPROTECTION = [")):
    current = current.replace(block(current, start_marker, end_marker), block(old, start_marker, end_marker))
open(target, "w", encoding="utf-8").write(current)
PY
chmod +x "$scratch/old-audit/Scripts/audit-hard-rules.sh"
# The copy's self-test writes its planted tree under the copy's own .build/scratch.
"$scratch/old-audit/Scripts/audit-hard-rules.sh" self-test > "$scratch/audit-old.out" 2>&1
auo=$?
grep -E "^(ok|FAIL|self-test)" "$scratch/audit-old.out"
echo "self-test exit with the old patterns: $auo"
missing="$(grep -m1 -o "missing \[[^]]*\]" "$scratch/audit-old.out" || true)"
echo "first 'missing' list: $missing"
expected_missing="('trust-override', 'Sources/Inferred.swift', 5), ('trust-override', 'Sources/Wrapped.swift', 13), ('weak-tls', 'Sources/Inferred.swift', 9), ('weak-tls', 'Sources/Inferred.swift', 11), ('weak-tls', 'Sources/Inferred.swift', 13), ('weak-tls', 'Sources/Wrapped.swift', 10)"
if (( auo != 0 )) && [[ "$missing" == "missing [$expected_missing]" ]]; then
  echo "control: as expected, exactly the 6 new planted lines are missed with the old patterns"
else
  echo "PROBLEM: expected the 6 new planted lines to be the only missing ones"; status=1
fi
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
