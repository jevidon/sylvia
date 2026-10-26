#!/usr/bin/env python3
"""Plant one route of the fourth review of the M0 exit preparation's finding SEC-ZIPGUARD-03, or of the routes of the
same kind found with its fix, in a copy of the repository tree, and judge what the dependency check reported on it.

  /usr/bin/python3 -I plant.py --list                               the routes, one per line
  /usr/bin/python3 -I plant.py <copy> <route>                       plant the route's files in the copy
  /usr/bin/python3 -I plant.py --index <route>                      for a route in a git repository: each planted file
                                                                    as "<path written> <path git tracks it as>"
  /usr/bin/python3 -I plant.py --verdict <route> <before> <after>   judge the check's two logs (exit 1 if unexpected)

SEC-ZIPGUARD-03: SwiftPM evaluates a version-specific manifest (Package@swift-<version>.swift) instead of the
Package.swift beside it, and the check's manifest-input rule read the raw text of Package.swift alone, so such a file
could read the environment and give a build a value the check, run without the variable as CI runs it, never saw. The
routes found with the fix: on the default macOS file system, which ignores letter case, a path tracked under a root
spelled in another letter case (packages/), a manifest named package.swift or Project.yml, and a module map named
MODULE.MODULEMAP or module_private.map are read by the build, under names the check read only as spelled.

Each route edits a copy of the tree as reproductions.sh makes it (git archive of the reviewed commit), and, for the
routes whose name begins with `git`, a copy that reproductions.sh has made a git repository: plant.py writes each file
at its path on disk, and reproductions.sh adds it to the index under the path --index prints, which may differ from it in
letter case only, as a commit made elsewhere would carry it. Nothing here adds a requirement on a remote package, so the
copy's inventory and locks stay as they are. A control is the same change with every name as the check reads it: the
check reports it before the fix and after it, the same way.
"""
import os
import re
import sys

DC = 'Apps/DesignCatalog/project.yml'
DESIGN = 'Packages/Design/Package.swift'
DESIGN_TARGET = 'name: "SylviaDesign",\n            dependencies: ["SylviaDesignTokens"],\n            path: "Sources/SylviaDesign",'
INCLUDE = 'Packages/Design/Sources/SylviaDesign/include'
# A product package of its own whose library target passes -import-module Zip, so that every file it compiles imports
# marmelroy/Zip's module (the check's flag rule fails the flag, and its transitive-direct rule the module, when it reads
# the manifest).
SHADOW_MANIFEST = ('// swift-tools-version: 6.2\n'
                   '// A product package planted by the fix-2 reproductions: its target imports Zip into every file.\n'
                   'import PackageDescription\n'
                   'let package = Package(\n'
                   '    name: "Shadow",\n'
                   '    platforms: [.iOS(.v26), .macOS(.v26)],\n'
                   '    products: [.library(name: "Shadow", targets: ["Shadow"])],\n'
                   '    targets: [\n'
                   '        .target(name: "Shadow", swiftSettings: [.unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "Zip"])]),\n'
                   '    ]\n'
                   ')\n')
SHADOW_SOURCE = 'public enum Shadow {\n    public static let name = "a planted product package"\n}\n'
SHADOW_PROJECT = ('name: Shadow\n'
                  'options:\n'
                  '  bundleIdPrefix: com.example\n'
                  '  deploymentTarget:\n'
                  '    iOS: "26.0"\n'
                  'targets:\n'
                  '  Shadow:\n'
                  '    type: application\n'
                  '    platform: iOS\n'
                  '    sources:\n'
                  '      - path: Sources\n'
                  '    settings:\n'
                  '      base:\n'
                  '        OTHER_SWIFT_FLAGS: "-Xfrontend -import-module -Xfrontend Zip"\n')
ZIP_IMPORT = '// Planted by the fix-2 reproductions: an import of marmelroy/Zip in shipping code.\ninternal import Zip\n'
MAP_UNZIP = 'module Mini {\n    header "unzip.h"\n    export *\n}\n'


def read(root, rel):
    return open(os.path.join(root, rel), encoding='utf-8').read()


def edit(root, rel, old, new):
    text = read(root, rel)
    if old not in text:
        raise SystemExit(f'plant.py: {old!r} is not in {rel}')
    with open(os.path.join(root, rel), 'w', encoding='utf-8') as f:
        f.write(text.replace(old, new, 1))


