#!/usr/bin/env python3
"""Check the anchor and capture-envelope contracts against what the Stage 0 spikes emit (ADR-0016).

JSON Schema validation of the committed fixtures is Scripts/validate-contracts.py's job. This script adds what that
check cannot show:

  0. Agreement with the other contracts. The capture kinds the schema knows are exactly the kinds
     Contracts/design/marginalia.v1.json maps onto the five capture markers (plan 4.4.5), and an unknown kind renders
     as Pending, never as Quote. A saved answer's endpoint uses exactly the context-pack contract's provider kinds and
     classifications, and every provider-config provider kind is either such an endpoint kind or a transcript's
     provider kind. The secret-name pattern is the context-pack one written without its (?i) flag. Every `pattern` in
     every contract schema and OpenAPI document compiles in Python and as ECMA-262 with the u flag (JSON Schema's
     dialect, which JavaScript validators use), except the recorded ones in other owners' contracts
     (KNOWN_NON_PORTABLE_PATTERNS). The kind lists in this script are read from the schemas.
  1. Fixtures (Contracts/fixtures/{anchor,capture-envelope}.v1/; each directory's mutations.json lists every invalid
     and semantic-invalid fixture with its base, its JSON Pointer operations and what it must fail with).
     * Every valid fixture passes the code-checked rules (U1, A1-A7, C1-C9) and the v1 writer profile (only known
       kinds), except the fixtures named unknown-kind-*, which show what a later writer may emit and a v1 reader
       accepts.
     * Every invalid fixture is its base valid fixture with the listed operations: one, or two where a field is added
       or removed together with the field that depends on it (the entry says why). It must fail the schema with
       exactly the listed errors (validator keyword, instance path, schema path with allOf members named by their
       title, and the missing property for a required or dependentRequired error), one error per fixture except where
       the entry lists more and says why. So a deleted or weakened schema rule changes a listed outcome and fails here.
     * Every semantic-invalid fixture is schema-valid, is its base with the listed operations, and breaks exactly one
       code-checked rule once: the rule its file name starts with.
  2. Spike output, adapted into the contract by the explicit steps below and then validated (schema, code rules and
     the v1 writer profile):
     * G0.1 EPUB: Docs/Stage0/evidence/G01-EPUB/anchor-samples.json and selection-samples.json (simulator output of
       the spike's AnchorSamplesTests and SelectionCaptureTests).
     * G0.1 PDF: Docs/Stage0/evidence/G01-PDF/anchor-samples.json (simulator output of AnchorCaptureRestoreTests),
       its ten anchors and its capture-envelope example.
     * G0.4 audio: Docs/Stage0/evidence/M0-contracts/g04-capture-records/ (records written by G0.4's own
       FileCaptureStore through CaptureService and AACExcerptExporter, run by commands/run-g04-capture-probe.sh).
     Every adaptation is a rename, a removal of a null, or a value the spike does not record, supplied by this script
     and counted in the report. Nothing a spike recorded is changed.
  3. G0.5 recovery: every capture row of Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite
     (the persistence spike's golden corpus, written through its own store), with its anchor, excerpt and note rows,
     and every note row without a capture on a whole work (as the note capture the envelope makes of it) is mapped
     field by field into an envelope; a note on an AI conversation has no v1 form and is recorded as such. A value the persistence spike does not store is filled with a
     placeholder that names a recorded deviation (RECOVERY_DEVIATIONS, ADR-0016 section 8); the envelope must then be
     schema-valid, and each code-rule violation must be a recorded deviation. The table definitions are read for the
     deviations rows cannot show. An observed difference that is not recorded fails, and so does a recorded one that is
     no longer observed.

Usage: check-spike-anchors.py [--root <repository root>] [--report <file>]
Exit status is non-zero if any check fails.
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import re
import sqlite3
import sys
import uuid
from collections import Counter
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
from referencing.exceptions import Unresolvable
from referencing.jsonschema import DRAFT202012

ANCHOR_ID = "urn:sylvia:schema:anchor:v1"
CAPTURE_ID = "urn:sylvia:schema:capture-envelope:v1"
CONTEXT_PACK_ID = "urn:sylvia:schema:context-pack:v1"
PROVIDER_CONFIG_ID = "urn:sylvia:schema:provider-config:v1"
TEXT_ANCHOR_KINDS = {"epub", "pdf", "text"}
MAX_AUDIO_SELECTION_MS = 120_000
# A7 tolerance for the 6-decimal rounding of a rectangle's x and w (or y and h).
RECT_TOLERANCE = 0.000001
# C9: AAC-LC adds 2,112 priming and up to 1,023 padding frames; a reader that ignores the edit list counts them.
PRIMING_PADDING_FRAMES = 4096
# C7: G0.5 AI drops transcript segments that end further than this past the clip.
SEGMENT_PAST_CLIP_MS = 1_000
# C4: plan 19.2's capture boundary budget ("within 500 ms of intended boundary"); ADR-0006 decision 14 measured the
# decoder's recorded actual start at most 47.9 ms from the true content position for every codec it tested.
BOUNDARY_BUDGET_MS = 500
TRANSCRIPT_ORIGINS = {"machine_transcript", "corrected_transcript"}
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
FIXTURE_NAMESPACE = uuid.UUID("6ba7b811-9dad-11d1-80b4-00c04fd430c8")  # RFC 4122 URL namespace
EPUB_SEGMENT_SEPARATOR = "\n\n"  # Spikes/G01-EPUB/Adapter/CaptureBuilder.swift, segmentSeparator
# Unicode White_Space (PropList.txt): what the EPUB adapter collapses before it looks for a selection in the extraction.
WHITE_SPACE_RUN = re.compile("[\u0009-\u000d \u0085   -     　]+")
SURROGATE = re.compile("[\ud800-\udfff]")

RULES = {
    "U1": "every string is a sequence of Unicode scalar values (no unpaired surrogate)",
    "A1": "every range has start < end",
    "A2": "a scalar range covers its text (EPUB text_offsets: the text with whitespace collapsed)",
    "A3": "a PDF anchor's exact_text is its segments' texts in document order, with nothing or one U+000A between two "
          "on one page and one U+000A between two on different pages (the reader's composition, ADR-0005)",
    "A4": "PDF segments are in document order",
    "A5": "an EPUB segment index is below its count",
    "A6": "audio ranges name distinct assets, ranges after the first start at 0, total at most 120,000 ms",
    "A7": "a PDF line rectangle lies within its page box (x + w <= 1, y + h <= 1, within 0.000001)",
    "C1": "anchors name the capture's work, and its edition when they name one",
    "C2": "a selected text_quote or word equals the exact text of its EPUB, PDF or text anchors (later kinds beside "
          "them are not compared; a selection with only later kinds is not checked); a word's source sentence "
          "contains it",
    "C3": "a capture's EPUB anchors name one asset; several carry segments 0..n-1 of n in order; one carries none",
    "C4": "a preserved or removed excerpt's actual ranges name the anchor's assets in order; each is non-empty, "
          "overlaps the anchor's range at its position and starts and ends within 500 ms of it",
    "C5": "a transcript quotation equals the transcript text, and the capture has the retained excerpt the "
          "transcript is of",
    "C6": "note revisions are numbered 1..n, current_revision is n, and note IDs are unique",
    "C7": "a transcript segment never runs backwards and ends at most 1,000 ms past the excerpt it transcribes",
    "C8": "revision is at least the durable writes the capture's state implies",
    "C9": "a preserved or removed excerpt's clip offsets, frame count and read-back duration agree with its actual ranges",
}


# ----------------------------------------------------------------------------------------------- code rules


def collapse_whitespace(text: str) -> str:
    """Each maximal run of White_Space replaced by one U+0020, leading and trailing ones removed (ADR-0016, A2)."""
    return WHITE_SPACE_RUN.sub(" ", text).strip(" ")


def scalar_len(text: str) -> int:
    """Unicode scalars in a str. Python strings are sequences of code points; rule U1 rejects surrogates."""
    return len(text)


def surrogate_violations(document, where: str = "") -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []

    def walk(value, path: str) -> None:
        if isinstance(value, str):
            if SURROGATE.search(value):
                out.append(("U1", f"{path or '(root)'}: unpaired surrogate"))
        elif isinstance(value, dict):
            for key, item in value.items():
                if SURROGATE.search(key):
                    out.append(("U1", f"{path}: property name with an unpaired surrogate"))
                walk(item, f"{path}/{key}")
        elif isinstance(value, list):
            for i, item in enumerate(value):
                walk(item, f"{path}/{i}")

    walk(document, where)
    return out


def anchor_violations(anchor: dict, *, check_strings: bool = True) -> list[tuple[str, str]]:
    """Rules U1 and A1-A7 on one schema-valid anchor."""
    out: list[tuple[str, str]] = surrogate_violations(anchor) if check_strings else []
    kind = anchor.get("kind")

    def scalar_range(r: dict | None, text: str | None, where: str, collapse: bool = False) -> None:
        if r is None:
            return
        if not r["start"] < r["end"]:
            out.append(("A1", f"{where}: start {r['start']} is not before end {r['end']}"))
            return
        if text is None:
            return
        covered = collapse_whitespace(text) if collapse else text
        if r["end"] - r["start"] != scalar_len(covered):
            what = "the text with whitespace collapsed" if collapse else "the text"
            out.append(("A2", f"{where}: range covers {r['end'] - r['start']} scalars, {what} has {scalar_len(covered)}"))

    if kind == "epub":
        scalar_range(anchor.get("text_offsets"), anchor.get("exact_text"), "text_offsets", collapse=True)
        seg = anchor.get("segment")
        if seg is not None and not seg["index"] < seg["count"]:
            out.append(("A5", f"segment index {seg['index']} is not below count {seg['count']}"))
    elif kind == "pdf":
        segments = anchor["segments"]
        for i, s in enumerate(segments):
            scalar_range(s["text_range"], s["text"], f"segments/{i}/text_range")
            for j, (x, y, w, h) in enumerate(s["line_rects"]):
                if x + w > 1 + RECT_TOLERANCE or y + h > 1 + RECT_TOLERANCE:
                    out.append(("A7", f"segments/{i}/line_rects/{j}: x + w = {x + w:.6f}, y + h = {y + h:.6f}: "
                                      f"past the page box"))
        # A3 (ADR-0005): exact_text is the reader's own composition of the pieces, not one fixed join. With one segment
        # it is that segment's text; with several, their texts in document order with nothing or one U+000A between
        # two pieces on one page (PDFKit keeps the line break after a piece that ends at a line's end) and one U+000A
        # where the page changes. A reader restores segment by segment and keeps exact_text as the quotation; this rule
        # refuses an exact_text no such composition of the segments gives. (Until 19 October 2026 the rule required the
        # "\n" join, which refused six of the eleven composed selections the G0.1 PDF spike stores exactly; M0 final
        # review R1-02.)
        texts = [re.escape(s["text"]) for s in segments]
        breaks = ["\n" if b["page_index"] != a["page_index"] else "\n?" for a, b in zip(segments, segments[1:])]
        if not re.fullmatch(texts[0] + "".join("\n?" + t for t in texts[1:]), anchor["exact_text"]):
            out.append(("A3", "exact_text is not the segments' texts in order with at most one U+000A between two"))
        elif not re.fullmatch(texts[0] + "".join(j + t for j, t in zip(breaks, texts[1:])), anchor["exact_text"]):
            out.append(("A3", "exact_text has no U+000A between two segments on different pages"))
        for i in range(1, len(segments)):
            a, b = segments[i - 1], segments[i]
            if b["page_index"] < a["page_index"]:
                out.append(("A4", f"segment {i} is on page {b['page_index']}, before segment {i - 1}'s page "
                                  f"{a['page_index']}"))
            elif b["page_index"] == a["page_index"] and b["text_range"]["start"] < a["text_range"]["end"]:
                out.append(("A4", f"segment {i} starts at {b['text_range']['start']}, before segment {i - 1} ends "
                                  f"at {a['text_range']['end']} on the same page"))
    elif kind == "text":
        scalar_range(anchor.get("text_range"), anchor.get("exact_text"), "text_range")
    elif kind == "audio":
        ranges = anchor["ranges"]
        total = 0
        for i, r in enumerate(ranges):
            if not r["start_ms"] < r["end_ms"]:
                out.append(("A1", f"ranges/{i}: start_ms {r['start_ms']} is not before end_ms {r['end_ms']}"))
            else:
                total += r["end_ms"] - r["start_ms"]
            if i > 0 and r["start_ms"] != 0:
                out.append(("A6", f"ranges/{i} continues the selection but starts at {r['start_ms']} ms, not 0"))
        ids = [r["asset_id"] for r in ranges]
        if len(set(ids)) != len(ids):
            out.append(("A6", "an asset appears in more than one range"))
        if total > MAX_AUDIO_SELECTION_MS:
            out.append(("A6", f"selection is {total} ms, above {MAX_AUDIO_SELECTION_MS} ms"))
    return out


def minimum_revision(capture: dict) -> int:
    """Rule C8: the durable writes a capture's state implies. Plan 10.2 writes the anchor (revision 1) before the
    export's outcome; each failed attempt is recorded durably; a removal follows a preservation; a transcript is made
    from a preserved excerpt; moving to the trash is a change of its own."""
    floor = 1
    excerpt = capture.get("retained_excerpt") or {}
    state = excerpt.get("state")
    if state == "preserved":
        floor += 1
    elif state == "failed":
        floor += excerpt["failure"]["attempts"]
    elif state == "removed":
        floor += 2
    if "transcript" in capture:
        floor += 1
    if "trashed_at" in capture:
        floor += 1
    return floor


def capture_violations(capture: dict) -> list[tuple[str, str]]:
    """Rules U1, A1-A7 (on every anchor) and C1-C9 on one schema-valid capture."""
    out: list[tuple[str, str]] = surrogate_violations(capture)
    anchors = capture["anchors"]
    for i, anchor in enumerate(anchors):
        out += [(rule, f"anchors/{i}: {msg}") for rule, msg in anchor_violations(anchor, check_strings=False)]
        if anchor.get("work_id") != capture["work_id"]:
            out.append(("C1", f"anchors/{i} names work {anchor.get('work_id')}, the capture {capture['work_id']}"))
        if "edition_id" in anchor and anchor["edition_id"] != capture.get("edition_id"):
            out.append(("C1", f"anchors/{i} names edition {anchor['edition_id']}, the capture {capture.get('edition_id')}"))

    kind = capture["kind"]
    epub = [a for a in anchors if a.get("kind") == "epub"]
    if len({(a["asset_id"], a["asset_sha256"]) for a in epub}) > 1:
        out.append(("C3", "the EPUB anchors name more than one asset"))
    if len(epub) > 1:
        indexes = [a.get("segment", {}).get("index") for a in epub]
        counts = {a.get("segment", {}).get("count") for a in epub}
        if indexes != list(range(len(epub))) or counts != {len(epub)}:
            out.append(("C3", f"EPUB anchors have segment indexes {indexes} and counts {sorted(map(str, counts))}"))
    elif len(epub) == 1 and "segment" in epub[0]:
        out.append(("C3", f"a single EPUB anchor carries segment {epub[0]['segment']}"))

    if kind in {"text_quote", "word"} and capture.get("quoted_text_origin") == "selection":
        # C2 compares a selection with the anchors a v1 reader takes text from (EPUB, PDF, text). An anchor of a later
        # writer's kind beside them is not compared, and a selection whose anchors are all of later kinds has nothing
        # v1 can compare, so it is not checked (ADR-0016 sections 5 and 6).
        readable = [a for a in anchors if a.get("kind") in TEXT_ANCHOR_KINDS]
        kinds = sorted({a["kind"] for a in readable})
        expected = None
        if kinds == ["epub"]:
            ordered = sorted(readable, key=lambda a: a.get("segment", {}).get("index", 0))
            expected = EPUB_SEGMENT_SEPARATOR.join(a["exact_text"] for a in ordered)
        elif len(readable) == 1:
            expected = readable[0]["exact_text"]
        elif readable:
            out.append(("C2", f"no defined join for {len(readable)} anchors of kinds {kinds}"))
        if expected is not None and capture["quoted_text"] != expected:
            out.append(("C2", "quoted_text is not the anchors' exact text"))
    word = capture.get("word")
    if kind == "word" and word and "source_sentence" in word and capture["quoted_text"] not in word["source_sentence"]:
        out.append(("C2", "word.source_sentence does not contain quoted_text"))

    excerpt = capture.get("retained_excerpt")
    has_file = excerpt is not None and excerpt.get("state") in {"preserved", "removed"}
    audio = [a for a in anchors if a.get("kind") == "audio"]
    if has_file and len(audio) == 1:
        want, got = audio[0]["ranges"], excerpt["actual_ranges"]
        if [r["asset_id"] for r in want] != [r["asset_id"] for r in got]:
            out.append(("C4", f"actual_ranges name {[r['asset_id'] for r in got]}, the anchor {[r['asset_id'] for r in want]}"))
        for i, r in enumerate(got):
            if not r["start_ms"] < r["end_ms"]:
                out.append(("C4", f"actual_ranges/{i}: start_ms {r['start_ms']} is not before end_ms {r['end_ms']}"))
                continue
            if i >= len(want) or want[i]["asset_id"] != r["asset_id"]:
                continue
            w = want[i]
            if not (r["start_ms"] < w["end_ms"] and w["start_ms"] < r["end_ms"]):
                out.append(("C4", f"actual_ranges/{i} [{r['start_ms']}, {r['end_ms']}) does not overlap the anchor's "
                                  f"range [{w['start_ms']}, {w['end_ms']})"))
            elif (abs(r["start_ms"] - w["start_ms"]) > BOUNDARY_BUDGET_MS
                  or abs(r["end_ms"] - w["end_ms"]) > BOUNDARY_BUDGET_MS):
                out.append(("C4", f"actual_ranges/{i} [{r['start_ms']}, {r['end_ms']}) is more than "
                                  f"{BOUNDARY_BUDGET_MS} ms from the anchor's range [{w['start_ms']}, {w['end_ms']}) "
                                  f"at its start or end"))
    if has_file:
        got = excerpt["actual_ranges"]
        lengths = [r["end_ms"] - r["start_ms"] for r in got]
        if got[0]["clip_start_ms"] != 0:
            out.append(("C9", f"actual_ranges/0: clip_start_ms {got[0]['clip_start_ms']}, not 0"))
        for i in range(1, len(got)):
            ends = got[i - 1]["clip_start_ms"] + lengths[i - 1]
            if abs(got[i]["clip_start_ms"] - ends) > 1:
                out.append(("C9", f"actual_ranges/{i}: clip_start_ms {got[i]['clip_start_ms']}, the range before it "
                                  f"ends at {ends} ms in the excerpt"))
        rate = excerpt["sample_rate_hz"]
        frames_ms = excerpt["frame_count"] * 1000 / rate
        if abs(frames_ms - sum(lengths)) > len(got):
            out.append(("C9", f"frame_count {excerpt['frame_count']} at {rate} Hz is {frames_ms:.1f} ms, the actual "
                              f"ranges total {sum(lengths)} ms"))
        slack = 1 + PRIMING_PADDING_FRAMES * 1000 / rate
        if abs(excerpt["duration_ms"] - frames_ms) > slack:
            out.append(("C9", f"duration_ms {excerpt['duration_ms']} read back for {frames_ms:.1f} ms of frames "
                              f"(tolerance {slack:.1f} ms)"))

    origin = capture.get("quoted_text_origin")
    transcript = capture.get("transcript")
    if origin in TRANSCRIPT_ORIGINS and transcript is not None:
        if origin == "machine_transcript" and capture.get("quoted_text") != transcript["raw_text"]:
            out.append(("C5", "quoted_text is not the transcript's raw_text"))
        if origin == "corrected_transcript" and capture.get("quoted_text") != transcript.get("corrected_text"):
            out.append(("C5", "quoted_text is not the transcript's corrected_text"))
        if excerpt is None:
            out.append(("C5", "a transcript quotation without the retained excerpt the transcript was made from"))
        elif transcript["clip_sha256"] != excerpt.get("blob_sha256"):
            out.append(("C5", "the transcript's clip_sha256 is not the retained excerpt's blob_sha256"))

    for note_id, n in Counter(note["note_id"] for note in capture["notes"]).items():
        if n > 1:
            out.append(("C6", f"note_id {note_id} is used by {n} notes"))
    for i, note in enumerate(capture["notes"]):
        numbers = [r["revision"] for r in note["revisions"]]
        if numbers != list(range(1, len(numbers) + 1)) or note["current_revision"] != len(numbers):
            out.append(("C6", f"notes/{i}: revisions {numbers}, current_revision {note['current_revision']}"))

    if transcript is not None:
        of_this_clip = has_file and transcript["clip_sha256"] == excerpt["blob_sha256"]
        clip_ms = excerpt["duration_ms"] if of_this_clip else None
        for i, s in enumerate(transcript["segments"]):
            if s["start_ms"] > s["end_ms"]:
                out.append(("C7", f"transcript/segments/{i}: start_ms {s['start_ms']} is after end_ms {s['end_ms']}"))
            elif clip_ms is not None and s["end_ms"] > clip_ms + SEGMENT_PAST_CLIP_MS:
                out.append(("C7", f"transcript/segments/{i}: ends at {s['end_ms']} ms, the excerpt is {clip_ms} ms"))

    floor = minimum_revision(capture)
    if capture["revision"] < floor:
        out.append(("C8", f"revision {capture['revision']}, but its state implies at least {floor} durable writes"))
    return out


# ----------------------------------------------------------------------------------------------- schemas


REQUIRED_MESSAGE = re.compile(r"^'(.*)' is a required property$")
DEPENDENCY_MESSAGE = re.compile(r"^'(.*)' is a dependency of '(.*)'$")


def json_pointer(parts) -> str:
    return "".join("/" + str(p).replace("~", "~0").replace("/", "~1") for p in parts)


def pointer_parts(pointer: str) -> list[str]:
    return [p.replace("~1", "/").replace("~0", "~") for p in pointer.split("/")[1:]]


class Schemas:
    """The contract schemas, a registry that resolves them by $id, and validators for the two contracts here."""

    def __init__(self, by_id: dict[str, dict]) -> None:
        self.by_id = by_id
        self.registry = Registry().with_resources(
            (i, Resource.from_contents(s, default_specification=DRAFT202012)) for i, s in by_id.items()
        )
        self.validators = {"anchor": self.make(by_id[ANCHOR_ID]), "capture": self.make(by_id[CAPTURE_ID])}
        self.roots = {"anchor": ANCHOR_ID, "capture": CAPTURE_ID}

    def make(self, schema: dict) -> Draft202012Validator:
        return Draft202012Validator(schema, registry=self.registry, format_checker=FormatChecker())

    def schema_path(self, root_id: str, parts) -> str:
        """The error's schema path from the contract's root, following the $ref hops jsonschema leaves out, with each
        allOf/anyOf/oneOf member written as `allOf[<title>]` when it has a title (so a path names the rule)."""
        resolver = self.registry.resolver(base_uri=root_id)
        node = self.by_id[root_id]
        parts = list(parts)
        out: list[str] = []
        i = 0
        try:
            while i < len(parts):
                seg = parts[i]
                while isinstance(node, dict) and seg not in node and "$ref" in node:
                    resolved = resolver.lookup(node["$ref"])
                    node, resolver = resolved.contents, resolved.resolver
                if isinstance(node, dict) and seg in {"allOf", "anyOf", "oneOf"} and i + 1 < len(parts):
                    child = node[seg][parts[i + 1]]
                    title = child.get("title") if isinstance(child, dict) else None
                    out.append(f"{seg}[{title}]" if title else f"{seg}/{parts[i + 1]}")
                    node, i = child, i + 2
                    continue
                node = node[seg]
                out.append(str(seg))
                i += 1
        except (KeyError, IndexError, TypeError, Unresolvable):
            return "/".join(map(str, parts)) + " (unresolved)"
        return "/".join(out)

    def errors(self, key: str, document) -> list[dict]:
        """Every schema error of `document` as {keyword, instance_path, schema_path[, property]}, sorted."""
        out = []
        for e in self.validators[key].iter_errors(document):
            item = {"keyword": e.validator, "instance_path": json_pointer(e.absolute_path),
                    "schema_path": self.schema_path(self.roots[key], e.absolute_schema_path)}
            match = (REQUIRED_MESSAGE.match(e.message) if e.validator == "required"
                     else DEPENDENCY_MESSAGE.match(e.message) if e.validator == "dependentRequired" else None)
            if match:
                item["property"] = match.group(1)
            out.append(item)
        return sorted(out, key=lambda d: json.dumps(d, sort_keys=True))


def describe_error(e: dict) -> str:
    missing = f" '{e['property']}'" if "property" in e else ""
    return f"{e['keyword']}{missing} at {e['instance_path'] or '/'} ({e['schema_path']})"


def load_schemas(root: Path) -> dict[str, dict]:
    by_id = {}
    for path in sorted((root / "Contracts/schemas").glob("*.schema.json")):
        schema = json.loads(path.read_text(encoding="utf-8"))
        by_id[schema["$id"]] = schema
    return by_id


# ----------------------------------------------------------------------------------------------- other contracts


class Kinds:
    """The known kinds, read from the schemas so this script cannot drift from them."""

    def __init__(self, by_id: dict[str, dict]) -> None:
        self.capture = set(by_id[CAPTURE_ID]["$defs"]["known_kind"]["enum"])
        self.anchor = set(by_id[ANCHOR_ID]["$defs"]["known_kind"]["enum"])


def writer_profile_violations(kinds: Kinds, capture: dict | None, anchors: list[dict]) -> list[str]:
    """What a v1 writer may emit: only known kinds."""
    out = []
    if capture is not None and capture["kind"] not in kinds.capture:
        out.append(f"capture kind {capture['kind']!r} is not a v1 kind")
    for a in anchors:
        if a.get("kind") not in kinds.anchor:
            out.append(f"anchor kind {a.get('kind')!r} is not a v1 kind")
    return out


def design_package_violations(root: Path, kinds: Kinds) -> tuple[list[str], str]:
    """The capture kinds must be exactly the strings the design package maps onto the capture markers."""
    path = root / "Contracts/design/marginalia.v1.json"
    mapping = json.loads(path.read_text(encoding="utf-8"))["capture_kind_mapping"]
    problems = []
    mapped = mapping["kinds"]
    if set(mapped) != kinds.capture:
        problems.append(f"design package maps kinds {sorted(mapped)}, the capture-envelope schema knows {sorted(kinds.capture)}")
    if sorted(mapped.values()) != sorted(set(mapped.values())) or set(mapped.values()) != {"quote", "note", "audio", "generated", "word"}:
        problems.append(f"design package kind mapping is not one-to-one onto the five capture markers: {mapped}")
    unrecognized = mapping.get("unrecognized", {})
    if unrecognized.get("marker") != "pending" or unrecognized.get("never") != "quote":
        problems.append(f"design package does not render an unknown kind as Pending (never Quote): {unrecognized}")
    if mapping.get("matching") != "exact, case-sensitive":
        problems.append(f"design package kind matching is {mapping.get('matching')!r}, not exact and case-sensitive")
    summary = ", ".join(f"{k} -> {v}" for k, v in sorted(mapped.items(), key=lambda kv: kv[1]))
    return problems, summary


def related_contract_violations(by_id: dict[str, dict]) -> tuple[list[str], str]:
    """A saved answer's endpoint is the context-pack contract's (plan 11.2); a transcript's provider kind is a
    provider-config kind that is not a text-generation endpoint kind."""
    problems = []
    capture = by_id[CAPTURE_ID]["properties"]
    endpoint = capture["generated_answer"]["properties"]["endpoint"]["properties"]
    pack = by_id[CONTEXT_PACK_ID]["properties"]["endpoint"]["properties"]
    for field in ("provider_kind", "classification"):
        if sorted(endpoint[field]["enum"]) != sorted(pack[field]["enum"]):
            problems.append(f"generated_answer.endpoint.{field} is {sorted(endpoint[field]['enum'])}, the context-pack "
                            f"contract's {sorted(pack[field]['enum'])}")
    transcription = set(capture["transcript"]["properties"]["provider_kind"]["enum"])
    configured = set(by_id[PROVIDER_CONFIG_ID]["properties"]["provider_kind"]["enum"])
    generation = set(endpoint["provider_kind"]["enum"])
    if transcription & generation or transcription | generation != configured:
        problems.append(f"provider-config kinds {sorted(configured)} are not exactly the answer endpoint kinds "
                        f"{sorted(generation)} and the transcript kinds {sorted(transcription)}")
    summary = (f"answer endpoint provider kinds and classifications equal the context-pack contract's; provider-config "
               f"kinds = {len(generation)} text-generation + {len(transcription)} transcription")
    secret = by_id[ANCHOR_ID]["$defs"]["not_secret_name"]["not"]["pattern"]
    pack_secret = by_id[CONTEXT_PACK_ID]["$defs"]["notSecretName"]["not"]["pattern"]
    try:
        derived = without_case_flag(pack_secret)
    except ValueError as exc:
        problems.append(f"the context-pack secret-name pattern cannot be written without (?i): {exc}")
    else:
        if derived != secret:
            problems.append("anchor.v1 $defs/not_secret_name is not the context-pack secret-name pattern written "
                            "without (?i)")
        else:
            summary += "; the secret-name pattern is the context-pack one written without (?i)"
    return problems, summary


# ----------------------------------------------------------------------------------------------- pattern portability

ECMA_SYNTAX_CHARACTERS = frozenset("^$\\.*+?()[]{}|")
ECMA_CONTROL_ESCAPES = {"f": 0x0C, "n": 0x0A, "r": 0x0D, "t": 0x09, "v": 0x0B}
HEX_DIGITS = frozenset("0123456789abcdefABCDEF")
QUANTIFIER_BRACES = re.compile(r"\{([0-9]+)(,([0-9]*))?\}")
GROUP_NAME = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*>")
# Patterns in other owners' contracts that are not ECMA-262, each with the change requested of its owner
# (Docs/Stage0/M0-contracts.md, shared changes). A new non-portable pattern fails the check, and so does a recorded
# one that has been fixed (remove its entry then).
KNOWN_NON_PORTABLE_PATTERNS = {
    "schemas/context-pack.v1.schema.json#/$defs/notSecretName/not/pattern":
        "(?i) is not ECMA-262; requested of M5: the form anchor.v1 $defs/not_secret_name uses",
    "schemas/provider-config.v1.schema.json#/$defs/notSecretName/not/pattern":
        "(?i) is not ECMA-262; requested of M5: the same names written out letter by letter",
}


class EcmaPatternError(ValueError):
    pass


class EcmaPattern:
    """Checks that a string is an ECMA-262 Pattern under the `u` flag: the ES2024 grammar (section 22.2.1) and its
    early errors. JSON Schema 2020-12 asks a `pattern` to be a valid ECMA-262 regular expression, and JavaScript
    validators such as Ajv compile it with the `u` flag; Python's `re`, which this repository's validators use, accepts
    constructs ECMA-262 refuses, such as an inline `(?i)`. Where these contracts need nothing more the check is
    stricter than the standard and says so: a Unicode property escape (`\\p{...}`), a modifier group (`(?i:...)`,
    ES2025), a repeated group name and a group name that is not an ASCII identifier are refused as unsupported here.
    Agreement with a JavaScript engine is shown by Docs/Stage0/evidence/M0-contracts/commands/check-patterns.js."""

    def __init__(self, source: str) -> None:
        self.s = source
        self.i = 0
        self.capturing = 0
        self.group_names: set[str] = set()
        self.backreferences: list[int] = []
        self.named_references: list[str] = []

    def check(self) -> None:
        self.disjunction()
        if self.i < len(self.s):
            self.fail("unmatched ')'" if self.s[self.i] == ")" else f"unexpected {self.s[self.i]!r}")
        for n in self.backreferences:
            if n > self.capturing:
                self.fail(f"backreference \\{n} to a group that does not exist")
        for name in self.named_references:
            if name not in self.group_names:
                self.fail(f"\\k<{name}> names no group")

    def fail(self, message: str):
        raise EcmaPatternError(f"{message} (offset {self.i})")

    def peek(self, k: int = 0) -> str | None:
        j = self.i + k
        return self.s[j] if j < len(self.s) else None

    def at(self, text: str) -> bool:
        return self.s.startswith(text, self.i)

    def expect(self, ch: str) -> None:
        if self.peek() != ch:
            self.fail(f"expected {ch!r}")
        self.i += 1

    def disjunction(self) -> None:
        self.alternative()
        while self.peek() == "|":
            self.i += 1
            self.alternative()

    def alternative(self) -> None:
        while self.peek() is not None and self.peek() not in "|)":
            self.term()

    def term(self) -> None:
        c = self.peek()
        if c in ("^", "$"):
            self.i += 1
            self.no_quantifier()
        elif c == "\\" and self.peek(1) in ("b", "B"):
            self.i += 2
            self.no_quantifier()
        elif self.at("(?=") or self.at("(?!") or self.at("(?<=") or self.at("(?<!"):
            self.i += 3 if self.at("(?=") or self.at("(?!") else 4
            self.disjunction()
            self.expect(")")
            self.no_quantifier()  # with the u flag no assertion is quantifiable (Annex B allows a lookahead without it)
        else:
            self.atom()
            self.quantifier()

    def no_quantifier(self) -> None:
        if self.peek() is not None and self.peek() in "*+?{":
            self.fail("nothing to repeat")

    def quantifier(self) -> None:
        c = self.peek()
        if c is not None and c in "*+?":
            self.i += 1
        elif c == "{":
            m = QUANTIFIER_BRACES.match(self.s, self.i)
            if not m:
                self.fail("'{' that is not a quantifier (the u flag has no literal brace)")
            if m.group(3) and int(m.group(3)) < int(m.group(1)):
                self.fail("quantifier range out of order")
            self.i = m.end()
        else:
            return
        if self.peek() == "?":
            self.i += 1

    def atom(self) -> None:
        c = self.peek()
        if c == ".":
            self.i += 1
        elif c == "\\":
            self.i += 1
            self.atom_escape()
        elif c == "[":
            self.character_class()
        elif c == "(":
            if self.at("(?:"):
                self.i += 3
            elif self.at("(?<"):
                self.i += 3
                name = self.group_name()
                if name in self.group_names:
                    self.fail(f"repeated group name {name!r} (unsupported here)")
                self.group_names.add(name)
                self.capturing += 1
            elif self.at("(?"):
                self.fail("'(?' followed by none of ':', '=', '!', '<=', '<!' or '<name>' (an inline flag such as "
                          "(?i) is not ECMA-262; a modifier group is unsupported here)")
            else:
                self.i += 1
                self.capturing += 1
            self.disjunction()
            self.expect(")")
        elif c in ECMA_SYNTAX_CHARACTERS:
            self.fail("nothing to repeat" if c in "*+?" else f"lone {c!r} (not a pattern character with the u flag)")
        else:
            self.i += 1

    def group_name(self) -> str:
        m = GROUP_NAME.match(self.s, self.i)
        if not m:
            self.fail("a group name that is not an ASCII identifier (unsupported here)")
        self.i = m.end()
        return m.group()[:-1]

    def atom_escape(self) -> None:
        c = self.peek()
        if c is None:
            self.fail("'\\' at the end")
        if c in "123456789":
            start = self.i
            while self.peek() is not None and self.peek() in "0123456789":
                self.i += 1
            self.backreferences.append(int(self.s[start:self.i]))
        elif c == "k":
            self.i += 1
            if self.peek() != "<":
                self.fail("\\k without a group name")
            self.i += 1
            self.named_references.append(self.group_name())
        elif c in "dDsSwW":
            self.i += 1
        elif c in "pP":
            self.fail("a Unicode property escape (unsupported here)")
        else:
            self.character_escape()

    def character_escape(self) -> int:
        """The code point of a CharacterEscape (the backslash is already consumed)."""
        c = self.peek()
        if c is None:
            self.fail("'\\' at the end")
        if c in ECMA_CONTROL_ESCAPES:
            self.i += 1
            return ECMA_CONTROL_ESCAPES[c]
        if c == "c":
            letter = self.peek(1)
            if letter is None or not ("a" <= letter <= "z" or "A" <= letter <= "Z"):
                self.fail("\\c without an ASCII letter")
            self.i += 2
            return ord(letter) % 32
        if c == "0":
            self.i += 1
            if self.peek() is not None and self.peek() in "0123456789":
                self.fail("\\0 followed by a digit")
            return 0
        if c == "x":
            digits = self.s[self.i + 1:self.i + 3]
            if len(digits) != 2 or not set(digits) <= HEX_DIGITS:
                self.fail("\\x without two hex digits")
            self.i += 3
            return int(digits, 16)
        if c == "u":
            return self.unicode_escape()
        if c in ECMA_SYNTAX_CHARACTERS or c == "/":
            self.i += 1
            return ord(c)
        self.fail(f"\\{c} (with the u flag only a syntax character or '/' may follow a backslash)")

    def unicode_escape(self) -> int:
        if self.peek(1) == "{":
            m = re.compile(r"\{([0-9A-Fa-f]+)\}").match(self.s, self.i + 1)
            if not m or int(m.group(1), 16) > 0x10FFFF:
                self.fail("\\u{...} that is not a code point")
            self.i = m.end()
            return int(m.group(1), 16)
        digits = self.s[self.i + 1:self.i + 5]
        if len(digits) != 4 or not set(digits) <= HEX_DIGITS:
            self.fail("\\u without four hex digits")
        self.i += 5
        value = int(digits, 16)
        trail = self.s[self.i + 2:self.i + 6] if self.at("\\u") else ""
        if 0xD800 <= value <= 0xDBFF and len(trail) == 4 and set(trail) <= HEX_DIGITS and 0xDC00 <= int(trail, 16) <= 0xDFFF:
            self.i += 6  # with the u flag an escaped surrogate pair is one code point
            return 0x10000 + ((value - 0xD800) << 10) + (int(trail, 16) - 0xDC00)
        return value

    def character_class(self) -> None:
        self.i += 1
        if self.peek() == "^":
            self.i += 1
        while True:
            c = self.peek()
            if c is None:
                self.fail("unterminated character class")
            if c == "]":
                self.i += 1
                return
            low = self.class_atom()
            if self.peek() == "-" and self.peek(1) not in (None, "]"):
                self.i += 1
                high = self.class_atom()
                if low is None or high is None:
                    self.fail("a class escape such as \\d at the end of a range")
                if low > high:
                    self.fail("character class range out of order")

    def class_atom(self) -> int | None:
        """A class atom's code point, or None for a class escape such as \\d."""
        c = self.peek()
        self.i += 1
        if c != "\\":
            return ord(c)
        e = self.peek()
        if e is None:
            self.fail("'\\' at the end")
        if e == "b":
            self.i += 1
            return 0x08
        if e == "-":
            self.i += 1
            return ord("-")
        if e in "dDsSwW":
            self.i += 1
            return None
        if e in "pP":
            self.fail("a Unicode property escape (unsupported here)")
        if e in "123456789":
            self.fail("a decimal escape in a character class")
        return self.character_escape()


