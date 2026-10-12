#!/usr/bin/env python3
"""Deterministic PDF fixtures for the G0.1 PDF spike (Sylvia, Stage 0).

Standard library only (no PDF library is installed on the build Mac). Every byte is a
function of this file: no timestamps, fixed document IDs, no compression (zlib output can
differ between zlib builds), integer-only numbers. Running it twice gives identical files;
`--check` verifies the committed fixtures match.

All text is original generated prose written for these fixtures (no third-party text).

Usage:
  make_pdf_fixtures.py --out DIR              # write the committed fixtures into DIR
  make_pdf_fixtures.py --check DIR            # exit 1 if DIR's fixtures differ from a fresh build
  make_pdf_fixtures.py --large PATH [--pages N]   # write the large text PDF (not committed)

Fixtures (see Spikes/G01-PDF/README.md for the full description):
  labels-multipage.pdf         8 pages; /PageLabels i, ii, iii, 1-4, A-1; multi-line paragraphs
  rotated.pdf                  /Rotate 0, 90, 180, 270, inherited 90, and 270 with offset Media/CropBox
  two-column.pdf               one two-column page
  mixed-scanned.pdf            text, image-only, text, image-only pages (no text layer on image pages)
  unicode.pdf                  non-BMP scalars, combining marks, multi-scalar glyphs via /ToUnicode
  encrypted-user-password.pdf  Standard security handler R3, RC4 128-bit, user password required
  encrypted-owner-only-nocopy.pdf  same handler, empty user password, copying not permitted
  truncated.pdf                labels-multipage.pdf cut to its first 55 % of bytes
  actions.pdf                  /OpenAction URI, page /AA URI, Link URI (canary + https), /Launch, GoTo,
                               document-level JavaScript
  actions-nonurl.pdf           links with non-URL actions: /Named NextPage, LastPage, Find, GoToPage, Print;
                               /GoToR; /ResetForm (with one text field); /JavaScript and /SubmitForm aimed at
                               the canary scheme; 3 pages
"""

import argparse
import hashlib
import os
import struct
import sys

# --------------------------------------------------------------------------------------
# Minimal PDF object model and writer
# --------------------------------------------------------------------------------------


class Name(object):
    def __init__(self, value):
        self.value = value


class Ref(object):
    def __init__(self, num):
        self.num = num


class PStr(object):
    """A PDF string. Written as hex so no escaping rules can go wrong."""

    def __init__(self, data):
        if isinstance(data, str):
            data = data.encode("latin-1")
        self.data = data


class Stream(object):
    def __init__(self, entries, data):
        self.entries = entries
        self.data = data


class Raw(object):
    """Bytes written verbatim (used for pre-formatted arrays such as the /ID)."""

    def __init__(self, data):
        self.data = data


def rc4(key, data):
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 0xFF
        s[i], s[j] = s[j], s[i]
    out = bytearray(len(data))
    i = j = 0
    for n, byte in enumerate(data):
        i = (i + 1) & 0xFF
        j = (j + s[i]) & 0xFF
        s[i], s[j] = s[j], s[i]
        out[n] = byte ^ s[(s[i] + s[j]) & 0xFF]
    return bytes(out)


PAD = bytes.fromhex("28BF4E5E4E758A4164004E56FFFA01082E2E00B6D0683E802F0CA9FE6453697A")


def pad_password(pw):
    return (pw + PAD)[:32]


class StandardSecurity(object):
    """ISO 32000-1 section 7.6.3, revision 3, RC4 with a 128-bit key (algorithms 1, 2, 3, 5)."""

    def __init__(self, user_pw, owner_pw, permissions, doc_id):
        self.n = 16
        self.p = permissions
        self.doc_id = doc_id
        # Algorithm 3: O entry
        h = hashlib.md5(pad_password(owner_pw or user_pw)).digest()
        for _ in range(50):
            h = hashlib.md5(h[: self.n]).digest()
        okey = h[: self.n]
        o = rc4(okey, pad_password(user_pw))
        for i in range(1, 20):
            o = rc4(bytes(b ^ i for b in okey), o)
        self.o = o
        # Algorithm 2: file key
        m = hashlib.md5()
        m.update(pad_password(user_pw))
        m.update(self.o)
        m.update(struct.pack("<i", self.p))
        m.update(doc_id)
        h = m.digest()
        for _ in range(50):
            h = hashlib.md5(h[: self.n]).digest()
        self.key = h[: self.n]
        # Algorithm 5: U entry
        u = rc4(self.key, hashlib.md5(PAD + doc_id).digest())
        for i in range(1, 20):
            u = rc4(bytes(b ^ i for b in self.key), u)
        self.u = u + bytes(16)

    def object_key(self, num, gen=0):
        k = self.key + struct.pack("<i", num)[:3] + struct.pack("<i", gen)[:2]
        return hashlib.md5(k).digest()[: min(self.n + 5, 16)]

    def dictionary(self):
        return {
            "Filter": Name("Standard"),
            "V": 2,
            "R": 3,
            "Length": 128,
            "O": PStr(self.o),
            "U": PStr(self.u),
            "P": self.p,
        }


