#!/usr/bin/env python3
"""Static guards against a trust bypass in the G0.2 transfer spike (plan 14.3, 22.3; ADR-0008). Run by the
trust-guards step of Scripts/ci.d/40-g02-transfer.sh; the behavior itself is proven by the rogue-host and wrong-pin
tests, and these guards catch configuration that would weaken it.

    python3 -I Spikes/G02-Transfer/Scripts/trust-guards.py <spike directory>
    python3 -I Spikes/G02-Transfer/Scripts/trust-guards.py --self-test <spike directory> <scratch directory>

The guards, in order (each prints one "ok:" line, or the hits and exit status 1):
  arbitrary-loads   NSAllowsArbitraryLoads (or ...InWebContent, ...ForMedia) appears in no scanned file, comments
                    included.
  ats-keys          no App Transport Security key outside the probe variants' plists iOS/Config/ATSVariant-*.plist,
                    which build the never-shipped G02TransferATSVariant; whole-line Swift comments, the harness plist's
                    "Deliberately absent" note and ATSProbeTests' three readings of the key are not configuration.
  harness-plist     the G02TransferHarness target of iOS/project.yml uses no ATS variant plist.
  trust-credential  a server-trust credential is created exactly once, in
                    TransferKit/Sources/SylviaTransferClient/PinnedSession.swift (PinnedTrustEvaluator.answer). Both
                    spellings are counted: URLCredential's initializer named, and an initializer with the trust label
                    whose type Swift infers from the completion handler (".init" and "trust:"; M0 final review round 2,
                    CC2-03: a delegate that answers every challenge that way is a trust-all, and the guard missed it).
  weak-tls          no TLS minimum below 1.2 in the Swift sources: URLSessionConfiguration's version property, NIOSSL's
                    minimumTLSVersion set or passed as an argument, Network.framework's
                    sec_protocol_options_set_min_tls_protocol_version with a 1.0 or 1.1 value (CC2-03), the
                    deprecated SSLProtocol values (tlsProtocol1, tlsProtocol11, sslProtocol2, 3 and All) and their C
                    names.

Scanned: files with the extensions in SCANNED below the spike directory. Paths are relative to the spike directory,
and a directory named .build, DerivedData, .swiftpm or .git below it is skipped by its name, so a checkout that itself
lies under a directory named .build (an agent's clone under .build/scratch/) is checked like any other. M0 final review
CC-01: the earlier grep dropped every hit whose absolute path contained /.build/, so in such a checkout these guards
printed their ok lines without having seen anything. Swift sources are matched as whole files with their whole-line
comments blanked, so a call written across lines is seen (M0 final review SEC-01: the earlier grep read one line at a
time).

The self-test copies the scanned files into <scratch directory>/<...>/.build/self-test/Spikes/G02-Transfer (a path
that contains /.build/), checks that the unchanged copy passes, and then plants one violation per guard in a fresh copy
each time, checking that exactly that guard fails; a violation inside a nested build directory and a key named in a
Swift comment must not fail. Planted values are assembled at run time, so this file contains none of them.
"""
from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

SKIPPED_DIRECTORIES = {".build", "DerivedData", ".swiftpm", ".git"}
SCANNED = {".swift", ".yml", ".yaml", ".plist", ".json", ".xcconfig", ".entitlements"}

ARBITRARY = re.compile(r"\bNSAllowsArbitraryLoads(?:InWebContent|ForMedia)?\b")
ATS_KEYS = re.compile(r"NSAppTransportSecurity|NSAllowsLocalNetworking|NSExceptionDomains"
                      r"|NS(?:|ThirdParty|Temporary)Exception(?:AllowsInsecureHTTPLoads|MinimumTLSVersion|RequiresForwardSecrecy)")
