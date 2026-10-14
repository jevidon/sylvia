#!/usr/bin/env python3
"""Shows that the contracts' regular expressions mean the same in Python and in ECMA-262, and that the checker's
ECMA-262 grammar check agrees with a JavaScript engine (ADR-0016; review finding L2-R2-01). Needs node.

    python3 -I Docs/Stage0/evidence/M0-contracts/commands/check-patterns.py [--log <file>]

1. Every `pattern` in every contract document compiles in node with and without the `u` flag, except the recorded
   non-portable ones in other owners' contracts, which fail there (so the record is true).
2. The checker's ECMA-262 grammar check (Scripts/check-spike-anchors.py, EcmaPattern) gives node's verdict with the
   `u` flag on a corpus of valid and invalid patterns; where it is stricter on purpose ("unsupported here") it may
   refuse what node accepts, never the reverse.
3. The secret-name pattern of anchor.v1, written without (?i), matches exactly the names the context-pack pattern
   matches in Python, in Python and in node with and without the `u` flag, case variants and lookalikes included
   (dotted and dotless I, the Kelvin sign, the long s).
4. The failure-reason guard refuses and allows the same strings in Python and node, and allows the documented
   residual cases.
5. The differences that remain are dialect differences, shown by their example strings: Python's `$` also matches
   before a final newline, and Python's `\\s` includes U+001C-U+001F and U+0085 but not U+FEFF.
6. The checker's case classes (each ASCII letter's characters under Python's (?i)) equal a full scan of the code
   points.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import string
import subprocess
import sys
from pathlib import Path


def repository_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "Scripts/lib/env.sh").is_file():
            return parent
    raise SystemExit("check-patterns.py: not inside the Sylvia repository")


ROOT = repository_root()
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("checker", ROOT / "Scripts/check-spike-anchors.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

# (pattern, expectation): "valid" and "invalid" with the u flag, or "unsupported" (the checker refuses on purpose).
EDGE_CASES = [
    (r"^[0-9a-f]{64}$", "valid"), (r"(?:a|b)+", "valid"), (r"(?=a)b", "valid"), (r"(?!a)b", "valid"),
    (r"(?<=a)b", "valid"), (r"(?<!a)b", "valid"), (r"(?<year>[0-9]{4})-\k<year>", "valid"), (r"(a)\1", "valid"),
    (r"\1(a)", "valid"), (r"\0", "valid"), (r"\x41", "valid"), (r"\u0041", "valid"), (r"\u{1F600}", "valid"),
    (r"\uD83D\uDE00", "valid"), (r"[\-]", "valid"), (r"[a-]", "valid"), (r"[-a]", "valid"), (r"[\b]", "valid"),
    (r"\/", "valid"), (r"a{2,}", "valid"), (r"a{2,3}?", "valid"), (r"[^]", "valid"), (r"[]", "valid"),
    (r"\cJ", "valid"), (r"\.", "valid"), (r"\$", "valid"), (r"[\s\S]", "valid"), (r"\bword\B", "valid"),
    (r"a|", "valid"), (r"()", "valid"), (r"[\u0130-\u0131]", "valid"), ("[İıKſ]", "valid"), (r"(?:)", "valid"),
    (r"\f\n\r\t\v", "valid"), (r"[\d-]", "valid"), (r"[_-]", "valid"), (r"a{0}", "valid"), (r"[{}]", "valid"),
    (r"[\]]", "valid"), (r"[\[]", "valid"), (r"^\\\\[^\s\\]", "valid"), (r"(?:a{1,2}){3}", "valid"),
    (r"(?i)abc", "invalid"), (r"a{", "invalid"), (r"a{1", "invalid"), (r"a{2,1}", "invalid"), (r"]", "invalid"),
    (r"}", "invalid"), (r"{", "invalid"), (r"\-", "invalid"), (r"[a-\d]", "invalid"), (r"[\d-a]", "invalid"),
    (r"[z-a]", "invalid"), (r"\c", "invalid"), (r"\c1", "invalid"), (r"\x4", "invalid"), (r"\u004", "invalid"),
    (r"\u{110000}", "invalid"), (r"\k<n>", "invalid"), (r"(a)\2", "invalid"), (r"\00", "invalid"),
    (r"(?=a)*", "invalid"), (r"(?<=a)*", "invalid"), (r"^*", "invalid"), (r"a**", "invalid"), (r"*", "invalid"),
    (r"\a", "invalid"), (r"\e", "invalid"), (r"\Z", "invalid"), (r"\A", "invalid"), (r"\z", "invalid"),
    (r"(?<a>x)(?<a>y)", "invalid"), (r"(", "invalid"), (r")", "invalid"), (r"[", "invalid"), ("\\", "invalid"),
    (r"(?P<n>a)", "invalid"), (r"a++", "invalid"), (r"\p", "invalid"), (r"[\1]", "invalid"), (r"(?#c)", "invalid"),
    (r"\_", "invalid"), (r"[\_]", "invalid"), (r"$+", "invalid"),
    (r"\p{L}", "unsupported"), (r"\P{Lu}", "unsupported"), (r"(?<a>x)|(?<a>y)", "unsupported"),
    (r"(?i:a)", "unsupported"), (r"(?<ä>x)", "unsupported"),
]

# Names the secret-name pattern refuses, in every spelling its alternatives allow.
SECRET_NAMES = ["api_key", "api-key", "apikey", "key", "secret", "client_secret", "client-secret", "clientsecret",
                "password", "passwd", "token", "access_token", "access-token", "accesstoken", "auth_token",
                "auth-token", "authtoken", "bearer", "authorization", "x_api_key", "x-api-key", "x_api-key",
                "x-api_key", "credential", "credentials"]
# Names it allows.
OTHER_NAMES = ["keys", "api_keys", "token_count", "secretary", "monkey", "tokens", "credentialed", "x__api_key",
               "passwords", "authorized", "bearers", "kid", "", "key ", " key", "keyword", "api", "api__key",
               "client__secret", "xapikey", "resource_href", "asset_sha256", "work_id", "author_display"]
LOOKALIKES = {"i": ["İ", "ı"], "k": ["\u212a"], "s": ["ſ"]}

# The failure-reason guard (capture-envelope.v1 retained_excerpt.failure.reason): refused, allowed, and the residual
# cases its description says it lets through.
REASON_REFUSED = [
    'decodeFailed("Part 3.mp3: The file /private/var/mobile/Library/Part 3.mp3 could not be opened.")',
    "Error Domain=NSCocoaErrorDomain Code=260 UserInfo={NSURL=file:///private/var/mobile/x.mp3}",
    "FILE:/x", "see ~/Library/Caches/x", "C:\\Users\\me\\book.mp3", "path=(/var/folders/x)",
    "/private/var/x at the start", "NSFilePath=/private/var/x", "path>/private/var/x", "a|/private/var/x",
    "\\\\server\\share\\a.mp3", "cannot open \\\\nas\\audiobooks\\Part 3.mp3", "open `/private/var/x` failed",
    "C:/Users/me/book.mp3", "path:/var/x", "x,/var/x", "x;/var/x", "<~/x>", "{/x}", "'/x'",
]
REASON_ALLOWED = [
    "source not on this device", "unsupported profile: HE-AAC v2", "Profile: main", "audio file: unreadable",
    'decodeFailed("Part 3.mp3: unsupported profile: HE-AAC v2")', "NSFilePath=Library/Retained/abc.m4a",
    "64 kb/s, 1/2 of the frames", "and / or", "https://speech.example.invalid/v1 refused",
    'encodeFailed("rename failed, errno 2")', "Part 3.mp3", "error +/- 5 ms", "I/O error", "w/o a header",
]
REASON_RESIDUAL = ["Users/jevidon/Music/Book/Part 3.mp3", "x)/private/var/x", "error+/private/var/x",
                   "~jevidon/Music/Part 3.mp3", "file%3A%2F%2F%2Fprivate%2Fvar%2Fx"]
# Dialect differences, each with what Python and ECMA-262 give (True: the pattern matches).
DIFFERENCES = [
    ("secret", "key\n", True, False, "Python's $ also matches before a final newline"),
    ("reason", "x\x1c/private/var/x", True, False, "Python's \\s includes U+001C-U+001F"),
    ("reason", "x\x85/private/var/x", True, False, "Python's \\s includes U+0085"),
    ("reason", "x\ufeff/private/var/x", False, True, "ECMA-262's \\s includes U+FEFF"),
]


def spellings(name: str) -> list[str]:
    out = [name, name.upper(), name.title(), name.swapcase()]
    for letter, alternatives in LOOKALIKES.items():
        if letter in name:
            out += [name.replace(letter, alt, 1) for alt in alternatives]
    return out


def node_results(patterns: list[str], tests: list[tuple[str, str]]) -> dict:
    node = shutil.which("node")
    if node is None:
        raise SystemExit("check-patterns.py: node is not installed")
    request = json.dumps({"patterns": patterns, "tests": tests})
    done = subprocess.run([node, str(Path(__file__).with_name("compile-patterns.js"))], input=request,
                          capture_output=True, text=True, check=True)
    return json.loads(done.stdout)


def ecma_only(pattern: str) -> str | None:
    try:
        checker.EcmaPattern(pattern).check()
    except checker.EcmaPatternError as exc:
        return str(exc)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()
    import yaml

    documents = [(p, json.loads(p.read_text(encoding="utf-8"))) for p in sorted((ROOT / "Contracts/schemas").glob("*.json"))]
    documents += [(p, yaml.safe_load(p.read_text(encoding="utf-8")))
                  for p in sorted((ROOT / "Contracts/openapi").glob("*")) if p.suffix in {".yaml", ".yml", ".json"}]
    contract = [(f"{p.relative_to(ROOT / 'Contracts').as_posix()}#{ptr}", pat)
                for p, doc in documents for ptr, pat in checker.contract_patterns(doc, "")]
    by_id = checker.load_schemas(ROOT)
    secret = by_id[checker.ANCHOR_ID]["$defs"]["not_secret_name"]["not"]["pattern"]
    pack_secret = by_id[checker.CONTEXT_PACK_ID]["$defs"]["notSecretName"]["not"]["pattern"]
    reason = by_id[checker.CAPTURE_ID]["properties"]["retained_excerpt"]["properties"]["failure"]["properties"]["reason"]["not"]["pattern"]
    names = [s for n in SECRET_NAMES + OTHER_NAMES for s in spellings(n)]
    tests = ([(secret, n) for n in names] + [(reason, s) for s in REASON_REFUSED + REASON_ALLOWED + REASON_RESIDUAL]
             + [(secret if which == "secret" else reason, s) for which, s, _, _, _ in DIFFERENCES])
    patterns = [p for _, p in contract] + [p for p, _ in EDGE_CASES]
    result = node_results(patterns, tests)
    compiled, ran = result["compiled"], iter(result["tests"])
    lines, problems = [f"node {result['node']}; python {sys.version.split()[0]}"], []

    # 1. Contract patterns.
    known = checker.KNOWN_NON_PORTABLE_PATTERNS
    for (key, pattern), c in zip(contract, compiled):
        python_problem = checker.ecma262_problem(pattern)
        if key in known:
            if python_problem is None or c["u"] is None or c["plain"] is None:
                problems.append(f"{key}: recorded as not portable, but python={python_problem!r} node u={c['u']!r} "
                                f"node={c['plain']!r}")
        elif python_problem is not None or c["u"] is not None or c["plain"] is not None:
            problems.append(f"{key}: python={python_problem!r} node u={c['u']!r} node={c['plain']!r}")
    lines.append(f"1. contract patterns: {len(contract)} in {len(documents)} documents; all compile in Python, in the "
                 f"checker's ECMA-262 check and in node with and without the u flag, except the {len(known)} recorded "
                 f"ones, which fail in the checker and in node with and without u")

    # 2. The grammar check against node on the corpus.
    tally = {"valid": 0, "invalid": 0, "unsupported": 0}
    for (pattern, expect), c in zip(EDGE_CASES, compiled[len(contract):]):
        ours, node_ok = ecma_only(pattern), c["u"] is None
        tally[expect] += 1
        agree = ((expect == "valid" and ours is None and node_ok) or (expect == "invalid" and ours and not node_ok)
                 or (expect == "unsupported" and ours))
        if not agree:
            problems.append(f"corpus {pattern!r} ({expect}): checker={ours!r}, node u={c['u']!r}")
        if expect == "unsupported":
            lines.append(f"   unsupported here {pattern!r}: checker refuses; node with u {'accepts' if node_ok else 'refuses: ' + c['u']}")
    lines.append(f"2. grammar check against node with the u flag: {tally['valid']} valid and {tally['invalid']} invalid "
                 f"patterns given the same verdict; {tally['unsupported']} refused on purpose (never accepted where "
                 f"node refuses)")

    # 3. The secret-name pattern.
    refused = 0
    for n in names:
        t = next(ran)
        python_flag, python_portable = bool(re.search(pack_secret, n)), bool(re.search(secret, n))
        if not python_flag == python_portable == t["u"] == t["plain"]:
            problems.append(f"secret name {n!r}: context-pack (?i) {python_flag}, portable in Python {python_portable}, "
                            f"node u {t['u']}, node {t['plain']}")
        refused += python_flag
    lines.append(f"3. secret-name pattern: {len(names)} names ({refused} refused, among them the lookalike spellings), "
                 f"the same in the context-pack (?i) pattern in Python, the portable pattern in Python, and node with "
                 f"and without u")

    # 4. The failure-reason guard.
    for group, strings, want in (("refused", REASON_REFUSED, True), ("allowed", REASON_ALLOWED, False),
                                 ("residual (allowed, documented)", REASON_RESIDUAL, False)):
        for s in strings:
            t = next(ran)
            got = (bool(re.search(reason, s)), t["u"], t["plain"])
            if got != (want, want, want):
                problems.append(f"reason {group} {s!r}: python {got[0]}, node u {got[1]}, node {got[2]}")
    lines.append(f"4. failure-reason guard: {len(REASON_REFUSED)} refused, {len(REASON_ALLOWED)} allowed and "
                 f"{len(REASON_RESIDUAL)} residual strings, the same in Python and node with and without u")

    # 5. Dialect differences.
    for which, s, python_want, ecma_want, why in DIFFERENCES:
        t = next(ran)
        pattern = secret if which == "secret" else reason
        got = (bool(re.search(pattern, s)), t["u"], t["plain"])
        if got != (python_want, ecma_want, ecma_want):
            problems.append(f"difference {s!r}: expected python {python_want}, node {ecma_want}; got {got}")
        lines.append(f"5. {which} {s!r}: Python {'matches' if python_want else 'does not match'}, node "
                     f"{'matches' if ecma_want else 'does not match'} ({why})")

    # 6. Case classes.
    for letter in string.ascii_lowercase:
        rx = re.compile("(?i)" + letter)
        full = {chr(cp) for cp in range(0x110000) if not 0xD800 <= cp <= 0xDFFF and rx.fullmatch(chr(cp))}
        if set(checker.case_class(letter)[1:-1]) != full:
            problems.append(f"case class of {letter}: {checker.case_class(letter)} != full scan {sorted(full)}")
    lines.append("6. case classes: for all 26 ASCII letters the checker's class equals a scan of every code point "
                 f"(non-ASCII members: {', '.join(f'{c}: ' + ' '.join(f'U+{ord(m):04X}' for m in checker.case_class(c)[1:-1] if not m.isascii()) for c in 'iks')})")

    lines.append(f"result: {'pass' if not problems else 'FAIL'} ({len(problems)} problem(s))")
    lines += [f"error: {p}" for p in problems]
    text = "\n".join(lines)
    print(text)
    if args.log:
        args.log.write_text(text + "\n", encoding="utf-8")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
