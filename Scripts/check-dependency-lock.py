#!/usr/bin/env python3
"""Dependency lock and license inventory check (ADR-0014).

  check-dependency-lock.py [check] [--root DIR] [--toolchain]   check the repository against Docs/Licenses/inventory.json
  check-dependency-lock.py self-test                            prove every failure below is detected (synthetic trees)
  check-dependency-lock.py acknowledgements [--write]           print (or write) the acknowledgements draft that the
                                                                inventory's `acknowledgements` section describes
  check-dependency-lock.py used-by-targets [--root DIR]         print, per package, the targets that use it directly, as
                                                                the manifests declare them (the inventory's used_by_targets)

Run it with the tools virtualenv (sylvia_python; it needs PyYAML) and with Xcode selected (`swift package
dump-package` reads every Package.swift). Scripts/ci.d/12-dependency-lock.sh runs `self-test` and `check --toolchain`.

Product code is everything under the inventory's product roots (Apps/, Packages/); spike code is everything under its
spike roots (Spikes/). Test code is a Swift or C-family implementation file that test targets of the product manifests
include and no other target does (by the source paths the manifests declare, and SwiftPM's default paths as SwiftPM
chooses them); every other file under the product roots is product code, whatever its directory is called, and every
header and module map there is product code wherever it sits, since product code can include or import it from
anywhere. A shipping target is a product-manifest target that is not a test target; a product project.yml's own
settings count as every target's. `check` fails when:
  pin-differs        a Package.resolved pin, or an exact requirement, differs from the inventory's version or revision;
                     a pin's identity differs from the inventory's; or a lock pins one package twice
  pin-missing        a lock lacks a package the inventory says it pins, or a package that its manifest requires directly
                     or through a local package (a stale lock, which a build would re-resolve instead of using)
  unknown-package    a lock or manifest names a package that is not in the inventory
  not-exact          a requirement is not an exact version: in a Package.swift or project.yml; a lock pin on a branch, a
                     bare revision or a kind other than remoteSourceControl; a Python requirement; or a workflow action on
                     a tag or branch rather than a commit, unless the inventory records a reasoned exemption for it
  spike-in-product   code under Spikes/ can reach Apps/ or Packages/: a product manifest or lock names a spike-only
                     package; a product manifest depends on a local package under Spikes/ (symbolic links resolved); any
                     path a product manifest names (sources, resources, frameworks, bundles, scripts, search paths and
                     flags), or a build-settings (.xcconfig) file or module map under the product roots names, resolves
                     under Spikes/ (test targets included); a symbolic link under Apps/ or Packages/ resolves there; or a
                     product C-family file #includes or #imports a file there
  outside-product    a product manifest builds from somewhere outside Apps/ and Packages/, where the product rules would
                     not see the code: a local package; a source of a shipping target; a build-settings file it uses
                     (configFiles, and the files those #include, each of which must be a file git tracks under the
                     product roots, so neither "<DEVELOPER_DIR>/..." nor an untracked #include? passes, and a # line the
                     check cannot read as an #include fails; review R4-02); a referenced Xcode project; a header,
                     module-map, bridging-header or prefix-header path in its settings or flags (or in a module map under
                     the product roots); or a symbolic link under Apps/ or Packages/ resolves outside them. And, for a
                     shipping target (review R3-01): a path it names inside the product roots holds nothing git tracks (a
                     build product, a package checkout under .build, a generated file), or a header or module map it
                     takes is not a file git tracks there; a path that starts with a build-product, SDK or toolchain
                     variable leaves that directory (..), reaches package checkouts (SourcePackages, checkouts), or is
                     where it takes a header, module map or sources from; a path uses any other variable, which the check
                     cannot evaluate; a setting assigns a variable the check evaluates itself (TRUSTED_VARS: the
                     build-product, SDK, toolchain and project-directory variables, SDKROOT to an SDK's name excepted;
                     review R4-03); a setting replaces a compiler, linker, SDK or toolchain input (CC, LD, LIBTOOL,
                     SWIFT_EXEC, TOOLCHAINS, SDKROOT other than an SDK's name, a header map, a response file, pkg-config
                     and the like); or the target declares build rules, which decide what compiles a file. And product
                     code that is not a test (review R4-02: until then only a path into Spikes/ was judged) brings in a
                     file (#include, #import, #include_next, #embed, or the assembler's .include and .incbin, in an
                     assembly file or in inline assembly) by a name that is absolute, that climbs out of the directory it
                     is found in with .. (unless, quoted, it resolves beside the including file to a file git tracks
                     under the product roots), or that passes through a build or package-checkout directory; or by a
                     computed include, whose file macros decide
  flag               a shipping target passes a compiler or linker flag (SwiftPM unsafeFlags; any build setting whose name
                     contains FLAGS; XcodeGen per-file compilerFlags; with -Xcc, -Xlinker, -Xfrontend, -Xclang and -Wl,
                     unwrapped) that is not one product targets may pass: FLAGS_ALLOWED, FLAG_PATTERNS_ALLOWED and
                     FLAGS_WITH_NAME, the search-path, header-file, module-map-file, library, framework, module-alias and
                     definition flags (each judged as described here), and nothing else, an input file among the flags
                     included (review R3-01: -import-module, -imacros, -vfsoverlay, -fplugin= and the like all fail;
                     review R4-04: only the Swift compiler's -Werror and -Wwarning take a diagnostic group after them, so
                     in a C or linker flag setting the word after them is an input file and fails)
  manifest-input     a product manifest's values depend on something the check does not read, so the value the build
                     uses is not the one the check judges (review R4-01): a key or value of a product project.yml (test
                     targets included) holds ${, which XcodeGen replaces from the environment or a template's attributes
                     when it generates the project (a YAML escape such as \x24{ too), or starts with ~, which XcodeGen
                     expands to a home directory in the paths it resolves; or a product Package.swift imports a module
                     other than PackageDescription and CompilerPluginSupport, or names Context, CommandLine, readLine,
                     _silgen_name, _cdecl, _extern, random numbers or clocks, or holds an #if (MANIFEST_INPUTS: every build
                     evaluates the manifest again, in its own environment). Read in the raw text of a Package.swift, so a
                     comment that names one is reported too
  transitive-direct  a product manifest depends directly on a package the inventory admits only as transitive, or
                     product code (not tests) reaches one of its modules: the word `import` followed, after white space,
                     comments and an optional import kind, by the module's name, anywhere in a Swift or C-family file
                     (which covers every Swift import declaration, @import, `#pragma clang module import`, _Pragma and
                     C++ import: for example `internal import Zip`); in a C-family file, any mention of one of its public
                     headers (any #include or #import of it, computed includes and __has_include included) or of a
                     framework-style path into it (`<Zip/...>`), and its Swift module's generated header (`Zip-Swift.h`);
                     a module map naming one of its public headers; a module alias for one of its modules, given by a
                     -module-alias flag, the SWIFT_MODULE_ALIASES setting or a SwiftPM `moduleAliases:` entry on a
                     product dependency; a module a flag imports into every file (-import-module); or, for a shipping
                     target, any value of the manifest or of a build-settings file it uses (settings, flags, definitions,
                     scripts) that names one of its public headers, and a preprocessor definition that names one of its
                     modules (review R3-01). The import and header checks read the raw text (C-family files after line
                     splicing, with and without trigraphs), not a lexer's view of it, so no comment, string, regex
                     literal or raw identifier can hide an import; the cost is that a comment, string literal or manifest
                     value that names such an import or header is reported too
  test-layout        a product target that is not a test target takes its sources from a directory that is named Tests or
                     ends in Tests, or builds a file that sits in such a directory at any depth (rename the directory or
                     move the file to a test target; test code is decided by target membership, not by names)
  test-in-product    a shipping target uses a test-only package (a build tool plugin from one included)
  platform           a product target that is not a test target can build, for a platform the inventory does not allow
                     for it, a package it uses (for example swift-nio, macOS only, in an iOS target)
  binary             third-party binary code can reach a product target: a binary target, or a framework, bundle or
                     Carthage dependency, or a committed Mach-O file or static library under Apps/ or Packages/, is not
                     in the inventory's `binaries` (or an entry there is stale or its digest differs); a library or
                     framework a product target links by name (SwiftPM linker settings, -l and -framework flags, an
                     XcodeGen `sdk:` dependency, a module map's `link`) is provided by no iOS or macOS SDK and is not
                     listed there (kind `linked`); or a library or framework search path, or a library or framework
                     named directly in linker flags, resolves outside Apps/ and Packages/ (build-product, SDK and
                     toolchain variables excepted)
  xcode-project      a committed Xcode project or workspace, anywhere: ADR-0002 commits only project.yml, and the check
                     does not read the package references, requirements, build settings or lock inside one (review R3-04)
  lock-registry      a committed Package.resolved is not registered, or a registration, lock list, direct-use list or
                     target-use list (used_by_targets) in the inventory is stale
  unlocked           a project or package whose graph reaches a remote package has no committed lock and no reasoned
                     exemption, an exemption names a manifest outside Spikes/ (exemptions are for Spikes/ only), or an
                     exemption is stale
  license-text       a license text copy under Docs/Licenses/texts differs from the digest read at the pinned revision; a
                     text the inventory names for a bundled component is not committed; or a package's license data were
                     read at another revision than the one the inventory pins
  vendored-asset     a font or license file under Apps/ or Packages/ is not in the inventory, or its digest changed
  python-tools       Scripts/tools/requirements.txt differs from the inventory
  ci-actions         a workflow action is not in the inventory (or an inventory entry is unused)
  toolchain          the Xcode pin in Scripts/lib/env.sh differs from the inventory, or another record of the pin does
                     (ADR-0001: they change together): the Xcode guard of .github/workflows/ci.yml (every "Build
                     version <build>", "/Applications/Xcode_<version>.app" and "Xcode <version> (<build>)" in a line
                     that is not a comment, and at least one "Build version" there), CLAUDE.md's toolchain line
                     ("- Xcode <version> (<build>)") or ADR-0001's toolchain table ("| Xcode | <version>, build <build>");
                     with --toolchain, also the installed Xcode build, Swift version or XcodeGen version, each compared
                     whole on the line that states it (so a build that only extends the pin, 27A9275a for 27A9275,
                     fails too: review TC-02), or the tools virtualenv: it must hold
                     exactly the pinned packages at their versions, those the inventory records as unpinned (pip) at any
                     version, and nothing else (and the check must run in it); or the SDKs cannot be listed to judge
                     what a product links by name
  docs               Docs/Licenses/third-party-inventory.md or ADR-0014 lacks a package's name and pinned version, or
                     Docs/Licenses/acknowledgements-draft.md differs from what the inventory and its texts generate
  inventory          the inventory itself is malformed, or a manifest cannot be read
Every failure is printed as `FAIL <category> <path>: <message>`; the exit status is 1 if there is any.

It warns, without failing, when (printed as `WARN <category> <path>: <message>`):
  toolchain          with --toolchain, a distribution the inventory records as unpinned (pip) is installed below the
                     minimum the inventory records for it, the first release outside every advisory found for it.
                     Nothing in the repository pins pip: Scripts/tools/bootstrap.sh creates the virtualenv with
                     `python3 -m venv`, which installs the pip that Python bundles (26.1.2 with Python 3.14.6), so a
                     failure here would fail every freshly bootstrapped virtualenv whose Python bundles an older pip,
                     on something no tracked file controls (review R2-01). Pinning pip in Scripts/tools/requirements.txt
                     moves it to the exact check above (requested in ADR-0014). A warning leaves the exit status at 0,
                     and Scripts/ci.sh shows a drop-in's log only when it fails, so in a passing `Scripts/ci.sh` run
                     this warning is in .build/ci-logs/12-dependency-lock.log and nowhere on the console (review R3-05;
                     a Scripts/ci.sh change that prints a passing drop-in's WARN lines is requested in ADR-0014).
The self-test proves each failure branch (each `self.fail(` call below) is reached by a mutation written for it, and
each warning branch (each `self.warn(` call) by an allowed change written for it, and fails if one is not.

What the check cannot see: code reached by symbol rather than by import or include (an `extern` prototype, `dlsym` or
`@_silgen_name` in product code calling a function that a transitive package links in, such as Minizip's); a header or
module name that the C preprocessor builds by token pasting or stringizing, so that it never appears whole in the text
(a computed #include or _Pragma whose argument a macro assembles from pieces); declarations reached through a module
that re-exports them (`@_exported import`), which is use through the parent package: at the pinned revisions swift-nio's
NIOFS and _NIOFileSystem re-export five SystemPackage types (FilePath, FileDescriptor, Errno, FilePermissions,
CInterop), and no product package re-exports any other transitive-only module; paths that build scripts and scheme
actions compute (a script that names Spikes/ or a transitive-only package's public header is caught; other paths in
scripts are not judged); build settings outside the lists above (drawn from Xcode 27.0's specifications), which are
read only for a transitive-only package's header names and for paths into Spikes/; what the compiler and linker take
from the environment rather than from a tracked file (CPATH, C_INCLUDE_PATH, LIBRARY_PATH and the like); the
requirements of packages behind an exempted (unlocked) Spikes project; a Package.swift's use of the order in which a
Set or Dictionary is iterated, which Swift seeds afresh in each process, so that a manifest that used it would vary
from one evaluation to the next, in CI as in a build, rather than hide a value from CI alone (review R4-01's
reasoning: random numbers and clocks, the other sources of such variation, are reported); and anything a build fetches
or runs that no manifest, lock or tracked file names. A C-family include of a plain name (no .., no absolute path, no
build or checkout directory) that is not beside the including file is found in the search directories: the target's
own, which the setting and flag rules judge, and its dependencies' public include directories, which for the
transitive-only packages hold, at the pinned revisions, only the public headers the inventory lists, judged by name,
and module maps (Docs/Stage0/evidence/M0-ExitPrep/zipguard/reproductions.log).
"""
import argparse
import ast
import bisect
import copy
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:  # pragma: no cover - environment problem, reported plainly
    sys.exit('check-dependency-lock.py needs PyYAML: run it with sylvia_python (Scripts/lib/env.sh)')

INVENTORY = 'Docs/Licenses/inventory.json'
HUMAN = 'Docs/Licenses/third-party-inventory.md'
ADR = 'Docs/ADRs/0014-dependency-lock-and-license-inventory.md'
REQUIREMENTS = 'Scripts/tools/requirements.txt'
ENV_SH = 'Scripts/lib/env.sh'
# The other records of the Xcode pin, which change together with the inventory's and env.sh's (ADR-0001; review TC-08).
WORKFLOW = '.github/workflows/ci.yml'
CLAUDE_MD = 'CLAUDE.md'
ADR_0001 = 'Docs/ADRs/0001-platform-baseline-and-toolchain.md'
ROLES =('product', 'product-transitive', 'test', 'spike')
PLATFORMS = ('iOS', 'macOS')
BINARY_KINDS = ('binaryTarget', 'framework', 'bundle', 'carthage', 'file', 'linked')
SKIP_DIRS = {'.git', '.build', 'DerivedData', '.swiftpm', 'node_modules'}
FONT_EXT = ('.ttf', '.otf', '.woff', '.woff2', '.ttc', '.dfont')
# A license or notice file: LICENSE, LICENSE.txt, LICENSE-MIT, OFL.txt, NOTICE.md, COPYING ... but not source code
# that happens to be called Notice.swift or License.swift.
LICENSE_STEM = re.compile(r'^(licen[cs]e|copying|notice|ofl|copyright)([_-][A-Za-z0-9.-]+)?$', re.I)
LICENSE_EXT = ('', '.txt', '.md', '.markdown', '.rtf', '.html', '.htm', '.terms', '.apache', '.mit', '.bsd')
# project.yml requirement keys: XcodeGen 2.46.0 writes both of the first two as `kind = exactVersion`, every other key
# as a range, branch or revision (Docs/Stage0/evidence/M0-dependencies/xcodegen-requirements.log).
XCODEGEN_EXACT = ('exactVersion', 'version')
XCODEGEN_OTHER = ('from', 'majorVersion', 'minorVersion', 'branch', 'revision', 'minVersion', 'maxVersion')
TEST_TYPES = ('bundle.unit-test', 'bundle.ui-testing')
VERSION = re.compile(r'^\d+(\.\d+){1,3}([-+][0-9A-Za-z.-]+)?$')
SHA = re.compile(r'^[0-9a-f]{64}$')
REV = re.compile(r'^[0-9a-f]{40}$')
C_EXTENSIONS = ('.c', '.h', '.m', '.mm', '.cc', '.cp', '.cpp', '.cxx', '.c++', '.hh', '.hpp', '.hxx', '.h++', '.inc',
                '.ipp', '.inl', '.tcc', '.pch',
                # Other sources that Xcode (or SwiftPM, for assembly) runs through the C preprocessor or the assembler,
                # whose #include, .include and .incbin can bring in a file as C does (review R4-02): assembly, Metal,
                # OpenCL, lex and yacc (C code with a grammar around it), MIG and IIG.
                '.s', '.sx', '.asm', '.metal', '.cl', '.l', '.lm', '.lmm', '.lpp', '.lxx', '.y', '.ym', '.ymm', '.ypp',
                '.yxx', '.defs', '.mig', '.iig')