# A credential from a server trust: URLCredential's initializer, named or with its type inferred (".init" alone).
CREDENTIAL = re.compile(r"(?:URLCredential\s*(?:\.init)?|\.init)\s*\(\s*trust\s*:")
# The deprecated SSLProtocol values are written with a character class, so that this file holds none of them literally.
WEAK_TLS = re.compile(r"tlsMinimumSupportedProtocolVersion\s*=\s*\.TLSv1[01]\b|minimumTLSVersion\s*[=:]\s*\.tlsv1[01]?\b"
                      r"|sec_protocol_options_set_min_tls_protocol_version\s*\([^)]*\.TLSv1[01]\b"
                      r"|\btls_protocol_version_TLSv1[01]\b|\bkTLSProtocol1[01]?\b|\bkSSLProtocol(?:2|3|All)\b"
                      r"|\.tls[P]rotocol1[01]?\b|\.ssl[P]rotocol(?:2|3|All)\b")
PINNED_ANSWER = "TransferKit/Sources/SylviaTransferClient/PinnedSession.swift"
ATS_VARIANT = re.compile(r"^iOS/Config/ATSVariant-[a-z-]*\.plist$")
HARNESS_NOTE = ("iOS/Config/Harness-Info.plist", re.compile(r"^  Deliberately absent: NSAppTransportSecurity\."))
PROBE_READINGS = ("iOS/Tests/HostedUnit/ATSProbeTests.swift",
                  re.compile(r'forInfoDictionaryKey: "NSAppTransportSecurity"|Info\.plist NSAppTransportSecurity'
                             r"|no NSAppTransportSecurity key"))
CREDENTIAL_NAME = "URLCredential" + "(trust:)"  # assembled, so that this file is not itself a hit of the hard-rule audit


def scanned_files(spike: Path) -> list[str]:
    """Every scanned file below the spike directory, as a path relative to it, build directories skipped by name."""
    found = []
    for directory, subdirectories, files in os.walk(spike):
        subdirectories[:] = sorted(d for d in subdirectories if d not in SKIPPED_DIRECTORIES)
        for name in sorted(files):
            path = Path(directory, name)
            if path.suffix.lower() in SCANNED and path.is_file() and not path.is_symlink():
                found.append(path.relative_to(spike).as_posix())
    return found


def read(spike: Path, relative: str) -> str:
    return (spike / relative).read_text(encoding="utf-8", errors="replace")


def code_text(relative: str, text: str) -> str:
    """Swift whole-line comments (// and ///) blanked, line count kept; other files unchanged."""
    if not relative.endswith(".swift"):
        return text
    return "\n".join("" if line.lstrip().startswith("//") else line for line in text.split("\n"))


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def hits_in(spike: Path, files: list[str], pattern: re.Pattern, *, code: bool, swift_only: bool = False) -> list[str]:
    out = []
    for relative in files:
        if swift_only and not relative.endswith(".swift"):
            continue
        raw = read(spike, relative)
        text = code_text(relative, raw) if code else raw
        lines = raw.split("\n")
        for match in pattern.finditer(text):
            number = line_of(text, match.start())
            out.append(f"{relative}:{number}: {lines[number - 1].strip()[:160]}")
    return out


def harness_section(spike: Path) -> list[str]:
    """The G02TransferHarness target's lines in iOS/project.yml (up to the next target)."""
    lines, inside = [], False
    for line in read(spike, "iOS/project.yml").split("\n"):
        if line.startswith("  G02TransferHarness:"):
            inside = True
        elif inside and re.match(r"^  [A-Za-z0-9_]+:\s*$", line):
            break
        if inside:
            lines.append(line)
    return lines


