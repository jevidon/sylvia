"""ADR-0014 evidence: copy the third-party notices that sit inside source files of shipped packages (code a package
took from another project, with no license file of its own) into Docs/Licenses/texts, for the acknowledgements.

  python3 -I Docs/Stage0/evidence/M0-dependencies/commands/extract-notices.py [--check]   (from the repository root)

Each notice is the block of comment lines from a start marker to an end marker (both included) in a file of a
checkout that resolve-locks.sh left; only the comment markers (`//` and one following space) are removed. Before
reading, the checkout's HEAD must equal the revision Docs/Licenses/inventory.json pins. Prints each output with its
SHA-256; with --check, compares with the committed copies instead of writing. No network.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

E = 'Spikes/G01-EPUB/.build/SourcePackages/checkouts'
NOTICES = [
    # (package name in the inventory, checkout, file in it, start marker, end marker, output under Docs/Licenses/texts)
    ('readium/swift-toolkit', f'{E}/swift-toolkit', 'Sources/Streamer/Toolkit/DataCompression.swift',
     r'^//\s+DataCompression$', r'limitations under the License\.$',
     'readium__swift-toolkit/Sources__Streamer__Toolkit__DataCompression.swift__notice'),
    ('scinfu/SwiftSoup', f'{E}/SwiftSoup', 'Sources/LRUCache.swift',
     r'^//\s+LRUCache\.swift$', r'IN THE SOFTWARE\.$',
     'scinfu__swiftsoup/Sources__LRUCache.swift__notice'),
    ('krzyzanowskim/CryptoSwift', f'{E}/CryptoSwift', 'Sources/CryptoSwift/CS_BigInt/GCD.swift',
     r'^//\s+CS\.BigInt$', r'Copyright © 2016-2017 Károly Lőrentey\.$',
     'krzyzanowskim__cryptoswift/Sources__CryptoSwift__CS_BigInt__GCD.swift__notice'),
    ('groue/GRDB.swift', 'Spikes/G05-AI/.build/checkouts/GRDB.swift', 'GRDB/Utils/Inflections+English.swift',
     r'Copyright \(c\) 2005-2019 David Heinemeier Hansson$', r'WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE\.$',
     'groue__grdb.swift/GRDB__Utils__Inflections+English.swift__notice'),
    ('groue/GRDB.swift', 'Spikes/G05-AI/.build/checkouts/GRDB.swift', 'GRDB/Core/Cursor.swift',
     r'Parts of this file are derived from the Swift\.org open source project:$', r'See https://swift\.org/LICENSE\.txt for license information$',
     'groue__grdb.swift/GRDB__Core__Cursor.swift__notice'),
    ('marmelroy/Zip', f'{E}/Zip', 'Zip/minizip/unzip.c',
     r'^/\* unzip\.c -- IO for uncompress', r'^\*/$',
     'marmelroy__zip/Zip__minizip__unzip.c__header-comment'),
    # crypt.h is compiled into unzip.c and zip.c (decrypt_byte, init_keys and update_keys are linked) and carries its
    # own notice, with holders unzip.c's header does not name (Terry Thorsen; Info-ZIP).
    ('marmelroy/Zip', f'{E}/Zip', 'Zip/minizip/include/crypt.h',
     r'^/\* crypt\.h -- base code for traditional PKWARE encryption', r'^\*/$',
     'marmelroy__zip/Zip__minizip__include__crypt.h__header-comment'),
    # Two files of Readium's ZIPFoundation fork carry the Readium Foundation's header, which points to "the BSD-style
    # license available in the top-level LICENSE file of the project"; that file is MIT. Both files must carry the same
    # block, so both entries write (or, with --check, compare) the same output.
    ('readium/ZIPFoundation', f'{E}/ZIPFoundation', 'Sources/ZIPFoundation/DataSource.swift',
     r'^//\s+Copyright 2025 Readium Foundation\.', r'available in the top-level LICENSE file of the project\.$',
     'readium__zipfoundation/Sources__ZIPFoundation__DataSource.swift__notice'),
    ('readium/ZIPFoundation', f'{E}/ZIPFoundation', 'Sources/ZIPFoundation/SharedMutableValue.swift',
     r'^//\s+Copyright 2025 Readium Foundation\.', r'available in the top-level LICENSE file of the project\.$',
     'readium__zipfoundation/Sources__ZIPFoundation__DataSource.swift__notice'),
    ('apple/swift-certificates', 'Spikes/G02-Transfer/SourceService/.build/checkouts/swift-certificates',
     'Sources/X509/X509BaseTypes/TimeCalculations.swift',
     r'Copyright © 2005-2020 Rich Felker, et al\.$', r'SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE\.$',
     'apple__swift-certificates/Sources__X509__X509BaseTypes__TimeCalculations.swift__notice'),
    # uSHET's cpp_magic.h, which CNIOAtomics compiles into the Mac source service (review R2-03): its header says where
    # the file comes from and its license; the license text itself is fetched (fetch-external-licenses.sh).
    ('apple/swift-nio', 'Spikes/G02-Transfer/SourceService/.build/checkouts/swift-nio', 'Sources/CNIOAtomics/src/cpp_magic.h',
     r'^//\s*this is https://github\.com/18sg/uSHET/', r'^//\s*LICENSE: MIT$',
     'apple__swift-nio/Sources__CNIOAtomics__src__cpp_magic.h__notice'),
]

check = '--check' in sys.argv
inventory = {p['name']: p for p in json.load(open('Docs/Licenses/inventory.json'))['packages']}
failures = 0
for name, checkout, rel, start, end, out in NOTICES:
    head = subprocess.run(['git', '-C', checkout, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    if head != inventory[name]['revision']:
        print(f'FAIL {name}: checkout {checkout} is at {head or "nothing"}, the inventory pins {inventory[name]["revision"]}')
        failures += 1
        continue
    lines = open(os.path.join(checkout, rel), encoding='utf-8').read().splitlines()
    i = next(n for n, l in enumerate(lines) if re.search(start, l))
    j = next(n for n in range(i, len(lines)) if re.search(end, lines[n]))
    text = '\n'.join(re.sub(r'^\s*// ?', '', l) for l in lines[i:j + 1]) + '\n'
    dest = os.path.join('Docs/Licenses/texts', out)
    digest = hashlib.sha256(text.encode()).hexdigest()
    if check:
        same = os.path.exists(dest) and open(dest, encoding='utf-8').read() == text
        print(f'{"ok  " if same else "FAIL"} {dest}: {rel} lines {i + 1}-{j + 1} at {head[:12]} (sha256 {digest})')
        failures += 0 if same else 1
    else:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, 'w', encoding='utf-8').write(text)
        print(f'wrote {dest}: {rel} lines {i + 1}-{j + 1} at {head[:12]} (sha256 {digest})')
sys.exit(1 if failures else 0)