class PDF(object):
    def __init__(self, ident):
        self.objects = [None]  # 1-based
        self.doc_id = hashlib.md5(("sylvia-g01-pdf:" + ident).encode("ascii")).digest()
        self.security = None
        self.encrypt_num = None

    def reserve(self):
        self.objects.append(None)
        return Ref(len(self.objects) - 1)

    def set(self, ref, value):
        self.objects[ref.num] = value
        return ref

    def add(self, value):
        return self.set(self.reserve(), value)

    def encrypt_with(self, security):
        self.security = security
        self.encrypt_num = self.add(security.dictionary()).num

    def _ser(self, v, num):
        if isinstance(v, bool):
            return b"true" if v else b"false"
        if isinstance(v, int):
            return str(v).encode("ascii")
        if v is None:
            return b"null"
        if isinstance(v, Name):
            return b"/" + v.value.encode("ascii")
        if isinstance(v, Ref):
            return ("%d 0 R" % v.num).encode("ascii")
        if isinstance(v, Raw):
            return v.data
        if isinstance(v, PStr):
            data = v.data
            if self.security is not None and num != self.encrypt_num:
                data = rc4(self.security.object_key(num), data)
            return b"<" + data.hex().upper().encode("ascii") + b">"
        if isinstance(v, list):
            return b"[" + b" ".join(self._ser(x, num) for x in v) + b"]"
        if isinstance(v, dict):
            parts = []
            for k in v:  # insertion order is the written order (deterministic)
                parts.append(b"/" + k.encode("ascii") + b" " + self._ser(v[k], num))
            return b"<<" + b" ".join(parts) + b">>"
        raise TypeError("cannot serialize %r" % (v,))

    def write(self, root, info=None):
        out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
        offsets = [0] * len(self.objects)
        for num in range(1, len(self.objects)):
            v = self.objects[num]
            offsets[num] = len(out)
            out += ("%d 0 obj\n" % num).encode("ascii")
            if isinstance(v, Stream):
                data = v.data
                if self.security is not None:
                    data = rc4(self.security.object_key(num), data)
                entries = dict(v.entries)
                entries["Length"] = len(data)
                out += self._ser(entries, num) + b"\nstream\n" + data + b"\nendstream"
            else:
                out += self._ser(v, num)
            out += b"\nendobj\n"
        xref = len(out)
        out += ("xref\n0 %d\n" % len(self.objects)).encode("ascii")
        out += b"0000000000 65535 f \n"
        for num in range(1, len(self.objects)):
            out += ("%010d 00000 n \n" % offsets[num]).encode("ascii")
        trailer = {"Size": len(self.objects), "Root": root}
        if info is not None:
            trailer["Info"] = info
        hexid = b"<" + self.doc_id.hex().upper().encode("ascii") + b">"
        trailer["ID"] = Raw(b"[" + hexid + b" " + hexid + b"]")
        if self.encrypt_num is not None:
            trailer["Encrypt"] = Ref(self.encrypt_num)
        out += b"trailer\n" + self._ser(trailer, 0) + b"\n"
        out += ("startxref\n%d\n%%%%EOF\n" % xref).encode("ascii")
        return bytes(out)


# --------------------------------------------------------------------------------------
# Content helpers
# --------------------------------------------------------------------------------------

LETTER = [0, 0, 612, 792]
FONT_SIZE = 11
LEADING = 15


def lit(data):
    """A literal string for a content stream, with every non-printable byte escaped in octal."""
    if isinstance(data, str):
        data = data.encode("latin-1")
    out = bytearray(b"(")
    for b in data:
        if b in (0x28, 0x29, 0x5C):
            out += b"\\" + bytes([b])
        elif 0x20 <= b <= 0x7E:
            out.append(b)
        else:
            out += ("\\%03o" % b).encode("ascii")
    out += b")"
    return bytes(out)


