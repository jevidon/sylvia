#!/usr/bin/env bash
# Generates the small, deterministic EPUB fixtures used by the G0.1 EPUB spike (Spikes/G01-EPUB).
#
#   Scripts/fixtures/generate-g01-epub-fixtures.sh            # write into Spikes/G01-EPUB/Fixtures/generated (committed)
#   Scripts/fixtures/generate-g01-epub-fixtures.sh --out DIR  # write elsewhere
#   Scripts/fixtures/generate-g01-epub-fixtures.sh --check    # regenerate into a temp dir and compare entry contents
#                                                             # (names, sizes, CRC-32) with the committed archives,
#                                                             # check MANIFEST.tsv and the text companions
#
# All text is written for these fixtures (generated content; no third-party text). Every archive uses a fixed
# timestamp and a fixed entry order, so the entry contents are identical on every run. Deflate output can differ
# between zlib versions, which is why --check compares entry contents rather than archive bytes.
#
# Fixtures (all under 1 MB):
#   g01-unicode.epub            valid EPUB 3, non-BMP, combining, Greek and CJK text, two chapters (selection/offset tests)
#   g01-hostile.epub            publication scripts and remote resources aimed at 127.0.0.1:00000 (the tests patch the
#                               port to their own loopback recorder); entries are STORED so the patch keeps sizes
#   g01-traversal.epub          valid EPUB plus "../" and absolute-path ZIP entries and an OPF href that climbs out
#   g01-symlink.epub            chapter 2 is a ZIP symlink entry pointing at /etc/hosts
#   g01-bomb.epub               chapter 2 inflates to 200 MiB (sizes declared honestly)
#   g01-bomb-lying.epub         same bytes, but chapter 2 declares an uncompressed size of 4096 bytes
#   g01-truncated.epub          g01-unicode.epub cut to 55 % of its length (no central directory)
#   g01-font-obfuscated.epub    a font obfuscated with the IDPF algorithm and declared in encryption.xml (must open)
#   g01-encrypted-chapter.epub  chapter 2 really encrypted with AES-256-CBC (fixed public fixture key, IV prepended as
#                               in XML Encryption), declared in encryption.xml with no licence (unknown protection)
#   g01-lcp-like.epub           the same ciphertext, encryption.xml pointing at an LCP licence, plus META-INF/license.lcpl
#   g01-adept-like.epub         chapter 2 encrypted with AES-128-CBC, an Adobe ADEPT key reference, META-INF/rights.xml
#   g01-protected-chapter.digests.txt  SHA-256 of chapter 2's plaintext and of the stored ciphertexts
#   g01-deep-nesting.epub       chapter 2 nests 10,000 <span> elements (excessive recursion)
#   g01-nesting-limit.epub      chapter 2 nests exactly 256 elements deep (html, body, p, 253 spans): the adapter's limit
#   g01-nonhtml-active.epub     scripts in reading-order documents that are not HTML: an SVG page and an item declared
#                               application/xml whose root is XHTML
#   g01-csp-bypass.epub         event handlers and scripts behind markup that misleads a text-level CSP injector: a
#                               comment containing "<head>", a prefixed <h:html> root, and "<!-->" in a text/html item
#   g01-nesting-bypass.epub     10,000-deep nesting a text-level depth scanner measures as shallow: spans after "<!-->",
#                               and "<span></x>" repeated (unmatched end tags)
#   g01-form-navigation.epub    forms (navigations that are not link activations) in an XHTML chapter and in a
#                               script-free spine item declared application/xml, aimed at an undeclared archive entry,
#                               a declared non-spine XML and XHTML resource with scripts, and markup declared as a PNG
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