def ecma262_problem(pattern: str) -> str | None:
    """None when `pattern` compiles in Python's `re` and as an ECMA-262 Pattern with the u flag, else why not."""
    try:
        re.compile(pattern)
    except re.error as exc:
        return f"not a Python regular expression: {exc}"
    try:
        EcmaPattern(pattern).check()
    except EcmaPatternError as exc:
        return f"not ECMA-262 with the u flag: {exc}"
    return None


def contract_patterns(node, where: str):
    """Every regular expression in a contract document: `pattern` keyword values and `patternProperties` names, as
    (JSON Pointer, pattern). Example and literal values are skipped; a property named `pattern` has a schema, not a
    string, as its value, so it is never taken for the keyword."""
    if isinstance(node, dict):
        for key, value in node.items():
            here = f"{where}/{str(key).replace('~', '~0').replace('/', '~1')}"
            if key == "pattern" and isinstance(value, str):
                yield here, value
            elif key == "patternProperties" and isinstance(value, dict):
                for name, sub in value.items():
                    sub_where = f"{here}/{name.replace('~', '~0').replace('/', '~1')}"
                    yield sub_where + " (name)", name
                    yield from contract_patterns(sub, sub_where)
            elif key not in {"examples", "example", "default", "const", "enum", "description", "title"}:
                yield from contract_patterns(value, here)
    elif isinstance(node, list):
        for i, item in enumerate(node):
            yield from contract_patterns(item, f"{where}/{i}")


