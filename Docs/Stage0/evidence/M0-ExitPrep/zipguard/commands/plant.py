#!/usr/bin/env python3
"""Plant one route around the dependency check's Zip guard in a copy of the repository tree (ADR-0014, review round 4:
R4-01, R4-02, R4-03 and R4-04, and the routes of the same kind that the fix closes with them).

  /usr/bin/python3 -I plant.py <copy of the tree> <route>
  /usr/bin/python3 -I plant.py --list

Each route edits the real product manifests and code of the copy (Apps/DesignCatalog, Packages/Design), the way the
review's reproductions did, and records any requirement it adds in the copy's inventory as the update procedure asks,
so that the route is the only thing a check could report. reproductions.sh runs the check before the fix and after it
on each planted copy.
"""
import json
import os
import sys

DC = 'Apps/DesignCatalog/project.yml'
DESIGN = 'Packages/Design/Package.swift'
INVENTORY = 'Docs/Licenses/inventory.json'
SHIM = 'Packages/Design/Sources/SylviaDesign/include/shim.h'
CONFIG = 'Apps/DesignCatalog/Config/Debug.xcconfig'


def edit(root, rel, old, new):
    path = os.path.join(root, rel)
    text = open(path, encoding='utf-8').read()
    if old not in text:
        raise SystemExit(f'plant.py: {old!r} is not in {rel}')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text.replace(old, new, 1))


