"""ADR-0014 evidence: the build settings that Xcode's own specifications pass to the compiler, linker and librarian, and
how Scripts/check-dependency-lock.py treats each in a shipping product target (review R3-01), so that its setting lists
can be traced to the installed Xcode rather than to memory.

  "$SYLVIA_TOOLS_VENV/bin/python" -I xcode-settings.py      (from the repository root, with DEVELOPER_DIR set)

Reads Clang.xcspec, Swift.xcspec, Ld.xcspec and Libtool.xcspec, and the path settings of CoreBuildSystem.xcspec, from
the Swift Build specifications inside the selected Xcode, and prints every setting there whose type is a path, a path
list or ordered set, a string or a string list and that maps to a command-line flag or argument, or is a path. Each is classified as
the check reads it: a search directory, a header file, a module-map file, a binary, a library or framework linked by
name, a module alias, a definition, flags (any name that contains FLAGS), a tool or SDK replacement (rejected), or
text (any other setting: read only for a transitive-only package's header names and for paths into Spikes/). Imports
the check to read its lists; reads files only.
"""
import glob
import os
import re
import sys

ROOT = os.getcwd()
sys.path.insert(0, os.path.join(ROOT, 'Scripts'))
import importlib.util
spec = importlib.util.spec_from_file_location('check', os.path.join(ROOT, 'Scripts', 'check-dependency-lock.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def treatment(name):
    if name in check.DIR_SETTINGS:
        return 'search directory (judged as a path)'
    if name in check.LIBPATH_SETTINGS:
        return 'library or framework search directory (judged as a path)'
    if name in check.HEADER_FILE_SETTINGS:
        return 'header file (must be a tracked product file; read as product code)'
    if name in check.MODULEMAP_FILE_SETTINGS:
        return 'module-map file (must be a tracked product file; read as a module map)'
    if name in check.BINARY_SETTINGS:
        return 'binary (judged as a path)'
    if name in check.LINKED_SETTINGS:
        return 'linked by name (must come from an SDK or the inventory)'
    if name in check.ALIAS_SETTINGS:
        return 'module alias (a transitive-only module fails)'
    if name in check.DEFINE_SETTINGS:
        return 'definition (a transitive-only header or module name fails)'
    if 'FLAGS' in name:
        return 'flags (only the allowed flags may appear)'
    if check.TOOL_SETTINGS.match(name):
        return 'tool or input replacement (rejected)'
    if name == 'SDKROOT':
        return 'SDK (rejected unless an SDK name)'
    return 'text (read for transitive header names and Spikes/ paths only)'


def main():
    dev = os.environ.get('DEVELOPER_DIR') or '/Applications/Xcode.app/Contents/Developer'
    found = sorted(glob.glob(os.path.join(dev, '..', 'SharedFrameworks', 'SwiftBuild.framework', '**', 'XCBSpecifications.ideplugin', 'Contents', 'Resources', '*.xcspec'), recursive=True))
    wanted = ('Clang.xcspec', 'Swift.xcspec', 'Ld.xcspec', 'Libtool.xcspec', 'CoreBuildSystem.xcspec')
    files = sorted(set(os.path.realpath(f) for f in found if os.path.basename(f) in wanted))  # symbolic links lead to the same file
    print('Xcode specifications read (%s):' % os.path.realpath(dev))
    for f in files:
        print('  ' + os.path.relpath(os.path.realpath(f), os.path.realpath(os.path.join(dev, '..'))))
    if len(files) != len(wanted):
        print('FAIL: expected %d specification files, found %d' % (len(wanted), len(files)))
        return 1
    rows = dict()
    for f in files:
        text = open(f, encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'Name\s*=\s*"?([A-Z0-9_]+)"?\s*;', text):
            name = m.group(1)
            block = text[m.end(): m.end() + 900]
            nxt = re.search(r'Name\s*=\s*"?[A-Z0-9_]+"?\s*;', block)
            if nxt:
                block = block[:nxt.start()]
            kind = re.search(r'Type\s*=\s*"?([A-Za-z]+)"?', block)
            if not kind or kind.group(1) not in ('PathList', 'PathOrderedSet', 'Path', 'StringList', 'String'):
                continue
            flag = re.search(r'CommandLine(?:Flag|PrefixFlag)\s*=\s*"?([^";\n]+)"?', block)
            args = re.search(r'CommandLineArgs\s*=\s*(\([^)]*\)|"[^"]*"|[^;\n]+)', block)
            mapping = ' '.join(x for x in ((flag.group(1) if flag else ''), (re.sub(r'\s+', ' ', args.group(1))[:70] if args else '')) if x)
            spec_name = os.path.basename(f)[:-len('.xcspec')]
            core = spec_name == 'CoreBuildSystem'
            if core and kind.group(1) not in ('PathList', 'PathOrderedSet', 'Path'):
                continue
            if not core and not mapping and kind.group(1) not in ('PathList', 'PathOrderedSet', 'Path'):
                continue
            rows.setdefault(name, []).append((spec_name, kind.group(1), mapping))
    counts = dict()
    print('\n%d settings; for each: the specifications that define it, its type, the flag or arguments it maps to, and the check' % len(rows))
    for name in sorted(rows):
        how = treatment(name)
        counts[how.split(' (')[0]] = counts.get(how.split(' (')[0], 0) + 1
        where = '; '.join('%s %s%s' % (s, k, (' -> ' + mp) if mp else '') for s, k, mp in rows[name])
        print('%-48s %s\n    %s' % (name, how, where))
    print('\nby treatment: ' + ', '.join('%s %d' % (k, v) for k, v in sorted(counts.items())))
    listed = set(check.DIR_SETTINGS + check.LIBPATH_SETTINGS + check.HEADER_FILE_SETTINGS + check.MODULEMAP_FILE_SETTINGS
                 + check.BINARY_SETTINGS + tuple(check.LINKED_SETTINGS) + check.ALIAS_SETTINGS + check.DEFINE_SETTINGS)
    print('\nthe settings the check lists by name that the listing above leaves out (no command-line mapping in those five '
          'specifications: the build system applies them itself), and where each is defined among all the specifications:')
    every = sorted(set(os.path.realpath(f) for f in found))
    texts = dict((os.path.basename(f)[:-len('.xcspec')], open(f, encoding='utf-8', errors='replace').read()) for f in every)
    for name in sorted(n for n in listed if n not in rows):
        where = []
        for spec_name, text in sorted(texts.items()):
            for m in re.finditer(r'Name\s*=\s*"?' + name + r'"?\s*;', text):
                kind = re.search(r'Type\s*=\s*"?([A-Za-z]+)"?', text[m.end(): m.end() + 400])
                where.append('%s %s' % (spec_name, kind.group(1) if kind else 'without a type'))
        print('  %-44s %s' % (name, '; '.join(where) or 'not defined in any of the %d specifications' % len(every)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