def pattern_portability_violations(root: Path) -> tuple[list[str], str]:
    """Every pattern in every contract schema and OpenAPI document compiles in Python and as ECMA-262 with the u flag,
    except the recorded ones (KNOWN_NON_PORTABLE_PATTERNS)."""
    import yaml  # the contract tooling's PyYAML (Scripts/tools/requirements.txt)

    documents = [(p, json.loads(p.read_text(encoding="utf-8"))) for p in sorted((root / "Contracts/schemas").glob("*.json"))]
    documents += [(p, yaml.safe_load(p.read_text(encoding="utf-8")))
                  for p in sorted((root / "Contracts/openapi").glob("*")) if p.suffix in {".yaml", ".yml", ".json"}]
    problems, seen_known, total = [], set(), 0
    for path, document in documents:
        for pointer, pattern in contract_patterns(document, ""):
            total += 1
            key = f"{path.relative_to(root / 'Contracts').as_posix()}#{pointer}"
            problem = ecma262_problem(pattern)
            if problem is None:
                continue
            if key in KNOWN_NON_PORTABLE_PATTERNS:
                seen_known.add(key)
            else:
                problems.append(f"pattern {key}: {problem}")
    for key in sorted(set(KNOWN_NON_PORTABLE_PATTERNS) - seen_known):
        problems.append(f"pattern {key}: recorded as not portable but now compiles everywhere (remove its entry)")
    summary = (f"{total} patterns in {len(documents)} contract documents compile in Python and as ECMA-262 with the u "
               f"flag, except {len(seen_known)} recorded in other owners' contracts "
               f"({'; '.join(f'{k}: {v}' for k, v in sorted(KNOWN_NON_PORTABLE_PATTERNS.items()) if k in seen_known)})")
    return problems, summary


