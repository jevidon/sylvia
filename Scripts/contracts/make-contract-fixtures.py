#!/usr/bin/env python3
"""Writes the anchor.v1 and capture-envelope.v1 contract fixtures (ADR-0016).

    python3 -I Scripts/contracts/make-contract-fixtures.py [<output Contracts/fixtures directory>]
    python3 -I Scripts/contracts/make-contract-fixtures.py --show <scratch directory>

With no argument it rewrites Contracts/fixtures/{anchor,capture-envelope}.v1; Scripts/ci.d/11-capture-anchor-contracts.sh
writes into a scratch directory and compares, so the committed fixtures are exactly what this script produces. With
--show it writes into the scratch directory and prints, for every invalid fixture, the schema errors it actually
fails with beside the errors listed here, to review a change to the schemas or the fixtures.

Valid fixtures are built here from real Stage 0 output where it exists (G0.1 EPUB and PDF anchor samples, the G0.4
capture probe's records), adapted exactly as Scripts/check-spike-anchors.py adapts spike output, and otherwise from
public-domain text (Walden, Walking, Meditations). A fixture constructed from a real sample (a narrower or wider
selection at the same place) says so where it is built.

Every invalid and semantic-invalid fixture is a valid fixture with the JSON Pointer operations listed below, written
to the fixture directory's mutations.json, which the checker re-applies. Each lists what it must fail with, written
by hand here and compared exactly by the checker: for an invalid fixture the schema errors (validator keyword,
instance path, schema path with allOf members named by title, and the missing property of a required or
dependentRequired error); for a semantic-invalid fixture the one code-checked rule, the one its name starts with.
Most invalid fixtures are one operation and fail with one error. Two operations are used only where a field must be
added or removed together with the field that depends on it (quoted_text and quoted_text_origin), and the entry says
why; no invalid fixture fails with more than one error.

Fixture IDs, digests and texts are fixtures (Contracts/README.md), except the values a comment calls real: the G0.1
anchors and the G0.4 member and excerpt digests, byte counts, frame counts and timing. No transcription or model was
called: transcripts and answers are fixture text.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import re
import shutil
import sys
from pathlib import Path

def repository_root() -> Path:
    """The nearest parent holding Scripts/lib/env.sh, so the script runs unchanged wherever it lives (ADR-0016 asks
    to move it beside the checker)."""
    for parent in Path(__file__).resolve().parents:
        if (parent / "Scripts/lib/env.sh").is_file():
            return parent
    raise SystemExit("make-contract-fixtures.py: not inside the Sylvia repository")


ROOT = repository_root()
sys.dont_write_bytecode = True  # loading the checker must not leave a __pycache__ in Scripts/
spec = importlib.util.spec_from_file_location("checker", ROOT / "Scripts/check-spike-anchors.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
U = checker.fixture_uuid
LOG = checker.Adaptations()


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def dumps(doc) -> str:
    """JSON with non-ASCII text written literally; an unpaired surrogate (rule U1 fixtures) as its \\u escape."""
    text = json.dumps(doc, indent=2, ensure_ascii=False)
    return re.sub("[\ud800-\udfff]", lambda m: f"\\u{ord(m.group()):04x}", text) + "\n"


# --------------------------------------------------------------------------------------------- entry helpers


def rm(path: str) -> dict:
    return {"op": "remove", "path": path}


def rep(path: str, value) -> dict:
    return {"op": "replace", "path": path, "value": value}


def add(path: str, value) -> dict:
    return {"op": "add", "path": path, "value": value}


def err(keyword: str, instance_path: str, schema_path: str, prop: str | None = None) -> dict:
    e = {"keyword": keyword, "instance_path": instance_path, "schema_path": schema_path}
    if prop is not None:
        e["property"] = prop
    return e


def req(instance_path: str, schema_path: str, prop: str) -> dict:
    return err("required", instance_path, schema_path, prop)


def inv(fixture: str, base: str, ops, expect, why: str | None = None) -> dict:
    """An invalid fixture: `base` with `ops` (one operation, or a list), failing with exactly `expect`."""
    entry = {"fixture": f"invalid/{fixture}", "base": base, "ops": ops if isinstance(ops, list) else [ops],
             "expect": expect if isinstance(expect, list) else [expect]}
    if why:
        entry["why"] = why
    return entry


def sem(fixture: str, base: str, ops) -> dict:
    """A semantic-invalid fixture: schema-valid, breaking exactly the code-checked rule its name starts with."""
    return {"fixture": f"semantic-invalid/{fixture}", "base": base, "ops": ops if isinstance(ops, list) else [ops],
            "expect": [{"rule": fixture.split("-", 1)[0].upper()}]}


# --------------------------------------------------------------------------------------------- shared IDs

MED_WORK, MED_EPUB_ED = U("fixture/meditations/work"), U("fixture/meditations/se-epub")
MED_AUDIO_ED = U("fixture/meditations/librivox")
UNI_WORK, UNI_ED = U("fixture/g01-unicode/work"), U("fixture/g01-unicode/epub")
PDF_WORK, PDF_ED = U("fixture/g01-pdf-labels/work"), U("fixture/g01-pdf-labels/pdf")
ROT_WORK, ROT_ED = U("fixture/g01-pdf-rotated/work"), U("fixture/g01-pdf-rotated/pdf")
WALDEN_WORK, WALDEN_TXT_ED = U("fixture/walden/work"), U("fixture/walden/txt")
WALKING_WORK, WALKING_MD_ED = U("fixture/walking/work"), U("fixture/walking/md")
FIELD_WORK, FIELD_ED = U("fixture/physical-walden/work"), U("fixture/physical-walden/printed")
T0 = "2026-10-13T08:00:00Z"

# --------------------------------------------------------------------------------------------- anchors

epub_samples = {s["name"]: s for s in load("Docs/Stage0/evidence/G01-EPUB/anchor-samples.json")["capture_samples"]}
pdf_samples = {s["name"]: s for s in load("Docs/Stage0/evidence/G01-PDF/anchor-samples.json")["samples"]}

# Real EPUB anchors from the G0.1 EPUB spike (simulator), adapted as the checker adapts them.
epub_noteref = checker.adapt_epub_anchor(epub_samples["se-epub3-across-noteref"]["anchors"][0], MED_WORK, MED_EPUB_ED, LOG)
epub_cross = [checker.adapt_epub_anchor(a, UNI_WORK, UNI_ED, LOG)
              for a in epub_samples["generated-quotation-across-resources"]["anchors"]]
epub_greek = checker.adapt_epub_anchor(epub_samples["se-epub3-greek"]["anchors"][0], MED_WORK, MED_EPUB_ED, LOG)

# Constructed from the real noteref anchor: a narrower selection (one word) in the same passage, resource and asset.
epub_word = copy.deepcopy(epub_noteref)
w_at = epub_word["exact_text"].index("beneficence")
epub_word["prefix"] = epub_noteref["prefix"] + epub_noteref["exact_text"][:w_at]
epub_word["exact_text"] = "beneficence"
epub_word["text_offsets"] = dict(epub_noteref["text_offsets"], start=w_at, end=w_at + len("beneficence"))
epub_word["reader"]["locator"]["text"] = {"before": epub_word["prefix"], "highlight": "beneficence",
                                          "after": epub_noteref["suffix"]}
MED_SENTENCE = (epub_noteref["exact_text"] + ", and abstinence, not only from evil deeds, but even from evil thoughts; "
                "and further, simplicity in my way of living, far removed from the habits of the rich.")

# The real Greek anchor without text_offsets (G0.1 EPUB finding F10: offsets are omitted when ambiguous).
epub_no_offsets = copy.deepcopy(epub_greek)
del epub_no_offsets["text_offsets"]

# Constructed from the real Greek anchor: a drag that starts one scalar earlier, on the space before "that". The
# rendered selection keeps the space; the adapter looks for the text with whitespace collapsed, so its offsets are
# unchanged ([266, 325), 59 scalars for 60 scalars of exact_text). Rule A2 for EPUB follows that definition.
epub_leading_space = copy.deepcopy(epub_greek)
assert epub_greek["prefix"].endswith(" ")
epub_leading_space["exact_text"] = " " + epub_greek["exact_text"]
epub_leading_space["prefix"] = epub_greek["prefix"][:-1]
epub_leading_space["reader"]["locator"]["text"] = dict(epub_greek["reader"]["locator"]["text"],
                                                       before=epub_leading_space["prefix"],
                                                       highlight=epub_leading_space["exact_text"])

# Real PDF anchors from the G0.1 PDF spike (simulator).
pdf_multiline = checker.adapt_pdf_anchor(pdf_samples["multiline"]["anchor"], PDF_WORK, PDF_ED, LOG)
pdf_two_pages = checker.adapt_pdf_anchor(pdf_samples["multi-page"]["anchor"], PDF_WORK, PDF_ED, LOG)
pdf_rotated = checker.adapt_pdf_anchor(pdf_samples["rotate-270-offset-cropbox"]["anchor"], ROT_WORK, ROT_ED, LOG)
# Real anchors of selections composed of several pieces (G0.1 PDF ComposedSelectionTests, simulator): exact_text is
# PDFKit's composition, pieces on one page next to each other, a piece ending at a line's end keeping that break, pages
# joined with one U+000A (rule A3; ADR-0005; M0 final review R1-02).
pdf_composed = {s["name"]: s for s in load("Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json")["samples"]}
pdf_composed_one_page = checker.adapt_pdf_anchor(pdf_composed["two pieces on one page, two lines apart"]["anchor"], PDF_WORK, PDF_ED, LOG)
pdf_composed_line_break = checker.adapt_pdf_anchor(pdf_composed["a middle piece that ends at a line's end"]["anchor"], PDF_WORK, PDF_ED, LOG)
pdf_composed_two_pages = checker.adapt_pdf_anchor(pdf_composed["two pieces on one page, then one on the next page"]["anchor"],
                                                  PDF_WORK, PDF_ED, LOG)

# Text anchors: no spike produced one. Walden (1854) and Walking (1862), public domain.
WALDEN_TEXT = ("I went to the woods because I wished to live deliberately, to front only the essential facts of "
               "life, and see if I could not learn what it had to teach, and not, when I came to die, discover "
               "that I had not lived.\n")
walden_quote = "to front only the essential facts of life"
w_start = WALDEN_TEXT.index(walden_quote)
text_plain = {
    "schema_version": 1, "kind": "text", "work_id": WALDEN_WORK, "edition_id": WALDEN_TXT_ED,
    "asset_id": U("fixture/walden/txt/asset"), "asset_sha256": sha(WALDEN_TEXT), "media_type": "text/plain",
    "exact_text": walden_quote, "prefix": WALDEN_TEXT[max(0, w_start - 32):w_start],
    "suffix": WALDEN_TEXT[w_start + len(walden_quote):w_start + len(walden_quote) + 32],
    "text_range": {"unit": "unicode_scalar", "start": w_start, "end": w_start + len(walden_quote)},
    "source_text": {"extraction_version": "sylvia-text-1+utf-8", "text_sha256": sha(WALDEN_TEXT)},
}
# The emphasis is added for the fixture. The selection spans it, so exact_text is the source span with its asterisks:
# for Markdown the anchor locates source text, markup included (rule A2; ADR-0016 section 3).
WALKING_MD = ("# Walking\n\nI wish to speak a word for Nature, for *absolute freedom* and wildness, as contrasted with "
              "a freedom and culture merely civil,—to regard man as an inhabitant, or a part and parcel of Nature, "
              "rather than a member of society.\n")
walking_quote = "for *absolute freedom* and wildness"
k_start = WALKING_MD.index(walking_quote)
text_markdown = {
    "schema_version": 1, "kind": "text", "work_id": WALKING_WORK, "edition_id": WALKING_MD_ED,
    "asset_id": U("fixture/walking/md/asset"), "asset_sha256": sha(WALKING_MD), "media_type": "text/markdown",
    "exact_text": walking_quote, "prefix": WALKING_MD[k_start - 32:k_start],
    "suffix": WALKING_MD[k_start + len(walking_quote):k_start + len(walking_quote) + 32],
    "text_range": {"unit": "unicode_scalar", "start": k_start, "end": k_start + len(walking_quote)},
    "source_text": {"extraction_version": "sylvia-text-1+utf-8", "text_sha256": sha(WALKING_MD)},
    "reader": {"adapter": "sylvia-text", "adapter_version": "1",
               "locator": {"utf16_range": {"location": len(WALKING_MD[:k_start].encode("utf-16-le")) // 2,
                                           "length": len(walking_quote.encode("utf-16-le")) // 2}}},
}

# Audio anchors with the real values of the G0.4 capture probe (LibriVox Meditations, four-file MP3 book).
probe = load("Docs/Stage0/evidence/M0-contracts/g04-capture-records/context.json")
member = {m["file_name"]: m for m in probe["members"]}
P1, P2 = member["Part 1.mp3"], member["Part 2.mp3"]
audio_single = {
    "schema_version": 1, "kind": "audio", "work_id": MED_WORK, "edition_id": MED_AUDIO_ED, "timeline_revision": 1,
    "ranges": [{"asset_id": P1["asset_id"].lower(), "asset_sha256": P1["sha256"], "start_ms": 60000, "end_ms": 90000}],
}
audio_cross = {
    "schema_version": 1, "kind": "audio", "work_id": MED_WORK, "edition_id": MED_AUDIO_ED, "timeline_revision": 1,
    "ranges": [
        {"asset_id": P1["asset_id"].lower(), "asset_sha256": P1["sha256"], "start_ms": P1["duration_ms"] - 20000, "end_ms": P1["duration_ms"]},
        {"asset_id": P2["asset_id"].lower(), "asset_sha256": P2["sha256"], "start_ms": 0, "end_ms": 10000},
    ],
}
later_anchor = {
    "schema_version": 1, "kind": "later_kind_example", "work_id": MED_WORK,
    "later_field": {"opaque": True, "note": "A field only a later writer understands."},
}

anchor_valid = {
    "epub-single-resource-across-noteref.json": epub_noteref,
    "epub-first-of-two-resources.json": epub_cross[0],
    "epub-without-text-offsets.json": epub_no_offsets,
    "epub-selection-starting-at-a-space.json": epub_leading_space,
    "pdf-multiline-printed-label.json": pdf_multiline,
    "pdf-two-pages.json": pdf_two_pages,
    "pdf-composed-two-pieces-on-one-page.json": pdf_composed_one_page,
    "pdf-composed-piece-keeping-its-line-break.json": pdf_composed_line_break,
    "pdf-composed-pieces-on-two-pages.json": pdf_composed_two_pages,
    "pdf-rotated-270-offset-cropbox-no-label.json": pdf_rotated,
    "text-plain.json": text_plain,
    "text-markdown-with-reader-locator.json": text_markdown,
    "audio-single-file.json": audio_single,
    "audio-cross-file.json": audio_cross,
    "unknown-kind-from-a-later-writer.json": later_anchor,
}

E, P, T, A = "epub-single-resource-across-noteref.json", "pdf-two-pages.json", "text-plain.json", "audio-cross-file.json"
AS = "audio-single-file.json"
EPUB_THEN, PDF_THEN, TEXT_THEN, AUDIO_THEN = "allOf[epub]/then", "allOf[pdf]/then", "allOf[text]/then", "allOf[audio]/then"
SEG = f"{PDF_THEN}/properties/segments/items"
RANGE = f"{AUDIO_THEN}/properties/ranges/items"
anchor_ops = [
    inv("missing-schema-version.json", E, rm("/schema_version"), req("", "required", "schema_version")),
    inv("newer-schema-version.json", E, rep("/schema_version", 2), err("const", "/schema_version", "properties/schema_version/const")),
    inv("missing-kind.json", E, rm("/kind"), req("", "required", "kind")),
    inv("missing-work-id.json", E, rm("/work_id"), req("", "required", "work_id")),
    inv("uppercase-work-id.json", E, rep("/work_id", MED_WORK.upper()), err("pattern", "/work_id", "properties/work_id/pattern")),
    inv("kind-uppercase.json", E, rep("/kind", "EPUB"), err("pattern", "/kind", "properties/kind/pattern")),
    inv("secret-field-name.json", E, add("/token", "not-a-real-token"), err("not", "", "propertyNames/not")),
    # EPUB: identity and digest, the located text and its context, the opaque locator, the offsets and their unit.
    inv("epub-missing-edition-id.json", E, rm("/edition_id"), req("", f"{EPUB_THEN}/required", "edition_id")),
    inv("epub-missing-asset-id.json", E, rm("/asset_id"), req("", f"{EPUB_THEN}/required", "asset_id")),
    inv("epub-missing-asset-sha256.json", E, rm("/asset_sha256"), req("", f"{EPUB_THEN}/required", "asset_sha256")),
    inv("epub-uppercase-asset-sha256.json", E, rep("/asset_sha256", epub_noteref["asset_sha256"].upper()),
        err("pattern", "/asset_sha256", f"{EPUB_THEN}/properties/asset_sha256/pattern")),
    inv("epub-missing-resource-href.json", E, rm("/resource_href"), req("", f"{EPUB_THEN}/required", "resource_href")),
    inv("epub-missing-resource-media-type.json", E, rm("/resource_media_type"), req("", f"{EPUB_THEN}/required", "resource_media_type")),
    inv("epub-missing-exact-text.json", E, rm("/exact_text"), req("", f"{EPUB_THEN}/required", "exact_text")),
    inv("epub-empty-exact-text.json", E, rep("/exact_text", ""), err("minLength", "/exact_text", f"{EPUB_THEN}/properties/exact_text/minLength")),
    inv("epub-missing-prefix.json", E, rm("/prefix"), req("", f"{EPUB_THEN}/required", "prefix")),
    inv("epub-missing-suffix.json", E, rm("/suffix"), req("", f"{EPUB_THEN}/required", "suffix")),
    inv("epub-missing-reader.json", E, rm("/reader"), req("", f"{EPUB_THEN}/required", "reader")),
    inv("epub-missing-reader-adapter.json", E, rm("/reader/adapter"), req("/reader", f"{EPUB_THEN}/properties/reader/required", "adapter")),
    inv("epub-missing-reader-locator.json", E, rm("/reader/locator"), req("/reader", f"{EPUB_THEN}/properties/reader/required", "locator")),
    inv("epub-missing-reader-adapter-version.json", E, rm("/reader/adapter_version"),
        req("/reader", f"{EPUB_THEN}/properties/reader/required", "adapter_version")),
    inv("epub-text-offsets-in-utf16.json", E, rep("/text_offsets/unit", "utf16"),
        err("const", "/text_offsets/unit", f"{EPUB_THEN}/properties/text_offsets/properties/unit/const")),
    inv("epub-text-offsets-without-unit.json", E, rm("/text_offsets/unit"),
        req("/text_offsets", f"{EPUB_THEN}/properties/text_offsets/required", "unit")),
    inv("epub-text-offsets-without-extraction-version.json", E, rm("/text_offsets/extraction_version"),
        req("/text_offsets", f"{EPUB_THEN}/properties/text_offsets/required", "extraction_version")),
    inv("epub-null-text-offsets.json", E, rep("/text_offsets", None), err("type", "/text_offsets", f"{EPUB_THEN}/properties/text_offsets/type")),
    inv("epub-progression-above-one.json", E, rep("/progression", 1.5), err("maximum", "/progression", f"{EPUB_THEN}/properties/progression/maximum")),
    inv("epub-position-zero.json", E, rep("/position", 0), err("minimum", "/position", f"{EPUB_THEN}/properties/position/minimum")),
    inv("epub-segment-count-one.json", E, add("/segment", {"index": 0, "count": 1}),
        err("minimum", "/segment/count", f"{EPUB_THEN}/properties/segment/properties/count/minimum")),
    # PDF: identity and digest, the text, the extraction, and per segment the page, label, rotation, box, range and geometry.
    inv("pdf-missing-edition-id.json", P, rm("/edition_id"), req("", f"{PDF_THEN}/required", "edition_id")),
    inv("pdf-missing-asset-id.json", P, rm("/asset_id"), req("", f"{PDF_THEN}/required", "asset_id")),
    inv("pdf-missing-asset-sha256.json", P, rm("/asset_sha256"), req("", f"{PDF_THEN}/required", "asset_sha256")),
    inv("pdf-missing-exact-text.json", P, rm("/exact_text"), req("", f"{PDF_THEN}/required", "exact_text")),
    inv("pdf-missing-extraction-platform.json", P, rm("/extraction/platform"),
        req("/extraction", f"{PDF_THEN}/properties/extraction/required", "platform")),
    inv("pdf-missing-segments.json", P, rm("/segments"), req("", f"{PDF_THEN}/required", "segments")),
    inv("pdf-no-segments.json", P, rep("/segments", []), err("minItems", "/segments", f"{PDF_THEN}/properties/segments/minItems")),
    inv("pdf-missing-reader.json", P, rm("/reader"), req("", f"{PDF_THEN}/required", "reader")),
    inv("pdf-segment-missing-page-index.json", P, rm("/segments/0/page_index"), req("/segments/0", f"{SEG}/required", "page_index")),
    inv("pdf-negative-page-index.json", P, rep("/segments/0/page_index", -1),
        err("minimum", "/segments/0/page_index", f"{SEG}/properties/page_index/minimum")),
    inv("pdf-null-page-label.json", "pdf-rotated-270-offset-cropbox-no-label.json", add("/segments/0/page_label", None),
        err("type", "/segments/0/page_label", f"{SEG}/properties/page_label/type")),
    inv("pdf-empty-page-label.json", P, rep("/segments/0/page_label", ""),
        err("minLength", "/segments/0/page_label", f"{SEG}/properties/page_label/minLength")),
    inv("pdf-segment-missing-page-rotation.json", P, rm("/segments/0/page_rotation"), req("/segments/0", f"{SEG}/required", "page_rotation")),
    inv("pdf-rotation-45.json", P, rep("/segments/0/page_rotation", 45),
        err("enum", "/segments/0/page_rotation", f"{SEG}/properties/page_rotation/enum")),
    inv("pdf-segment-missing-page-box.json", P, rm("/segments/0/page_box"), req("/segments/0", f"{SEG}/required", "page_box")),
    inv("pdf-page-box-not-crop.json", P, rep("/segments/0/page_box/name", "media"),
        err("const", "/segments/0/page_box/name", f"{SEG}/properties/page_box/properties/name/const")),
    inv("pdf-segment-missing-text.json", P, rm("/segments/0/text"), req("/segments/0", f"{SEG}/required", "text")),
    inv("pdf-segment-missing-text-range.json", P, rm("/segments/0/text_range"), req("/segments/0", f"{SEG}/required", "text_range")),
    inv("pdf-text-range-in-utf16.json", P, rep("/segments/0/text_range/unit", "utf16"),
        err("const", "/segments/0/text_range/unit", f"{SEG}/properties/text_range/properties/unit/const")),
    inv("pdf-text-range-without-unit.json", P, rm("/segments/0/text_range/unit"),
        req("/segments/0/text_range", f"{SEG}/properties/text_range/required", "unit")),
    inv("pdf-segment-missing-prefix.json", P, rm("/segments/0/prefix"), req("/segments/0", f"{SEG}/required", "prefix")),
    inv("pdf-segment-missing-suffix.json", P, rm("/segments/0/suffix"), req("/segments/0", f"{SEG}/required", "suffix")),
    inv("pdf-segment-without-line-rects.json", P, rep("/segments/0/line_rects", []),
        err("minItems", "/segments/0/line_rects", f"{SEG}/properties/line_rects/minItems")),
    inv("pdf-line-rect-outside-page.json", P, rep("/segments/0/line_rects/0/0", 1.2),
        err("maximum", "/segments/0/line_rects/0/0", f"{SEG}/properties/line_rects/items/prefixItems/0/maximum")),
    inv("pdf-line-rect-zero-width.json", P, rep("/segments/0/line_rects/0/2", 0),
        err("exclusiveMinimum", "/segments/0/line_rects/0/2", f"{SEG}/properties/line_rects/items/prefixItems/2/exclusiveMinimum")),
    inv("pdf-line-rect-three-numbers.json", P, rm("/segments/0/line_rects/0/3"),
        err("minItems", "/segments/0/line_rects/0", f"{SEG}/properties/line_rects/items/minItems")),
    inv("pdf-missing-page-text-sha256.json", P, rm("/segments/0/page_text_sha256"), req("/segments/0", f"{SEG}/required", "page_text_sha256")),
    # Text: identity and digest, the text, its context, the range and its unit, and the decoded text it indexes.
    inv("text-missing-edition-id.json", T, rm("/edition_id"), req("", f"{TEXT_THEN}/required", "edition_id")),
    inv("text-missing-asset-id.json", T, rm("/asset_id"), req("", f"{TEXT_THEN}/required", "asset_id")),
    inv("text-missing-asset-sha256.json", T, rm("/asset_sha256"), req("", f"{TEXT_THEN}/required", "asset_sha256")),
    inv("text-html-media-type.json", T, rep("/media_type", "text/html"), err("enum", "/media_type", f"{TEXT_THEN}/properties/media_type/enum")),
    inv("text-missing-exact-text.json", T, rm("/exact_text"), req("", f"{TEXT_THEN}/required", "exact_text")),
    inv("text-missing-prefix.json", T, rm("/prefix"), req("", f"{TEXT_THEN}/required", "prefix")),
    inv("text-missing-suffix.json", T, rm("/suffix"), req("", f"{TEXT_THEN}/required", "suffix")),
    inv("text-missing-text-range.json", T, rm("/text_range"), req("", f"{TEXT_THEN}/required", "text_range")),
    inv("text-text-range-without-unit.json", T, rm("/text_range/unit"),
        req("/text_range", f"{TEXT_THEN}/properties/text_range/required", "unit")),
    inv("text-missing-source-text.json", T, rm("/source_text"), req("", f"{TEXT_THEN}/required", "source_text")),
    inv("text-missing-source-text-digest.json", T, rm("/source_text/text_sha256"),
        req("/source_text", f"{TEXT_THEN}/properties/source_text/required", "text_sha256")),
    # Audio: the edition, the timeline revision, and per range the asset, its digest and integer asset-local times.
    inv("audio-missing-edition-id.json", A, rm("/edition_id"), req("", f"{AUDIO_THEN}/required", "edition_id")),
    inv("audio-missing-timeline-revision.json", A, rm("/timeline_revision"), req("", f"{AUDIO_THEN}/required", "timeline_revision")),
    inv("audio-no-ranges.json", A, rep("/ranges", []), err("minItems", "/ranges", f"{AUDIO_THEN}/properties/ranges/minItems")),
    inv("audio-range-missing-asset-id.json", A, rm("/ranges/1/asset_id"), req("/ranges/1", f"{RANGE}/required", "asset_id")),
    inv("audio-range-missing-asset-sha256.json", A, rm("/ranges/1/asset_sha256"), req("/ranges/1", f"{RANGE}/required", "asset_sha256")),
    inv("audio-range-missing-start.json", A, rm("/ranges/0/start_ms"), req("/ranges/0", f"{RANGE}/required", "start_ms")),
    inv("audio-range-missing-end.json", A, rm("/ranges/0/end_ms"), req("/ranges/0", f"{RANGE}/required", "end_ms")),
    inv("audio-negative-start.json", A, rep("/ranges/0/start_ms", -1), err("minimum", "/ranges/0/start_ms", f"{RANGE}/properties/start_ms/minimum")),
    inv("audio-fractional-milliseconds.json", A, rep("/ranges/1/end_ms", 9999.5), err("type", "/ranges/1/end_ms", f"{RANGE}/properties/end_ms/type")),
    inv("audio-top-level-asset-id.json", A, add("/asset_id", P1["asset_id"].lower()), err("not", "", f"{AUDIO_THEN}/not")),
    inv("audio-top-level-asset-sha256.json", A, add("/asset_sha256", P1["sha256"]), err("not", "", f"{AUDIO_THEN}/not")),
    # Each field's definition ($ref), nested requirement and bound, so that deleting any of them changes an outcome
    # (commands/mutation-pass.py; review finding R1-07).
    inv("uppercase-edition-id.json", E, rep("/edition_id", MED_EPUB_ED.upper()), err("pattern", "/edition_id", "properties/edition_id/pattern")),
    inv("epub-uppercase-asset-id.json", E, rep("/asset_id", epub_noteref["asset_id"].upper()),
        err("pattern", "/asset_id", f"{EPUB_THEN}/properties/asset_id/pattern")),
    inv("epub-media-type-not-a-media-type.json", E, rep("/resource_media_type", "XHTML"),
        err("pattern", "/resource_media_type", f"{EPUB_THEN}/properties/resource_media_type/pattern")),
    inv("epub-prefix-not-text.json", E, rep("/prefix", 42), err("type", "/prefix", f"{EPUB_THEN}/properties/prefix/type")),
    inv("epub-suffix-not-text.json", E, rep("/suffix", 42), err("type", "/suffix", f"{EPUB_THEN}/properties/suffix/type")),
    inv("epub-progression-below-zero.json", E, rep("/progression", -0.1), err("minimum", "/progression", f"{EPUB_THEN}/properties/progression/minimum")),
    inv("epub-total-progression-above-one.json", E, rep("/total_progression", 1.5),
        err("maximum", "/total_progression", f"{EPUB_THEN}/properties/total_progression/maximum")),
    inv("epub-reader-adapter-not-a-token.json", E, rep("/reader/adapter", "Readium Swift"),
        err("pattern", "/reader/adapter", f"{EPUB_THEN}/properties/reader/properties/adapter/pattern")),
    inv("epub-segment-without-index.json", E, add("/segment", {"count": 2}), req("/segment", f"{EPUB_THEN}/properties/segment/required", "index")),
    inv("epub-segment-without-count.json", E, add("/segment", {"index": 0}), req("/segment", f"{EPUB_THEN}/properties/segment/required", "count")),
    inv("epub-segment-index-negative.json", E, add("/segment", {"index": -1, "count": 2}),
        err("minimum", "/segment/index", f"{EPUB_THEN}/properties/segment/properties/index/minimum")),
    inv("epub-text-offsets-without-basis.json", E, rm("/text_offsets/basis"), req("/text_offsets", f"{EPUB_THEN}/properties/text_offsets/required", "basis")),
    inv("epub-text-offsets-other-basis.json", E, rep("/text_offsets/basis", "readium-dom"),
        err("const", "/text_offsets/basis", f"{EPUB_THEN}/properties/text_offsets/properties/basis/const")),
    inv("epub-text-offsets-without-block-index.json", E, rm("/text_offsets/block_index"),
        req("/text_offsets", f"{EPUB_THEN}/properties/text_offsets/required", "block_index")),
    inv("epub-text-offsets-negative-block-index.json", E, rep("/text_offsets/block_index", -1),
        err("minimum", "/text_offsets/block_index", f"{EPUB_THEN}/properties/text_offsets/properties/block_index/minimum")),
    inv("epub-text-offsets-without-start.json", E, rm("/text_offsets/start"), req("/text_offsets", f"{EPUB_THEN}/properties/text_offsets/required", "start")),
    inv("epub-text-offsets-negative-start.json", E, rep("/text_offsets/start", -1),
        err("minimum", "/text_offsets/start", f"{EPUB_THEN}/properties/text_offsets/properties/start/minimum")),
    inv("epub-text-offsets-without-end.json", E, rm("/text_offsets/end"), req("/text_offsets", f"{EPUB_THEN}/properties/text_offsets/required", "end")),
    inv("epub-text-offsets-end-zero.json", E, rep("/text_offsets/end", 0),
        err("minimum", "/text_offsets/end", f"{EPUB_THEN}/properties/text_offsets/properties/end/minimum")),
    # The G0.1 PDF asset ID has no hex letters, so uppercasing would not change it: a label instead of a UUID.
    inv("pdf-asset-id-not-a-uuid.json", P, rep("/asset_id", "labels.pdf"), err("pattern", "/asset_id", f"{PDF_THEN}/properties/asset_id/pattern")),
    inv("pdf-uppercase-asset-sha256.json", P, rep("/asset_sha256", pdf_two_pages["asset_sha256"].upper()),
        err("pattern", "/asset_sha256", f"{PDF_THEN}/properties/asset_sha256/pattern")),
    inv("pdf-empty-exact-text.json", P, rep("/exact_text", ""), err("minLength", "/exact_text", f"{PDF_THEN}/properties/exact_text/minLength")),
    inv("pdf-missing-extraction.json", P, rm("/extraction"), req("", f"{PDF_THEN}/required", "extraction")),
    inv("pdf-missing-extraction-extractor.json", P, rm("/extraction/extractor"), req("/extraction", f"{PDF_THEN}/properties/extraction/required", "extractor")),
    inv("pdf-missing-extraction-adapter-version.json", P, rm("/extraction/adapter_version"),
        req("/extraction", f"{PDF_THEN}/properties/extraction/required", "adapter_version")),
    inv("pdf-extraction-adapter-version-zero.json", P, rep("/extraction/adapter_version", 0),
        err("minimum", "/extraction/adapter_version", f"{PDF_THEN}/properties/extraction/properties/adapter_version/minimum")),
    inv("pdf-reader-without-adapter.json", P, rm("/reader/adapter"), req("/reader", f"{PDF_THEN}/properties/reader/required", "adapter")),
    inv("pdf-segment-missing-line-rects.json", P, rm("/segments/0/line_rects"), req("/segments/0", f"{SEG}/required", "line_rects")),
    inv("pdf-segment-empty-text.json", P, rep("/segments/0/text", ""), err("minLength", "/segments/0/text", f"{SEG}/properties/text/minLength")),
    inv("pdf-segment-prefix-not-text.json", P, rep("/segments/0/prefix", 42), err("type", "/segments/0/prefix", f"{SEG}/properties/prefix/type")),
    inv("pdf-segment-suffix-not-text.json", P, rep("/segments/0/suffix", 42), err("type", "/segments/0/suffix", f"{SEG}/properties/suffix/type")),
    inv("pdf-uppercase-page-text-sha256.json", P, rep("/segments/0/page_text_sha256", pdf_two_pages["segments"][0]["page_text_sha256"].upper()),
        err("pattern", "/segments/0/page_text_sha256", f"{SEG}/properties/page_text_sha256/pattern")),
    inv("pdf-page-box-without-name.json", P, rm("/segments/0/page_box/name"), req("/segments/0/page_box", f"{SEG}/properties/page_box/required", "name")),
    inv("pdf-page-box-without-rect.json", P, rm("/segments/0/page_box/rect"), req("/segments/0/page_box", f"{SEG}/properties/page_box/required", "rect")),
    inv("pdf-page-box-rect-three-numbers.json", P, rm("/segments/0/page_box/rect/3"),
        err("minItems", "/segments/0/page_box/rect", f"{SEG}/properties/page_box/properties/rect/minItems")),
    inv("pdf-page-box-rect-five-numbers.json", P, add("/segments/0/page_box/rect/4", 1),
        err("maxItems", "/segments/0/page_box/rect", f"{SEG}/properties/page_box/properties/rect/maxItems")),
    inv("pdf-page-box-x-not-a-number.json", P, rep("/segments/0/page_box/rect/0", "0"),
        err("type", "/segments/0/page_box/rect/0", f"{SEG}/properties/page_box/properties/rect/prefixItems/0/type")),
    inv("pdf-page-box-y-not-a-number.json", P, rep("/segments/0/page_box/rect/1", "0"),
        err("type", "/segments/0/page_box/rect/1", f"{SEG}/properties/page_box/properties/rect/prefixItems/1/type")),
    inv("pdf-page-box-zero-width.json", P, rep("/segments/0/page_box/rect/2", 0),
        err("exclusiveMinimum", "/segments/0/page_box/rect/2", f"{SEG}/properties/page_box/properties/rect/prefixItems/2/exclusiveMinimum")),
    inv("pdf-page-box-zero-height.json", P, rep("/segments/0/page_box/rect/3", 0),
        err("exclusiveMinimum", "/segments/0/page_box/rect/3", f"{SEG}/properties/page_box/properties/rect/prefixItems/3/exclusiveMinimum")),
    inv("pdf-line-rect-below-the-page.json", P, rep("/segments/0/line_rects/0/1", -0.1),
        err("minimum", "/segments/0/line_rects/0/1", f"{SEG}/properties/line_rects/items/prefixItems/1/minimum")),
    inv("pdf-line-rect-wider-than-the-page.json", P, rep("/segments/0/line_rects/0/2", 1.5),
        err("maximum", "/segments/0/line_rects/0/2", f"{SEG}/properties/line_rects/items/prefixItems/2/maximum")),
    inv("pdf-line-rect-zero-height.json", P, rep("/segments/0/line_rects/0/3", 0),
        err("exclusiveMinimum", "/segments/0/line_rects/0/3", f"{SEG}/properties/line_rects/items/prefixItems/3/exclusiveMinimum")),
    inv("pdf-line-rect-taller-than-the-page.json", P, rep("/segments/0/line_rects/0/3", 1.5),
        err("maximum", "/segments/0/line_rects/0/3", f"{SEG}/properties/line_rects/items/prefixItems/3/maximum")),
    inv("pdf-line-rect-five-numbers.json", P, add("/segments/0/line_rects/0/4", 0.5),
        err("maxItems", "/segments/0/line_rects/0", f"{SEG}/properties/line_rects/items/maxItems")),
    inv("text-uppercase-asset-id.json", T, rep("/asset_id", text_plain["asset_id"].upper()), err("pattern", "/asset_id", f"{TEXT_THEN}/properties/asset_id/pattern")),
    inv("text-uppercase-asset-sha256.json", T, rep("/asset_sha256", text_plain["asset_sha256"].upper()),
        err("pattern", "/asset_sha256", f"{TEXT_THEN}/properties/asset_sha256/pattern")),
    inv("text-missing-media-type.json", T, rm("/media_type"), req("", f"{TEXT_THEN}/required", "media_type")),
    inv("text-empty-exact-text.json", T, rep("/exact_text", ""), err("minLength", "/exact_text", f"{TEXT_THEN}/properties/exact_text/minLength")),
    inv("text-prefix-not-text.json", T, rep("/prefix", 42), err("type", "/prefix", f"{TEXT_THEN}/properties/prefix/type")),
    inv("text-suffix-not-text.json", T, rep("/suffix", 42), err("type", "/suffix", f"{TEXT_THEN}/properties/suffix/type")),
    inv("text-text-range-without-start.json", T, rm("/text_range/start"), req("/text_range", f"{TEXT_THEN}/properties/text_range/required", "start")),
    inv("text-text-range-without-end.json", T, rm("/text_range/end"), req("/text_range", f"{TEXT_THEN}/properties/text_range/required", "end")),
    inv("text-text-range-negative-start.json", T, rep("/text_range/start", -1),
        err("minimum", "/text_range/start", f"{TEXT_THEN}/properties/text_range/properties/start/minimum")),
    inv("text-text-range-end-zero.json", T, rep("/text_range/end", 0), err("minimum", "/text_range/end", f"{TEXT_THEN}/properties/text_range/properties/end/minimum")),
    inv("text-source-text-without-extraction-version.json", T, rm("/source_text/extraction_version"),
        req("/source_text", f"{TEXT_THEN}/properties/source_text/required", "extraction_version")),
    inv("text-uppercase-source-text-digest.json", T, rep("/source_text/text_sha256", text_plain["source_text"]["text_sha256"].upper()),
        err("pattern", "/source_text/text_sha256", f"{TEXT_THEN}/properties/source_text/properties/text_sha256/pattern")),
    inv("text-reader-without-locator.json", "text-markdown-with-reader-locator.json", rm("/reader/locator"),
        req("/reader", f"{TEXT_THEN}/properties/reader/required", "locator")),
    inv("audio-missing-ranges.json", A, rm("/ranges"), req("", f"{AUDIO_THEN}/required", "ranges")),
    inv("audio-timeline-revision-zero.json", A, rep("/timeline_revision", 0),
        err("minimum", "/timeline_revision", f"{AUDIO_THEN}/properties/timeline_revision/minimum")),
    inv("audio-range-asset-id-not-a-uuid.json", A, rep("/ranges/0/asset_id", "part-1"), err("pattern", "/ranges/0/asset_id", f"{RANGE}/properties/asset_id/pattern")),
    inv("audio-range-uppercase-asset-sha256.json", A, rep("/ranges/0/asset_sha256", P1["sha256"].upper()),
        err("pattern", "/ranges/0/asset_sha256", f"{RANGE}/properties/asset_sha256/pattern")),
    # Every numeric field's type: positions, counts and milliseconds are integers (Contracts/README.md, units), and
    # coordinates are numbers (review finding R2-01; commands/mutation-pass.py protects each numeric `type`).
    inv("audio-fractional-start-milliseconds.json", A, rep("/ranges/0/start_ms", audio_cross["ranges"][0]["start_ms"] + 0.5),
        err("type", "/ranges/0/start_ms", f"{RANGE}/properties/start_ms/type")),
    inv("audio-fractional-timeline-revision.json", A, rep("/timeline_revision", 1.5),
        err("type", "/timeline_revision", f"{AUDIO_THEN}/properties/timeline_revision/type")),
    inv("epub-fractional-position.json", E, rep("/position", epub_noteref["position"] + 0.5),
        err("type", "/position", f"{EPUB_THEN}/properties/position/type")),
    inv("epub-progression-not-a-number.json", E, rep("/progression", str(epub_noteref["progression"])),
        err("type", "/progression", f"{EPUB_THEN}/properties/progression/type")),
    inv("epub-segment-fractional-index.json", E, add("/segment", {"index": 0.5, "count": 2}),
        err("type", "/segment/index", f"{EPUB_THEN}/properties/segment/properties/index/type")),
    inv("epub-segment-fractional-count.json", E, add("/segment", {"index": 0, "count": 2.5}),
        err("type", "/segment/count", f"{EPUB_THEN}/properties/segment/properties/count/type")),
    inv("pdf-extraction-adapter-version-fractional.json", P, rep("/extraction/adapter_version", 1.5),
        err("type", "/extraction/adapter_version", f"{PDF_THEN}/properties/extraction/properties/adapter_version/type")),
    inv("pdf-fractional-page-index.json", P, rep("/segments/0/page_index", pdf_two_pages["segments"][0]["page_index"] + 0.5),
        err("type", "/segments/0/page_index", f"{SEG}/properties/page_index/type")),
    inv("pdf-line-rect-width-not-a-number.json", P, rep("/segments/0/line_rects/0/2", "0.1"),
        err("type", "/segments/0/line_rects/0/2", f"{SEG}/properties/line_rects/items/prefixItems/2/type")),
    inv("pdf-line-rect-height-not-a-number.json", P, rep("/segments/0/line_rects/0/3", "0.01"),
        err("type", "/segments/0/line_rects/0/3", f"{SEG}/properties/line_rects/items/prefixItems/3/type")),
    inv("pdf-page-box-width-not-a-number.json", P, rep("/segments/0/page_box/rect/2", "612"),
        err("type", "/segments/0/page_box/rect/2", f"{SEG}/properties/page_box/properties/rect/prefixItems/2/type")),
    inv("pdf-page-box-height-not-a-number.json", P, rep("/segments/0/page_box/rect/3", "792"),
        err("type", "/segments/0/page_box/rect/3", f"{SEG}/properties/page_box/properties/rect/prefixItems/3/type")),
    # Schema-valid, but each breaks exactly the code-checked rule its name starts with.
    sem("u1-prefix-with-an-unpaired-surrogate.json", E, rep("/prefix", epub_noteref["prefix"] + "\ud800")),
    sem("a1-text-offsets-empty-range.json", E, rep("/text_offsets/start", epub_noteref["text_offsets"]["end"])),
    sem("a1-audio-range-ends-before-it-starts.json", AS, rep("/ranges/0/end_ms", 50000)),
    sem("a2-epub-text-offsets-shorter-than-text.json", E, rep("/text_offsets/end", epub_noteref["text_offsets"]["end"] - 1)),
    sem("a2-epub-text-offsets-count-the-leading-space.json", "epub-selection-starting-at-a-space.json",
        rep("/text_offsets/start", epub_leading_space["text_offsets"]["start"] - 1)),
    sem("a2-pdf-text-range-longer-than-text.json", P, rep("/segments/1/text_range/end", 42)),
    sem("a2-text-range-shorter-than-text.json", T, rep("/text_range/end", text_plain["text_range"]["end"] - 1)),
    sem("a3-pdf-exact-text-joined-with-space.json", P, rep("/exact_text", " ".join(s["text"] for s in pdf_two_pages["segments"]))),
    # Each branch of A3 has a fixture (commands/mutation-pass.py): no U+000A where the page changes; and, on a real
    # composed selection, its two pieces in the wrong order.
    sem("a3-pdf-no-line-feed-where-the-page-changes.json", P, rep("/exact_text", "".join(s["text"] for s in pdf_two_pages["segments"]))),
    sem("a3-pdf-composed-pieces-out-of-order.json", "pdf-composed-two-pieces-on-one-page.json",
        rep("/exact_text", "".join(s["text"] for s in reversed(pdf_composed_one_page["segments"])))),
    sem("a4-pdf-second-segment-on-an-earlier-page.json", P, rep("/segments/1/page_index", 2)),
    sem("a5-epub-segment-index-equals-count.json", "epub-first-of-two-resources.json", rep("/segment/index", 2)),
    sem("a6-audio-second-range-not-from-start.json", A, rep("/ranges/1/start_ms", 500)),
    sem("a6-audio-same-asset-twice.json", A, rep("/ranges/1", dict(audio_cross["ranges"][0], start_ms=0, end_ms=1000))),
    sem("a6-audio-longer-than-120-seconds.json", AS, rep("/ranges/0/end_ms", 180001)),
    # The reviewer's example: x + w = 1.4.
    sem("a7-pdf-line-rect-past-the-page-box.json", P, rep("/segments/0/line_rects/0", [0.9, 0.5, 0.5, 0.01])),
    # The other edge: y + h = 1.1 (each branch of a code rule has a fixture; commands/mutation-pass.py, R2-01).
    sem("a7-pdf-line-rect-above-the-page-box.json", P, rep("/segments/0/line_rects/0", [0.1, 0.9, 0.5, 0.2])),
    # The second segment moved onto the first one's page at [380, 421): its text and length are unchanged (A2, A3
    # hold), and it starts before the first segment ends at 392 (review finding R2-01).
    sem("a4-pdf-segments-overlap-on-one-page.json", P, rep("/segments/1", dict(
        pdf_two_pages["segments"][1], page_index=pdf_two_pages["segments"][0]["page_index"],
        page_label=pdf_two_pages["segments"][0]["page_label"],
        text_range={"unit": "unicode_scalar", "start": 380, "end": 380 + len(pdf_two_pages["segments"][1]["text"])}))),
    sem("u1-reader-locator-key-with-an-unpaired-surrogate.json", E, add("/reader/locator/note\ud800", "x")),
    # The rendered words alone, without the asterisks the range covers in the source (ADR-0016 section 3).
    sem("a2-markdown-exact-text-without-its-markup.json", "text-markdown-with-reader-locator.json",
        rep("/exact_text", walking_quote.replace("*", ""))),
]

# --------------------------------------------------------------------------------------------- captures


def snapshot(title, author, kind, label=None, origin=None, ids=None):
    s = {"title": title, "author_display": author, "source_kind": kind}
    if ids:
        s["edition_identifiers"] = ids
    if label:
        s["location_label"], s["location_label_origin"] = label, origin
    return s


def note(key, *bodies, fmt="markdown", times=None):
    times = times or [f"2026-10-13T08:00:{10 + i:02d}Z" for i in range(len(bodies))]
    return {"note_id": U(f"fixture/note/{key}"), "current_revision": len(bodies),
            "revisions": [{"revision": i + 1, "body": b, "format": fmt, "saved_at": times[i]}
                          for i, b in enumerate(bodies)]}


def capture(key, kind, work, edition, anchors, surface, **extra):
    c = {"schema_version": 1, "capture_id": U(f"fixture/capture/{key}"), "work_id": work}
    if edition:
        c["edition_id"] = edition
    c["kind"] = kind
    c.update({k: v for k, v in extra.items() if k in ("quoted_text", "quoted_text_origin", "word", "generated_answer")})
    c["source_snapshot"] = extra["source_snapshot"]
    c["anchors"] = anchors
    c["notes"] = extra.get("notes", [])
    for k in ("retained_excerpt", "transcript"):
        if k in extra:
            c[k] = extra[k]
    c["provenance"] = {"surface": surface, "idempotency_key": f"fixture-{key}"}
    if "entry_point" in extra:
        c["provenance"]["entry_point"] = extra["entry_point"]
    c["created_at"] = T0
    c["updated_at"] = extra.get("updated_at", T0)
    c["revision"] = extra.get("revision", 1)
    if "trashed_at" in extra:
        c["trashed_at"] = extra["trashed_at"]
    return c


MED_SNAP = snapshot("Meditations", "Marcus Aurelius", "local_epub", "Book I", "app",
                    {"standard_ebooks": "marcus-aurelius/meditations/george-long"})
med_audio_snap = snapshot("Meditations", "Marcus Aurelius", "local_audio", "Part 1 · 1:30", "app")

# The G0.4 probe's preserved excerpts (real values: G0.4's AACExcerptExporter on the host), adapted exactly as the
# checker adapts the probe's records.
records = {json.loads(p.read_text())["idempotencyKey"]: json.loads(p.read_text())
           for p in (ROOT / "Docs/Stage0/evidence/M0-contracts/g04-capture-records/records").glob("*.json")}
excerpt_files = {e["capture_id"].lower(): e for e in probe["excerpt_files"]}


def preserved_from_probe(key, anchor):
    raw = records[key]
    return checker.g04_preserved_excerpt(key, raw["excerpt"]["saved"]["_0"], anchor["ranges"],
                                         excerpt_files[raw["id"].lower()], LOG)


single_excerpt = preserved_from_probe("m0-contracts-single", audio_single)
cross_excerpt = preserved_from_probe("m0-contracts-cross-file", audio_cross)
# Fixture transcript of the real single-file excerpt: Meditations, Book I (George Long's translation), with one
# machine error ("have had") that the corrected text fixes. No transcription endpoint was called.
RAW = "From the gods, to have had good grandfathers, good parents, a good sister."
transcript = {
    "clip_sha256": single_excerpt["blob_sha256"], "raw_text": RAW,
    "segments": [{"start_ms": 0, "end_ms": 4200, "text": RAW}], "language": "en",
    "provider_kind": "openai_compatible_transcription", "host": "speech.example.invalid", "model": "fixture-transcriber-1",
    "created_at": "2026-10-13T08:05:00Z", "discarded_segment_count": 0,
}
corrected = dict(transcript, corrected_text="From the gods, to have good grandfathers, good parents, a good sister.")
removed_excerpt = dict(single_excerpt, state="removed", removed_at="2026-10-20T09:00:00Z")

pdf_quote_snapshot = snapshot("Sylvia G0.1 PDF fixture: page labels", "Fixture generator", "local_pdf", "Pages 1-2", "app")
walden_snap = snapshot("Walden", "Henry David Thoreau", "local_text", "Where I Lived, and What I Lived For", "app")
physical_snap = snapshot("Walden", "Henry David Thoreau", "physical", "p. 112", "user", {"isbn": "9780000000002"})  # placeholder ISBN-13
endpoint = {"provider_kind": "anthropic_messages", "host": "api.example.invalid", "classification": "hosted", "model": "fixture-model-1"}
answer = {
    "conversation_id": U("fixture/conversation/1"), "message_id": U("fixture/message/2"), "context_pack_id": U("fixture/pack/1"),
    "question": "What does he mean by piety here?",
    "answer_text": "In the selected passage [c1], piety is listed among what he learned from his mother.",
    "answer_state": "complete", "endpoint": endpoint,
}
word_entry = {"headword": "beneficence", "source_sentence": MED_SENTENCE}

capture_valid = {
    "quote-epub.json": capture("quote-epub", "text_quote", MED_WORK, MED_EPUB_ED, [epub_noteref], "reader",
                               quoted_text=epub_noteref["exact_text"], quoted_text_origin="selection", source_snapshot=MED_SNAP,
                               notes=[note("quote-epub", "First thought.", "Second thought, *Markdown*.")],
                               updated_at="2026-10-13T08:00:11Z"),
    # A note edited after the device clock moved back: valid (timestamps are not ordered; a note edit leaves the
    # capture's revision unchanged).
    "quote-epub-note-edited-after-the-clock-went-back.json": capture(
        "quote-epub-clock", "text_quote", MED_WORK, MED_EPUB_ED, [epub_noteref], "reader",
        quoted_text=epub_noteref["exact_text"], quoted_text_origin="selection", source_snapshot=MED_SNAP,
        notes=[note("quote-epub-clock", "First thought.", "Second thought.",
                    times=["2026-10-13T08:00:10Z", "2026-10-13T07:58:30Z"])],
        updated_at="2026-10-13T07:58:30Z"),
    "quote-epub-across-two-resources.json": capture(
        "quote-epub-2", "text_quote", UNI_WORK, UNI_ED, epub_cross, "reader",
        quoted_text=checker.EPUB_SEGMENT_SEPARATOR.join(a["exact_text"] for a in epub_cross), quoted_text_origin="selection",
        source_snapshot=snapshot("Sylvia G0.1 Unicode fixture", "Fixture generator", "local_epub", "Chapter One", "app")),
    "quote-epub-selection-starting-at-a-space.json": capture(
        "quote-epub-space", "text_quote", MED_WORK, MED_EPUB_ED, [epub_leading_space], "reader",
        quoted_text=epub_leading_space["exact_text"], quoted_text_origin="selection",
        source_snapshot=snapshot("Meditations", "Marcus Aurelius", "local_epub", "Book VII", "app")),
    "quote-pdf-two-pages.json": capture("quote-pdf", "text_quote", PDF_WORK, PDF_ED, [pdf_two_pages], "reader",
                                        quoted_text=pdf_two_pages["exact_text"], quoted_text_origin="selection",
                                        source_snapshot=pdf_quote_snapshot),
    "quote-pdf-composed-selection.json": capture("quote-pdf-composed", "text_quote", PDF_WORK, PDF_ED, [pdf_composed_line_break],
                                                 "reader", quoted_text=pdf_composed_line_break["exact_text"],
                                                 quoted_text_origin="selection",
                                                 source_snapshot=snapshot("Sylvia G0.1 PDF fixture: page labels",
                                                                          "Fixture generator", "local_pdf", "Page 1", "app")),
    "quote-text-plain.json": capture("quote-text", "text_quote", WALDEN_WORK, WALDEN_TXT_ED, [text_plain], "reader",
                                     quoted_text=walden_quote, quoted_text_origin="selection", source_snapshot=walden_snap),
    "quote-typed-for-a-physical-book.json": capture(
        "quote-physical", "text_quote", FIELD_WORK, FIELD_ED, [], "manual_entry",
        quoted_text="Our life is frittered away by detail.", quoted_text_origin="user_entered", source_snapshot=physical_snap),
    "quote-in-trash.json": capture("quote-trash", "text_quote", WALDEN_WORK, WALDEN_TXT_ED, [text_plain], "reader",
                                   quoted_text=walden_quote, quoted_text_origin="selection", source_snapshot=walden_snap,
                                   updated_at="2026-10-14T09:00:00Z", trashed_at="2026-10-14T09:00:00Z", revision=2),
    "note-on-a-physical-book-page.json": capture(
        "note-physical", "note", FIELD_WORK, FIELD_ED, [], "manual_entry", source_snapshot=physical_snap,
        notes=[note("note-physical", "Read on the train; the map on this page.", fmt="plain")]),
    "note-edition-unknown.json": capture(
        "note-unknown-edition", "note", WALDEN_WORK, None, [], "manual_entry",
        source_snapshot=snapshot("Walden", "Henry David Thoreau", "physical"),
        notes=[note("note-unknown-edition", "Read in a borrowed copy; I do not know which printing.", fmt="plain")]),
    # A note on the whole work is a note capture with no anchors (plan 11.1: notes may be work-level; ADR-0016
    # section 4). G0.5 recovery keeps the same note as a row without a capture (deviation note-without-capture).
    "note-on-the-whole-work.json": capture(
        "note-work", "note", WALDEN_WORK, None, [], "manual_entry",
        source_snapshot=snapshot("Walden", "Henry David Thoreau", "work"),
        notes=[note("note-work", "# Simplicity\n\nSimplify, simplify.")]),
    "word-epub.json": capture(
        "word", "word", MED_WORK, MED_EPUB_ED, [epub_word], "reader",
        quoted_text="beneficence", quoted_text_origin="selection", word=word_entry,
        source_snapshot=MED_SNAP, notes=[note("word", "Doing good, as a habit.")]),
    "audio-preserved-single-file.json": capture(
        "audio-single", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player",
        source_snapshot=med_audio_snap, retained_excerpt=single_excerpt, notes=[note("audio-single", "The part about the gods.", fmt="plain")],
        updated_at="2026-10-13T08:00:01Z", revision=2),
    "audio-preserved-cross-file-quick-capture.json": capture(
        "audio-cross", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_cross], "quick_capture",
        entry_point="intent.control@com.jevidon.sylvia",
        source_snapshot=snapshot("Meditations", "Marcus Aurelius", "local_audio", "Part 2 · 0:10", "app"), retained_excerpt=cross_excerpt,
        updated_at="2026-10-13T08:00:01Z", revision=2),
    "audio-pending.json": capture("audio-pending", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player",
                                  source_snapshot=med_audio_snap, retained_excerpt={"state": "pending"}),
    "audio-failed-source-not-on-device.json": capture(
        "audio-failed", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player", source_snapshot=med_audio_snap,
        retained_excerpt={"state": "failed", "failure": {"reason": "source not on this device", "attempts": 1}},
        notes=[note("audio-failed", "Kept even though the excerpt failed.", fmt="plain")], updated_at="2026-10-13T08:00:01Z", revision=2),
    # A decode error whose reason names a codec profile (not a path): the reviewer's example of a reason the earlier
    # pattern refused. Two failed attempts: revision 3 (rule C8).
    "audio-failed-decode-error-naming-a-profile.json": capture(
        "audio-failed-profile", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player", source_snapshot=med_audio_snap,
        retained_excerpt={"state": "failed", "failure": {
            "reason": "decodeFailed(\"Part 1.mp3: unsupported profile: HE-AAC v2\")", "attempts": 2}},
        updated_at="2026-10-13T08:02:00Z", revision=3),
    "audio-transcript-not-saved-as-quote.json": capture(
        "audio-transcript", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player", source_snapshot=med_audio_snap,
        retained_excerpt=single_excerpt, transcript=transcript, updated_at="2026-10-13T08:05:00Z", revision=3),
    "audio-machine-transcript-quote.json": capture(
        "audio-machine", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player", source_snapshot=med_audio_snap,
        quoted_text=RAW, quoted_text_origin="machine_transcript", retained_excerpt=single_excerpt, transcript=transcript,
        updated_at="2026-10-13T08:05:30Z", revision=4),
    "audio-corrected-transcript-quote.json": capture(
        "audio-corrected", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player", source_snapshot=med_audio_snap,
        quoted_text=corrected["corrected_text"], quoted_text_origin="corrected_transcript", retained_excerpt=single_excerpt,
        transcript=corrected, updated_at="2026-10-13T08:06:30Z", revision=5),
    # The user removed the excerpt audio after saving its corrected transcript as the quotation (plan 17.2, "Remove
    # excerpt audio"): the quotation, the transcript and the record of the export stay; the file does not.
    "audio-excerpt-removed-after-its-transcript.json": capture(
        "audio-removed", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player", source_snapshot=med_audio_snap,
        quoted_text=corrected["corrected_text"], quoted_text_origin="corrected_transcript", retained_excerpt=removed_excerpt,
        transcript=corrected, updated_at="2026-10-20T09:00:00Z", revision=6),
    "audio-typed-by-user.json": capture(
        "audio-typed", "audio_capture", MED_WORK, MED_AUDIO_ED, [audio_single], "player", source_snapshot=med_audio_snap,
        quoted_text="to have had good grandfathers", quoted_text_origin="user_entered", retained_excerpt={"state": "pending"},
        updated_at="2026-10-13T08:00:20Z", revision=2),
    "generated-answer-complete.json": capture("generated", "generated_answer", MED_WORK, MED_EPUB_ED, [], "conversation",
                                              generated_answer=answer, source_snapshot=MED_SNAP),
    "generated-answer-interrupted.json": capture(
        "generated-interrupted", "generated_answer", MED_WORK, MED_EPUB_ED, [], "conversation",
        generated_answer=dict(answer, message_id=U("fixture/message/4"), answer_state="interrupted",
                              answer_text="In the selected passage [c1], piety is"), source_snapshot=MED_SNAP),
    "generated-answer-cancelled-after-some-text.json": capture(
        "generated-cancelled", "generated_answer", MED_WORK, MED_EPUB_ED, [], "conversation",
        generated_answer=dict(answer, message_id=U("fixture/message/6"), answer_state="cancelled",
                              answer_text="In the selected passage [c1], piety"), source_snapshot=MED_SNAP),
    # A later writer's kind, with values v1 does not know in the fields every capture has: accepted and preserved.
    "unknown-kind-from-a-later-writer.json": capture(
        "later", "later_kind_example", MED_WORK, MED_EPUB_ED, [dict(later_anchor, edition_id=MED_EPUB_ED)],
        "later_surface_example", quoted_text="Text a later kind carries; a v1 reader never shows it as a Quote.",
        quoted_text_origin="later_origin_example",
        source_snapshot=snapshot("Meditations", "Marcus Aurelius", "later_source_example", "Book I", "later_origin_example"),
        notes=[note("later", "A note on a later writer's capture, in a format v1 does not know.", fmt="later_format_example")]),
    # A later writer's anchor kind located without an edition (addendum 4.3: a clip located in a retained clip while
    # the edition is unknown): the capture names no edition, which only an anchor of a known kind requires.
    "unknown-kind-anchor-without-an-edition.json": capture(
        "later-no-edition", "note", MED_WORK, None, [later_anchor], "manual_entry",
        source_snapshot=snapshot("Meditations", "Marcus Aurelius", "later_source_example"),
        notes=[note("later-no-edition", "Located only by a later writer's anchor.", fmt="plain")]),
    # A later writer's anchor kind beside the EPUB anchor of a selected quotation: C2 compares the quotation with the
    # EPUB anchor and leaves the later one alone (ADR-0016 sections 5 and 6; review finding R2-03).
    "unknown-kind-anchor-beside-an-epub-selection.json": capture(
        "later-beside-epub", "text_quote", MED_WORK, MED_EPUB_ED, [epub_noteref, later_anchor], "reader",
        quoted_text=epub_noteref["exact_text"], quoted_text_origin="selection", source_snapshot=MED_SNAP),
    # A selected quotation located only by a later writer's anchor kind: a v1 reader has no text to compare it with,
    # so C2 does not apply; it shows the quotation as stored, located by its label (ADR-0016 section 6).
    "unknown-kind-anchor-only-on-a-selected-quote.json": capture(
        "later-only", "text_quote", MED_WORK, None, [later_anchor], "reader",
        quoted_text="Words a later writer's anchor locates; a v1 reader has nothing to compare them with.",
        quoted_text_origin="selection",
        source_snapshot=snapshot("Meditations", "Marcus Aurelius", "later_source_example", "Book I", "app")),
    # A later writer's kind that reuses v1's retained excerpt and transcript as v1 defines them (ADR-0016 section 6,
    # rule 2): accepted, and checked like an audio capture by C4, C5, C7, C8 and C9.
    "unknown-kind-reusing-the-excerpt-and-transcript.json": capture(
        "later-transcript", "later_kind_example", MED_WORK, MED_AUDIO_ED, [audio_single], "player",
        quoted_text=RAW, quoted_text_origin="machine_transcript", retained_excerpt=single_excerpt, transcript=transcript,
        source_snapshot=med_audio_snap, updated_at="2026-10-13T08:05:30Z", revision=3),
}

Q, AU, N, G = "quote-epub.json", "audio-preserved-single-file.json", "note-on-a-physical-book-page.json", "generated-answer-complete.json"
W, PEND, FAIL, RMV = "word-epub.json", "audio-pending.json", "audio-failed-source-not-on-device.json", "audio-excerpt-removed-after-its-transcript.json"
TRS, LATER, LATER_NE = "audio-transcript-not-saved-as-quote.json", "unknown-kind-from-a-later-writer.json", "unknown-kind-anchor-without-an-edition.json"
epub_anchor_without_digest = {k: v for k, v in epub_noteref.items() if k != "asset_sha256"}
pending_excerpt_with = {"state": "pending"}
WITH_TEXT = "a quotation with the origin it requires (dependentRequired)"
WITHOUT_TEXT = "the quotation and its origin, which requires it (dependentRequired)"
XP = "properties/retained_excerpt"
RULE = {name: f"allOf[{name}]/then" for name in ("text_quote", "word", "note", "audio_capture", "generated_answer",
                                                 "typed-quote-has-no-reader-anchor", "selection-has-anchors",
                                                 "transcript-origin", "corrected-transcript", "anchor-names-edition",
                                                 "known-kind-values")}
capture_ops = [
    # Fields every capture has.
    inv("missing-schema-version.json", Q, rm("/schema_version"), req("", "required", "schema_version")),
    inv("newer-schema-version.json", Q, rep("/schema_version", 2), err("const", "/schema_version", "properties/schema_version/const")),
    inv("missing-capture-id.json", Q, rm("/capture_id"), req("", "required", "capture_id")),
    inv("uppercase-capture-id.json", Q, rep("/capture_id", capture_valid[Q]["capture_id"].upper()), err("pattern", "/capture_id", "properties/capture_id/pattern")),
    inv("missing-work-id.json", Q, rm("/work_id"), req("", "required", "work_id")),
    inv("missing-kind.json", N, rm("/kind"), req("", "required", "kind")),
    inv("kind-uppercase.json", Q, rep("/kind", "TEXT_QUOTE"), err("pattern", "/kind", "properties/kind/pattern")),
    inv("missing-source-snapshot.json", Q, rm("/source_snapshot"), req("", "required", "source_snapshot")),
    inv("empty-snapshot-title.json", Q, rep("/source_snapshot/title", ""), err("minLength", "/source_snapshot/title", "properties/source_snapshot/properties/title/minLength")),
    inv("missing-anchors.json", Q, rm("/anchors"), req("", "required", "anchors")),
    inv("missing-notes.json", Q, rm("/notes"), req("", "required", "notes")),
    inv("missing-provenance.json", Q, rm("/provenance"), req("", "required", "provenance")),
    inv("missing-idempotency-key.json", Q, rm("/provenance/idempotency_key"), req("/provenance", "properties/provenance/required", "idempotency_key")),
    inv("unknown-provenance-surface.json", Q, rep("/provenance/surface", "share_extension"),
        err("enum", "/provenance/surface", f"{RULE['known-kind-values']}/properties/provenance/properties/surface/enum")),
    inv("missing-created-at.json", Q, rm("/created_at"), req("", "required", "created_at")),
    inv("non-utc-created-at.json", Q, rep("/created_at", "2026-10-13T10:00:00+02:00"), err("pattern", "/created_at", "properties/created_at/pattern")),
    inv("created-at-impossible-date.json", Q, rep("/created_at", "2026-02-30T08:00:00Z"), err("format", "/created_at", "properties/created_at/format")),
    inv("missing-updated-at.json", Q, rm("/updated_at"), req("", "required", "updated_at")),
    inv("missing-revision.json", Q, rm("/revision"), req("", "required", "revision")),
    inv("revision-zero.json", Q, rep("/revision", 0), err("minimum", "/revision", "properties/revision/minimum")),
    inv("null-edition-id.json", Q, rep("/edition_id", None), err("type", "/edition_id", "properties/edition_id/type")),
    inv("secret-field-name.json", Q, add("/password", "not-a-real-password"), err("not", "", "propertyNames/not")),
    inv("trashed-at-not-utc.json", "quote-in-trash.json", rep("/trashed_at", "2026-10-14T10:00:00+01:00"), err("pattern", "/trashed_at", "properties/trashed_at/pattern")),
    inv("location-label-without-origin.json", Q, rm("/source_snapshot/location_label_origin"),
        err("dependentRequired", "/source_snapshot", "properties/source_snapshot/dependentRequired", "location_label_origin")),
    inv("location-origin-without-label.json", Q, rm("/source_snapshot/location_label"),
        err("dependentRequired", "/source_snapshot", "properties/source_snapshot/dependentRequired", "location_label")),
    inv("location-origin-machine.json", Q, rep("/source_snapshot/location_label_origin", "machine_suggested"),
        err("enum", "/source_snapshot/location_label_origin", f"{RULE['known-kind-values']}/properties/source_snapshot/properties/location_label_origin/enum")),
    # Notes.
    inv("note-revision-html-format.json", Q, rep("/notes/0/revisions/0/format", "html"),
        err("enum", "/notes/0/revisions/0/format", f"{RULE['known-kind-values']}/properties/notes/items/properties/revisions/items/properties/format/enum")),
    inv("note-revision-missing-saved-at.json", Q, rm("/notes/0/revisions/0/saved_at"),
        req("/notes/0/revisions/0", "properties/notes/items/properties/revisions/items/required", "saved_at")),
    inv("note-without-revisions.json", Q, rep("/notes/0/revisions", []), err("minItems", "/notes/0/revisions", "properties/notes/items/properties/revisions/minItems")),
    # Quoted text and its origin.
    inv("quoted-text-without-origin.json", Q, rm("/quoted_text_origin"), err("dependentRequired", "", "dependentRequired", "quoted_text_origin")),
    inv("origin-without-quoted-text.json", N, add("/quoted_text_origin", "user_entered"), err("dependentRequired", "", "dependentRequired", "quoted_text")),
    inv("empty-quoted-text.json", Q, rep("/quoted_text", ""), err("minLength", "/quoted_text", "properties/quoted_text/minLength")),
    inv("selection-without-anchors.json", Q, rep("/anchors", []), err("minItems", "/anchors", f"{RULE['selection-has-anchors']}/properties/anchors/minItems")),
    inv("anchors-without-edition-id.json", Q, rm("/edition_id"), req("", f"{RULE['anchor-names-edition']}/required", "edition_id")),
    # The same rule for each other known anchor kind, so it is protected kind by kind, not only through the writer
    # profile (commands/mutation-pass.py deletes each value of the rule's kind list).
    inv("anchors-without-edition-id-pdf.json", "quote-pdf-two-pages.json", rm("/edition_id"),
        req("", f"{RULE['anchor-names-edition']}/required", "edition_id")),
    inv("anchors-without-edition-id-text.json", "quote-text-plain.json", rm("/edition_id"),
        req("", f"{RULE['anchor-names-edition']}/required", "edition_id")),
    inv("anchors-without-edition-id-audio.json", AU, rm("/edition_id"), req("", f"{RULE['anchor-names-edition']}/required", "edition_id")),
    # The four open fields are closed for every known kind, not only for text_quote (the unknown-* fixtures above).
    inv("note-kind-with-an-unknown-surface.json", N, rep("/provenance/surface", "share_extension"),
        err("enum", "/provenance/surface", f"{RULE['known-kind-values']}/properties/provenance/properties/surface/enum")),
    inv("audio-with-an-unknown-surface.json", AU, rep("/provenance/surface", "share_extension"),
        err("enum", "/provenance/surface", f"{RULE['known-kind-values']}/properties/provenance/properties/surface/enum")),
    inv("generated-answer-with-an-unknown-location-origin.json", G, rep("/source_snapshot/location_label_origin", "machine_suggested"),
        err("enum", "/source_snapshot/location_label_origin", f"{RULE['known-kind-values']}/properties/source_snapshot/properties/location_label_origin/enum")),
    inv("word-with-an-unknown-note-format.json", W, rep("/notes/0/revisions/0/format", "html"),
        err("enum", "/notes/0/revisions/0/format", f"{RULE['known-kind-values']}/properties/notes/items/properties/revisions/items/properties/format/enum")),
    inv("anchor-without-asset-digest.json", Q, rep("/anchors/0", epub_anchor_without_digest),
        req("/anchors/0", "properties/anchors/items/allOf[epub]/then/required", "asset_sha256")),
    # text_quote.
    inv("quote-without-quoted-text.json", "quote-typed-for-a-physical-book.json", [rm("/quoted_text"), rm("/quoted_text_origin")],
        req("", f"{RULE['text_quote']}/required", "quoted_text"), why=WITHOUT_TEXT),
    inv("quote-from-machine-transcript.json", Q, rep("/quoted_text_origin", "machine_transcript"),
        req("", f"{RULE['transcript-origin']}/required", "transcript")),
    inv("quote-with-audio-anchor.json", Q, rep("/anchors/0", audio_single), err("not", "/anchors/0", f"{RULE['text_quote']}/properties/anchors/items/not")),
    inv("quote-with-word-entry.json", Q, add("/word", word_entry), err("not", "", f"{RULE['text_quote']}/not")),
    inv("quote-with-generated-answer.json", Q, add("/generated_answer", answer), err("not", "", f"{RULE['text_quote']}/not")),
    inv("quote-with-excerpt.json", Q, add("/retained_excerpt", pending_excerpt_with), err("not", "", f"{RULE['text_quote']}/not")),
    inv("quote-with-transcript.json", Q, add("/transcript", transcript), err("not", "", f"{RULE['text_quote']}/not")),
    # A typed quotation at a reader anchor (finding R1-02): the anchor would locate other words than the typed ones.
    inv("quote-typed-at-an-epub-anchor.json", Q, rep("/quoted_text_origin", "user_entered"),
        err("not", "/anchors/0", f"{RULE['typed-quote-has-no-reader-anchor']}/properties/anchors/items/not")),
    inv("quote-typed-at-a-pdf-anchor.json", "quote-pdf-two-pages.json", rep("/quoted_text_origin", "user_entered"),
        err("not", "/anchors/0", f"{RULE['typed-quote-has-no-reader-anchor']}/properties/anchors/items/not")),
    inv("quote-typed-at-a-text-anchor.json", "quote-text-plain.json", rep("/quoted_text_origin", "user_entered"),
        err("not", "/anchors/0", f"{RULE['typed-quote-has-no-reader-anchor']}/properties/anchors/items/not")),
    # word.
    inv("word-without-word-entry.json", W, rm("/word"), req("", f"{RULE['word']}/required", "word")),
    inv("word-without-headword.json", W, rm("/word/headword"), req("/word", "properties/word/required", "headword")),
    inv("word-without-quoted-text.json", W, [rm("/quoted_text"), rm("/quoted_text_origin")], req("", f"{RULE['word']}/required", "quoted_text"), why=WITHOUT_TEXT),
    inv("word-typed-by-user.json", W, rep("/quoted_text_origin", "user_entered"), err("const", "/quoted_text_origin", f"{RULE['word']}/properties/quoted_text_origin/const")),
    inv("word-without-anchors.json", W, rep("/anchors", []), err("minItems", "/anchors", f"{RULE['selection-has-anchors']}/properties/anchors/minItems")),
    inv("word-with-audio-anchor.json", W, rep("/anchors/0", audio_single), err("not", "/anchors/0", f"{RULE['word']}/properties/anchors/items/not")),
    inv("word-with-generated-answer.json", W, add("/generated_answer", answer), err("not", "", f"{RULE['word']}/not")),
    inv("word-with-excerpt.json", W, add("/retained_excerpt", pending_excerpt_with), err("not", "", f"{RULE['word']}/not")),
    inv("word-with-transcript.json", W, add("/transcript", transcript), err("not", "", f"{RULE['word']}/not")),
    # note.
    inv("note-kind-without-notes.json", N, rep("/notes", []), err("minItems", "/notes", f"{RULE['note']}/properties/notes/minItems")),
    inv("note-kind-with-quoted-text.json", N, [add("/quoted_text", "A note is the user's words, not a quotation."), add("/quoted_text_origin", "user_entered")],
        err("not", "", f"{RULE['note']}/not"), why=WITH_TEXT),
    inv("note-kind-with-word-entry.json", N, add("/word", word_entry), err("not", "", f"{RULE['note']}/not")),
    inv("note-kind-with-generated-answer.json", N, add("/generated_answer", answer), err("not", "", f"{RULE['note']}/not")),
    inv("note-kind-with-excerpt.json", N, add("/retained_excerpt", pending_excerpt_with), err("not", "", f"{RULE['note']}/not")),
    inv("note-kind-with-transcript.json", N, add("/transcript", transcript), err("not", "", f"{RULE['note']}/not")),
    # audio_capture.
    inv("audio-without-excerpt-record.json", AU, rm("/retained_excerpt"), req("", f"{RULE['audio_capture']}/required", "retained_excerpt")),
    inv("audio-without-anchors.json", AU, rep("/anchors", []), err("minItems", "/anchors", f"{RULE['audio_capture']}/properties/anchors/minItems")),
    inv("audio-with-two-anchors.json", AU, add("/anchors/1", audio_cross), err("maxItems", "/anchors", f"{RULE['audio_capture']}/properties/anchors/maxItems")),
    inv("audio-with-epub-anchor.json", AU, rep("/anchors/0", dict(epub_noteref, edition_id=MED_AUDIO_ED)),
        err("const", "/anchors/0/kind", f"{RULE['audio_capture']}/properties/anchors/items/properties/kind/const")),
    inv("audio-with-selection-origin.json", "audio-typed-by-user.json", rep("/quoted_text_origin", "selection"),
        err("enum", "/quoted_text_origin", f"{RULE['audio_capture']}/properties/quoted_text_origin/enum")),
    inv("audio-with-word-entry.json", AU, add("/word", word_entry), err("not", "", f"{RULE['audio_capture']}/not")),
    inv("audio-with-generated-answer.json", AU, add("/generated_answer", answer), err("not", "", f"{RULE['audio_capture']}/not")),
    inv("audio-machine-transcript-without-transcript.json", "audio-machine-transcript-quote.json", rm("/transcript"),
        req("", f"{RULE['transcript-origin']}/required", "transcript")),
    inv("audio-transcript-quote-with-pending-excerpt.json", "audio-machine-transcript-quote.json", rep("/retained_excerpt", {"state": "pending"}),
        err("enum", "/retained_excerpt/state", f"{RULE['transcript-origin']}/properties/retained_excerpt/properties/state/enum")),
    inv("audio-corrected-transcript-without-correction.json", "audio-corrected-transcript-quote.json", rm("/transcript/corrected_text"),
        req("/transcript", f"{RULE['corrected-transcript']}/properties/transcript/required", "corrected_text")),
    # A corrected transcript quotation needs the transcript and its preserved excerpt as much as a machine one: text
    # that was never transcribed is not a transcript quotation (plan 10.2, 4.4.6; review finding R2-01).
    inv("audio-corrected-transcript-without-transcript.json", "audio-corrected-transcript-quote.json", rm("/transcript"),
        req("", f"{RULE['transcript-origin']}/required", "transcript")),
    inv("audio-corrected-transcript-quote-with-pending-excerpt.json", "audio-corrected-transcript-quote.json",
        rep("/retained_excerpt", {"state": "pending"}),
        err("enum", "/retained_excerpt/state", f"{RULE['transcript-origin']}/properties/retained_excerpt/properties/state/enum")),
    # The retained excerpt in each state.
    inv("excerpt-without-state.json", PEND, rm("/retained_excerpt/state"), req("/retained_excerpt", f"{XP}/required", "state")),
    inv("excerpt-state-saved.json", AU, rep("/retained_excerpt/state", "saved"), err("enum", "/retained_excerpt/state", f"{XP}/properties/state/enum")),
    inv("excerpt-preserved-without-blob-digest.json", AU, rm("/retained_excerpt/blob_sha256"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "blob_sha256")),
    inv("excerpt-preserved-without-file-extension.json", AU, rm("/retained_excerpt/file_extension"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "file_extension")),
    inv("excerpt-preserved-without-media-type.json", AU, rm("/retained_excerpt/media_type"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "media_type")),
    inv("excerpt-preserved-without-byte-count.json", AU, rm("/retained_excerpt/byte_count"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "byte_count")),
    inv("excerpt-preserved-without-format.json", AU, rm("/retained_excerpt/format"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "format")),
    inv("excerpt-preserved-without-read-back-duration.json", AU, rm("/retained_excerpt/duration_ms"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "duration_ms")),
    inv("excerpt-preserved-without-sample-rate.json", AU, rm("/retained_excerpt/sample_rate_hz"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "sample_rate_hz")),
    inv("excerpt-preserved-without-frame-count.json", AU, rm("/retained_excerpt/frame_count"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "frame_count")),
    inv("excerpt-preserved-without-actual-ranges.json", AU, rm("/retained_excerpt/actual_ranges"),
        req("/retained_excerpt", f"{XP}/allOf[preserved]/then/required", "actual_ranges")),
    inv("excerpt-preserved-with-failure.json", AU, add("/retained_excerpt/failure", {"reason": "x", "attempts": 1}),
        err("not", "/retained_excerpt", f"{XP}/allOf[preserved]/then/not")),
    inv("excerpt-preserved-with-removed-at.json", AU, add("/retained_excerpt/removed_at", "2026-10-20T09:00:00Z"),
        err("not", "/retained_excerpt", f"{XP}/allOf[preserved]/then/not")),
    inv("excerpt-fractional-sample-rate.json", AU, rep("/retained_excerpt/sample_rate_hz", 44100.5),
        err("type", "/retained_excerpt/sample_rate_hz", f"{XP}/properties/sample_rate_hz/type")),
    inv("excerpt-actual-range-without-source-format.json", AU, rm("/retained_excerpt/actual_ranges/0/source_format"),
        req("/retained_excerpt/actual_ranges/0", f"{XP}/properties/actual_ranges/items/required", "source_format")),
    inv("excerpt-actual-range-without-clip-offset.json", AU, rm("/retained_excerpt/actual_ranges/0/clip_start_ms"),
        req("/retained_excerpt/actual_ranges/0", f"{XP}/properties/actual_ranges/items/required", "clip_start_ms")),
    inv("excerpt-removed-without-removed-at.json", RMV, rm("/retained_excerpt/removed_at"),
        req("/retained_excerpt", f"{XP}/allOf[removed]/then/required", "removed_at")),
    inv("excerpt-removed-without-blob-digest.json", RMV, rm("/retained_excerpt/blob_sha256"),
        req("/retained_excerpt", f"{XP}/allOf[removed]/then/required", "blob_sha256")),
    inv("excerpt-removed-with-failure.json", RMV, add("/retained_excerpt/failure", {"reason": "x", "attempts": 1}),
        err("not", "/retained_excerpt", f"{XP}/allOf[removed]/then/not")),
    inv("excerpt-failed-without-failure.json", FAIL, rm("/retained_excerpt/failure"), req("/retained_excerpt", f"{XP}/allOf[failed]/then/required", "failure")),
    inv("excerpt-failure-without-attempts.json", FAIL, rm("/retained_excerpt/failure/attempts"),
        req("/retained_excerpt/failure", f"{XP}/properties/failure/required", "attempts")),
    inv("excerpt-failure-reason-with-a-file-path.json", FAIL, rep("/retained_excerpt/failure/reason",
        "decodeFailed(\"Part 3.mp3: The file /private/var/mobile/Library/Part 3.mp3 could not be opened.\")"),
        err("not", "/retained_excerpt/failure/reason", f"{XP}/properties/failure/properties/reason/not")),
    inv("excerpt-failure-reason-with-a-file-url.json", FAIL, rep("/retained_excerpt/failure/reason",
        "Error Domain=NSCocoaErrorDomain Code=260 UserInfo={NSURL=file:///private/var/mobile/Part%203.mp3}"),
        err("not", "/retained_excerpt/failure/reason", f"{XP}/properties/failure/properties/reason/not")),
    inv("excerpt-failure-reason-with-a-home-path.json", FAIL, rep("/retained_excerpt/failure/reason", "cannot open ~/Library/Audiobooks/Part 3.mp3"),
        err("not", "/retained_excerpt/failure/reason", f"{XP}/properties/failure/properties/reason/not")),
    inv("excerpt-failure-reason-with-a-drive-path.json", FAIL, rep("/retained_excerpt/failure/reason", "cannot open C:\\Audiobooks\\Part 3.mp3"),
        err("not", "/retained_excerpt/failure/reason", f"{XP}/properties/failure/properties/reason/not")),
    # The review's cases the first guard let through (R2-07): a UNC path, and a path after '>'.
    inv("excerpt-failure-reason-with-a-unc-path.json", FAIL, rep("/retained_excerpt/failure/reason", "cannot open \\\\nas\\audiobooks\\Part 3.mp3"),
        err("not", "/retained_excerpt/failure/reason", f"{XP}/properties/failure/properties/reason/not")),
    inv("excerpt-failure-reason-with-a-path-after-an-angle-bracket.json", FAIL, rep("/retained_excerpt/failure/reason",
        "decodeFailed(path>/private/var/mobile/Part 3.mp3)"),
        err("not", "/retained_excerpt/failure/reason", f"{XP}/properties/failure/properties/reason/not")),
    # Only a preserved or removed excerpt names a file and its timing: one field of excerpt_file_fields each.
    inv("excerpt-failed-with-blob-digest.json", FAIL, add("/retained_excerpt/blob_sha256", single_excerpt["blob_sha256"]),
        err("not", "/retained_excerpt", f"{XP}/allOf[failed]/then/not")),
    inv("excerpt-failed-with-file-extension.json", FAIL, add("/retained_excerpt/file_extension", "m4a"),
        err("not", "/retained_excerpt", f"{XP}/allOf[failed]/then/not")),
    inv("excerpt-failed-with-media-type.json", FAIL, add("/retained_excerpt/media_type", "audio/mp4"),
        err("not", "/retained_excerpt", f"{XP}/allOf[failed]/then/not")),
    inv("excerpt-failed-with-byte-count.json", FAIL, add("/retained_excerpt/byte_count", 1),
        err("not", "/retained_excerpt", f"{XP}/allOf[failed]/then/not")),
    inv("excerpt-failed-with-removed-at.json", FAIL, add("/retained_excerpt/removed_at", "2026-10-20T09:00:00Z"),
        err("not", "/retained_excerpt", f"{XP}/allOf[failed]/then/not")),
    inv("excerpt-pending-with-blob-digest.json", PEND, add("/retained_excerpt/blob_sha256", single_excerpt["blob_sha256"]),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    inv("excerpt-pending-with-format.json", PEND, add("/retained_excerpt/format", single_excerpt["format"]),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    inv("excerpt-pending-with-duration.json", PEND, add("/retained_excerpt/duration_ms", 30000),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    inv("excerpt-pending-with-sample-rate.json", PEND, add("/retained_excerpt/sample_rate_hz", 44100),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    inv("excerpt-pending-with-frame-count.json", PEND, add("/retained_excerpt/frame_count", 1323000),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    inv("excerpt-pending-with-actual-ranges.json", PEND, add("/retained_excerpt/actual_ranges", single_excerpt["actual_ranges"]),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    inv("excerpt-pending-with-failure.json", PEND, add("/retained_excerpt/failure", {"reason": "x", "attempts": 1}),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    inv("excerpt-pending-with-removed-at.json", PEND, add("/retained_excerpt/removed_at", "2026-10-20T09:00:00Z"),
        err("not", "/retained_excerpt", f"{XP}/allOf[pending]/then/not")),
    # Transcript.
    inv("transcript-without-clip-digest.json", TRS, rm("/transcript/clip_sha256"), req("/transcript", "properties/transcript/required", "clip_sha256")),
    inv("transcript-text-provider-kind.json", TRS, rep("/transcript/provider_kind", "openai_responses"),
        err("enum", "/transcript/provider_kind", "properties/transcript/properties/provider_kind/enum")),
    inv("transcript-secret-field.json", TRS, add("/transcript/api_key", "not-a-real-key"), err("not", "/transcript", "properties/transcript/propertyNames/not")),
    # generated_answer.
    inv("generated-answer-without-answer-object.json", G, rm("/generated_answer"), req("", f"{RULE['generated_answer']}/required", "generated_answer")),
    inv("generated-answer-with-quoted-text.json", G, [add("/quoted_text", "A model answer is not a quotation."), add("/quoted_text_origin", "user_entered")],
        err("not", "", f"{RULE['generated_answer']}/not"), why=WITH_TEXT),
    inv("generated-answer-with-word-entry.json", G, add("/word", word_entry), err("not", "", f"{RULE['generated_answer']}/not")),
    inv("generated-answer-with-excerpt.json", G, add("/retained_excerpt", pending_excerpt_with), err("not", "", f"{RULE['generated_answer']}/not")),
    inv("generated-answer-with-transcript.json", G, add("/transcript", transcript), err("not", "", f"{RULE['generated_answer']}/not")),
    inv("generated-answer-without-context-pack.json", G, rm("/generated_answer/context_pack_id"),
        req("/generated_answer", "properties/generated_answer/required", "context_pack_id")),
    inv("generated-answer-without-answer-state.json", G, rm("/generated_answer/answer_state"),
        req("/generated_answer", "properties/generated_answer/required", "answer_state")),
    inv("generated-answer-draft-state.json", G, rep("/generated_answer/answer_state", "draft"),
        err("enum", "/generated_answer/answer_state", "properties/generated_answer/properties/answer_state/enum")),
    inv("generated-answer-without-answer-text.json", G, rep("/generated_answer/answer_text", ""),
        err("minLength", "/generated_answer/answer_text", "properties/generated_answer/properties/answer_text/minLength")),
    inv("generated-answer-endpoint-with-credential.json", G, add("/generated_answer/endpoint/authorization", "not-a-real-header"),
        err("not", "/generated_answer/endpoint", "properties/generated_answer/properties/endpoint/propertyNames/not")),
    inv("generated-answer-from-the-reader.json", G, rep("/provenance/surface", "reader"),
        err("const", "/provenance/surface", f"{RULE['generated_answer']}/properties/provenance/properties/surface/const")),
    # Later writers: a v1 field keeps its v1 definition on every kind (ADR-0016 section 6).
    inv("unknown-kind-with-a-new-excerpt-state.json", LATER, add("/retained_excerpt", {"state": "streaming"}),
        err("enum", "/retained_excerpt/state", f"{XP}/properties/state/enum")),
    inv("unknown-kind-anchor-of-a-known-kind-without-capture-edition.json", LATER_NE, add("/anchors/1", dict(text_plain, work_id=MED_WORK)),
        req("", f"{RULE['anchor-names-edition']}/required", "edition_id")),
    # A later kind may bring new values in the four open fields, but each is still a lowercase token.
    inv("unknown-kind-origin-not-a-token.json", LATER, rep("/quoted_text_origin", "Later Origin"),
        err("pattern", "/quoted_text_origin", "properties/quoted_text_origin/pattern")),
    inv("unknown-kind-surface-not-a-token.json", LATER, rep("/provenance/surface", "Later Surface"),
        err("pattern", "/provenance/surface", "properties/provenance/properties/surface/pattern")),
    inv("unknown-kind-location-origin-not-a-token.json", LATER, rep("/source_snapshot/location_label_origin", "Later Origin"),
        err("pattern", "/source_snapshot/location_label_origin", "properties/source_snapshot/properties/location_label_origin/pattern")),
    inv("unknown-kind-note-format-not-a-token.json", LATER, rep("/notes/0/revisions/0/format", "Rich Text"),
        err("pattern", "/notes/0/revisions/0/format", "properties/notes/items/properties/revisions/items/properties/format/pattern")),
    # Each field's definition ($ref), nested requirement and bound, so that deleting any of them changes an outcome
    # (commands/mutation-pass.py; review finding R1-01).
    inv("uppercase-work-id.json", Q, rep("/work_id", MED_WORK.upper()), err("pattern", "/work_id", "properties/work_id/pattern")),
    inv("non-utc-updated-at.json", Q, rep("/updated_at", "2026-10-13T10:00:11+02:00"), err("pattern", "/updated_at", "properties/updated_at/pattern")),
    inv("quote-with-an-unknown-origin.json", Q, rep("/quoted_text_origin", "ocr"),
        err("enum", "/quoted_text_origin", f"{RULE['known-kind-values']}/properties/quoted_text_origin/enum")),
    inv("provenance-without-surface.json", Q, rm("/provenance/surface"), req("/provenance", "properties/provenance/required", "surface")),
    inv("snapshot-without-title.json", Q, rm("/source_snapshot/title"), req("/source_snapshot", "properties/source_snapshot/required", "title")),
    inv("snapshot-without-author.json", Q, rm("/source_snapshot/author_display"), req("/source_snapshot", "properties/source_snapshot/required", "author_display")),
    inv("snapshot-without-source-kind.json", Q, rm("/source_snapshot/source_kind"), req("/source_snapshot", "properties/source_snapshot/required", "source_kind")),
    inv("snapshot-source-kind-not-a-token.json", Q, rep("/source_snapshot/source_kind", "Local EPUB"),
        err("pattern", "/source_snapshot/source_kind", "properties/source_snapshot/properties/source_kind/pattern")),
    inv("snapshot-identifier-name-not-a-token.json", Q, add("/source_snapshot/edition_identifiers/ISBN", "9780000000002"),
        err("pattern", "/source_snapshot/edition_identifiers", "properties/source_snapshot/properties/edition_identifiers/propertyNames/pattern")),
    inv("snapshot-identifier-empty.json", Q, rep("/source_snapshot/edition_identifiers/standard_ebooks", ""),
        err("minLength", "/source_snapshot/edition_identifiers/standard_ebooks", "properties/source_snapshot/properties/edition_identifiers/additionalProperties/minLength")),
    inv("note-without-id.json", Q, rm("/notes/0/note_id"), req("/notes/0", "properties/notes/items/required", "note_id")),
    inv("note-uppercase-id.json", Q, rep("/notes/0/note_id", capture_valid[Q]["notes"][0]["note_id"].upper()),
        err("pattern", "/notes/0/note_id", "properties/notes/items/properties/note_id/pattern")),
    inv("note-without-current-revision.json", Q, rm("/notes/0/current_revision"), req("/notes/0", "properties/notes/items/required", "current_revision")),
    inv("note-current-revision-zero.json", Q, rep("/notes/0/current_revision", 0),
        err("minimum", "/notes/0/current_revision", "properties/notes/items/properties/current_revision/minimum")),
    inv("note-without-revision-list.json", Q, rm("/notes/0/revisions"), req("/notes/0", "properties/notes/items/required", "revisions")),
    inv("note-revision-without-number.json", Q, rm("/notes/0/revisions/0/revision"),
        req("/notes/0/revisions/0", "properties/notes/items/properties/revisions/items/required", "revision")),
    inv("note-revision-number-zero.json", Q, rep("/notes/0/revisions/0/revision", 0),
        err("minimum", "/notes/0/revisions/0/revision", "properties/notes/items/properties/revisions/items/properties/revision/minimum")),
    inv("note-revision-without-body.json", Q, rm("/notes/0/revisions/0/body"),
        req("/notes/0/revisions/0", "properties/notes/items/properties/revisions/items/required", "body")),
    inv("note-revision-without-format.json", Q, rm("/notes/0/revisions/0/format"),
        req("/notes/0/revisions/0", "properties/notes/items/properties/revisions/items/required", "format")),
    inv("note-revision-saved-at-not-utc.json", Q, rep("/notes/0/revisions/0/saved_at", "2026-10-13T10:00:10+02:00"),
        err("pattern", "/notes/0/revisions/0/saved_at", "properties/notes/items/properties/revisions/items/properties/saved_at/pattern")),
    inv("note-trashed-at-not-utc.json", Q, add("/notes/0/trashed_at", "2026-10-14T10:00:00+01:00"),
        err("pattern", "/notes/0/trashed_at", "properties/notes/items/properties/trashed_at/pattern")),
    inv("generated-answer-without-question.json", G, rm("/generated_answer/question"), req("/generated_answer", "properties/generated_answer/required", "question")),
    inv("generated-answer-without-answer-text-field.json", G, rm("/generated_answer/answer_text"),
        req("/generated_answer", "properties/generated_answer/required", "answer_text")),
    inv("generated-answer-without-conversation.json", G, rm("/generated_answer/conversation_id"),
        req("/generated_answer", "properties/generated_answer/required", "conversation_id")),
    inv("generated-answer-without-message.json", G, rm("/generated_answer/message_id"), req("/generated_answer", "properties/generated_answer/required", "message_id")),
    inv("generated-answer-without-endpoint.json", G, rm("/generated_answer/endpoint"), req("/generated_answer", "properties/generated_answer/required", "endpoint")),
    inv("generated-answer-uppercase-conversation-id.json", G, rep("/generated_answer/conversation_id", answer["conversation_id"].upper()),
        err("pattern", "/generated_answer/conversation_id", "properties/generated_answer/properties/conversation_id/pattern")),
    inv("generated-answer-uppercase-message-id.json", G, rep("/generated_answer/message_id", answer["message_id"].upper()),
        err("pattern", "/generated_answer/message_id", "properties/generated_answer/properties/message_id/pattern")),
    inv("generated-answer-uppercase-context-pack-id.json", G, rep("/generated_answer/context_pack_id", answer["context_pack_id"].upper()),
        err("pattern", "/generated_answer/context_pack_id", "properties/generated_answer/properties/context_pack_id/pattern")),
    inv("generated-answer-endpoint-without-provider-kind.json", G, rm("/generated_answer/endpoint/provider_kind"),
        req("/generated_answer/endpoint", "properties/generated_answer/properties/endpoint/required", "provider_kind")),
    inv("generated-answer-endpoint-without-host.json", G, rm("/generated_answer/endpoint/host"),
        req("/generated_answer/endpoint", "properties/generated_answer/properties/endpoint/required", "host")),
    inv("generated-answer-endpoint-without-classification.json", G, rm("/generated_answer/endpoint/classification"),
        req("/generated_answer/endpoint", "properties/generated_answer/properties/endpoint/required", "classification")),
    inv("generated-answer-endpoint-without-model.json", G, rm("/generated_answer/endpoint/model"),
        req("/generated_answer/endpoint", "properties/generated_answer/properties/endpoint/required", "model")),
    inv("generated-answer-endpoint-unknown-provider-kind.json", G, rep("/generated_answer/endpoint/provider_kind", "google_genai"),
        err("enum", "/generated_answer/endpoint/provider_kind", "properties/generated_answer/properties/endpoint/properties/provider_kind/enum")),
    inv("generated-answer-endpoint-unknown-classification.json", G, rep("/generated_answer/endpoint/classification", "cloud"),
        err("enum", "/generated_answer/endpoint/classification", "properties/generated_answer/properties/endpoint/properties/classification/enum")),
    inv("excerpt-uppercase-blob-digest.json", AU, rep("/retained_excerpt/blob_sha256", single_excerpt["blob_sha256"].upper()),
        err("pattern", "/retained_excerpt/blob_sha256", f"{XP}/properties/blob_sha256/pattern")),
    inv("excerpt-file-extension-uppercase.json", AU, rep("/retained_excerpt/file_extension", "M4A"),
        err("pattern", "/retained_excerpt/file_extension", f"{XP}/properties/file_extension/pattern")),
    inv("excerpt-media-type-not-a-media-type.json", AU, rep("/retained_excerpt/media_type", "audio"),
        err("pattern", "/retained_excerpt/media_type", f"{XP}/properties/media_type/pattern")),
    inv("excerpt-byte-count-zero.json", AU, rep("/retained_excerpt/byte_count", 0), err("minimum", "/retained_excerpt/byte_count", f"{XP}/properties/byte_count/minimum")),
    inv("excerpt-duration-zero.json", AU, rep("/retained_excerpt/duration_ms", 0), err("minimum", "/retained_excerpt/duration_ms", f"{XP}/properties/duration_ms/minimum")),
    inv("excerpt-sample-rate-zero.json", AU, rep("/retained_excerpt/sample_rate_hz", 0),
        err("minimum", "/retained_excerpt/sample_rate_hz", f"{XP}/properties/sample_rate_hz/minimum")),
    inv("excerpt-frame-count-zero.json", AU, rep("/retained_excerpt/frame_count", 0), err("minimum", "/retained_excerpt/frame_count", f"{XP}/properties/frame_count/minimum")),
    inv("excerpt-no-actual-ranges.json", AU, rep("/retained_excerpt/actual_ranges", []),
        err("minItems", "/retained_excerpt/actual_ranges", f"{XP}/properties/actual_ranges/minItems")),
    inv("excerpt-actual-range-without-asset-id.json", AU, rm("/retained_excerpt/actual_ranges/0/asset_id"),
        req("/retained_excerpt/actual_ranges/0", f"{XP}/properties/actual_ranges/items/required", "asset_id")),
    inv("excerpt-actual-range-without-start.json", AU, rm("/retained_excerpt/actual_ranges/0/start_ms"),
        req("/retained_excerpt/actual_ranges/0", f"{XP}/properties/actual_ranges/items/required", "start_ms")),
    inv("excerpt-actual-range-without-end.json", AU, rm("/retained_excerpt/actual_ranges/0/end_ms"),
        req("/retained_excerpt/actual_ranges/0", f"{XP}/properties/actual_ranges/items/required", "end_ms")),
    inv("excerpt-actual-range-asset-id-not-a-uuid.json", AU, rep("/retained_excerpt/actual_ranges/0/asset_id", "part-1"),
        err("pattern", "/retained_excerpt/actual_ranges/0/asset_id", f"{XP}/properties/actual_ranges/items/properties/asset_id/pattern")),
    inv("excerpt-actual-range-negative-start.json", AU, rep("/retained_excerpt/actual_ranges/0/start_ms", -1),
        err("minimum", "/retained_excerpt/actual_ranges/0/start_ms", f"{XP}/properties/actual_ranges/items/properties/start_ms/minimum")),
    inv("excerpt-actual-range-end-zero.json", AU, rep("/retained_excerpt/actual_ranges/0/end_ms", 0),
        err("minimum", "/retained_excerpt/actual_ranges/0/end_ms", f"{XP}/properties/actual_ranges/items/properties/end_ms/minimum")),
    inv("excerpt-actual-range-negative-clip-offset.json", AU, rep("/retained_excerpt/actual_ranges/0/clip_start_ms", -1),
        err("minimum", "/retained_excerpt/actual_ranges/0/clip_start_ms", f"{XP}/properties/actual_ranges/items/properties/clip_start_ms/minimum")),
    inv("excerpt-removed-at-not-utc.json", RMV, rep("/retained_excerpt/removed_at", "2026-10-20T10:00:00+01:00"),
        err("pattern", "/retained_excerpt/removed_at", f"{XP}/properties/removed_at/pattern")),
    inv("excerpt-failure-without-reason.json", FAIL, rm("/retained_excerpt/failure/reason"),
        req("/retained_excerpt/failure", f"{XP}/properties/failure/required", "reason")),
    inv("excerpt-failure-attempts-zero.json", FAIL, rep("/retained_excerpt/failure/attempts", 0),
        err("minimum", "/retained_excerpt/failure/attempts", f"{XP}/properties/failure/properties/attempts/minimum")),
    inv("transcript-uppercase-clip-digest.json", TRS, rep("/transcript/clip_sha256", transcript["clip_sha256"].upper()),
        err("pattern", "/transcript/clip_sha256", "properties/transcript/properties/clip_sha256/pattern")),
    inv("transcript-created-at-not-utc.json", TRS, rep("/transcript/created_at", "2026-10-13T10:05:00+02:00"),
        err("pattern", "/transcript/created_at", "properties/transcript/properties/created_at/pattern")),
    inv("transcript-without-raw-text.json", TRS, rm("/transcript/raw_text"), req("/transcript", "properties/transcript/required", "raw_text")),
    inv("transcript-without-segments.json", TRS, rm("/transcript/segments"), req("/transcript", "properties/transcript/required", "segments")),
    inv("transcript-without-provider-kind.json", TRS, rm("/transcript/provider_kind"), req("/transcript", "properties/transcript/required", "provider_kind")),
    inv("transcript-without-host.json", TRS, rm("/transcript/host"), req("/transcript", "properties/transcript/required", "host")),
    inv("transcript-without-model.json", TRS, rm("/transcript/model"), req("/transcript", "properties/transcript/required", "model")),
    inv("transcript-without-created-at.json", TRS, rm("/transcript/created_at"), req("/transcript", "properties/transcript/required", "created_at")),
    inv("transcript-without-discarded-count.json", TRS, rm("/transcript/discarded_segment_count"),
        req("/transcript", "properties/transcript/required", "discarded_segment_count")),
    inv("transcript-negative-discarded-count.json", TRS, rep("/transcript/discarded_segment_count", -1),
        err("minimum", "/transcript/discarded_segment_count", "properties/transcript/properties/discarded_segment_count/minimum")),
    inv("transcript-segment-without-start.json", TRS, rm("/transcript/segments/0/start_ms"),
        req("/transcript/segments/0", "properties/transcript/properties/segments/items/required", "start_ms")),
    inv("transcript-segment-without-end.json", TRS, rm("/transcript/segments/0/end_ms"),
        req("/transcript/segments/0", "properties/transcript/properties/segments/items/required", "end_ms")),
    inv("transcript-segment-without-text.json", TRS, rm("/transcript/segments/0/text"),
        req("/transcript/segments/0", "properties/transcript/properties/segments/items/required", "text")),
    inv("transcript-segment-negative-start.json", TRS, rep("/transcript/segments/0/start_ms", -1),
        err("minimum", "/transcript/segments/0/start_ms", "properties/transcript/properties/segments/items/properties/start_ms/minimum")),
    inv("transcript-segment-negative-end.json", TRS, rep("/transcript/segments/0/end_ms", -1),
        err("minimum", "/transcript/segments/0/end_ms", "properties/transcript/properties/segments/items/properties/end_ms/minimum")),
    # Every integer field refuses a fraction: milliseconds, frame and attempt counts, revisions (Contracts/README.md,
    # units; review finding R2-01; commands/mutation-pass.py protects each numeric `type`).
    inv("revision-fractional.json", Q, rep("/revision", 1.5), err("type", "/revision", "properties/revision/type")),
    inv("note-fractional-current-revision.json", Q, rep("/notes/0/current_revision", 1.5),
        err("type", "/notes/0/current_revision", "properties/notes/items/properties/current_revision/type")),
    inv("note-revision-fractional-number.json", Q, rep("/notes/0/revisions/0/revision", 1.5),
        err("type", "/notes/0/revisions/0/revision", "properties/notes/items/properties/revisions/items/properties/revision/type")),
    inv("excerpt-fractional-duration.json", AU, rep("/retained_excerpt/duration_ms", single_excerpt["duration_ms"] + 0.5),
        err("type", "/retained_excerpt/duration_ms", f"{XP}/properties/duration_ms/type")),
    inv("excerpt-fractional-frame-count.json", AU, rep("/retained_excerpt/frame_count", single_excerpt["frame_count"] + 0.5),
        err("type", "/retained_excerpt/frame_count", f"{XP}/properties/frame_count/type")),
    inv("excerpt-actual-range-fractional-start.json", AU, rep("/retained_excerpt/actual_ranges/0/start_ms",
        single_excerpt["actual_ranges"][0]["start_ms"] + 0.5),
        err("type", "/retained_excerpt/actual_ranges/0/start_ms", f"{XP}/properties/actual_ranges/items/properties/start_ms/type")),
    inv("excerpt-actual-range-fractional-end.json", AU, rep("/retained_excerpt/actual_ranges/0/end_ms",
        single_excerpt["actual_ranges"][0]["end_ms"] + 0.5),
        err("type", "/retained_excerpt/actual_ranges/0/end_ms", f"{XP}/properties/actual_ranges/items/properties/end_ms/type")),
    inv("excerpt-actual-range-fractional-clip-offset.json", AU, rep("/retained_excerpt/actual_ranges/0/clip_start_ms", 0.5),
        err("type", "/retained_excerpt/actual_ranges/0/clip_start_ms", f"{XP}/properties/actual_ranges/items/properties/clip_start_ms/type")),
    inv("excerpt-failure-fractional-attempts.json", FAIL, rep("/retained_excerpt/failure/attempts", 1.5),
        err("type", "/retained_excerpt/failure/attempts", f"{XP}/properties/failure/properties/attempts/type")),
    inv("transcript-segment-fractional-start.json", TRS, rep("/transcript/segments/0/start_ms", 0.5),
        err("type", "/transcript/segments/0/start_ms", "properties/transcript/properties/segments/items/properties/start_ms/type")),
    inv("transcript-segment-fractional-end.json", TRS, rep("/transcript/segments/0/end_ms", 4200.5),
        err("type", "/transcript/segments/0/end_ms", "properties/transcript/properties/segments/items/properties/end_ms/type")),
    inv("transcript-fractional-discarded-count.json", TRS, rep("/transcript/discarded_segment_count", 0.5),
        err("type", "/transcript/discarded_segment_count", "properties/transcript/properties/discarded_segment_count/type")),
    # Schema-valid, but each breaks exactly the code-checked rule its name starts with.
    sem("u1-note-with-an-unpaired-surrogate.json", Q, rep("/notes/0/revisions/0/body", "First thought.\udc00")),
    sem("c1-anchor-names-another-edition.json", Q, rep("/anchors/0/edition_id", MED_AUDIO_ED)),
    sem("c1-anchor-names-another-work.json", Q, rep("/anchors/0/work_id", WALDEN_WORK)),
    sem("c2-quoted-text-trimmed.json", Q, rep("/quoted_text", epub_noteref["exact_text"][:-1])),
    sem("c2-resources-joined-with-one-newline.json", "quote-epub-across-two-resources.json",
        rep("/quoted_text", "\n".join(a["exact_text"] for a in epub_cross))),
    sem("c2-word-sentence-without-the-word.json", W, rep("/word/source_sentence", "From my mother, piety and abstinence.")),
    sem("c3-epub-anchors-out-of-order.json", "quote-epub-across-two-resources.json", rep("/anchors", list(reversed(epub_cross)))),
    sem("c3-epub-anchors-from-two-assets.json", "quote-epub-across-two-resources.json",
        rep("/anchors/1/asset_sha256", epub_noteref["asset_sha256"])),
    sem("c3-single-anchor-claims-a-second-segment.json", Q, add("/anchors/0/segment", {"index": 0, "count": 2})),
    sem("c4-actual-ranges-name-another-asset.json", AU, rep("/retained_excerpt/actual_ranges/0/asset_id", P2["asset_id"].lower())),
    # Part 2's range decoded to no samples while Part 1's 20 s did: frames and duration agree with what was written
    # (rule C9), so only the empty range is wrong. One operation replaces the excerpt record.
    sem("c4-actual-range-empty.json", "audio-preserved-cross-file-quick-capture.json", rep("/retained_excerpt", dict(
        cross_excerpt, frame_count=882000, duration_ms=20000,
        actual_ranges=[cross_excerpt["actual_ranges"][0], dict(cross_excerpt["actual_ranges"][1], start_ms=5000, end_ms=5000)]))),
    # The reviewer's other example: an excerpt that claims audio from elsewhere in the file.
    sem("c4-actual-range-elsewhere-in-the-file.json", AU, rep("/retained_excerpt/actual_ranges/0",
        dict(single_excerpt["actual_ranges"][0], start_ms=0, end_ms=30000))),
    sem("c5-machine-quote-differs-from-raw-text.json", "audio-machine-transcript-quote.json", rep("/quoted_text", RAW + " More.")),
    sem("c5-transcript-of-another-clip.json", "audio-machine-transcript-quote.json", rep("/transcript/clip_sha256", cross_excerpt["blob_sha256"])),
    sem("c6-note-revisions-skip-a-number.json", Q, rep("/notes/0/revisions/1/revision", 3)),
    sem("c6-current-revision-not-latest.json", Q, rep("/notes/0/current_revision", 1)),
    sem("c6-two-notes-share-an-id.json", Q, add("/notes/1", capture_valid[Q]["notes"][0])),
    sem("c7-transcript-segment-runs-backwards.json", TRS, rep("/transcript/segments/0/start_ms", 5000)),
    sem("c7-transcript-segment-past-the-excerpt.json", TRS, rep("/transcript/segments/0/end_ms", 31001)),
    sem("c8-preserved-excerpt-at-revision-1.json", AU, rep("/revision", 1)),
    sem("c8-second-failed-attempt-at-revision-2.json", FAIL, rep("/retained_excerpt/failure/attempts", 2)),
    sem("c8-trashed-at-revision-1.json", "quote-in-trash.json", rep("/revision", 1)),
    sem("c9-first-range-not-at-the-excerpt-start.json", AU, rep("/retained_excerpt/actual_ranges/0/clip_start_ms", 5)),
    sem("c9-second-range-after-a-gap.json", "audio-preserved-cross-file-quick-capture.json", rep("/retained_excerpt/actual_ranges/1/clip_start_ms", 25000)),
    # 30,050 ms of frames for 30,000 ms of ranges: within the read-back tolerance of duration_ms, not of the ranges.
    sem("c9-frame-count-not-the-ranges.json", AU, rep("/retained_excerpt/frame_count", 1325205)),
    # The reviewer's example: a read-back duration of 1 ms for 30 s of ranges.
    sem("c9-duration-not-the-frames.json", AU, rep("/retained_excerpt/duration_ms", 1)),
    # Each branch of a code rule has a fixture that only it detects (commands/mutation-pass.py; review finding R2-01).
    sem("a2-quote-anchor-offsets-shorter-than-text.json", Q, rep("/anchors/0/text_offsets/end", epub_noteref["text_offsets"]["end"] - 1)),
    sem("c2-pdf-quote-is-not-its-anchor-text.json", "quote-pdf-two-pages.json",
        rep("/quoted_text", pdf_two_pages["exact_text"].replace("\n", " "))),
    sem("c2-text-quote-is-not-its-anchor-text.json", "quote-text-plain.json", rep("/quoted_text", walden_quote[:-len(" of life")])),
    sem("c2-two-pdf-anchors-have-no-defined-join.json", "quote-pdf-two-pages.json", add("/anchors/1", pdf_multiline)),
    # The reviewer's example (R2-03): a later writer's anchor beside the EPUB anchor no longer exempts the quotation.
    sem("c2-quote-differs-from-its-epub-anchor-beside-a-later-kind-anchor.json", "unknown-kind-anchor-beside-an-epub-selection.json",
        rep("/quoted_text", "Words that appear nowhere in the anchored passage.")),
    sem("c3-epub-segment-count-not-the-number-of-anchors.json", "quote-epub-across-two-resources.json", rep("/anchors/1/segment/count", 3)),
    # The reviewer's example (R2-02): the actual range overlaps the request by 1 ms, so 29.999 s of the 30 s excerpt
    # come from after it. Its length is unchanged, so frames and duration still agree (C9 holds).
    sem("c4-actual-range-overlaps-by-one-millisecond.json", AU, rep("/retained_excerpt/actual_ranges/0",
        dict(single_excerpt["actual_ranges"][0], start_ms=89999, end_ms=119999))),
    # 600 ms missing at the start or at the end, with the frames and read-back duration of the 29.4 s written (C9 holds).
    sem("c4-actual-range-starts-late.json", AU, rep("/retained_excerpt", dict(
        single_excerpt, frame_count=1296540, duration_ms=29400,
        actual_ranges=[dict(single_excerpt["actual_ranges"][0], start_ms=single_excerpt["actual_ranges"][0]["start_ms"] + 600)]))),
    sem("c4-actual-range-ends-early.json", AU, rep("/retained_excerpt", dict(
        single_excerpt, frame_count=1296540, duration_ms=29400,
        actual_ranges=[dict(single_excerpt["actual_ranges"][0], end_ms=single_excerpt["actual_ranges"][0]["end_ms"] - 600)]))),
    sem("c5-corrected-quote-differs-from-corrected-text.json", "audio-corrected-transcript-quote.json", rep("/quoted_text", RAW)),
    sem("c5-later-kind-transcript-quote-without-an-excerpt.json", "unknown-kind-reusing-the-excerpt-and-transcript.json",
        rm("/retained_excerpt")),
    sem("c8-removed-excerpt-at-revision-3.json", RMV, rep("/revision", 3)),
    sem("c8-transcript-at-revision-2.json", TRS, rep("/revision", 2)),
]


def write(out: Path, stem: str, valid: dict, ops: list) -> None:
    base = out / stem
    for folder in ("valid", "invalid", "semantic-invalid"):
        shutil.rmtree(base / folder, ignore_errors=True)
        (base / folder).mkdir(parents=True)
    for name, doc in valid.items():
        (base / "valid" / name).write_text(dumps(doc), encoding="utf-8")
    names = [e["fixture"] for e in ops]
    duplicates = sorted({n for n in names if names.count(n) > 1})
    if duplicates:
        raise SystemExit(f"{stem}: fixtures listed twice: {duplicates}")
    for entry in ops:
        doc = checker.apply_ops(valid[entry["base"]], entry["ops"])
        (base / entry["fixture"]).write_text(dumps(doc), encoding="utf-8")
    (base / "mutations.json").write_text(dumps(ops), encoding="utf-8")
    print(f"{stem}: {len(valid)} valid, {sum(1 for o in ops if o['fixture'].startswith('invalid/'))} invalid, "
          f"{sum(1 for o in ops if o['fixture'].startswith('semantic-invalid/'))} semantic-invalid")


def show(out: Path) -> int:
    """Print each invalid fixture's actual schema errors beside its listed ones, and each semantic one's rules."""
    schemas = checker.Schemas(checker.load_schemas(ROOT))
    differences = 0
    for stem, key, ops, rules in (("anchor.v1", "anchor", anchor_ops, checker.anchor_violations),
                                  ("capture-envelope.v1", "capture", capture_ops, checker.capture_violations)):
        for entry in ops:
            doc = json.loads((out / stem / entry["fixture"]).read_text(encoding="utf-8"))
            got = schemas.errors(key, doc)
            if entry["fixture"].startswith("invalid/"):
                want = sorted(entry["expect"], key=lambda d: json.dumps(d, sort_keys=True))
                same = got == want
                print(f"{'same' if same else 'DIFF'} {stem}/{entry['fixture']}")
                if not same:
                    differences += 1
                    print("     got:  " + " | ".join(map(checker.describe_error, got)))
                    print("     want: " + " | ".join(map(checker.describe_error, want)))
            else:
                found = [r for r, _ in rules(doc)] if not got else ["schema-invalid"]
                same = found == [entry["expect"][0]["rule"]]
                differences += not same
                print(f"{'same' if same else 'DIFF'} {stem}/{entry['fixture']}: {found}")
    print(f"differences: {differences}")
    return 1 if differences else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--show":
        target = Path(sys.argv[2]).resolve()
        write(target, "anchor.v1", anchor_valid, anchor_ops)
        write(target, "capture-envelope.v1", capture_valid, capture_ops)
        sys.exit(show(target))
    out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "Contracts/fixtures"
    write(out, "anchor.v1", anchor_valid, anchor_ops)
    write(out, "capture-envelope.v1", capture_valid, capture_ops)
    sys.exit(0)