C_HEADER_EXTENSIONS = ('.h', '.hh', '.hpp', '.hxx', '.h++', '.inc', '.ipp', '.inl', '.tcc', '.pch')
# First bytes of a Mach-O file (thin, either byte order) or a universal binary, and of a static library (ar archive).
MACHO_MAGIC = (b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xcf\xfa\xed\xfe',
               b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
AR_MAGIC = b'!<arch>\n'
BINARY_DIR_EXT = ('.framework', '.xcframework')
BINARY_FILE_EXT = ('.a', '.dylib', '.so', '.o', '.tbd')
# Xcode's names for the project directory, as a build setting or a script variable sees them.
PROJECT_DIR_VARS = re.compile(r'\$(?:\((?:SRCROOT|PROJECT_DIR|SOURCE_ROOT)\)|\{(?:SRCROOT|PROJECT_DIR|SOURCE_ROOT)\}'
                              r'|(?:SRCROOT|PROJECT_DIR|SOURCE_ROOT)(?![A-Za-z0-9_]))')
# Build settings, by what a value they hold brings into the build (keys without a [condition] suffix). The lists follow
# the settings that Xcode 27.0's specifications pass to the compiler and linker as paths, flags, module aliases,
# definitions or tools (Docs/Stage0/evidence/M0-dependencies/xcode-settings.log, commands/xcode-settings.py).
DIR_SETTINGS = ('HEADER_SEARCH_PATHS', 'USER_HEADER_SEARCH_PATHS', 'SYSTEM_HEADER_SEARCH_PATHS', 'SWIFT_INCLUDE_PATHS',
                'SWIFT_SYSTEM_INCLUDE_PATHS', 'SWIFT_OVERLOAD_PREBUILT_MODULE_CACHE_PATH')
LIBPATH_SETTINGS = ('LIBRARY_SEARCH_PATHS', 'FRAMEWORK_SEARCH_PATHS', 'SYSTEM_FRAMEWORK_SEARCH_PATHS',
                    'CLANG_SYSTEM_FRAMEWORK_SEARCH_PATHS', 'SWIFTC_SYSTEM_FRAMEWORK_SEARCH_PATHS',
                    'PRODUCT_TYPE_LIBRARY_SEARCH_PATHS', 'PRODUCT_TYPE_FRAMEWORK_SEARCH_PATHS')
HEADER_FILE_SETTINGS = ('GCC_PREFIX_HEADER', 'PREFIX_HEADER', 'SWIFT_OBJC_BRIDGING_HEADER')
MODULEMAP_FILE_SETTINGS = ('MODULEMAP_FILE', 'MODULEMAP_PRIVATE_FILE')
BINARY_SETTINGS = ('REEXPORTED_LIBRARY_PATHS', 'BUNDLE_LOADER')
LINKED_SETTINGS = {'REEXPORTED_LIBRARY_NAMES': 'library', 'REEXPORTED_FRAMEWORK_NAMES': 'framework'}
ALIAS_SETTINGS = ('SWIFT_MODULE_ALIASES',)
DEFINE_SETTINGS = ('GCC_PREPROCESSOR_DEFINITIONS', 'GCC_PREPROCESSOR_DEFINITIONS_NOT_USED_IN_PRECOMPS',
                   'GCC_PRODUCT_TYPE_PREPROCESSOR_DEFINITIONS', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS')
# Settings that replace a compiler, linker, SDK or toolchain input, take the compiler's or linker's inputs or flags from a
# file or a header map, remap paths, or set the dynamic loader's environment: a product target may not set them
# (SDKROOT only to an SDK's name). Every setting whose name contains FLAGS (OTHER_CFLAGS, OTHER_SWIFT_FLAGS,
# OTHER_LDFLAGS, WARNING_CFLAGS, SWIFT_TOOLCHAIN_FLAGS ...) is read as flags.
TOOL_SETTINGS = re.compile(r'^(?:CC|CPLUSPLUS|LD|LDPLUSPLUS|LIBTOOL|TOOLCHAINS|SYSROOT|COMPOSITE_SDK_DIRS|CCHROOT|'
                           r'SWIFT_RESOURCE_DIR|CLANG_RESOURCE_DIR(?:_CLANG|_SWIFTC)?|SWIFT_LIBRARY_PATH|'
                           r'SWIFT_RESPONSE_FILE_PATH|(?:CLANG_|SWIFTC_)?ALTERNATE_LINKER(?:_PATH)?|CPP_HEADERMAP_[A-Z0-9_]*|'
                           r'[A-Z0-9_]*_EXEC|[A-Z0-9_]*_(?:SYSROOT|SDKROOT)_LINKER_INPUT|[A-Z0-9_]*INPUT_FILE_LIST_PATH__|'
                           r'FILE_LIST|LD_ENVIRONMENT|[A-Z0-9_]*_PREFIX_MAPPINGS)$')
SDK_NAME = re.compile(r'^(?:auto|[a-z]+(?:[0-9]+(?:\.[0-9]+)*)?)$')
# A setting value that starts with one of these Xcode variables names build products, the SDK or the toolchain; what
# follows it may not leave that directory (no `..`) or name a package checkout. Inside a product target, any other
# variable cannot be evaluated by the check and fails (review R3-01); `$(inherited)` counts only as a word of its own.
BUILD_VAR_NAMES = ('BUILT_PRODUCTS_DIR', 'TARGET_BUILD_DIR', 'CONFIGURATION_BUILD_DIR', 'BUILD_DIR', 'BUILD_ROOT',
                   'OBJROOT', 'SYMROOT', 'DERIVED_FILE_DIR', 'DERIVED_FILES_DIR', 'PROJECT_TEMP_DIR', 'TARGET_TEMP_DIR',
                   'SDKROOT', 'SDK_DIR', 'PLATFORM_DIR', 'PLATFORM_DEVELOPER_FRAMEWORKS_DIR',
                   'PLATFORM_DEVELOPER_LIBRARY_DIR', 'DEVELOPER_DIR', 'DEVELOPER_FRAMEWORKS_DIR', 'TOOLCHAIN_DIR',
                   'DT_TOOLCHAIN_DIR')
BUILD_VARS = re.compile(r'^\$[({](?:' + '|'.join(BUILD_VAR_NAMES) + r')[)}]')
# The variables the check evaluates itself: a path that starts with a build-product, SDK or toolchain variable is
# trusted to stay in that directory, and the project-directory variables are replaced by the manifest's directory. A
# product manifest or build-settings file that assigns one of them would make such a path point anywhere, so it may
# not (review R4-03); SDKROOT is the exception, which a product target may set to an SDK's name (TOOL_SETTINGS judges
# it), and which then still names an SDK.
TRUSTED_VARS = frozenset(BUILD_VAR_NAMES + ('SRCROOT', 'PROJECT_DIR', 'SOURCE_ROOT')) - {'SDKROOT'}
INHERITED = ('$(inherited)', '${inherited}')
VARIABLE = re.compile(r'\$(?:[({]([A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*))')
# Directories that hold build products and package checkouts (SwiftPM's .build, Xcode's DerivedData and SourcePackages).
CHECKOUT_DIRS = {'.build', 'deriveddata', 'sourcepackages', 'checkouts', '.swiftpm'}
# Compiler and linker flags. After -Xcc, -Xlinker, -Xfrontend, -Xclang and -Wl, are unwrapped, a product target may
# pass only the flags below, each with a rule for its argument; anything else, an input file among the flags included,
# fails, because what it brings into the build cannot be judged (review R3-01: -import-module, -include, and a
# bridging header or search path into package checkouts reached Zip and Minizip with no import in any source file).
FLAG_WRAPPERS = ('-Xcc', '-Xlinker', '-Xfrontend', '-Xclang')
DIR_FLAGS = ('-I', '-isystem', '-iquote', '-idirafter', '-Isystem')
LIBPATH_FLAGS = ('-L', '-F', '-iframework', '-Fsystem')
HEADER_FILE_FLAGS = ('-include', '-import-objc-header')
IMPORT_FLAGS = ('-import-module', '-testable-import-module')
FRAMEWORK_FLAGS = ('-framework', '-weak_framework', '-needed_framework', '-reexport_framework', '-lazy_framework',
                   '-upward_framework')
LIBFILE_FLAGS = ('-force_load', '-load_hidden', '-reexport_library', '-lazy_library', '-weak_library', '-needed_library',
                 '-upward_library', '-filelist')
LIBNAME_PREFIXES = ('-weak-l', '-reexport-l', '-lazy-l', '-needed-l', '-upward-l', '-hidden-l', '-l')
FLAGS_ALLOWED = frozenset('''
    -ObjC -all_load -dead_strip -dead_strip_dylibs -no_warn_duplicate_libraries -application_extension
    -w -pedantic -warnings-as-errors -no-warnings-as-errors -suppress-warnings
    -g -gnone -gline-tables-only -Onone -Osize -Ounchecked
    -fobjc-arc -fno-objc-arc -fobjc-weak -fmodules -fcxx-modules -fno-exceptions -fno-rtti -fapplication-extension
    -application-extension -enable-actor-data-race-checks -disable-actor-data-race-checks -warn-concurrency
    -strict-memory-safety -require-explicit-sendable -enable-bare-slash-regex'''.split())
FLAG_PATTERNS_ALLOWED = re.compile(
    r'^(?:-W(?:no-)?[a-z][a-z0-9-]*(?:=[a-z0-9-]+)?|-std=[A-Za-z0-9+]+|-O[0-3sz]?|-U[A-Za-z_][A-Za-z0-9_]*|'
    r'-strict-concurrency=(?:minimal|targeted|complete)|-enforce-exclusivity=(?:checked|unchecked)|'
    r'-warn-long-(?:function-bodies|expression-type-checking)=[0-9]+|-fvisibility=(?:hidden|default))$')
FLAGS_WITH_NAME = ('-enable-upcoming-feature', '-enable-experimental-feature', '-disable-upcoming-feature',
                   '-swift-version', '-language-mode', '-default-isolation', '-U')
NAME_ARG = re.compile(r'^[A-Za-z0-9_.]+$')
# Swift's -Werror and -Wwarning take an optional diagnostic group (Swift 6.1 and later); Clang's -Werror takes none, so
# in a C, C++ or linker flag setting the word after it is an input file, not a group (review R4-04).
DIAG_FLAGS = ('-Werror', '-Wwarning')
DIAG_GROUP = re.compile(r'^[A-Z][A-Za-z0-9]*$')
BINARY_PATH = re.compile(r'(\.(a|dylib|tbd|so|o)$|\.x?c?framework(/|$))')
MODULEMAP_PATHS = re.compile(r'\b(?:umbrella\s+header|private\s+header|textual\s+header|exclude\s+header|header|umbrella'
                             r'|extern\s+module\s+[A-Za-z_][\w.]*)\s*"([^"]+)"')
MODULEMAP_LINKS = re.compile(r'\blink\s+(framework\s+)?"([^"]+)"')
EXTERN_MODULE = re.compile(r'\bextern\s+module\s+[A-Za-z_][\w.]*\s*"([^"]+)"')
# Review R4-01: when it generates a project, XcodeGen 2.46.0 replaces `${NAME}` in every key and value of a project.yml:
# from the environment (unless `--no-env`, which sylvia_generate does not pass; Scripts/lib/env.sh exports SYLVIA_ROOT),
# and in a target template from the target's name and platform and the template's attributes (`${target_name}`,
# `${platform}`, templateAttributes; --no-env or not). A YAML escape (`"\x24{NAME}"`) is the same text once parsed and
# is replaced too. And it does not take a path that starts with ~ (a local package's path, a source path) from the
# project's directory: it expands the ~ to a home directory. The value the build uses is then not the one this check
# reads, so a product project.yml may hold neither (Docs/Stage0/evidence/M0-ExitPrep/zipguard/reproductions.log,
# part 2a).
XCODEGEN_EXPANSION = re.compile(r'\$\{')
# A product Package.swift is evaluated again by every build, in that build's environment. It may read nothing but its
# own text: it may import only PackageDescription and CompilerPluginSupport, and may not name what reads the
# environment, the package's directory or git (Context), the manifest process's arguments, in which SwiftPM passes that
# context (CommandLine), standard input (readLine), a C function bound by name without an import (_silgen_name, _cdecl,
# _extern: getenv, fopen ...), random numbers or clocks, or hold a compilation condition (#if), which the compiler
# evaluates for the host and flags of each evaluation (review R4-01's reasoning, for SwiftPM). Read in the raw text, so
# a comment that names one counts too.
MANIFEST_IMPORTS_ALLOWED = ('PackageDescription', 'CompilerPluginSupport')
MANIFEST_INPUTS = re.compile(r'(?<![A-Za-z0-9_])(?:Context|CommandLine|readLine|_silgen_name|_cdecl|_extern|'
                             r'(?:Continuous|Suspending)?Clock)(?![A-Za-z0-9_])|[Rr]andom|[Ss]huffle|'
                             r'#[ \t]*(?:if|elseif)(?![A-Za-z0-9_])')
# Review R4-02: C-family include directives, judged by where their file can be, not only against Spikes/: a quoted
# name may resolve beside the including file, and any name is looked up in each search directory, where `..` climbs out
# of it (from a package's public include directory into its sources, for one). #embed (C23) brings a file's bytes in
# the same way. A directive whose operand is neither "..." nor <...> is a computed include: its file is decided by
# macros, which the check does not evaluate. The assembler's .include and .incbin are looked up in the working and
# search directories, never beside the file; they are read anywhere in the text, so inline assembly in a C string
# (`asm(".incbin \"file\"")`) counts too.
C_INCLUDE_DIRECTIVE = re.compile(r'^[ \t]*(?:#|%:)[ \t]*(include_next|include|import|embed)(?![A-Za-z0-9_])[ \t]*(.*)$',
                                 re.M)
ASM_INCLUDE_DIRECTIVE = re.compile(r'\.(?:include|incbin)[ \t]+\\?"([^"\n\\]*)\\?"')


def norm_url(url):
    """github.com/owner/repo, lower case, without scheme, user, .git or trailing slash."""
    u = url.strip().lower()
    u = re.sub(r'^[a-z+]+://', '', u)
    u = re.sub(r'^[^@/]+@([^:/]+):', r'\1/', u)
    u = re.sub(r'^[^@/]+@', '', u)
    u = u.rstrip('/')
    return u[:-4] if u.endswith('.git') else u


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def tree_sha256(path):
    """SHA-256 of a file, or of a directory as the sorted list of its files' relative paths and SHA-256s."""
    if os.path.isfile(path):
        return sha256_file(path)
    lines = []
    for dp, dns, fns in os.walk(path):
        dns.sort()
        for fn in sorted(fns):
            full = os.path.join(dp, fn)
            if os.path.isfile(full):
                lines.append(f'{os.path.relpath(full, path)}\0{sha256_file(full)}\n')
    return hashlib.sha256(''.join(sorted(lines)).encode('utf-8')).hexdigest()


def norm_py(name):
    return re.sub(r'[-_.]+', '-', name).lower()


def version_key(v):
    """A sortable key for a PEP 440 version without an epoch or local part (26.2 == 26.2.0; 26.2.0rc1 and 26.2.0.dev1
    come before 26.2.0, 26.2.0.post1 after it), or None when v is not one."""
    m = re.match(r'^(\d+(?:\.\d+)*)(?:[-_.]?(a|b|rc)[-_.]?(\d+))?(?:[-_.]?post[-_.]?(\d+))?(?:[-_.]?dev[-_.]?(\d+))?$',
                 str(v).strip(), re.I)
    if not m:
        return None
    release = [int(x) for x in m.group(1).split('.')]
    while len(release) > 1 and release[-1] == 0:
        release.pop()
    pre = (-1, ('a', 'b', 'rc').index(m.group(2).lower()), int(m.group(3))) if m.group(2) else (0, 0, 0)
    post = int(m.group(4)) if m.group(4) else -1
    dev = (0, int(m.group(5))) if m.group(5) else (1, 0)
    return (tuple(release), pre, post, dev)


def is_license_name(name):
    stem, ext = os.path.splitext(name)
    return bool(LICENSE_STEM.match(stem)) and ext.lower() in LICENSE_EXT


def in_test_named_dir(rel):
    """Whether a path has a directory named Tests or ending in Tests. Only the test-layout rule uses the name: a file is
    test code because test targets include it (Checker.is_test_file), never because of what its directory is called."""
    return any(x == 'Tests' or x.endswith('Tests') for x in rel.split('/')[:-1])


def as_list(value):
    if value is None:
        return []
    return list(value) if isinstance(value, (list, tuple)) else [value]


def strings_in(value, skip=()):
    """Every string value in a YAML or JSON structure (keys excluded), skipping the top-level keys named in skip."""
    out, stack = [], [value]
    while stack:
        v = stack.pop()
        if isinstance(v, str):
            out.append(v)
        elif isinstance(v, dict):
            stack.extend(x for k, x in v.items() if k not in skip)
            skip = ()  # only at the top level
        elif isinstance(v, list):
            stack.extend(v)
    return out


def yaml_texts(value, where=''):
    """[(where, text)] for every key and every string value in a YAML structure, with where naming its place
    (targets.App.settings.base, or 'the key targets.App' for a key)."""
    out = []
    if isinstance(value, dict):
        for k, v in value.items():
            here = f'{where}.{k}' if where else str(k)
            if isinstance(k, str):
                out.append((f'the key {here}', k))
            out += yaml_texts(v, here)
    elif isinstance(value, list):
        for i, v in enumerate(value):
            out += yaml_texts(v, f'{where}[{i}]')
    elif isinstance(value, str):
        out.append((where, value))
    return out


def run_tool(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout + ''


def venv_distributions():
    """{normalized name: version} of the running interpreter's virtualenv, or None when it is not a virtualenv."""
    if sys.prefix == getattr(sys, 'base_prefix', sys.prefix):
        return None
    from importlib import metadata
    return {norm_py(d.metadata['Name']): d.version for d in metadata.distributions()}


def sdk_names():
    """{'library': names, 'framework': names} that the iOS, iOS Simulator and macOS SDKs provide (usr/lib/lib<name>.tbd
    and System/Library/Frameworks/<name>.framework), or None when an SDK cannot be found."""
    names = {'library': set(), 'framework': set()}
    for sdk in ('iphoneos', 'iphonesimulator', 'macosx'):
        r = subprocess.run(['xcrun', '--sdk', sdk, '--show-sdk-path'], capture_output=True, text=True)
        path = r.stdout.strip()
        if r.returncode != 0 or not os.path.isdir(path):
            return None
        for sub in ('usr/lib', 'usr/lib/swift'):
            for fn in os.listdir(os.path.join(path, sub)) if os.path.isdir(os.path.join(path, sub)) else []:
                m = re.match(r'^lib(.+?)(\.[0-9][0-9.]*)?\.(tbd|dylib|a)$', fn)
                if m:
                    names['library'].add(m.group(1))
        for sub in ('System/Library/Frameworks', 'System/Library/SubFrameworks'):
            for fn in os.listdir(os.path.join(path, sub)) if os.path.isdir(os.path.join(path, sub)) else []:
                if fn.endswith('.framework'):
                    names['framework'].add(fn[:-len('.framework')])
    return names


def setting_items(pairs, text=False):
    """[(kind, value)] for the build settings among (key, value) pairs that bring something into the build: the kinds of
    flag_items, ('tool', 'KEY = value') for a setting that replaces a compiler, linker, SDK or toolchain input, and
    ('redefine', 'KEY = value') for one that assigns a variable the check evaluates itself (TRUSTED_VARS, review
    R4-03). With text=True (a build-settings file, whose values are not manifest strings), every other setting's value
    as ('text', value), which judge() reads for the names of transitive-only packages' public headers."""
    out = []
    for key, value in pairs:
        k = str(key).split('[', 1)[0].strip()
        words = [w for w in split_setting(value) if w not in INHERITED]
        if k in TRUSTED_VARS:
            out.append(('redefine', f"{k} = {' '.join(words)}"))  # review R4-03
        elif k in DIR_SETTINGS:
            out += [('include', w) for w in words]
        elif k in LIBPATH_SETTINGS:
            out += [('libpath', w) for w in words]
        elif k in HEADER_FILE_SETTINGS:
            out += [('header-file', w) for w in words]
        elif k in MODULEMAP_FILE_SETTINGS:
            out += [('modulemap-file', w) for w in words]
        elif k in BINARY_SETTINGS:
            out += [('binary', w) for w in words]
        elif k in LINKED_SETTINGS:
            out += [(LINKED_SETTINGS[k], w) for w in words]
        elif k in ALIAS_SETTINGS:
            out += [('alias', w) for w in words]
        elif k in DEFINE_SETTINGS:
            out += [('define', w) for w in words]
        elif 'FLAGS' in k:
            out += flag_items(words, swift='SWIFT' in k)
        elif TOOL_SETTINGS.match(k) or (k == 'SDKROOT' and not all(SDK_NAME.match(w) for w in words)):
            out.append(('tool', f"{k} = {' '.join(words)}"))
        elif text:
            out += [('text', str(v)) for v in as_list(value)]
    return out


def split_setting(value):
    """A build-setting value (a string or a list of strings) as words, quotes respected."""
    words = []
    for v in as_list(value):
        v = str(v)
        try:
            words += shlex.split(v, posix=True)
        except ValueError:  # unbalanced quotes: fall back to white space
            words += v.split()
    return words


def flag_items(tokens, swift=False):
    """[(kind, value)] for compiler and linker flags, once the -Xcc, -Xlinker, -Xfrontend, -Xclang and -Wl, wrappers are
    unwrapped: ('include', path) for a header or module search directory; ('libpath', path) for a library or framework
    search directory; ('header-file', path) for a header included into every file (-include, -import-objc-header);
    ('modulemap-file', path); ('binary', path) for a library, framework or object file named directly; ('library',
    name) and ('framework', name) for what is linked by name; ('alias', 'A=B') for -module-alias; ('import', module)
    for a module imported into every file (-import-module); ('define', text) for -D; and ('flag', token) for every
    token that is none of these and not one of the flags a product target may pass (FLAGS_ALLOWED,
    FLAG_PATTERNS_ALLOWED, FLAGS_WITH_NAME), an input file among the flags included. `swift` says that the flags are
    the Swift compiler's (OTHER_SWIFT_FLAGS, a SwiftPM swiftSettings unsafeFlags, a Swift file's compilerFlags): only
    there does -Werror or -Wwarning take the diagnostic group after it; for Clang and the linker that word is an input
    file (review R4-04)."""
    flat, i = [], 0
    while i < len(tokens):
        t = tokens[i]
        if t in FLAG_WRAPPERS and i + 1 < len(tokens):
            flat.append(tokens[i + 1])
            i += 2
        elif t.startswith('-Wl,'):
            flat += [x for x in t[4:].split(',') if x]
            i += 1
        else:
            flat.append(t)
            i += 1
    items, i = [], 0
    while i < len(flat):
        t, arg = flat[i], flat[i + 1] if i + 1 < len(flat) else ''
        i += 1
        if t in INHERITED:
            continue
        if t in DIR_FLAGS:
            items.append(('include', arg))
            i += 1
        elif t.startswith(('-isystem', '-iquote', '-idirafter')):
            items.append(('include', re.sub(r'^-(isystem|iquote|idirafter)', '', t)))
        elif t.startswith('-I') and len(t) > 2:
            items.append(('include', t[2:]))
        elif t in HEADER_FILE_FLAGS:
            items.append(('header-file', arg))
            i += 1
        elif t.startswith('-fmodule-map-file='):
            items.append(('modulemap-file', t.split('=', 1)[1]))
        elif t in LIBPATH_FLAGS:
            items.append(('libpath', arg))
            i += 1
        elif t.startswith(('-L', '-F')) and len(t) > 2:
            items.append(('libpath', t[2:]))
        elif t in FRAMEWORK_FLAGS:
            items.append(('framework', arg))
            i += 1
        elif t in LIBFILE_FLAGS:
            items.append(('binary', arg))
            i += 1
        elif t == '-module-alias':
            items.append(('alias', arg))
            i += 1
        elif t.startswith('-module-alias='):
            items.append(('alias', t.split('=', 1)[1]))
        elif t in IMPORT_FLAGS:
            items += [('import', arg), ('flag', t)]
            i += 1
        elif t == '-D':
            items.append(('define', arg))
            i += 1
        elif t.startswith('-D') and len(t) > 2:
            items.append(('define', t[2:]))
        elif t in FLAGS_WITH_NAME and NAME_ARG.match(arg):
            i += 1
        elif swift and t in DIAG_FLAGS and DIAG_GROUP.match(arg):
            i += 1
        elif t in FLAGS_ALLOWED or FLAG_PATTERNS_ALLOWED.match(t):
            pass
        elif t.startswith(LIBNAME_PREFIXES) and not t.startswith(('-lazy_', '-lto')) and \
                len(t) > len(next(p for p in LIBNAME_PREFIXES if t.startswith(p))):
            items.append(('library', t[len(next(p for p in LIBNAME_PREFIXES if t.startswith(p))):]))
        elif not t.startswith('-') and BINARY_PATH.search(t):
            items.append(('binary', t))
        else:
            items.append(('flag', t))
    return items


# ----- Swift and C-family source scanning ---------------------------------------------------------------------------
# The checks for transitive-only modules and headers read the raw text of a file, not a lexer's view of it. A scanner
# that skips comments and literals is fooled by any construct it lexes differently from the compiler, and the import it
# then misses still compiles (review R2-02: a Swift regex literal holding `/*` or `"`; also raw identifiers such as
# `a /* b`, C++ raw strings, a line splice that ends a comment, digraphs and trigraphs). An import declaration's tokens
# can be separated only by white space and comments, so reading every `import` word in the raw text finds every import;
# the cost is a report when a comment or string literal names such an import or header, which rewording fixes.
SWIFT_IMPORT_KINDS = {'typealias', 'struct', 'class', 'enum', 'protocol', 'let', 'var', 'func'}
IMPORT_WORD = re.compile(r'(?<![A-Za-z0-9_$])import(?![A-Za-z0-9_$])')
NAME_AT = re.compile(r'`([^`\n]*)`|([A-Za-z_][A-Za-z0-9_]*)')
# C translation phase 2: a backslash, optional horizontal white space (clang accepts it, with a warning), a line break.
SPLICE = re.compile(r'\\[ \t\v\f]*\r?\n')
TRIGRAPHS = {'=': '#', '/': '\\', "'": '^', '(': '[', ')': ']', '!': '|', '<': '{', '>': '}', '-': '~'}
TRIGRAPH = re.compile(r"\?\?([=/'()!<>-])")
# A header file name anywhere in C-family text (its last path component), and a framework-style path into a module.
HEADER_WORD = re.compile(r'[A-Za-z0-9_.+-]*[A-Za-z0-9_+-]\.(?:h|hh|hpp|hxx|inc|ipp|inl|tcc)(?![A-Za-z0-9_])', re.I)
FRAMEWORK_PATH = re.compile(r'[<"][ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*/')
# A C++ raw string literal's opening, with any encoding prefix: R"delim( ... )delim".
RAW_STRING = re.compile(r'(?:u8|u|U|L)?R"([^ ()\\\t\v\f\n]{0,16})\(')
# The preprocessing directives that include a file (`#` or its digraph `%:`, C95 and C++) are C_INCLUDE_DIRECTIVE,
# above, read after comments are blanked.


def _skip_block_comment(text, i):
    """End of the (nestable) /* */ comment that starts at i."""
    depth, j, n = 0, i, len(text)
    while j < n:
        if text.startswith('/*', j):
            depth, j = depth + 1, j + 2
        elif text.startswith('*/', j):
            depth, j = depth - 1, j + 2
            if depth == 0:
                return j
        else:
            j += 1
    return n


def _skip_separators(text, i, nested):
    """The first index at or after i that is neither white space nor inside a comment: // to the line end, and /* */,
    nested as Swift nests them when `nested`, otherwise ending at the first */ as in C."""
    n = len(text)
    while i < n:
        if text[i].isspace() or text[i] == '\0':
            i += 1
        elif text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif text.startswith('/*', i):
            if nested:
                i = _skip_block_comment(text, i)
            else:
                j = text.find('*/', i + 2)
                i = n if j < 0 else j + 2
        else:
            break
    return i


def raw_imports(text, kinds=(), nested=True):
    """[(module, offset of `import`)] for every word `import` in the text, comments and literals included, that white
    space and comments separate from a module name (and, given `kinds`, from an import kind before the name): the name's
    first component, without backticks. This finds every Swift import declaration, Objective-C @import, `#pragma clang
    module import`, `_Pragma("clang module import ...")` and C++ import, however it is written."""
    out = []
    for m in IMPORT_WORD.finditer(text):
        nm = NAME_AT.match(text, _skip_separators(text, m.end(), nested))
        if nm and nm.group(2) in kinds:
            nm = NAME_AT.match(text, _skip_separators(text, nm.end(), nested))
        if nm:
            out.append((nm.group(1) if nm.group(1) is not None else nm.group(2), m.start()))
    return out


def swift_import_hits(text):
    """[(module, line)] for every import a Swift file can hold: raw_imports with Swift's import kinds and nested
    comments, so attributes, access levels, statements before it on the line, line breaks, comments, regex literals and
    raw identifiers make no difference."""
    return [(name, text.count('\n', 0, pos) + 1) for name, pos in raw_imports(text, SWIFT_IMPORT_KINDS, nested=True)]


def _splice(text):
    """(text with every line splice removed, a function mapping an offset in it to a line of the given text)."""
    pieces, marks, last, out_len, removed = [], [], 0, 0, 0
    for m in SPLICE.finditer(text):
        pieces.append(text[last:m.start()])
        out_len += m.start() - last
        removed += m.group(0).count('\n')
        marks.append((out_len, removed))
        last = m.end()
    pieces.append(text[last:])
    spliced = ''.join(pieces)
    starts = [o for o, _ in marks]

    def line_of(off):
        k = bisect.bisect_right(starts, off)
        return spliced.count('\n', 0, off) + 1 + (marks[k - 1][1] if k else 0)
    return spliced, line_of


def c_variants(text):
    """[(text, line_of)]: the C-family text as the preprocessor may read it, line splices joined, without trigraphs and,
    when it holds any, with them (a file compiled with -trigraphs or in a strict ISO C mode reads ??= as #)."""
    out = [_splice(text)]
    if TRIGRAPH.search(text):
        out.append(_splice(TRIGRAPH.sub(lambda m: TRIGRAPHS[m.group(1)], text)))
    return out


def c_code(text, keep_strings):
    """C-family source (line splices already joined) with its comments blanked and, unless keep_strings, the contents of
    its string and character literals, C++ raw strings included; line breaks kept, so offsets still map to lines."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        raw = RAW_STRING.match(text, i) if c in 'uULR' and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] == '_')) else None
        if text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
        elif raw:
            close = ')' + raw.group(1) + '"'
            j = text.find(close, raw.end())
            j = n if j < 0 else j + len(close)
            out.append(text[i:j] if keep_strings else re.sub(r'[^\n]', ' ', text[i:j]))
            i = j
            continue
        elif c in '"\'':
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            j = min(j + 1, n)
            out.append(text[i:j] if keep_strings else c + re.sub(r'[^\n]', ' ', text[i + 1:j - 1]) + text[j - 1:j])
            i = j
            continue
        else:
            out.append(c)
            i += 1
            continue
        out.append(re.sub(r'[^\n]', ' ', text[i:j]))
        i = j
    return ''.join(out)


def c_imports(text):
    """[(kind, name, line)] for C-family source, under every way the preprocessor may read it (c_variants), with
    comments blanked: ('include', path, line) for each #include, #import, #include_next and #embed directive (`#` or
    `%:`) of a quoted name, ('include<', path, line) for one of a <name>, and for each assembler .include or .incbin
    (in an assembly file, or in inline assembly in a string), and ('computed-include', directive, line) for a directive
    whose operand is neither, which macros decide (review R4-02); and three kinds that read the raw text, so no comment
    or literal can hide them: ('module', name, line) for every module raw_imports finds (@import, #pragma clang module
    import, _Pragma, C++ import); ('header', name, line) for every header file name, which covers any include of it,
    computed ones and __has_include among them; and ('framework', module, line) for every framework-style path
    (<M/...> or "M/...")."""
    found = set()
    for t, line_of in c_variants(text):
        code = c_code(t, keep_strings=True)
        for m in C_INCLUDE_DIRECTIVE.finditer(code):
            operand = m.group(2).strip()
            quoted = re.match(r'"([^"\n]*)"', operand) or re.match(r'<([^>\n]*)>', operand)
            if quoted:
                found.add(('include' if operand[0] == '"' else 'include<', quoted.group(1).strip(), line_of(m.start())))
            elif operand:
                found.add(('computed-include', f'#{m.group(1)} {operand[:80]}', line_of(m.start())))
        for m in ASM_INCLUDE_DIRECTIVE.finditer(code):
            found.add(('include<', m.group(1).strip(), line_of(m.start())))
        for name, pos in raw_imports(t, nested=False):
            found.add(('module', name, line_of(pos)))
        for m in HEADER_WORD.finditer(t):
            found.add(('header', m.group(0), line_of(m.start())))
        for m in FRAMEWORK_PATH.finditer(t):
            found.add(('framework', m.group(1), line_of(m.start())))
    return sorted(found, key=lambda x: (x[2], x[0], x[1]))


# A cache of `swift package dump-package` output across Checker instances (the self-test checks many copies of one
# synthetic tree): keyed by the manifest's path and content, with the tree's root replaced by a placeholder.
_DUMP_CACHE = {}
_ROOT_PLACEHOLDER = '\x00ROOT\x00'


def _rebase(value, old, new):
    if isinstance(value, str):
        for o in old:
            if value == o or value.startswith(o + '/'):
                return new + value[len(o):]
        return value
    if isinstance(value, list):
        return [_rebase(v, old, new) for v in value]
    if isinstance(value, dict):
        return {k: _rebase(v, old, new) for k, v in value.items()}
    return value


def _platforms_of(condition):
    """The lower-case platform names of a SwiftPM target dependency condition, or None when it has none."""
    names = (condition or {}).get('platformNames') if isinstance(condition, dict) else None
    return {str(n).lower() for n in names} if names else None


def _target_platforms(platform, destinations):
    """The platforms an XcodeGen target builds for, lower case (Mac Catalyst counts as iOS), or None if unknown."""
    names = set()
    for v in as_list(platform) + as_list(destinations):
        v = str(v).lower()
        if v in ('auto', ''):
            continue
        names.add('ios' if v in ('ios', 'ipados', 'maccatalyst') else v)
    return names or None


class Checker:
    def __init__(self, root, swift=None, run=None, distributions=None, sdk=None):
        self.root = os.path.abspath(root)
        self.real_root = os.path.realpath(self.root)
        self.failures = []
        self.sites = []  # the line of the fail() call behind each failure (the self-test's coverage check reads it)
        self.warnings = []
        self.warn_lines = []  # the line of the warn() call behind each warning (likewise)
        self.lines = []
        self.swift = swift or (['xcrun', 'swift'] if shutil.which('xcrun') else ['swift'])
        self.run_tool = run or run_tool
        self.distributions = distributions or venv_distributions
        self.sdk_source = sdk or sdk_names
        self._sdk = False
        self.lock_pins = {}
        self.product_binaries = []
        self.linked_used = set()
        self.banned_modules, self.banned_headers = {}, {}
        self.members = []  # (path the target includes, case-folded; test target?; manifest; target) for product manifests
        self.named_files = {}  # tracked file -> {'header-file', 'modulemap-file'}: named by a shipping target's settings

    # ----- reporting -------------------------------------------------------------------------------------------------
    def fail(self, category, where, message):
        self.failures.append((category, where, message))
        self.sites.append(sys._getframe(1).f_lineno)

    def warn(self, category, where, message):
        """A finding printed as WARN that does not change the exit status (see the module docstring for when)."""
        self.warnings.append((category, where, message))
        self.warn_lines.append(sys._getframe(1).f_lineno)

    def note(self, text):
        self.lines.append(text)

    # ----- files -----------------------------------------------------------------------------------------------------
    def path(self, rel):
        return os.path.join(self.root, rel)

    def rel_real(self, path):
        """path (absolute, or relative to the root), symbolic links resolved, relative to the resolved root."""
        return os.path.relpath(os.path.realpath(os.path.join(self.root, path)), self.real_root)

    def files(self):
        """The tracked files (git ls-files) or, outside a git checkout, every file; a symbolic link to a directory is
        one entry, as git tracks it."""
        if not hasattr(self, '_files'):
            if os.path.exists(self.path('.git')):
                out = subprocess.run(['git', '-C', self.root, 'ls-files', '-z'], capture_output=True, check=True).stdout
                listed = [p for p in out.decode('utf-8').split('\0') if p]
                self._files = sorted(p for p in listed if os.path.lexists(self.path(p)))
            else:
                found = []
                for dp, dns, fns in os.walk(self.root):
                    keep = []
                    for d in sorted(dns):
                        if os.path.islink(os.path.join(dp, d)):
                            found.append(os.path.relpath(os.path.join(dp, d), self.root))
                        elif d not in SKIP_DIRS:
                            keep.append(d)
                    dns[:] = keep
                    found += [os.path.relpath(os.path.join(dp, fn), self.root) for fn in fns]
                self._files = sorted(found)
        return self._files

    @staticmethod
    def under(rel, roots):
        return any(rel == r or rel.startswith(r.rstrip('/') + '/') for r in roots)

    def owners(self, rel):
        """[(test target?, manifest, target)] for the product-manifest targets whose declared source paths include rel."""
        key = rel.casefold()
        return [(test, manifest, target) for path, test, manifest, target in self.members
                if key == path or key.startswith(path + '/')]

    def is_test_file(self, rel):
        """Test code: a file that test targets of the product manifests include and no other target does. A file no
        target includes, or one in a test-named directory that a shipping target builds, is product code."""
        owners = self.owners(rel)
        return bool(owners) and all(test for test, _, _ in owners)

    @staticmethod
    def under_ci(rel, roots):
        """under(), ignoring case: the default macOS file system does, so ../../spikes reaches Spikes/."""
        return Checker.under(rel.casefold(), [r.casefold() for r in roots])

    # ----- manifests -------------------------------------------------------------------------------------------------
    def dump_package(self, rel):
        content = open(self.path(rel), 'rb').read()
        key = (rel, hashlib.sha256(content).hexdigest())
        if key not in _DUMP_CACHE:
            pkg_dir = os.path.dirname(self.path(rel))
            with tempfile.TemporaryDirectory(prefix='dump-package-') as tmp:
                r = subprocess.run(self.swift + ['package', '--package-path', pkg_dir, '--scratch-path', tmp, 'dump-package'],
                                   capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(f'swift package dump-package failed: {" ".join(r.stderr.split())[-400:]}')
            _DUMP_CACHE[key] = _rebase(json.loads(r.stdout), sorted({self.real_root, self.root}, key=len, reverse=True),
                                       _ROOT_PLACEHOLDER)
        return _rebase(copy.deepcopy(_DUMP_CACHE[key]), [_ROOT_PLACEHOLDER], self.root)

    def swiftpm(self, rel):
        """Package.swift at rel -> the manifest model (see manifest())."""
        d = self.dump_package(rel)
        base = os.path.dirname(rel)
        pkg_dir = self.path(base)
        model = {'remote': [], 'local': [], 'targets': [], 'binaries': [], 'strings': [], 'items': [], 'texts': []}
        # What the manifest reads besides its own text (MANIFEST_INPUTS), as (line, what): check_product_manifest
        # fails a product manifest on any. The raw text is read, so a comment that names one counts too.
        text = open(self.path(rel), encoding='utf-8', errors='replace').read()
        model['inputs'] = sorted(
            [(line, f'imports {name}') for name, line in swift_import_hits(text) if name not in MANIFEST_IMPORTS_ALLOWED]
            + [(text.count('\n', 0, m.start()) + 1, f'names {m.group(0)!r}') for m in MANIFEST_INPUTS.finditer(text)])
        for dep in d.get('dependencies', []):
            if 'sourceControl' in dep:
                sc = dep['sourceControl'][0]
                urls = sc.get('location', {}).get('remote', [])
                url = urls[0].get('urlString') if urls and isinstance(urls[0], dict) else (urls[0] if urls else '')
                req = sc.get('requirement', {})
                if 'exact' in req:
                    requirement = ('exact', req['exact'][0])
                else:
                    kind = next(iter(req), 'unknown')
                    requirement = (kind, json.dumps(req[kind]) if kind in req else '')
                model['remote'].append({'url': url, 'ref': sc.get('identity', ''), 'requirement': requirement})
            elif 'fileSystem' in dep:
                model['local'].append({'path': self.rel_real(dep['fileSystem'][0]['path']),
                                       'ref': dep['fileSystem'][0].get('identity', '')})
            else:
                model['remote'].append({'url': '', 'ref': json.dumps(dep)[:80], 'requirement': ('unknown', 'registry')})
        model['strings'] = [(s, [pkg_dir]) for s in strings_in(d, skip=('dependencies', 'targets', 'packageKind'))]
        # (value, whether only test targets use it): read for transitive-only packages' header names.
        model['texts'] = [(s, False) for s, _ in model['strings']]

        def kind_of(ttype):
            return 'test' if ttype == 'test' else 'plugin' if ttype == 'plugin' else 'regular'

        same_kind = {}
        for t in d.get('targets', []):
            same_kind[kind_of(t.get('type'))] = same_kind.get(kind_of(t.get('type')), 0) + 1

        def default_dir(name, ttype):
            """SwiftPM's directory for a target without a path (its PackageBuilder): <name> inside the first of the
            predefined directories that exists in the package (Tests, Sources, Source, src, srcs for a test target;
            Plugins for a plugin; Sources, Source, src, srcs otherwise), or that whole directory when it holds no
            <name> and the target is the only one of its kind (tools version 5.9 and later)."""
            kind = kind_of(ttype)
            bases = {'test': ('Tests', 'Sources', 'Source', 'src', 'srcs'), 'plugin': ('Plugins',)}.get(
                kind, ('Sources', 'Source', 'src', 'srcs'))
            root = next((b for b in bases if os.path.isdir(self.path(os.path.join(base, b)))), bases[0])
            if not os.path.isdir(self.path(os.path.join(base, root, name))) and same_kind.get(kind) == 1:
                return root
            return os.path.join(root, name)

        for t in d.get('targets', []):
            ttype = t.get('type')
            tdir = os.path.normpath(os.path.join(base, t.get('path') or default_dir(t['name'], ttype)))
            uses, items = [], []
            if ttype != 'binary':
                # The target's own sources: judged like any other path a product target builds from, so a target
                # whose sources are a package checkout under .build/ fails (review R3-01).
                items.append(('source', tdir, [self.root]))
            for dep in t.get('dependencies', []):
                if 'product' in dep:
                    # [name, package, moduleAliases ({original: alias} or null), condition]
                    pr = dep['product']
                    uses.append((pr[0], (pr[1] or pr[0]).lower(), _platforms_of(pr[3] if len(pr) > 3 else None)))
                    aliases = pr[2] if len(pr) > 2 and isinstance(pr[2], dict) else {}
                    # SwiftPM module aliasing renames a module of the product's graph; written as -module-alias
                    # writes it (alias=original), so judge() reads the original module's name after the `=`.
                    items += [('alias', f'{alias}={original}', []) for original, alias in sorted(aliases.items())]
                elif 'byName' in dep:
                    bn = dep['byName']
                    uses.append((bn[0], bn[0].lower(), _platforms_of(bn[1] if len(bn) > 1 else None)))
            # A build tool plugin from another package runs that package's code in the build: a use of the package.
            for usage in t.get('pluginUsages') or []:
                plugin = (usage or {}).get('plugin') or []
                if len(plugin) > 1 and plugin[1]:
                    uses.append((plugin[0], str(plugin[1]).lower(), None))
            if t.get('pkgConfig') or t.get('providers'):
                items.append(('tool', f"pkgConfig {t.get('pkgConfig')!r} (system library target {t['name']})", []))
            for s in t.get('settings') or []:
                only = _platforms_of(s.get('condition'))
                if only is not None and not only & {'ios', 'macos', 'maccatalyst'}:
                    continue  # a setting for other platforms (Linux, Windows ...) never reaches an Apple build
                for kind, arg in (s.get('kind') or {}).items():
                    value = arg.get('_0') if isinstance(arg, dict) else arg
                    if kind == 'headerSearchPath':
                        items.append(('include', str(value), [self.path(tdir)]))
                    elif kind == 'unsafeFlags':
                        items += [(k, v, [pkg_dir, self.path(tdir)])
                                  for k, v in flag_items([str(x) for x in as_list(value)], swift=s.get('tool') == 'swift')]
                    elif kind in ('linkedLibrary', 'linkedFramework'):
                        items.append(('library' if kind == 'linkedLibrary' else 'framework', str(value), []))
                    elif kind == 'define':
                        items.append(('define', str(value), []))
            model['targets'].append({'name': t['name'], 'test': ttype == 'test', 'uses': uses, 'platforms': None,
                                     'dirs': [tdir], 'items': [dict(kind=k, value=v, bases=b, where=rel, spike=False)
                                                               for k, v, b in items]})
            if ttype == 'binary':
                model['binaries'].append({'kind': 'binaryTarget', 'name': t['name'], 'url': t.get('url'),
                                          'checksum': t.get('checksum'),
                                          'path': os.path.normpath(os.path.join(base, t['path'])) if t.get('path') else None})
            model['strings'] += [(s, [pkg_dir, self.path(tdir)]) for s in strings_in(t)]
            model['texts'] += [(s, ttype == 'test') for s in strings_in(t)]
        return model

    @staticmethod
    def settings_pairs(block, groups, seen=()):
        """(key, value) pairs of an XcodeGen settings block: `base`, every configuration and the setting groups it
        names, or the block itself when it is a flat mapping of settings."""
        if not isinstance(block, dict):
            return []
        if not any(k in block for k in ('base', 'configs', 'groups')):
            return list(block.items())
        out = list((block.get('base') or {}).items()) if isinstance(block.get('base'), dict) else []
        for cfg in (block.get('configs') or {}).values() if isinstance(block.get('configs'), dict) else []:
            out += list(cfg.items()) if isinstance(cfg, dict) else []
        for g in as_list(block.get('groups')):
            if g not in seen:
                out += Checker.settings_pairs(groups.get(g), groups, seen + (g,))
        return out

    def xcconfig_pairs(self, path, seen=None, includes=None):
        """(key, value, file relative to the root) for the .xcconfig file at path and every file it #includes
        (relative to the including file, or to Xcode's directory for "<DEVELOPER_DIR>/..."). A `//` starts a comment,
        as Xcode reads these files. Each #include and optional #include? is also added to `includes`, as (the path it
        names, as a build-setting value relative to the including file's directory, that directory, the including file
        and line), and each other line that starts with #, which the check cannot read, as (None, the line, ...):
        config_items judges them (review R4-02: until then where an included file is was not judged)."""
        seen = set() if seen is None else seen
        includes = [] if includes is None else includes
        real = os.path.realpath(path)
        if real in seen or not os.path.isfile(real):
            return []
        seen.add(real)
        rel = os.path.relpath(real, self.real_root)
        out = []
        for n, line in enumerate(open(real, encoding='utf-8', errors='replace').read().splitlines(), 1):
            line = line.split('//', 1)[0].strip()
            if line.startswith('#'):
                # A path with a variable in it cannot be read here (the check would have to guess what Xcode
                # substitutes), so it counts as a line the check cannot read.
                m = re.match(r'^#include\??[ \t]*"([^"$]+)"$', line)
                named = re.sub(r'^<DEVELOPER_DIR>', '$(DEVELOPER_DIR)', m.group(1)) if m else None
                includes.append((named, line, os.path.dirname(real), f'{rel}:{n}'))
                if named is not None and '$' not in named:
                    out += self.xcconfig_pairs(os.path.join(os.path.dirname(real), named), seen, includes)
                continue
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])*)\s*=\s*(.*)$', line)
            if m:
                out.append((m.group(1), m.group(2), rel))
        return out

    def xcodegen(self, rel):
        """project.yml at rel -> the manifest model; package references are the keys of `packages:`."""
        y = yaml.safe_load(open(self.path(rel), encoding='utf-8')) or {}
        if not isinstance(y, dict):
            raise RuntimeError('not a YAML mapping')
        if 'include' in y:
            raise RuntimeError('`include:` is not supported by the dependency check; declare packages in this file')
        base = os.path.dirname(rel)
        model = {'remote': [], 'local': [], 'targets': [], 'binaries': [],
                 'strings': [(s, [self.path(base)]) for s in strings_in(y, skip=('packages', 'localPackages'))],
                 # (value, whether only test targets use it): read for transitive-only packages' header names; the
                 # project's own values (settings, schemes and their scripts ...) apply to every target.
                 'texts': [(s, False) for s in strings_in(y, skip=('packages', 'localPackages', 'targets', 'targetTemplates'))],
                 # Keys and values that XcodeGen replaces or expands when it generates the project (XCODEGEN_EXPANSION,
                 # review R4-01), as (where, text): check_product_manifest fails a product project.yml on any.
                 'expansions': [(where, s) for where, s in yaml_texts(y)
                                if XCODEGEN_EXPANSION.search(s) or s.lstrip().startswith('~')]}
        packages = dict(y.get('packages') or {})
        for p in y.get('localPackages') or []:
            packages[os.path.basename(str(p).rstrip('/'))] = {'path': p}
        for key, spec in packages.items():
            spec = spec or {}
            if 'path' in spec:
                model['local'].append({'path': self.rel_real(os.path.join(base, str(spec['path']))), 'ref': str(key).lower()})
                continue
            url = spec.get('url') or (f"https://github.com/{spec['github']}" if spec.get('github') else '')
            exact = [k for k in XCODEGEN_EXACT if k in spec]
            other = [k for k in XCODEGEN_OTHER if k in spec]
            if len(exact) == 1 and not other:
                value = spec[exact[0]]
                requirement = ('exact', value) if isinstance(value, str) else ('unquoted', repr(value))
            else:
                requirement = ('+'.join(exact + other) or 'none', ', '.join(f'{k}: {spec[k]}' for k in exact + other))
            model['remote'].append({'url': url, 'ref': str(key).lower(), 'requirement': requirement})
        templates = y.get('targetTemplates') or {}
        groups = y.get('settingGroups') or {}
        here = [self.path(base)]

        def config_items(configs):
            """A configFiles block: each file as a 'source' item, each file it #includes as a 'config' item (review
            R4-02; a #include line the check cannot read as an 'unreadable' one), and the settings they hold (every
            value read as text too, since a build-settings file's values are not manifest strings)."""
            out = []
            for path in (configs or {}).values() if isinstance(configs, dict) else []:
                full = os.path.join(self.path(base), str(path))
                out.append(dict(kind='source', value=str(path), bases=here, where=rel, spike=False))
                includes = []
                for k, v, f in self.xcconfig_pairs(full, includes=includes):
                    out += [dict(kind=kind, value=value, bases=here, where=f, spike=True)
                            for kind, value in setting_items([(k, v)], text=True)]
                for named, line, directory, where in includes:
                    out.append(dict(kind='config' if named is not None else 'unreadable',
                                    value=named if named is not None else line, bases=[directory], where=where, spike=True))
            return out

        model['items'] = [dict(kind=k, value=v, bases=here, where=rel, spike=False)
                          for k, v in setting_items(self.settings_pairs(y.get('settings'), groups)
                                                    + [p for g in groups.values() for p in self.settings_pairs(g, groups)])]
        model['items'] += config_items(y.get('configFiles'))
        for name, ref in (y.get('projectReferences') or {}).items():
            if isinstance(ref, dict) and ref.get('path'):
                model['items'].append(dict(kind='project', value=str(ref['path']), bases=here, where=rel, spike=False))

        def resolve(target, seen=()):
            r = {'type': target.get('type'), 'deps': as_list(target.get('dependencies')),
                 'sources': as_list(target.get('sources')), 'platform': target.get('platform'),
                 'destinations': target.get('supportedDestinations'),
                 'settings': self.settings_pairs(target.get('settings'), groups),
                 'configs': dict(target.get('configFiles') or {}) if isinstance(target.get('configFiles'), dict) else {},
                 'plugins': as_list(target.get('buildToolPlugins')), 'rules': as_list(target.get('buildRules')),
                 'texts': strings_in(target)}
            for name in as_list(target.get('templates')):
                if name in seen or name not in templates:
                    continue
                t = resolve(templates[name] or {}, seen + (name,))
                r['type'] = r['type'] or t['type']
                r['platform'] = r['platform'] or t['platform']
                r['destinations'] = r['destinations'] or t['destinations']
                r['deps'] = t['deps'] + r['deps']
                r['sources'] = t['sources'] + r['sources']
                r['settings'] = t['settings'] + r['settings']
                r['configs'] = dict(t['configs'], **r['configs'])
                r['plugins'] = t['plugins'] + r['plugins']
                r['rules'] = t['rules'] + r['rules']
                r['texts'] = t['texts'] + r['texts']
            return r

        for name, target in (y.get('targets') or {}).items():
            r = resolve(target or {})
            deps = [d for d in r['deps'] if isinstance(d, dict)]
            uses = [(d.get('product') or d['package'], str(d['package']).lower(), None) for d in deps if 'package' in d]
            # A build tool plugin from a package runs that package's code in the build: a use of the package.
            uses += [(str(p.get('plugin')), str(p['package']).lower(), None) for p in r['plugins']
                     if isinstance(p, dict) and p.get('package')]
            dirs, flags = [], []
            for s in r['sources']:
                p = s.get('path') if isinstance(s, dict) else s
                if p:
                    dirs.append(os.path.normpath(os.path.join(base, str(p))))
                if isinstance(s, dict) and s.get('compilerFlags'):
                    # Per-file flags (review R3-01); a Swift file's are the Swift compiler's (review R4-04).
                    flags += flag_items(split_setting(s['compilerFlags']), swift=str(p or '').lower().endswith('.swift'))
            items = [dict(kind='source', value=d, bases=[self.root], where=rel, spike=False) for d in dirs]
            items += [dict(kind=k, value=v, bases=here, where=rel, spike=False) for k, v in setting_items(r['settings']) + flags]
            items += config_items(r['configs'])
            # A build rule decides which compiler or script processes which files, so it can compile as code a file
            # this check does not read as code, and whose includes it does not judge (review R4-02's reasoning).
            items += [dict(kind='tool', value=f'buildRules {json.dumps(rule)[:160]}', bases=[], where=rel, spike=False)
                      for rule in r['rules']]
            model['texts'] += [(s, r['type'] in TEST_TYPES) for s in r['texts']]
            for d in deps:
                if 'sdk' in d:
                    value = str(d['sdk'])
                    kind = 'framework' if value.endswith('.framework') else 'library'
                    value = re.sub(r'\.framework$', '', value) if kind == 'framework' else re.sub(r'^lib|(\.[0-9][0-9.]*)?\.(tbd|dylib|a)$', '', value)
                    items.append(dict(kind=kind, value=value, bases=[], where=rel, spike=False))
            model['targets'].append({'name': name, 'test': r['type'] in TEST_TYPES, 'uses': uses, 'dirs': dirs,
                                     'platforms': _target_platforms(r['platform'], r['destinations']), 'items': items})
            for d in deps:
                for kind in ('framework', 'bundle', 'carthage'):
                    if kind in d:
                        value = str(d[kind])
                        model['binaries'].append({'kind': kind, 'target': name, 'name': value if kind == 'carthage' else None,
                                                  'path': None if kind == 'carthage' else os.path.normpath(os.path.join(base, value))})
        return model

    def manifest(self, rel):
        """{'remote': [{url, ref, requirement}], 'local': [{path (resolved, root-relative), ref}],
            'targets': [{name, test, uses: [(product, package ref, platforms of its condition or None)], dirs, platforms,
                         items}],
            'binaries': [...], 'strings': [(string value, [directories it may be relative to])], 'items': [...],
            'texts': [(string value, whether only test targets use it)]}
        An item is one path, name, flag or setting the manifest gives the build (judge() reads it): {kind (source,
        project, include, libpath, header-file, modulemap-file, binary, library, framework, alias, import, define, flag,
        tool or text), value, bases (directories a relative path may be relative to), where (the file that names it),
        spike (whether judge() must report a reference into Spikes/ itself, because no manifest string carries it)};
        manifest-level items apply to every target."""
        if not hasattr(self, '_models'):
            self._models = {}
        if rel not in self._models:
            self._models[rel] = self.swiftpm(rel) if rel.endswith('Package.swift') else self.xcodegen(rel)
        return self._models[rel]

    def remote_graph(self, rel, seen=None):
        """True when the manifest, or a local package it depends on (recursively), requires a remote package."""
        seen = set() if seen is None else seen
        if rel in seen:
            return False
        seen.add(rel)
        m = self.manifest(rel)
        if m['remote']:
            return True
        for local in m['local']:
            target = os.path.join(local['path'], 'Package.swift')
            if os.path.isfile(self.path(target)) and self.remote_graph(target, seen):
                return True
        return False

    def required_remote(self, rel, seen=None):
        """[(url, the manifest that requires it)] for the manifest and every local package it reaches (recursively)."""
        seen = set() if seen is None else seen
        if rel in seen:
            return []
        seen.add(rel)
        m = self.manifest(rel)
        out = [(d['url'], rel) for d in m['remote'] if d['url']]
        for local in m['local']:
            target = os.path.join(local['path'], 'Package.swift')
            if os.path.isfile(self.path(target)):
                out += self.required_remote(target, seen)
        return out

    # ----- the check -------------------------------------------------------------------------------------------------
    def run(self, toolchain=False):
        try:
            inv = json.load(open(self.path(INVENTORY), encoding='utf-8'))
        except (OSError, ValueError) as e:
            self.fail('inventory', INVENTORY, f'cannot read: {e}')
            return
        files = self.files()
        tracked = set(files)
        product_roots = inv.get('roots', {}).get('product', [])
        spike_roots = inv.get('roots', {}).get('spike', [])
        packages = self.check_inventory(inv, tracked)
        self.check_xcode_projects(files)
        self.binaries_inv = [b for b in inv.get('binaries', []) if isinstance(b, dict)]
        for p in packages:
            if p['role'] == 'product-transitive':
                self.banned_modules.update({m.casefold(): (m, p) for m in p.get('modules', [])})
                self.banned_headers.update({h.casefold(): (h, p) for h in p.get('headers', [])})
                # A Swift module's generated Objective-C header (Zip-Swift.h) exposes its @objc API to C-family code.
                self.banned_headers.update({f'{m}-Swift.h'.casefold(): (f'{m}-Swift.h', p) for m in p.get('modules', [])})
        by_url = {p['_norm']: p for p in packages}
        locks = self.check_locks(inv, files, tracked, by_url, product_roots)
        self.check_manifests(inv, files, tracked, by_url, locks, product_roots, spike_roots)
        self.check_symlinks(files, product_roots, spike_roots)
        self.check_modulemaps(files, product_roots, spike_roots)
        self.check_license_texts(packages, tracked)
        self.check_product_sources(files, product_roots, spike_roots)
        self.check_binaries(inv, files, product_roots)
        self.check_vendored(inv, files, tracked, product_roots)
        self.check_python(inv, toolchain)
        self.check_actions(inv, files)
        self.check_toolchain(inv, toolchain)
        self.check_docs(packages)
        self.check_acknowledgements(inv, tracked)

    def check_inventory(self, inv, tracked):
        if inv.get('schema_version') != 1:
            self.fail('inventory', INVENTORY, f"schema_version is {inv.get('schema_version')!r}, expected 1")
        packages, seen = [], set()
        for i, p in enumerate(inv.get('packages', [])):
            where = f"{INVENTORY} packages[{i}] {p.get('name', '?')}"
            missing = [k for k in ('name', 'url', 'identity', 'version', 'revision', 'role', 'platforms', 'direct_in',
                                   'used_by_targets', 'locks', 'license') if k not in p]
            if missing:
                self.fail('inventory', where, f'missing fields {missing}')
                continue
            for k in ('direct_in', 'locks', 'used_by_targets'):
                if not isinstance(p[k], list):
                    self.fail('inventory', where, f'{k} must be a list')
                    p[k] = []
            if not isinstance(p['license'], dict):
                self.fail('inventory', where, 'license must be an object with an id and files')
                p['license'] = {}
            p['_norm'] = norm_url(p['url'])
            if p['_norm'] in seen:
                self.fail('inventory', where, f"duplicate package {p['_norm']}")
            seen.add(p['_norm'])
            if p['role'] not in ROLES:
                self.fail('inventory', where, f"role {p['role']!r} is not one of {ROLES}")
            if not isinstance(p['platforms'], list) or not p['platforms'] or any(x not in PLATFORMS for x in p['platforms']):
                self.fail('inventory', where, f"platforms {p['platforms']!r} must be a non-empty list drawn from {PLATFORMS}")
                p['platforms'] = list(PLATFORMS)
            if not VERSION.match(str(p['version'])):
                self.fail('inventory', where, f"version {p['version']!r} is not an exact version")
            if not REV.match(str(p['revision'])):
                self.fail('inventory', where, f"revision {p['revision']!r} is not a 40-character commit")
            for u in p['used_by_targets']:
                if not (isinstance(u, dict) and u.get('manifest') and u.get('target') and isinstance(u.get('products'), list)
                        and isinstance(u.get('test'), bool)):
                    self.fail('inventory', where, f'used_by_targets entry {u!r} needs a manifest, a target, a products list and test')
            files = p['license'].get('files') or []
            if not p['license'].get('id') or not files:
                self.fail('inventory', where, 'license needs an id and at least one file')
            for f in files:
                if not SHA.match(str(f.get('sha256', ''))) or not f.get('text'):
                    self.fail('inventory', where, f"license file {f.get('path')!r} needs a sha256 and a text path")
            for k in ('modules', 'headers'):
                if k in p and not (isinstance(p[k], list) and all(isinstance(x, str) and x for x in p[k])):
                    self.fail('inventory', where, f'{k} must be a list of names')
                    p[k] = []
            if p['role'] == 'product-transitive' and not p.get('modules'):
                self.fail('inventory', where, 'a product-transitive package needs its module names (modules), which the import check bans')
            packages.append(p)
        for i, b in enumerate(inv.get('binaries', [])):
            if not isinstance(b, dict) or b.get('kind') not in BINARY_KINDS or not b.get('license'):
                self.fail('inventory', f'{INVENTORY} binaries[{i}]', f'needs a kind from {BINARY_KINDS} and a license')
            elif b['kind'] == 'linked' and not (b.get('name') and b.get('manifest')):
                self.fail('inventory', f'{INVENTORY} binaries[{i}]', 'a linked entry needs the name it links and the manifest (or module map) that links it')
        return packages

    def check_locks(self, inv, files, tracked, by_url, product_roots):
        registry = {}
        for entry in inv.get('locks', []):
            path, manifest = entry.get('path', ''), entry.get('manifest', '')
            registry[path] = entry
            if path not in tracked:
                self.fail('lock-registry', path, 'registered in the inventory but not committed')
            if manifest not in tracked or os.path.dirname(manifest) != os.path.dirname(path):
                self.fail('lock-registry', path, f'its manifest {manifest!r} is not a committed file in the same directory')
        committed = [f for f in files if os.path.basename(f) == 'Package.resolved' and os.path.isfile(self.path(f))]
        for path in committed:
            if path not in registry:
                self.fail('lock-registry', path, 'committed lock not registered in the inventory (locks)')
        pinned_in = {}
        for path in committed:
            try:
                d = json.load(open(self.path(path), encoding='utf-8'))
            except ValueError as e:
                self.fail('lock-registry', path, f'not valid JSON: {e}')
                continue
            if d.get('version') not in (2, 3):
                self.fail('lock-registry', path, f"unsupported Package.resolved format version {d.get('version')!r}")
            product = self.under(path, product_roots)
            seen = set()
            self.lock_pins[path] = set()
            for pin in d.get('pins', []):
                state, location = pin.get('state', {}), pin.get('location', '')
                key = norm_url(location)
                self.lock_pins[path].add(key)
                if pin.get('kind') != 'remoteSourceControl':
                    self.fail('not-exact', path, f"pin {pin.get('identity')!r} is {pin.get('kind')!r}; only remoteSourceControl pins are allowed")
                p = by_url.get(key)
                if p is None:
                    self.fail('unknown-package', path, f'pins {location} ({state.get("version")}), which is not in the inventory')
                    continue
                if key in seen:
                    self.fail('pin-differs', path, f'pins {p["name"]} twice')
                seen.add(key)
                pinned_in.setdefault(key, set()).add(path)
                if pin.get('identity') != p['identity']:
                    self.fail('pin-differs', path, f"{p['name']}: identity {pin.get('identity')!r}, inventory {p['identity']!r}")
                if 'version' not in state or state.get('branch'):
                    self.fail('not-exact', path, f"{p['name']}: pinned to {state.get('branch') or 'a bare revision'}, not a version")
                if state.get('version') != p['version'] or state.get('revision') != p['revision']:
                    self.fail('pin-differs', path, f"{p['name']}: lock {state.get('version')} {state.get('revision')}, inventory {p['version']} {p['revision']}")
                if path not in p['locks']:
                    self.fail('lock-registry', path, f"pins {p['name']}, but the inventory's locks for it do not list this file")
                if product and p['role'] == 'spike':
                    self.fail('spike-in-product', path, f"pins the spike-only package {p['name']}")
        for p in by_url.values():
            for path in p['locks']:
                if path not in registry:
                    self.fail('lock-registry', INVENTORY, f"{p['name']} lists {path}, which is not a registered lock")
                elif path in tracked and path not in pinned_in.get(p['_norm'], set()):
                    self.fail('pin-missing', path, f"does not pin {p['name']}, which the inventory says it does")
        self.note(f'locks: {len(committed)} committed, {len(registry)} registered')
        return registry

    def check_manifests(self, inv, files, tracked, by_url, registry, product_roots, spike_roots):
        manifests = [f for f in files if os.path.basename(f) in ('Package.swift', 'project.yml') and os.path.isfile(self.path(f))]
        declared, used = {}, {}
        unlocked = {u.get('manifest'): u for u in inv.get('unlocked', [])}
        remote_count = 0
        for rel in manifests:
            product = self.under(rel, product_roots)
            try:
                m = self.manifest(rel)
            except (RuntimeError, ValueError, yaml.YAMLError) as e:
                self.fail('inventory', rel, f'cannot read the manifest: {e}')
                continue
            refs = {}
            for dep in m['remote']:
                remote_count += 1
                key = norm_url(dep['url'])
                p = by_url.get(key)
                kind, value = dep['requirement']
                if kind != 'exact':
                    self.fail('not-exact', rel, f"{dep['url'] or dep['ref']}: requirement {kind} {value}; only exact versions are allowed")
                if p is None:
                    self.fail('unknown-package', rel, f"requires {dep['url'] or dep['ref']}, which is not in the inventory")
                    continue
                refs[dep['ref']] = p
                declared.setdefault(key, set()).add(rel)
                if kind == 'exact' and str(value) != p['version']:
                    self.fail('pin-differs', rel, f"{p['name']}: requires exactly {value}, inventory pins {p['version']}")
                if rel not in p['direct_in']:
                    self.fail('lock-registry', rel, f"requires {p['name']}, but the inventory's direct_in for it does not list this manifest")
                if product and p['role'] == 'spike':
                    self.fail('spike-in-product', rel, f"requires the spike-only package {p['name']}")
                if product and p['role'] == 'product-transitive':
                    self.fail('transitive-direct', rel, f"requires {p['name']} directly; the inventory admits it only through another package")
            for t in m['targets']:
                for product_name, ref, _ in t['uses']:
                    if ref in refs:
                        used.setdefault(refs[ref]['_norm'], set()).add((rel, t['name'], product_name, t['test']))
            if product:
                self.check_product_manifest(rel, m, refs, product_roots, spike_roots)
            lock = os.path.join(os.path.dirname(rel), 'Package.resolved')
            try:
                needs_lock = self.remote_graph(rel)
            except (RuntimeError, ValueError, yaml.YAMLError) as e:
                self.fail('inventory', rel, f'cannot follow its local packages: {e}')
                continue
            if needs_lock and lock not in tracked:
                if rel not in unlocked:
                    self.fail('unlocked', rel, 'reaches remote packages but has no committed Package.resolved beside it and no exemption')
                elif not self.under(rel, spike_roots):
                    self.fail('unlocked', rel, f"a manifest outside {' and '.join(spike_roots)} cannot be exempted (exemptions are for spikes only); commit its lock")
            if rel in unlocked and (lock in tracked or not needs_lock):
                self.fail('unlocked', rel, 'stale exemption: it ' + ('has a committed lock' if lock in tracked else 'reaches no remote package'))
        # A lock must pin every package its manifest requires, directly or through a local package; otherwise SwiftPM
        # (without --force-resolved-versions) would resolve the missing ones afresh, unlocked.
        for path, entry in sorted(registry.items()):
            manifest = entry.get('manifest', '')
            if path not in self.lock_pins or manifest not in tracked:
                continue
            try:
                required = self.required_remote(manifest)
            except (RuntimeError, ValueError, yaml.YAMLError):
                continue  # reported above
            for url, via in required:
                if norm_url(url) not in self.lock_pins[path]:
                    how = '' if via == manifest else f' through its local package {os.path.dirname(via)}'
                    self.fail('pin-missing', path, f'does not pin {url}, which {manifest} requires{how}: the lock is stale; re-resolve it')
        for u in unlocked.values():
            if u.get('manifest') not in tracked:
                self.fail('lock-registry', INVENTORY, f"unlocked entry for {u.get('manifest')!r}, which is not a committed manifest")
            if not (u.get('reason') or '').strip():
                self.fail('inventory', INVENTORY, f"unlocked entry for {u.get('manifest')!r} gives no reason")
        for key, p in by_url.items():
            for rel in p['direct_in']:
                if rel not in declared.get(key, set()):
                    self.fail('lock-registry', INVENTORY, f"{p['name']} lists {rel} in direct_in, but that manifest does not require it")
            want = {(u.get('manifest'), u.get('target'), prod, u.get('test')) for u in p['used_by_targets'] if isinstance(u, dict)
                    for prod in u.get('products') or []}
            have = used.get(key, set())
            if want != have:
                self.fail('lock-registry', INVENTORY,
                          f"{p['name']}: used_by_targets is stale: the manifests also have {sorted(have - want) or 'nothing'}; the inventory also has {sorted(want - have) or 'nothing'} (run `check-dependency-lock.py used-by-targets`)")
        self.used = used
        self.note(f'manifests: {len(manifests)} read, {remote_count} remote requirements')

    def check_product_manifest(self, rel, m, refs, product_roots, spike_roots):
        """Rules for a manifest under Apps/ or Packages/."""
        # Review R4-01: what the generator or the build evaluates from outside the manifest's text, so that the value
        # the build uses is not the one this check reads: XcodeGen's ${...} and ~ (any key or value of a project.yml,
        # test targets included, since a key or a template name can move code between targets), and what a
        # Package.swift reads besides its own text.
        for where, text in m.get('expansions', []):
            how = ('XcodeGen expands a leading ~ in the paths it resolves, such as a local package\'s path or a source '
                   'path, to a home directory: it does not take such a path from the project\'s directory'
                   if not XCODEGEN_EXPANSION.search(text) else
                   'XcodeGen replaces ${NAME} with the environment variable NAME when it generates the project (and, in a '
                   'target template, with the target\'s name, its platform or a template attribute), a YAML escape such '
                   'as \\x24{ included')
            self.fail('manifest-input', rel, f"{where} is {text[:120]!r}: {how}, so the value the build uses is not the one this check reads (review R4-01). Write the value out; a build setting may use Xcode's $(NAME), which the path rules judge")
        for line, what in m.get('inputs', []):
            self.fail('manifest-input', f'{rel}:{line}', f"{what}: every build evaluates a Package.swift again, in its own environment, so a product manifest may read nothing but its own text: it may import only {' and '.join(MANIFEST_IMPORTS_ALLOWED)}, and may not name Context (the environment, the package directory, git), CommandLine, readLine, _silgen_name, _cdecl or _extern, random numbers or clocks, or hold an #if (review R4-01's reasoning). Found in the raw text: a comment that names one counts too")
        for local in m['local']:
            if self.under_ci(local['path'], spike_roots):
                self.fail('spike-in-product', rel, f"depends on {local['path']} under {'/'.join(spike_roots)}, which is never shipped")
            elif not self.under_ci(local['path'], product_roots):
                self.fail('outside-product', rel, f"depends on the local package {local['path']}, outside {' and '.join(product_roots)}, where the product rules do not apply")
        for value, bases in m['strings']:
            for hit in self.spike_paths(value, bases, spike_roots):
                self.fail('spike-in-product', rel, f'names {hit[0]!r}, which resolves to {hit[1]} under {"/".join(spike_roots)}; Spikes code is never shipped')
        # Any value a shipping target uses (settings, flags, definitions, scripts ...) that names a public header of a
        # transitive-only package: such a name reaches the build without an include in any source file (review R3-01).
        for value in sorted({v for v, test in m.get('texts', []) if not test}):
            self.judge_text(rel, value, 'a value of the manifest', modules=False)
        for t in m['targets']:
            for d in t['dirs']:
                self.members.append((os.path.normpath(d).casefold(), t['test'], rel, t['name']))
            if not t['test']:
                for d in t['dirs']:
                    if in_test_named_dir(d + '/x'):
                        self.fail('test-layout', rel, f"target {t['name']} is not a test target but takes its sources from {d}, a directory named like test code; rename it or make the target a test target")
            for product_name, ref, condition in t['uses']:
                p = refs.get(ref)
                if not p:
                    continue
                if p['role'] == 'test' and not t['test']:
                    self.fail('test-in-product', rel, f"target {t['name']} uses {product_name} from the test-only package {p['name']}")
                if not t['test'] and p['role'] in ('product', 'product-transitive'):
                    # Without a condition, a dependency builds wherever its target does: for a package target (whose
                    # `platforms:` sets minimum versions, not a limit) or a target of unknown platform, that is every
                    # platform Sylvia builds for.
                    allowed = {x.lower() for x in p['platforms']}
                    effective = condition if condition is not None else (t['platforms'] or {x.lower() for x in PLATFORMS})
                    if not effective <= allowed:
                        self.fail('platform', rel, f"target {t['name']} can build {product_name} for {', '.join(sorted(effective))}, but the inventory allows {p['name']} only on {', '.join(p['platforms'])}")
        for item in m.get('items', []):
            self.judge(rel, item, False, product_roots, spike_roots)
        for t in m['targets']:
            for item in t.get('items', []):
                self.judge(rel, item, t['test'], product_roots, spike_roots)
        for b in m['binaries']:
            self.product_binaries.append(dict(b, manifest=rel))

    def judge(self, rel, item, test, product_roots, spike_roots):
        """One path, name, flag or setting that a product manifest, or a build-settings file or module map under the
        product roots, gives the build (see manifest() for the kinds). Test targets never ship, so only their references
        into Spikes/ are judged. For a shipping target:
          - a flag must be one a product target may pass, a setting may not replace a tool or the SDK, and a module a
            flag imports implicitly, or a definition's text, may not name a transitive-only package's module or header;
          - a path may use only the project-directory variables, or start with a build-product, SDK or toolchain
            variable and stay inside it; a path into the repository must stay inside Apps/ and Packages/ and name
            content git tracks there (so never a package checkout, build product or generated file under them), and a
            header or module map it takes must be such a file, which the check then reads as product code."""
        kind, value, where = item['kind'], str(item['value']), item['where']
        label = where if where.split(':')[0] == rel else f'{where} (used by {rel})'
        if kind == 'alias':
            hit = self.banned_modules.get(value.split('=', 1)[-1].strip().casefold())
            if hit and not test:
                self.fail('transitive-direct', label, f"aliases {hit[0]} ({value}), a module of {hit[1]['name']}, which product code may use only through the package that brings it")
            return
        if kind in ('library', 'framework'):
            if not test:
                self.judge_linked(rel, label, kind, value)
            return
        if kind in ('flag', 'tool', 'import', 'define', 'text', 'redefine', 'unreadable'):
            if test:
                return
            if kind == 'redefine':
                self.fail('outside-product', label, f"sets {value}: the check evaluates that variable itself (a path that starts with a build-product, SDK or toolchain variable is trusted to stay in that directory, and $(SRCROOT), $(PROJECT_DIR) and $(SOURCE_ROOT) are the project's directory), so a manifest or build-settings file that assigns it could point such a path anywhere (review R4-03)")
            elif kind == 'unreadable':
                self.fail('outside-product', label, f"has the line {value!r}: a build-settings file may hold only settings, comments and #include \"<path>\" or #include? \"<path>\" lines whose path holds no variable, and this check cannot read which file this one brings in (review R4-02)")
            elif kind == 'flag':
                self.fail('flag', label, f"passes {value!r}, which is not one of the flags a product target may pass (FLAGS_ALLOWED and the path, name and definition flags in Scripts/check-dependency-lock.py): what it brings into the build cannot be judged. Remove it, or add it there with a rule for its argument and a self-test case (ADR-0014 section 6)")
            elif kind == 'tool':
                self.fail('outside-product', label, f"sets {value}: it replaces a compiler, linker, SDK or toolchain input, or takes flags from outside the manifests, so what the target is built with cannot be judged")
            elif kind == 'import':
                hit = self.banned_modules.get(value.strip().casefold())
                if hit:
                    self.fail('transitive-direct', label, f"imports {hit[0]} into every source file of the target (-import-module {value}, with no import in any file), a module of {hit[1]['name']}, which product code may use only through the package that brings it")
            else:
                self.judge_text(label, value, 'a preprocessor definition' if kind == 'define' else 'a build setting', modules=kind == 'define')
            return
        how, found = self.resolve_setting(value, item['bases'])
        if how == 'path':
            for path in found:
                if self.under_ci(path, spike_roots):
                    if item['spike']:  # otherwise the manifest's own strings already reported it
                        self.fail('spike-in-product', label, f'names {value!r}, which resolves to {path} under {"/".join(spike_roots)}; Spikes code is never shipped')
                elif test:
                    continue
                elif not self.under_ci(path, product_roots):
                    what = {'include': 'takes headers or a module map from', 'source': 'builds from',
                            'project': 'builds from', 'config': 'takes build settings from',
                            'header-file': 'includes into every file', 'modulemap-file': 'takes a module map from',
                            'libpath': 'searches for libraries or frameworks in', 'binary': 'links'}[kind]
                    self.fail('binary' if kind in ('libpath', 'binary') else 'outside-product', label,
                              f"{what} {value!r}, which resolves to {path}, outside {' and '.join(product_roots)}, where the product rules do not apply")
                else:
                    self.judge_inside(label, kind, value, path)
        elif test or how == 'empty':
            return
        elif how == 'unknown':
            self.fail('outside-product', label, f"names {value!r}, which uses {', '.join('$(' + v + ')' for v in found)}: a variable the check cannot evaluate. A path in a product target may use only $(SRCROOT), $(PROJECT_DIR) or $(SOURCE_ROOT), or start with a build-product, SDK or toolchain variable")
        elif '..' in found or any(p.casefold() in CHECKOUT_DIRS for p in found):
            self.fail('outside-product', label, f"names {value!r}, which leaves the build-product, SDK or toolchain directory it starts from, or reaches package checkouts: code outside Apps/ and Packages/ (Xcode keeps package checkouts beside the build products, in SourcePackages/checkouts)")
        elif kind in ('header-file', 'modulemap-file', 'source', 'project', 'config'):
            self.fail('outside-product', label,
                      f"takes build settings from {value!r}, a build, SDK or toolchain directory: the build-settings files a product target uses, and the files they #include, must be files git tracks under {' or '.join(product_roots)}, where the check can read them (review R4-02)"
                      if kind == 'config' else
                      f"takes {'a header' if kind == 'header-file' else 'a module map' if kind == 'modulemap-file' else 'sources'} from {value!r}, a build directory: what a product target compiles must be a file git tracks under {' or '.join(product_roots)}, where the check can read it")

    def judge_inside(self, label, kind, value, path):
        """A path a shipping target takes from inside the product roots must name content git tracks: a tracked file,
        or a directory that holds one (a referenced Xcode project: one generated from a project.yml tracked beside it).
        Anything else there is a build product, a package checkout (.build/checkouts) or a generated file, which the
        product rules cannot read. A header or module map a setting or flag names is then read as product code."""
        tracked_file = self.tracked_file(path)
        if kind in ('header-file', 'modulemap-file', 'config'):
            ok = tracked_file is not None
        elif kind == 'project':
            ok = self.tracked_dir(path) or self.tracked_file(os.path.join(os.path.dirname(path), 'project.yml')) is not None
        else:
            ok = tracked_file is not None or self.tracked_dir(path)
        if not ok:
            where = ' (a build or package-checkout directory)' if any(p.casefold() in CHECKOUT_DIRS for p in path.split('/')) else ''
            also = '; a referenced Xcode project must be generated from a project.yml tracked beside it' if kind == 'project' else ''
            self.fail('outside-product', label, f"names {value!r}, which resolves to {path}{where}: {'that is not a file' if kind in ('header-file', 'modulemap-file', 'config') else 'nothing there is'} tracked by git, so it can hold only build products, package checkouts or generated files, which the product rules cannot read{also}")
        elif kind in ('header-file', 'modulemap-file'):
            self.named_files.setdefault(tracked_file, set()).add(kind)

    def judge_text(self, label, value, what, modules):
        """Text that reaches the build (a definition, a setting or another manifest value) may not name a public header
        of a transitive-only package, which a computed include, a prefix header or a script could then reach without
        an include in any source file; a definition may not name one of its modules either, since a macro can carry it
        into an import. Reads the raw text, so a mention that includes nothing counts too (review R3-01)."""
        for m in HEADER_WORD.finditer(value):
            hit = self.banned_headers.get(m.group(0).casefold())
            if hit:
                self.fail('transitive-direct', label, f"names {m.group(0)}, a public header of {hit[1]['name']}, in {what} ({value[:120]!r}), which product code may reach only through the package that brings it (found in the raw text: a mention counts too)")
                return
        if modules:
            for m in re.finditer(r'[A-Za-z_][A-Za-z0-9_]*', value):
                hit = self.banned_modules.get(m.group(0).casefold())
                if hit:
                    self.fail('transitive-direct', label, f"names {hit[0]}, a module of {hit[1]['name']}, in {what} ({value[:120]!r}): a macro can carry a module's name into an import, so a definition may not name one")
                    return

    def judge_include(self, where, f, name, angled, product_roots):
        """A file that product code (not tests) brings in by #include, #import, #include_next or #embed, or the
        assembler's .include or .incbin, must be code the check reads (review R4-02: until then only a path into
        Spikes/ was judged). A quoted name that resolves beside the including file to a file git tracks under the
        product roots is that file, which the check reads as product code. Any other name is looked up in the search
        directories (the target's own, which the setting rules judge, and the public include directories of the
        packages it depends on, Minizip's among them), so it may not be absolute, climb out of the directory it is found
        in with `..` (from a package's include directory into the package's own sources, for one), or pass through a
        build or package-checkout directory."""
        parts = [p for p in re.split(r'[\\/]+', name) if p not in ('', '.')]
        here = None
        if not angled:
            here = self.rel_real(os.path.join(os.path.dirname(f), name))
            if self.tracked_file(here) and self.under_ci(here, product_roots):
                return
        beside = f'; beside this file it would be {here}, which is not a file git tracks under {" or ".join(product_roots)}' if here else ''
        if os.path.isabs(name):
            self.fail('outside-product', where, f"includes {name!r}, an absolute path{beside}: what a product file brings in must be a file git tracks under {' or '.join(product_roots)}, where the product rules read it")
        elif '..' in parts:
            self.fail('outside-product', where, f"includes {name!r}{beside}, and in a search directory its `..` climbs out of that directory (from a package's public include directory into the package's own sources, for one), to code the product rules do not read (Minizip's unzip.c, for one)")
        elif any(p.casefold() in CHECKOUT_DIRS for p in parts):
            self.fail('outside-product', where, f"includes {name!r}, a path through a build or package-checkout directory ({next(p for p in parts if p.casefold() in CHECKOUT_DIRS)}), whose files the product rules do not read")

    def tracked_file(self, path):
        """The tracked file at path (compared ignoring case, as the default macOS file system does), or None."""
        if not hasattr(self, '_tracked_cf'):
            self._tracked_cf = {f.casefold(): f for f in self.files()}
            self._tracked_dirs_cf = {d.casefold() for f in self.files() for d in self.parents(f)}
        return self._tracked_cf.get(path.casefold())

    def tracked_dir(self, path):
        """Whether git tracks a file under the directory at path."""
        self.tracked_file(path)
        return path.casefold() in self._tracked_dirs_cf

    @staticmethod
    def parents(rel):
        parts = rel.split('/')
        return ['/'.join(parts[:i]) for i in range(1, len(parts))]

    def judge_linked(self, rel, label, kind, name):
        """A library or framework a product target links by name must come from the SDK or be inventoried."""
        if self._sdk is False:
            self._sdk = self.sdk_source()
        if self._sdk is None:
            self.fail('toolchain', 'xcrun --show-sdk-path', f'cannot list the SDKs, so {label} linking the {kind} {name!r} cannot be judged')
            return
        if name in self._sdk[kind]:
            return
        for i, b in enumerate(self.binaries_inv):
            if b.get('kind') == 'linked' and b.get('manifest') == rel and b.get('name') == name:
                self.linked_used.add(i)
                return
        self.fail('binary', label, f"links the {kind} {name!r}, which no SDK provides and the inventory does not list (binaries, kind linked): third-party binary code")

    def resolve_setting(self, value, bases):
        """How a path that a setting, flag or module map names can be judged: ('empty', []) for nothing or
        $(inherited); ('build', the path components after the variable) for a value that starts with a build-product,
        SDK or toolchain variable and uses no other; ('unknown', the variables' names) for a value that uses any other
        variable; ('path', the paths it names) otherwise: symbolic links resolved, relative to the resolved root, one per
        base directory it may be relative to, with the project-directory variables replaced by that base."""
        value = value.strip()
        if not value or value in INHERITED:
            return 'empty', []
        m = BUILD_VARS.match(value)
        if m:
            others = [a or b for a, b in VARIABLE.findall(value[m.end():])]
            if others:
                return 'unknown', others
            return 'build', [p for p in value[m.end():].split('/') if p and p != '.']
        out = set()
        for base in bases or [self.root]:
            v = PROJECT_DIR_VARS.sub(lambda _: base, value)
            if '$' in v:
                return 'unknown', [a or b for a, b in VARIABLE.findall(v)] or [v]
            out.add(self.rel_real(os.path.join(base, os.path.expanduser(v))))
        return 'path', sorted(out)

    def spike_paths(self, value, bases, spike_roots):
        """[(token, resolved path)] for each path-like word in a manifest string that resolves under a spike root:
        words separated by white space, quotes, = , ; or :, with Xcode's project-directory variables replaced and a
        leading compiler or linker flag (-I, -L, -F ...) removed."""
        hits = []
        for base in bases:
            text = PROJECT_DIR_VARS.sub(lambda _: base, value)
            for tok in re.split(r'[\s"\'=,;:]+', text):
                tok = re.sub(r'^-[A-Za-z_]+(?=[./~$])', '', tok)
                if '/' not in tok:
                    continue
                if '$' in tok:  # another variable: only a spike root named as a path component can be judged
                    if any(re.search(r'(^|/)' + re.escape(r.rstrip('/')) + r'(/|$)', tok, re.I) for r in spike_roots):
                        hits.append((tok, tok))
                    continue
                rel = self.rel_real(os.path.join(base, os.path.expanduser(tok)))
                if self.under_ci(rel, spike_roots):
                    hits.append((tok, rel))
        return sorted(set(hits))

    def check_symlinks(self, files, product_roots, spike_roots):
        """A symbolic link under Apps/ or Packages/ must stay inside them: the files it reaches would be built as
        product code without being checked as product code."""
        n = 0
        for f in files:
            if self.under(f, product_roots) and os.path.islink(self.path(f)):
                n += 1
                rel = self.rel_real(f)
                if self.under_ci(rel, spike_roots):
                    self.fail('spike-in-product', f, f'is a symbolic link to {rel}, under {"/".join(spike_roots)}, which is never shipped')
                elif not self.under_ci(rel, product_roots):
                    self.fail('outside-product', f, f"is a symbolic link to {rel}, outside {' and '.join(product_roots)}, so what it reaches is not checked as product code")
        self.note(f'symbolic links under the product roots: {n}')

    def check_modulemaps(self, files, product_roots, spike_roots):
        """A Clang module map under Apps/ or Packages/ can make a header importable as a module of any name, so the
        headers, umbrella directories and libraries it names are held to the rules for product code. Every module map
        there is product code, whichever target's directory holds it, because product code can import the modules it
        defines from anywhere (review R3-01); so is a file that a shipping target names as a module map (MODULEMAP_FILE,
        -fmodule-map-file=) or that a module map names as an extern module, whatever the file is called."""
        queue = [f for f in files if self.under(f, product_roots) and os.path.isfile(self.path(f))
                 and (f.endswith('.modulemap') or os.path.basename(f) == 'module.map')]
        queue += sorted(f for f, kinds in self.named_files.items() if 'modulemap-file' in kinds)
        done = set()
        while queue:
            f = queue.pop(0)
            if f in done:
                continue
            done.add(f)
            full = self.path(f)
            test = False
            here = [os.path.dirname(full)]
            reported = set()
            for raw, line_of in c_variants(open(full, encoding='utf-8', errors='replace').read()):
                # Any header name in the raw text, so that no comment or literal can hide one from the check.
                for m in HEADER_WORD.finditer(raw):
                    hit = self.banned_headers.get(m.group(0).casefold())
                    where = f'{f}:{line_of(m.start())}'
                    if hit and not test and (where, m.group(0)) not in reported:
                        reported.add((where, m.group(0)))
                        self.fail('transitive-direct', where, f"names {m.group(0)}, a public header of {hit[1]['name']}, which product code may use only through the package that brings it (found in the raw text: a comment that names it counts)")
                text = c_code(raw, keep_strings=True)
                items = [dict(kind='include', value=m.group(1), bases=here, where=f'{f}:{line_of(m.start())}', spike=True)
                         for m in MODULEMAP_PATHS.finditer(text)]
                items += [dict(kind='framework' if m.group(1) else 'library', value=m.group(2), bases=[],
                               where=f'{f}:{line_of(m.start())}', spike=True) for m in MODULEMAP_LINKS.finditer(text)]
                # An extern module's map is read as a module map too (its own path is judged with the items above).
                for m in EXTERN_MODULE.finditer(text):
                    how, found = self.resolve_setting(m.group(1), here)
                    for path in found if how == 'path' else []:
                        named = self.tracked_file(path)
                        if named and self.under_ci(named, product_roots):
                            queue.append(named)
                for item in items:
                    if (item['kind'], item['value'], item['where']) not in reported:  # each once, whatever the variant
                        reported.add((item['kind'], item['value'], item['where']))
                        self.judge(f, item, test, product_roots, spike_roots)
        self.note(f'module maps read as product code: {len(done)}')

    def check_xcode_projects(self, files):
        """ADR-0002 commits each project's project.yml, never the Xcode project or workspace generated from it. One that
        is committed anyway would be read by Xcode with its own package references, requirements, build settings and
        lock, none of which this check reads (review R3-04), so any tracked file inside one fails, wherever it is."""
        bundles = {}
        for f in files:
            parts = f.split('/')
            for i, p in enumerate(parts):
                if p.casefold().endswith(('.xcodeproj', '.xcworkspace')):
                    bundles.setdefault('/'.join(parts[:i + 1]), []).append(f)
                    break
        for bundle, members in sorted(bundles.items()):
            kind = 'workspace' if bundle.casefold().endswith('.xcworkspace') else 'project'
            self.fail('xcode-project', bundle, f"is a committed Xcode {kind} ({len(members)} tracked file(s)): ADR-0002 commits only project.yml, and the package references, requirements, build settings and lock inside it are not checked. Remove it from the index; sylvia_generate writes it from project.yml")
        self.note(f'committed Xcode projects or workspaces: {len(bundles)}')

    def check_license_texts(self, packages, tracked):
        n = 0
        for p in packages:
            read_at = p['license'].get('read_at')
            if read_at != p['revision']:
                self.fail('license-text', INVENTORY, f"{p['name']}: license data were read at {read_at}, but the package is pinned at {p['revision']}; read them again at the pinned revision (ADR-0014 update procedure, step 4)")
            for f in p['license'].get('files') or []:
                text = f.get('text', '')
                n += 1
                if text not in tracked:
                    self.fail('license-text', text or INVENTORY, f"{p['name']}: license text copy is not committed")
                elif sha256_file(self.path(text)) != f.get('sha256'):
                    self.fail('license-text', text, f"{p['name']}: differs from {f.get('path')} at the pinned revision (sha256 {f.get('sha256')})")
            for b in p.get('bundled') or []:
                for text in [t.strip() for t in (b.get('text') or '').split(';') if t.strip()]:
                    n += 1
                    if text not in tracked:
                        self.fail('license-text', text, f"{p['name']}: the text for bundled {b.get('component', '?')[:40]!r} is not committed")
        self.note(f'license texts: {n} checked')

    def check_acknowledgements(self, inv, tracked):
        ack = inv.get('acknowledgements')
        if not ack:
            return
        try:
            expected = render_acknowledgements(self.root, inv)
        except (OSError, KeyError, ValueError) as e:
            self.fail('docs', ack.get('draft', INVENTORY), f'cannot generate the acknowledgements draft: {e}')
            return
        draft = ack.get('draft', '')
        if draft not in tracked or open(self.path(draft), encoding='utf-8').read() != expected:
            self.fail('docs', draft, 'acknowledgements draft is out of date: run Scripts/check-dependency-lock.py acknowledgements --write')
        else:
            self.note(f'acknowledgements draft: matches the inventory ({len(expected)} characters)')

    def check_product_sources(self, files, product_roots, spike_roots):
        """Product code (not tests) must not reach a module of a package the inventory admits only as transitive: such
        a module is in the build graph, so the compiler would accept the import (for example `import Zip`, whose
        unzipFile has an unfixed path-traversal advisory, ADR-0014). The scan reads the raw text (swift_import_hits,
        c_imports). No product file, test or not, may include a file under Spikes/. And a target that is not a test
        target must not build a file from a test-named directory (test code is decided by target membership)."""
        modules, headers = self.banned_modules, self.banned_headers

        def banned(where, name, what):
            hit = modules.get(name.casefold())
            if hit:
                self.fail('transitive-direct', where, f"imports {hit[0]}{what}, a module of {hit[1]['name']}, which product code may use only through the package that brings it (found in the raw text: a comment or string literal that names the import counts)")

        swift_n = c_n = 0
        named = {f for f, kinds in self.named_files.items() if 'header-file' in kinds}
        for f in files:
            full = self.path(f)
            if not self.under(f, product_roots) or not os.path.isfile(full):
                continue
            test = self.is_test_file(f)
            if f in named or f.lower().endswith(C_HEADER_EXTENSIONS):
                # A header is product code wherever it sits, since any product file can include it; so is a file that a
                # shipping target includes into every file (-include, a prefix or bridging header), whatever its name
                # (review R3-01).
                test = False
            shipping = [(manifest, target) for is_test, manifest, target in self.owners(f) if not is_test]
            if shipping and in_test_named_dir(f):
                self.fail('test-layout', f, f"target {shipping[0][1]} ({shipping[0][0]}) is not a test target but builds this file, which sits in a directory named Tests or ending in Tests; rename the directory or move the file to a test target")
            if f.endswith('.swift'):
                if test:
                    continue
                swift_n += 1
                for name, line in swift_import_hits(open(full, encoding='utf-8', errors='replace').read()):
                    banned(f'{f}:{line}', name, '')
            elif f.lower().endswith(C_EXTENSIONS) or f in named:
                c_n += 0 if test else 1
                for kind, name, line in c_imports(open(full, encoding='utf-8', errors='replace').read()):
                    where = f'{f}:{line}'
                    if kind in ('include', 'include<'):
                        rel = self.rel_real(os.path.join(os.path.dirname(f), name))
                        if self.under_ci(rel, spike_roots):
                            self.fail('spike-in-product', where, f'includes {name}, which resolves to {rel} under {"/".join(spike_roots)}; Spikes code is never shipped')
                        elif not test:
                            self.judge_include(where, f, name, kind == 'include<', product_roots)
                    elif test:
                        continue
                    elif kind == 'computed-include':
                        self.fail('outside-product', where, f"{name}: a computed include, whose file macros decide, so this check cannot tell which file it brings in (review R4-02). Write the file's name out, as \"...\" or <...>, where the include rules can judge it")
                    elif kind == 'module':
                        banned(where, name, '')
                    elif kind == 'framework':
                        banned(where, name, f' (a path into it: {name}/...)')
                    elif kind == 'header':
                        hit = headers.get(name.casefold())
                        if hit:
                            self.fail('transitive-direct', where, f"names {name}, a public header of {hit[1]['name']}, which product code may use only through the package that brings it (found in the raw text: any include of it, or a comment or literal that names it)")
        self.note(f'product sources: {swift_n} Swift and {c_n} C-family files checked for imports of transitive-only modules')

    def check_binaries(self, inv, files, product_roots):
        """Third-party binaries entering a product target must be inventoried like packages."""
        entries = self.binaries_inv
        used = set(self.linked_used)

        def find(**want):
            for i, b in enumerate(entries):
                if all(b.get(k) == v for k, v in want.items()):
                    return i, b
            return None, None

        for b in self.product_binaries:
            if b['kind'] == 'binaryTarget':
                i, e = find(kind='binaryTarget', manifest=b['manifest'], name=b['name'])
                what = f"binary target {b['name']}"
                ok = e is not None and (e.get('url') == b['url'] and e.get('checksum') == b['checksum'] if b['url'] else
                                        e.get('path') == b['path'] and os.path.exists(self.path(b['path'] or ''))
                                        and tree_sha256(self.path(b['path'])) == e.get('sha256'))
            elif b['kind'] == 'carthage':
                i, e = find(kind='carthage', manifest=b['manifest'], name=b['name'])
                what, ok = f"Carthage dependency {b['name']} of target {b['target']}", e is not None
            else:
                i, e = find(kind=b['kind'], manifest=b['manifest'], path=b['path'])
                what = f"{b['kind']} dependency {b['path']} of target {b['target']}"
                ok = e is not None and os.path.exists(self.path(b['path'])) and tree_sha256(self.path(b['path'])) == e.get('sha256')
            if e is not None:
                used.add(i)
            if not ok:
                self.fail('binary', b['manifest'], f'{what} is third-party binary code that the inventory does not list'
                          + (' with this URL and checksum, or digest' if e is not None else '') + ' (binaries)')
        committed = 0
        for f in files:
            full = self.path(f)
            if not self.under(f, product_roots) or os.path.islink(full) or not os.path.isfile(full):
                continue
            with open(full, 'rb') as fh:
                head = fh.read(8)
            parts = f.split('/')
            kind = ('Mach-O file' if head[:4] in MACHO_MAGIC else 'static library' if head == AR_MAGIC else
                    'framework file' if any(x.endswith(BINARY_DIR_EXT) for x in parts[:-1]) else
                    'library file' if f.endswith(BINARY_FILE_EXT) else None)
            if kind is None:
                continue
            committed += 1
            # A `file` entry lists one committed file by path and digest; a framework, bundle or local binary target
            # entry lists everything inside its directory (its digest is checked as a tree above).
            listed = [(i, e) for i, e in enumerate(entries) if e.get('kind') == 'file' and e.get('path') == f]
            inside = [(i, e) for i, e in enumerate(entries) if e.get('kind') != 'file' and e.get('path')
                      and f.startswith(e['path'].rstrip('/') + '/')]
            used.update(i for i, _ in listed + inside)
            if listed and sha256_file(full) != listed[0][1].get('sha256'):
                self.fail('binary', f, f"a committed {kind} whose digest differs from the inventory's (binaries)")
            elif not listed and not inside:
                self.fail('binary', f, f'a committed {kind} under {" or ".join(product_roots)} that the inventory does not list (binaries)')
        for i, e in enumerate(entries):
            if i not in used:
                self.fail('binary', INVENTORY, f"binaries entry {e.get('kind')} {e.get('name') or e.get('path')} is stale: nothing in a product manifest or under {' or '.join(product_roots)} matches it")
        self.note(f'binaries: {len(self.product_binaries)} declared by product manifests, {committed} committed under the product roots, {len(entries)} inventoried')

    def check_vendored(self, inv, files, tracked, product_roots):
        listed = {a.get('path'): a for a in inv.get('vendored_assets', [])}
        for path, a in listed.items():
            if path not in tracked:
                self.fail('vendored-asset', path, 'listed in the inventory but not committed')
            elif sha256_file(self.path(path)) != a.get('sha256'):
                self.fail('vendored-asset', path, f"digest {sha256_file(self.path(path))} differs from the inventory's {a.get('sha256')}")
        for f in files:
            name = os.path.basename(f)
            if self.under(f, product_roots) and (name.lower().endswith(FONT_EXT) or is_license_name(name)) and f not in listed:
                self.fail('vendored-asset', f, 'a font or license file under Apps/ or Packages/ that the inventory does not list')
        self.note(f'vendored assets: {len(listed)} listed')

    def check_python(self, inv, toolchain):
        tools = inv.get('python_tools', {})
        want = {norm_py(p['name']): p['version'] for p in tools.get('packages', [])}
        req = tools.get('requirements', REQUIREMENTS)
        try:
            lines = open(self.path(req), encoding='utf-8').read().splitlines()
        except OSError:
            self.fail('python-tools', req, 'requirements file missing')
            return
        have = {}
        for n, line in enumerate(lines, 1):
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            m = re.match(r'^([A-Za-z0-9][A-Za-z0-9._-]*)==([0-9][^\s;]*)$', line)
            if not m:
                self.fail('not-exact', f'{req}:{n}', f'{line!r} is not an exact name==version pin')
                continue
            have[norm_py(m.group(1))] = m.group(2)
        for name in sorted(set(want) | set(have)):
            if want.get(name) != have.get(name):
                self.fail('python-tools', req, f'{name}: requirements {have.get(name)}, inventory {want.get(name)}')
        # An unpinned distribution (the virtualenv's installer, pip) has no exact version to compare: a new virtualenv
        # holds what its Python bundles (review R2-01: 26.1.2 with Python 3.14.6). It must be present, at any version.
        # Below the minimum the inventory records (the first release outside every advisory found for it) the check
        # warns without failing, because no tracked file decides that version (ADR-0014 section 3).
        unpinned = {}
        for p in tools.get('unpinned', []):
            if not all(str(p.get(k) or '').strip() for k in ('name', 'version', 'minimum', 'minimum_why', 'why', 'owner', 'fix')):
                self.fail('inventory', INVENTORY, f'python_tools.unpinned entry {p!r} needs a name, version, minimum, minimum_why, why, owner and fix')
            elif version_key(p['minimum']) is None:
                self.fail('inventory', INVENTORY, f"python_tools.unpinned entry {p['name']}: minimum {p['minimum']!r} is not a version")
            elif norm_py(p['name']) in have:
                self.fail('inventory', INVENTORY, f"python_tools.unpinned lists {p['name']}, which {req} pins; move it to packages")
            else:
                unpinned[norm_py(p['name'])] = p
        floors = ', '.join(f"{n} at any version, with a warning below {p['minimum']}" for n, p in sorted(unpinned.items()))
        note = f'python tools: {len(have)} pinned' + (f', {len(unpinned)} recorded as unpinned ({floors})' if unpinned else '')
        if toolchain:
            installed = self.distributions()
            if installed is None:
                self.fail('toolchain', sys.executable, 'not running in a virtualenv: run the check with sylvia_python, so that the tools virtualenv is compared with the inventory')
            else:
                failed = len(self.failures)
                for name, version in sorted(want.items()):
                    if installed.get(name) != version:
                        self.fail('toolchain', 'virtualenv', f'virtualenv has {name} {installed.get(name)}, inventory {version}')
                found = []
                for name, p in sorted(unpinned.items()):
                    have_version = installed.get(name)
                    if have_version is None:
                        self.fail('toolchain', 'virtualenv', f"virtualenv lacks {name}, which the inventory records as unpinned (python_tools.unpinned)")
                        continue
                    key = version_key(have_version)
                    unpinned_why = f"nothing in the repository pins {name}; {p['fix']}"
                    if key is None:
                        self.warn('toolchain', 'virtualenv', f"{name} {have_version} is not a version this check can compare with {p['minimum']}, the first release outside every advisory the inventory records for it ({p['minimum_why']}); {unpinned_why}")
                        found.append(f'{name} {have_version} (not compared: see the warning)')
                    elif key < version_key(p['minimum']):
                        self.warn('toolchain', 'virtualenv', f"{name} {have_version} is below {p['minimum']}, the first release outside every advisory the inventory records for it ({p['minimum_why']}); {unpinned_why}")
                        found.append(f"{name} {have_version}, below {p['minimum']} (see the warning)")
                    else:
                        found.append(f'{name} {have_version}')
                for name in sorted(set(installed) - set(want) - set(unpinned)):
                    self.fail('toolchain', 'virtualenv', f'virtualenv holds {name} {installed[name]}, which the inventory does not record (python_tools)')
                if len(self.failures) == failed:  # only when every comparison above held
                    note += '; the virtualenv holds exactly these' + (f" ({', '.join(found)})" if found else '')
        self.note(note)

    def check_actions(self, inv, files):
        want = {a.get('uses'): a for a in inv.get('ci_actions', [])}
        used = set()
        for f in files:
            if f.startswith('.github/workflows/') and f.endswith(('.yml', '.yaml')):
                for n, line in enumerate(open(self.path(f), encoding='utf-8').read().splitlines(), 1):
                    m = re.match(r'^\s*(?:-\s*)?uses:\s*["\']?([^"\'\s#]+)', line)
                    if not m or m.group(1).startswith(('./', 'docker://')):
                        continue
                    uses = m.group(1)
                    used.add(uses)
                    entry = want.get(uses)
                    if entry is None:
                        self.fail('ci-actions', f'{f}:{n}', f'{uses} is not in the inventory (ci_actions)')
                        continue
                    ref = uses.rsplit('@', 1)[1] if '@' in uses else ''
                    if not REV.match(ref):
                        exempt = entry.get('pinned_to_commit') is False and (entry.get('reason') or '').strip() and (entry.get('owner') or '').strip()
                        if not exempt:
                            self.fail('not-exact', f'{f}:{n}', f'{uses} is on the movable reference {ref or "(none)"!r}, not a commit; pin it to a commit or record a reasoned exemption (pinned_to_commit false, reason, owner) in the inventory')
                    elif entry.get('pinned_to_commit') is not True:
                        self.fail('ci-actions', INVENTORY, f'{uses} is pinned to a commit, but the inventory does not say so (pinned_to_commit)')
        for uses in want:
            if uses not in used:
                self.fail('ci-actions', INVENTORY, f'{uses} is listed but no workflow uses it')
        exempt = sorted(u for u in used if u in want and not REV.match(u.rsplit('@', 1)[-1])
                        and want[u].get('pinned_to_commit') is False and (want[u].get('reason') or '').strip())
        self.note(f'workflow actions: {len(used)} used' + (f'; on a tag under a recorded exemption: {", ".join(exempt)}' if exempt else ''))

    def check_toolchain(self, inv, toolchain):
        tc = inv.get('toolchain', {})
        build = tc.get('xcode', {}).get('build')
        version = tc.get('xcode', {}).get('version')
        try:
            env = open(self.path(ENV_SH), encoding='utf-8').read()
            m = re.search(r'SYLVIA_XCODE_BUILD_PINNED="([^"]+)"', env)
            if not m or m.group(1) != build:
                self.fail('toolchain', ENV_SH, f'SYLVIA_XCODE_BUILD_PINNED is {m.group(1) if m else None!r}, inventory {build!r}')
        except OSError:
            self.fail('toolchain', ENV_SH, 'missing')
        self.check_pin_records(version, build)
        if not toolchain:
            return
        # Each value is compared whole, on the line of the tool's output that states it: a search for the expected text
        # passed a build that only extends the pin ("Build version 27A9275a" contains "Build version 27A9275"), and the
        # failure named the output's first line rather than the build (review TC-02).
        runs = [(['xcodebuild', '-version'], 'Build version ', build),
                (self.swift + ['--version'], 'Swift version ', tc.get('swift')),
                (['xcodegen', '--version'], 'Version: ', tc.get('xcodegen'))]
        for cmd, label, pinned in runs:
            expected = f'{label}{pinned}'
            try:
                out = self.run_tool(cmd)
            except OSError as e:
                self.fail('toolchain', ' '.join(cmd), f'cannot run: {e}')
                continue
            lines = [line.strip() for line in out.splitlines() if line.strip()]
            stated = [line[line.index(label):] for line in lines if label in line]
            if not stated or any(s != expected for s in stated):
                got = next((s for s in stated if s != expected), lines[0] if lines else '(no output)')
                self.fail('toolchain', ' '.join(cmd), f'expected {expected!r}, got {got!r}')
            else:
                self.note(f'toolchain: {" ".join(cmd)} -> {stated[0]} (the pin, compared whole)')

    def check_pin_records(self, version, build):
        """The Xcode pin as the workflow's guard, CLAUDE.md's toolchain line and ADR-0001's toolchain table state it must
        be the inventory's: ADR-0001 records the pin in those three, the inventory and Scripts/lib/env.sh, and changes
        them together, and until review TC-08 only env.sh was compared, so a re-pin that missed the workflow's guard
        passed every local check. The workflow's comment lines are history and are not read."""
        def read(rel):
            try:
                return open(self.path(rel), encoding='utf-8').read()
            except OSError:
                return ''

        workflow = '\n'.join(line for line in read(WORKFLOW).splitlines() if not line.lstrip().startswith('#'))
        guard = re.findall(r'Build version ([^"\'\s]+)', workflow)
        records = [
            (WORKFLOW, 'Xcode guard line ("Build version <build>")', bool(guard),
             [('the guard looks for', f'Build version {b}', f'Build version {build}') for b in guard]
             + [('a candidate Xcode is', f'Xcode_{v}.app', f'Xcode_{version}.app')
                for v in re.findall(r'/Applications/Xcode_([^/\s"\']+)\.app', workflow)]
             + [('the text names', f'Xcode {v} ({b})', f'Xcode {version} ({build})')
                for v, b in re.findall(r'\bXcode (\d+(?:\.\d+)+) \(([0-9A-Za-z]+)\)', workflow)]),
            (CLAUDE_MD, 'toolchain line ("- Xcode <version> (<build>)")', None,
             [('the toolchain line names', f'Xcode {v} ({b})', f'Xcode {version} ({build})')
              for v, b in re.findall(r'^- Xcode (\S+) \(([^)\s]+)\)', read(CLAUDE_MD), re.M)]),
            (ADR_0001, 'toolchain table row ("| Xcode | <version>, build <build>")', None,
             [('the toolchain table names', f'{v.strip()}, build {b}', f'{version}, build {build}')
              for v, b in re.findall(r'^\| Xcode \| ([^,|]+), build ([^\s(|,]+)', read(ADR_0001), re.M)]),
        ]
        agreed = []
        for rel, what, present, pairs in records:
            if not (pairs if present is None else present):
                self.fail('toolchain', rel, f'has no {what}, so its record of the Xcode pin cannot be compared with the inventory')
                continue
            wrong = [(how, seen, want) for how, seen, want in pairs if seen != want]
            for how, seen, want in wrong:
                self.fail('toolchain', rel, f'{how} {seen!r}; the inventory pins {want!r} (ADR-0001: every record of the pin changes with it)')
            if not wrong:
                agreed.append(rel)
        if agreed:
            self.note(f'toolchain: the Xcode pin {version} ({build}) as stated in ' + ', '.join(agreed))

    def check_docs(self, packages):
        def token(s):  # s as a whole token: "apple/swift-nio" does not match "apple/swift-nio-ssl", nor 1.0.0 match 1.0.0.1
            return re.compile(r'(?<![\w./@-])' + re.escape(s) + r'(?![\w/@-]|\.\w)')

        for rel, need_rev in ((HUMAN, True), (ADR, False)):
            try:
                text = open(self.path(rel), encoding='utf-8').read().splitlines()
            except OSError:
                self.fail('docs', rel, 'missing')
                continue
            for p in packages:
                parts = [p['name'], p['version']] + ([p['revision'][:12]] if need_rev else [])
                patterns = [token(x) for x in parts]
                if not any(all(rx.search(line) for rx in patterns) for line in text):
                    self.fail('docs', rel, f"no line names {' '.join(parts)}")


def used_by_report(root):
    """{package name: used_by_targets list} as the manifests declare it (for writing the inventory's used_by_targets)."""
    c = Checker(root)
    inv = json.load(open(c.path(INVENTORY), encoding='utf-8'))
    c.run()
    out = {}
    for p in c.check_inventory(inv, set(c.files())):
        groups = {}
        for manifest, target, product, test in sorted(getattr(c, 'used', {}).get(p['_norm'], set())):
            groups.setdefault((manifest, target, test), []).append(product)
        out[p['name']] = [{'manifest': m, 'target': t, 'products': sorted(prods), 'test': test}
                          for (m, t, test), prods in sorted(groups.items())]
    return out


# ----- acknowledgements draft -------------------------------------------------------------------------------------
def fenced(text):
    """text in a code fence longer than any run of backticks inside it."""
    longest = max((len(m.group(0)) for m in re.finditer(r'`+', text)), default=0)
    fence = '`' * max(3, longest + 1)
    return f'{fence}text\n{text.rstrip()}\n{fence}\n'


def npm_table(text):
    """The combined npm license file -> one table row per package: name, version, license, copyright lines."""
    rows = []
    for block in text.split('\n==== ')[1:]:
        spec, _, rest = block.partition('\n')
        name, version = spec.rsplit('@', 1)
        body = rest.split('\n\n', 1)[1] if '\n\n' in rest else ''
        kind = ('MIT' if 'Permission is hereby granted, free of charge' in body else
                'Apache-2.0' if 'Apache License' in body else 'see text')
        lines = [' '.join(l.split()) for l in body.splitlines() if re.match(r'\s*copyright\s*(\(c\)|©|\d)', l, re.I)]
        rows.append(f"| {name} | {version} | {kind} | {'; '.join(lines) or '(none in the file)'} |")
    return rows


def render_acknowledgements(root, inv):
    ack = inv['acknowledgements']

    def read(rel):
        return open(os.path.join(root, rel), encoding='utf-8').read()

    out = ['# Acknowledgements (draft)', '',
           '<!-- Generated by `Scripts/check-dependency-lock.py acknowledgements --write` from Docs/Licenses/inventory.json '
           'and the texts under Docs/Licenses/texts. Do not edit by hand; CI fails when this file differs from the output. -->',
           '']
    out += [ack['preamble'], '']
    for product in ack['products']:
        out += [f"## {product['title']}", '', product['basis'], '']
        for e in product['entries']:
            out += [f"### {e['name']}" + (f" {e['version']}" if e.get('version') else ''), '']
            out += [f"{e['url']} · {e['license']}" if e.get('url') else e['license'], '']
            if e.get('note'):
                out += [e['note'], '']
            if e.get('pending'):
                out += [f"**Pending (not yet decided):** {e['pending']}", '']
            for rel in e.get('texts', []):
                out += [fenced(read(rel))]
            for rel in e.get('notices', []):
                out += ['NOTICE:', '', fenced(read(rel))]
            if e.get('apache'):
                out += ['Licensed under the Apache License, Version 2.0; the full text is at the end of this document.', '']
            if e.get('npm'):
                text = read(e['npm'])
                out += ['| Package | Version | License | Copyright |', '| --- | --- | --- | --- |'] + npm_table(text) + ['']
                blocks = text[text.index('\n==== ') + 1:] if '\n==== ' in text else text  # without the file's header
                out += ["Each package's license file, as published in that version:", '', fenced(blocks)]
    out += ['## Apache License 2.0', '', fenced(read(ack['apache_text']))]
    return '\n'.join(out).rstrip('\n') + '\n'


# ----- self-test --------------------------------------------------------------------------------------------------
SELFTEST_TOOLCHAIN = '.selftest/toolchain.json'  # the synthetic tree's fake toolchain (versions, virtualenv)
BASE_FILES = {
    'Docs/Licenses/texts/a/LICENSE': 'A license\n',
    'Docs/Licenses/texts/b/LICENSE': 'B license\n',
    'Docs/Licenses/texts/t/LICENSE': 'T license\n',
    'Docs/Licenses/texts/x/LICENSE': 'X license\n',
    'Docs/Licenses/texts/s/LICENSE': 'S license\n',
    'Packages/Good/Package.swift': '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Good",
    dependencies: [
        .package(url: "https://example.com/acme/A.git", exact: "1.0.0"),
        .package(url: "https://example.com/acme/T.git", exact: "3.0.0"),
    ],
    targets: [
        .target(name: "Good", dependencies: [.product(name: "A", package: "A")]),
        .testTarget(name: "GoodTests", dependencies: ["Good", .product(name: "T", package: "T")]),
    ]
)
''',
    'Packages/Good/Package.resolved': None,  # written from the pins below
    'Packages/Good/Sources/Good/Good.swift': 'import Foundation\npublic struct Good {}\n',
    'Packages/Good/Sources/Good/Fonts/Face.ttf': 'not really a font\n',
    'Packages/Good/Sources/Good/Fonts/OFL.txt': 'OFL\n',
    'Spikes/S/Package.swift': '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "S",
    dependencies: [.package(url: "https://example.com/acme/S.git", exact: "5.0.0")],
    targets: [.target(name: "S", dependencies: [.product(name: "S", package: "S")])]
)
''',
    'Spikes/S/Package.resolved': None,
    'Spikes/S/Sources/S/S.swift': 'public struct S {}\n',
    'Spikes/S/include/s.h': 'int s(void);\n',
    'Spikes/Probe/project.yml': 'name: Probe\npackages:\n  Local:\n    path: ../S\ntargets:\n  Probe:\n    type: application\n    platform: iOS\n    dependencies:\n      - package: Local\n        product: S\n',
    'Apps/App/project.yml': 'name: App\npackages:\n  Good:\n    path: ../../Packages/Good\n  A:\n    url: https://example.com/acme/A.git\n    exactVersion: 1.0.0\ntargets:\n  App:\n    type: application\n    platform: iOS\n    sources:\n      - path: Sources\n    dependencies:\n      - package: Good\n        product: Good\n      - package: A\n        product: A\n',
    'Apps/App/Package.resolved': None,
    'Apps/App/Sources/App.swift': 'import Good\n',
    'Fixtures/sample.txt': 'fixture\n',
    'Scripts/tools/requirements.txt': '# pinned\nalpha==1.0\nBeta_Pkg==2.0.1\n',
    'Scripts/lib/env.sh': 'export SYLVIA_XCODE_BUILD_PINNED="27A266a"\n',
    # The workflow's Xcode guard, CLAUDE.md's toolchain line and ADR-0001's table: the other records of the Xcode pin
    # (review TC-08). The comment names an earlier pin, which the check must not read.
    '.github/workflows/ci.yml': ('jobs:\n  ci:\n    steps:\n'
                                 '      # Xcode 26.0 (17A100), the pin before (a comment: history, not read)\n'
                                 '      - run: for c in /Applications/Xcode_27.0.app /Applications/Xcode.app; do '
                                 'DEVELOPER_DIR="$c/Contents/Developer" xcodebuild -version | grep -qx "Build version 27A266a" && exit 0; '
                                 'done; echo "::error::Xcode 27.0 (27A266a) is not installed"; exit 1\n'
                                 '      - uses: actions/checkout@v4\n'),
    'CLAUDE.md': '# Synthetic\n\n## Toolchain\n\n- Xcode 27.0 (27A266a), Swift 9.9 (self-test)\n- Xcode targets come from a project.yml\n',
    'Docs/ADRs/0001-platform-baseline-and-toolchain.md': '| Item | Pinned value |\n| --- | --- |\n| Xcode | 27.0, build 27A266a (self-test) |\n',
    'Docs/Licenses/third-party-inventory.md': None,
    'Docs/ADRs/0014-dependency-lock-and-license-inventory.md': None,
}
PKGS = {  # name: (url, identity, version, revision, role)
    'acme/A': ('https://example.com/acme/A.git', 'a', '1.0.0', 'a' * 40, 'product'),
    'acme/B': ('https://example.com/acme/B.git', 'b', '2.0.0', 'b' * 40, 'product-transitive'),
    'acme/T': ('https://example.com/acme/T.git', 't', '3.0.0', 'c' * 40, 'test'),
    'acme/X': ('https://example.com/acme/X.git', 'x', '4.0.0', 'd' * 40, 'test'),
    'acme/S': ('https://example.com/acme/S.git', 's', '5.0.0', 'e' * 40, 'spike'),
}
LOCKS = {'Packages/Good/Package.resolved': ['acme/A', 'acme/B', 'acme/T', 'acme/X'],
         'Apps/App/Package.resolved': ['acme/A', 'acme/B', 'acme/T', 'acme/X'],
         'Spikes/S/Package.resolved': ['acme/S']}
USED_BY = {
    'acme/A': [{'manifest': 'Apps/App/project.yml', 'target': 'App', 'products': ['A'], 'test': False},
               {'manifest': 'Packages/Good/Package.swift', 'target': 'Good', 'products': ['A'], 'test': False}],
    'acme/T': [{'manifest': 'Packages/Good/Package.swift', 'target': 'GoodTests', 'products': ['T'], 'test': True}],
    'acme/S': [{'manifest': 'Spikes/S/Package.swift', 'target': 'S', 'products': ['S'], 'test': False}],
}
FAKE_TOOLCHAIN = {'xcodebuild': 'Xcode 27.0\nBuild version 27A266a\n',
                  'swift': 'Apple Swift version 9.9 (synthetic-9.9)\nTarget: arm64-apple-macosx26.0\n',
                  'xcodegen': 'Version: 9.9.9\n',
                  'venv': {'alpha': '1.0', 'beta-pkg': '2.0.1', 'pip': '26.2.1'}}


def write_base(root):
    def write(rel, text):
        os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
        with open(os.path.join(root, rel), 'w', encoding='utf-8') as f:
            f.write(text)

    for rel, text in BASE_FILES.items():
        if text is not None:
            write(rel, text)
    for rel, names in LOCKS.items():
        pins = [{'identity': PKGS[n][1], 'kind': 'remoteSourceControl', 'location': PKGS[n][0],
                 'state': {'revision': PKGS[n][3], 'version': PKGS[n][2]}} for n in names]
        write(rel, json.dumps({'originHash': '0' * 64, 'pins': pins, 'version': 3}, indent=2))
    write(SELFTEST_TOOLCHAIN, json.dumps(FAKE_TOOLCHAIN, indent=2))
    rows = [f'| {n} | {v[2]} | `{v[3][:12]}` |' for n, v in PKGS.items()]
    write(HUMAN, '\n'.join(rows) + '\n')
    write(ADR, '\n'.join(f'| {n} | {v[2]} |' for n, v in PKGS.items()) + '\n')
    direct = {'acme/A': ['Packages/Good/Package.swift', 'Apps/App/project.yml'], 'acme/T': ['Packages/Good/Package.swift'],
              'acme/S': ['Spikes/S/Package.swift']}
    inv = {
        'schema_version': 1,
        'roots': {'product': ['Apps', 'Packages'], 'spike': ['Spikes']},
        'toolchain': {'xcode': {'version': '27.0', 'build': '27A266a'}, 'swift': '9.9 (synthetic-9.9)', 'xcodegen': '9.9.9'},
        'locks': [{'path': p, 'manifest': p.replace('Package.resolved', 'project.yml' if p.startswith('Apps') else 'Package.swift')} for p in LOCKS],
        'unlocked': [{'manifest': 'Spikes/Probe/project.yml', 'reason': 'local package only (self-test)'}],
        'packages': [{'name': n, 'url': v[0], 'identity': v[1], 'version': v[2], 'revision': v[3], 'role': v[4],
                      'platforms': ['iOS', 'macOS'], 'direct_in': direct.get(n, []), 'used_by_targets': USED_BY.get(n, []),
                      'locks': [l for l, ns in LOCKS.items() if n in ns],
                      'license': {'id': 'MIT', 'read_at': v[3],
                                  'files': [{'path': 'LICENSE', 'text': f'Docs/Licenses/texts/{v[1]}/LICENSE',
                                             'sha256': hashlib.sha256(BASE_FILES[f'Docs/Licenses/texts/{v[1]}/LICENSE'].encode()).hexdigest()}]}}
                     for n, v in PKGS.items()],
        'binaries': [],
        'vendored_assets': [{'path': p, 'sha256': hashlib.sha256(BASE_FILES[p].encode()).hexdigest()}
                            for p in ('Packages/Good/Sources/Good/Fonts/Face.ttf', 'Packages/Good/Sources/Good/Fonts/OFL.txt')],
        'python_tools': {'requirements': REQUIREMENTS, 'packages': [{'name': 'alpha', 'version': '1.0'}, {'name': 'beta-pkg', 'version': '2.0.1'}],
                         'unpinned': [{'name': 'pip', 'version': '26.2.1', 'minimum': '26.2.0', 'minimum_why': 'an advisory affects earlier versions (self-test)',
                                       'why': 'the installer (self-test)', 'owner': 'self-test', 'fix': 'pin it (self-test)'}]},
        'ci_actions': [{'uses': 'actions/checkout@v4', 'pinned_to_commit': False, 'reason': 'self-test exemption', 'owner': 'self-test'}],
        'acknowledgements': {
            'draft': 'Docs/Licenses/acknowledgements-draft.md', 'apache_text': 'Docs/Licenses/texts/b/LICENSE',
            'preamble': 'Synthetic draft (self-test).',
            'products': [{'title': 'App', 'basis': 'The synthetic app.', 'entries': [
                {'name': 'A', 'version': '1.0.0', 'url': 'https://example.com/acme/A', 'license': 'MIT', 'texts': ['Docs/Licenses/texts/a/LICENSE']},
                {'name': 'B', 'version': '2.0.0', 'license': 'Apache-2.0', 'apache': True}]}],
        },
    }
    b = next(p for p in inv['packages'] if p['name'] == 'acme/B')
    b['modules'], b['headers'] = ['BModule'], ['bmodule.h']
    write(INVENTORY, json.dumps(inv, indent=2))
    write(inv['acknowledgements']['draft'], render_acknowledgements(root, inv))


def edit(root, rel, old, new, count=1):
    p = os.path.join(root, rel)
    text = open(p, encoding='utf-8').read()
    if old not in text:
        raise AssertionError(f'self-test setup: {old!r} not in {rel}')
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text.replace(old, new, count))


