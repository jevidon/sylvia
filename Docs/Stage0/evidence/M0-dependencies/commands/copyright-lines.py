"""ADR-0014 evidence: every distinct copyright line in the source files of the package directories that ship, so code
taken from a third party (whose notice the acknowledgements must carry) is found even when it has no license file.

  python3 -I copyright-lines.py <dir> [<dir> ...]

For each directory: the number of source files, then each distinct copyright line (whitespace collapsed, years kept)
with the number of files that carry it. Source files: C, C++, Objective-C, assembly, Swift, JavaScript, TypeScript,
CSS. Reads files only; no network.
"""
import os
import re
import sys

EXT = ('.c', '.h', '.cc', '.cpp', '.m', '.mm', '.S', '.s', '.inc', '.swift', '.js', '.ts', '.css')
LINE = re.compile(r'copyright\s*(\(c\)|©|\d{4})|\(c\)\s*\d{4}|©\s*\d{4}', re.I)

for top in sys.argv[1:]:
    counts, files = {}, 0
    for dp, dns, fns in os.walk(top):
        dns[:] = sorted(d for d in dns if d not in {'.git', '.build', 'node_modules', 'Tests', 'Test', 'Benchmarks'})
        for fn in sorted(fns):
            if not fn.endswith(EXT):
                continue
            files += 1
            seen = set()
            with open(os.path.join(dp, fn), encoding='utf-8', errors='replace') as f:
                for n, line in enumerate(f):
                    if n > 80:
                        break
                    if LINE.search(line):
                        text = ' '.join(line.strip().strip('/*#;').split())[:140]
                        if text not in seen:
                            seen.add(text)
                            counts[text] = counts.get(text, 0) + 1
    print(f'== {top}: {files} source files (test directories skipped), {len(counts)} distinct copyright lines')
    for text, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f'   {n:5d}  {text}')
