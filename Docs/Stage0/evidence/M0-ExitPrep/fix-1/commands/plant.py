#!/usr/bin/env python3
"""Plant one route of the review of the M0 exit preparation's finding SEC-ZIPGUARD-01 in a copy of the repository tree:
a product manifest's local package inside Apps/ or Packages/ that git does not track, which the dependency check judged
only against Spikes/ and the product roots, so that its manifest and sources were read by nothing.

  /usr/bin/python3 -I plant.py <copy of the tree> <route>
  /usr/bin/python3 -I plant.py --list

Each route edits the real product manifests of the copy (Apps/DesignCatalog/project.yml, Packages/Design/Package.swift)
as the review's reproductions did (its b00, b01, b02 and b03), or in the forms of the same kind the fix also closes.
Where a route needs the local package's directory populated, as a build would find it, it writes a stand-in package
named Zip there, whose one source file declares a type and imports nothing: it is not marmelroy/Zip's code, and the
check never reads it, since it is untracked (under .build, which the check skips in a tree with no .git, as git ignores
it; or, for the route `git`, a file the copy's git repository does not track). Nothing here adds a requirement on a
remote package, so the copy's inventory and locks stay as they are, and the route is the only thing a check could
report. reproductions.sh runs the check before the fix and after it on each planted copy.
"""
import os
import sys

DC = 'Apps/DesignCatalog/project.yml'
DESIGN = 'Packages/Design/Package.swift'
STAND_IN_MANIFEST = ('// swift-tools-version: 6.2\n'
                     '// A stand-in for a package checkout (fix-1 reproductions): not marmelroy/Zip.\n'
                     'import PackageDescription\n'
                     'let package = Package(\n'
                     '    name: "Zip",\n'
                     '    platforms: [.iOS(.v26), .macOS(.v26)],\n'
                     '    products: [.library(name: "Zip", targets: ["Zip"])],\n'
                     '    targets: [.target(name: "Zip")]\n'
                     ')\n')
STAND_IN_SOURCE = 'public enum StandIn {\n    public static let name = "a stand-in package named Zip"\n}\n'


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


def stand_in(directory):
    """The local package's directory, populated as a build would find it, with the stand-in package."""
    def plant(r):
        add(r, f'{directory}/Package.swift', STAND_IN_MANIFEST)
        add(r, f'{directory}/Sources/Zip/StandIn.swift', STAND_IN_SOURCE)
    return plant


def dc_package(name, path):
    return lambda r: edit(r, DC, 'packages:\n', f'packages:\n  {name}:\n    path: {path}\n')


def dc_uses(package, product):
    """The DesignCatalog app target, a shipping target, depends on the product."""
    anchor = '      - package: SylviaDesign\n        product: SylviaDesignGallery\n'
    return lambda r: edit(r, DC, anchor, anchor + f'      - package: {package}\n        product: {product}\n')


def design_package(path, package):
    """Packages/Design depends on the local package at path, and its SylviaDesign library target, which ships, on that
    package's product Zip."""
    def plant(r):
        edit(r, DESIGN, '    dependencies: [\n        .package(url:',
             f'    dependencies: [\n        .package(path: "{path}"),\n        .package(url:')
        edit(r, DESIGN, 'name: "SylviaDesign",\n            dependencies: ["SylviaDesignTokens"],',
             f'name: "SylviaDesign",\n            dependencies: ["SylviaDesignTokens", .product(name: "Zip", package: "{package}")],')
    return plant


def tree(*changes):
    return lambda r: [c(r) for c in changes]


ROUTES = {
    # The review's b00: a local package in Packages/Design's own package checkouts, populated as at build time, whose
    # product the shipping app target uses.
    'b00 the app project depends on a local package in Packages/Design/.build/checkouts, populated, and the app uses its product':
        tree(stand_in('Packages/Design/.build/checkouts/Zip'),
             dc_package('Vendored', '../../Packages/Design/.build/checkouts/Zip'), dc_uses('Vendored', 'Zip')),
    # The review's b01, its control: the same package at the repository root's .build, outside the product roots,
    # which the check reported before the fix too (outside-product).
    'b01 (control) the same local package at the repository root, outside the product roots':
        tree(stand_in('.build/checkouts/Zip'), dc_package('Vendored', '../../.build/checkouts/Zip'), dc_uses('Vendored', 'Zip')),
    # The review's b02: Packages/Design's manifest depends on a local package under its own .build (here not
    # populated: the manifest is read the same way either way), and its shipping library uses its product.
    'b02 Packages/Design depends on a local package under its own .build, and SylviaDesign uses its product':
        design_package('.build/checkouts/Zip', 'Zip'),
    # The review's b03: Packages/Design depends on ../Vendored, a directory under Packages/ that holds only an
    # untracked .build.
    'b03 Packages/Design depends on Packages/Vendored, which holds only an untracked .build':
        tree(stand_in('Packages/Vendored/.build/checkouts/Zip'), design_package('../Vendored', 'Vendored')),
    # XcodeGen's localPackages list, the older form of the same declaration.
    "localPackages the app project's localPackages list names the package checkout":
        tree(stand_in('Packages/Design/.build/checkouts/Zip'),
             lambda r: edit(r, DC, 'targets:\n  DesignCatalog:\n',
                            'localPackages:\n  - ../../Packages/Design/.build/checkouts/Zip\ntargets:\n  DesignCatalog:\n'),
             dc_uses('Zip', 'Zip')),
    # A directory git tracks, but no Package.swift git tracks: tracked content is not enough.
    'tracked-dir the app project names a tracked directory with no Package.swift (Packages/Design/Sources) as a local package':
        dc_package('DesignSources', '../../Packages/Design/Sources'),
    # In a copy that is a git repository (reproductions.sh makes it one, the base committed): a package generated or
    # copied into Packages/ before the build, outside any .build, which git does not track.
    'git in a git repository, Packages/Design depends on Packages/Generated, a package git does not track':
        tree(stand_in('Packages/Generated'), design_package('../Generated', 'Generated')),
}


def main():
    if sys.argv[1:] == ['--list']:
        print('\n'.join(ROUTES))
        return 0
    root, route = sys.argv[1], sys.argv[2]
    ROUTES[route](root)
    return 0


if __name__ == '__main__':
    sys.exit(main())