def add(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def design_version_specific(name, code, target):
    """A version-specific manifest beside Packages/Design/Package.swift, which stays as it is: Design's manifest with
    Swift code after its import line and the SylviaDesign target's opening lines replaced."""
    def plant(r):
        text = read(r, DESIGN)
        for old, new in (('import PackageDescription\n', 'import PackageDescription\n' + code), (DESIGN_TARGET, target)):
            if old not in text:
                raise SystemExit(f'plant.py: {old!r} is not in {DESIGN}')
            text = text.replace(old, new, 1)
        add(r, f'Packages/Design/{name}', text)
    return plant


ENV_PATH = design_version_specific(
    'Package@swift-6.4.swift',
    'import Foundation\nlet designPath = ProcessInfo.processInfo.environment["SYLVIA_EXTRA"] ?? "Sources/SylviaDesign"\n',
    'name: "SylviaDesign",\n            dependencies: ["SylviaDesignTokens"],\n            path: designPath,')
ENV_TEST_PACKAGE = design_version_specific(
    'Package@swift-6.swift',
    'import Foundation\nlet extra: [Target.Dependency] = ProcessInfo.processInfo.environment["SYLVIA_EXTRA"] == nil ? []\n'
    '    : [.product(name: "SnapshotTesting", package: "swift-snapshot-testing")]\n',
    'name: "SylviaDesign",\n            dependencies: ["SylviaDesignTokens"] + extra,\n            path: "Sources/SylviaDesign",')


def dc_uses_shadow(r):
    """The design catalog app, a shipping target, depends on the planted package's product."""
    edit(r, DC, 'packages:\n', 'packages:\n  Shadow:\n    path: ../../Packages/Shadow\n')
    anchor = '      - package: SylviaDesign\n        product: SylviaDesignGallery\n'
    edit(r, DC, anchor, anchor + '      - package: Shadow\n        product: Shadow\n')


def shadow_package(manifest_name):
    def plant(r):
        add(r, f'Packages/Shadow/{manifest_name}', SHADOW_MANIFEST)
        add(r, 'Packages/Shadow/Sources/Shadow/Shadow.swift', SHADOW_SOURCE)
        dc_uses_shadow(r)
    return plant


def shadow_project(name):
    def plant(r):
        add(r, f'Apps/Shadow/{name}', SHADOW_PROJECT)
        add(r, 'Apps/Shadow/Sources/App.swift', 'print("a planted product app")\n')
    return plant


def tree(*changes):
    return lambda r: [c(r) for c in changes]


# name: (description, plant, the files the route plants that the check must report after the fix (each failure after
# it must be at one of them), the categories it may report them in, whether it is a control, index paths for a git copy)
ROUTES = {
    'vsm-env': (
        "the review's route: Packages/Design/Package@swift-6.4.swift beside an unchanged Package.swift, the SylviaDesign "
        "target's path read from the environment variable SYLVIA_EXTRA (as fix-1's observation planted it)",
        ENV_PATH, ['Packages/Design/Package@swift-6.4.swift'], {'manifest-input'}, False, None),
    'vsm-test-package': (
        "Packages/Design/Package@swift-6.swift: SylviaDesign, a shipping library, depends on the test-only "
        "SnapshotTesting when SYLVIA_EXTRA is set",
        ENV_TEST_PACKAGE, ['Packages/Design/Package@swift-6.swift'], {'manifest-input'}, False, None),
    'vsm-letter-case': (
        "the review's route named in capitals, Packages/Design/PACKAGE@SWIFT-6.4.SWIFT, which SwiftPM takes too",
        tree(ENV_PATH, lambda r: os.rename(os.path.join(r, 'Packages/Design/Package@swift-6.4.swift'),
                                           os.path.join(r, 'Packages/Design/PACKAGE@SWIFT-6.4.SWIFT'))),
        ['Packages/Design/PACKAGE@SWIFT-6.4.SWIFT'], {'manifest-input'}, False, None),
    'manifest-letter-case': (
        "Packages/Shadow/package.swift, a product package whose target passes -import-module Zip, which the design "
        "catalog app uses through ../../Packages/Shadow",
        shadow_package('package.swift'), ['Packages/Shadow/package.swift'], {'letter-case'}, False, None),
    'manifest-letter-case-control': (
        "(control) the same package with its manifest named Package.swift",
        shadow_package('Package.swift'), [], set(), True, None),
    'project-letter-case': (
        "Apps/Shadow/Project.yml, a product project whose app target passes -import-module Zip",
        shadow_project('Project.yml'), ['Apps/Shadow/Project.yml'], {'letter-case'}, False, None),
    'project-letter-case-control': (
        "(control) the same project named project.yml",
        shadow_project('project.yml'), [], set(), True, None),
    'git-root-letter-case': (
        "in a git repository: Shadow.swift, which imports Zip, in SylviaDesign's source directory, tracked as "
        "packages/Design/Sources/SylviaDesign/Shadow.swift",
        lambda r: add(r, 'Packages/Design/Sources/SylviaDesign/Shadow.swift', ZIP_IMPORT),
        ['packages/Design/Sources/SylviaDesign/Shadow.swift'], {'letter-case'}, False,
        [('Packages/Design/Sources/SylviaDesign/Shadow.swift', 'packages/Design/Sources/SylviaDesign/Shadow.swift')]),
    'git-root-letter-case-control': (
        "(control) in a git repository: the same file tracked as Packages/Design/Sources/SylviaDesign/Shadow.swift",
        lambda r: add(r, 'Packages/Design/Sources/SylviaDesign/Shadow.swift', ZIP_IMPORT), [], set(), True,
        [('Packages/Design/Sources/SylviaDesign/Shadow.swift', 'Packages/Design/Sources/SylviaDesign/Shadow.swift')]),
    'git-root-letter-case-manifest': (
        "in a git repository: the planted package tracked as packages/Shadow/Package.swift and its source, which the "
        "design catalog app uses through ../../Packages/Shadow",
        shadow_package('Package.swift'),
        ['packages/Shadow/Package.swift', 'packages/Shadow/Sources/Shadow/Shadow.swift'], {'letter-case'}, False,
        [('Packages/Shadow/Package.swift', 'packages/Shadow/Package.swift'),
         ('Packages/Shadow/Sources/Shadow/Shadow.swift', 'packages/Shadow/Sources/Shadow/Shadow.swift'),
         (DC, DC)]),
    'modulemap-letter-case': (
        f"{INCLUDE}/MODULE.MODULEMAP, which clang loads as module.modulemap, names Minizip's unzip.h",
        lambda r: add(r, f'{INCLUDE}/MODULE.MODULEMAP', MAP_UNZIP), [f'{INCLUDE}/MODULE.MODULEMAP'],
        {'transitive-direct', 'outside-product'}, False, None),
    'modulemap-letter-case-control': (
        "(control) the same module map named module.modulemap",
        lambda r: add(r, f'{INCLUDE}/module.modulemap', MAP_UNZIP), [], set(), True, None),
    'modulemap-private': (
        f"{INCLUDE}/module_private.map, which clang reads beside a module.map, names unzip.h; the module.map beside it "
        "names a header of its own",
        tree(lambda r: add(r, f'{INCLUDE}/shim.h', 'int shim(void);\n'),
             lambda r: add(r, f'{INCLUDE}/module.map', 'module Shim {\n    header "shim.h"\n    export *\n}\n'),
             lambda r: add(r, f'{INCLUDE}/module_private.map', MAP_UNZIP)),
        [f'{INCLUDE}/module_private.map'], {'transitive-direct', 'outside-product'}, False, None),
}

FAIL_LINE = re.compile(r'^FAIL (\S+) (\S+): ')


def failures(log):
    out = []
    for line in open(log, encoding='utf-8', errors='replace'):
        m = FAIL_LINE.match(line)
        if m:
            out.append((m.group(1), re.sub(r':[0-9]+$', '', m.group(2)), line.rstrip('\n')))
    return out


def verdict(route, before_log, after_log):
    _, _, planted, categories, control, _ = ROUTES[route]
    before, after = failures(before_log), failures(after_log)
    if control:
        ok = bool(before) and [f[2] for f in before] == [f[2] for f in after]
        print('ok (the control: fails before the fix and after it, the same way)' if ok else 'UNEXPECTED (control)')
        return 0 if ok else 1
    stray = [f for f in after if f[0] not in categories or not any(f[1] == p or f[1].startswith(p + '/') for p in planted)]
    reported = {p for p in planted if any(f[1] == p for f in after)}
    ok = not before and after and not stray and reported == set(planted)
    print(f"ok (passed before the fix; fails after it, {len(after)} finding(s), each at a planted file, in "
          f"{' or '.join(sorted(categories))})" if ok else
          f"UNEXPECTED (before: {len(before)} finding(s); after: {len(after)}, {len(stray)} of them not at a planted file "
          f"in {' or '.join(sorted(categories))}; planted files reported: {len(reported)} of {len(planted)})")
    return 0 if ok else 1


def main():
    args = sys.argv[1:]
    if args == ['--list']:
        print('\n'.join(ROUTES))
        return 0
    if args[:1] == ['--index']:
        for disk, index in ROUTES[args[1]][5] or []:
            print(disk, index)
        return 0
    if args[:1] == ['--verdict']:
        return verdict(args[1], args[2], args[3])
    if args[:1] == ['--describe']:
        print(ROUTES[args[1]][0])
        return 0
    root, route = args
    ROUTES[route][1](root)
    return 0


if __name__ == '__main__':
    sys.exit(main())