def edit_json(root, rel, change):
    p = os.path.join(root, rel)
    d = json.load(open(p, encoding='utf-8'))
    change(d)
    with open(p, 'w', encoding='utf-8') as f:
        json.dump(d, f, indent=2)


def lock_pin(d, identity):
    return next(x for x in d['pins'] if x['identity'] == identity)


def inv_pkg(d, name):
    return next(p for p in d['packages'] if p['name'] == name)


def add_file(root, rel, text, mode='w'):
    os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
    with open(os.path.join(root, rel), mode, **({} if 'b' in mode else {'encoding': 'utf-8'})) as f:
        f.write(text)


def add_link(root, rel, target):
    os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
    os.symlink(target, os.path.join(root, rel))


def tool(root, change):
    edit_json(root, SELFTEST_TOOLCHAIN, change)


def swift_use(form):
    """A product source file whose only import of the transitive module is written in the given form."""
    return lambda r: add_file(r, 'Packages/Good/Sources/Good/Use.swift', form)


def c_use(name, text):
    return lambda r: add_file(r, f'Packages/Good/Sources/Good/{name}', text)


APP_SOURCES = '    sources:\n      - path: Sources\n'
APP_DEPS = '        product: A\n'
APP_YML = 'Apps/App/project.yml'
GOOD_SWIFT = 'Packages/Good/Package.swift'
GOOD_TARGET = '.target(name: "Good", dependencies: [.product(name: "A", package: "A")])'
GOOD_MODULEMAP = 'Packages/Good/Sources/Good/include/module.modulemap'


