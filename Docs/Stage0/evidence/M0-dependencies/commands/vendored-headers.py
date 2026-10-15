"""ADR-0014 evidence: license statements and origin notes in the source headers of third-party code vendored inside
pinned packages, so that code with no license file of its own is found even when it carries no copyright line.

  python3 -I vendored-headers.py <package checkout> [...] [--dir <directory> ...]

A package checkout: every target its manifest declares (`swift package dump-package`, read into a temporary scratch
directory; test, plugin and macro targets excluded, since they never ship), at the path SwiftPM builds it from, that
holds a C-family file (C, C++, Objective-C, assembly, headers, module maps). Review R2-03: the survey covers every C
target of every package that ships, not a hand-picked list, so a vendored header such as uSHET's cpp_magic.h in
swift-nio's CNIOAtomics is not missed. `--dir`: a plain directory, every source file in it (C-family, Swift, JS, TS).

For each target or directory: the number of source files; how many carry each license marker in their first 60 lines;
the files that carry none; every origin note in the first 60 lines (a line saying the file is, or was copied, taken or
ported from, another project; a link to a file in another repository; a license tag such as `LICENSE: MIT`); the SPDX
identifiers, counted; every directory named like vendored code (third_party, vendor, external ...), which may hold code
with no header at all; and any upstream revision file (hash.txt or similar). Markers match license statements, not
words: `SSLeay` as a symbol name (BoringSSL's kSSLeayMethod in crypto/rand/rand.cc) is not a license (review R2-05).
An origin note or vendored-code directory that REVIEWED or REVIEWED_DIRS does not list fails the command.
Reads files only; no network.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

MARKERS = [
    ('Apache-2.0', re.compile(r'Licensed under the Apache License, Version 2\.0|Licensed under Apache License v2\.0'
                              r'|SPDX-License-Identifier:\s*Apache-2\.0', re.I)),
    ('ISC', re.compile(r'Permission to use, copy, modify, and/or distribute this software for any'
                       r'|SPDX-License-Identifier:\s*ISC\b', re.I)),
    # The OpenSSL and SSLeay licenses as statements (OpenSSL's short header, the licenses' own sentences, the SSLeay
    # copyright line), never the bare words, which BoringSSL also uses as identifiers.
    ('OpenSSL/SSLeay', re.compile(r'Licensed under the OpenSSL licen[cs]e|\bOpenSSL License\b'
                                  r'|This product includes software developed by the OpenSSL Project'
                                  r'|This package is an SSL implementation written by Eric Young'
                                  r'|The licen[cs]e and distribution terms for any publi[cs]ally available version'
                                  r'|Copyright \(C\) 1995-1998 Eric Young', re.I)),
    ('MIT', re.compile(r'Permission is hereby granted, free of charge|SPDX-License-Identifier:\s*MIT\b'
                       r'|\bMIT[- ]licen[cs]ed?\b|\bLICEN[CS]E\s*:\s*MIT\b|licensed under (?:the )?MIT\b', re.I)),
    ('zlib/Info-ZIP', re.compile(r"provided 'as-is'|Info-ZIP|zlib license|Gilles Vollant", re.I)),
    # A BSD license statement, not the word BSD (platform macros such as __FreeBSD__, "BSD variants" in comments).
    ('BSD', re.compile(r'Redistribution and use in source and binary forms|BSD[- ](?:style|licen[cs]e|[234]-Clause)'
                       r'|SPDX-License-Identifier:\s*BSD', re.I)),
    ('public domain', re.compile(r'public domain|disclaims copyright', re.I)),
]
# A line that says where a file comes from, or names a license other than by its text.
ORIGIN = re.compile(
    r'\bthis (?:file |code |header |library |module )?is (?:(?:a )?(?:copy|copied|taken|derived|adapted|ported) '
    r'(?:of |from ))?https?://'
    r'|\b(?:copied|taken|ported|vendored|borrowed|lifted|adapted) (?:verbatim |directly |mostly |largely |in part )?'
    r'from\b'
    r'|\b(?:code|file|implementation|functions?|routines?) (?:is |was |are |were )?(?:derived|based) (?:up)?on\b'
    r'|\boriginally (?:from https?://|part of|written for|developed (?:for|as part of))'
    r'|^\s*(?://+|/\*+|\*+|#+|--)\s*LICEN[CS]E\s*:\s*\S'
    # A link to a source file in a repository (not to documentation, a schema or a directory).
    r'|https?://(?:(?:github\.com|gitlab\.com|bitbucket\.org)/[^\s)>"\']+/(?:blob|raw)/|raw\.githubusercontent\.com/)'
    r'[^\s)>"\'#?]+\.(?:c|h|cc|cpp|cxx|hpp|hh|m|mm|s|asm|inc|swift|js|mjs|ts|py|rb|go|rs|java|kt|cs|v)\b', re.I)
SPDX = re.compile(r'SPDX-License-Identifier:\s*([A-Za-z0-9.+-]+(?:\s+(?:WITH|AND|OR)\s+[A-Za-z0-9.+-]+)*)')
# Every file with an origin note, as reviewed for ADR-0014 (checkout directory name, path in the checkout): what the
# notes mean and where the inventory records it. A note in a file not listed here is printed as UNREVIEWED and the
# command exits 1, so new third-party code in a package upgrade cannot pass unnoticed (ADR-0014 section 6, step 4).
BORINGSSL = ('BoringSSL\'s own provenance notes (public-domain eSTREAM, SUPERCOP and neon2 code, algorithm references, '
             'spec links); covered by the BoringSSL row and its LICENSE at this revision')
REVIEWED = {
    ('swift-nio', 'Sources/CNIOAtomics/src/cpp_magic.h'):
        'uSHET cpp_magic.h (MIT, Thomas Nixon and Jonathan Heathcote), linked into the Mac source service: inventory '
        'bundled entry and acknowledgements (review R2-03). The "tricks described by pfultz2" are techniques from a '
        'wiki page, not copied code',
    ('swift-nio', 'Sources/CNIOLinux/liburing_shims.c'): 'copied from swift-nio\'s own shim.c; Linux only',
    ('swift-nio', 'Sources/NIOAsyncAwaitDemo/FullRequestResponse.swift'):
        'mostly copied from Apple\'s swift-nio-extras (Apache-2.0); an example executable, not linked into any build',
    ('swift-nio', 'Sources/NIOPosix/Resolver.swift'): 'not an origin note ("an implementation based on getaddrinfo")',
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/chacha/chacha.cc'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/curve25519/curve25519.cc'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/curve25519/asm/x25519-asm-arm.S'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/fipsmodule/aes/aes_nohw.cc.inc'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/fipsmodule/bn/div_extra.cc.inc'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/fipsmodule/bn/jacobi.cc.inc'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/poly1305/poly1305_arm.cc'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/poly1305/poly1305_arm_asm.S'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/crypto/trust_token/trust_token.cc'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/gen/bcm/ghash-neon-armv8-apple.S'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/gen/bcm/ghash-neon-armv8-linux.S'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/gen/bcm/ghash-neon-armv8-win.S'): BORINGSSL,
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/include/CNIOBoringSSL_trust_token.h'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/chacha/chacha.cc'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/curve25519/curve25519.cc'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/curve25519/asm/x25519-asm-arm.S'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/fipsmodule/aes/aes_nohw.cc.inc'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/fipsmodule/bn/div_extra.cc.inc'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/fipsmodule/bn/jacobi.cc.inc'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/poly1305/poly1305_arm.cc'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/poly1305/poly1305_arm_asm.S'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/crypto/trust_token/trust_token.cc'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/gen/bcm/ghash-neon-armv8-apple.S'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/gen/bcm/ghash-neon-armv8-linux.S'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/gen/bcm/ghash-neon-armv8-win.S'): BORINGSSL,
    ('swift-crypto', 'Sources/CCryptoBoringSSL/include/CCryptoBoringSSL_trust_token.h'): BORINGSSL,
    ('SwiftSoup', 'Sources/BinarySearch.swift'):
        'a binary search "Adapted from" a Stack Overflow answer (Garth Snyder, 2019); Stack Overflow contributions are '
        'CC BY-SA. Linked into the app through SwiftSoup: inventory bundled entry, pending counsel (ADR-0014 section 7)',
    ('CryptoSwift', 'Sources/CryptoSwift/RSA/RSA.swift'): 'points to CS_BigInt, attaswift/BigInt (MIT): inventory bundled entry',
    ('CryptoSwift', 'Sources/CryptoSwift/Operators.swift'): 'a Swift Evolution link, not an origin note',
    ('GRDB.swift', 'GRDB/Utils/Inflections+English.swift'): 'Ruby on Rails inflections (MIT): inventory bundled entry',
    ('swift-toolkit', 'Sources/Streamer/Parser/EPUB/OPFMeta.swift'):
        'a link to calibre\'s source for a vocabulary URI (https://calibre-ebook.com); no code taken',
    ('swift-toolkit', 'Sources/Navigator/EPUB/Scripts/src/vendor/hypothesis/anchoring/pdf.ts'):
        'a four-value PDF.js enum; pdf.ts is imported only by the vendored tests, and no readium-*.js bundle contains it',
    ('swift-certificates', 'Sources/X509/CryptographicMessageSyntax/CMSIssuerAndSerialNumber.swift'):
        'definitions from the X.501 and X.509 standards (ASN.1 types), not code',
}


# Directories named the way vendored code is usually kept (third_party, vendor, external ...): code there can carry no
# header at all, so no origin note finds it (review round 2: swift-crypto copies BoringSSL's third_party/fiat without
# its LICENSE). Each such directory in a surveyed tree must be listed here with where the inventory covers it; another
# is printed as UNREVIEWED and fails the command, like an unreviewed origin note.
VENDOR_DIR_NAMES = {'third_party', 'thirdparty', 'third-party', '3rdparty', 'vendor', 'vendored', 'external',
                    'externals', 'deps', 'contrib'}
REVIEWED_DIRS = {
    ('swift-nio-ssl', 'Sources/CNIOBoringSSL/third_party'):
        'fiat-crypto (11 files): MIT, whose text BoringSSL\'s top-level LICENSE at 817ab07e carries; inventory BoringSSL row',
    ('swift-crypto', 'Sources/CCryptoBoringSSL/third_party'):
        'fiat-crypto (18 files): Apache-2.0 by BoringSSL\'s third_party/fiat/LICENSE at 0226f304 (fetched; swift-crypto '
        'omits it): inventory bundled entry and acknowledgements',
    ('swift-toolkit', 'Sources/Navigator/EPUB/Scripts/src/vendor'):
        'the Hypothesis client anchoring code v1.1763.0 (BSD-2-Clause): inventory bundled entry and acknowledgements',
}


def checkout_of(path):
    """(checkout directory name, path inside it) for a file under a package checkout (a directory whose parent is
    named checkouts), or (None, path)."""
    parts = os.path.normpath(os.path.abspath(path)).split(os.sep)
    for i in range(len(parts) - 2, 0, -1):
        if parts[i - 1] == 'checkouts':
            return parts[i], '/'.join(parts[i + 1:])
    return None, path


UNREVIEWED = []
C_EXT = ('.c', '.h', '.cc', '.cpp', '.cxx', '.c++', '.m', '.mm', '.S', '.s', '.inc', '.hpp', '.hh', '.hxx', '.def',
         '.modulemap')
DIR_EXT = ('.c', '.h', '.cc', '.cpp', '.S', '.s', '.inc', '.swift', '.js', '.ts', '.m')
SKIP = {'.git', '.build', 'node_modules'}


def target_dirs(checkout):
    """[(target name, type, directory)] for every target a package declares that can ship, at SwiftPM's path."""
    with tempfile.TemporaryDirectory(prefix='vendored-headers-') as tmp:
        r = subprocess.run(['xcrun', 'swift', 'package', '--package-path', checkout, '--scratch-path', tmp,
                            'dump-package'], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f'dump-package failed for {checkout}: {" ".join(r.stderr.split())[-300:]}')
    out = []
    for t in json.loads(r.stdout).get('targets', []):
        if t.get('type') in ('test', 'plugin', 'macro'):
            continue
        if t.get('path'):
            d = os.path.join(checkout, t['path'])
        else:
            d = next((os.path.join(checkout, base, t['name']) for base in ('Sources', 'Source', 'src', 'srcs')
                      if os.path.isdir(os.path.join(checkout, base, t['name']))), None)
        if d and os.path.isdir(d):
            out.append((t['name'], t.get('type'), os.path.normpath(d)))
    return out