def guards(spike: Path) -> list[tuple[str, bool, list[str]]]:
    """Each guard's name, whether it passed, and its output lines."""
    files = scanned_files(spike)
    results = []

    hits = hits_in(spike, files, ARBITRARY, code=False)
    results.append(("arbitrary-loads", not hits,
                    ["NSAllowsArbitraryLoads found:"] + hits if hits else ["ok: NSAllowsArbitraryLoads appears nowhere"]))

    hits = []
    for hit in hits_in(spike, files, ATS_KEYS, code=True):
        relative, number, _ = hit.split(":", 2)
        line = read(spike, relative).split("\n")[int(number) - 1]
        if ATS_VARIANT.match(relative):
            continue
        if relative == HARNESS_NOTE[0] and HARNESS_NOTE[1].match(line):
            continue
        if relative == PROBE_READINGS[0] and PROBE_READINGS[1].search(line):
            continue
        hits.append(hit)
    results.append(("ats-keys", not hits, ["ATS keys outside the probe variants:"] + hits if hits else [
        "ok: no App Transport Security key in the harness; ATS keys only in iOS/Config/ATSVariant-*.plist (probe app); "
        "Swift comment lines that name a key are not configuration and are ignored"]))

    section = harness_section(spike)
    bad = [line.strip() for line in section if "ATSVariant" in line]
    if not section:
        results.append(("harness-plist", False, ["iOS/project.yml has no G02TransferHarness target"]))
    else:
        results.append(("harness-plist", not bad, ["the harness target uses an ATS variant plist:"] + bad if bad else [
            "ok: G02TransferHarness uses Config/Harness-Info.plist only"]))

    hits = hits_in(spike, files, CREDENTIAL, code=True, swift_only=True)
    ok = len(hits) == 1 and hits[0].startswith(PINNED_ANSWER + ":")
    results.append(("trust-credential", ok, [
        f"ok: {CREDENTIAL_NAME} appears once, in PinnedTrustEvaluator.answer (PinnedSession.swift), used by every session"]
        if ok else ["a server-trust credential is created outside the pinned answer:"] + (hits or ["(none found)"])))

    hits = hits_in(spike, files, WEAK_TLS, code=True, swift_only=True)
    results.append(("weak-tls", not hits, ["TLS below 1.2 allowed:"] + hits if hits else ["ok: no TLS minimum below 1.2"]))
    return results


def run(spike: Path) -> int:
    files = scanned_files(spike)
    print(f"environment: host; static checks over Spikes/G02-Transfer ({len(files)} files: "
          f"{', '.join(sorted(SCANNED))}; directories named {', '.join(sorted(SKIPPED_DIRECTORIES))} skipped)")
    status = 0
    for _, passed, lines in guards(spike):
        print("\n".join(lines))
        if not passed:
            status = 1
    return status