def good_settings(text):
    """The Good library target with more arguments (Swift source, such as linkerSettings: [...])."""
    return lambda r: edit(r, GOOD_SWIFT, GOOD_TARGET, GOOD_TARGET[:-1] + ', ' + text + ')')


def app_settings(text):
    """The App target with base build settings (YAML lines indented under `base:`)."""
    return lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '    settings:\n      base:\n' + text)


def app_project(text):
    """Top-level keys added to the App project (YAML), before its targets."""
    return lambda r: edit(r, APP_YML, 'targets:\n', text + 'targets:\n')


def app_config(text, included=None):
    """The App project uses Apps/App/Config/App.xcconfig (configFiles) with this text; `included` is an optional
    (file name, text) for a second file in the same directory that the first #includes."""
    def mutate(r):
        app_project('configFiles:\n  Debug: Config/App.xcconfig\n')(r)
        add_file(r, 'Apps/App/Config/App.xcconfig', text)
        if included:
            add_file(r, f'Apps/App/Config/{included[0]}', included[1])
    return mutate


def tree(*changes):
    """Several changes applied in order."""
    return lambda r: [change(r) for change in changes]


def app_declares_t(r):
    """The App project declares the test-only package T (for its test targets), and the inventory records that
    requirement as the update procedure asks, so that nothing but the rule under test is reported."""
    edit(r, APP_YML, 'exactVersion: 1.0.0\n', 'exactVersion: 1.0.0\n  T:\n    url: https://example.com/acme/T.git\n    exactVersion: 3.0.0\n')
    edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/T')['direct_in'].append(APP_YML))


