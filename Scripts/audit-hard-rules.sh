#!/usr/bin/env bash
# Repository-wide audit of the CLAUDE.md non-negotiable rules that a machine can check
# (plan 2.2, 14.2, 14.3, 18.1, 22.2, 22.3; ADR-0015 section "Mechanical hard-rule audit").
#
#   Scripts/audit-hard-rules.sh                      # audit this repository (tracked and untracked, not ignored)
#   Scripts/audit-hard-rules.sh --root DIR           # audit another tree (git or plain directory)
#   Scripts/audit-hard-rules.sh --allowlist FILE     # use FILE instead of the built-in allowlist ("none" for none)
#   Scripts/audit-hard-rules.sh --allow-stale        # an allowlist entry that matches nothing is a note, not a failure
#   Scripts/audit-hard-rules.sh self-test            # planted violations in a temporary directory (.build/scratch)
#
# Rules (one finding per matching line):
#   ats-arbitrary-loads         NSAllowsArbitraryLoads, ...InWebContent or ...ForMedia in a configuration file
#                               (.plist, .yml, .yaml, .json, .xcconfig, .entitlements; .json covers an XcodeGen
#                               project.json). Never allowlistable.
#   ats-exception               any other ATS exception key in a configuration file (NSAllowsLocalNetworking,
#                               NSExceptionDomains and the NSException*/NSThirdPartyException*/NSTemporaryException*
#                               keys). Allowed only where the allowlist names the file and an ADR.
#   trust-override              a server-trust credential or a disabled certificate check in source code:
#                               URLCredential(trust:), SecTrustSetExceptions, a Network.framework verify block,
#                               NIOSSL certificateVerification .none / .noHostnameVerification, Alamofire disabled
#                               evaluators, allowsAnyHTTPSCertificate, kCFStreamSSLValidatesCertificateChain,
#                               Python unverified contexts / CERT_NONE / check_hostname=False / verify=False,
#                               SSL_VERIFY_NONE, curl -k/--insecure, wget --no-check-certificate,
#                               NODE_TLS_REJECT_UNAUTHORIZED=0, GIT_SSL_NO_VERIFY, PYTHONHTTPSVERIFY=0.
#   weak-tls                    a TLS minimum below 1.2 in source code (URLSession, NIOSSL, Network, Python ssl).
#   file-protection-none        NSFileProtectionNone, .noFileProtection, FileProtectionType.none,
#                               URLFileProtection.none, NSURLFileProtectionNone, a protection key set to .none.
#   keychain-accessible-always  kSecAttrAccessibleAlways / AlwaysThisDeviceOnly. Never allowlistable.
#   key-like-string             a provider or cloud credential format in any text file (OpenAI/Anthropic-style
#                               "sk-" keys, AWS access key IDs, GitHub, GitLab, Slack, Google API, Stripe and
#                               Hugging Face tokens). A token that names itself a canary, fixture, example,
#                               placeholder, dummy, fake or "not a real" key is reported as allowed (canary).
#   private-key-block           a PEM "PRIVATE KEY" header in any text file. Never allowlistable.
#   generic-secret              a secret-named field (key, secret, token, password, ...) assigned a 24+ character
#                               value with digits and letters and at least 3.5 bits of entropy per character,
#                               in any text file. Canary-named values are allowed as above.
#   secret-file                 a key or credential container file: *.p12, *.pfx, *.p8, *.key, *.keychain,
#                               *.keychain-db, *.mobileprovision, *.provisionprofile, *.jks, *.keystore, .env, .env.*,
#                               id_rsa, id_ecdsa, id_ed25519 (matched by name, so a binary key file is found too).
#                               Never allowlistable.
#   todo-in-product             TODO or FIXME, or a fatalError("unimplemented"/"not implemented"/"stub"), in a
#                               product target: Apps/** and Packages/** source and configuration files, excluding
#                               test directories (*Tests), LintFixtures and snapshot references. Spikes/ are
#                               Stage 0 evidence code that is never shipped (ADR-0002) and are not product targets.
#
# What is scanned: in a git work tree, `git ls-files --cached --others --exclude-standard` (committed and new
# files, never ignored ones such as .build/); otherwise every file below the root except .git, .build,
# DerivedData, .swiftpm and node_modules. Binary files (a NUL byte in the first 8 KiB) are skipped and counted.
# This script and Scripts/ci.d/13-hard-rules.sh are not scanned: they hold the patterns themselves.
#
# Comment handling: XML comments in .plist files and whole-line comments (// in C-family and Swift, # in shell,
# Python, YAML and .xcconfig) are ignored for the ATS, trust, TLS and protection rules, so a comment that names a
# key is not configuration. Block comments and trailing comments are not stripped; a hit there must be allowlisted
# with its reason. Credential and TODO rules read the raw text, comments included.
#
# Lines: the ATS, trust, TLS, protection and Keychain rules match the comment-stripped text of the whole file, so a
# call or setting written across lines (`URLCredential(` on one line, `trust:` on the next) is found; a hit is
# reported at the line where the match starts (M0 final review SEC-01: these rules read one line at a time). The
# credential and TODO rules match line by line.
#
# Allowlist reasons: each names the ADR that justifies the exception (ADR-NNNN), and an entry whose reason names
# none is refused (CLAUDE.md, ADR-0015 section 6; M0 final review SEC-02).
#
# Output never prints a matched credential: key-like and generic-secret hits show the rule, the field name, the
# value's length and its first four characters only.
#
# Exit status: 0 no finding; 1 a finding, a stale allowlist entry (unless --allow-stale) or an invalid allowlist;
# 2 usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Built-in allowlist for this repository. Format: rule | path glob (fnmatch, relative to the root) |
# line regex (Python; "-" for any line) | reason, naming the ADR that justifies it (ADR-NNNN; an entry without one is
# refused). An entry that matches no hit is stale and fails the audit (so the list cannot outlive the code it excuses).
# The G0.2 drop-in's own guard, which this list excused until 19 October 2026, now builds its patterns at run time
# (Spikes/G02-Transfer/Scripts/trust-guards.py), so it needs no entry.
read -r -d '' DEFAULT_ALLOWLIST <<'ALLOWLIST' || true
ats-exception | Spikes/G02-Transfer/iOS/Config/ATSVariant-*.plist | - | ADR-0008 "App Transport Security": Info.plist variants of the never-shipped probe app G02TransferATSVariant that measured which ATS keys Tailscale address forms need; the harness has no ATS key (40-g02-transfer guards)
ats-exception | Spikes/G05-AI/ATSProbe/App/Info-*.plist | - | ADR-0011 "ATS": never-shipped ATS probe host apps that measured cleartext to local addresses with NSAllowsLocalNetworking and CIDR exceptions
ats-exception | Spikes/G05-AI/ATSProbe/project.yml | - | ADR-0011 "ATS": the same probe apps' XcodeGen Info.plist properties
trust-override | Spikes/G02-Transfer/TransferKit/Sources/SylviaTransferClient/PinnedSession.swift | URLCredential\(trust: trust\) | ADR-0008 "One trust path": PinnedTrustEvaluator.answer returns the credential only after the leaf's SPKI SHA-256 equals the pin (constant-time compare); 40-g02-transfer checks it is the only one
trust-override | Spikes/G02-Transfer/SourceService/Sources/SylviaSourceService/HTTPServer.swift | certificateVerification = \.none | ADR-0008, ADR-0009: server-side NIOSSL setting meaning "request no client certificate"; phones authenticate with a scoped bearer token and pin the server's key
file-protection-none | Spikes/G05-Recovery/Sources/SylviaRecovery/FileProtection.swift | case \.none: return FileProtectionType\.none | ADR-0012: maps a file's reported class during readback so that an unprotected file is detected as a mismatch; writes nothing
file-protection-none | Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DataProtectionTests.swift | noFileProtection | ADR-0012 evidence: test-only probe that the platform default class is C, writing one byte into the test's temporary directory
file-protection-none | Spikes/G05-Recovery/Tests/SylviaRecoveryTests/DataProtectionTests.swift | let none = FileProtectionType\.none // refused on every path | ADR-0015 (TM-F1; M0 final review SEC-06): test input showing that a protector given no protection is refused by write, copyFile, ensureDirectory and protect before anything is written or changed
key-like-string | Spikes/G05-AI/Tests/SylviaAITests/CredentialSafetyTests.swift | sk-live-abcdef0123456789 | ADR-0011 "Credentials": G0.5 AI redaction test input (sequential hex digits, not a credential), which the test asserts is redacted
generic-secret | Contracts/fixtures/pair-request.v1/* | "invitation_secret": "q7Hc | ADR-0008 (pairing): the G0.2 contract fixtures' fixed invitation secret, an example value of no system (Contracts/README.md "Example IDs and digests are fixtures, not real data"), written by Scripts/fixtures/generate-g02-transfer-contract-fixtures.sh
generic-secret | Contracts/fixtures/pair-response.v1/* | "token": "Zm9y | ADR-0008 (pairing): the G0.2 contract fixtures' fixed device token, an example value of no system, written by the same generator
generic-secret | Contracts/fixtures/pairing-payload.v1/* | "invitation_secret": "q7Hc | ADR-0008 (pairing): the same fixed invitation secret in the pairing-payload fixtures, written by the same generator
generic-secret | Scripts/fixtures/generate-g02-transfer-contract-fixtures.sh | fixture only | ADR-0008 (pairing): the generator's fixed fixture values, each commented "fixture only"
ALLOWLIST

read -r -d '' AUDIT_PY <<'PY' || true
import argparse, bisect, fnmatch, io, math, os, re, subprocess, sys

SELF_PATHS = {"Scripts/audit-hard-rules.sh", "Scripts/ci.d/13-hard-rules.sh"}
SKIP_DIRS = {".git", ".build", "DerivedData", ".swiftpm", "node_modules"}
CONFIG_EXT = {".plist", ".yml", ".yaml", ".json", ".xcconfig", ".entitlements"}
CFAMILY_EXT = {".swift", ".m", ".mm", ".h", ".c", ".cc", ".cpp", ".js", ".ts", ".go", ".java", ".kt", ".metal"}
HASH_EXT = {".py", ".sh", ".bash", ".zsh", ".rb", ".pl"}
PRODUCT_EXT = {".swift", ".m", ".mm", ".h", ".c", ".cc", ".cpp", ".metal", ".plist", ".yml", ".yaml",
               ".xcconfig", ".strings", ".stringsdict", ".entitlements", ".intentdefinition", ".xcprivacy"}
NON_ALLOWLISTABLE = {"ats-arbitrary-loads", "keychain-accessible-always", "private-key-block", "secret-file"}
RULES = ["ats-arbitrary-loads", "ats-exception", "trust-override", "weak-tls", "file-protection-none",
         "keychain-accessible-always", "key-like-string", "private-key-block", "generic-secret", "secret-file",
         "todo-in-product"]

ATS_ARBITRARY = re.compile(r"\bNSAllowsArbitraryLoads(InWebContent|ForMedia)?\b")
ATS_EXCEPTION = re.compile(r"\b(NSAllowsLocalNetworking|NSExceptionDomains|NSException(AllowsInsecureHTTPLoads|MinimumTLSVersion|RequiresForwardSecrecy)"
                           r"|NSThirdPartyException(AllowsInsecureHTTPLoads|MinimumTLSVersion|RequiresForwardSecrecy)"
                           r"|NSTemporaryException(AllowsInsecureHTTPLoads|MinimumTLSVersion|RequiresForwardSecrecy))\b")
TRUST = [
    re.compile(r"URLCredential\s*(\.init)?\s*\(\s*trust\s*:"),
    re.compile(r"\bSecTrustSetExceptions\s*\("),
    re.compile(r"\bsec_protocol_options_set_verify_block\s*\("),
    re.compile(r"\bcertificateVerification\s*[:=]\s*\.(none|noHostnameVerification)\b"),
    re.compile(r"\b(set)?[Aa]llowsAnyHTTPSCertificate\b"),
    re.compile(r"\bDisabled(Trust)?Evaluator\b"),
    re.compile(r"\bkCFStreamSSLValidatesCertificateChain\b"),
    re.compile(r"\b_create_unverified_context\b|\bssl\.CERT_NONE\b|\bcheck_hostname\s*=\s*False\b|\bverify\s*=\s*False\b"),
    re.compile(r"\bSSL_VERIFY_NONE\b"),
    re.compile(r"\bcurl\b[^|;&\n]*?\s(--insecure\b|-[A-Za-z]*k[A-Za-z]*(?=\s|$))"),
    re.compile(r"\bwget\b[^|;&\n]*--no-check-certificate"),
    re.compile(r"\bNODE_TLS_REJECT_UNAUTHORIZED\s*=\s*['\"]?0|\bGIT_SSL_NO_VERIFY\b|\bPYTHONHTTPSVERIFY\s*=\s*['\"]?0"),
]
WEAK_TLS = [
    re.compile(r"tlsMinimumSupportedProtocolVersion\s*=\s*\.TLSv1[01]\b"),
    re.compile(r"\bminimumTLSVersion\s*=\s*\.tlsv1[01]?\b"),
    re.compile(r"\btls_protocol_version_TLSv1[01]\b|\bkTLSProtocol1[01]?\b|\bkSSLProtocol(2|3|All)\b"),
    re.compile(r"\bssl\.PROTOCOL_(TLSv1|TLSv1_1|SSLv2|SSLv3|SSLv23)\b|\bTLSVersion\.(TLSv1|TLSv1_1|SSLv3)\b"),
]
PROTECTION = [
    re.compile(r"\bNSFileProtectionNone\b|\bNSURLFileProtectionNone\b|\bNSDataWritingFileProtectionNone\b"),
    re.compile(r"\.noFileProtection\b"),
    re.compile(r"\bFileProtectionType\.none\b|\bURLFileProtection\.none\b"),
    re.compile(r"\bprotection(Key)?\s*:\s*\.none\b"),
]
KEYCHAIN_ALWAYS = re.compile(r"\bkSecAttrAccessibleAlways(ThisDeviceOnly)?\b")
KEY_FORMATS = [
    ("openai/anthropic-style key", re.compile(r"(?<![A-Za-z0-9_-])sk-(?:proj-|ant-|live-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}")),
    ("AWS access key ID", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}")),
    ("GitLab token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("Stripe key", re.compile(r"\b[sr]k_(?:live|test)_[A-Za-z0-9]{16,}")),
    ("Hugging Face token", re.compile(r"\bhf_[A-Za-z0-9]{30,}\b")),
]
PRIVATE_KEY = re.compile(r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----")
GENERIC = re.compile(r"(?i)\b([\w.-]*(?:api[_-]?key|secret|token|password|passwd|private[_-]?key|access[_-]?key|bearer)[\w-]*)"
                     r"[\"']?\s*[:=]\s*[\"']?(?:Bearer\s+)?([A-Za-z0-9+/_=.-]{24,})")
CANARY = re.compile(r"(?i)canary|not-?a-?real|fixture|example|placeholder|dummy|fake")
SECRET_FILE = re.compile(r"(?i)(^|/)(\.env(\..*)?|id_(rsa|ecdsa|ed25519)(\.pub)?"
                         r"|[^/]*\.(p12|pfx|p8|key|keychain|keychain-db|mobileprovision|provisionprofile|jks|keystore))$")
TODO = re.compile(r"\b(TODO|FIXME)\b|fatalError\(\s*\"(?i:unimplemented|not implemented|stub)")
ADR_REFERENCE = re.compile(r"\bADR-\d{4}\b")


def entropy(s):
    counts = {}
    for c in s:
        counts[c] = counts.get(c, 0) + 1
    return -sum(n / len(s) * math.log2(n / len(s)) for n in counts.values())


def list_files(root):
    try:
        top = subprocess.run(["git", "-C", root, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        is_git = top.returncode == 0 and os.path.realpath(top.stdout.strip()) == os.path.realpath(root)
    except FileNotFoundError:
        is_git = False
    if is_git:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                             capture_output=True, check=True).stdout
        paths = sorted({p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p})
        return "git", [p for p in paths if os.path.isfile(os.path.join(root, p)) and not os.path.islink(os.path.join(root, p))]
    paths = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for f in filenames:
            full = os.path.join(dirpath, f)
            if os.path.isfile(full) and not os.path.islink(full):
                paths.append(os.path.relpath(full, root))
    return "walk", sorted(paths)


def blank(match):
    return re.sub(r"[^\n]", " ", match.group(0))


def strip_comments(path, text):
    ext = os.path.splitext(path)[1].lower()
    lines = text.split("\n")
    if ext == ".plist":
        return re.sub(r"<!--.*?-->", blank, text, flags=re.S).split("\n")
    if ext in (".yml", ".yaml"):
        return [re.sub(r"(?<!\S)#.*$", "", l) for l in lines]
    if ext in CFAMILY_EXT or ext == ".xcconfig":
        return ["" if l.lstrip().startswith("//") else l for l in lines]
    if ext in HASH_EXT or (lines and lines[0].startswith("#!")):
        return ["" if l.lstrip().startswith("#") and not l.startswith("#!") else l for l in lines]
    return lines


def is_source(path, first_line):
    ext = os.path.splitext(path)[1].lower()
    return ext in CFAMILY_EXT or ext in HASH_EXT or first_line.startswith("#!")


def is_product(path):
    parts = path.split("/")
    if parts[0] not in ("Apps", "Packages"):
        return False
    if any(p.endswith("Tests") or p in ("LintFixtures", "__Snapshots__") for p in parts[1:-1]):
        return False
    return os.path.splitext(path)[1].lower() in PRODUCT_EXT


def redact(value):
    return f"{len(value)} characters, starts {value[:4]!r}"


def scan(root):
    mode, paths = list_files(root)
    hits = []  # (rule, path, line, excerpt, canary)
    stats = {"mode": mode, "files": 0, "binary": 0, "excluded": []}
    for path in paths:
        if path in SELF_PATHS:
            stats["excluded"].append(path)
            continue
        stats["files"] += 1
        if SECRET_FILE.search(path):
            hits.append(("secret-file", path, 0, "credential container file name", False))
        try:
            with open(os.path.join(root, path), "rb") as fh:
                data = fh.read()
        except OSError as error:
            hits.append(("unreadable", path, 0, str(error), False))
            continue
        if b"\0" in data[:8192]:
            stats["binary"] += 1
            continue
        text = data.decode("utf-8", "replace")
        raw = text.split("\n")
        ext = os.path.splitext(path)[1].lower()
        code = strip_comments(path, text)
        source = is_source(path, raw[0] if raw else "")
        # The configuration and code rules read the comment-stripped text of the whole file, so a match may run across
        # lines; each is reported once, at the line where it starts (SEC-01).
        whole = "\n".join(code)
        starts = [0]
        for line in code[:-1]:
            starts.append(starts[-1] + len(line) + 1)

        def lines_matching(patterns):
            found = set()
            for pattern in patterns:
                for m in pattern.finditer(whole):
                    found.add(bisect.bisect_right(starts, m.start()))
            return sorted(found)

        checks = []
        if ext in CONFIG_EXT:
            checks += [("ats-arbitrary-loads", [ATS_ARBITRARY]), ("ats-exception", [ATS_EXCEPTION])]
        if source:
            checks += [("trust-override", TRUST), ("weak-tls", WEAK_TLS)]
        if source or ext in CONFIG_EXT:
            checks += [("file-protection-none", PROTECTION), ("keychain-accessible-always", [KEYCHAIN_ALWAYS])]
        for rule, patterns in checks:
            for number in lines_matching(patterns):
                hits.append((rule, path, number, code[number - 1].strip()[:160], False))
        product = is_product(path)
        for number, line in enumerate(raw, 1):
            for kind, pattern in KEY_FORMATS:
                for m in pattern.finditer(line):
                    canary = bool(CANARY.search(m.group(0)))
                    hits.append(("key-like-string", path, number, f"{kind}, {redact(m.group(0))}", canary))
            if PRIVATE_KEY.search(line):
                hits.append(("private-key-block", path, number, "PEM private key header", False))
            for m in GENERIC.finditer(line):
                value = m.group(2)
                if not (re.search(r"[0-9]", value) and re.search(r"[A-Za-z]", value)):
                    continue
                if entropy(value) < 3.5:
                    continue
                canary = bool(CANARY.search(value))
                hits.append(("generic-secret", path, number, f"field {m.group(1)!r}, value {redact(value)}", canary))
            if product and TODO.search(line):
                hits.append(("todo-in-product", path, number, line.strip()[:160], False))
    return hits, stats


def parse_allowlist(text):
    entries, errors = [], []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) != 4 or not all(parts):
            errors.append(f"allowlist line {number}: expected 'rule | glob | line regex | reason'")
            continue
        rule, glob, regex, reason = parts
        if rule not in RULES:
            errors.append(f"allowlist line {number}: unknown rule {rule!r}")
            continue
        if rule in NON_ALLOWLISTABLE:
            errors.append(f"allowlist line {number}: rule {rule} can never be allowlisted (CLAUDE.md hard rule)")
            continue
        if not ADR_REFERENCE.search(reason):
            errors.append(f"allowlist line {number}: the reason names no ADR (ADR-NNNN); an exception names the ADR "
                          f"that justifies it (CLAUDE.md, ADR-0015 section 6)")
            continue
        try:
            compiled = None if regex == "-" else re.compile(regex)
        except re.error as error:
            errors.append(f"allowlist line {number}: bad regex: {error}")
            continue
        entries.append({"line": number, "rule": rule, "glob": glob, "regex": compiled, "reason": reason, "used": 0})
    return entries, errors


def classify(root, hits, entries):
    findings, allowed = [], []
    for hit in hits:
        rule, path, number, excerpt, canary = hit
        if canary:
            allowed.append((hit, "canary: the value names itself a test canary, fixture or example"))
            continue
        raw_line = ""
        if number:
            try:
                with open(os.path.join(root, path), encoding="utf-8", errors="replace") as fh:
                    for i, l in enumerate(fh, 1):
                        if i == number:
                            raw_line = l
                            break
            except OSError:
                pass
        match = None
        for e in entries:
            if e["rule"] == rule and fnmatch.fnmatchcase(path, e["glob"]) and (e["regex"] is None or e["regex"].search(raw_line)):
                match = e
                break
        if match:
            match["used"] += 1
            allowed.append((hit, f"allowlist line {match['line']}: {match['reason']}"))
        else:
            findings.append(hit)
    return findings, allowed


def report(root, allowlist_text, allow_stale, out=sys.stdout):
    entries, errors = parse_allowlist(allowlist_text)
    hits, stats = scan(root)
    findings, allowed = classify(root, hits, entries)
    stale = [e for e in entries if e["used"] == 0]
    p = lambda *a: print(*a, file=out)
    p(f"root: {root}")
    p(f"file list: {stats['mode']} ({'git ls-files --cached --others --exclude-standard' if stats['mode'] == 'git' else 'directory walk'})")
    p(f"files scanned: {stats['files']} ({stats['binary']} binary, skipped for text rules); not scanned (hold the patterns): {', '.join(stats['excluded']) or 'none'}")
    p(f"allowlist: {len(entries)} entries")
    for error in errors:
        p(f"ALLOWLIST-ERROR {error}")
    p("")
    for rule, path, number, excerpt, _ in findings:
        p(f"FINDING {rule} {path}:{number}: {excerpt}")
    for (rule, path, number, excerpt, _), why in allowed:
        p(f"ALLOWED {rule} {path}:{number}: {excerpt}  [{why}]")
    for e in stale:
        p(f"{'NOTE' if allow_stale else 'STALE'} allowlist line {e['line']} ({e['rule']} | {e['glob']}) matched nothing")
    p("")
    p("| Rule | Findings | Allowed |")
    p("| --- | --- | --- |")
    for rule in RULES + (["unreadable"] if any(h[0] == "unreadable" for h in hits) else []):
        f = sum(1 for h in findings if h[0] == rule)
        a = sum(1 for h, _ in allowed if h[0] == rule)
        p(f"| {rule} | {f} | {a} |")
    failed = bool(findings) or bool(errors) or (bool(stale) and not allow_stale)
    p("")
    p(f"result: {'FAIL' if failed else 'PASS'} ({len(findings)} finding(s), {len(allowed)} allowed, {len(stale)} stale allowlist entr{'y' if len(stale) == 1 else 'ies'}, {len(errors)} allowlist error(s))")
    return failed, findings, allowed, stale, errors


# ------------------------------------------------------------------------------------------------
# Self-test: plant one violation per rule (and lookalikes that must not be reported) in a temporary
# directory, then check that exactly the planted lines are reported, in a plain directory and again
# as a git work tree. Credential-shaped values are assembled at run time so that this script never
# contains one.

def plant(root):
    k = lambda *parts: "".join(parts)
    hex32 = "9f8e7d6c5b4a39281706f5e4d3c2b1a0"
    files = {
        "App/Info.plist": f"""<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<!-- {k('NSAllows','ArbitraryLoads')} is mentioned in a comment only -->
<key>NSAppTransportSecurity</key><dict>
<key>{k('NSAllows','ArbitraryLoads')}</key><true/> <!-- audit-expect: ats-arbitrary-loads -->
<key>{k('NSAllows','LocalNetworking')}</key><true/> <!-- audit-expect: ats-exception -->
</dict></dict></plist>
""",
        "App/project.yml": f"""targets:
  App:
    info:
      properties:
        # {k('NSException','AllowsInsecureHTTPLoads')}: a comment, not configuration
        NSAppTransportSecurity:
          {k('NSException','Domains')}:  # audit-expect: ats-exception
            example.org:
              {k('NSException','AllowsInsecureHTTPLoads')}: true  # audit-expect: ats-exception
""",
        "Probe/ATS-Info.plist": f"<plist><dict><key>{k('NSAllows','LocalNetworking')}</key><true/></dict></plist> <!-- audit-allowed: ats-exception -->\n",
        "Sources/Trust.swift": f"""import Foundation
// {k('URLCredential','(trust:')} mentioned in a comment is not code
final class TrustAll: NSObject, URLSessionDelegate {{
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {{
        return (.useCredential, {k('URLCredential','(trust:')} c.protectionSpace.serverTrust!)) // audit-expect: trust-override
    }}
}}
let configuration = URLSessionConfiguration.ephemeral
configuration.{k('tlsMinimumSupported','ProtocolVersion')} = .TLSv10 // audit-expect: weak-tls
configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
tls.{k('certificate','Verification')} = .none // audit-expect: trust-override
tls.minimumTLSVersion = .tlsv12
""",
        "Sources/Store.swift": f"""import Foundation
func save(_ data: Data, to url: URL) throws {{
    try data.write(to: url, options: .{k('noFile','Protection')}) // audit-expect: file-protection-none
    try data.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.{k('no','ne')}], ofItemAtPath: url.path) // audit-expect: file-protection-none
}}
let query: [String: Any] = [kSecAttrAccessible as String: {k('kSecAttrAccessible','Always')}] // audit-expect: keychain-accessible-always
let ok: [String: Any] = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
""",
        "Sources/Keys.swift": f"""let apiKey = "{k('s','k-','proj-')}{hex32}{hex32[:8]}" // audit-expect: key-like-string audit-expect: generic-secret
let awsKey = "{k('AK','IA')}{'Q7RT2MZX4LPN8VWY'}" // audit-expect: key-like-string
let testAPIKey = "{k('s','k-')}test-CANARY-{hex32}"
let fixtureToken = "{k('s','k-')}fixture-not-a-real-key-{hex32[:6]}"
let digestToken = "{'ab' * 20}"
let charactersPerOutputToken = charactersPerOutputToken
let invitationSecret = "{k('q7Hc0bJx2mVt9Wd4','LkPz8Rn1Ys6Ea3Gu5Fi0Oh2Tj4M')}" // audit-expect: generic-secret
let lowEntropyToken = "{'WlpaWlpa' * 5}"
""",
        "Config/key.pem": f"""{k('-----BEGIN ','EC PRIVATE',' KEY-----')}
MHcCAQEE (truncated, not a key)
-----END EC PRIVATE KEY-----
""",
        "scripts/fetch.sh": f"""#!/usr/bin/env bash
# {k('curl -','k')} in a comment is not a command
{k('curl -fsS','Lk')} https://example.org/x -o x # audit-expect: trust-override
curl -fsSL https://example.org/x | sort -k2
{k('wget --no-check','-certificate')} https://example.org/y # audit-expect: trust-override
""",
        "tools/probe.py": f"""import ssl
context = ssl.{k('_create_unverified','_context')}()  # audit-expect: trust-override
safe = ssl.create_default_context()
""",
        "Apps/Reader/Sources/ReaderView.swift": f"""import SwiftUI
// {k('TO','DO')}: wire the real store // audit-expect: todo-in-product
func load() {{ fatalError("{k('not ','implemented')}") }} // audit-expect: todo-in-product
""",
        "Apps/Reader/Tests/ReaderTests.swift": f"// {k('TO','DO')} in a test target is not a product target\n",
        "Packages/Thing/Sources/Thing/Thing.swift": f"/// {k('FIX','ME')} before release // audit-expect: todo-in-product\n",
        "Spikes/G99/Probe.swift": f"// {k('TO','DO')} in a never-shipped spike\n",
        "Docs/notes.md": f"We never set {k('NSAllows','ArbitraryLoads')}; {k('URLCredential','(trust:')} is pinned.\n",
        "Config/.env.production": "",
        # SEC-01: a call and a setting written across lines (no marker: a trailing comment would break the match), and
        # an XcodeGen project spec in JSON.
        "Sources/Wrapped.swift": f"""import Foundation
func wrapped(_ c: URLAuthenticationChallenge) -> URLCredential {{
    let credential = {k('URLCredential','(')}
        trust: c.protectionSpace.serverTrust!)
    return credential
}}
let wrappedConfiguration = URLSessionConfiguration.ephemeral
func lower() {{ wrappedConfiguration.{k('tlsMinimumSupported','ProtocolVersion')} =
    .TLSv11 }}
""",
        "Apps/Reader/project.json": f'{{"targets": {{"Reader": {{"info": {{"properties": {{"NSAppTransportSecurity": {{"{k("NSAllows","ArbitraryLoads")}": true}}}}}}}}}}, "note": "audit-expect: ats-arbitrary-loads"}}\n',
    }
    for path, content in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full) or root, exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(content)
    with open(os.path.join(root, "Fixtures.bin"), "wb") as fh:
        fh.write(b"\0" + k("s", "k-", "proj-").encode() + hex32.encode())  # binary: skipped
    # SEC-01: key and credential containers found by their names, binary or not (a DER key, a keychain, a profile).
    for name in ("Config/signing.key", "Config/login.keychain-db", "Config/App.provisionprofile"):
        with open(os.path.join(root, name), "wb") as fh:
            fh.write(b"\x30\x82\x01\x00\x00" + b"\x02\x01\x00" * 4)
    expected = set()
    for path, content in files.items():
        for number, line in enumerate(content.split("\n"), 1):
            for rule in re.findall(r"audit-expect: ([a-z-]+)", line):
                expected.add((rule, path, number))
    expected.add(("private-key-block", "Config/key.pem", 1))
    expected.add(("secret-file", "Config/.env.production", 0))
    expected.add(("trust-override", "Sources/Wrapped.swift", 3))
    expected.add(("weak-tls", "Sources/Wrapped.swift", 8))
    for name in ("Config/signing.key", "Config/login.keychain-db", "Config/App.provisionprofile"):
        expected.add(("secret-file", name, 0))
    return expected


def self_test(root):
    failures = []
    def check(condition, message):
        print(("ok: " if condition else "FAIL: ") + message)
        if not condition:
            failures.append(message)

    expected = plant(root)
    probe_allowlist = "ats-exception | Probe/*.plist | - | self-test (ADR-0015): a probe plist named in the allowlist\n"
    for label in ("plain directory", "git work tree"):
        if label == "git work tree":
            subprocess.run(["git", "init", "-q", root], check=True)
            subprocess.run(["git", "-C", root, "add", "-A"], check=True)
        print(f"--- {label}")
        buffer = io.StringIO()
        failed, findings, allowed, stale, errors = report(root, probe_allowlist, False, out=buffer)
        print(buffer.getvalue())
        actual = {(r, p, n) for r, p, n, _, _ in findings}
        check(actual == expected, f"{label}: exactly the {len(expected)} planted lines are findings"
              + ("" if actual == expected else f"; missing {sorted(expected - actual)}; unexpected {sorted(actual - expected)}"))
        check(failed, f"{label}: the audit fails when there are findings")
        allowed_keys = {(h[0], h[1]) for h, _ in allowed}
        check(("ats-exception", "Probe/ATS-Info.plist") in allowed_keys, f"{label}: an allowlisted probe plist is reported as allowed, not as a finding")
        canaries = [h for h, why in allowed if why.startswith("canary")]
        check(len(canaries) == 4, f"{label}: the two canary keys are allowed as canaries under both credential rules ({len(canaries)} of 4)")
        check(stats_ok(root, label), f"{label}: the binary file is skipped and the Spikes/, test-target and Markdown lookalikes are not findings")
        printed = buffer.getvalue()
        check("q7Hc0bJx2mVt" not in printed and "9f8e7d6c5b4a3928" not in printed,
              f"{label}: no matched credential value is printed (only length and first four characters)")
        if label == "git work tree":
            ignored = os.path.join(root, ".build", "leak.swift")
            os.makedirs(os.path.dirname(ignored), exist_ok=True)
            with open(os.path.join(root, ".gitignore"), "w") as fh:
                fh.write(".build/\n")
            with open(ignored, "w") as fh:
                fh.write("let x = 1 // " + "TO" + "DO\n")
            check(".build/leak.swift" not in [p for p in list_files(root)[1]], "git work tree: ignored files are not listed")
    buffer = io.StringIO()
    failed, _, _, stale, _ = report(root, probe_allowlist + "trust-override | Nowhere/*.swift | - | stale entry (ADR-0015)\n", False, out=buffer)
    check(failed and len(stale) == 1, "an allowlist entry that matches nothing is reported STALE and fails the audit")
    buffer = io.StringIO()
    failed, _, _, _, errors = report(root, "ats-arbitrary-loads | App/Info.plist | - | attempt (ADR-0015)\n", False, out=buffer)
    check(failed and any("can never be allowlisted" in e for e in errors), "allowlisting a never-allowlistable rule is refused")
    buffer = io.StringIO()
    failed, _, allowed, _, errors = report(root, "ats-exception | Probe/*.plist | - | a probe plist, with no decision record named\n", False, out=buffer)
    check(failed and any("names no ADR" in e for e in errors)
          and not any(h[1] == "Probe/ATS-Info.plist" for h, _ in allowed),
          "an allowlist entry whose reason names no ADR is refused, and excuses nothing")
    # A clean tree passes.
    clean = os.path.join(root, "clean")
    os.makedirs(os.path.join(clean, "Apps", "Reader"))
    with open(os.path.join(clean, "Apps", "Reader", "View.swift"), "w") as fh:
        fh.write("import SwiftUI\nlet session = URLSession(configuration: .ephemeral)\n")
    buffer = io.StringIO()
    failed, findings, _, _, _ = report(clean, "", False, out=buffer)
    check(not failed and not findings, "a clean tree passes with no finding")
    print()
    print(f"self-test: {'FAIL' if failures else 'PASS'} ({len(failures)} failure(s))")
    return 1 if failures else 0


def stats_ok(root, label):
    hits, stats = scan(root)
    paths = {h[1] for h in hits}
    return (stats["binary"] >= 1 and "Fixtures.bin" not in paths and "Spikes/G99/Probe.swift" not in paths
            and "Apps/Reader/Tests/ReaderTests.swift" not in paths and "Docs/notes.md" not in paths)


def main():
    parser = argparse.ArgumentParser(prog="audit-hard-rules.sh")
    parser.add_argument("command", nargs="?", default="audit", choices=["audit", "self-test"])
    parser.add_argument("--root")
    parser.add_argument("--allowlist")
    parser.add_argument("--allow-stale", action="store_true")
    parser.add_argument("--self-test-dir")
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()
    if args.command == "self-test":
        return self_test(args.self_test_dir)
    root = os.path.abspath(args.root or args.repo_root)
    if not os.path.isdir(root):
        print(f"not a directory: {root}", file=sys.stderr)
        return 2
    if args.allowlist in (None, "default"):
        allowlist = os.environ["AUDIT_DEFAULT_ALLOWLIST"]
    elif args.allowlist == "none":
        allowlist = ""
    else:
        with open(args.allowlist, encoding="utf-8") as fh:
            allowlist = fh.read()
    failed = report(root, allowlist, args.allow_stale)[0]
    return 1 if failed else 0


sys.exit(main())
PY

PYTHON=/usr/bin/python3
[[ -x "$PYTHON" ]] || PYTHON="$(command -v python3)"

if [[ "${1:-}" == "self-test" ]]; then
  mkdir -p "$REPO_ROOT/.build/scratch"
  dir="$(mktemp -d "$REPO_ROOT/.build/scratch/audit-self-test.XXXXXX")"
  trap 'rm -rf "$dir"' EXIT
  echo "self-test directory: ${dir#"$REPO_ROOT"/} (removed on exit)"
  AUDIT_DEFAULT_ALLOWLIST="$DEFAULT_ALLOWLIST" "$PYTHON" -I -c "$AUDIT_PY" self-test --self-test-dir "$dir" --repo-root "$REPO_ROOT"
  exit $?
fi

AUDIT_DEFAULT_ALLOWLIST="$DEFAULT_ALLOWLIST" exec "$PYTHON" -I -c "$AUDIT_PY" audit --repo-root "$REPO_ROOT" "$@"
