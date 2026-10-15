"""ADR-0014 evidence: the copyright (name ID 0), version (5), license description (13) and license URL (14)
records of every OpenType/TrueType font file under the given directories, with each file's SHA-256.

  python3 -I font-names.py <dir> [<dir> ...]
Reads files only; no network. Parses the 'name' table directly (no third-party module).
"""
import hashlib
import os
import struct
import sys

WANT = {0: 'copyright', 5: 'version', 13: 'license', 14: 'license URL', 3: 'unique ID'}


def names(path):
    data = open(path, 'rb').read()
    num_tables = struct.unpack('>H', data[4:6])[0]
    for i in range(num_tables):
        tag, _, off, length = struct.unpack('>4sIII', data[12 + 16 * i: 28 + 16 * i])
        if tag == b'name':
            break
    else:
        return {}
    _, count, string_off = struct.unpack('>HHH', data[off:off + 6])
    out = {}
    for i in range(count):
        pid, eid, lid, nid, ln, so = struct.unpack('>HHHHHH', data[off + 6 + 12 * i: off + 18 + 12 * i])
        if nid not in WANT:
            continue
        raw = data[off + string_off + so: off + string_off + so + ln]
        if pid == 3 or pid == 0:
            s = raw.decode('utf-16-be', errors='replace')
        else:
            s = raw.decode('mac_roman', errors='replace')
        if (pid, lid) in ((3, 0x409), (1, 0), (0, 0)) or nid not in out:
            out[nid] = s
    return out


for top in sys.argv[1:]:
    for dp, dns, fns in os.walk(top):
        dns[:] = sorted(d for d in dns if d not in {'.git', '.build'})
        for fn in sorted(fns):
            if fn.lower().endswith(('.otf', '.ttf', '.woff', '.woff2')):
                p = os.path.join(dp, fn)
                h = hashlib.sha256(open(p, 'rb').read()).hexdigest()
                print(f'== {p} ({os.path.getsize(p)} bytes, sha256 {h})')
                if fn.lower().endswith(('.woff', '.woff2')):
                    print('   (WOFF: name table not parsed)')
                    continue
                for nid, v in sorted(names(p).items()):
                    print(f'   {WANT[nid]}: {" ".join(v.split())[:400]}')