_CASE_CANDIDATES: list[str] = []


def case_class(letter: str) -> str:
    """Every character Python's case-insensitive match accepts for an ASCII letter, as a character class: the ASCII
    pair first, then the others by code point (for i: U+0130 and U+0131; for k: U+212A; for s: U+017F)."""
    if not _CASE_CANDIDATES:
        # Characters whose lowercase, uppercase or case-folded form begins with an ASCII letter. For every ASCII
        # letter, matching every code point against "(?i)<letter>" finds exactly the same members, more slowly
        # (Docs/Stage0/evidence/M0-contracts/commands/check-case-classes.py, run by the clean run).
        for cp in range(0x110000):
            if 0xD800 <= cp <= 0xDFFF:
                continue
            ch = chr(cp)
            if any(f[:1].isascii() and f[:1].isalpha() for f in (ch.lower(), ch.upper(), ch.casefold())):
                _CASE_CANDIDATES.append(ch)
    rx = re.compile("(?i)" + re.escape(letter))
    members = [c for c in _CASE_CANDIDATES if rx.fullmatch(c)]
    ascii_part = sorted((m for m in members if m.isascii()), key=lambda m: (m.islower(), m))
    return "[" + "".join(ascii_part + sorted(m for m in members if not m.isascii())) + "]"


def without_case_flag(pattern: str) -> str:
    """A `(?i)` pattern written without the flag, each ASCII letter replaced by its case class. Only the form the
    secret-name pattern has is supported: no escape, and no letter inside a character class."""
    if not pattern.startswith("(?i)"):
        return pattern
    body, out, in_class = pattern[len("(?i)"):], [], False
    if "\\" in body:
        raise ValueError("an escape in a (?i) pattern")
    for ch in body:
        if ch == "[":
            in_class = True
        elif ch == "]":
            in_class = False
        if ch.isascii() and ch.isalpha():
            if in_class:
                raise ValueError("a letter inside a character class")
            out.append(case_class(ch))
        else:
            out.append(ch)
    return "".join(out)


# ----------------------------------------------------------------------------------------------- adapters


class Adaptations:
    """Counts every change made to spike output before validation, by kind of change."""

    def __init__(self) -> None:
        self.counts: Counter[str] = Counter()

    def note(self, what: str, n: int = 1) -> None:
        self.counts[what] += n


def fixture_uuid(label: str) -> str:
    return str(uuid.uuid5(FIXTURE_NAMESPACE, f"urn:sylvia:fixture:{label}"))


def ms_to_rfc3339(ms: int) -> str:
    t = dt.datetime.fromtimestamp(ms / 1000, tz=dt.timezone.utc)
    return t.strftime("%Y-%m-%dT%H:%M:%S.") + f"{ms % 1000:03d}Z"


def rename(obj: dict, old: str, new: str, log: Adaptations, what: str) -> None:
    if old in obj:
        obj[new] = obj.pop(old)
        log.note(what)


def adapt_epub_anchor(raw: dict, work_id: str, edition_id: str, log: Adaptations) -> dict:
    a = copy.deepcopy(raw)
    rename(a, "version", "schema_version", log, "epub: version renamed schema_version")
    rename(a, "asset_digest", "asset_sha256", log, "epub: asset_digest renamed asset_sha256")
    for key in [k for k, v in a.items() if v is None]:
        del a[key]
        log.note("epub: null field omitted")
    if isinstance(a.get("asset_id"), str) and not UUID_RE.match(a["asset_id"]):
        a["asset_id"] = fixture_uuid(a["asset_id"])
        log.note("epub: fixture label asset_id replaced by a UUID (spike has no asset IDs)")
    a["work_id"], a["edition_id"] = work_id, edition_id
    log.note("epub: work_id and edition_id supplied (spike records neither)")
    return a


def adapt_pdf_anchor(raw: dict, work_id: str, edition_id: str, log: Adaptations) -> dict:
    a = copy.deepcopy(raw)
    rename(a, "version", "schema_version", log, "pdf: version renamed schema_version")
    for s in a["segments"]:
        if "page_label" in s and s["page_label"] is None:
            del s["page_label"]
            log.note("pdf: null page_label omitted (no printed label)")
    if "reader_locator" in a:
        locator = a.pop("reader_locator")
        adapter = locator.pop("adapter")
        a["reader"] = {"adapter": adapter, "locator": locator}
        log.note("pdf: reader_locator restructured as reader {adapter, locator}")
    a["work_id"], a["edition_id"] = work_id, edition_id
    log.note("pdf: work_id and edition_id supplied (spike records neither)")
    return a


def envelope_for_text_anchors(name: str, anchors: list[dict], quoted_text: str, source_kind: str,
                              location_label: str | None, log: Adaptations, work_id: str, edition_id: str) -> dict:
    env = {
        "schema_version": 1,
        "capture_id": fixture_uuid(f"{name}/capture"),
        "work_id": work_id,
        "edition_id": edition_id,
        "kind": "text_quote",
        "quoted_text": quoted_text,
        "quoted_text_origin": "selection",
        "source_snapshot": {"title": name, "author_display": "", "source_kind": source_kind},
        "anchors": anchors,
        "notes": [],
        "provenance": {"surface": "reader", "idempotency_key": f"spike:{name}"},
        "created_at": "2026-10-13T00:00:00Z",
        "updated_at": "2026-10-13T00:00:00Z",
        "revision": 1,
    }
    if location_label:
        env["source_snapshot"]["location_label"] = location_label
        env["source_snapshot"]["location_label_origin"] = "app"
    log.note("envelope wrapper supplied around spike anchors (kind text_quote, ids, snapshot, provenance, times, revision)")
    return env


def epub_cases(root: Path, log: Adaptations) -> list[tuple[str, dict | None, list[dict]]]:
    cases = []
    base = root / "Docs/Stage0/evidence/G01-EPUB"
    samples = json.loads((base / "anchor-samples.json").read_text(encoding="utf-8"))["capture_samples"]
    selection = json.loads((base / "selection-samples.json").read_text(encoding="utf-8"))["samples"]
    for source, entries in (("anchor-samples.json", samples),
                            ("selection-samples.json", [s for s in selection if "anchors" in s])):
        for s in entries:
            name = s.get("name") or s.get("case")
            label = s["anchors"][0]["asset_id"]
            work_id, edition_id = fixture_uuid(f"{label}/work"), fixture_uuid(f"{label}/edition")
            anchors = [adapt_epub_anchor(a, work_id, edition_id, log) for a in s["anchors"]]
            title = s["anchors"][0].get("reader", {}).get("locator", {}).get("title")
            env = envelope_for_text_anchors(f"g01-epub/{name}", anchors, s["quoted_text"], "local_epub", title, log,
                                            work_id, edition_id)
            cases.append((f"G0.1 EPUB {source} {name}", env, anchors))
    return cases