def good_manifest(code, dependencies=None, path=None):
    """The Good package's manifest with Swift code after its import line, and the Good target's dependencies (a Swift
    expression) or path replaced (review R4-01's reasoning: a manifest that reads something besides its own text)."""
    def mutate(r):
        edit(r, GOOD_SWIFT, 'import PackageDescription\n', 'import PackageDescription\n' + code)
        target = GOOD_TARGET
        if dependencies:
            target = target.replace('[.product(name: "A", package: "A")]', dependencies)
        if path:
            target = target[:-1] + f', path: {path})'
        edit(r, GOOD_SWIFT, GOOD_TARGET, target)
    return mutate
MUTATIONS = [  # (what, category, a fragment of the message that only this rule writes, mutation)
    ('a lock pins another version', 'pin-differs', 'lock 1.0.1',
     lambda r: edit_json(r, 'Packages/Good/Package.resolved', lambda d: lock_pin(d, 'a')['state'].update(version='1.0.1'))),
    ('a lock pins another revision', 'pin-differs', 'lock 2.0.0 ' + 'f' * 40,
     lambda r: edit_json(r, 'Apps/App/Package.resolved', lambda d: lock_pin(d, 'b')['state'].update(revision='f' * 40))),
    ('a lock pin has another identity', 'pin-differs', "identity 'a2', inventory 'a'",
     lambda r: edit_json(r, 'Packages/Good/Package.resolved', lambda d: lock_pin(d, 'a').update(identity='a2'))),
    ('a lock pins one package twice', 'pin-differs', 'pins acme/X twice',
     lambda r: edit_json(r, 'Packages/Good/Package.resolved', lambda d: d['pins'].append(copy.deepcopy(lock_pin(d, 'x'))))),
    ('a lock pin is not a remote source-control pin', 'not-exact', "is 'localSourceControl'",
     lambda r: edit_json(r, 'Spikes/S/Package.resolved', lambda d: lock_pin(d, 's').update(kind='localSourceControl'))),
    ('a lock drops a pin the inventory lists', 'pin-missing', 'does not pin acme/X',
     lambda r: edit_json(r, 'Apps/App/Package.resolved', lambda d: d['pins'].remove(lock_pin(d, 'x')))),
    ('a manifest gains an inventoried exact requirement, but its lock was not re-resolved', 'pin-missing',
     'does not pin https://example.com/acme/A.git, which Spikes/S/Package.swift requires',
     lambda r: (edit(r, 'Spikes/S/Package.swift', '[.package(', '[.package(url: "https://example.com/acme/A.git", exact: "1.0.0"), .package('),
                edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A')['direct_in'].append('Spikes/S/Package.swift')))),
    ('a lock and the inventory both drop a pin the manifest requires', 'pin-missing',
     'does not pin https://example.com/acme/A.git, which Packages/Good/Package.swift requires',
     lambda r: (edit_json(r, 'Packages/Good/Package.resolved', lambda d: d['pins'].remove(lock_pin(d, 'a'))),
                edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A')['locks'].remove('Packages/Good/Package.resolved')))),
    ('a lock and the inventory drop a pin that a local package requires', 'pin-missing', 'through its local package Packages/Good',
     lambda r: (edit_json(r, 'Apps/App/Package.resolved', lambda d: d['pins'].remove(lock_pin(d, 't'))),
                edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/T')['locks'].remove('Apps/App/Package.resolved')))),
    ('a lock pins a package missing from the inventory', 'unknown-package', 'pins https://example.com/acme/Zed.git',
     lambda r: edit_json(r, 'Spikes/S/Package.resolved', lambda d: d['pins'].append(
         {'identity': 'zed', 'kind': 'remoteSourceControl', 'location': 'https://example.com/acme/Zed.git',
          'state': {'revision': '9' * 40, 'version': '9.0.0'}}))),
    ('a lock pins a branch', 'not-exact', 'pinned to main, not a version',
     lambda r: edit_json(r, 'Spikes/S/Package.resolved', lambda d: lock_pin(d, 's').update(state={'branch': 'main', 'revision': 'e' * 40}))),
    ('a manifest requires a package missing from the inventory', 'unknown-package', 'requires https://example.com/acme/Zed.git',
     lambda r: edit(r, 'Spikes/S/Package.swift', '[.package(', '[.package(url: "https://example.com/acme/Zed.git", exact: "9.0.0"), .package(')),
    ('a Package.swift requirement uses from:', 'not-exact', 'requirement range',
     lambda r: edit(r, 'Spikes/S/Package.swift', 'exact: "5.0.0"', 'from: "5.0.0"')),
    ('a Package.swift requirement uses branch:', 'not-exact', 'requirement branch',
     lambda r: edit(r, 'Packages/Good/Package.swift', 'exact: "1.0.0"', 'branch: "main"')),
    ('a Package.swift requirement uses revision:', 'not-exact', 'requirement revision',
     lambda r: edit(r, 'Packages/Good/Package.swift', 'exact: "1.0.0"', 'revision: "' + 'a' * 40 + '"')),
    ('a project.yml requirement uses from:', 'not-exact', 'requirement from from: 1.0.0',
     lambda r: edit(r, 'Apps/App/project.yml', 'exactVersion: 1.0.0', 'from: 1.0.0')),
    ('a project.yml requirement adds a range to an exact version', 'not-exact', 'requirement exactVersion+maxVersion',
     lambda r: edit(r, 'Apps/App/project.yml', 'exactVersion: 1.0.0', 'exactVersion: 1.0.0\n    maxVersion: 2.0.0')),
    ('a project.yml version YAML reads as a number', 'not-exact', 'requirement unquoted',
     lambda r: edit(r, 'Apps/App/project.yml', 'exactVersion: 1.0.0', 'exactVersion: 1.0')),
    ('an exact requirement names another version', 'pin-differs', 'requires exactly 1.0.2',
     lambda r: edit(r, 'Apps/App/project.yml', 'exactVersion: 1.0.0', 'exactVersion: 1.0.2')),
    ('a product manifest requires a spike-only package', 'spike-in-product', 'requires the spike-only package acme/S',
     lambda r: edit(r, 'Packages/Good/Package.swift', 'dependencies: [\n        .package(', 'dependencies: [\n        .package(url: "https://example.com/acme/S.git", exact: "5.0.0"),\n        .package(')),
    ('a product lock pins a spike-only package', 'spike-in-product', 'pins the spike-only package acme/S',
     lambda r: edit_json(r, 'Apps/App/Package.resolved', lambda d: d['pins'].append(
         {'identity': 's', 'kind': 'remoteSourceControl', 'location': PKGS['acme/S'][0], 'state': {'revision': 'e' * 40, 'version': '5.0.0'}}))),
    ('a product project depends on a local package under Spikes/', 'spike-in-product', 'depends on Spikes/S',
     lambda r: edit(r, 'Apps/App/project.yml', 'packages:\n', 'packages:\n  SpikeCode:\n    path: ../../Spikes/S\n')),
    ('a product project depends on a symbolic link to a package under Spikes/', 'spike-in-product', 'depends on Spikes/S',
     lambda r: (add_link(r, 'Packages/Linked', '../Spikes/S'),
                edit(r, 'Apps/App/project.yml', 'packages:\n', 'packages:\n  Linked:\n    path: ../../Packages/Linked\n'))),
    ('a product target compiles sources from Spikes/ (sources path)', 'spike-in-product', 'resolves to Spikes/S/Sources/S',
     lambda r: edit(r, 'Apps/App/project.yml', APP_SOURCES, APP_SOURCES + '      - path: ../../Spikes/S/Sources/S\n')),
    ('a product target compiles sources from Spikes/ (sources as a string)', 'spike-in-product', 'resolves to Spikes/S/Sources',
     lambda r: edit(r, 'Apps/App/project.yml', APP_SOURCES, '    sources: ../../Spikes/S/Sources\n')),
    ('a product target names Spikes/ with another capitalization', 'spike-in-product', 'under Spikes',
     lambda r: edit(r, 'Apps/App/project.yml', APP_SOURCES, APP_SOURCES + '      - path: ../../spikes/S/Sources/S\n')),
    ('a product target copies Spikes/ files as a resource folder', 'spike-in-product', 'resolves to Spikes/S/include',
     lambda r: edit(r, 'Apps/App/project.yml', APP_SOURCES, APP_SOURCES + '      - path: ../../Spikes/S/include\n        type: folder\n        buildPhase: resources\n')),
    ('a product build setting searches Spikes/ through $(SRCROOT)', 'spike-in-product', 'resolves to Spikes/S/include',
     lambda r: edit(r, 'Apps/App/project.yml', APP_SOURCES, APP_SOURCES + '    settings:\n      base:\n        HEADER_SEARCH_PATHS: "$(inherited) $(SRCROOT)/../../Spikes/S/include"\n')),
    ('a product build script copies from Spikes/', 'spike-in-product', 'resolves to Spikes/S',
     lambda r: edit(r, 'Apps/App/project.yml', APP_SOURCES, APP_SOURCES + '    postBuildScripts:\n      - name: Copy\n        script: cp -R ../../Spikes/S "$BUILT_PRODUCTS_DIR"\n')),
    ('a product Package.swift passes a flag into Spikes/', 'spike-in-product', 'resolves to Spikes/S/include',
     lambda r: edit(r, 'Packages/Good/Package.swift', '.target(name: "Good", dependencies: [.product(name: "A", package: "A")])',
                    '.target(name: "Good", dependencies: [.product(name: "A", package: "A")], cSettings: [.unsafeFlags(["-I../../Spikes/S/include"])])')),
    ('a symbolic link under Packages/ points into Spikes/', 'spike-in-product', 'is a symbolic link to Spikes/S/Sources/S/S.swift',
     lambda r: add_link(r, 'Packages/Good/Sources/Good/Linked.swift', '../../../../Spikes/S/Sources/S/S.swift')),
    ('a product C file includes a header under Spikes/', 'spike-in-product', 'resolves to Spikes/S/include/s.h',
     c_use('shim.c', '#include "../../../../Spikes/S/include/s.h"\nint f(void) { return s(); }\n')),
    ('a product project depends on a local package outside the product roots', 'outside-product', 'depends on the local package Tools/T',
     lambda r: (add_file(r, 'Tools/T/Package.swift', '// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "T", targets: [.target(name: "T")])\n'),
                edit(r, 'Apps/App/project.yml', 'packages:\n', 'packages:\n  Tool:\n    path: ../../Tools/T\n'))),
    ('a product manifest requires a transitive-only package', 'transitive-direct', 'requires acme/B directly',
     lambda r: edit(r, 'Packages/Good/Package.swift', 'dependencies: [\n        .package(', 'dependencies: [\n        .package(url: "https://example.com/acme/B.git", exact: "2.0.0"),\n        .package(')),
    ('product code imports a transitive module with an attribute', 'transitive-direct', 'imports BModule', swift_use('import Foundation\n@preconcurrency import BModule\n')),
    ('product code imports a transitive module: internal import', 'transitive-direct', 'imports BModule', swift_use('internal import BModule\n')),
    ('product code imports a transitive module: public import', 'transitive-direct', 'imports BModule', swift_use('public import BModule\n')),
    ('product code imports a transitive module: package import', 'transitive-direct', 'imports BModule', swift_use('package import BModule\n')),
    ('product code imports a transitive module: fileprivate import', 'transitive-direct', 'imports BModule', swift_use('fileprivate import BModule\n')),
    ('product code imports a transitive module: private import', 'transitive-direct', 'imports BModule', swift_use('private import BModule\n')),
    ('product code imports a transitive module: attribute and access level', 'transitive-direct', 'imports BModule', swift_use('@preconcurrency internal import BModule\n')),
    ('product code imports a transitive module after another import on one line', 'transitive-direct', 'imports BModule', swift_use('import Foundation; import BModule\n')),
    ('product code imports a transitive module after a statement on one line', 'transitive-direct', 'imports BModule', swift_use('let x = 1; import BModule\n')),
    ('product code imports a transitive module with a line break before its name', 'transitive-direct', 'imports BModule', swift_use('import\n    BModule\n')),
    ('product code imports a transitive module with a comment between the tokens', 'transitive-direct', 'imports BModule', swift_use('import/* c */BModule\n')),
    ('product code imports a transitive module after a comment on the line', 'transitive-direct', 'imports BModule', swift_use('/* c */ import BModule\n')),
    ('product code imports a transitive module in backticks', 'transitive-direct', 'imports BModule', swift_use('import `BModule`\n')),
    ('product code imports one declaration of a transitive module', 'transitive-direct', 'imports BModule', swift_use('internal import struct BModule.Thing\n')),
    ('product code re-exports a submodule of a transitive module', 'transitive-direct', 'imports BModule', swift_use('@_exported import BModule.Sub\n')),
    ('product code imports a transitive module in one #if branch', 'transitive-direct', 'imports BModule', swift_use('#if os(Linux)\nimport Glibc\n#else\nimport BModule\n#endif\n')),
    ('Objective-C imports a transitive module with @import', 'transitive-direct', 'imports BModule', c_use('Use.m', '@import Foundation;\n@import BModule;\n')),
    ('Objective-C imports a transitive submodule with @import', 'transitive-direct', 'imports BModule', c_use('Use.m', '@import BModule.Sub;\n')),
    ('C includes a transitive module framework-style', 'transitive-direct', 'imports BModule (a path into it: BModule/...)', c_use('use.c', '#include <BModule/b.h>\n')),
    ('Objective-C #imports a transitive module framework-style', 'transitive-direct', 'imports BModule', c_use('Use.m', '#import <BModule/b.h>\n')),
    ('C includes a public header of a transitive module by name', 'transitive-direct', 'a public header of acme/B', c_use('use.c', '#include "bmodule.h"\n')),
    ('a C header includes a public header of a transitive module with spaces after #', 'transitive-direct', 'a public header of acme/B', c_use('use.h', '#  include <bmodule.h>\n')),
    ('Objective-C++ imports a transitive module with #pragma clang module import', 'transitive-direct', 'imports BModule', c_use('Use.mm', '#pragma clang module import BModule\n')),
    ('a product target that is not a test uses a test-only package', 'test-in-product', 'target Good uses T',
     lambda r: edit(r, 'Packages/Good/Package.swift', '.target(name: "Good", dependencies: [.product(name: "A", package: "A")])',
                    '.target(name: "Good", dependencies: [.product(name: "A", package: "A"), .product(name: "T", package: "T")])')),
    ('an app target uses a test-only package through project.yml', 'test-in-product', 'target App uses T',
     lambda r: edit(r, 'Apps/App/project.yml', 'exactVersion: 1.0.0\n', 'exactVersion: 1.0.0\n  T:\n    url: https://example.com/acme/T.git\n    exactVersion: 3.0.0\n')
     or edit(r, 'Apps/App/project.yml', APP_DEPS, APP_DEPS + '      - package: T\n        product: T\n')),
    ('a target template makes an app use a test-only package', 'test-in-product', 'target Templated uses T',
     lambda r: edit(r, 'Apps/App/project.yml', 'exactVersion: 1.0.0\n', 'exactVersion: 1.0.0\n  T:\n    url: https://example.com/acme/T.git\n    exactVersion: 3.0.0\ntargetTemplates:\n  AppBase:\n    type: application\n    dependencies:\n      - package: T\n        product: T\n')
     or edit(r, 'Apps/App/project.yml', 'targets:\n', 'targets:\n  Templated:\n    templates: [AppBase]\n    platform: iOS\n')),
    ('a product library target takes its sources from a Tests directory', 'test-layout', 'target Helpers is not a test target',
     lambda r: edit(r, 'Packages/Good/Package.swift', '.testTarget(', '.target(name: "Helpers", path: "Tests/Helpers"),\n        .testTarget(')),
    ('a product app target takes its sources from a directory ending in Tests', 'test-layout', 'target App is not a test target',
     lambda r: edit(r, 'Apps/App/project.yml', APP_SOURCES, APP_SOURCES + '      - path: IntegrationTests\n')),
    ('a product package target uses a macOS-only package on every platform', 'platform', 'target Good can build A for ios, macos',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A').update(platforms=['macOS']))),
    ('an iOS app target uses a macOS-only package', 'platform', 'target App can build A for ios',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A').update(platforms=['macOS']))),
    ('a product package declares a binary target', 'binary', 'binary target Vendor',
     lambda r: edit(r, 'Packages/Good/Package.swift', '.testTarget(', '.binaryTarget(name: "Vendor", url: "https://example.com/vendor.xcframework.zip", checksum: "' + '1' * 64 + '"),\n        .testTarget(')),
    ('a product app target links a committed framework', 'binary', 'framework dependency Apps/App/Vendor/Foo.xcframework',
     lambda r: (add_file(r, 'Apps/App/Vendor/Foo.xcframework/Info.plist', '<plist/>\n'),
                edit(r, 'Apps/App/project.yml', APP_DEPS, APP_DEPS + '      - framework: Vendor/Foo.xcframework\n'))),
    ('a product app target embeds a Carthage framework', 'binary', 'Carthage dependency Foo',
     lambda r: edit(r, 'Apps/App/project.yml', APP_DEPS, APP_DEPS + '      - carthage: Foo\n')),
    ('a Mach-O file is committed under Apps/', 'binary', 'a committed Mach-O file',
     lambda r: add_file(r, 'Apps/App/Vendor/libfoo.bin', b'\xcf\xfa\xed\xfe' + b'\0' * 28, 'wb')),
    ('a static library is committed under Packages/', 'binary', 'a committed static library',
     lambda r: add_file(r, 'Packages/Good/Vendor/data.bin', AR_MAGIC + b'x' * 8, 'wb')),
    ('the inventory lists a binary that nothing uses', 'binary', 'is stale',
     lambda r: edit_json(r, INVENTORY, lambda d: d['binaries'].append({'kind': 'file', 'path': 'Apps/App/Vendor/gone.a', 'sha256': '0' * 64, 'license': 'MIT'}))),
    ('a committed lock is not registered', 'lock-registry', 'committed lock not registered',
     lambda r: add_file(r, 'Packages/Other/Package.resolved', open(os.path.join(r, 'Spikes/S/Package.resolved')).read())),
    ('a manifest reaches remote packages without a lock or exemption', 'unlocked', 'no committed Package.resolved',
     lambda r: add_file(r, 'Spikes/Probe2/project.yml', 'name: Probe2\npackages:\n  Local:\n    path: ../S\ntargets: {}\n')),
    ('a stale exemption for a manifest that now has a lock', 'unlocked', 'stale exemption',
     lambda r: add_file(r, 'Spikes/Probe/Package.resolved', open(os.path.join(r, 'Spikes/S/Package.resolved')).read())),
    ('a product manifest is exempted instead of locked', 'unlocked', 'cannot be exempted',
     lambda r: (os.remove(os.path.join(r, 'Apps/App/Package.resolved')),
                edit_json(r, INVENTORY, lambda d: (d['unlocked'].append({'manifest': 'Apps/App/project.yml', 'reason': 'x'}),
                                                   d['locks'].remove(next(l for l in d['locks'] if l['path'] == 'Apps/App/Package.resolved')),
                                                   [p['locks'].remove('Apps/App/Package.resolved') for p in d['packages'] if 'Apps/App/Package.resolved' in p['locks']])))),
    ('the inventory lists a requirement no manifest makes', 'lock-registry', 'does not require it',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X')['direct_in'].append('Spikes/S/Package.swift'))),
    ("the inventory's used_by_targets misses a target that uses the package", 'lock-registry', 'acme/A: used_by_targets is stale',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A')['used_by_targets'].pop())),
    ('a Python requirement is a range', 'not-exact', "'alpha>=1.0' is not an exact",
     lambda r: edit(r, REQUIREMENTS, 'alpha==1.0', 'alpha>=1.0')),
    ('a Python requirement version differs', 'python-tools', 'beta-pkg: requirements 2.0.2',
     lambda r: edit(r, REQUIREMENTS, 'Beta_Pkg==2.0.1', 'Beta_Pkg==2.0.2')),
    ('a font under Packages/ is not in the inventory', 'vendored-asset', 'does not list',
     lambda r: add_file(r, 'Packages/Good/Sources/Good/Fonts/Other.otf', 'font\n')),
    ('a license file under Apps/ is not in the inventory', 'vendored-asset', 'does not list',
     lambda r: add_file(r, 'Apps/App/Vendor/LICENSE.md', 'third-party license\n')),
    ('a listed font changed', 'vendored-asset', "differs from the inventory's",
     lambda r: edit(r, 'Packages/Good/Sources/Good/Fonts/Face.ttf', 'not really', 'still not')),
    ('a license text copy was edited', 'license-text', 'differs from LICENSE at the pinned revision',
     lambda r: edit(r, 'Docs/Licenses/texts/a/LICENSE', 'A license', 'A licence')),
    ('a package was moved to another revision without reading its license again', 'license-text', 'license data were read at ' + 'a' * 40,
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A').update(revision='9' * 40))),
    ('a workflow uses an action missing from the inventory', 'ci-actions', 'actions/checkout@v5 is not in the inventory',
     lambda r: edit(r, '.github/workflows/ci.yml', 'actions/checkout@v4', 'actions/checkout@v5')),
    ('a workflow uses an action on a tag without an exemption', 'not-exact', "actions/cache@v4 is on the movable reference 'v4'",
     lambda r: (edit(r, '.github/workflows/ci.yml', '      - uses: actions/checkout@v4\n', '      - uses: actions/checkout@v4\n      - uses: actions/cache@v4\n'),
                edit_json(r, INVENTORY, lambda d: d['ci_actions'].append({'uses': 'actions/cache@v4'})))),
    ('the Xcode pin in env.sh differs', 'toolchain', "'27A999z'",
     lambda r: edit(r, ENV_SH, '27A266a', '27A999z')),
    ('the installed Xcode build differs (the failure names the installed build, review TC-02)', 'toolchain',
     "expected 'Build version 27A266a', got 'Build version 27B100'",
     lambda r: tool(r, lambda d: d.update(xcodebuild='Xcode 27.1\nBuild version 27B100\n'))),
    ('the installed Xcode build only extends the pin (review TC-02)', 'toolchain',
     "expected 'Build version 27A266a', got 'Build version 27A266ab'",
     lambda r: tool(r, lambda d: d.update(xcodebuild='Xcode 27.0\nBuild version 27A266ab\n'))),
    ('xcodebuild states no build', 'toolchain', "expected 'Build version 27A266a', got 'xcodebuild: error: no developer tools'",
     lambda r: tool(r, lambda d: d.update(xcodebuild='xcodebuild: error: no developer tools\n'))),
    ('the installed Swift differs', 'toolchain', "expected 'Swift version 9.9 (synthetic-9.9)', got 'Swift version 9.8 (synthetic-9.8)'",
     lambda r: tool(r, lambda d: d.update(swift='Apple Swift version 9.8 (synthetic-9.8)\n'))),
    ('the installed Swift only extends the pinned version line', 'toolchain',
     "got 'Swift version 9.9 (synthetic-9.9) with a suffix'",
     lambda r: tool(r, lambda d: d.update(swift='Apple Swift version 9.9 (synthetic-9.9) with a suffix\n'))),
    ('the installed XcodeGen differs', 'toolchain', "expected 'Version: 9.9.9', got 'Version: 9.9.8'",
     lambda r: tool(r, lambda d: d.update(xcodegen='Version: 9.9.8\n'))),
    ('the installed XcodeGen only extends the pin', 'toolchain', "expected 'Version: 9.9.9', got 'Version: 9.9.91'",
     lambda r: tool(r, lambda d: d.update(xcodegen='Version: 9.9.91\n'))),
    ("the workflow's Xcode guard looks for another build (review TC-08)", 'toolchain',
     "the guard looks for 'Build version 27A999z'; the inventory pins 'Build version 27A266a'",
     lambda r: edit(r, '.github/workflows/ci.yml', 'grep -qx "Build version 27A266a"', 'grep -qx "Build version 27A999z"')),
    ("the workflow's Xcode guard looks first for another Xcode", 'toolchain',
     "a candidate Xcode is 'Xcode_27.9.app'; the inventory pins 'Xcode_27.0.app'",
     lambda r: edit(r, '.github/workflows/ci.yml', '/Applications/Xcode_27.0.app', '/Applications/Xcode_27.9.app')),
    ("the workflow's error names another Xcode", 'toolchain',
     "the text names 'Xcode 27.9 (27Z1)'; the inventory pins 'Xcode 27.0 (27A266a)'",
     lambda r: edit(r, '.github/workflows/ci.yml', '::error::Xcode 27.0 (27A266a)', '::error::Xcode 27.9 (27Z1)')),
    ('the workflow has no Xcode guard', 'toolchain', 'has no Xcode guard line',
     lambda r: edit(r, '.github/workflows/ci.yml', 'grep -qx "Build version 27A266a" && exit 0; ', '')),
    ("CLAUDE.md's toolchain line names another Xcode", 'toolchain',
     "the toolchain line names 'Xcode 27.9 (27Z1)'; the inventory pins 'Xcode 27.0 (27A266a)'",
     lambda r: edit(r, 'CLAUDE.md', '- Xcode 27.0 (27A266a)', '- Xcode 27.9 (27Z1)')),
    ("CLAUDE.md has no toolchain line", 'toolchain', 'has no toolchain line',
     lambda r: edit(r, 'CLAUDE.md', '- Xcode 27.0 (27A266a), Swift 9.9 (self-test)\n', '')),
    ("ADR-0001's toolchain table names another Xcode", 'toolchain',
     "the toolchain table names '27.0, build 27A999z'; the inventory pins '27.0, build 27A266a'",
     lambda r: edit(r, 'Docs/ADRs/0001-platform-baseline-and-toolchain.md', '| Xcode | 27.0, build 27A266a', '| Xcode | 27.0, build 27A999z')),
    ('XcodeGen is not installed', 'toolchain', 'cannot run',
     lambda r: tool(r, lambda d: d.update(xcodegen=None))),
    ('the virtualenv holds another version of a pinned package', 'toolchain', 'virtualenv has alpha 1.1, inventory 1.0',
     lambda r: tool(r, lambda d: d['venv'].update(alpha='1.1'))),
    ('the virtualenv lacks a pinned package', 'toolchain', 'virtualenv has beta-pkg None, inventory 2.0.1',
     lambda r: tool(r, lambda d: d['venv'].pop('beta-pkg'))),
    ('the check does not run in a virtualenv', 'toolchain', 'not running in a virtualenv',
     lambda r: tool(r, lambda d: d.update(venv=None))),
    ('the human-readable inventory lacks a package (a longer name is not a match)', 'docs', 'no line names acme/B',
     lambda r: edit(r, HUMAN, '| acme/B |', '| acme/Bee |')),
    ('the human-readable inventory shows an old version', 'docs', 'no line names acme/B 2.0.0',
     lambda r: edit(r, HUMAN, '| acme/B | 2.0.0 |', '| acme/B | 1.9.0 |')),
    ('the ADR shows another version', 'docs', 'no line names acme/S 5.0.0',
     lambda r: edit(r, ADR, '| acme/S | 5.0.0 |', '| acme/S | 5.0.0.1 |')),
    ('the acknowledgements draft was edited by hand', 'docs', 'acknowledgements draft is out of date',
     lambda r: edit(r, 'Docs/Licenses/acknowledgements-draft.md', '### A 1.0.0', '### A 1.0.1')),
    ('a bundled component names a license text that is not committed', 'license-text', 'is not committed',
     lambda r: edit_json(r, INVENTORY, lambda d: d['packages'][0].update(bundled=[{'component': 'x', 'text': 'Docs/Licenses/texts/a/MISSING'}]))),
    ('the inventory gives a package an unknown role', 'inventory', "role 'maybe'",
     lambda r: edit_json(r, INVENTORY, lambda d: d['packages'][0].update(role='maybe'))),
    ('the inventory gives a package no platforms', 'inventory', 'platforms [] must be a non-empty list',
     lambda r: edit_json(r, INVENTORY, lambda d: d['packages'][0].update(platforms=[]))),
    ('the inventory names no modules for a transitive-only package', 'inventory', 'needs its module names',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/B').pop('modules'))),
    # The inventory's own shape.
    ('the inventory is not valid JSON', 'inventory', 'cannot read', lambda r: add_file(r, INVENTORY, '{not json\n')),
    ('the inventory has another schema version', 'inventory', 'schema_version is 2',
     lambda r: edit_json(r, INVENTORY, lambda d: d.update(schema_version=2))),
    ('an inventory package lacks a field', 'inventory', "missing fields ['license']",
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X').pop('license'))),
    ('an inventory list field is not a list', 'inventory', 'direct_in must be a list',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X').update(direct_in='Spikes/S/Package.swift'))),
    ('an inventory license is not an object', 'inventory', 'license must be an object',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X').update(license='MIT'))),
    ('the inventory lists one package twice', 'inventory', 'duplicate package',
     lambda r: edit_json(r, INVENTORY, lambda d: d['packages'].append(dict(copy.deepcopy(inv_pkg(d, 'acme/X')), name='acme/X2')))),
    ('the inventory gives a range as a version', 'inventory', "version '^4.0.0' is not an exact version",
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X').update(version='^4.0.0'))),
    ('the inventory gives a short revision', 'inventory', "revision 'dddd' is not a 40-character commit",
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X').update(revision='dddd'))),
    ('an inventory target use is incomplete', 'inventory', 'used_by_targets entry',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A')['used_by_targets'].append({'manifest': 'x'}))),
    ('an inventory license has no identifier', 'inventory', 'license needs an id',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X')['license'].update(id=''))),
    ('an inventory license file has no digest', 'inventory', 'needs a sha256 and a text path',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X')['license']['files'][0].update(sha256=''))),
    ('an inventory module list is a string', 'inventory', 'modules must be a list of names',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/B').update(modules='BModule'))),
    ('an inventory binary has no kind', 'inventory', 'needs a kind from',
     lambda r: edit_json(r, INVENTORY, lambda d: d['binaries'].append({'path': 'Apps/App/x', 'license': 'MIT'}))),
    ('an inventory linked binary names nothing', 'inventory', 'a linked entry needs the name',
     lambda r: edit_json(r, INVENTORY, lambda d: d['binaries'].append({'kind': 'linked', 'license': 'MIT'}))),
    # Lock registration.
    ('the inventory registers a lock that is not committed', 'lock-registry', 'registered in the inventory but not committed',
     lambda r: edit_json(r, INVENTORY, lambda d: d['locks'].append({'path': 'Spikes/Gone/Package.resolved', 'manifest': 'Spikes/Gone/Package.swift'}))),
    ('a registered lock names a manifest in another directory', 'lock-registry', 'is not a committed file in the same directory',
     lambda r: edit_json(r, INVENTORY, lambda d: next(l for l in d['locks'] if l['path'] == 'Spikes/S/Package.resolved').update(manifest='Spikes/Probe/project.yml'))),
    ('a lock is not valid JSON', 'lock-registry', 'not valid JSON', lambda r: add_file(r, 'Spikes/S/Package.resolved', '{\n')),
    ('a lock has an unknown format version', 'lock-registry', 'unsupported Package.resolved format version 1',
     lambda r: edit_json(r, 'Spikes/S/Package.resolved', lambda d: d.update(version=1))),
    ("the inventory's lock list for a package misses a lock that pins it", 'lock-registry', "the inventory's locks for it do not list this file",
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/S')['locks'].remove('Spikes/S/Package.resolved'))),
    ('the inventory lists a lock that is not registered', 'lock-registry', 'which is not a registered lock',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A')['locks'].append('Spikes/Gone/Package.resolved'))),
    # Manifests that cannot be read, and exemptions.
    ('a project.yml is not a YAML mapping', 'inventory', 'cannot read the manifest',
     lambda r: add_file(r, 'Spikes/Probe/project.yml', '- a list, not a project\n')),
    ("the inventory's direct_in misses a manifest that requires the package", 'lock-registry', "direct_in for it does not list this manifest",
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/S')['direct_in'].remove('Spikes/S/Package.swift'))),
    ('a local package that a project depends on cannot be read', 'inventory', 'cannot follow its local packages',
     lambda r: add_file(r, 'Spikes/S/Package.swift', '// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "S", nonsense: true)\n')),
    ('an exemption names a manifest that is not committed', 'lock-registry', 'which is not a committed manifest',
     lambda r: edit_json(r, INVENTORY, lambda d: d['unlocked'].append({'manifest': 'Spikes/Gone/project.yml', 'reason': 'x'}))),
    ('an exemption gives no reason', 'inventory', 'gives no reason',
     lambda r: edit_json(r, INVENTORY, lambda d: d['unlocked'][0].update(reason=' '))),
    # Module aliases, build-settings files and module maps (R1-01, R1-02).
    ('a product package aliases a transitive module (-module-alias in unsafeFlags)', 'transitive-direct', 'aliases BModule (Alias=BModule)',
     good_settings('swiftSettings: [.unsafeFlags(["-module-alias", "Alias=BModule"])]')),
    ('a product package renames a transitive module with SwiftPM module aliasing (moduleAliases:)', 'transitive-direct', 'aliases BModule (Alias=BModule)',
     lambda r: edit(r, GOOD_SWIFT, '.product(name: "A", package: "A")])', '.product(name: "A", package: "A", moduleAliases: ["BModule": "Alias"])])')),
    ('a product project aliases a transitive module in OTHER_SWIFT_FLAGS', 'transitive-direct', 'aliases BModule (Alias=BModule)',
     app_settings('        OTHER_SWIFT_FLAGS: "$(inherited) -module-alias Alias=BModule"\n')),
    ('an xcconfig a product project uses searches Spikes/ for headers', 'spike-in-product', 'resolves to Spikes/S/include',
     app_config('HEADER_SEARCH_PATHS = $(inherited) $(SRCROOT)/../../Spikes/S/include // a comment\n')),
    ('an xcconfig #included by a product xcconfig searches Spikes/', 'spike-in-product', "names '../../Spikes/S/include', which resolves to Spikes/S/include",
     app_config('#include "Base.xcconfig"\n', ('Base.xcconfig', 'SWIFT_INCLUDE_PATHS = ../../Spikes/S/include\n'))),
    ('a product module map names a header under Spikes/', 'spike-in-product', 'resolves to Spikes/S/include/s.h',
     lambda r: add_file(r, GOOD_MODULEMAP, 'module Mini {\n    header "../../../../../Spikes/S/include/s.h"\n}\n')),
    ('a product module map names a public header of a transitive package', 'transitive-direct', 'names bmodule.h, a public header of acme/B',
     lambda r: add_file(r, GOOD_MODULEMAP, 'module Mini {\n    umbrella header "bmodule.h"\n}\n')),
    # Where product code may come from (R1-02): Apps/ and Packages/ only.
    ('a product target compiles shared code from outside Apps/ and Packages/', 'outside-product', "builds from 'Shared/Code'",
     tree(lambda r: add_file(r, 'Shared/Code/x.swift', 'import BModule\n'),
          lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '      - path: ../../Shared/Code\n'))),
    ('a product project takes build settings from outside Apps/ and Packages/', 'outside-product', "builds from '../../Shared/App.xcconfig'",
     tree(lambda r: add_file(r, 'Shared/App.xcconfig', 'OTHER_LDFLAGS = -ObjC\n'),
          app_project('configFiles:\n  Debug: ../../Shared/App.xcconfig\n'))),
    ('a product project references an Xcode project outside Apps/ and Packages/', 'outside-product', "builds from '../../Shared/Lib.xcodeproj'",
     app_project('projectReferences:\n  Lib:\n    path: ../../Shared/Lib.xcodeproj\n')),
    ('a product project searches for headers outside Apps/ and Packages/', 'outside-product', 'takes headers or a module map from',
     app_settings('        HEADER_SEARCH_PATHS: "$(inherited) $(SRCROOT)/../../Shared/include"\n')),
    ('a product module map names a header outside Apps/ and Packages/', 'outside-product', 'resolves to Shared/include/x.h',
     lambda r: add_file(r, GOOD_MODULEMAP, 'module Mini {\n    header "../../../../../Shared/include/x.h"\n}\n')),
    ('a symbolic link under Packages/ points outside the product roots', 'outside-product', 'is a symbolic link to Shared/x.swift',
     tree(lambda r: add_file(r, 'Shared/x.swift', 'import BModule\n'),
          lambda r: add_link(r, 'Packages/Good/Sources/Good/Shared.swift', '../../../../Shared/x.swift'))),
    # Binaries reached by search path or by name (R1-09).
    ('a product target searches a host directory for libraries', 'binary', "searches for libraries or frameworks in '/opt/homebrew/lib'",
     app_settings('        LIBRARY_SEARCH_PATHS: /opt/homebrew/lib\n')),
    ('a product package passes a library search path outside the tree', 'binary', "searches for libraries or frameworks in '/opt/homebrew/lib'",
     good_settings('linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib"])]')),
    ('a product target force-loads a library from outside Apps/ and Packages/', 'binary', "links '../../Shared/libvendor.a'",
     app_settings('        OTHER_LDFLAGS: "-force_load ../../Shared/libvendor.a"\n')),
    ('a product package links a library no SDK provides', 'binary', "links the library 'vendorfoo'",
     good_settings('linkerSettings: [.linkedLibrary("vendorfoo")]')),
    ('a product package links a framework no SDK provides', 'binary', "links the framework 'VendorKit'",
     good_settings('linkerSettings: [.linkedFramework("VendorKit")]')),
    ('a product target links a library by -l', 'binary', "links the library 'vendorfoo'",
     app_settings('        OTHER_LDFLAGS: "$(inherited) -Xlinker -lvendorfoo"\n')),
    ('a product target links a framework through -Wl,', 'binary', "links the framework 'VendorKit'",
     app_settings('        OTHER_LDFLAGS: "-Wl,-framework,VendorKit"\n')),
    ('a product target names an SDK dependency that no SDK provides', 'binary', "links the library 'vendorfoo'",
     lambda r: edit(r, APP_YML, APP_DEPS, APP_DEPS + '      - sdk: libvendorfoo.tbd\n')),
    ('a product module map links a library no SDK provides', 'binary', "links the library 'vendorfoo'",
     lambda r: add_file(r, GOOD_MODULEMAP, 'module Mini {\n    header "mini.h"\n    link "vendorfoo"\n}\n')),
    ('the SDKs cannot be listed to judge what a product links', 'toolchain', 'cannot list the SDKs',
     tree(lambda r: tool(r, lambda d: d.update(sdk=None)), good_settings('linkerSettings: [.linkedLibrary("sqlite3")]'))),
    ('a committed library whose digest differs from the inventory', 'binary', "whose digest differs from the inventory's",
     tree(lambda r: add_file(r, 'Packages/Good/Vendor/data.bin', AR_MAGIC + b'x' * 8, 'wb'),
          lambda r: edit_json(r, INVENTORY, lambda d: d['binaries'].append({'kind': 'file', 'path': 'Packages/Good/Vendor/data.bin', 'sha256': '0' * 64, 'license': 'MIT'})))),
    # License texts, assets, tools, actions, toolchain and documents.
    ('a license text the inventory names is not committed', 'license-text', 'license text copy is not committed',
     lambda r: edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/X')['license']['files'][0].update(text='Docs/Licenses/texts/x/GONE'))),
    ('the acknowledgements cannot be generated', 'docs', 'cannot generate the acknowledgements draft',
     lambda r: edit_json(r, INVENTORY, lambda d: d['acknowledgements'].pop('preamble'))),
    ('a listed vendored asset is not committed', 'vendored-asset', 'listed in the inventory but not committed',
     lambda r: edit_json(r, INVENTORY, lambda d: d['vendored_assets'].append({'path': 'Packages/Good/Sources/Good/Fonts/Gone.ttf', 'sha256': '0' * 64}))),
    ('the requirements file is missing', 'python-tools', 'requirements file missing', lambda r: os.remove(os.path.join(r, REQUIREMENTS))),
    ('an unpinned virtualenv entry gives no reason', 'inventory', 'needs a name, version, minimum, minimum_why, why, owner and fix',
     lambda r: edit_json(r, INVENTORY, lambda d: d['python_tools']['unpinned'][0].pop('why'))),
    ('an unpinned virtualenv entry gives no minimum version', 'inventory', 'needs a name, version, minimum',
     lambda r: edit_json(r, INVENTORY, lambda d: d['python_tools']['unpinned'][0].pop('minimum'))),
    ('an unpinned virtualenv entry gives a minimum that is not a version', 'inventory', "minimum 'latest' is not a version",
     lambda r: edit_json(r, INVENTORY, lambda d: d['python_tools']['unpinned'][0].update(minimum='latest'))),
    ('an unpinned virtualenv entry is also pinned', 'inventory', 'which Scripts/tools/requirements.txt pins',
     lambda r: edit_json(r, INVENTORY, lambda d: d['python_tools']['unpinned'].append({'name': 'alpha', 'version': '1.0', 'minimum': '1.0', 'minimum_why': 'x', 'why': 'x', 'owner': 'x', 'fix': 'x'}))),
    ('the virtualenv holds a package the inventory does not record', 'toolchain', 'virtualenv holds gamma 0.1',
     lambda r: tool(r, lambda d: d['venv'].update(gamma='0.1'))),
    # Review R2-01: the installer is unpinned, so a new virtualenv holds the pip its Python bundles (26.1.2 for Python
    # 3.14.6). Any version passes (below the recorded minimum with a warning: NEGATIVES), but it must be there.
    ('the virtualenv lacks the unpinned installer', 'toolchain', 'virtualenv lacks pip',
     lambda r: tool(r, lambda d: d['venv'].pop('pip'))),
    # Review R2-06: exemptions are for Spikes/ only, not just "anything outside Apps/ and Packages/".
    ('a manifest outside Apps/, Packages/ and Spikes/ is exempted instead of locked', 'unlocked', 'cannot be exempted',
     lambda r: (add_file(r, 'Tools/T/project.yml', 'name: T\npackages:\n  Local:\n    path: ../../Spikes/S\ntargets: {}\n'),
                edit_json(r, INVENTORY, lambda d: d['unlocked'].append({'manifest': 'Tools/T/project.yml', 'reason': 'x'})))),
    # Review R2-02 (a): test code is decided by target membership, never by a directory's name.
    ('product code in a test-named subfolder of a library target imports a transitive module', 'transitive-direct', 'imports BModule',
     lambda r: add_file(r, 'Packages/Good/Sources/Good/ABTests/Experiment.swift', 'internal import BModule\n')),
    ('a library target builds a file from a test-named subfolder', 'test-layout', 'builds this file, which sits in a directory named Tests',
     lambda r: add_file(r, 'Packages/Good/Sources/Good/ABTests/Experiment.swift', 'struct Experiment {}\n')),
    ('the only library target, with no directory of its own, takes all of Sources/ (SwiftPM 5.9 and later) and builds a file from a test-named subfolder',
     'test-layout', 'target Solo (Packages/Solo/Package.swift) is not a test target but builds this file',
     tree(lambda r: add_file(r, 'Packages/Solo/Package.swift', '// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "Solo", targets: [.target(name: "Solo")])\n'),
          lambda r: add_file(r, 'Packages/Solo/Sources/ABTests/Experiment.swift', 'struct Experiment {}\n'))),
    ('product code in a test-named subfolder of an app target imports a transitive module', 'transitive-direct', 'imports BModule',
     lambda r: add_file(r, 'Apps/App/Sources/FeatureTests/Use.swift', 'import BModule\n')),
    ('a C file in a test-named subfolder of a library target includes a transitive public header', 'transitive-direct', 'a public header of acme/B',
     c_use('ABTests/use.c', '#include <bmodule.h>\n')),
    ('a module map in a test-named subfolder of a library target names a transitive public header', 'transitive-direct', 'names bmodule.h, a public header of acme/B',
     lambda r: add_file(r, 'Packages/Good/Sources/Good/ABTests/module.modulemap', 'module Mini {\n    header "bmodule.h"\n}\n')),
    ('a file that no target includes is product code even in a Tests directory: it imports a transitive module', 'transitive-direct', 'imports BModule',
     tree(lambda r: add_file(r, 'Packages/Good/Tests/GoodTests/GoodTests.swift', 'import Good\n'),
          lambda r: add_file(r, 'Packages/Good/Tests/Shared/Use.swift', 'import BModule\n'))),
    # Review R2-02 (b): literals and raw identifiers a lexer can misread (each form compiles: round2-reproductions.log).
    ('an import between two extended regex literals that hold /* and */', 'transitive-direct', 'imports BModule',
     swift_use('@MainActor let r1 = #/ /* /#\nimport BModule\n@MainActor let r2 = #/ */ /#\n')),
    ('an import after a bare regex literal that holds a quote', 'transitive-direct', 'imports BModule',
     swift_use('@MainActor let r3 = /"/; import BModule\n')),
    ('an import between two multi-line extended regex literals that hold /* and */', 'transitive-direct', 'imports BModule',
     swift_use('@MainActor let r1 = #/\n  [/*]\n/#\nimport BModule\n@MainActor let r2 = #/\n  [*/]\n/#\n')),
    ('an import between two raw identifiers that hold /* and */', 'transitive-direct', 'imports BModule',
     swift_use('func `a /* b`() {}\nimport BModule\nfunc `c */ d`() {}\n')),
    ('an import after a raw identifier that holds a quote', 'transitive-direct', 'imports BModule',
     swift_use('func `e " f`() {}; import BModule\n')),
    ('an import named only in a comment is reported (the check reads the raw text)', 'transitive-direct', 'imports BModule',
     swift_use('import Foundation\n// import BModule\n')),
    ('an import named only in a string literal is reported', 'transitive-direct', 'imports BModule',
     swift_use('let s = "import BModule"\n')),
    ('an include after a C++ raw string that holds /*', 'transitive-direct', 'a public header of acme/B',
     c_use('use.cpp', 'const char *a = R"(\n/*)";\n#include <bmodule.h>\nconst char *b = "*/";\n')),
    ('an include after a comment that a line splice ends', 'transitive-direct', 'a public header of acme/B',
     c_use('use.c', '/* a comment that ends with a spliced *\\\n/\n#include <bmodule.h>\n/* another comment */\n')),
    ('an include written with the digraph %:', 'transitive-direct', 'a public header of acme/B', c_use('use.c', '%:include <bmodule.h>\n')),
    ('an include written with the trigraph ??=', 'transitive-direct', 'a public header of acme/B', c_use('use.c', '??=include <bmodule.h>\n')),
    ('a computed include through a macro', 'transitive-direct', 'a public header of acme/B',
     c_use('use.c', '#define HEADER <bmodule.h>\n#include HEADER\n')),
    ('a module import through _Pragma', 'transitive-direct', 'imports BModule', c_use('use.c', '_Pragma("clang module import BModule")\n')),
    ('Objective-C imports the generated Swift header of a transitive module', 'transitive-direct', 'names BModule-Swift.h',
     c_use('Use.m', '#import "BModule-Swift.h"\n')),
    ('a product C file includes a header under Spikes/ with the digraph %:', 'spike-in-product', 'resolves to Spikes/S/include/s.h',
     c_use('shim.c', '%:include "../../../../Spikes/S/include/s.h"\n')),
    ('a product C++ file includes a header under Spikes/ after a raw string that holds /*', 'spike-in-product', 'resolves to Spikes/S/include/s.h',
     c_use('shim.cpp', 'const char *a = R"(\n/*)";\n#include "../../../../Spikes/S/include/s.h"\nconst char *b = "*/";\n')),
    ('a product C file includes a header under Spikes/ after a comment that a line splice ends', 'spike-in-product', 'resolves to Spikes/S/include/s.h',
     c_use('shim.c', '/* spliced *\\\n/\n#include "../../../../Spikes/S/include/s.h"\n/* another */\n')),
    ('a workflow action pinned to a commit is not recorded as pinned', 'ci-actions', 'is pinned to a commit, but the inventory does not say so',
     tree(lambda r: edit(r, '.github/workflows/ci.yml', 'actions/checkout@v4', 'actions/checkout@' + '0' * 40),
          lambda r: edit_json(r, INVENTORY, lambda d: d['ci_actions'][0].update(uses='actions/checkout@' + '0' * 40)))),
    ('the inventory lists an action no workflow uses', 'ci-actions', 'is listed but no workflow uses it',
     lambda r: edit_json(r, INVENTORY, lambda d: d['ci_actions'].append({'uses': 'actions/cache@' + '1' * 40, 'pinned_to_commit': True}))),
    ('Scripts/lib/env.sh is missing', 'toolchain', 'missing', lambda r: os.remove(os.path.join(r, ENV_SH))),
    ('the human-readable inventory is missing', 'docs', 'missing', lambda r: os.remove(os.path.join(r, HUMAN))),
    # Review R3-01: routes to a transitive-only package through flags and settings, with no import in any source file.
    ('a product package imports a transitive module into every file with -import-module', 'transitive-direct', 'imports BModule into every source file',
     good_settings('swiftSettings: [.unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "BModule"])]')),
    ('a product target imports a module into every file with -import-module: not a flag a product target may pass', 'flag', "passes '-import-module'",
     app_settings('        OTHER_SWIFT_FLAGS: "$(inherited) -Xfrontend -import-module -Xfrontend Good"\n')),
    ('a product target force-includes a transitive public header with -include', 'transitive-direct', 'a public header of acme/B, in a value of the manifest',
     app_settings('        OTHER_CFLAGS: "-include bmodule.h"\n')),
    ('a product package force-includes a transitive public header through -Xcc -include', 'transitive-direct', 'a public header of acme/B, in a value of the manifest',
     good_settings('swiftSettings: [.unsafeFlags(["-Xcc", "-include", "-Xcc", "bmodule.h"])]')),
    ('a product target takes a bridging header from the package checkouts beside the build products', 'outside-product', 'which leaves the build-product, SDK or toolchain directory',
     app_settings('        SWIFT_OBJC_BRIDGING_HEADER: "$(BUILD_DIR)/../../SourcePackages/checkouts/B/include/b-bridge.h"\n')),
    ('a product target takes a prefix header named like a transitive public header from the package checkouts', 'transitive-direct', 'a public header of acme/B, in a value of the manifest',
     app_settings('        GCC_PREFIX_HEADER: "$(BUILD_DIR)/../../SourcePackages/checkouts/B/include/bmodule.h"\n')),
    ('a product target searches the package checkouts for headers through $(BUILD_DIR)/..', 'outside-product', 'which leaves the build-product, SDK or toolchain directory',
     app_settings('        HEADER_SEARCH_PATHS: "$(inherited) $(BUILD_DIR)/../../SourcePackages/checkouts/B/include"\n')),
    ('a product target searches a package checkout below a build variable without ..', 'outside-product', 'or reaches package checkouts',
     app_settings('        SWIFT_INCLUDE_PATHS: "$(BUILD_ROOT)/SourcePackages/checkouts/B"\n')),
    ('a product package searches a package checkout under its own .build for headers', 'outside-product', '(a build or package-checkout directory)',
     good_settings('cSettings: [.headerSearchPath("../../.build/checkouts/B/include")]')),
    ('a product package target takes its sources from a package checkout under .build', 'outside-product', '(a build or package-checkout directory)',
     lambda r: edit(r, GOOD_SWIFT, '.testTarget(', '.target(name: "Vendored", path: ".build/checkouts/B/Sources/B"),\n        .testTarget(')),
    ('a product target searches an untracked directory under Apps/', 'outside-product', 'tracked by git, so it can hold only build products',
     app_settings('        HEADER_SEARCH_PATHS: "$(SRCROOT)/Generated"\n')),
    ('a product path uses a variable the check cannot evaluate', 'outside-product', 'a variable the check cannot evaluate',
     app_settings('        HEADER_SEARCH_PATHS: "$(MY_HEADERS)/include"\n')),
    ('a build-product path goes on with another variable', 'outside-product', 'a variable the check cannot evaluate',
     app_settings('        LIBRARY_SEARCH_PATHS: "$(BUILT_PRODUCTS_DIR)/$(VENDOR_SUBDIR)"\n')),
    ('a product target takes a prefix header from a build directory', 'outside-product', 'a build directory: what a product target compiles must be a file',
     app_settings('        GCC_PREFIX_HEADER: "$(DERIVED_FILE_DIR)/Prefix.h"\n')),
    ('a product target takes a module map that is not tracked', 'outside-product', 'that is not a file tracked by git',
     app_settings('        MODULEMAP_FILE: "$(SRCROOT)/Support/Missing.modulemap"\n')),
    ('a module map with an unusual file name, named by MODULEMAP_FILE, wraps a transitive public header', 'transitive-direct', 'names bmodule.h, a public header of acme/B, which product code may use',
     tree(lambda r: add_file(r, 'Apps/App/Support/Mini.txt', 'module Mini {\n    header "bmodule.h"\n}\n'),
          app_settings('        MODULEMAP_FILE: "$(SRCROOT)/Support/Mini.txt"\n'))),
    ('a file with an unusual name, force-included with -include, includes a transitive public header', 'transitive-direct', 'which product code may use only through the package that brings it (found in the raw text: any include',
     tree(lambda r: add_file(r, 'Apps/App/Support/Prefix.txt', '#include <bmodule.h>\n'),
          app_settings('        OTHER_CFLAGS: "-include $(SRCROOT)/Support/Prefix.txt"\n'))),
    ('a header in a test target directory includes a transitive public header: headers are product code wherever they sit', 'transitive-direct', 'which product code may use only through the package that brings it (found in the raw text: any include',
     tree(lambda r: add_file(r, 'Packages/Good/Tests/GoodTests/GoodTests.swift', 'import Good\n'),
          lambda r: add_file(r, 'Packages/Good/Tests/GoodTests/shim.h', '#include <bmodule.h>\n'))),
    ('a module map in a test target directory wraps a transitive public header: module maps are product code wherever they sit', 'transitive-direct', 'names bmodule.h, a public header of acme/B, which product code may use',
     tree(lambda r: add_file(r, 'Packages/Good/Tests/GoodTests/GoodTests.swift', 'import Good\n'),
          lambda r: add_file(r, 'Packages/Good/Tests/GoodTests/module.modulemap', 'module TestShim {\n    header "bmodule.h"\n}\n'))),
    ('a module map names an extern module map with an unusual file name that wraps a transitive public header', 'transitive-direct', 'names bmodule.h, a public header of acme/B, which product code may use',
     tree(lambda r: add_file(r, GOOD_MODULEMAP, 'module Outer {\n    extern module Inner "inner.map"\n}\n'),
          lambda r: add_file(r, 'Packages/Good/Sources/Good/include/inner.map', 'module Inner {\n    header "bmodule.h"\n}\n'))),
    ('a preprocessor definition names a transitive public header, for a computed include', 'transitive-direct', 'a public header of acme/B, in a preprocessor definition',
     app_settings('        GCC_PREPROCESSOR_DEFINITIONS: "HDR=<bmodule.h>"\n')),
    ('a SwiftPM definition names a transitive module', 'transitive-direct', "a macro can carry a module's name into an import",
     good_settings('cSettings: [.define("MOD", to: "BModule")]')),
    ('SWIFT_MODULE_ALIASES aliases a transitive module', 'transitive-direct', 'aliases BModule (Alias=BModule)',
     app_settings('        SWIFT_MODULE_ALIASES: "Alias=BModule"\n')),
    ('per-file compilerFlags force-include a transitive public header', 'transitive-direct', 'a public header of acme/B, in a value of the manifest',
     lambda r: edit(r, APP_YML, APP_SOURCES, '    sources:\n      - path: Sources\n        compilerFlags: ["-include", "bmodule.h"]\n')),
    ('per-file compilerFlags load a compiler plugin', 'flag', "passes '-fplugin=/tmp/plugin.dylib'",
     lambda r: edit(r, APP_YML, APP_SOURCES, '    sources:\n      - path: Sources\n        compilerFlags: "-fplugin=/tmp/plugin.dylib"\n')),
    ('WARNING_CFLAGS passes a preprocessor option through -Wp,', 'flag', "passes '-Wp,-include,bmodule.h'",
     app_settings('        WARNING_CFLAGS: "-Wall -Wp,-include,bmodule.h"\n')),
    ('a product package passes a VFS overlay', 'flag', "passes '-vfsoverlay'",
     good_settings('swiftSettings: [.unsafeFlags(["-vfsoverlay", "overlay.yaml"])]')),
    ('a product target passes a source file among its flags', 'flag', "passes '../../Shared/Extra.swift'",
     app_settings('        OTHER_SWIFT_FLAGS: "../../Shared/Extra.swift"\n')),
    ('a product target replaces the C compiler (CC)', 'outside-product', 'it replaces a compiler, linker, SDK or toolchain input',
     app_settings('        CC: /opt/homebrew/opt/llvm/bin/clang\n')),
    ('a product target builds against an SDK at a path', 'outside-product', 'it replaces a compiler, linker, SDK or toolchain input',
     app_settings('        SDKROOT: /tmp/Custom.sdk\n')),
    ('a product target links with another linker', 'outside-product', 'it replaces a compiler, linker, SDK or toolchain input',
     app_settings('        CLANG_ALTERNATE_LINKER: /opt/homebrew/bin/ld64.lld\n')),
    ('a product target takes linker inputs from a file list', 'outside-product', 'it replaces a compiler, linker, SDK or toolchain input',
     app_settings('        CLANG__INPUT_FILE_LIST_PATH__: "$(SRCROOT)/inputs.LinkFileList"\n')),
    ('a product package takes compiler flags from pkg-config (a system library target)', 'outside-product', 'it replaces a compiler, linker, SDK or toolchain input',
     tree(lambda r: add_file(r, 'Packages/Good/Sources/CZip/module.modulemap', 'module CZip [system] {\n    header "shim.h"\n    link "z"\n}\n'),
          lambda r: add_file(r, 'Packages/Good/Sources/CZip/shim.h', '#include <zlib.h>\n'),
          lambda r: edit(r, GOOD_SWIFT, '.testTarget(', '.systemLibrary(name: "CZip", pkgConfig: "zlib"),\n        .testTarget('))),
    ('a manifest script names a transitive public header', 'transitive-direct', 'a public header of acme/B, in a value of the manifest',
     lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '    preBuildScripts:\n      - name: Copy\n        script: cp "\x24BUILD_DIR/../../SourcePackages/checkouts/B/include/bmodule.h" "\x24SRCROOT/Sources/"\n')),
    ('a build-settings file names a transitive public header', 'transitive-direct', 'a public header of acme/B, in a build setting',
     app_config('VENDOR_NOTE = bmodule.h\n')),
    ('a product target uses a build tool plugin from a test-only package', 'test-in-product', 'target Good uses TPlugin',
     lambda r: edit(r, GOOD_SWIFT, GOOD_TARGET, GOOD_TARGET[:-1] + ', plugins: [.plugin(name: "TPlugin", package: "T")])')),
    ('a product project references an untracked Xcode project inside Apps/', 'outside-product', 'nothing there is tracked by git',
     app_project('projectReferences:\n  Lib:\n    path: Lib/Lib.xcodeproj\n')),
    # Review R3-04: a committed Xcode project or workspace carries package references the check would not read.
    ('an Xcode project is committed under Apps/, with a package reference of its own on a branch', 'xcode-project', 'is a committed Xcode project',
     lambda r: add_file(r, 'Apps/App/App.xcodeproj/project.pbxproj', '/* XCRemoteSwiftPackageReference "Zed" */ repositoryURL = "https://example.com/acme/Zed.git"; requirement = {kind = branch; branch = main;};\n')),
    ('a workspace is committed under Spikes/', 'xcode-project', 'is a committed Xcode workspace',
     lambda r: add_file(r, 'Spikes/S/S.xcworkspace/contents.xcworkspacedata', '<Workspace version="1.0"/>\n')),
    # Review R4-01: XcodeGen expands ${NAME} from the environment, so a product project.yml could reach Spikes/ code,
    # import a transitive module or use a test-only package with no literal value the check could judge (what XcodeGen
    # 2.46.0 expands is shown in Docs/Stage0/evidence/M0-ExitPrep/zipguard/reproductions.log, part 2a).
    ('R4-01 (a): a local package path that XcodeGen expands from the environment into Spikes/', 'manifest-input',
     "packages.SpikeCode.path is '${SYLVIA_ROOT}/Spikes/S'",
     lambda r: edit(r, APP_YML, 'packages:\n', 'packages:\n  SpikeCode:\n    path: ${SYLVIA_ROOT}/Spikes/S\n')),
    ('R4-01 (b): a target template named from the environment, which passes -import-module for a transitive module',
     'manifest-input', "targets.App.templates[0] is '${SYLVIA_TEMPLATE}'",
     tree(app_project('targetTemplates:\n  Quiet:\n    settings:\n      base:\n'
                      '        OTHER_SWIFT_FLAGS: "-Xfrontend -import-module -Xfrontend BModule"\n'),
          lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '    templates:\n      - ${SYLVIA_TEMPLATE}\n'))),
    ('R4-01 (c): a dependency of the app target on a package named from the environment, a test-only one',
     'manifest-input', "targets.App.dependencies[2].package is '${SYLVIA_EXTRA_PACKAGE}'",
     tree(app_declares_t, lambda r: edit(r, APP_YML, APP_DEPS, APP_DEPS + '      - package: ${SYLVIA_EXTRA_PACKAGE}\n        product: T\n'))),
    ('R4-01: a YAML escape that parses to ${NAME} (\\x24{), in a local package path', 'manifest-input',
     "packages.SpikeCode.path is '${SYLVIA_ROOT}/Spikes/S'",
     lambda r: edit(r, APP_YML, 'packages:\n', 'packages:\n  SpikeCode:\n    path: "\\x24{SYLVIA_ROOT}/Spikes/S"\n')),
    ('R4-01: a build setting whose name XcodeGen takes from the environment (keys are expanded too)', 'manifest-input',
     'the key targets.App.settings.base.${SYLVIA_SEARCH_SETTING}',
     app_settings('        ${SYLVIA_SEARCH_SETTING}: "$(SRCROOT)/../../Shared/include"\n')),
    ('R4-01: a target template that takes a dependency from a template attribute (templateAttributes)', 'manifest-input',
     "targetTemplates.WithDep.dependencies[0].package is '${dep_package}'",
     tree(app_declares_t,
          app_project('targetTemplates:\n  WithDep:\n    dependencies:\n      - package: ${dep_package}\n        product: T\n'),
          lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '    templates: [WithDep]\n    templateAttributes:\n      dep_package: T\n'))),
    ('R4-01: a local package path with a leading ~, which XcodeGen expands to a home directory', 'manifest-input',
     "packages.Home.path is '~/Vendor/Zip': XcodeGen expands a leading ~",
     lambda r: edit(r, APP_YML, 'packages:\n', 'packages:\n  Home:\n    path: ~/Vendor/Zip\n')),
    ('R4-01: a source path with a leading ~', 'manifest-input', "targets.App.sources[1].path is '~/Shared/Code'",
     lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '      - path: ~/Shared/Code\n')),
    # The same reasoning for SwiftPM: every build evaluates a Package.swift again, in its own environment.
    ('a product Package.swift reads the environment through Context, to add a test-only package', 'manifest-input',
     "names 'Context'",
     good_manifest('let extra: [Target.Dependency] = Context.environment["SYLVIA_EXTRA"] == nil ? [] : [.product(name: "T", package: "T")]\n',
                   dependencies='[.product(name: "A", package: "A")] + extra')),
    ('a product Package.swift imports Foundation to read the environment, for a source path', 'manifest-input',
     'imports Foundation',
     good_manifest('import Foundation\nlet goodPath = ProcessInfo.processInfo.environment["SYLVIA_GOOD_PATH"] ?? "Sources/Good"\n',
                   path='goodPath')),
    ('a product Package.swift binds getenv by name without an import (_silgen_name)', 'manifest-input',
     "names '_silgen_name'",
     good_manifest('@_silgen_name("getenv") func cGetenv(_ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?\n'
                   'let extra: [Target.Dependency] = cGetenv("SYLVIA_EXTRA") == nil ? [] : [.product(name: "T", package: "T")]\n',
                   dependencies='[.product(name: "A", package: "A")] + extra')),
    ("a product Package.swift reads its process's arguments, in which SwiftPM passes the environment (CommandLine)",
     'manifest-input', "names 'CommandLine'",
     good_manifest('let extra: [Target.Dependency] = CommandLine.arguments.contains("-sylvia") ? [.product(name: "T", package: "T")] : []\n',
                   dependencies='[.product(name: "A", package: "A")] + extra')),
    ('a product Package.swift holds a compilation condition (#if)', 'manifest-input', "names '#if'",
     good_manifest('#if compiler(>=99)\nlet extra: [Target.Dependency] = [.product(name: "T", package: "T")]\n#else\n'
                   'let extra: [Target.Dependency] = []\n#endif\n', dependencies='[.product(name: "A", package: "A")] + extra')),
    ('a product Package.swift draws a random number', 'manifest-input', "names 'random'",
     good_manifest('let extra: [Target.Dependency] = Int.random(in: 0..<1_000_000) == 0 ? [.product(name: "T", package: "T")] : []\n',
                   dependencies='[.product(name: "A", package: "A")] + extra')),
    ('a product Package.swift reads a clock', 'manifest-input', "names 'ContinuousClock'",
     good_manifest('let start = ContinuousClock.now\nlet extra: [Target.Dependency] = ContinuousClock.now - start > .seconds(1) ? [.product(name: "T", package: "T")] : []\n',
                   dependencies='[.product(name: "A", package: "A")] + extra')),
    # Review R4-02: C-family include paths judged only against Spikes/, so an include outside the product roots or into
    # a package checkout passed; the forms compile against Minizip's own sources and the routes passed the check before
    # the fix (Docs/Stage0/evidence/M0-ExitPrep/zipguard/reproductions.log, parts 1 and 2c).
    ('R4-02 (a): a product header includes a file outside Apps/ and Packages/', 'outside-product',
     "includes '../../../../../Shared/include/x.h'; beside this file it would be Shared/include/x.h",
     tree(lambda r: add_file(r, 'Shared/include/x.h', 'int x(void);\n'),
          lambda r: add_file(r, 'Packages/Good/Sources/Good/include/shim.h', '#include "../../../../../Shared/include/x.h"\n'))),
    ("R4-02 (b): a product header includes a transitive package's C source from its checkout under .build", 'outside-product',
     "includes '../../../.build/checkouts/B/Sources/CB/b.c'",
     lambda r: add_file(r, 'Packages/Good/Sources/Good/include/shim.h', '#include "../../../.build/checkouts/B/Sources/CB/b.c"\n')),
    ("a product C file includes a transitive package's source through `..` from a search directory (Minizip's include directory: ../unzip.c)",
     'outside-product', "includes '../b.c'; beside this file it would be Packages/Good/Sources/b.c",
     c_use('use.c', '#include "../b.c"\nint use(void) { return 0; }\n')),
    ('a product C file includes <../...>, found only in a search directory', 'outside-product', "includes '../src/b.c', and in a search directory",
     c_use('use.c', '#include <../src/b.c>\n')),
    ('a product C file includes a path through package checkouts without ..', 'outside-product',
     'a path through a build or package-checkout directory (SourcePackages)',
     c_use('use.c', '#include <SourcePackages/checkouts/B/Sources/CB/b.c>\n')),
    ('a product C file includes an absolute path', 'outside-product', "includes '/opt/vendor/b.c', an absolute path",
     c_use('use.c', '#include "/opt/vendor/b.c"\n')),
    ('Objective-C #imports a file outside the product roots', 'outside-product', "includes '../../../../Shared/include/x.h'",
     tree(lambda r: add_file(r, 'Shared/include/x.h', 'int x(void);\n'),
          c_use('Use.m', '#import "../../../../Shared/include/x.h"\n'))),
    ('#include_next climbs out of a search directory', 'outside-product', "includes '../b.h'",
     c_use('use.h', '#include_next <../b.h>\n')),
    ('#embed brings in the bytes of a file outside the product roots (C23)', 'outside-product', "includes '../../../../Shared/blob.bin'",
     tree(lambda r: add_file(r, 'Shared/blob.bin', 'blob\n'),
          c_use('use.c', 'static const unsigned char blob[] = {\n#embed "../../../../Shared/blob.bin"\n};\n'))),
    ('an assembly file brings in a file outside the product roots with .incbin', 'outside-product', "includes '../../../../Shared/blob.bin'",
     tree(lambda r: add_file(r, 'Shared/blob.bin', 'blob\n'),
          c_use('blob.s', '.data\n.incbin "../../../../Shared/blob.bin"\n'))),
    ('inline assembly in a C file brings in a file outside the product roots with .incbin', 'outside-product',
     "includes '../../../../Shared/blob.bin'",
     tree(lambda r: add_file(r, 'Shared/blob.bin', 'blob\n'),
          c_use('use.c', '__asm__(".data\\n.incbin \\"../../../../Shared/blob.bin\\"");\n'))),
    ('a lex file includes a file outside the product roots in its C code', 'outside-product', "includes '../../../../Shared/include/x.h'",
     tree(lambda r: add_file(r, 'Shared/include/x.h', 'int x(void);\n'),
          c_use('scan.l', '%{\n#include "../../../../Shared/include/x.h"\n%}\n%%\n.\t;\n%%\n'))),
    ('an include written with the digraph %: climbs out of a search directory', 'outside-product', "includes '../b.c'",
     c_use('use.c', '%:include "../b.c"\n')),
    ('a computed include, whose file a macro decides', 'outside-product', 'a computed include, whose file macros decide',
     c_use('use.c', '#define SRC "../b.c"\n#include SRC\n')),
    # The same reasoning for build-settings files: where an #include'd file is was not judged at all.
    ('a product xcconfig #includes a build-settings file outside Apps/ and Packages/', 'outside-product',
     "takes build settings from '../../../Shared/Base.xcconfig', which resolves to Shared/Base.xcconfig, outside",
     tree(lambda r: add_file(r, 'Shared/Base.xcconfig', 'OTHER_LDFLAGS = -ObjC\n'),
          app_config('#include "../../../Shared/Base.xcconfig"\n'))),
    ("a product xcconfig #includes a build-settings file from Xcode's directory (<DEVELOPER_DIR>)", 'outside-product',
     "takes build settings from '$(DEVELOPER_DIR)/Makefiles/CoreOS/Xcode/BSD.xcconfig', a build, SDK or toolchain directory",
     app_config('#include "<DEVELOPER_DIR>/Makefiles/CoreOS/Xcode/BSD.xcconfig"\n')),
    ('a product xcconfig optionally #includes a file git does not track (#include?)', 'outside-product',
     'resolves to Apps/App/Config/Generated.xcconfig: that is not a file tracked by git',
     app_config('#include? "Generated.xcconfig"\n')),
    ('a product xcconfig holds an #include the check cannot read', 'outside-product', "has the line '#include <Base.xcconfig>'",
     app_config('#include <Base.xcconfig>\n', ('Base.xcconfig', 'OTHER_LDFLAGS = -ObjC\n'))),
    ('a product xcconfig #includes a path with a variable in it', 'outside-product', 'has the line \'#include "$(SRCROOT)/../../Shared/Base.xcconfig"\'',
     tree(lambda r: add_file(r, 'Shared/Base.xcconfig', 'OTHER_LDFLAGS = -ObjC\n'),
          app_config('#include "$(SRCROOT)/../../Shared/Base.xcconfig"\n'))),
    ('a product target builds files with a build rule (it can compile as C a file the check does not read as code)',
     'outside-product', 'sets buildRules',
     lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '    buildRules:\n      - filePattern: "*.txt"\n'
                                                           '        compilerSpec: com.apple.compilers.llvm.clang.1_0\n')),
    # Review R4-03: a product manifest or build-settings file redefines a variable the check evaluates itself.
    ('R4-03: a product target redefines DERIVED_FILE_DIR, then searches it for headers', 'outside-product',
     'sets DERIVED_FILE_DIR = /opt/elsewhere/B/include',
     app_settings('        DERIVED_FILE_DIR: /opt/elsewhere/B/include\n        HEADER_SEARCH_PATHS: $(DERIVED_FILE_DIR)\n'
                  '        SWIFT_INCLUDE_PATHS: $(DERIVED_FILE_DIR)\n')),
    ('R4-03: a product xcconfig redefines SRCROOT', 'outside-product', 'sets SRCROOT = /opt/elsewhere',
     app_config('SRCROOT = /opt/elsewhere\nHEADER_SEARCH_PATHS = $(SRCROOT)/include\n')),
    # Review R4-04: Clang's -Werror takes no argument, so the word after it in a C or linker flag setting is an input.
    ('R4-04: -Werror followed by an input file in OTHER_LDFLAGS', 'flag', "passes 'Evil'",
     app_settings('        OTHER_LDFLAGS: "-Werror Evil"\n')),
    ('R4-04: -Werror followed by an input file in a SwiftPM linker unsafeFlags', 'flag', "passes 'Evil'",
     good_settings('linkerSettings: [.unsafeFlags(["-Werror", "Evil"])]')),
]


NEGATIVES = [  # (what, change[, warning]) that must not produce any failure, and no warning but the one named (a
               # (category, message fragment) pair) when there is one
    ('a product test imports a module of a transitive-only package',
     lambda r: add_file(r, 'Packages/Good/Tests/GoodTests/UseTests.swift', 'internal import BModule\n')),
    ('a product test in C includes a public header of a transitive-only package',
     lambda r: add_file(r, 'Packages/Good/Tests/GoodTests/shim.c', '#include <bmodule.h>\n')),
    ('the only test target, with no directory of its own, takes all of Tests/ (SwiftPM 5.9 and later): a test there imports a transitive module',
     lambda r: add_file(r, 'Packages/Good/Tests/Shared/UseTests.swift', 'internal import BModule\n')),
    ('`import` as an argument label, a member name or a raw identifier, and imports of other modules, are not imports of a transitive module',
     lambda r: add_file(r, 'Packages/Good/Sources/Good/Labels.swift',
                        'import Foundation\nfunc f(import x: Int) -> Int { x }\nlet a = f(import: 1)\n'
                        'struct S { var `import` = 2 }\nlet b = S().import\n// import Foundation\n'
                        'let c = "import Good"\nlet g = "\\(f(import: 3))"\nfunc `import`() {}\nlet r = #/ import /#\n'
                        'let BModuleName = "BModule"\n')),
    ('C files that include system and own headers, and name the transitive module only as a word',
     lambda r: add_file(r, 'Packages/Good/Sources/Good/shim.m',
                        '#include <stdio.h>\n#import "Good.h"\n%:include <string.h>\n// BModule is reached only through Good\n'
                        'static const char *s = "bmodule";\nstatic const char *raw = R"x(not a header: bmodule_h)x";\n')),
    ('the unpinned installer is newer than the version recorded (any version at or above the minimum)',
     lambda r: tool(r, lambda d: d['venv'].update(pip='26.3'))),
    ('the unpinned installer is exactly its minimum, written without a trailing zero',
     lambda r: tool(r, lambda d: d['venv'].update(pip='26.2'))),
    # Review R2-01: what a freshly bootstrapped virtualenv on Python 3.14.6 holds passes, with a warning.
    ('the unpinned installer is below its minimum (a fresh virtualenv on Python 3.14.6 holds pip 26.1.2): a warning',
     lambda r: tool(r, lambda d: d['venv'].update(pip='26.1.2')), ('toolchain', 'pip 26.1.2 is below 26.2.0')),
    ('the unpinned installer is a pre-release of its minimum: a warning',
     lambda r: tool(r, lambda d: d['venv'].update(pip='26.2.0rc1')), ('toolchain', 'pip 26.2.0rc1 is below 26.2.0')),
    ('the unpinned installer has a version this check cannot compare: a warning',
     lambda r: tool(r, lambda d: d['venv'].update(pip='26.2.1+local')), ('toolchain', 'is not a version this check can compare')),
    ('a product package renames a module of a package that is not transitive-only (moduleAliases:)',
     lambda r: edit(r, GOOD_SWIFT, '.product(name: "A", package: "A")])', '.product(name: "A", package: "A", moduleAliases: ["A": "AlsoA"])])')),
    ('a file in a test target named like test code, and a shipping target whose own directory names are ordinary',
     lambda r: (add_file(r, 'Packages/Good/Tests/GoodTests/Support/HelperTests.swift', 'internal import BModule\n'),
                add_file(r, 'Packages/Good/Sources/Good/Testing/Probe.swift', 'struct Probe {}\n'))),
    ('a product source file named Notice.swift is not a license file',
     lambda r: add_file(r, 'Packages/Good/Sources/Good/Notice.swift', 'struct Notice {}\n')),
    ('a lock spells a package URL without .git and in another case',
     lambda r: edit_json(r, 'Packages/Good/Package.resolved', lambda d: lock_pin(d, 'a').update(location='https://Example.com/acme/A/'))),
    ('a spike target may use a test-only package', lambda r: (
        edit(r, 'Spikes/S/Package.swift', '[.package(', '[.package(url: "https://example.com/acme/T.git", exact: "3.0.0"), .package('),
        edit(r, 'Spikes/S/Package.swift', '[.product(name: "S", package: "S")]', '[.product(name: "S", package: "S"), .product(name: "T", package: "T")]'),
        edit_json(r, 'Spikes/S/Package.resolved', lambda d: d['pins'].append(
            {'identity': 't', 'kind': 'remoteSourceControl', 'location': PKGS['acme/T'][0], 'state': {'revision': 'c' * 40, 'version': '3.0.0'}})),
        edit_json(r, INVENTORY, lambda d: [inv_pkg(d, 'acme/T')[k].append(v)
                                          for k, v in (('direct_in', 'Spikes/S/Package.swift'), ('locks', 'Spikes/S/Package.resolved'))]
                  and inv_pkg(d, 'acme/T')['used_by_targets'].append({'manifest': 'Spikes/S/Package.swift', 'target': 'S', 'products': ['T'], 'test': False})))),
    ('a product target names paths inside the product roots (where tracked files are) and build-product, SDK and toolchain variables',
     tree(lambda r: add_file(r, 'Packages/Good/include/good.h', 'int good(void);\n'),
          lambda r: add_file(r, 'Apps/App/Vendor/README.txt', 'vendored notes\n'),
          lambda r: add_file(r, 'Apps/App/Sources/include/app.h', 'int app(void);\n'),
          app_settings('        HEADER_SEARCH_PATHS: "$(inherited) $(SRCROOT)/../../Packages/Good/include $(BUILT_PRODUCTS_DIR)/include"\n'
                       '        LIBRARY_SEARCH_PATHS: "$(inherited) $(PROJECT_DIR)/Vendor $(SDKROOT)/usr/lib"\n'
                       '        FRAMEWORK_SEARCH_PATHS: "$(PLATFORM_DIR)/Developer/Library/Frameworks"\n'
                       '        OTHER_SWIFT_FLAGS: "$(inherited) -Xcc -I$(SRCROOT)/Sources/include -module-alias Alias=Good"\n'))),
    ('a product target and package link SDK libraries and frameworks by name',
     tree(good_settings('linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("c++"), .linkedFramework("Foundation")]'),
          lambda r: edit(r, APP_YML, APP_DEPS, APP_DEPS + '      - sdk: libz.tbd\n      - sdk: UIKit.framework\n'),
          app_settings('        OTHER_LDFLAGS: "$(inherited) -ObjC -lsqlite3 -framework UIKit -Wl,-weak_framework,SwiftUI"\n'))),
    ('a product project uses xcconfig files that stay inside the product roots',
     tree(lambda r: add_file(r, 'Apps/App/Sources/include/app.h', 'int app(void);\n'),
          app_config('#include "Base.xcconfig"\nHEADER_SEARCH_PATHS = $(inherited) $(SRCROOT)/Sources/include // the app\'s own\n',
                     ('Base.xcconfig', 'OTHER_LDFLAGS = -lz -framework CoreText\nSWIFT_INCLUDE_PATHS = $(BUILT_PRODUCTS_DIR)\n')))),
    ('a product module map names its own header and links an SDK library',
     tree(lambda r: add_file(r, 'Packages/Good/Sources/Good/include/good.h', 'int good(void);\n'),
          lambda r: add_file(r, GOOD_MODULEMAP, '// the package\'s own module\nmodule GoodC {\n    header "good.h"\n    link "z"\n    export *\n}\n'))),
    ('a product test target takes fixtures, outside headers and a transitive module alias (tests never ship)',
     lambda r: edit(r, APP_YML, 'targets:\n', 'targets:\n  AppTests:\n    type: bundle.unit-test\n    platform: iOS\n'
                                              '    sources:\n      - path: ../../Fixtures/sample.txt\n        buildPhase: resources\n'
                                              '    settings:\n      base:\n        HEADER_SEARCH_PATHS: "$(SRCROOT)/../../Shared/include"\n'
                                              '        OTHER_SWIFT_FLAGS: "-module-alias Alias=BModule"\n        OTHER_LDFLAGS: "-lvendorfoo"\n')),
    ('a product package links a library only on Linux, where no Apple SDK is involved',
     good_settings('linkerSettings: [.linkedLibrary("rt", .when(platforms: [.linux]))]')),
    ('a product package links a library the inventory lists (binaries, kind linked)',
     tree(good_settings('linkerSettings: [.linkedLibrary("vendorfoo")]'),
          lambda r: edit_json(r, INVENTORY, lambda d: d['binaries'].append({'kind': 'linked', 'manifest': GOOD_SWIFT, 'name': 'vendorfoo', 'license': 'MIT'})))),
    ('a macOS-only package used only under a macOS condition, by a macOS app target', lambda r: (
        edit_json(r, INVENTORY, lambda d: inv_pkg(d, 'acme/A').update(platforms=['macOS'])),
        edit(r, 'Packages/Good/Package.swift', '.product(name: "A", package: "A")', '.product(name: "A", package: "A", condition: .when(platforms: [.macOS]))'),
        edit(r, 'Apps/App/project.yml', 'platform: iOS', 'platform: macOS'))),
    ('an inventoried binary target with the same URL and checksum', lambda r: (
        edit(r, 'Packages/Good/Package.swift', '.testTarget(', '.binaryTarget(name: "Vendor", url: "https://example.com/vendor.xcframework.zip", checksum: "' + '1' * 64 + '"),\n        .testTarget('),
        edit_json(r, INVENTORY, lambda d: d['binaries'].append({'kind': 'binaryTarget', 'manifest': 'Packages/Good/Package.swift', 'name': 'Vendor',
                                                                'url': 'https://example.com/vendor.xcframework.zip', 'checksum': '1' * 64, 'license': 'MIT'})))),
    ('a workflow action pinned to a commit and recorded as such', lambda r: (
        edit(r, '.github/workflows/ci.yml', 'actions/checkout@v4', 'actions/checkout@' + '0' * 40),
        edit_json(r, INVENTORY, lambda d: d['ci_actions'][0].update(uses='actions/checkout@' + '0' * 40, pinned_to_commit=True)))),
    ('a symbolic link under Packages/ to another product file', lambda r: add_link(r, 'Packages/Good/Sources/Good/Alias.swift', 'Good.swift')),
    # Review R3-01: what product targets may still do with flags, settings, headers and module maps.
    ('a product target and package pass only flags product targets may pass',
     tree(app_settings('        OTHER_SWIFT_FLAGS: "$(inherited) -warnings-as-errors -enable-upcoming-feature ExistentialAny -strict-concurrency=complete -Xfrontend -warn-long-function-bodies=200 -DDEBUG -Werror DeprecatedDeclaration"\n'
                       '        OTHER_CFLAGS: "-Wall -Wno-unused-parameter -std=c17 -fobjc-arc -DFOO=1 -U BAR -O2"\n'
                       '        OTHER_LDFLAGS: "-ObjC -dead_strip -lz"\n'),
          good_settings('swiftSettings: [.unsafeFlags(["-warnings-as-errors", "-Xfrontend", "-enable-actor-data-race-checks"])]'))),
    ('a tracked prefix header, bridging header and module map, definitions without transitive names, and SDKROOT set to an SDK',
     tree(lambda r: add_file(r, 'Apps/App/Support/Prefix.pch', '#include <stdio.h>\n'),
          lambda r: add_file(r, 'Apps/App/Support/App-Bridging-Header.h', '#import "Good.h"\n'),
          lambda r: add_file(r, 'Apps/App/Support/App.modulemap', 'module AppSupport {\n    header "App-Bridging-Header.h"\n}\n'),
          app_settings('        GCC_PREFIX_HEADER: Support/Prefix.pch\n'
                       '        SWIFT_OBJC_BRIDGING_HEADER: "$(SRCROOT)/Support/App-Bridging-Header.h"\n'
                       '        MODULEMAP_FILE: "$(SRCROOT)/Support/App.modulemap"\n'
                       '        GCC_PREPROCESSOR_DEFINITIONS: "DEBUG=1 NAME=Good"\n'
                       '        SDKROOT: iphoneos\n'))),
    ('a test target passes any flag and setting (tests never ship)',
     lambda r: edit(r, APP_YML, 'targets:\n', 'targets:\n  AppTests:\n    type: bundle.unit-test\n    platform: iOS\n    settings:\n      base:\n'
                                              '        OTHER_SWIFT_FLAGS: "-Xfrontend -import-module -Xfrontend BModule -vfsoverlay x.yaml"\n'
                                              '        OTHER_CFLAGS: "-include bmodule.h"\n        CC: /opt/homebrew/bin/clang\n'
                                              '        HEADER_SEARCH_PATHS: "$(BUILD_DIR)/../../SourcePackages/checkouts/B/include"\n')),
    ('a referenced Xcode project generated from a project.yml tracked beside it',
     tree(lambda r: add_file(r, 'Apps/Lib/project.yml', 'name: Lib\ntargets: {}\n'),
          app_project('projectReferences:\n  Lib:\n    path: ../Lib/Lib.xcodeproj\n'))),
    # Review round 4: what product code and manifests may still do after the fixes of R4-01 to R4-04.
    ('product C files that include their own tracked header through .., headers by plain name (system, generated) and data by plain name',
     tree(lambda r: add_file(r, 'Packages/Good/Sources/Good/include/good.h', 'int good(void);\n'),
          lambda r: add_file(r, 'Packages/Good/Sources/Good/src/impl.c',
                             '#include "../include/good.h"\n#include <stdio.h>\n#include "Good-Swift.h"\n'
                             '#include_next <limits.h>\n#import <Foundation/Foundation.h>\nint good(void) { return 1; }\n'),
          lambda r: add_file(r, 'Packages/Good/Sources/Good/data.s', '.data\n.incbin "blob.bin"\n'))),
    ("a product project uses Xcode's $(NAME) and a script's $NAME and ~ inside its text, which XcodeGen leaves alone",
     lambda r: edit(r, APP_YML, APP_SOURCES, APP_SOURCES + '    postBuildScripts:\n      - name: Stamp\n'
                                                           '        script: echo "$BUILT_PRODUCTS_DIR" "$(date)" ~\n'
                                                           '    settings:\n      base:\n        PRODUCT_NAME: $(TARGET_NAME)\n')),
    ('spike manifests may read the environment and use ${NAME} (they never ship)',
     tree(lambda r: edit(r, 'Spikes/S/Package.swift', 'import PackageDescription\n',
                         'import PackageDescription\nlet spikeFlag = Context.environment["SYLVIA_SPIKE"] != nil\n'),
          lambda r: edit(r, 'Spikes/Probe/project.yml', '    platform: iOS\n',
                         '    platform: iOS\n    postBuildScripts:\n      - name: Env\n        script: echo "${HOME}"\n'))),
    ('a product Package.swift that imports CompilerPluginSupport as well as PackageDescription',
     lambda r: edit(r, GOOD_SWIFT, 'import PackageDescription\n', 'import PackageDescription\nimport CompilerPluginSupport\n')),
    ("Swift's -Werror with a diagnostic group, in swiftSettings and in a Swift file's compilerFlags (review R4-04 keeps it allowed there)",
     tree(good_settings('swiftSettings: [.unsafeFlags(["-Werror", "DeprecatedDeclaration"])]'),
          lambda r: edit(r, APP_YML, APP_SOURCES, '    sources:\n      - path: Sources/App.swift\n'
                                                  '        compilerFlags: ["-Werror", "DeprecatedDeclaration"]\n'))),
]


_REAL_SDK = []


def fake_toolchain(root):
    """A run function, a virtualenv reader and an SDK reader that answer from the synthetic tree's
    .selftest/toolchain.json (the SDK reader answers with the real SDKs unless that file sets "sdk" to null)."""
    def state():
        return json.load(open(os.path.join(root, SELFTEST_TOOLCHAIN), encoding='utf-8'))

    def run(cmd):
        out = state().get(os.path.basename(cmd[-2]))
        if out is None:
            raise OSError(f'{cmd[-2]}: not installed (self-test)')
        return out

    def sdk():
        if 'sdk' in state():
            return state()['sdk']
        if not _REAL_SDK:
            _REAL_SDK.append(sdk_names())
        return _REAL_SDK[0]

    return dict(run=run, distributions=lambda: state()['venv'], sdk=sdk)


def fail_sites(method='fail'):
    """{line: source} of every `self.<method>(` call in this file: the check's failure (or warning) branches."""
    source = open(os.path.abspath(__file__), encoding='utf-8').read()
    lines = source.splitlines()
    return {n.lineno: lines[n.lineno - 1].strip() for n in ast.walk(ast.parse(source))
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == method
            and isinstance(n.func.value, ast.Name) and n.func.value.id == 'self'}


def self_test(swift=None):
    """Runs the check on a synthetic tree, then on one mutated copy per entry in MUTATIONS (each must be reported
    with its own category and message) and one changed copy per entry in NEGATIVES (none may be reported, and none
    may warn except as the entry says). Every failure branch of the check (each `self.fail(` call) must be reached by
    the mutation written for it, and every warning branch (each `self.warn(` call) by the allowed change written for
    it; a branch that nothing reaches fails the self-test, so the claim that the self-test covers every rule stays
    true."""
    failures = 0
    covered, warned = set(), set()
    with tempfile.TemporaryDirectory(prefix='dependency-lock-self-test-') as tmp:
        base = os.path.join(tmp, 'base')
        write_base(base)
        clean = Checker(base, swift, **fake_toolchain(base))
        clean.run(toolchain=True)
        if clean.failures or clean.warnings:
            print('FAIL  the clean synthetic tree reports failures or warnings:')
            for f in clean.failures + clean.warnings:
                print('     ', *f)
            return 1
        print('ok    the clean synthetic tree passes, toolchain checks included (' + '; '.join(clean.lines) + ')')
        for i, (what, category, fragment, mutate) in enumerate(MUTATIONS):
            root = os.path.join(tmp, f'm{i:03d}')
            shutil.copytree(base, root, symlinks=True)
            mutate(root)
            c = Checker(root, swift, **fake_toolchain(root))
            c.run(toolchain=True)
            hits = [(f, line) for f, line in zip(c.failures, c.sites) if f[0] == category and fragment in f[2]]
            covered.update(line for _, line in hits)
            if any(f[1] == 'virtualenv' for f in c.failures) and any('holds exactly these' in n for n in c.lines):
                failures += 1  # review R2-01: the success note must never accompany a failed comparison
                print(f'FAIL  {what}: the virtualenv comparison failed, yet the check also notes that it holds exactly the recorded packages')
            if hits:
                print(f'ok    {what}: {category} {hits[0][0][1]}: {hits[0][0][2][:110]}')
            else:
                failures += 1
                print(f'FAIL  {what}: expected {category} with {fragment!r}; got:')
                for f in c.failures or [('none', '', '')]:
                    print('     ', *f)
        for i, (what, change, *expect) in enumerate(NEGATIVES):
            root = os.path.join(tmp, f'n{i:03d}')
            shutil.copytree(base, root, symlinks=True)
            change(root)
            c = Checker(root, swift, **fake_toolchain(root))
            c.run(toolchain=True)
            want = expect[0] if expect else None
            hits = [(w, line) for w, line in zip(c.warnings, c.warn_lines) if want and w[0] == want[0] and want[1] in w[2]]
            others = [w for w in c.warnings if not (want and w[0] == want[0] and want[1] in w[2])]
            warned.update(line for _, line in hits)
            if c.failures:
                failures += 1
                print(f'FAIL  {what}: expected no failure; got:')
                for f in c.failures:
                    print('     ', *f)
            elif others or (want and not hits):
                failures += 1
                print(f'FAIL  {what}: expected ' + (f'the warning {want[0]} {want[1]!r}' if want else 'no warning') + '; got:')
                for w in c.warnings or [('none', '', '')]:
                    print('     ', *w)
            else:
                print(f'ok    {what}: no failure' + (f'; warns {hits[0][0][0]} {hits[0][0][1]}: {hits[0][0][2][:110]}' if hits else ''))
    sites, warn_sites = fail_sites('fail'), fail_sites('warn')
    missing = sorted(set(sites) - covered)
    for line in missing:
        failures += 1
        print(f'FAIL  no mutation reaches the failure branch at line {line}: {sites[line][:120]}')
    missing_warn = sorted(set(warn_sites) - warned)
    for line in missing_warn:
        failures += 1
        print(f'FAIL  no allowed change reaches the warning branch at line {line}: {warn_sites[line][:120]}')
    categories = sorted({m[1] for m in MUTATIONS})
    print(f'self-test: {len(MUTATIONS)} mutations ({len(categories)} categories: {", ".join(categories)}) and '
          f'{len(NEGATIVES)} allowed changes; {len(sites) - len(missing)} of the {len(sites)} failure branches reached '
          f'by the mutation written for them, {len(warn_sites) - len(missing_warn)} of the {len(warn_sites)} warning '
          f'branches by the allowed change written for them; {failures} wrong')
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('mode', nargs='?', default='check', choices=['check', 'self-test', 'acknowledgements', 'used-by-targets'])
    ap.add_argument('--root', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    ap.add_argument('--toolchain', action='store_true', help='also check the installed Xcode, Swift, XcodeGen and virtualenv')
    ap.add_argument('--write', action='store_true', help='acknowledgements: write the draft instead of printing it')
    args = ap.parse_args()
    if args.mode == 'self-test':
        return self_test()
    if args.mode == 'used-by-targets':
        print(json.dumps(used_by_report(args.root), indent=2))
        return 0
    if args.mode == 'acknowledgements':
        inv = json.load(open(os.path.join(args.root, INVENTORY), encoding='utf-8'))
        text = render_acknowledgements(args.root, inv)
        if args.write:
            path = os.path.join(args.root, inv['acknowledgements']['draft'])
            with open(path, 'w', encoding='utf-8') as f:
                f.write(text)
            print(f"wrote {inv['acknowledgements']['draft']} ({len(text)} characters)")
        else:
            sys.stdout.write(text)
        return 0
    c = Checker(args.root)
    c.run(toolchain=args.toolchain)
    for line in c.lines:
        print('ok    ' + line)
    for category, where, message in c.failures:
        print(f'FAIL {category} {where}: {message}')
    # Warnings come last, just before the summary, so the end of a log shows them (review R3-05: Scripts/ci.sh prints a
    # drop-in's log only when it fails, so a warning in a passing run is seen only by reading the log).
    for category, where, message in c.warnings:
        print(f'WARN {category} {where}: {message}')
    print(f'dependency lock check: {len(c.failures)} failure(s), {len(c.warnings)} warning(s)'
          + (' (the WARN lines above do not fail the check)' if c.warnings else ''))
    return 1 if c.failures else 0


if __name__ == '__main__':
    sys.exit(main())
