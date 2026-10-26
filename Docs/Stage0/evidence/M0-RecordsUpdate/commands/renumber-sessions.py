#!/usr/bin/env python3
"""Renumber what m0-sessions numbered alike with m0-exit-prep, in the text that
came from m0-sessions.

Both branches appended integration log sections after section 27 and items
after item 103 of the gate summary's Section 6.3: m0-exit-prep's sections
28-35 and items 104-130, m0-sessions's sections 28-32 and items 104-150. After
both are merged, m0-exit-prep's keep their numbers and m0-sessions's become
sections 36-40 and items 131-177 (section + 8, item + 27).

A line is m0-sessions's when it is, verbatim, in the file at SESSIONS and in
neither the file at EXIT_PREP nor at BASE nor at OWNER. In such lines (and in
the integration log's sections that came from m0-sessions, headings included)
this rewrites:
  - "section(s) N" (lowercase) and "integration log N.M" for N in 28-32;
  - "N.M" sub-section numbers inside m0-sessions's integration log sections;
  - "item(s) N" for N in 104-150 (Section 6.3's numbering), and the numbered
    list items themselves in Section 6.3.
References to m0-sessions's never-written section 33 and items 151-158 are not
rewritten: they are listed for a person to handle.

Lines that are in none of the four versions (combined by the merge) are
listed with their candidate references, for a person to handle; nothing in
them is rewritten.

usage: renumber-sessions.py [--apply] FILE...
"""
import argparse
import re
import subprocess
import sys

BASE = "044ed3cf86db838c93cda7e2ca4829474b234ae5"
OWNER = "c72247a69a374ce361834550b92689b4abab95ee"
EXIT_PREP = "c3adae682812c2f47ed3bb7f07778ccb25118963"
SESSIONS = "1d5ac477e5cb71ce453f74a1676a405fe491bf68"
SEC_SHIFT, ITEM_SHIFT = 8, 27

SEC = re.compile(r"\b(sections?|integration log)( )(2[89]|3[0-3])\b(\.\d+)*")
SEC_LIST = re.compile(r"\b(sections) (2[89]|3[0-3])((?:(?:, | and |-)(?:2[89]|3[0-3]))+)\b")
SUB = re.compile(r"(?<![\d.])(2[89]|3[0-2])\.(\d{1,2})(?:\.(\d))?(?![\d])")
ITEM = re.compile(r"\b(items?) (1[0-5]\d)((?:(?:, | and |-)1[0-5]\d)*)\b")


def lines_at(rev, path):
    r = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True)
    return set(r.stdout.decode("utf-8", "replace").split("\n")) if r.returncode == 0 else set()


def shift_sec(n):
    n = int(n)
    return str(n + SEC_SHIFT) if 28 <= n <= 32 else None


def shift_item(n):
    n = int(n)
    return str(n + ITEM_SHIFT) if 104 <= n <= 150 else None


def renumber(line, in_sessions_log_section, problems, where):
    def sec_list(m):
        nums = re.findall(r"\d+", m.group(0)[len(m.group(1)) + 1:])
        seps = re.findall(r", | and |-", m.group(3))
        out = [shift_sec(x) for x in nums]
        if None in out:
            problems.append(f"{where}: {m.group(0)!r} names a section m0-sessions never wrote")
            return m.group(0)
        s = f"{m.group(1)} {out[0]}"
        for sep, x in zip(seps, out[1:]):
            s += sep + x
        return s

    def sec(m):
        new = shift_sec(m.group(3))
        if new is None:
            problems.append(f"{where}: {m.group(0)!r} names a section m0-sessions never wrote")
            return m.group(0)
        return f"{m.group(1)}{m.group(2)}{new}{m.group(0)[len(m.group(1)) + 1 + len(m.group(3)):]}"

    def item(m):
        nums = re.findall(r"1[0-5]\d", m.group(0))
        seps = re.findall(r", | and |-", m.group(3) or "")
        out = [shift_item(x) for x in nums]
        if None in out:
            problems.append(f"{where}: {m.group(0)!r} names an item m0-sessions never wrote")
            return m.group(0)
        s = f"{m.group(1)} {out[0]}"
        for sep, x in zip(seps, out[1:]):
            s += sep + x
        return s

    def sub(m):
        new = shift_sec(m.group(1))
        tail = f".{m.group(3)}" if m.group(3) else ""
        return f"{new}.{m.group(2)}{tail}"

    line = SEC_LIST.sub(sec_list, line)
    line = SEC.sub(sec, line)
    line = ITEM.sub(item, line)
    if in_sessions_log_section:
        line = SUB.sub(sub, line)
    return line


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()
    problems, mixed, changed = [], [], 0
    for path in args.files:
        sess = lines_at(SESSIONS, path)
        other = lines_at(EXIT_PREP, path) | lines_at(BASE, path) | lines_at(OWNER, path)
        text = open(path, encoding="utf-8").read().split("\n")
        out = []
        in_log_section = False
        in_items = False
        for n, line in enumerate(text, 1):
            if path.endswith("integration-log.md") and line.startswith("## "):
                m = re.match(r"## (\d+)\. ", line)
                in_log_section = bool(m and 28 <= int(m.group(1)) <= 32 and line in sess and line not in other)
            if path.endswith("M0-gate.md"):
                if line.startswith("### 6.3"):
                    in_items = True
                elif line.startswith("## 7."):
                    in_items = False
            origin_sessions = line in sess and line not in other
            new = line
            if origin_sessions or in_log_section:
                where = f"{path}:{n}"
                if path.endswith("integration-log.md") and in_log_section and line.startswith("#"):
                    m = re.match(r"^(#{2,4} )(2[89]|3[0-2])((?:\.\d+)*)(\.? )(.*)$", line)
                    if m:
                        new = (m.group(1) + shift_sec(m.group(2)) + m.group(3) + m.group(4)
                               + renumber(m.group(5), True, problems, where))
                    else:
                        new = renumber(line, True, problems, where)
                else:
                    new = renumber(line, in_log_section, problems, where)
                if in_items and origin_sessions:
                    m = re.match(r"^(\d+)\. ", new)
                    if m and 104 <= int(m.group(1)) <= 150:
                        new = f"{int(m.group(1)) + ITEM_SHIFT}. " + new[m.end():]
            elif line not in sess and line not in other:
                cands = [m.group(0) for m in SEC.finditer(line)] + [m.group(0) for m in ITEM.finditer(line)
                                                                     if any(104 <= int(x) <= 158 for x in re.findall(r"1[0-5]\d", m.group(0)))]
                if cands:
                    mixed.append(f"{path}:{n}: {cands}")
            if new != line:
                changed += 1
            out.append(new)
        if args.apply:
            open(path, "w", encoding="utf-8").write("\n".join(out))
    for p in problems:
        print("dangling:", p)
    for m in mixed:
        print("mixed:   ", m)
    print(f"{changed} line(s) {'rewritten' if args.apply else 'to rewrite'}; {len(problems)} dangling; {len(mixed)} mixed line(s) listed")


if __name__ == "__main__":
    sys.exit(main())