out="$SYLVIA_ROOT/Spikes/G01-EPUB/Fixtures/generated"
check=0
while (( $# )); do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --check) check=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

committed="$SYLVIA_ROOT/Spikes/G01-EPUB/Fixtures/generated"
if (( check )); then
  out="$(mktemp -d)"
  trap 'rm -rf "$out"' EXIT
fi
mkdir -p "$out"

/usr/bin/python3 - "$out" <<'PY'
import hashlib, io, os, struct, sys, zipfile

OUT = sys.argv[1]
WHEN = (2026, 10, 6, 0, 0, 0)
PLACEHOLDER = "127.0.0.1:00000"

def info(name, compress=zipfile.ZIP_DEFLATED):
    zi = zipfile.ZipInfo(name, date_time=WHEN)
    zi.compress_type = compress
    zi.create_system = 3
    zi.external_attr = (0o100644 << 16)
    return zi

def write_epub(path, entries, stored=False, extra=None):
    """entries: list of (name, bytes|str). mimetype is always first and STORED."""
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(info("mimetype", zipfile.ZIP_STORED), b"application/epub+zip")
        for name, data in entries:
            if isinstance(data, str):
                data = data.encode("utf-8")
            z.writestr(info(name, zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED), data, compresslevel=None if stored else 9)
        if extra:
            extra(z)

CONTAINER = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"""

def opf(uid, title, items, spine, extra_meta=""):
    manifest = "\n".join(
        f'    <item id="{i}" href="{h}" media-type="{m}"' + (f' properties="{p}"' if p else "") + "/>"
        for (i, h, m, p) in items)
    spine_xml = "\n".join(f'    <itemref idref="{s}"/>' for s in spine)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="en">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">{uid}</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>Sylvia fixture generator</dc:creator>
    <meta property="dcterms:modified">2026-10-06T00:00:00Z</meta>{extra_meta}
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
{manifest}
  </manifest>
  <spine>
{spine_xml}
  </spine>
</package>
"""

def nav(entries):
    lis = "\n".join(f'      <li><a href="{h}">{t}</a></li>' for (h, t) in entries)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en">
<head><title>Contents</title></head>
<body>
  <nav epub:type="toc" id="toc"><h1>Contents</h1>
    <ol>
{lis}
    </ol>
  </nav>
</body>
</html>
"""

def xhtml(title, body, head=""):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en">
<head><title>{title}</title>{head}</head>
<body>
{body}
</body>
</html>
"""

def simple_book(uid, title, chapters, extra_items=(), extra_entries=(), extra_meta=""):
    """chapters: list of (id, href, title, body). Returns entries."""
    items = [(cid, href, "application/xhtml+xml", None) for (cid, href, _, _) in chapters] + list(extra_items)
    entries = [
        ("META-INF/container.xml", CONTAINER),
        ("OEBPS/content.opf", opf(uid, title, items, [c[0] for c in chapters], extra_meta)),
        ("OEBPS/nav.xhtml", nav([(href, t) for (_, href, t, _) in chapters])),
    ]
    for (_, href, t, body) in chapters:
        entries.append((f"OEBPS/{href}", xhtml(t, body)))
    entries.extend(extra_entries)
    return entries

FILLER = ("The orchard keeper counted the rows twice before the light went, and wrote the number in a small book "
          "kept for that purpose alone. ")

# 1. Unicode fixture -------------------------------------------------------------------------------
U_C1 = "\n".join([
    '<h1 id="c1-title">Chapter One: Marks in the Margin</h1>',
    '<p id="p1">' + FILLER * 3 + '</p>',
    # Non-BMP: MATHEMATICAL FRAKTUR letters (U+1D509 etc.) and an emoji; combining acute (e + U+0301); CJK; Greek.
    '<p id="p-nonbmp">The scribe wrote \U0001D509\U0001D52F\U0001D51E\U0001D528\U0001D531\U0001D532\U0001D52F letters beside the river, '
    'then drew a small \U0001F33F in the corner and signed it Amélie with a careful hand.</p>',
    '<p id="p-cjk">On the next leaf she copied 漢字 for “Han characters” and the Greek ἀρετή for virtue.</p>',
    '<p id="p2">' + FILLER * 4 + '</p>',
    '<p id="p-end1">The first chapter closes on this sentence, which a reader might keep together with the opening of the next.</p>',
])
U_C2 = "\n".join([
    '<h1 id="c2-title">Chapter Two: The Second Leaf</h1>',
    '<p id="p-start2">The second chapter opens here, continuing the thought across the resource boundary.</p>',
    '<p id="p3">' + FILLER * 5 + '</p>',
])
unicode_entries = simple_book(
    "urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000001", "Sylvia Unicode Fixture",
    [("c1", "c1.xhtml", "Chapter One", U_C1), ("c2", "c2.xhtml", "Chapter Two", U_C2)])
write_epub(os.path.join(OUT, "g01-unicode.epub"), unicode_entries)

# 2. Hostile content fixture (STORED so the tests can patch the loopback port in place) ---------------
R = "http://" + PLACEHOLDER
H_HEAD = f"""
<link rel="stylesheet" type="text/css" href="style.css"/>
<link rel="stylesheet" type="text/css" href="{R}/remote.css"/>
<link rel="prefetch" href="{R}/prefetch"/>
<script type="text/javascript" src="evil.js"></script>
<script type="text/javascript" src="{R}/remote.js"></script>
<script type="text/javascript">
window.__sylviaInline = true;
document.documentElement.setAttribute('data-sylvia-pwned', 'inline');
try {{ fetch('{R}/inline-fetch'); }} catch (e) {{}}
try {{ new Image().src = '{R}/inline-image'; }} catch (e) {{}}
</script>"""
H_BODY = f"""<p id="target">This hostile fixture paragraph is ordinary text that the reader must still display.</p>
<img src="{R}/remote-img.png" alt="remote image"/>
<img src="missing.png" alt="missing" onerror="window.__sylviaOnerror = true"/>
<p><a id="jslink" href="javascript:window.__sylviaJsUrl = true">javascript link</a></p>
<iframe src="{R}/iframe" title="remote frame"></iframe>
<object data="{R}/object" type="text/html"></object>
<video poster="{R}/poster.png" src="{R}/video.mp4" preload="auto"></video>
<audio src="{R}/audio.mp3" preload="auto" autoplay="autoplay"></audio>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20">
  <script type="text/javascript">window.__sylviaSvg = true;</script>
  <image xlink:href="{R}/svg-image.png" width="10" height="10"/>
</svg>
<div style="background-image: url('{R}/inline-style-bg.png')">Inline style with a remote background.</div>
<form action="{R}/form" method="get"><p><input type="text" name="q" value="x"/></p></form>
<p id="tail">End of the hostile chapter.</p>"""
H_EVIL_JS = f"""window.__sylviaExternal = true;
document.documentElement.setAttribute('data-sylvia-pwned-external', '1');
try {{ fetch('{R}/external-js-fetch'); }} catch (e) {{}}
try {{ var x = new XMLHttpRequest(); x.open('GET', '{R}/xhr'); x.send(); }} catch (e) {{}}
try {{ new WebSocket('ws://{PLACEHOLDER}/ws'); }} catch (e) {{}}
try {{ navigator.sendBeacon('{R}/beacon', 'x'); }} catch (e) {{}}
"""
H_CSS = f"""@import url("{R}/import.css");
@font-face {{ font-family: "Remote Face"; src: url("{R}/font.woff"); }}
body {{ background-image: url("{R}/css-bg.png"); }}
#tail {{ font-family: "Remote Face", serif; }}
"""
H_C2 = f"""<p id="refresh-target">This chapter carries a meta refresh and a base element that point at the loopback recorder.</p>
<img src="base-relative.png" alt="relative to a remote base"/>"""
hostile_items = [
    ("c1", "c1.xhtml", "application/xhtml+xml", "scripted remote-resources"),
    ("c2", "c2.xhtml", "application/xhtml+xml", "remote-resources"),
    ("js", "evil.js", "text/javascript", None),
    ("css", "style.css", "text/css", None),
]
hostile_entries = [
    ("META-INF/container.xml", CONTAINER),
    ("OEBPS/content.opf", opf("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000002", "Sylvia Hostile Fixture", hostile_items, ["c1", "c2"])),
    ("OEBPS/nav.xhtml", nav([("c1.xhtml", "Scripts and remote resources"), ("c2.xhtml", "Refresh and base")])),
    ("OEBPS/c1.xhtml", xhtml("Scripts and remote resources", H_BODY, head=H_HEAD).replace("<body>", '<body onload="window.__sylviaOnload = true">')),
    ("OEBPS/c2.xhtml", xhtml("Refresh and base", H_C2, head=f'\n<meta http-equiv="refresh" content="0;url={R}/meta-refresh"/>\n<base href="{R}/base/"/>')),
    ("OEBPS/evil.js", H_EVIL_JS),
    ("OEBPS/style.css", H_CSS),
]
write_epub(os.path.join(OUT, "g01-hostile.epub"), hostile_entries, stored=True)

# Shared small valid book for the archive-level fixtures.
def small_book(uid, title, c2_body="<p>Second chapter text.</p>", extra_items=(), extra_entries=()):
    return simple_book(uid, title, [
        ("c1", "c1.xhtml", "Chapter One", '<p id="first">' + FILLER * 2 + "</p>"),
        ("c2", "c2.xhtml", "Chapter Two", c2_body),
    ], extra_items, extra_entries)

# 3. Path traversal and absolute paths ------------------------------------------------------------------
trav = small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000003", "Sylvia Traversal Fixture",
                  extra_items=[("outside", "../../../../../../../../etc/hosts", "application/xhtml+xml", None)])
trav += [
    ("../g01-escape-marker.txt", "SYLVIA-ESCAPE-MARKER parent directory"),
    ("../../../../../../../../tmp/g01-escape-marker.txt", "SYLVIA-ESCAPE-MARKER deep traversal"),
    ("/tmp/g01-absolute-marker.txt", "SYLVIA-ESCAPE-MARKER absolute path"),
    ("OEBPS/../../g01-escape-marker-2.txt", "SYLVIA-ESCAPE-MARKER embedded dot-dot"),
]
write_epub(os.path.join(OUT, "g01-traversal.epub"), trav)

# 4. Symlink entry ---------------------------------------------------------------------------------------
def add_symlink(z):
    zi = zipfile.ZipInfo("OEBPS/c2.xhtml", date_time=WHEN)
    zi.create_system = 3
    zi.external_attr = (0o120777 << 16)
    zi.compress_type = zipfile.ZIP_STORED
    z.writestr(zi, b"/etc/hosts")
sym = [e for e in small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000004", "Sylvia Symlink Fixture") if e[0] != "OEBPS/c2.xhtml"]
write_epub(os.path.join(OUT, "g01-symlink.epub"), sym, extra=add_symlink)

# 5/6. Decompression bomb (honest and lying sizes) ------------------------------------------------------------
BOMB_SIZE = 200 * 1024 * 1024
def bomb_body():
    head = xhtml("Chapter Two", "<p>BOMB-START").split("BOMB-START")[0] + "<p>"
    tail = "</p>\n</body>\n</html>\n"
    pad = BOMB_SIZE - len(head) - len(tail)
    return head.encode() + b" " * pad + tail.encode()
bomb_entries = [e for e in small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000005", "Sylvia Bomb Fixture") if e[0] != "OEBPS/c2.xhtml"]
bomb_entries.append(("OEBPS/c2.xhtml", bomb_body()))
bomb_path = os.path.join(OUT, "g01-bomb.epub")
write_epub(bomb_path, bomb_entries)

def patch_declared_size(src, dst, entry_name, new_size):
    data = bytearray(open(src, "rb").read())
    name = entry_name.encode()
    # Local file header: signature PK\x03\x04, uncompressed size at offset 22.
    i = 0
    patched_local = patched_central = 0
    while True:
        i = data.find(b"PK\x03\x04", i)
        if i < 0: break
        n = struct.unpack_from("<H", data, i + 26)[0]
        if data[i + 30:i + 30 + n] == name:
            struct.pack_into("<I", data, i + 22, new_size); patched_local += 1
        i += 4
    i = 0
    while True:
        i = data.find(b"PK\x01\x02", i)
        if i < 0: break
        n = struct.unpack_from("<H", data, i + 28)[0]
        if data[i + 46:i + 46 + n] == name:
            struct.pack_into("<I", data, i + 24, new_size); patched_central += 1
        i += 4
    assert patched_local == 1 and patched_central == 1, (patched_local, patched_central)
    open(dst, "wb").write(bytes(data))
patch_declared_size(bomb_path, os.path.join(OUT, "g01-bomb-lying.epub"), "OEBPS/c2.xhtml", 4096)

# 7. Truncated archive ------------------------------------------------------------------------------------------
u = open(os.path.join(OUT, "g01-unicode.epub"), "rb").read()
open(os.path.join(OUT, "g01-truncated.epub"), "wb").write(u[: int(len(u) * 0.55)])

# 8. IDPF font obfuscation (must still open) -------------------------------------------------------------------
FONT_UID = "urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000008"
font_plain = b"\x00\x01\x00\x00" + bytes((i * 37 + 11) % 256 for i in range(4092))  # synthetic, not a usable font
key = hashlib.sha1("".join(FONT_UID.split()).encode()).digest()
font_obf = bytes(b ^ key[i % 20] if i < 1040 else b for i, b in enumerate(font_plain))
ENC_FONT = """<?xml version="1.0" encoding="UTF-8"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/sylvia-test.otf"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>
"""
font_entries = simple_book(FONT_UID, "Sylvia Obfuscated Font Fixture", [
    ("c1", "c1.xhtml", "Chapter One", '<p id="first">' + FILLER * 2 + "</p>"),
    ("c2", "c2.xhtml", "Chapter Two", "<p>Second chapter text.</p>"),
], extra_items=[("font", "fonts/sylvia-test.otf", "font/otf", None)],
   extra_entries=[("META-INF/encryption.xml", ENC_FONT), ("OEBPS/fonts/sylvia-test.otf", font_obf)])
write_epub(os.path.join(OUT, "g01-font-obfuscated.epub"), font_entries)
open(os.path.join(OUT, "g01-font-obfuscated.font-plain.sha256"), "w").write(hashlib.sha256(font_plain).hexdigest() + "\n")

# 9. Content encryption without a supported licence ----------------------------------------------------------------
# Real AES-CBC encryption of a real chapter, in the W3C XML Encryption layout EPUB uses (16-byte IV followed by the
# ciphertext, PKCS#7 padding). The keys are fixed fixture values derived from public strings, so the archives are
# deterministic; they are not secrets and protect nothing. The adapter never decrypts: the tests check that Readium
# alone serves these bytes unchanged and that Sylvia refuses the book with an unsupported-protection error.
PROTECTED_C2 = ('<p id="protected">This chapter is encrypted with AES in the fixture. A reader without the key sees only '
                'ciphertext, and Sylvia must say the book uses protection it does not support.</p>\n' + "<p>" + FILLER * 20 + "</p>")
PROTECTED_C2_XHTML = xhtml("Chapter Two", PROTECTED_C2).encode("utf-8")

def aes_cbc_encrypt(plain, key, iv):
    """IV || AES-CBC(plain) with PKCS#7 padding, via the system openssl; verified by decrypting again."""
    import subprocess
    algo = {16: "-aes-128-cbc", 32: "-aes-256-cbc"}[len(key)]
    ct = subprocess.run(["/usr/bin/openssl", "enc", algo, "-e", "-K", key.hex(), "-iv", iv.hex()],
                        input=plain, capture_output=True, check=True).stdout
    back = subprocess.run(["/usr/bin/openssl", "enc", algo, "-d", "-K", key.hex(), "-iv", iv.hex()],
                          input=ct, capture_output=True, check=True).stdout
    assert back == plain and len(ct) % 16 == 0 and ct[:len(plain)] != plain[:len(ct)]
    return iv + ct

KEY_256 = hashlib.sha256(b"sylvia-g01-epub-fixture-key-256 (public, not a secret)").digest()
KEY_128 = hashlib.sha256(b"sylvia-g01-epub-fixture-key-128 (public, not a secret)").digest()[:16]
IV = hashlib.sha256(b"sylvia-g01-epub-fixture-iv").digest()[:16]
cipher = aes_cbc_encrypt(PROTECTED_C2_XHTML, KEY_256, IV)
cipher_128 = aes_cbc_encrypt(PROTECTED_C2_XHTML, KEY_128, IV)
with open(os.path.join(OUT, "g01-protected-chapter.digests.txt"), "w") as f:
    f.write("# SHA-256 of OEBPS/c2.xhtml in the protected fixtures (generate-g01-epub-fixtures.sh)\n")
    f.write(f"plaintext\t{hashlib.sha256(PROTECTED_C2_XHTML).hexdigest()}\n")
    f.write(f"stored-aes256\t{hashlib.sha256(cipher).hexdigest()}\n")
    f.write(f"stored-aes128\t{hashlib.sha256(cipher_128).hexdigest()}\n")
ENC_AES ="""<?xml version="1.0" encoding="UTF-8"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#" xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/>
    <ds:KeyInfo><ds:KeyName>publisher-key-1</ds:KeyName></ds:KeyInfo>
    <enc:CipherData><enc:CipherReference URI="OEBPS/c2.xhtml"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>
"""
enc = [e for e in small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000009", "Sylvia Encrypted Chapter Fixture") if e[0] != "OEBPS/c2.xhtml"]
enc += [("META-INF/encryption.xml", ENC_AES), ("OEBPS/c2.xhtml", cipher)]
write_epub(os.path.join(OUT, "g01-encrypted-chapter.epub"), enc)

# 10. LCP-like ----------------------------------------------------------------------------------------------------
ENC_LCP = ENC_AES.replace("<ds:KeyInfo><ds:KeyName>publisher-key-1</ds:KeyName></ds:KeyInfo>",
    '<ds:KeyInfo><ds:RetrievalMethod URI="license.lcpl#/encryption/content_key" Type="http://readium.org/2014/01/lcp#EncryptedContentKey"/></ds:KeyInfo>')
LICENSE = '{"id":"00000000-0000-0000-0000-000000000000","provider":"https://fixture.invalid","issued":"2026-10-06T00:00:00Z","encryption":{"profile":"http://readium.org/lcp/basic-profile","content_key":{"algorithm":"http://www.w3.org/2001/04/xmlenc#aes256-cbc","encrypted_value":"AAAA"},"user_key":{"algorithm":"http://www.w3.org/2001/04/xmlenc#sha256","text_hint":"fixture","key_check":"AAAA"}},"links":[],"signature":{"algorithm":"http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256","certificate":"AAAA","value":"AAAA"}}\n'
lcp = [e for e in small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000010", "Sylvia LCP-like Fixture") if e[0] != "OEBPS/c2.xhtml"]
lcp += [("META-INF/encryption.xml", ENC_LCP), ("META-INF/license.lcpl", LICENSE), ("OEBPS/c2.xhtml", cipher)]
write_epub(os.path.join(OUT, "g01-lcp-like.epub"), lcp)

# 11. Adobe ADEPT-like ---------------------------------------------------------------------------------------------
ENC_ADEPT = """<?xml version="1.0" encoding="UTF-8"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#" xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
    <ds:KeyInfo><resource xmlns="http://ns.adobe.com/adept">urn:uuid:00000000-0000-0000-0000-000000000000</resource></ds:KeyInfo>
    <enc:CipherData><enc:CipherReference URI="OEBPS/c2.xhtml"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>
"""
RIGHTS = '<?xml version="1.0"?>\n<adept:rights xmlns:adept="http://ns.adobe.com/adept"><adept:licenseToken><adept:resource>urn:uuid:00000000-0000-0000-0000-000000000000</adept:resource></adept:licenseToken></adept:rights>\n'
adept = [e for e in small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000011", "Sylvia ADEPT-like Fixture") if e[0] != "OEBPS/c2.xhtml"]
adept += [("META-INF/encryption.xml", ENC_ADEPT), ("META-INF/rights.xml", RIGHTS), ("OEBPS/c2.xhtml", cipher_128)]
write_epub(os.path.join(OUT, "g01-adept-like.epub"), adept)

# 12. Deep nesting -------------------------------------------------------------------------------------------------
DEPTH = 10000
deep_body = '<p id="deep-intro">The next paragraph nests ten thousand span elements.</p>\n<p id="deep">' + "<span>" * DEPTH + "Innermost words." + "</span>" * DEPTH + "</p>"
deep = small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000012", "Sylvia Deep Nesting Fixture", c2_body=deep_body)
write_epub(os.path.join(OUT, "g01-deep-nesting.epub"), deep)

# 13. Nesting exactly at the adapter limit (256 levels: html, body, p and 253 spans) ------------------------------
LIMIT_SPANS = 253
limit_body = ('<p id="limit-intro">The next paragraph nests exactly two hundred and fifty-six elements deep.</p>\n<p id="deep">'
              + "<span>" * LIMIT_SPANS + "Words at the nesting limit." + "</span>" * LIMIT_SPANS + "</p>")
limit = small_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000013", "Sylvia Nesting Limit Fixture", c2_body=limit_body)
write_epub(os.path.join(OUT, "g01-nesting-limit.epub"), limit)

# 14. Active content in reading-order documents that are not HTML -----------------------------------------------
# An SVG content document in the spine, and a spine item declared application/xml whose root is XHTML. Neither is
# an HTML media type, so an HTML-only sanitizer would not touch them.
SVG_DOC = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" viewBox="0 0 600 200" onload="window.__sylviaSvgOnload = true">
  <script type="text/javascript">window.__sylviaSvgDoc = true; document.documentElement.setAttribute('data-sylvia-pwned', 'svg-document');</script>
  <text id="svg-text" x="10" y="40">An SVG page in the reading order.</text>
</svg>
"""
XML_DOC = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head><title>XML item</title></head>
<body>
<script type="text/javascript">window.__sylviaXmlDoc = true; document.documentElement.setAttribute('data-sylvia-pwned', 'xml-document');</script>
<p id="xml-text">A reading-order item declared as application/xml.</p>
</body>
</html>
"""
active_items = [
    ("c1", "c1.xhtml", "application/xhtml+xml", None),
    ("c2", "c2.svg", "image/svg+xml", "scripted"),
    ("c3", "c3.xml", "application/xml", None),
]
active = [
    ("META-INF/container.xml", CONTAINER),
    ("OEBPS/content.opf", opf("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000014", "Sylvia Non-HTML Active Content Fixture", active_items, ["c1", "c2", "c3"])),
    ("OEBPS/nav.xhtml", nav([("c1.xhtml", "Chapter One"), ("c2.svg", "SVG page"), ("c3.xml", "XML item")])),
    ("OEBPS/c1.xhtml", xhtml("Chapter One", '<p id="first">' + FILLER * 2 + "</p>")),
    ("OEBPS/c2.svg", SVG_DOC),
    ("OEBPS/c3.xml", XML_DOC),
]
write_epub(os.path.join(OUT, "g01-nonhtml-active.epub"), active)

# 15. Markup where a text-level sanitizer and the browser disagree about where <head> is ------------------------
# All three are well-formed XML. c1: a comment containing "<head>" before the real head (a regex that inserts a CSP
# after the first "<head>" puts it inside the comment). c2: a namespace-prefixed root, <h:html>/<h:head> (a regex for
# "<head" or "<html" finds neither). c3 is declared text/html, so WebKit parses it with its HTML parser, where "<!-->"
# is a complete (empty) comment and the script after it is live; an XML parser sees one comment holding the script.
BYPASS_C1 = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en"><!-- <head> --><head><title>Comment before head</title></head>
<body onload="window.__sylviaBypassOnload = true">
<p id="target">A comment that mentions the head element comes before the real head.</p>
<img src="missing.png" alt="" onerror="window.__sylviaBypassOnerror = true; document.documentElement.setAttribute('data-sylvia-pwned', 'onerror')"/>
</body>
</html>
"""
BYPASS_C2 = """<?xml version="1.0" encoding="UTF-8"?>
<h:html xmlns:h="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en"><h:head><h:title>Prefixed root</h:title></h:head>
<h:body onload="window.__sylviaBypassOnload = true">
<h:p id="target">The root element carries a namespace prefix.</h:p>
<h:img src="missing.png" alt="" onerror="window.__sylviaBypassOnerror = true; document.documentElement.setAttribute('data-sylvia-pwned', 'onerror')"/>
<h:script>window.__sylviaBypassInline = true;</h:script>
</h:body>
</h:html>
"""
BYPASS_C3 = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en"><head><title>Comment opener</title></head>
<body>
<!--><script>window.__sylviaBypassInline = true; document.documentElement.setAttribute('data-sylvia-pwned', 'comment-opener');</script>-->
<p id="target">An HTML parser reads the comment opener above as a whole comment.</p>
</body>
</html>
"""
bypass_items = [
    ("c1", "c1.xhtml", "application/xhtml+xml", None),
    ("c2", "c2.xhtml", "application/xhtml+xml", None),
    ("c3", "c3.html", "text/html", None),
]
bypass = [
    ("META-INF/container.xml", CONTAINER),
    ("OEBPS/content.opf", opf("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000015", "Sylvia CSP Placement Fixture", bypass_items, ["c1", "c2", "c3"])),
    ("OEBPS/nav.xhtml", nav([("c1.xhtml", "Comment before head"), ("c2.xhtml", "Prefixed root"), ("c3.html", "Comment opener")])),
    ("OEBPS/c1.xhtml", BYPASS_C1),
    ("OEBPS/c2.xhtml", BYPASS_C2),
    ("OEBPS/c3.html", BYPASS_C3),
]
write_epub(os.path.join(OUT, "g01-csp-bypass.epub"), bypass)

# 16. Nesting that a text-level depth scanner measures as shallow --------------------------------------------------
# c2: 10,000 unclosed spans after "<!-->" and before "-->" (well-formed XML: one comment; an HTML tokenizer reads
# "<!-->" as a whole comment and the spans as elements). c3: "<span></x>" 10,000 times (a scanner that pops on any end
# tag sees depth 1; an HTML parser ignores the unmatched end tags and nests every span; not well-formed XML).
NEST_C2 = ('<p id="before">Before the comment.</p>\n<!-->' + "<span>" * DEPTH + "Innermost words." + "-->\n"
           '<p id="after">After the comment.</p>')
NEST_C3 = '<p id="mismatched">' + "<span></x>" * DEPTH + "Innermost words.</p>"
nest = simple_book("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000016", "Sylvia Nesting Divergence Fixture", [
    ("c1", "c1.xhtml", "Chapter One", '<p id="first">' + FILLER * 2 + "</p>"),
    ("c2", "c2.xhtml", "Comment-wrapped nesting", NEST_C2),
    ("c3", "c3.xhtml", "Unmatched end tags", NEST_C3),
])
write_epub(os.path.join(OUT, "g01-nesting-bypass.epub"), nest)

# 17. Navigations that are not link activations, to entries the reader must not render as they are (review R2-01) --
# Readium 3.11.0 cancels link activations only, so a form submission can navigate the web view. c1 is XHTML (a page
# CSP with form-action 'none' applies); c2 is declared application/xml with an XHTML root and no script, so it cannot
# carry a page CSP. The targets: evil.html is in the archive but not in the manifest (Readium would serve it as
# text/html by its extension); decl.xml is declared application/xml but not in the spine, with an XHTML script;
# extra.xhtml is declared application/xhtml+xml but not in the spine, with a script; fake.png is declared image/png but
# holds HTML with a script.
def target_page(marker, flag, text):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en"><head><title>{text}</title></head>
<body>
<script type="text/javascript">window.{flag} = true; document.documentElement.setAttribute('data-sylvia-pwned', '{marker}');</script>
<p id="target-text">{text}</p>
</body>
</html>
"""
FORMS = """<form action="evil.html"><button id="go" type="submit">Continue</button></form>
<form action="decl.xml"><button id="go2" type="submit">Continue to the record</button></form>
<form action="fake.png"><button id="go3" type="submit">Continue to the picture</button></form>
<form action="extra.xhtml"><button id="go4" type="submit">Continue to the appendix</button></form>"""
FORM_C2 = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head><title>XML item with forms</title></head>
<body>
<p id="xml-text">A reading-order item declared as application/xml, with no script, only forms.</p>
{FORMS}
</body>
</html>
"""
form_items = [
    ("c1", "c1.xhtml", "application/xhtml+xml", None),
    ("c2", "c2.xml", "application/xml", None),
    ("decl", "decl.xml", "application/xml", None),
    ("extra", "extra.xhtml", "application/xhtml+xml", None),
    ("fake", "fake.png", "image/png", None),
]
form = [
    ("META-INF/container.xml", CONTAINER),
    ("OEBPS/content.opf", opf("urn:uuid:5a1e0c2d-0b6f-4a43-9d7e-000000000017", "Sylvia Form Navigation Fixture", form_items, ["c1", "c2"])),
    ("OEBPS/nav.xhtml", nav([("c1.xhtml", "Chapter One"), ("c2.xml", "XML item with forms")])),
    ("OEBPS/c1.xhtml", xhtml("Chapter One", '<p id="first">' + FILLER * 2 + "</p>\n" + FORMS)),
    ("OEBPS/c2.xml", FORM_C2),
    ("OEBPS/evil.html", target_page("undeclared-entry", "__sylviaEvil", "An archive entry the manifest does not declare.")),
    ("OEBPS/decl.xml", target_page("declared-xml-resource", "__sylviaEvil", "A declared XML resource outside the spine.")),
    ("OEBPS/extra.xhtml", target_page("declared-html-resource", "__sylviaEvil", "A declared XHTML resource outside the spine.")),
    ("OEBPS/fake.png", target_page("passive-type", "__sylviaEvil", "Markup declared as a PNG image.")),
]
write_epub(os.path.join(OUT, "g01-form-navigation.epub"), form)
PY

# Manifest of a fixture directory: entry-level contents (name, size, CRC-32) so a different zlib still compares
# equal. The truncated fixture is described as a prefix of g01-unicode.epub in the same directory.
manifest() {
  /usr/bin/python3 - "$1" <<'PY'
import os, sys, zipfile, hashlib
d = sys.argv[1]
print("# file\tbytes\tsha256(file)\tentries(name:size:crc32 ...) -- written by generate-g01-epub-fixtures.sh")
unicode_bytes = open(os.path.join(d, "g01-unicode.epub"), "rb").read()
for f in sorted(os.listdir(d)):
    if not f.endswith(".epub"):
        continue
    p = os.path.join(d, f)
    b = open(p, "rb").read()
    try:
        z = zipfile.ZipFile(p)
        ent = " ".join(f"{i.filename}:{i.file_size}:{i.CRC:08x}" for i in z.infolist())
    except zipfile.BadZipFile:
        if unicode_bytes.startswith(b) and len(b) == int(len(unicode_bytes) * 0.55):
            ent = "not-a-zip:first-55-percent-of:g01-unicode.epub"
        else:
            ent = f"not-a-zip:sha256:{hashlib.sha256(b).hexdigest()}"
    print(f"{f}\t{len(b)}\t{hashlib.sha256(b).hexdigest()}\t{ent}")
PY
}
manifest "$out" > "$out/MANIFEST.tsv"

if (( check )); then
  status=0
  # 1. The committed archives themselves (not just their manifest) hold the entries the generator writes.
  #    Only the entry column is compared: archive bytes may differ with another zlib.
  manifest "$committed" > "$out/COMMITTED.tsv"
  if ! diff <(cut -f1,4 "$out/COMMITTED.tsv") <(cut -f1,4 "$out/MANIFEST.tsv"); then
    echo "g01 epub fixtures: committed archives differ from the generator's output" >&2
    status=1
  fi
  # 2. The committed MANIFEST.tsv describes the committed archives exactly (all columns).
  if ! diff "$committed/MANIFEST.tsv" "$out/COMMITTED.tsv"; then
    echo "g01 epub fixtures: MANIFEST.tsv is stale" >&2
    status=1
  fi
  # 3. The small text companions are byte-identical.
  for f in g01-font-obfuscated.font-plain.sha256 g01-protected-chapter.digests.txt; do
    if ! cmp -s "$committed/$f" "$out/$f"; then
      echo "g01 epub fixtures: $f differs" >&2
      status=1
    fi
  done
  if (( status )); then exit 1; fi
  echo "g01 epub fixtures: committed archives, manifest and companions match the generator"
else
  ls -l "$out"
fi