def pdf_cases(root: Path, log: Adaptations) -> list[tuple[str, dict | None, list[dict]]]:
    cases = []
    doc = json.loads((root / "Docs/Stage0/evidence/G01-PDF/anchor-samples.json").read_text(encoding="utf-8"))
    for s in doc["samples"]:
        label = s["fixture"]
        work_id, edition_id = fixture_uuid(f"{label}/work"), fixture_uuid(f"{label}/edition")
        anchor = adapt_pdf_anchor(s["anchor"], work_id, edition_id, log)
        label_text = anchor["segments"][0].get("page_label")
        env = envelope_for_text_anchors(f"g01-pdf/{s['name']}", [anchor], s["anchor"]["exact_text"], "local_pdf",
                                        f"Page {label_text}" if label_text else None, log, work_id, edition_id)
        cases.append((f"G0.1 PDF anchor-samples.json {s['name']}", env, [anchor]))

    # Selections composed of several pieces (ComposedSelectionTests, every shape it captures and restores exactly):
    # their exact_text is PDFKit's composition, which rule A3 must accept (M0 final review R1-02).
    composed = json.loads((root / "Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json").read_text(encoding="utf-8"))
    for s in composed["samples"]:
        label = s["fixture"]
        work_id, edition_id = fixture_uuid(f"{label}/work"), fixture_uuid(f"{label}/edition")
        anchor = adapt_pdf_anchor(s["anchor"], work_id, edition_id, log)
        label_text = anchor["segments"][0].get("page_label")
        env = envelope_for_text_anchors(f"g01-pdf/composed/{s['name']}", [anchor], s["anchor"]["exact_text"], "local_pdf",
                                        f"Page {label_text}" if label_text else None, log, work_id, edition_id)
        cases.append((f"G0.1 PDF anchor-composed-samples.json {s['name']}", env, [anchor]))

    # The spike's own capture-envelope example (A.1's shape). Its kind, text_quote, is already the contract's.
    example = copy.deepcopy(doc["capture_envelope_example"])
    example["anchors"] = [adapt_pdf_anchor(a, example["work_id"], example["edition_id"], log) for a in example["anchors"]]
    example["quoted_text_origin"] = "selection"
    example["notes"] = []
    example["provenance"] = {"surface": "reader", "idempotency_key": "spike:g01-pdf/capture_envelope_example"}
    example["updated_at"] = example["created_at"]
    example["source_snapshot"]["location_label_origin"] = "app"
    log.note("pdf example: quoted_text_origin, notes, provenance, updated_at, location_label_origin supplied")
    cases.append(("G0.1 PDF anchor-samples.json capture_envelope_example", example, example["anchors"]))
    return cases


G04_KIND = {"audio": "audio_capture"}  # G0.4 CaptureKind -> envelope kind; any other value passes through unchanged


def g04_surface(origin: str) -> tuple[str, str | None]:
    """G0.4 `CaptureRecord.origin`: "player", or `intent[.<surface>]@<process>` (CaptureMomentIntent.origin)."""
    if origin == "player":
        return "player", None
    if re.fullmatch(r"intent(\.[a-z_]+)?@[A-Za-z0-9.-]+", origin):
        return "quick_capture", origin
    raise AssertionError(f"unknown G0.4 origin {origin!r}")


def g04_preserved_excerpt(name: str, e: dict, ranges: list[dict], file_info: dict, log: Adaptations) -> dict:
    """A G0.4 `ExportedExcerpt` (state `saved`) in the envelope's form."""
    requested = [{"asset_id": x["assetID"].lower(), "start_ms": x["startMs"], "end_ms": x["endMs"]}
                 for x in e["requestedRanges"]]
    if requested != [{k: r[k] for k in ("asset_id", "start_ms", "end_ms")} for r in ranges]:
        raise AssertionError(f"{name}: requestedRanges differ from the record's ranges")
    if file_info["byte_count"] != e["byteCount"]:
        raise AssertionError(f"{name}: byteCount {e['byteCount']} differs from the file ({file_info['byte_count']})")
    if float(e["sampleRate"]) != int(e["sampleRate"]):
        raise AssertionError(f"{name}: sample rate {e['sampleRate']} is not a whole number of hertz")
    actual, clip = [], 0
    for x, source_format in zip(e["actualRanges"], e["sourceFormats"], strict=True):
        actual.append({"asset_id": x["assetID"].lower(), "start_ms": x["startMs"], "end_ms": x["endMs"],
                       "clip_start_ms": clip, "source_format": source_format})
        clip += x["endMs"] - x["startMs"]
    log.note("g04: clip_start_ms supplied: the actual ranges back to back, as AACExcerptExporter writes them "
             "(spike records none)")
    excerpt = {
        "state": "preserved",
        "blob_sha256": file_info["sha256"],
        "file_extension": e["fileName"].rsplit(".", 1)[1],
        "media_type": "audio/mp4",
        "byte_count": e["byteCount"],
        "format": e["format"],
        "sample_rate_hz": int(e["sampleRate"]),
        "frame_count": e["frameCount"],
        "actual_ranges": actual,
    }
    if e.get("outputDurationMs") is not None:
        excerpt["duration_ms"] = e["outputDurationMs"]  # absent when AVFoundation could not read it back
    log.note("g04: excerpt state saved renamed preserved")
    log.note("g04: excerpt blob_sha256 supplied from the excerpt file's bytes (spike records none)")
    log.note("g04: excerpt media_type audio/mp4 supplied from its m4a format")
    return excerpt