def self_test(spike: Path, scratch: Path) -> int:
    base = scratch / ".build" / "self-test" / "Spikes" / "G02-Transfer"
    a = lambda *parts: "".join(parts)  # noqa: E731  (planted values assembled at run time)
    plist = lambda body: f'<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n{body}\n</dict></plist>\n'  # noqa: E731
    cases = [
        ("the unchanged copy, under a path that contains /.build/", None, None),
        ("NSAllowsArbitraryLoads in a planted plist", [("write", "iOS/Config/Planted-Info.plist",
            plist(a("<key>NSApp", "TransportSecurity</key><dict><key>NSAllows", "ArbitraryLoads</key><true/></dict>")))],
         {"arbitrary-loads", "ats-keys"}),
        ("an ATS key in a planted plist", [("write", "iOS/Config/Planted-Info.plist",
            plist(a("<key>NSApp", "TransportSecurity</key><dict><key>NSAllows", "LocalNetworking</key><true/></dict>")))],
         {"ats-keys"}),
        ("an ATS key in a JSON project spec", [("write", "iOS/project.json",
            a('{"targets": {"X": {"info": {"properties": {"NSApp', 'TransportSecurity": {"NSException', 'Domains": {}}}}}}}\n'))],
         {"ats-keys"}),
        ("the harness target given an ATS variant plist", [("replace", "iOS/project.yml",
            "INFOPLIST_FILE: Config/Harness-Info.plist", "INFOPLIST_FILE: Config/ATSVariant-local-networking.plist")],
         {"harness-plist"}),
        ("a second server-trust credential written across two lines", [("write", "TransferKit/Sources/SylviaTransferClient/Planted.swift",
            a("import Foundation\nfunc planted(_ t: SecTrust) -> URLCredential {\n    URLCredential", "(\n        trust: t)\n}\n"))],
         {"trust-credential"}),
        ("a TLS 1.0 minimum", [("write", "TransferKit/Sources/SylviaTransferCore/Planted.swift",
            a("import Foundation\nlet c = URLSessionConfiguration.ephemeral\nfunc f() { c.tlsMinimumSupported", "ProtocolVersion =\n    .TLSv10 }\n"))],
         {"weak-tls"}),
        # M0 final review round 2, CC2-03: forms that compile in Swift 6 and that the guards missed.
        ("a server-trust credential whose type Swift infers, answering every challenge", [("write",
            "TransferKit/Sources/SylviaTransferClient/Planted.swift",
            a("import Foundation\nfinal class Planted: NSObject, URLSessionDelegate {\n",
              "    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,\n",
              "                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {\n",
              "        completionHandler(.useCredential, .in", "it(trust: c.protectionSpace.serverTrust!))\n    }\n}\n"))],
         {"trust-credential"}),
        ("a TLS 1.0 minimum set through Network.framework", [("write", "TransferKit/Sources/SylviaTransferCore/Planted.swift",
            a("import Network\nlet o = NWProtocolTLS.Options()\nfunc f() {\n    sec_protocol_options_set_min_tls",
              "_protocol_version(o.securityProtocolOptions,\n        .TLS", "v10)\n}\n"))],
         {"weak-tls"}),
        ("a TLS 1.1 minimum passed as an argument", [("write", "SourceService/Sources/SylviaSourceService/Planted.swift",
            a("struct Settings { var minimumTLSVersion: Int }\nfunc f() { _ = Settings(minimumTLS", "Version: .tlsv11) }\n"))],
         {"weak-tls"}),
        ("a deprecated SSLProtocol minimum", [("write", "TransferKit/Sources/SylviaTransferCore/Planted.swift",
            a("import Foundation\nlet c = URLSessionConfiguration.ephemeral\nfunc f() { c.tlsMinimumSupportedProtocol = .tls",
              "Protocol1 }\n"))],
         {"weak-tls"}),
        ("TLS 1.2 minimums in the same forms are not findings", [("write", "TransferKit/Sources/SylviaTransferCore/Planted.swift",
            a("import Network\nlet o = NWProtocolTLS.Options()\nfunc f() {\n    sec_protocol_options_set_min_tls",
              "_protocol_version(o.securityProtocolOptions, .TLSv12)\n    _ = Settings(minimumTLSVersion: .tlsv12)\n",
              "    c.tlsMinimumSupportedProtocol = .tlsProtocol12\n}\n"))],
         set()),
        ("a violation inside a nested build directory is not the spike's", [("write", "TransferKit/.build/checkouts/x/Planted-Info.plist",
            plist(a("<key>NSAllows", "ArbitraryLoads</key><true/>")))], set()),
        ("an ATS key named in a Swift comment line", [("write", "TransferKit/Sources/SylviaTransferCore/Comment.swift",
            a("// NSApp", "TransportSecurity is never set by this module\nlet commentOnly = 1\n"))], set()),
    ]
    failures = 0
    print(f"self-test: copies of the scanned files under {base} (the path contains /.build/)")
    for name, operations, expected in cases:
        if base.exists():
            shutil.rmtree(base)
        for relative in scanned_files(spike):
            target = base / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(spike / relative, target)
        for operation in operations or []:
            if operation[0] == "write":
                (base / operation[1]).parent.mkdir(parents=True, exist_ok=True)
                (base / operation[1]).write_text(operation[2], encoding="utf-8")
            else:
                text = (base / operation[1]).read_text(encoding="utf-8")
                if operation[2] not in text:
                    print(f"FAIL: {name}: the text to replace is not in {operation[1]}")
                    failures += 1
                    continue
                (base / operation[1]).write_text(text.replace(operation[2], operation[3], 1), encoding="utf-8")
        failed = {guard for guard, passed, _ in guards(base) if not passed}
        want = expected or set()
        good = failed == want
        failures += 0 if good else 1
        print(f"{'ok' if good else 'FAIL'}: {name}: "
              + (f"fails {', '.join(sorted(failed))}" if failed else "passes")
              + ("" if good else f" (expected {'to fail ' + ', '.join(sorted(want)) if want else 'to pass'})"))
    shutil.rmtree(scratch / ".build" / "self-test", ignore_errors=True)
    print(f"self-test: {'PASS' if not failures else 'FAIL'} ({len(cases)} cases, {failures} failure(s))")
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    if len(argv) == 4 and argv[1] == "--self-test":
        return self_test(Path(argv[2]).resolve(), Path(argv[3]).resolve())
    if len(argv) == 2:
        return run(Path(argv[1]).resolve())
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