def files_in(top, exts):
    for dp, dns, fns in os.walk(top):
        dns[:] = sorted(d for d in dns if d not in SKIP)
        for fn in sorted(fns):
            if fn.endswith(exts) or fn == 'module.map':
                yield os.path.join(dp, fn)


def survey(top, label, exts):
    total = 0
    counts = {name: 0 for name, _ in MARKERS}
    none, origins, spdx, revs, vendor_dirs = [], [], {}, [], []
    for dp, dns, fns in os.walk(top):
        dns[:] = sorted(d for d in dns if d not in SKIP)
        if os.path.basename(dp).lower() in VENDOR_DIR_NAMES and dp != top:
            key = checkout_of(dp)
            verdict = REVIEWED_DIRS.get(key)
            if verdict is None:
                UNREVIEWED.append(f'{key[0]}/{key[1]} (a directory named like vendored code)')
            n = sum(len(f) for _, _, f in os.walk(dp))
            vendor_dirs.append(f'{os.path.relpath(dp, top)}/ ({n} files) -> '
                               + ('reviewed: ' + verdict if verdict else 'UNREVIEWED: add it to REVIEWED_DIRS once it is matched to the inventory'))
        for fn in sorted(fns):
            p = os.path.join(dp, fn)
            if fn.lower() in ('hash.txt', 'version.txt', 'revision.txt') or fn.lower().startswith('readme'):
                with open(p, errors='replace') as f:
                    revs.append((os.path.relpath(p, top), f.read().strip()[:300]))
    for p in files_in(top, exts):
        total += 1
        with open(p, errors='replace') as f:
            lines = [f.readline() for _ in range(60)]
        head = ''.join(lines)
        hit = False
        for name, rx in MARKERS:
            if rx.search(head):
                counts[name] += 1
                hit = True
        if not hit:
            none.append(os.path.relpath(p, top))
        for m in SPDX.finditer(head):
            spdx[m.group(1)] = spdx.get(m.group(1), 0) + 1
        notes = [(n, " ".join(line.strip().strip("/*#;").split())[:160]) for n, line in enumerate(lines, 1)
                 if ORIGIN.search(line)]
        if notes:
            key = checkout_of(p)
            verdict = REVIEWED.get(key)
            if verdict is None:
                UNREVIEWED.append(f'{key[0]}/{key[1]}')
            origins += [f'{os.path.relpath(p, top)}:{n}: {text}' for n, text in notes]
            origins.append(f'  -> {"reviewed: " + verdict if verdict else "UNREVIEWED: add it to REVIEWED once it is matched to the inventory"}')
    print(f'== {label}: {total} source files')
    for name, n in counts.items():
        if n:
            print(f'   {name}: {n}')
    print(f'   no license marker in the first 60 lines: {len(none)}' + (f' (first: {", ".join(none[:6])})' if none else ''))
    if spdx:
        print('   SPDX identifiers: ' + ', '.join(f'{k} {v}' for k, v in sorted(spdx.items())))
    print(f'   origin notes (a copy of another project, a link to a file in another repository, a license tag): '
          f'{sum(1 for o in origins if not o.startswith("  -> "))}')
    for o in origins:
        print(f'     {o}')
    if vendor_dirs:
        print(f'   directories named like vendored code (third_party, vendor ...): {len(vendor_dirs)}')
        for v in vendor_dirs:
            print(f'     {v}')
    for rel, text in revs[:4]:
        print(f'   {rel}: {" ".join(text.split())[:300]}')


def main(argv):
    dirs, checkouts, i = [], [], 0
    while i < len(argv):
        if argv[i] == '--dir':
            dirs.append(argv[i + 1])
            i += 2
        else:
            checkouts.append(argv[i])
            i += 1
    for checkout in checkouts:
        head = subprocess.run(['git', '-C', checkout, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
        found = [(n, k, d) for n, k, d in target_dirs(checkout) if any(True for _ in files_in(d, C_EXT))]
        print(f'#### {checkout} at {head or "?"}: {len(found)} target(s) with C-family files')
        for name, kind, d in found:
            survey(d, f'{d} (target {name}, {kind})', C_EXT)
    for d in dirs:
        survey(d, d, DIR_EXT)
    print()
    print(f'files with origin notes, and directories named like vendored code, not yet reviewed: {len(UNREVIEWED)}'
          + ''.join(f'\n  {u}' for u in UNREVIEWED))
    return 1 if UNREVIEWED else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