def g04_cases(root: Path, log: Adaptations) -> tuple[list[tuple[str, dict | None, list[dict]]], list[str]]:
    base = root / "Docs/Stage0/evidence/M0-contracts/g04-capture-records"
    context = json.loads((base / "context.json").read_text(encoding="utf-8"))
    members = {m["asset_id"].lower(): m for m in context["members"]}
    excerpts = {e["capture_id"].lower(): e for e in context["excerpt_files"]}
    writes = {k.lower(): v for k, v in context["durable_writes"].items()}
    work_id = fixture_uuid("g04-audio/multi/work")
    cases, skipped = [], []
    for path in sorted((base / "records").glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        name = f"G0.4 record {raw['idempotencyKey']} ({path.name})"
        if raw["kind"] == "bookmark":
            skipped.append(f"{name}: a bookmark is a position only, not a capture in the envelope (ADR-0016)")
            continue
        for forbidden in ("quotedText", "quoted_text", "transcript", "text"):
            if forbidden in raw:
                raise AssertionError(f"{name}: the spike record unexpectedly carries {forbidden}")
        capture_id = raw["id"].lower()
        edition_id = raw["editionID"].lower()
        log.note("g04: UUIDs lowercased (Swift uuidString is uppercase)")
        kind = G04_KIND.get(raw["kind"], raw["kind"])
        if kind != raw["kind"]:
            log.note(f"g04: kind {raw['kind']} renamed {kind} (the design package's kind for the Audio marker)")
        ranges = []
        for r in raw["ranges"]:
            asset = r["assetID"].lower()
            ranges.append({"asset_id": asset, "asset_sha256": members[asset]["sha256"],
                           "start_ms": r["startMs"], "end_ms": r["endMs"]})
            log.note("g04: range asset_sha256 supplied from the member file's bytes (spike records no digest)")
        anchor = {"schema_version": 1, "kind": "audio", "work_id": work_id, "edition_id": edition_id,
                  "timeline_revision": raw["timelineRevision"], "ranges": ranges}
        log.note("g04: work_id supplied (spike records none)")
        state = next(iter(raw["excerpt"]))
        body = raw["excerpt"][state]
        if state == "pending":
            excerpt = {"state": "pending"}
        elif state == "failed":
            excerpt = {"state": "failed", "failure": {"reason": body["reason"], "attempts": body["attempts"]}}
        elif state == "saved":
            excerpt = g04_preserved_excerpt(name, body["_0"], ranges, excerpts[capture_id], log)
        else:
            raise AssertionError(f"{name}: unknown excerpt state {state}")
        notes = []
        if raw.get("note") is not None:
            notes = [{"note_id": fixture_uuid(f"{capture_id}/note"), "current_revision": 1,
                      "revisions": [{"revision": 1, "body": raw["note"], "format": "plain",
                                     "saved_at": ms_to_rfc3339(raw["createdAtMs"])}]}]
            log.note("g04: single note string wrapped as note revision 1 (spike keeps one string, saved with the capture)")
        surface, entry_point = g04_surface(raw["origin"])
        provenance = {"surface": surface, "idempotency_key": raw["idempotencyKey"]}
        if entry_point:
            provenance["entry_point"] = entry_point
        log.note("g04: origin mapped to provenance surface (and entry_point for a quick-capture intent)")
        env = {
            "schema_version": 1, "capture_id": capture_id, "work_id": work_id, "edition_id": edition_id,
            "kind": kind,
            "source_snapshot": {"title": "Meditations", "author_display": "Marcus Aurelius", "source_kind": "local_audio"},
            "anchors": [anchor], "notes": notes, "retained_excerpt": excerpt, "provenance": provenance,
            "created_at": ms_to_rfc3339(raw["createdAtMs"]), "updated_at": ms_to_rfc3339(raw["updatedAtMs"]),
            "revision": writes[capture_id],
        }
        log.note("g04: source_snapshot supplied (spike records none)")
        log.note("g04: revision supplied: the durable writes the probe counted for the record (spike has no revision)")
        cases.append((name, env, [anchor]))
    return cases, skipped


# ----------------------------------------------------------------------------------------------- G0.5 recovery

RECOVERY_LIBRARY = "Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite"
RECOVERY_KIND = {"quote": "text_quote", "note": "note", "audio": "audio_capture", "generated": "generated_answer", "word": "word"}
# How the persistence spike (G0.5 recovery) stores captures differently from the envelope. ADR-0016 section 8 records
# each with its reason; recovery_checks observes them in the committed library's rows and table definitions.
RECOVERY_DEVIATIONS = {
    "kind-names": "capture.kind is quote, audio or generated where the envelope and the design package use text_quote, "
                  "audio_capture and generated_answer",
    "manual-anchor": "a typed page of a printed book is an anchor row of kind 'manual', {\"page\": 112, \"manual\": true} "
                     "(envelope: no anchor; source_snapshot.location_label with origin user)",
    "audio-no-text": "CHECK (kind <> 'audio' OR quoted_text IS NULL) refuses quoted text on every audio capture "
                     "(envelope: a labelled transcript or the user's typing may supply it, plan A.1, 10.4)",
    "note-origins": "note_revision.origin allows transcript_correction and ai_derived (envelope notes are the user's "
                    "words; a correction is transcript.corrected_text, an answer a generated_answer capture)",
    "no-quote-origin": "no column records where quoted text came from (envelope: quoted_text_origin, plan 11.1)",
    "no-location-origin": "no column records who supplied the location label (envelope: location_label_origin, "
                          "addendum 4.3)",
    "no-surface": "no column records the capture surface (envelope: provenance.surface)",
    "anchor-edition-nullable": "capture_anchor.edition_id may be NULL (envelope: every anchor of a known kind names "
                               "its edition)",
    "anchor-asset-nullable": "capture_anchor.asset_id and asset_sha256 may be NULL for every kind except audio "
                             "(envelope: every anchor of a known kind names its asset and digest)",
    "epub-text-as-digest": "an EPUB locator keeps the selected text only as exact_text_sha256 (it equals the SHA-256 "
                           "of the capture's quoted_text; envelope: exact_text)",
    "epub-text-missing": "an EPUB locator with neither the selected text nor its digest (the word capture)",
    "epub-context-missing": "an EPUB locator without prefix and suffix (the word capture)",
    "epub-media-type-opaque": "the EPUB resource's media type is only inside the opaque adapter_payload (Readium's "
                              "type; envelope: resource_media_type)",
    "epub-media-type-missing": "an EPUB anchor with no media type at all (the word capture)",
    "epub-offsets-without-block": "EPUB start and end in unicode_scalar with no block_index or extraction_version "
                                  "(envelope: text_offsets names both)",
    "epub-reader-unnamed": "Readium's locator is kept in adapter_payload without the adapter's name or version "
                           "(envelope: reader.adapter, reader.adapter_version)",
    "epub-reader-missing": "an EPUB anchor without a reader locator (the word capture)",
    "pdf-reduced": "a PDF locator is {page_index, page_label, rotation, rects, text_range}: no exact_text, extraction, "
                   "page box, segment text, prefix, suffix, page text digest or reader locator",
    "pdf-range-length": "the PDF anchor's text_range [880, 939] covers 59 scalars for a 60-scalar quotation (an "
                        "inclusive end, or an off-by-one; envelope ranges are half-open)",
    "audio-member-sequence": "an audio anchor row's locator keeps member_sequence, the member's position at capture "
                             "time (envelope: no member order in an anchor, so a reorder never rewrites a capture)",
    "excerpt-no-timing": "retained_excerpt has clip_duration_ms only: no format, sample rate, frame count, actual "
                         "ranges or clip offsets (plan 7.2, 10.2)",
    "excerpt-ranges-by-digest": "retained_excerpt.source_ranges_json names each range by asset digest only, without "
                                "its asset ID",
    "excerpt-file-every-state": "retained_excerpt requires blob_sha256, byte_count, media_type and file_extension in "
                                "every export_state, pending and failed included (envelope: only a preserved or "
                                "removed excerpt names a file)",
    "excerpt-not-unique": "nothing makes retained_excerpt.capture_id unique, so a capture can have several excerpt rows "
                          "(envelope: one retained_excerpt per capture)",
    "excerpt-duration-zero": "clip_duration_ms may be 0 (envelope: duration_ms is at least 1)",
    "excerpt-no-removed": "export_state has no state for an excerpt the user removed (envelope: removed, plan 17.2)",
    "revision-excludes-excerpt": "capture.revision stays 1 when the capture's excerpt row is preserved (envelope: the "
                                 "excerpt's changes count, rule C8)",
    "word-no-entry": "a word capture has no vocabulary entry (headword, source sentence) in the capture tables",
    "quoted-text-allowed-on-note-and-generated": "the capture CHECKs refuse quoted_text only on audio captures, so a "
                                                 "note or a generated capture may hold it (envelope: never)",
    "word-text-optional": "no CHECK requires quoted_text on a word capture (envelope: a word always has it, by "
                          "selection)",
    "generated-not-linked": "no column links a generated capture to its conversation, answering message or context "
                            "pack (envelope: generated_answer.conversation_id, message_id and context_pack_id)",
    "answer-state-no-cancelled": "message.state has no cancelled state (envelope: answer_state complete, interrupted "
                                 "or cancelled, from G0.5 AI's AskState)",
    "audio-no-transcript": "no table or column keeps a transcript of an audio capture's excerpt: raw text, segments, "
                           "provider, model, correction (envelope: transcript, plan 10.4)",
    "excerpt-failure-unrecorded": "a failed export keeps neither its reason nor its number of attempts (envelope: "
                                  "failure {reason, attempts})",
    "id-case-unchecked": "the capture and note ID columns check only length(id) = 36, so an uppercase UUID (Swift's "
                         "uuidString) is accepted (envelope: lowercase)",
    "note-without-capture": "a note on a whole work is a note row without a capture (envelope: a note capture with no "
                            "anchors, holding that note)",
    "note-on-conversation": "a note attached to an AI conversation (note.conversation_id) has no form in the v1 "
                            "envelope (open item for M1 and M5)",
}
# The PDF anchor fields the recovery locator does not have (deviation pdf-reduced), checked exactly.
RECOVERY_PDF_MISSING = {"exact_text", "extraction", "reader", "segments/0/page_box", "segments/0/text",
                        "segments/0/prefix", "segments/0/suffix", "segments/0/page_text_sha256"}
PLACEHOLDER = "(not stored by G0.5 recovery)"


def table_info(db: sqlite3.Connection, table: str) -> dict[str, dict]:
    return {r["name"]: dict(r) for r in db.execute(f"PRAGMA table_info({table})")}


def check_values(sql: str, column: str) -> set[str]:
    """The values of a `column IN ('a', 'b')` CHECK in a table's SQL."""
    match = re.search(rf"\b{column}\s+IN\s*\(([^)]*)\)", sql)
    return set(re.findall(r"'([^']*)'", match.group(1))) if match else set()


def recovery_table_deviations(db: sqlite3.Connection) -> dict[str, str]:
    """Deviations visible in the table definitions, with where they were seen."""
    sql = {r["name"]: r["sql"] for r in db.execute("SELECT name, sql FROM sqlite_master WHERE type = 'table'")}
    seen: dict[str, str] = {}
    kinds = check_values(sql["capture"], "kind")
    if kinds & {"quote", "audio", "generated"}:
        seen["kind-names"] = f"capture.kind CHECK {sorted(kinds)}"
    if re.search(r"kind\s*<>\s*'audio'\s+OR\s+quoted_text\s+IS\s+NULL", sql["capture"]):
        seen["audio-no-text"] = "capture CHECK"
    origins = check_values(sql["note_revision"], "origin")
    if origins - {"user"}:
        seen["note-origins"] = f"note_revision.origin CHECK {sorted(origins)}"
    for name in ("quoted_text_origin", "location_label_origin", "surface"):
        for table in ("capture", "capture_anchor"):
            if name in table_info(db, table):
                break
        else:
            key = {"quoted_text_origin": "no-quote-origin", "location_label_origin": "no-location-origin",
                   "surface": "no-surface"}[name]
            seen[key] = f"no {name} column"
    anchor_cols = table_info(db, "capture_anchor")
    if not anchor_cols["edition_id"]["notnull"]:
        seen["anchor-edition-nullable"] = "capture_anchor.edition_id NULL allowed"
    if not anchor_cols["asset_id"]["notnull"] and not anchor_cols["asset_sha256"]["notnull"]:
        seen["anchor-asset-nullable"] = "capture_anchor.asset_id, asset_sha256 NULL allowed"
    excerpt_cols = table_info(db, "retained_excerpt")
    states = check_values(sql["retained_excerpt"], "export_state")
    if states & {"pending", "failed"} and all(excerpt_cols[c]["notnull"] for c in
                                              ("blob_sha256", "byte_count", "media_type", "file_extension")):
        seen["excerpt-file-every-state"] = f"NOT NULL file columns, export_state {sorted(states)}"
    if "removed" not in states:
        seen["excerpt-no-removed"] = f"export_state CHECK {sorted(states)}"
    if re.search(r"clip_duration_ms\s*>=\s*0", sql["retained_excerpt"]):
        seen["excerpt-duration-zero"] = "CHECK (clip_duration_ms >= 0)"
    unique_on_capture = False
    for index in db.execute("PRAGMA index_list(retained_excerpt)"):
        columns = [r["name"] for r in db.execute(f"PRAGMA index_info({index['name']})")]
        unique_on_capture |= bool(index["unique"]) and columns == ["capture_id"]
    if not unique_on_capture:
        seen["excerpt-not-unique"] = "no unique index on retained_excerpt.capture_id"
    for name in ("format", "sample_rate_hz", "frame_count", "actual_ranges_json"):
        if name in excerpt_cols:
            break
    else:
        seen["excerpt-no-timing"] = "retained_excerpt has no timing columns"
    # Which kinds the capture CHECKs require (IS NOT NULL) or refuse (IS NULL) quoted text on. The envelope requires
    # it on a text_quote (quote) and a word, and refuses it on a note and a generated answer.
    text_rules = dict(re.findall(r"CHECK\s*\(\s*kind\s*<>\s*'(\w+)'\s+OR\s+quoted_text\s+IS\s+(NOT\s+NULL|NULL)\s*\)",
                                 sql["capture"]))
    allowed = [k for k in ("note", "generated") if text_rules.get(k) != "NULL"]
    if allowed:
        seen["quoted-text-allowed-on-note-and-generated"] = (f"capture CHECKs on quoted_text: {text_rules}; no CHECK "
                                                              f"refuses it on {allowed}")
    if not re.fullmatch(r"NOT\s+NULL", text_rules.get("word", "")):
        seen["word-text-optional"] = f"capture CHECKs on quoted_text: {text_rules}; none for word"
    capture_cols = table_info(db, "capture")
    links = sorted({"conversation_id", "message_id", "context_pack_id"} & set(capture_cols))
    back = sorted(t for t in ("message", "context_pack") if "capture_id" in table_info(db, t))
    if not links and not back:
        seen["generated-not-linked"] = "capture has no conversation_id, message_id or context_pack_id; message and " \
                                       "context_pack have no capture_id"
    states = check_values(sql["message"], "state")
    if "cancelled" not in states:
        seen["answer-state-no-cancelled"] = f"message.state CHECK {sorted(states)}"
    transcript_like = sorted(f"{t}.{c}" for t in sql for c in table_info(db, t) if "transcript" in c or c == "raw_text")
    if not transcript_like and not [t for t in sql if "transcript" in t]:
        seen["audio-no-transcript"] = "no transcript table and no transcript or raw_text column"
    if not any(re.search(r"reason|attempt|fail|error", c) for c in excerpt_cols):
        seen["excerpt-failure-unrecorded"] = "retained_excerpt has no reason or attempts column"
    unchecked_ids = [t for t in ("capture", "note")
                     if re.search(r"\bid\s+TEXT\s+PRIMARY\s+KEY\s+NOT\s+NULL\s+CHECK\s*\(\s*length\(id\)\s*=\s*36\s*\)\s*,",
                                  sql[t]) and not re.search(r"lower\(id\)|id\s+NOT\s+GLOB|id\s+GLOB", sql[t])]
    if unchecked_ids:
        seen["id-case-unchecked"] = f"{', '.join(f'{t}.id' for t in unchecked_ids)} CHECK only length(id) = 36"
    return seen


def recovery_envelope(db: sqlite3.Connection, row: sqlite3.Row, seen: dict[str, set[str]], log: Adaptations,
                      skip_rules: set[str]) -> dict:
    """One recovery capture row as an envelope; placeholders are named by the deviation they stand for."""
    name = row["idempotency_key"]

    def deviation(key: str) -> None:
        seen.setdefault(key, set()).add(name)

    kind = RECOVERY_KIND.get(row["kind"])
    if kind is None:
        raise AssertionError(f"{name}: kind {row['kind']!r} has no envelope kind")
    if kind != row["kind"]:
        deviation("kind-names")
    env: dict = {"schema_version": 1, "capture_id": row["id"], "work_id": row["work_id"]}
    if row["edition_id"] is not None:
        env["edition_id"] = row["edition_id"]
    env["kind"] = kind
    snapshot = json.loads(row["source_snapshot_json"])
    if "location_label" in snapshot:
        snapshot["location_label_origin"] = "user" if snapshot.get("source_kind") == "physical" else "app"
        deviation("no-location-origin")
    env["source_snapshot"] = snapshot

    anchor_rows = db.execute("SELECT * FROM capture_anchor WHERE capture_id = ? ORDER BY ordinal", (row["id"],)).fetchall()
    anchors: list[dict] = []
    audio_rows = []
    quoted = row["quoted_text"]
    for a in anchor_rows:
        locator = json.loads(a["locator_json"])
        payload = json.loads(a["adapter_payload"]) if a["adapter_payload"] else None
        base = {"schema_version": a["schema_version"], "kind": a["kind"], "work_id": a["work_id"]}
        if a["edition_id"] is not None:
            base["edition_id"] = a["edition_id"]
        if a["kind"] == "manual":
            deviation("manual-anchor")
            continue
        if a["kind"] == "audio":
            audio_rows.append((a, locator))
            continue
        base.update({"asset_id": a["asset_id"], "asset_sha256": a["asset_sha256"]})
        if a["kind"] == "epub":
            anchor = dict(base, resource_href=locator["resource_href"])
            if "exact_text_sha256" in locator:
                if quoted is None or hashlib.sha256(quoted.encode("utf-8")).hexdigest() != locator["exact_text_sha256"]:
                    raise AssertionError(f"{name}: exact_text_sha256 is not the SHA-256 of the capture's quoted_text")
                deviation("epub-text-as-digest")
                log.note("g05-recovery: EPUB exact_text taken from quoted_text, whose SHA-256 equals exact_text_sha256")
            else:
                deviation("epub-text-missing")
            anchor["exact_text"] = quoted if quoted is not None else PLACEHOLDER
            if "prefix" in locator and "suffix" in locator:
                anchor["prefix"], anchor["suffix"] = locator["prefix"], locator["suffix"]
            else:
                anchor["prefix"] = anchor["suffix"] = ""
                deviation("epub-context-missing")
            if payload and "type" in payload:
                anchor["resource_media_type"] = payload["type"]
                deviation("epub-media-type-opaque")
            else:
                anchor["resource_media_type"] = "application/xhtml+xml"
                deviation("epub-media-type-missing")
            if "start" in locator and "end" in locator:
                if a["text_offset_unit"] != "unicode_scalar":
                    raise AssertionError(f"{name}: EPUB offsets in {a['text_offset_unit']!r}")
                anchor["text_offsets"] = {"unit": "unicode_scalar", "basis": "sylvia-extraction",
                                          "extraction_version": PLACEHOLDER, "block_index": 0,
                                          "start": locator["start"], "end": locator["end"]}
                deviation("epub-offsets-without-block")
            anchor["reader"] = {"adapter": "unrecorded", "adapter_version": PLACEHOLDER, "locator": payload or {}}
            deviation("epub-reader-unnamed" if payload else "epub-reader-missing")
            anchors.append(anchor)
        elif a["kind"] == "pdf":
            if a["text_offset_unit"] != "unicode_scalar":
                raise AssertionError(f"{name}: PDF offsets in {a['text_offset_unit']!r}")
            missing = {"exact_text", "extraction", "reader", "segments/0/page_box", "segments/0/text",
                       "segments/0/prefix", "segments/0/suffix", "segments/0/page_text_sha256"}
            present = {k for k in ("exact_text", "extraction", "reader", "page_box", "text", "prefix", "suffix",
                                   "page_text_sha256") if k in locator}
            missing -= {k if k in {"exact_text", "extraction", "reader"} else f"segments/0/{k}" for k in present}
            if missing != RECOVERY_PDF_MISSING:
                raise AssertionError(f"{name}: PDF locator lacks {sorted(missing)}, recorded {sorted(RECOVERY_PDF_MISSING)}")
            deviation("pdf-reduced")
            start, end = locator["text_range"]
            segment = {"page_index": locator["page_index"], "page_rotation": locator["rotation"],
                       "page_box": {"name": "crop", "rect": [0, 0, 1, 1]}, "text": quoted or PLACEHOLDER,
                       "text_range": {"unit": "unicode_scalar", "start": start, "end": end},
                       "prefix": "", "suffix": "", "line_rects": locator["rects"], "page_text_sha256": "0" * 64}
            if "page_label" in locator:
                segment["page_label"] = locator["page_label"]
            log.note("g05-recovery: PDF rotation renamed page_rotation, rects line_rects, text_range [s, e] made a "
                     "unicode_scalar range")
            anchors.append(dict(base, exact_text=quoted or PLACEHOLDER, segments=[segment],
                                extraction={"extractor": PLACEHOLDER, "adapter_version": 1, "platform": PLACEHOLDER},
                                reader={"adapter": "unrecorded", "locator": {}}))
        else:
            raise AssertionError(f"{name}: anchor kind {a['kind']!r} has no envelope form")
    if audio_rows:
        revisions = {loc["timeline_revision"] for _, loc in audio_rows}
        if len(revisions) != 1:
            raise AssertionError(f"{name}: audio anchor rows name timeline revisions {sorted(revisions)}")
        if any("member_sequence" in loc for _, loc in audio_rows):
            deviation("audio-member-sequence")
        first = audio_rows[0][0]
        anchor = {"schema_version": first["schema_version"], "kind": "audio", "work_id": first["work_id"],
                  "timeline_revision": revisions.pop(),
                  "ranges": [{"asset_id": a["asset_id"], "asset_sha256": a["asset_sha256"],
                              "start_ms": a["start_ms"], "end_ms": a["end_ms"]} for a, _ in audio_rows]}
        if first["edition_id"] is not None:
            anchor["edition_id"] = first["edition_id"]
        log.note("g05-recovery: audio anchor rows assembled into one audio anchor")
        anchors.append(anchor)
    env["anchors"] = anchors

    if quoted is not None:
        env["quoted_text"] = quoted
        env["quoted_text_origin"] = "selection" if any(a["kind"] in TEXT_ANCHOR_KINDS for a in anchors) else "user_entered"
        deviation("no-quote-origin")
    if kind == "word":
        env["word"] = {"headword": quoted or PLACEHOLDER}
        deviation("word-no-entry")

    notes = []
    for note in db.execute("SELECT * FROM note WHERE capture_id = ? ORDER BY created_at_ms, id", (row["id"],)):
        revisions = db.execute("SELECT * FROM note_revision WHERE note_id = ? ORDER BY revision", (note["id"],)).fetchall()
        if any(r["origin"] != "user" for r in revisions):
            deviation("note-origins")
        item = {"note_id": note["id"], "current_revision": note["current_revision"],
                "revisions": [{"revision": r["revision"], "body": r["body"], "format": r["format"],
                               "saved_at": ms_to_rfc3339(r["saved_at_ms"])} for r in revisions]}
        if note["trashed_at_ms"] is not None:
            item["trashed_at"] = ms_to_rfc3339(note["trashed_at_ms"])
        notes.append(item)
    env["notes"] = notes

    excerpts = db.execute("SELECT * FROM retained_excerpt WHERE capture_id = ? ORDER BY created_at_ms, id",
                          (row["id"],)).fetchall()
    if len(excerpts) > 1:
        raise AssertionError(f"{name}: {len(excerpts)} retained_excerpt rows")
    if excerpts:
        ex = excerpts[0]
        audio = [a for a in anchors if a["kind"] == "audio"]
        by_digest = {r["asset_sha256"]: r["asset_id"] for a in audio for r in a["ranges"]}
        source = json.loads(ex["source_ranges_json"])
        if any("asset_id" not in s for s in source):
            deviation("excerpt-ranges-by-digest")
        requested = [{"asset_id": by_digest.get(s["asset_sha256"]), "start_ms": s["start_ms"], "end_ms": s["end_ms"]}
                     for s in source]
        if not audio or requested != [{k: r[k] for k in ("asset_id", "start_ms", "end_ms")} for r in audio[0]["ranges"]]:
            raise AssertionError(f"{name}: the excerpt's source ranges are not the audio anchor's ranges")
        excerpt = {"state": ex["export_state"]}
        if ex["export_state"] in {"preserved", "removed"}:
            clip, actual = 0, []
            for r in requested:
                actual.append(dict(r, clip_start_ms=clip, source_format=PLACEHOLDER))
                clip += r["end_ms"] - r["start_ms"]
            excerpt.update({"blob_sha256": ex["blob_sha256"], "file_extension": ex["file_extension"],
                            "media_type": ex["media_type"], "byte_count": ex["byte_count"],
                            "duration_ms": ex["clip_duration_ms"], "format": PLACEHOLDER,
                            "sample_rate_hz": 44_100, "frame_count": ex["clip_duration_ms"] * 441 // 10,
                            "actual_ranges": actual})
            deviation("excerpt-no-timing")
            skip_rules |= {"C4", "C9"}  # their inputs (actual ranges, frames) are placeholders here
        env["retained_excerpt"] = excerpt

    surface = ("reader" if any(a["kind"] in TEXT_ANCHOR_KINDS for a in anchors)
               else "player" if any(a["kind"] == "audio" for a in anchors) else "manual_entry")
    env["provenance"] = {"surface": surface, "idempotency_key": row["idempotency_key"]}
    deviation("no-surface")
    env["created_at"], env["updated_at"] = ms_to_rfc3339(row["created_at_ms"]), ms_to_rfc3339(row["updated_at_ms"])
    env["revision"] = row["revision"]
    if row["trashed_at_ms"] is not None:
        env["trashed_at"] = ms_to_rfc3339(row["trashed_at_ms"])
    return env


def recovery_work_note_envelope(db: sqlite3.Connection, note: sqlite3.Row, log: Adaptations) -> dict:
    """A note row without a capture or conversation (a note on the whole work) as the `note` capture the envelope
    makes of it (deviation note-without-capture). The capture ID, the source snapshot (the work's title and authors,
    source kind `work`), the provenance and the revision are supplied; the note and its revisions are the rows'."""
    work = db.execute("SELECT * FROM work WHERE id = ?", (note["work_id"],)).fetchone()
    authors = [r["display_name"] for r in db.execute(
        "SELECT c.display_name FROM work_contributor wc JOIN contributor c ON c.id = wc.contributor_id "
        "WHERE wc.work_id = ? AND wc.role = 'author' ORDER BY wc.ordinal", (note["work_id"],))]
    revisions = db.execute("SELECT * FROM note_revision WHERE note_id = ? ORDER BY revision", (note["id"],)).fetchall()
    item = {"note_id": note["id"], "current_revision": note["current_revision"],
            "revisions": [{"revision": r["revision"], "body": r["body"], "format": r["format"],
                           "saved_at": ms_to_rfc3339(r["saved_at_ms"])} for r in revisions]}
    env = {"schema_version": 1, "capture_id": fixture_uuid(f"g05-recovery/work-note/{note['id']}/capture"),
           "work_id": note["work_id"], "kind": "note",
           "source_snapshot": {"title": work["title"], "author_display": ", ".join(authors), "source_kind": "work"},
           "anchors": [], "notes": [item],
           "provenance": {"surface": "manual_entry", "idempotency_key": f"{PLACEHOLDER} work note {note['id']}"},
           "created_at": ms_to_rfc3339(note["created_at_ms"]), "updated_at": ms_to_rfc3339(note["updated_at_ms"])}
    if note["trashed_at_ms"] is not None:
        item["trashed_at"] = env["trashed_at"] = ms_to_rfc3339(note["trashed_at_ms"])
    env["revision"] = minimum_revision(env)
    log.note("g05-recovery: work-level note wrapped in a note capture (capture ID, the work's snapshot, provenance and "
             "revision supplied; deviation note-without-capture)")
    return env


# A code-rule violation on a recovery envelope that a recorded deviation explains.
RECOVERY_RULE_DEVIATIONS = {
    ("C8", "audio_capture"): "revision-excludes-excerpt",
    ("A2", "pdf"): "pdf-range-length",
}


def recovery_checks(root: Path, schemas: Schemas, kinds: Kinds, log: Adaptations) -> tuple[list[str], list[str]]:
    """Returns (report lines, problems)."""
    db = sqlite3.connect(f"file:{root / RECOVERY_LIBRARY}?mode=ro&immutable=1", uri=True)
    db.row_factory = sqlite3.Row
    lines: list[str] = []
    problems: list[str] = []
    seen: dict[str, set[str]] = {k: {"table definitions"} for k in recovery_table_deviations(db)}
    rows = db.execute("SELECT * FROM capture ORDER BY id").fetchall()
    for row in rows:
        name = f"G0.5 recovery capture {row['idempotency_key']}"
        skip: set[str] = set()
        try:
            env = recovery_envelope(db, row, seen, log, skip)
        except (AssertionError, KeyError, TypeError, ValueError) as exc:
            problems.append(f"{name}: cannot be mapped: {exc}")
            continue
        schema_errors = schemas.errors("capture", env)
        problems += [f"{name}: unrecorded difference: {describe_error(e)}" for e in schema_errors]
        problems += [f"{name}: writer profile: {m}" for m in writer_profile_violations(kinds, env, env["anchors"])]
        explained = []
        if not schema_errors:
            for rule, msg in capture_violations(env):
                if rule in skip:
                    continue
                anchor_kind = None
                match = re.match(r"anchors/(\d+): ", msg)
                if match:
                    anchor_kind = env["anchors"][int(match.group(1))]["kind"]
                key = RECOVERY_RULE_DEVIATIONS.get((rule, anchor_kind or env["kind"]))
                if key is None:
                    problems.append(f"{name}: unrecorded difference: {rule} {msg}")
                else:
                    seen.setdefault(key, set()).add(row["idempotency_key"])
                    explained.append(f"{rule} ({key})")
        unchecked = f"; not checked: {', '.join(sorted(skip))} (placeholder timing)" if skip else ""
        lines.append(f"  {'ok  ' if not schema_errors else 'FAIL'} {name}: {env['kind']}, {len(env['anchors'])} "
                     f"anchor(s), {len(env['notes'])} note(s){', excerpt ' + env['retained_excerpt']['state'] if 'retained_excerpt' in env else ''}; "
                     f"schema-valid with placeholders: {'yes' if not schema_errors else 'no'}; code rules explained by "
                     f"recorded deviations: {', '.join(explained) or 'none'}{unchecked}")
    # Notes without a capture: on the whole work (mapped into the note capture the envelope makes of it) or on an AI
    # conversation (no v1 form).
    loose = db.execute("SELECT * FROM note WHERE capture_id IS NULL ORDER BY created_at_ms, id").fetchall()
    work_notes = 0
    for note in loose:
        label = f"note {note['id'][:8]}"
        origins = {r["origin"] for r in db.execute("SELECT origin FROM note_revision WHERE note_id = ?", (note["id"],))}
        if origins - {"user"}:
            seen.setdefault("note-origins", set()).add(label)
        if note["conversation_id"] is not None:
            seen.setdefault("note-on-conversation", set()).add(label)
            lines.append(f"  --   G0.5 recovery {label} on conversation {note['conversation_id'][:8]}: no form in the v1 "
                         f"envelope (recorded deviation note-on-conversation; ADR-0016 open item)")
            continue
        work_notes += 1
        seen.setdefault("note-without-capture", set()).add(label)
        name = f"G0.5 recovery work {label}"
        env = recovery_work_note_envelope(db, note, log)
        schema_errors = schemas.errors("capture", env)
        problems += [f"{name}: unrecorded difference: {describe_error(e)}" for e in schema_errors]
        problems += [f"{name}: writer profile: {m}" for m in writer_profile_violations(kinds, env, env["anchors"])]
        if not schema_errors:
            problems += [f"{name}: unrecorded difference: {rule} {msg}" for rule, msg in capture_violations(env)]
        lines.append(f"  {'ok  ' if not schema_errors else 'FAIL'} {name}: as a note capture with no anchors, "
                     f"{len(env['notes'][0]['revisions'])} revision(s){', in the trash' if 'trashed_at' in env else ''}; "
                     f"schema-valid with the supplied wrapper: {'yes' if not schema_errors else 'no'}")
    db.close()
    for key in sorted(set(seen) - set(RECOVERY_DEVIATIONS)):
        problems.append(f"G0.5 recovery: observed deviation {key} is not recorded")
    for key in sorted(set(RECOVERY_DEVIATIONS) - set(seen)):
        problems.append(f"G0.5 recovery: recorded deviation {key} is no longer observed (update ADR-0016 section 8)")
    mapped = (f"{len(rows)} capture rows and {work_notes} work-level note rows mapped field by field into envelopes, "
              f"{len(loose) - work_notes} conversation note row(s) without a v1 form")
    header = (f"G0.5 recovery library-v1.sqlite: {mapped}; {len(set(seen) & set(RECOVERY_DEVIATIONS))} of "
              f"{len(RECOVERY_DEVIATIONS)} recorded deviations observed, none unrecorded"
              if not [p for p in problems if "deviation" in p] else
              f"G0.5 recovery library-v1.sqlite: {mapped}; deviation records do not match")
    lines.insert(0, header)
    for key in sorted(set(seen) & set(RECOVERY_DEVIATIONS)):
        lines.append(f"  recorded deviation {key} (ADR-0016 section 8; seen in {', '.join(sorted(seen[key]))}): "
                     f"{RECOVERY_DEVIATIONS[key]}")
    return lines, problems


# ----------------------------------------------------------------------------------------------- fixtures


def apply_op(document, op: dict):
    doc = copy.deepcopy(document)
    parts = pointer_parts(op["path"])
    if not parts:
        if op["op"] != "replace":
            raise ValueError("only replace applies to the whole document")
        return copy.deepcopy(op["value"])
    parent = doc
    for p in parts[:-1]:
        parent = parent[int(p)] if isinstance(parent, list) else parent[p]
    last = parts[-1]
    kind = op["op"]
    if kind not in {"remove", "replace", "add"}:
        raise ValueError(f"unknown op {kind}")
    if isinstance(parent, list):
        index = len(parent) if last == "-" else int(last)
        if kind == "remove":
            del parent[index]
        elif kind == "replace":
            parent[index] = copy.deepcopy(op["value"])
        else:
            parent.insert(index, copy.deepcopy(op["value"]))
    else:
        if kind == "remove":
            del parent[last]
        else:
            if kind == "replace" and last not in parent:
                raise KeyError(f"replace of missing {op['path']}")
            if kind == "add" and last in parent:
                raise KeyError(f"add of existing {op['path']}")
            parent[last] = copy.deepcopy(op["value"])
    return doc


def apply_ops(document, ops: list[dict]):
    for op in ops:
        document = apply_op(document, op)
    return document


def fixture_outcomes(root: Path, stem: str, key: str, schemas: Schemas, rules, profile) -> tuple[Counter, list[str]]:
    """Checks one fixture directory against its mutations.json. Returns counts and problems."""
    problems: list[str] = []
    counts: Counter[str] = Counter()
    base_dir = root / "Contracts/fixtures" / stem
    valid = {p.name: json.loads(p.read_text(encoding="utf-8")) for p in sorted((base_dir / "valid").glob("*.json"))}
    for name, doc in valid.items():
        counts["valid"] += 1
        errors = schemas.errors(key, doc)
        if errors:
            problems.append(f"{stem}/valid/{name}: schema: {describe_error(errors[0])}")
            continue
        for rule, msg in rules(doc):
            problems.append(f"{stem}/valid/{name}: {rule} {msg}")
        later_writer = name.startswith("unknown-kind-")
        violations = profile(doc)
        if later_writer and not violations:
            problems.append(f"{stem}/valid/{name}: named for a later writer's kind but uses only v1 kinds")
        if not later_writer:
            problems += [f"{stem}/valid/{name}: writer profile: {v}" for v in violations]
    mutations = json.loads((base_dir / "mutations.json").read_text(encoding="utf-8"))
    listed = set()
    for entry in mutations:
        where = f"{stem}/{entry['fixture']}"
        folder, file = entry["fixture"].split("/")
        listed.add(entry["fixture"])
        path = base_dir / folder / file
        if not path.exists():
            problems.append(f"{where}: listed in mutations.json but missing")
            continue
        actual = json.loads(path.read_text(encoding="utf-8"))
        base = valid.get(entry["base"])
        if base is None:
            problems.append(f"{where}: base {entry['base']} is not a valid fixture")
            continue
        ops = entry["ops"]
        if not 1 <= len(ops) <= 2 or (len(ops) == 2 and not entry.get("why")):
            problems.append(f"{where}: {len(ops)} operations{'' if entry.get('why') else ' without a stated reason'}")
        try:
            expected = apply_ops(base, ops)
        except (KeyError, IndexError, ValueError) as exc:
            problems.append(f"{where}: operations do not apply: {exc}")
            continue
        if expected != actual:
            problems.append(f"{where}: is not its base with the listed operations")
            continue
        got = schemas.errors(key, actual)
        if folder == "invalid":
            counts["invalid"] += 1
            counts[f"invalid with {len(ops)} operation(s)"] += 1
            want = sorted(entry["expect"], key=lambda d: json.dumps(d, sort_keys=True))
            counts[f"invalid failing with {len(want)} error(s)"] += 1
            if not want or (len(want) > 1 and not entry.get("why")):
                problems.append(f"{where}: lists {len(want)} expected errors{'' if entry.get('why') else ' without a stated reason'}")
            if got != want:
                problems.append(f"{where}: schema errors [{'; '.join(map(describe_error, got)) or 'none'}], "
                                f"expected [{'; '.join(map(describe_error, want))}]")
        elif folder == "semantic-invalid":
            counts["semantic-invalid"] += 1
            if got:
                problems.append(f"{where}: expected schema-valid, got: {describe_error(got[0])}")
                continue
            rule = entry["expect"][0]["rule"] if entry.get("expect") else None
            if rule != file.split("-", 1)[0].upper() or len(entry["expect"]) != 1:
                problems.append(f"{where}: expects {entry.get('expect')}, but its name starts with {file.split('-', 1)[0]}")
            found = [r for r, _ in rules(actual)]
            if found != [rule]:
                problems.append(f"{where}: expected exactly one violation of {rule}, got {found or 'none'}")
        else:
            problems.append(f"{where}: unknown folder {folder}")
    for folder in ("invalid", "semantic-invalid"):
        for path in sorted((base_dir / folder).glob("*.json")):
            if f"{folder}/{path.name}" not in listed:
                problems.append(f"{stem}/{folder}/{path.name}: not listed in mutations.json")
    return counts, problems


def fixture_summary(stem: str, counts: Counter) -> str:
    def tally(prefix: str, noun: str) -> str:
        parts = [(int(k[len(prefix):].split(" ")[0]), counts[k]) for k in counts if k.startswith(prefix)]
        return ", ".join(f"{n} with {size} {noun}{'s' if size != 1 else ''}" for size, n in sorted(parts))
    return (f"fixtures {stem}: {counts['valid']} valid (pass the code rules and, unless named unknown-kind-*, the v1 "
            f"writer profile); {counts['invalid']} invalid, each its base with the listed operations "
            f"({tally('invalid with ', 'operation')}) failing the schema with exactly the listed errors "
            f"({tally('invalid failing with ', 'error')}); {counts['semantic-invalid']} semantic-invalid, each "
            f"schema-valid and breaking exactly one code-checked rule once, the one its name starts with")


# ----------------------------------------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=Path(__file__).resolve().parents[1], type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    root: Path = args.root.resolve()
    by_id = load_schemas(root)
    schemas = Schemas(by_id)
    kinds = Kinds(by_id)
    lines: list[str] = []
    failures: list[str] = []

    problems, summary = design_package_violations(root, kinds)
    failures += problems
    lines.append(f"design package: capture kinds map onto the capture markers as {summary}; an unknown kind is Pending, never Quote")
    problems, summary = related_contract_violations(by_id)
    failures += problems
    lines.append(f"related contracts: {summary}")
    problems, summary = pattern_portability_violations(root)
    failures += problems
    lines.append(f"patterns: {summary}")

    profiles = {
        "anchor": lambda doc: writer_profile_violations(kinds, None, [doc]),
        "capture": lambda doc: writer_profile_violations(kinds, doc, doc["anchors"]),
    }
    for stem, key, rules in (("anchor.v1", "anchor", anchor_violations), ("capture-envelope.v1", "capture", capture_violations)):
        counts, problems = fixture_outcomes(root, stem, key, schemas, rules, profiles[key])
        lines.append(fixture_summary(stem, counts))
        failures += problems

    log = Adaptations()
    cases: list[tuple[str, dict | None, list[dict]]] = []
    skipped: list[str] = []
    for source, loader in (("G0.1 EPUB", epub_cases), ("G0.1 PDF", pdf_cases), ("G0.4", g04_cases)):
        try:
            loaded = loader(root, log)
        except (AssertionError, KeyError, TypeError, ValueError) as exc:
            failures.append(f"{source} spike output: cannot be adapted: {exc!r}")
            continue
        if source == "G0.4":
            loaded, g04_skipped = loaded
            skipped += g04_skipped
        cases += loaded
    anchor_count = 0
    by_source: Counter[str] = Counter()
    for name, envelope, anchors in cases:
        by_source[" ".join(name.split(" ")[:2])] += 1
        schema_valid = True
        for i, anchor in enumerate(anchors):
            anchor_count += 1
            for error in schemas.errors("anchor", anchor):
                schema_valid = False
                failures.append(f"{name}: anchor {i}: schema: {describe_error(error)}")
        if envelope is not None:
            for error in schemas.errors("capture", envelope):
                schema_valid = False
                failures.append(f"{name}: envelope: schema: {describe_error(error)}")
        # The code rules presuppose a schema-valid document (ADR-0016 section 5).
        if schema_valid and envelope is not None:
            failures += [f"{name}: {rule} {msg}" for rule, msg in capture_violations(envelope)]
        elif schema_valid:
            for a in anchors:
                failures += [f"{name}: {rule} {msg}" for rule, msg in anchor_violations(a)]
        failures += [f"{name}: writer profile: {m}" for m in writer_profile_violations(kinds, envelope, anchors)]
        lines.append(f"  ok? {name}: {len(anchors)} anchor(s){', envelope ' + envelope['kind'] if envelope else ''}")
    lines.append(f"spike output: {len(cases)} captures, {anchor_count} anchors validated "
                 f"({', '.join(f'{k}: {v}' for k, v in sorted(by_source.items()))})")
    for s in skipped:
        lines.append(f"  not a capture: {s}")

    # Control: the same anchors without the adaptations. They are expected to fail (the contract renames and
    # restructures fields), which shows the adaptations above are what makes them valid, nothing else.
    raw_failing, raw_total, raw_reasons = 0, 0, Counter()
    epub_doc = json.loads((root / "Docs/Stage0/evidence/G01-EPUB/anchor-samples.json").read_text(encoding="utf-8"))
    pdf_doc = json.loads((root / "Docs/Stage0/evidence/G01-PDF/anchor-samples.json").read_text(encoding="utf-8"))
    raw_anchors = [a for s in epub_doc["capture_samples"] for a in s["anchors"]] + [s["anchor"] for s in pdf_doc["samples"]]
    for raw in raw_anchors:
        raw_total += 1
        errors = schemas.errors("anchor", raw)
        if errors:
            raw_failing += 1
            raw_reasons.update(sorted({e.get("property") or e["keyword"] for e in errors}))
    commonest = sorted(raw_reasons.items(), key=lambda kv: (-kv[1], kv[0]))[:3]  # ties in name order: reproducible
    lines.append(f"control: {raw_failing} of {raw_total} G0.1 anchors fail the schema without adaptation "
                 f"(most common: {'; '.join(f'{r} ({n})' for r, n in commonest)})")

    try:
        recovery_lines, problems = recovery_checks(root, schemas, kinds, log)
    except (AssertionError, KeyError, TypeError, ValueError, sqlite3.Error) as exc:
        recovery_lines, problems = [], [f"G0.5 recovery library: cannot be checked: {exc!r}"]
    failures += problems
    lines += recovery_lines

    lines.append("adaptations applied to spike output before validation (each counted):")
    for what, n in sorted(log.counts.items()):
        lines.append(f"  {n:4d} x {what}")
    lines.append("code-checked rules: " + "; ".join(f"{k} {v}" for k, v in RULES.items()))

    # Replace the provisional per-case marker now that failures are known.
    failed_names = {f.split(":")[0] for f in failures}
    lines = [l.replace("  ok? ", "  FAIL " if l[6:].split(":")[0] in failed_names else "  ok   ") for l in lines]
    lines.append(f"result: {'FAIL' if failures else 'pass'} ({len(failures)} problem(s))")
    lines += [f"error: {f}" for f in failures]
    text = "\n".join(lines)
    print(text)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