def add(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def inventory(root, change):
    path = os.path.join(root, INVENTORY)
    d = json.load(open(path, encoding='utf-8'))
    change(d)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(d, f, indent=2)
        f.write('\n')


def package(d, name):
    return next(p for p in d['packages'] if p['name'] == name)


def dc_packages(text):
    return lambda r: edit(r, DC, 'packages:\n', 'packages:\n' + text)


def dc_target(text):
    """Lines added to the DesignCatalog app target, after its type."""
    return lambda r: edit(r, DC, '  DesignCatalog:\n    type: application\n', '  DesignCatalog:\n    type: application\n' + text)


def dc_settings(text):
    """Base build settings added to the DesignCatalog app target."""
    return lambda r: edit(r, DC, '        PRODUCT_NAME: DesignCatalog\n', '        PRODUCT_NAME: DesignCatalog\n' + text)


def dc_templates(text):
    return lambda r: edit(r, DC, 'targets:\n  DesignCatalog:\n', 'targetTemplates:\n' + text + 'targets:\n  DesignCatalog:\n')


def dc_config(text, extra=None):
    """The DesignCatalog project takes Config/Debug.xcconfig (configFiles) with this text; extra is (path, text)."""
    def plant(r):
        edit(r, DC, 'targets:\n  DesignCatalog:\n', 'configFiles:\n  Debug: Config/Debug.xcconfig\ntargets:\n  DesignCatalog:\n')
        add(r, CONFIG, text)
        if extra:
            add(r, *extra)
    return plant


def snapshot_declared(r):
    """The DesignCatalog project declares swift-snapshot-testing, which its lock already pins, recorded in direct_in."""
    dc_packages('  swift-snapshot-testing:\n    url: https://github.com/pointfreeco/swift-snapshot-testing\n'
                '    exactVersion: 1.19.6\n')(r)
    inventory(r, lambda d: package(d, 'pointfreeco/swift-snapshot-testing')['direct_in'].append(DC))


def all_of(*plants):
    return lambda r: [p(r) for p in plants]


def design_manifest(code, old, new):
    """Packages/Design/Package.swift with Swift code after its import line, and one more replacement."""
    return all_of(lambda r: edit(r, DESIGN, 'import PackageDescription\n', 'import PackageDescription\n' + code),
                  lambda r: edit(r, DESIGN, old, new))


SYLVIA_DESIGN_DEPS = '            dependencies: ["SylviaDesignTokens"],\n            path: "Sources/SylviaDesign",'
EXTRA_DEPS = '            dependencies: ["SylviaDesignTokens"] + extra,\n            path: "Sources/SylviaDesign",'

ROUTES = {
    # Review R4-01 as reproduced by the review (its (a), (b) and (c)), and what else XcodeGen evaluates.
    'R4-01 (a) local package path from the environment, into Spikes/':
        dc_packages('  ZipEvalCommon:\n    path: ${SYLVIA_ROOT}/Spikes/G03-Intake/ZipEval/Common\n'),
    'R4-01 (b) target template named from the environment, passing -import-module Zip':
        all_of(dc_templates('  Quiet:\n    settings:\n      base:\n        OTHER_SWIFT_FLAGS: "-Xfrontend -import-module -Xfrontend Zip"\n'),
               dc_target('    templates:\n      - ${SYLVIA_TEMPLATE}\n')),
    'R4-01 (c) app dependency on a package named from the environment (swift-snapshot-testing)':
        all_of(snapshot_declared,
               lambda r: edit(r, DC, '        product: SylviaDesignGallery\n',
                              '        product: SylviaDesignGallery\n      - package: ${SYLVIA_EXTRA_PACKAGE}\n        product: SnapshotTesting\n')),
    'YAML escape \\x24{ that parses to ${ (local package path)':
        dc_packages('  ZipEvalCommon:\n    path: "\\x24{SYLVIA_ROOT}/Spikes/G03-Intake/ZipEval/Common"\n'),
    'build setting name from the environment (a key)':
        dc_settings('        ${SYLVIA_SEARCH_SETTING}: "$(SRCROOT)/../../Scripts/tools"\n'),
    'template attribute naming the package of a dependency (templateAttributes; swift-snapshot-testing)':
        all_of(snapshot_declared,
               dc_templates('  WithDep:\n    dependencies:\n      - package: ${dep_package}\n        product: SnapshotTesting\n'),
               dc_target('    templates: [WithDep]\n    templateAttributes:\n      dep_package: swift-snapshot-testing\n')),
    'local package path with a leading ~':
        dc_packages('  Vendored:\n    path: ~/Vendor/Zip\n'),
    # The same reasoning for SwiftPM: every build evaluates Packages/Design/Package.swift again.
    'Package.swift reads the environment through Context (adds SnapshotTesting to SylviaDesign)':
        design_manifest('let extra: [Target.Dependency] = Context.environment["SYLVIA_EXTRA"] == nil ? [] : '
                        '[.product(name: "SnapshotTesting", package: "swift-snapshot-testing")]\n',
                        SYLVIA_DESIGN_DEPS, EXTRA_DEPS),
    'Package.swift imports Foundation and reads ProcessInfo (adds SnapshotTesting to SylviaDesign)':
        design_manifest('import Foundation\nlet extra: [Target.Dependency] = ProcessInfo.processInfo.environment["SYLVIA_EXTRA"] == nil ? [] : '
                        '[.product(name: "SnapshotTesting", package: "swift-snapshot-testing")]\n',
                        SYLVIA_DESIGN_DEPS, EXTRA_DEPS),
    # Review R4-02 as reproduced by the review (its (a) and (b)), and the other forms of the same include.
    'R4-02 (a) product header includes a file outside Apps/ and Packages/':
        lambda r: add(r, SHIM, '#include "../../../../../Scripts/tools/x.h"\n'),
    "R4-02 (b) product header includes Minizip's unzip.c from a package checkout":
        lambda r: add(r, SHIM, '#include "../../../.build/checkouts/Zip/Zip/minizip/unzip.c"\n'),
    "include \"../unzip.c\", found through Minizip's include directory":
        lambda r: add(r, SHIM, '#include "../unzip.c"\n'),
    'include <../unzip.c>':
        lambda r: add(r, SHIM, '#include <../unzip.c>\n'),
    'computed include of ../unzip.c through a macro':
        lambda r: add(r, SHIM, '#define MINIZIP_SOURCE "../unzip.c"\n#include MINIZIP_SOURCE\n'),
    '#embed of a file outside the product roots':
        lambda r: add(r, SHIM, 'static const unsigned char blob[] = {\n#embed "../../../../../Scripts/tools/requirements.txt"\n};\n'),
    'assembly file with .incbin of a file outside the product roots':
        lambda r: add(r, 'Packages/Design/Sources/SylviaDesign/blob.s', '.data\n.incbin "../../../../Scripts/tools/requirements.txt"\n'),
    'inline assembly with .incbin of ../unzip.c':
        lambda r: add(r, SHIM, '__asm__(".data\\n.incbin \\"../unzip.c\\"\\n.text");\n'),
    'build-settings file #includes one outside Apps/ and Packages/':
        dc_config('#include "../../../Scripts/tools/Base.xcconfig"\n', ('Scripts/tools/Base.xcconfig', 'OTHER_LDFLAGS = -ObjC\n')),
    "build-settings file #includes one from Xcode's directory (<DEVELOPER_DIR>)":
        dc_config('#include "<DEVELOPER_DIR>/Makefiles/CoreOS/Xcode/BSD.xcconfig"\n'),
    'build-settings file #include? of a file git does not track':
        dc_config('#include? "Generated.xcconfig"\n'),
    'build rule that compiles *.txt files with clang':
        dc_target('    buildRules:\n      - filePattern: "*.txt"\n        compilerSpec: com.apple.compilers.llvm.clang.1_0\n'),
    # Review R4-03 and R4-04 as reproduced by the review.
    'R4-03 DERIVED_FILE_DIR redefined, then searched for headers and Swift modules':
        dc_settings('        DERIVED_FILE_DIR: /opt/elsewhere/Zip/Zip/minizip/include\n        HEADER_SEARCH_PATHS: $(DERIVED_FILE_DIR)\n'
                    '        SWIFT_INCLUDE_PATHS: $(DERIVED_FILE_DIR)\n'),
    'R4-04 -Werror followed by an input file in OTHER_LDFLAGS':
        dc_settings('        OTHER_LDFLAGS: "-Werror Evil"\n'),
}


def main():
    if sys.argv[1:] == ['--list']:
        for name in ROUTES:
            print(name)
        return 0
    root, route = sys.argv[1], sys.argv[2]
    ROUTES[route](root)
    return 0


if __name__ == '__main__':
    sys.exit(main())