def text_line(font, size, x, y, data):
    return b"BT /" + font.encode("ascii") + (" %d Tf %d %d Td " % (size, x, y)).encode("ascii") + lit(data) + b" Tj ET\n"


def text_line_tj(font, size, x, y, parts):
    """parts: list of bytes (shown) and ints (TJ adjustments in thousandths of an em)."""
    body = b" ".join(lit(p) if isinstance(p, (bytes, str)) else str(p).encode("ascii") for p in parts)
    return b"BT /" + font.encode("ascii") + (" %d Tf %d %d Td " % (size, x, y)).encode("ascii") + b"[" + body + b"] TJ ET\n"


def wrap(text, width):
    words = text.split(" ")
    lines, cur = [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = w if not cur else cur + " " + w
    if cur:
        lines.append(cur)
    return lines


def paragraph_block(paragraphs, x, top, width_chars, font="F1", size=FONT_SIZE, leading=LEADING):
    """Lays out paragraphs from `top` downward; a blank line separates paragraphs."""
    out = bytearray()
    y = top
    for para in paragraphs:
        for line in wrap(para, width_chars):
            out += text_line(font, size, x, y, line)
            y -= leading
        y -= leading
    return bytes(out), y


HELVETICA = {"Type": Name("Font"), "Subtype": Name("Type1"), "BaseFont": Name("Helvetica"), "Encoding": Name("WinAnsiEncoding")}
HELVETICA_BOLD = {"Type": Name("Font"), "Subtype": Name("Type1"), "BaseFont": Name("Helvetica-Bold"), "Encoding": Name("WinAnsiEncoding")}


def add_page(pdf, parent, content, media=None, crop=None, rotate=None, fonts=None, xobjects=None, extra=None):
    resources = {}
    if fonts:
        resources["Font"] = fonts
    if xobjects:
        resources["XObject"] = xobjects
    page = {"Type": Name("Page"), "Parent": parent}
    if media is not None:
        page["MediaBox"] = media
    if crop is not None:
        page["CropBox"] = crop
    if rotate is not None:
        page["Rotate"] = rotate
    page["Resources"] = resources
    page["Contents"] = pdf.add(Stream({}, content))
    if extra:
        page.update(extra)
    return pdf.add(page)


def simple_document(ident, build_pages, catalog_extra=None, info_title=None, pages_extra=None, security=None):
    pdf = PDF(ident)
    if security is not None:
        sec = security(pdf.doc_id)
        pdf.encrypt_with(sec)
    catalog = pdf.reserve()
    pages = pdf.reserve()
    f1 = pdf.add(dict(HELVETICA))
    f2 = pdf.add(dict(HELVETICA_BOLD))
    kids = build_pages(pdf, pages, {"F1": f1, "F2": f2})
    pages_dict = {"Type": Name("Pages"), "Kids": kids, "Count": len(kids), "MediaBox": LETTER}
    if pages_extra:
        pages_dict.update(pages_extra)
    pdf.set(pages, pages_dict)
    cat = {"Type": Name("Catalog"), "Pages": pages}
    if catalog_extra:
        cat.update(catalog_extra(pdf) if callable(catalog_extra) else catalog_extra)
    pdf.set(catalog, cat)
    info = None
    if info_title is not None:
        info = pdf.add({"Title": PStr(info_title), "Producer": PStr("Sylvia make_pdf_fixtures.py")})
    return pdf.write(catalog, info)


# --------------------------------------------------------------------------------------
# Prose (original, generated for these fixtures)
# --------------------------------------------------------------------------------------

FRONT = [
    ["Preface. This volume was assembled to test how a reader keeps its place. "
     "Every sentence here was written for the fixture and carries no outside text. "
     "The front matter uses roman numerals so that the printed label never equals the physical page."],
    ["Acknowledgements. The author thanks the patient pages that agreed to be rotated, cropped, "
     "split into columns and scanned without complaint. Their cooperation made the measurements possible."],
    ["Contents. One, the pond in winter. Two, the heron at the inlet. Three, the ledger of small things. "
     "Four, what the lamp showed. Appendix, notes on the method."],
]

BODY = [
    ["The pond in winter keeps its own counsel. Under a skin of grey ice the water still moves, slowly, "
     "turning over the cold it gathered in the night. A walker who stops at the shore hears it settle.",
     "Snow lies in the reeds like paper folded and forgotten. The light arrives late and leaves early, "
     "and in between it is careful, touching each stone as if it were counting them."],
    ["The heron at the inlet waited without moving for the length of a long breath. Its patience was not "
     "idleness; it was attention held so steadily that the fish forgot it was there.",
     "When it struck, the water closed over the place so quickly that the ripple seemed to come first. "
     "Then the bird stood as before, and the inlet resumed its quiet business."],
    ["The ledger of small things records what nobody else will: the first frost on the pump handle, the day "
     "the wrens left, the hour the stove went out and the room stayed warm anyway.",
     "Kept faithfully, such a ledger becomes a map of attention. It shows not what happened in the world "
     "but what a person was willing to notice, which is a different and more useful history."],
    ["What the lamp showed was only the table, the open book and the edge of a hand. Beyond that circle the "
     "room existed by memory alone, and memory furnished it generously.",
     "Reading by such a light, one learns that a page is a place. It has a top and a bottom, a margin to "
     "write in, and a particular line where the eye returns after looking up."],
]

APPENDIX = [
    "Appendix. Notes on the method. Each page of this fixture was generated by a small script so that the "
    "words, their positions and the page labels are known in advance and can be checked exactly.",
]


# --------------------------------------------------------------------------------------
# Fixtures
# --------------------------------------------------------------------------------------


def page_header(label_text):
    return text_line("F2", 9, 72, 760, label_text)


def labels_multipage():
    def pages(pdf, parent, fonts):
        kids = []
        for i, paras in enumerate(FRONT):
            content, _ = paragraph_block(paras, 72, 700, 78)
            kids.append(add_page(pdf, parent, page_header("Front matter, physical page %d" % (i + 1)) + content, fonts=fonts))
        for i, paras in enumerate(BODY):
            content, _ = paragraph_block(paras, 72, 700, 78)
            kids.append(add_page(pdf, parent, page_header("Body, physical page %d" % (i + 4)) + content, fonts=fonts))
        content, _ = paragraph_block(APPENDIX, 72, 700, 78)
        kids.append(add_page(pdf, parent, page_header("Appendix, physical page 8") + content, fonts=fonts))
        return kids

    labels = {"PageLabels": {"Nums": [0, {"S": Name("r")}, 3, {"S": Name("D")}, 7, {"S": Name("D"), "P": PStr("A-")}]}}
    return simple_document("labels-multipage", pages, catalog_extra=labels, info_title="Sylvia G0.1 PDF fixture: page labels")


ROTATION_TEXT = [
    "This page tests rotation. The words are written in unrotated page space and the page dictionary "
    "asks the viewer to turn the page for display. A highlight saved here must land on the same words "
    "however the page is turned.",
    "Second paragraph on the rotated page. The quiet water held the evening light a little longer than "
    "the sky did, as if it were reluctant to give it back.",
]


def rotated():
    def pages(pdf, parent, fonts):
        kids = []
        for rot in (0, 90, 180, 270):
            content, _ = paragraph_block(ROTATION_TEXT, 72, 700, 78)
            kids.append(add_page(pdf, parent, page_header("Rotate %d" % rot) + content, rotate=rot, fonts=fonts))
        # Rotation inherited from an intermediate /Pages node.
        sub = pdf.reserve()
        content, _ = paragraph_block(ROTATION_TEXT, 72, 700, 78)
        leaf = add_page(pdf, sub, page_header("Rotate 90 inherited from the page tree") + content, fonts=fonts)
        pdf.set(sub, {"Type": Name("Pages"), "Parent": parent, "Kids": [leaf], "Count": 1, "Rotate": 90})
        kids.append(sub)
        # Offset MediaBox origin, a CropBox inside it, and rotation 270.
        content, _ = paragraph_block(ROTATION_TEXT, 40, 640, 70)
        kids.append(add_page(pdf, parent, page_header("Rotate 270 with offset MediaBox and CropBox") + content,
                             media=[-40, -60, 572, 732], crop=[20, 30, 540, 700], rotate=270, fonts=fonts))
        return kids

    def build():
        # Count must include the leaf under the intermediate node; simple_document counts kids,
        # which is correct here because each kid holds exactly one page.
        return simple_document("rotated", pages, info_title="Sylvia G0.1 PDF fixture: rotation")

    return build()


LEFT_COLUMN = [
    "Left column. The first column describes the shoreline in the morning, when mist stands on the "
    "water and the far bank is only a suggestion of darker grey.",
    "It continues with the boats drawn up on the gravel, each one turned over to keep the rain out, "
    "their keels in a row like the spines of closed books.",
]
RIGHT_COLUMN = [
    "Right column. The second column takes up the afternoon, when the wind comes round to the west and "
    "the water breaks into small bright pieces that will not hold still.",
    "By evening the two columns meet again in the same quiet, and a reader who followed both has "
    "walked the whole day along the shore.",
]


def two_column():
    def pages(pdf, parent, fonts):
        title = text_line("F2", 13, 72, 730, "Two-column page: read the left column first, then the right")
        left, _ = paragraph_block(LEFT_COLUMN, 72, 700, 38)
        right, _ = paragraph_block(RIGHT_COLUMN, 324, 700, 38)
        return [add_page(pdf, parent, page_header("Two columns") + title + left + right, fonts=fonts)]

    return simple_document("two-column", pages, info_title="Sylvia G0.1 PDF fixture: two columns")


def rle_encode(data):
    """PDF RunLengthDecode encoder (ISO 32000-1 7.4.5)."""
    out = bytearray()
    i, n = 0, len(data)
    while i < n:
        run = 1
        while i + run < n and run < 128 and data[i + run] == data[i]:
            run += 1
        if run > 1:
            out += bytes([257 - run, data[i]])
            i += run
            continue
        j = i + 1
        while j < n and j - i < 128 and not (j + 1 < n and data[j] == data[j + 1]):
            j += 1
        out += bytes([j - i - 1]) + data[i:j]
        i = j
    out += b"\x80"
    return bytes(out)


def scanned_image(seed, width=240, height=310):
    """A grey 'scanned page': dark bars shaped like lines of text, deterministic per seed."""
    rows = []
    state = seed
    line_lengths = []
    for k in range(24):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        line_lengths.append(150 + state % 50 if k % 6 != 5 else 0)
    for y in range(height):
        row = bytearray([246] * width)  # off-white paper
        band = (y - 20) // 12
        within = (y - 20) % 12
        if y >= 20 and band < len(line_lengths) and 2 <= within <= 8 and line_lengths[band]:
            for x in range(25, 25 + line_lengths[band]):
                if (x // 7) % 6 != 5:  # gaps between "words"
                    row[x] = 52
        rows.append(bytes(row))
    raw = b"".join(rows)
    return Stream({"Type": Name("XObject"), "Subtype": Name("Image"), "Width": width, "Height": height,
                   "ColorSpace": Name("DeviceGray"), "BitsPerComponent": 8, "Filter": Name("RunLengthDecode")},
                  rle_encode(raw))


MIXED_TEXT = [
    ["Mixed document, page one. This page has a real text layer, so selection, search and capture work "
     "here. The next page is a scanned image with no text behind it."],
    ["Mixed document, page three. Text features return on this page because it carries selectable text. "
     "The lantern by the gate was lit at dusk and left burning until the last cart came home."],
]


def mixed_scanned():
    def pages(pdf, parent, fonts):
        kids = []
        c, _ = paragraph_block(MIXED_TEXT[0], 72, 700, 78)
        kids.append(add_page(pdf, parent, page_header("Mixed: text page") + c, fonts=fonts))
        img = pdf.add(scanned_image(7))
        kids.append(add_page(pdf, parent, b"q 468 0 0 604 72 120 cm /Im1 Do Q\n", xobjects={"Im1": img}))
        c, _ = paragraph_block(MIXED_TEXT[1], 72, 700, 78)
        kids.append(add_page(pdf, parent, page_header("Mixed: text page") + c, fonts=fonts))
        img2 = pdf.add(scanned_image(11))
        kids.append(add_page(pdf, parent, b"q 468 0 0 604 72 120 cm /Im1 Do Q\n", xobjects={"Im1": img2}))
        return kids

    return simple_document("mixed-scanned", pages, info_title="Sylvia G0.1 PDF fixture: mixed scanned pages")


def utf16be_hex(s):
    return s.encode("utf-16-be").hex().upper()


# Codes above 0x7F in font F3. Each draws a standard Helvetica glyph (via /Differences) and maps to the
# Unicode text below through /ToUnicode. The drawn glyph is a stand-in for scripts the base font cannot draw
# (marked "placeholder"); the text layer carries the real characters, which is what extraction and anchors use.
UNICODE_CODES = [
    (0x80, "A", "\U0001D400"),                    # MATHEMATICAL BOLD CAPITAL A (non-BMP)
    (0x81, "B", "\U0001D401"),                    # MATHEMATICAL BOLD CAPITAL B (non-BMP)
    (0x82, "acute", "\u0301"),                    # COMBINING ACUTE ACCENT, drawn over the preceding e
    (0x83, "eacute", "\u00e9"),                   # precomposed e with acute
    (0x84, "bullet", "\U00020BB7"),               # CJK Extension B ideograph (non-BMP), placeholder glyph
    (0x85, "bullet", "\U0001F469\u200d\U0001F52C"),  # woman scientist ZWJ sequence: three scalars, one glyph
    (0x86, "Aring", "A\u030a"),                   # A + COMBINING RING ABOVE: two scalars, one glyph
    (0x87, "bullet", "\U0001F600"),               # GRINNING FACE (non-BMP), placeholder glyph
]


def unicode_font(pdf):
    cmap_lines = [
        "/CIDInit /ProcSet findresource begin",
        "12 dict begin",
        "begincmap",
        "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
        "/CMapName /Sylvia-G01-UCS def",
        "/CMapType 2 def",
        "1 begincodespacerange",
        "<00> <FF>",
        "endcodespacerange",
        "1 beginbfrange",
        "<20> <7E> <0020>",
        "endbfrange",
        "%d beginbfchar" % len(UNICODE_CODES),
    ]
    for code, _, text in UNICODE_CODES:
        cmap_lines.append("<%02X> <%s>" % (code, utf16be_hex(text)))
    cmap_lines += ["endbfchar", "endcmap", "CMapName currentdict /CMap defineresource pop", "end", "end"]
    tounicode = pdf.add(Stream({}, ("\n".join(cmap_lines) + "\n").encode("ascii")))
    differences = [0x80]
    for _, glyph, _ in UNICODE_CODES:
        differences.append(Name(glyph))
    return pdf.add({"Type": Name("Font"), "Subtype": Name("Type1"), "BaseFont": Name("Helvetica"),
                    "Encoding": {"Type": Name("Encoding"), "BaseEncoding": Name("WinAnsiEncoding"),
                                 "Differences": differences},
                    "ToUnicode": tounicode})


def unicode_doc():
    def pages(pdf, parent, fonts):
        f3 = unicode_font(pdf)
        fonts = dict(fonts)
        fonts["F3"] = f3
        c = page_header("Unicode")
        c += text_line("F1", FONT_SIZE, 72, 700, "Unicode fixture page. Each line below mixes ASCII with other scalars.")
        c += text_line("F3", FONT_SIZE, 72, 680, b"Bold math: \x80\x81 end of the math line.")
        # e (width 556) then the acute (width 333) pulled back over it and the advance restored.
        c += text_line_tj("F3", FONT_SIZE, 72, 660, [b"Decomposed: cafe", 444, b"\x82", -111, b" and precomposed: caf\x83 here."])
        c += text_line("F3", FONT_SIZE, 72, 640, b"Supplementary ideograph \x84 and emoji \x87 then sequence \x85 done.")
        c += text_line("F3", FONT_SIZE, 72, 620, b"Ring above as two scalars: \x86ngstrom unit.")
        c += text_line("F1", FONT_SIZE, 72, 600, "Closing line in plain ASCII after the special characters.")
        return [add_page(pdf, parent, c, fonts=fonts)]

    return simple_document("unicode", pages, info_title="Sylvia G0.1 PDF fixture: unicode")


ENCRYPTED_TEXT = ["This document is encrypted. A reader must not try to open it without the owner's consent, "
                  "and Sylvia does not ask for or guess a password."]

# Permission bits (ISO 32000-1 table 22). Bits 1-2 are 0; 7-8 and 13-32 are 1 for revision 3.
P_ALL = -4                      # 0xFFFFFFFC: everything permitted
P_NO_COPY = P_ALL & ~(1 << 4)   # clear bit 5 (copy or extract text and graphics); accessibility (bit 10) stays on


def encrypted(user_pw, owner_pw, perms, ident):
    def pages(pdf, parent, fonts):
        c, _ = paragraph_block(ENCRYPTED_TEXT, 72, 700, 78)
        return [add_page(pdf, parent, page_header("Encrypted") + c, fonts=fonts)]

    return simple_document(ident, pages,
                           security=lambda doc_id: StandardSecurity(user_pw, owner_pw, perms, doc_id))


CANARY = "sylvia-g01-canary"


def actions_doc():
    def pages(pdf, parent, fonts):
        c = page_header("Actions")
        lines = [
            (700, "Link A opens the canary scheme: tap here."),
            (670, "Link B points at https://example.invalid/track (reserved domain)."),
            (640, "Link C is a Launch action that names an executable."),
            (610, "Link D goes to page two inside this document."),
        ]
        for y, t in lines:
            c += text_line("F1", FONT_SIZE, 72, y, t)
        c += text_line("F1", FONT_SIZE, 72, 560, "The catalog also has an OpenAction and this page has an open (AA) action.")

        def link(y, action):
            return pdf.add({"Type": Name("Annot"), "Subtype": Name("Link"), "Rect": [68, y - 4, 400, y + 12],
                            "Border": [0, 0, 1], "A": action})

        p2 = pdf.reserve()
        annots = [
            link(700, {"S": Name("URI"), "URI": PStr(CANARY + "://link-uri")}),
            link(670, {"S": Name("URI"), "URI": PStr("https://example.invalid/track")}),
            link(640, {"S": Name("Launch"), "F": PStr("/bin/sh"), "Win": {"F": PStr("cmd.exe"), "P": PStr("/c calc")}}),
            link(610, {"S": Name("GoTo"), "D": [p2, Name("XYZ"), 0, 792, 0]}),
        ]
        p1 = add_page(pdf, parent, c, fonts=fonts, extra={
            "Annots": annots,
            "AA": {"O": {"S": Name("URI"), "URI": PStr(CANARY + "://page-open-action")}},
        })
        c2 = page_header("Actions page two") + text_line("F1", FONT_SIZE, 72, 700, "Page two. Internal links may navigate here.")
        pdf.set(p2, {"Type": Name("Page"), "Parent": parent, "Resources": {"Font": fonts},
                     "Contents": pdf.add(Stream({}, c2))})
        return [p1, p2]

    def catalog(pdf):
        js = pdf.add({"S": Name("JavaScript"), "JS": PStr("app.launchURL('" + CANARY + "://javascript', true);")})
        return {
            "OpenAction": {"S": Name("URI"), "URI": PStr(CANARY + "://open-action")},
            "Names": {"JavaScript": {"Names": [PStr("auto"), js]}},
        }

    return simple_document("actions", pages, catalog_extra=catalog, info_title="Sylvia G0.1 PDF fixture: actions")


def actions_nonurl_doc():
    """Link annotations whose actions are not URLs, so the tests can record what PDFView does with each."""
    shared = {}

    def pages(pdf, parent, fonts):
        shared.update(fonts)
        rows = [
            ("Link A is a named NextPage action.", {"S": Name("Named"), "N": Name("NextPage")}),
            ("Link B is a named LastPage action.", {"S": Name("Named"), "N": Name("LastPage")}),
            ("Link C is a named Find action.", {"S": Name("Named"), "N": Name("Find")}),
            ("Link D is a named GoToPage action.", {"S": Name("Named"), "N": Name("GoToPage")}),
            ("Link E is a named Print action.", {"S": Name("Named"), "N": Name("Print")}),
            ("Link F is a remote GoTo into another file.", {"S": Name("GoToR"), "F": PStr("other.pdf"), "D": [0, Name("Fit")]}),
            ("Link G resets the form field below.", {"S": Name("ResetForm")}),
            ("Link H runs JavaScript that asks for the canary.",
             {"S": Name("JavaScript"), "JS": PStr("app.launchURL('" + CANARY + "://javascript-link', true);")}),
            ("Link I submits the form to the canary.",
             {"S": Name("SubmitForm"), "F": {"FS": Name("URL"), "F": PStr(CANARY + "://submit-form")}, "Flags": 4}),
        ]
        c = page_header("Non-URL actions")
        annots = []
        for i, (label, action) in enumerate(rows):
            y = 700 - 28 * i
            c += text_line("F1", FONT_SIZE, 72, y, label)
            annots.append(pdf.add({"Type": Name("Annot"), "Subtype": Name("Link"), "Rect": [68, y - 6, 400, y + 14],
                                   "Border": [0, 0, 1], "A": action}))
        c += text_line("F1", FONT_SIZE, 72, 430, "Field:")
        field = pdf.add({"Type": Name("Annot"), "Subtype": Name("Widget"), "FT": Name("Tx"), "T": PStr("note"),
                         "V": PStr("Filled in"), "DV": PStr("Default"), "Rect": [120, 424, 400, 444], "F": 4,
                         "DA": PStr("/F1 11 Tf 0 g")})
        annots.append(field)
        p1 = add_page(pdf, parent, c, fonts=fonts, extra={"Annots": annots})
        kids = [p1]
        for n in ("two", "three"):
            body = page_header("Non-URL actions page " + n) + text_line("F1", FONT_SIZE, 72, 700, "Page %s of three." % n)
            kids.append(add_page(pdf, parent, body, fonts=fonts))
        shared["field"] = field
        return kids

    def catalog(pdf):
        return {"AcroForm": {"Fields": [shared["field"]], "NeedAppearances": True,
                             "DR": {"Font": {"F1": shared["F1"]}}, "DA": PStr("/F1 11 Tf 0 g")}}

    return simple_document("actions-nonurl", pages, catalog_extra=catalog,
                           info_title="Sylvia G0.1 PDF fixture: non-URL actions")


def large_doc(page_count):
    def pages(pdf, parent, fonts):
        kids = []
        for i in range(page_count):
            paras = BODY[i % len(BODY)] + ["Page marker p%05d. The fixture repeats its prose so that every page has "
                                           "about the same amount of selectable text." % (i + 1)]
            content, _ = paragraph_block(paras * 2, 72, 720, 78)
            kids.append(add_page(pdf, parent, page_header("Large fixture, physical page %d" % (i + 1)) + content, fonts=fonts))
        return kids

    labels = {"PageLabels": {"Nums": [0, {"S": Name("r")}, 10, {"S": Name("D")}]}}
    return simple_document("large-%d" % page_count, pages, catalog_extra=labels, info_title="Sylvia G0.1 PDF fixture: large")


def committed_fixtures():
    labels = labels_multipage()
    return [
        ("labels-multipage.pdf", labels),
        ("rotated.pdf", rotated()),
        ("two-column.pdf", two_column()),
        ("mixed-scanned.pdf", mixed_scanned()),
        ("unicode.pdf", unicode_doc()),
        ("encrypted-user-password.pdf", encrypted(b"sylvia-user-pw", b"sylvia-owner-pw", P_ALL, "encrypted-user-password")),
        ("encrypted-owner-only-nocopy.pdf", encrypted(b"", b"sylvia-owner-pw", P_NO_COPY, "encrypted-owner-only-nocopy")),
        ("truncated.pdf", labels[: len(labels) * 55 // 100]),
        ("actions.pdf", actions_doc()),
        ("actions-nonurl.pdf", actions_nonurl_doc()),
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", help="directory for the committed fixtures")
    ap.add_argument("--check", help="verify the fixtures in this directory match a fresh build")
    ap.add_argument("--large", help="path for the large text PDF")
    ap.add_argument("--pages", type=int, default=1000)
    args = ap.parse_args()
    if not (args.out or args.check or args.large):
        ap.error("nothing to do")
    status = 0
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for name, data in committed_fixtures():
            with open(os.path.join(args.out, name), "wb") as fh:
                fh.write(data)
            print("wrote %-34s %8d bytes  sha256 %s" % (name, len(data), hashlib.sha256(data).hexdigest()))
    if args.check:
        for name, data in committed_fixtures():
            path = os.path.join(args.check, name)
            try:
                with open(path, "rb") as fh:
                    have = fh.read()
            except IOError:
                print("MISSING  %s" % name)
                status = 1
                continue
            if have != data:
                print("DIFFERS  %s" % name)
                status = 1
            else:
                print("ok       %-34s sha256 %s" % (name, hashlib.sha256(data).hexdigest()))
    if args.large:
        data = large_doc(args.pages)
        d = os.path.dirname(os.path.abspath(args.large))
        os.makedirs(d, exist_ok=True)
        tmp = args.large + ".partial"
        with open(tmp, "wb") as fh:
            fh.write(data)
        os.replace(tmp, args.large)
        print("wrote %s  %d pages  %d bytes  sha256 %s" % (args.large, args.pages, len(data), hashlib.sha256(data).hexdigest()))
    return status


if __name__ == "__main__":
    sys.exit(main())
