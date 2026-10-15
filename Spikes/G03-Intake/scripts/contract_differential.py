"""G0.3 differential check: the contract schemas and the Swift manifest readers judge the same inputs.

    contract_differential.py <Contracts dir> <empty work dir> <sylviapack-tool>

Run by check-contract-instances.sh (CI step 5). Every input is a file of bytes. The schema's verdict is what
Scripts/validate-contracts.py would conclude about that file as a fixture: it reads the file as UTF-8, parses it with
Python's json.loads and validates it (jsonschema, Draft 2020-12, with format checks). A file it cannot read or parse is
invalid. The reader's verdict is `sylviapack-tool check-manifest`: the readers' size limit, the strict text check,
decoding and the readers' own validation, through the same functions PackReader and InboxScanner use.

Three parts:
1. Named cases (edge inputs written by hand), each with the outcome it must have:
   agree         schema and reader give the same verdict;
   documented    the schema accepts and the reader refuses, for a rule the schema's description gives to readers
                 (byte limits of paths, file names and whole manifests, NFC, uniqueness, sums, group rules, size and
                 member limits);
   reader-limit  the schema accepts and the reader refuses, for a limit RFC 8259 and the contracts' units leave to
                 readers (a member name given twice, an unpaired surrogate, nesting deeper than 512, an integer
                 outside the reader's 64-bit field);
   quirk         the schema accepts and the reader refuses an input the specifications refuse but the Python
                 validator lets through ($ before a final line feed in Python's re, Python's lenient uuid check, NaN
                 and Infinity in Python's json).
   A divergence passes only if the reader's reason belongs to the expected class (REASONS below).
2. Seeded random mutations of the same base manifests (the pack's with group ids that hold "K", so that a mutation
   can write a canonically equivalent twin, U+212A, where a group is looked up; review R4-01). Each must either agree
   or diverge in the documented direction (schema accepts, reader refuses) for a reason in one of the three classes. A
   manifest a reader accepts and its schema refuses fails the check, as does a refusal whose reason belongs to no class.
3. Instants (review R4-03): for every named case whose created_at both sides accept, the instant the reader decodes
   (`sylviapack-tool created-at`) must equal the proleptic Gregorian instant Python's datetime gives, within 1 ms.

Cases are keyed by (kind, name), and each reader's verdicts are read from its own output (review R3-02: the first
version keyed them by name only, so the pack's date-time cases took the handoff reader's verdicts).
"""
from __future__ import annotations

import copy
import datetime
import json
import pathlib
import random
import re
import subprocess
import sys
from collections import Counter
from decimal import Decimal

from jsonschema import Draft202012Validator, FormatChecker

KINDS = ("pack", "handoff")
SCHEMAS = {"pack": "sylviapack-manifest.v1", "handoff": "import-handoff-manifest.v1"}
BASES = {"pack": "sylviapack-manifest.v1/valid/publication-and-audiobook.json",
         "handoff": "import-handoff-manifest.v1/valid/one-file-representation.json"}
CLASSES = ("documented", "reader-limit", "quirk")
FUZZ_SEED = 20261013
FUZZ_PER_KIND = 1500
# The readers' manifest size limits (PackLimits.maxManifestBytes, HandoffManifest.maxBytes), which both schemas'
# descriptions state (review R4-02). The cases at and one byte over each limit fail if the Swift values change.
SIZE_LIMITS = {"pack": 16 * 1024 * 1024, "handoff": 256 * 1024}
# The fuzz base for the pack: the same manifest with group ids that hold "K" (review R4-01).
FUZZ_GROUP_IDS = {"walden": "WALDEN-K", "meditations-audio": "Meditations_K_audio"}
# The only non-ASCII code points canonically equivalent to ASCII text (CanonicalEquivalenceTests): Swift's String
# equality takes each for its ASCII twin, JSON Schema does not.
CANONICAL_TWINS = {"K": "\u212a", ";": "\u037e", "`": "\u1fef"}

# The reader's reason for refusing a schema-valid input, by class (anchored regular expressions over the
# `check-manifest` reason). A divergence whose reason matches none of them is unexplained and fails the check.
REASONS = {
    "documented": [
        r"unsafe_path: (length|component length|not Unicode NFC)",
        r"duplicate_path: .*",
        r"path_conflict: .*",
        r"manifest_invalid: (total_size is not the sum of sizes|unknown group_id|audiobook member must be audio or cover"
        r"|audiobook member needs order >= 1|duplicate member order|order without group_id|duplicate group_id"
        r"|size overflow)",
        r"limit_exceeded: .*",
        r"invalid field original_filename",
        r"duplicate item id or stored_path",
        r"total_bytes is not the sum of byte_count",
        r"invalid field byte_count",
        r"manifest_too_large: more than \d+ bytes",
        r"handoff\.json is larger than \d+ bytes",
    ],
    "reader-limit": [
        r"not strict JSON: (duplicate_member_name|unpaired_surrogate|nested_too_deep) at byte \d+",
        r"not decodable: .*is not representable in Swift\.",
    ],
    "quirk": [
        r"manifest_invalid: (sha256|group_id|files\.group_id)",
        r"invalid field sha256",
        r"stored_path is not items/<n>\[\.<ext>\]",
        r"unsafe_path: forbidden character U\+A",
        r"not decodable: (created_at|pack_id|handoff_id|items\.\d+\.item_id): "
        r"(not an RFC 3339 date-time|not a canonical UUID \(8-4-4-4-12 hexadecimal digits\))",
        r"not strict JSON: nan_or_infinity at byte \d+",
    ],
}
MARK = "@@G03-RAW@@"


def reason_class(reason: str) -> str | None:
    for name in CLASSES:
        if any(re.fullmatch(pattern, reason) for pattern in REASONS[name]):
            return name
    return None


class Check:
    def __init__(self, contracts: pathlib.Path, work: pathlib.Path, tool: str):
        self.contracts, self.work, self.tool = contracts, work, tool
        self.validators = {kind: Draft202012Validator(
            json.loads((contracts / "schemas" / f"{SCHEMAS[kind]}.schema.json").read_text(encoding="utf-8")),
            format_checker=FormatChecker()) for kind in KINDS}
        self.bases = {kind: json.loads((contracts / "fixtures" / BASES[kind]).read_text(encoding="utf-8")) for kind in KINDS}
        self.plan: list[dict] = []
        self.dates: dict[tuple[str, str], str] = {}   # (kind, case name) -> created_at, for part 3
        self.probe = work / "schema-probe.json"

    # -- verdicts -------------------------------------------------------------------------------------------------

    def schema_verdict(self, kind: str, raw: bytes) -> tuple[str, str]:
        verdict, why, _ = self.schema_judgement(kind, raw)
        return verdict, why

    def schema_judgement(self, kind: str, raw: bytes):
        """As Scripts/validate-contracts.py: json.loads(path.read_text(encoding="utf-8")), then validation. Also returns
        the document as Python read it (None if it could not)."""
        self.probe.write_bytes(raw)
        try:
            document = json.loads(self.probe.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return "invalid", "the validator's json.loads refuses it", None
        except (UnicodeDecodeError, ValueError, RecursionError) as error:
            return "invalid", f"the validator cannot load it: {type(error).__name__}", None
        return ("valid" if self.validators[kind].is_valid(document) else "invalid"), "", document

    def reader_verdicts(self, kind: str, directory: pathlib.Path) -> dict[str, tuple[str, str]]:
        names = sorted(p.name for p in directory.glob("*.json"))
        output = subprocess.run([self.tool, "check-manifest", kind, *names], cwd=directory, check=True,
                                capture_output=True, text=True).stdout
        verdicts = {}
        for line in output.splitlines():
            verdict, rest = line.split(" ", 1)
            name, _, reason = rest.partition(": ") if verdict == "refused" else (rest, "", "")
            assert name not in verdicts, f"{kind} {name}: two reader lines"
            verdicts[name] = (verdict, reason)
        assert sorted(verdicts) == names, f"{kind}: the reader judged {len(verdicts)} of {len(names)} files"
        return verdicts

    # -- named cases ----------------------------------------------------------------------------------------------

    def add_bytes(self, kind: str, name: str, raw: bytes, expect: str, note: str = "") -> None:
        assert expect in ("agree", *CLASSES), expect
        assert not any(c["kind"] == kind and c["name"] == name for c in self.plan), f"duplicate case {kind} {name}"
        (self.work / "cases" / kind / f"{name}.json").write_bytes(raw)
        schema, why = self.schema_verdict(kind, raw)
        self.plan.append({"kind": kind, "name": name, "expect": expect, "note": note, "schema": schema, "why": why})

    def document(self, kind: str, mutate=None):
        document = copy.deepcopy(self.bases[kind])
        if mutate:
            mutate(document)
        return document

    def add(self, kind: str, name: str, mutate, expect: str, note: str = "") -> None:
        document = self.document(kind, mutate)
        if name.startswith("created_at-") and isinstance(document.get("created_at"), str):
            self.dates[(kind, name)] = document["created_at"]
        self.add_bytes(kind, name, dumps(document), expect, note)

    def add_raw(self, kind: str, name: str, keys: list, token: str | bytes, expect: str, note: str = "",
                before=None) -> None:
        """The base manifest, first changed by `before` if given, with the JSON at `keys` replaced by `token`, written as
        is (any bytes)."""
        def mutate(document):
            if before:
                before(document)
            setter(keys, MARK)(document)
        document = self.document(kind, mutate)
        text = json.dumps(document, ensure_ascii=False).encode("utf-8")
        marker = json.dumps(MARK).encode()
        assert text.count(marker) == 1
        self.add_bytes(kind, name, text.replace(marker, token if isinstance(token, bytes) else token.encode("utf-8")),
                       expect, note)

    def add_duplicate(self, kind: str, name: str, keys: list, first: str, second: str, expect: str) -> None:
        """The member at `keys` written twice in its object: `first`, then `second` (raw JSON values)."""
        document = self.document(kind, setter(keys, MARK))
        text = json.dumps(document, ensure_ascii=False)
        member = f"{json.dumps(keys[-1])}: {json.dumps(MARK)}"
        assert text.count(member) == 1
        doubled = f"{json.dumps(keys[-1])}: {first}, {json.dumps(keys[-1])}: {second}"
        self.add_bytes(kind, name, text.replace(member, doubled).encode("utf-8"), expect)

    def named_cases(self) -> None:
        e = "\u00e9"   # one code point, two UTF-8 bytes
        # String bounds of both schemas, at, below and above each limit, in ASCII and non-ASCII text (review R2-04).
        bounds = {
            "pack": [("generator.name", ["generator", "name"], 1, 128), ("generator.version", ["generator", "version"], 1, 64),
                     ("media_type", ["files", 0, "media_type"], 1, 128), ("title", ["groups", 0, "title"], 0, 1024),
                     ("creator", ["groups", 0, "creators", 0], 0, 512), ("language", ["groups", 0, "language"], 0, 35),
                     ("identifier.scheme", ["groups", 0, "identifiers", 0, "scheme"], 1, 64),
                     ("identifier.value", ["groups", 0, "identifiers", 0, "value"], 1, 512)],
            "handoff": [("bundle_identifier", ["producer", "bundle_identifier"], 1, 255),
                        ("build_version", ["producer", "build_version"], 1, 64),
                        ("content_type", ["items", 0, "content_type"], 1, 128),
                        ("provider_type_identifier", ["items", 0, "provider_type_identifier"], 1, 128)],
        }
        for kind, fields in bounds.items():
            for label, keys, low, high in fields:
                for n in sorted({n for n in (low - 1, low, high, high + 1) if n >= 0}):
                    self.add(kind, f"{label}-ascii-{n}", setter(keys, "a" * n), "agree")
                for n in (high, high + 1):
                    self.add(kind, f"{label}-nonascii-{n}cp-{2 * n}bytes", setter(keys, e * n), "agree")

        for order in (-1, 0, 1):
            self.add("pack", f"order-{order}-publication-member", setter(["files", 0, "order"], order), "agree")

        dates_ok = ["2026-10-06T12:00:00Z", "2026-10-06T12:00:00.5Z", "2026-10-06t12:00:00z", "2026-10-06T12:00:00+13:00",
                    "2026-10-06T12:00:00-00:00", "2026-10-06T15:30:00.123456789+13:00", "2024-02-29T00:00:00Z",
                    "0001-01-01T00:00:00Z", "9999-12-31T23:59:59.999999999Z", "2000-02-29T00:00:00Z",
                    "2026-10-06T12:00:00+23:59", "2026-10-06T12:00:00-23:59"]
        dates_bad = ["2026-02-30T12:00:00Z", "2025-02-29T00:00:00Z", "2026-10-06T24:00:00Z", "2026-10-06T12:00:60Z",
                     "2026-10-06T12:00:00+1300", "2026-10-06T12:00:00+24:00", "2026-10-06T12:00:00", "2026-10-06 12:00:00Z",
                     "2026-10-06T12:00:00.Z", "0000-01-01T00:00:00Z", "20261006T120000Z", "6 October 2026",
                     "2026-10-06T12:00:00Z ", "\u0662026-10-06T12:00:00Z", "1900-02-29T00:00:00Z", "2026-13-01T00:00:00Z",
                     "2026-10-06T12:00:00+23:60", "\uff12026-10-06T12:00:00Z"]
        for kind in KINDS:
            for i, value in enumerate(dates_ok + dates_bad):
                self.add(kind, f"created_at-{'ok' if value in dates_ok else 'bad'}-{i:02d}", setter(["created_at"], value),
                         "agree", repr(value))
            for label, value in (("trailing-line-feed", "2026-10-06T12:00:00Z\n"), ("lowercase-trailing-line-feed", "2026-10-06t12:00:00z\n")):
                self.add(kind, f"created_at-quirk-{label}", setter(["created_at"], value), "quirk", repr(value))
            # Proleptic Gregorian instants around and before 1582-10-15, and at both ends of the range (review R4-03):
            # both sides accept them, and part 3 compares the instants. 1000-02-29 and 1700-02-29 exist only in the
            # Julian calendar.
            for label, value in (("1582-10-10", "1582-10-10T00:00:00Z"), ("1582-10-04", "1582-10-04T23:59:59Z"),
                                 ("1582-10-15", "1582-10-15T00:00:00Z"), ("1500-03-01", "1500-03-01T00:00:00Z"),
                                 ("0004-02-29", "0004-02-29T00:00:00Z"), ("1600-02-29", "1600-02-29T12:00:00.25Z"),
                                 ("0001-01-01-plus-23-59", "0001-01-01T00:00:00+23:59"),
                                 ("9999-12-31-minus-23-59", "9999-12-31T23:59:59-23:59"),
                                 ("1969-12-31-fraction", "1969-12-31T23:59:59.999Z")):
                self.add(kind, f"created_at-proleptic-{label}", setter(["created_at"], value), "agree", repr(value))
            for year in ("1000", "1700"):
                self.add(kind, f"created_at-julian-only-leap-day-{year}", setter(["created_at"], f"{year}-02-29T00:00:00Z"), "agree")

        # Paths (pack) and file names (handoff): byte limits the schemas state in their descriptions.
        c255, c254, c256 = e * 127 + "a", e * 127, e * 128
        for name, value, expect in [
            ("path-ascii-512bytes", "a" * 250 + "/" + "c" * 250 + "/bbbbbb.txt", "agree"),
            ("path-ascii-513bytes", "a" * 250 + "/" + "c" * 250 + "/bbbbbbb.txt", "agree"),
            ("path-nonascii-512bytes-258cp", c255 + "/" + c254 + "/a", "agree"),
            ("path-nonascii-513bytes-259cp", c255 + "/" + c255 + "/a", "documented"),
            ("path-example-607bytes-307cp", e * 100 + "/" + e * 100 + "/" + e * 100 + ".epub", "documented"),
            ("path-component-255bytes", "Book/" + c255, "agree"),
            ("path-component-256bytes-128cp", "Book/" + c256, "documented"),
            ("path-sixteen-components", "/".join(f"d{i}" for i in range(1, 16)) + "/f.txt", "agree"),
            # A "/" carrying a combining mark (U+0301 after it) or a prepended mark (U+0600 before it) is still a
            # separator to the schema's pattern and the file system; the readers once treated it as part of a Swift
            # Character and accepted these (report F18).
            ("path-hidden-separator-dot-dot", "../́se-walden.epub", "agree"),
            ("path-hidden-separator-dot-dot-in-the-middle", "Walden/../́se-walden.epub", "agree"),
            ("path-hidden-separator-dot", "./́se-walden.epub", "agree"),
            ("path-hidden-separator-absolute", "/́se-walden.epub", "agree"),
            ("path-hidden-separator-empty-component", "Walden//́se-walden.epub", "agree"),
            ("path-hidden-separator-trailing", "Walden/se-walden.epub؀/", "agree"),
            ("path-hidden-separator-sixteen-components", "/́".join(f"d{i}" for i in range(1, 17)) + ".epub", "agree"),
            ("path-combining-mark-inside-a-component", "Walden/se-waldx́n.epub", "agree"),   # x + U+0301 has no NFC form
            ("path-c1-control-character", "Walden/se-walden\u0085.epub", "agree"),
        ]:
            self.add("pack", name, setter(["files", 0, "path"], value), expect)
        self.add("pack", "rule-hidden-separator-file-is-also-a-folder",
                 setter(["files", 1, "path"], "Walden/se-walden.epub/́0001.mp3"), "documented")
        for name, value, expect in [
            ("original_filename-ascii-255bytes", "M" * 250 + ".epub", "agree"),
            ("original_filename-ascii-256bytes", "M" * 251 + ".epub", "agree"),
            ("original_filename-nonascii-255bytes-128cp", c255, "agree"),
            ("original_filename-nonascii-256bytes-128cp", c256, "documented"),
            ("original_filename-empty", "", "agree"),
            ("original_filename-with-line-feed", "Meditations\n.epub", "agree"),
            ("original_filename-hidden-separator", "Meditations/́.epub", "agree"),           # report F18
            ("original_filename-separator-after-prepended-mark", "Meditations؀/.epub", "agree"),
            ("original_filename-combining-mark", "Meditationś.epub", "agree"),
        ]:
            self.add("handoff", name, setter(["items", 0, "original_filename"], value), expect)

        self.rule_cases()
        self.null_cases()
        self.uuid_cases()
        self.text_cases()
        self.number_cases()
        self.canonical_cases()
        self.size_cases()

        # Python's re: $ also matches before a final line feed (ECMA-262, which JSON Schema names, does not).
        self.add("pack", "quirk-sha256-trailing-line-feed", lambda d: d["files"][0].__setitem__("sha256", d["files"][0]["sha256"] + "\n"), "quirk")
        self.add("pack", "quirk-path-trailing-line-feed", lambda d: d["files"][0].__setitem__("path", d["files"][0]["path"] + "\n"), "quirk")
        self.add("pack", "quirk-group_id-trailing-line-feed",
                 lambda d: (d["groups"][0].__setitem__("group_id", "walden\n"), d["files"][0].__setitem__("group_id", "walden\n")), "quirk")
        self.add("handoff", "quirk-stored-path-trailing-line-feed", setter(["items", 0, "stored_path"], "items/0.epub\n"), "quirk")
        self.add("handoff", "quirk-sha256-trailing-line-feed", lambda d: d["items"][0].__setitem__("sha256", d["items"][0]["sha256"] + "\n"), "quirk")

    def rule_cases(self) -> None:
        """Rules the schemas' descriptions leave to readers: the schema accepts, the reader refuses."""
        def pack_rule(name, mutate):
            self.add("pack", name, mutate, "documented")
        pack_rule("rule-path-not-nfc", setter(["files", 0, "path"], "Walden/se-walde\u0301n.epub"))   # NFD
        pack_rule("rule-paths-equal-ignoring-case", lambda d: d["files"][2].__setitem__("path", d["files"][1]["path"].upper()))
        pack_rule("rule-file-is-also-a-folder", setter(["files", 1, "path"], "Walden/se-walden.epub/01.mp3"))
        pack_rule("rule-total-size-not-the-sum", setter(["total_size"], 1))
        pack_rule("rule-unknown-group-id", setter(["files", 0, "group_id"], "nowhere"))
        pack_rule("rule-audio-member-without-order", lambda d: d["files"][1].pop("order"))
        pack_rule("rule-duplicate-member-order", setter(["files", 2, "order"], 1))
        pack_rule("rule-epub-in-audiobook-group", setter(["files", 0, "group_id"], "meditations-audio"))
        pack_rule("rule-order-without-group", lambda d: (d["files"][0].pop("group_id"), d["files"][0].__setitem__("order", 1)))
        pack_rule("rule-duplicate-group-id", setter(["groups", 1, "group_id"], "walden"))
        resize = lambda d, index, size: (d.__setitem__("total_size", d["total_size"] - d["files"][index]["size"] + size),
                                         d["files"][index].__setitem__("size", size))
        pack_rule("rule-epub-over-1gib", lambda d: resize(d, 0, (1 << 30) + 1))
        pack_rule("rule-audio-over-20gib", lambda d: resize(d, 1, (20 << 30) + 1))
        for kind_name, media, limit in (("pdf", "application/pdf", 2 << 30), ("text", "text/plain", 256 << 20), ("cover", "image/jpeg", 32 << 20)):
            def as_kind(d, size, kind_name=kind_name, media=media):
                d["files"][0].update(kind=kind_name, media_type=media)
                resize(d, 0, size)
            self.add("pack", f"rule-{kind_name}-at-limit", lambda d, as_kind=as_kind, limit=limit: as_kind(d, limit), "agree")
            pack_rule(f"rule-{kind_name}-over-limit", lambda d, as_kind=as_kind, limit=limit: as_kind(d, limit + 1))
        for members, expect in ((500, "agree"), (501, "documented")):
            self.add("pack", f"rule-{members}-audio-members", lambda d, n=members: audiobook(d, n), expect)
        for count, expect in ((10, "agree"), (11, "documented")):
            self.add("pack", f"rule-total-{count}x20gib", lambda d, n=count: twenty_gib_members(d, n), expect)
        self.add("handoff", "rule-duplicate-stored-path",
                 lambda d: d["items"].append(dict(d["items"][0], item_id="6F1E8D2B-3C4A-4B0D-9E8F-7A6B5C4D3E21")) or
                 d.__setitem__("total_bytes", 2 * d["total_bytes"]), "documented")
        self.add("handoff", "rule-duplicate-item-id",
                 lambda d: d["items"].append(dict(d["items"][0], stored_path="items/1.epub")) or
                 d.__setitem__("total_bytes", 2 * d["total_bytes"]), "documented")
        self.add("handoff", "rule-total-bytes-not-the-sum", setter(["total_bytes"], 1), "documented")
        self.add("handoff", "rule-byte-count-sum-overflows",
                 lambda d: (d["items"].append(dict(d["items"][0], item_id="6F1E8D2B-3C4A-4B0D-9E8F-7A6B5C4D3E21", stored_path="items/1.epub",
                                                   byte_count=1 << 63)),
                            d["items"][0].__setitem__("byte_count", 1 << 63), d.__setitem__("total_bytes", 0)), "documented")

    def null_cases(self) -> None:
        """Review R3-01: no member admits null; the readers used to read null as absent."""
        for keys in (["files", 0, "group_id"], ["files", 1, "order"], ["groups", 0, "title"], ["groups", 0, "creators"],
                     ["groups", 0, "language"], ["groups", 0, "identifiers"], ["groups", 1, "member_order_basis"],
                     ["generator"], ["files"], ["total_size"], ["groups", 0, "creators", 0]):
            self.add("pack", "null-" + ".".join(map(str, keys)), setter(keys, None), "agree")
        for keys in (["producer", "build_version"], ["items", 0, "sha256"], ["created_at"]):
            self.add("handoff", "null-" + ".".join(map(str, keys)), setter(keys, None), "agree")
        for kind in KINDS:
            self.add(kind, "null-in-an-unknown-member", setter(["x_future"], None), "agree")

    def uuid_cases(self) -> None:
        canonical = self.bases["pack"]["pack_id"]
        for name, value, expect in [
            ("pack_id-lowercase", canonical.lower(), "agree"),
            ("pack_id-nul-suffix", canonical + "\u0000", "agree"),        # UUID(uuidString:) accepted these (R3-01)
            ("pack_id-nul-then-more", canonical + "\u0000junk", "agree"),
            ("pack_id-braces", "{" + canonical + "}", "agree"),
            ("pack_id-no-hyphens", canonical.replace("-", ""), "agree"),
            ("pack_id-urn-prefix", "urn:uuid:" + canonical, "agree"),
            ("pack_id-extra-hyphen", canonical[:24] + "-" + canonical[24:], "quirk"),
            ("pack_id-trailing-hyphen", canonical + "-", "quirk"),
            ("pack_id-hyphen-in-last-group", canonical[:28] + "-" + canonical[28:], "quirk"),
            ("pack_id-underscore-between-digits", canonical[:33] + "_" + canonical[34:], "quirk"),
            ("pack_id-leading-plus", "+" + canonical[1:], "quirk"),
            ("pack_id-arabic-indic-digit", "\u0665" + canonical[1:], "quirk"),
            ("pack_id-trailing-space", canonical[:-1] + " ", "quirk"),
            ("pack_id-urn-suffix", canonical + "urn:", "quirk"),
        ]:
            self.add("pack", name, setter(["pack_id"], value), expect, repr(value))
        handoff_id = self.bases["handoff"]["handoff_id"]
        item_id = self.bases["handoff"]["items"][0]["item_id"]
        self.add("handoff", "handoff_id-nul-suffix", setter(["handoff_id"], handoff_id + "\u0000"), "agree")
        self.add("handoff", "item_id-nul-then-more", setter(["items", 0, "item_id"], item_id + "\u0000junk"), "agree")
        self.add("handoff", "handoff_id-extra-hyphen", setter(["handoff_id"], handoff_id[:24] + "-" + handoff_id[24:]), "quirk")
        self.add("handoff", "item_id-extra-hyphen", setter(["items", 0, "item_id"], item_id[:24] + "-" + item_id[24:]), "quirk")

    def text_cases(self) -> None:
        """The text layer (review R3-01): what each side does with bytes that are not strict JSON."""
        for kind in KINDS:
            text = dumps(self.bases[kind])
            array = ["files"] if kind == "pack" else ["items"]
            self.add_bytes(kind, "text-utf8-byte-order-mark", b"\xef\xbb\xbf" + text, "agree")
            self.add_bytes(kind, "text-utf16le", text.decode().encode("utf-16-le"), "agree")
            self.add_bytes(kind, "text-utf16le-byte-order-mark", b"\xff\xfe" + text.decode().encode("utf-16-le"), "agree")
            self.add_bytes(kind, "text-utf16be", text.decode().encode("utf-16-be"), "agree")
            self.add_bytes(kind, "text-utf32le", text.decode().encode("utf-32-le"), "agree")
            self.add_bytes(kind, "text-trailing-comma-in-object", text[:-1] + b",}", "agree")
            self.add_raw(kind, "text-trailing-comma-in-array", array,
                         "[" + json.dumps(self.bases[kind][array[0]], ensure_ascii=False)[1:-1] + ",]", "agree")
            self.add_bytes(kind, "text-crlf-tabs-and-spaces", b"\r\n\t " + text.replace(b", ", b",\r\n\t") + b" \r\n", "agree")
            unknown = ["x_unknown"]
            self.add_raw(kind, "text-invalid-utf8-in-an-unknown-member", unknown, b'"a\xc3(b"', "agree")
            self.add_raw(kind, "text-control-character-in-an-unknown-member", unknown, b'"a\x01b"', "agree")
            self.add_raw(kind, "text-bad-escape-in-an-unknown-member", unknown, '"\\x"', "agree")
            self.add_raw(kind, "text-malformed-number-in-an-unknown-member", unknown, "1e+", "agree")
            self.add_raw(kind, "text-leading-zero-in-an-unknown-member", unknown, "-01", "agree")
            self.add_raw(kind, "text-noncharacter-and-nul-in-an-unknown-member", unknown, '"\\uffff\\u0000\U0010ffff"', "agree")
            self.add_raw(kind, "text-nesting-512-levels", unknown, "[" * 511 + "]" * 511, "agree")
            self.add_raw(kind, "text-nesting-513-levels", unknown, "[" * 512 + "]" * 512, "reader-limit")
            self.add_raw(kind, "text-integer-4300-digits-in-an-unknown-member", unknown, "1" + "0" * 4299, "agree")
            self.add_raw(kind, "text-integer-4301-digits-in-an-unknown-member", unknown, "1" + "0" * 4300, "agree")
            self.add_raw(kind, "text-float-5000-digits-in-an-unknown-member", unknown, "1" + "0" * 4999 + ".0", "agree")
            self.add_raw(kind, "text-unpaired-surrogate-in-an-unknown-member", unknown, '"\\ud800"', "reader-limit")
            self.add_raw(kind, "text-unpaired-surrogate-in-a-member-name", unknown, '{"\\udc00": 1}', "reader-limit")
            self.add_raw(kind, "text-surrogate-pair-in-an-unknown-member", unknown, '"\\ud83d\\ude00"', "agree")
            for token in ("NaN", "Infinity", "-Infinity"):
                self.add_raw(kind, f"text-{token.lower()}-in-an-unknown-member", unknown, token, "quirk")
            self.add_raw(kind, "unknown-members-of-every-type", unknown,
                         '{"a": [1, -0.5e-3, true, false, null, "s", {"b": {}}], "c": ""}', "agree")
        self.add("pack", "text-unpaired-surrogate-in-a-title", setter(["groups", 0, "title"], "\ud800"), "reader-limit")
        self.add("pack", "text-nul-in-a-title", setter(["groups", 0, "title"], "a\u0000b"), "agree")
        self.add("handoff", "text-unpaired-surrogate-in-original_filename", setter(["items", 0, "original_filename"], "\udc00.epub"), "reader-limit")
        self.add_raw("pack", "text-nan-as-a-size", ["files", 0, "size"], "NaN", "agree")
        # A member name twice: Python keeps the last value, JSONDecoder kept the first (review R3-01).
        long65 = json.dumps("x" * 65)
        self.add_duplicate("handoff", "duplicate-build_version-second-too-long", ["producer", "build_version"], '"1"', long65, "agree")
        self.add_duplicate("handoff", "duplicate-build_version-first-too-long", ["producer", "build_version"], long65, '"1"', "reader-limit")
        self.add_duplicate("handoff", "duplicate-build_version-both-valid", ["producer", "build_version"], '"1"', '"2"', "reader-limit")
        self.add_duplicate("pack", "duplicate-generator.name-both-valid", ["generator", "name"], '"Sylvia for Mac"', '"Other"', "reader-limit")
        self.add_duplicate("pack", "duplicate-files-second-empty", ["files"],
                           json.dumps(self.bases["pack"]["files"], ensure_ascii=False), "[]", "agree")
        self.add_duplicate("pack", "duplicate-files-first-empty", ["files"],
                           "[]", json.dumps(self.bases["pack"]["files"], ensure_ascii=False), "reader-limit")
        self.add_raw("pack", "duplicate-name-written-with-an-escape", ["total_size"],
                     f'{self.bases["pack"]["total_size"]}, "\\u0074otal_size": {self.bases["pack"]["total_size"]}', "reader-limit")
        self.add_raw("pack", "duplicate-name-in-an-unknown-member", ["x_unknown"], '{"a": 1, "a": 2}', "reader-limit")
        self.add_raw("pack", "distinct-names-that-look-alike", ["x_unknown"], '{"\u00e9": 1, "e\u0301": 2}', "agree")

    def canonical_cases(self) -> None:
        """Review R4-01: text that Swift's String equality takes for other text (U+212A KELVIN SIGN for K) while JSON
        Schema compares code points. A file group_id must name its group exactly."""
        kelvin = "\u212a"

        def groups(group: str, member: str, index: int = 0, files=(0,)):
            def mutate(document):
                document["groups"][index]["group_id"] = group
                for file in files:
                    document["files"][file]["group_id"] = member
            return mutate
        self.add("pack", "group_id-kelvin-sign-on-the-file", groups("WALDEN_K", "WALDEN_" + kelvin), "agree")
        self.add("pack", "group_id-kelvin-sign-on-audiobook-members",
                 groups("MEDITATIONS_K", "MEDITATIONS_" + kelvin, index=1, files=(1, 2)), "agree")
        self.add("pack", "group_id-kelvin-sign-on-the-group", groups("WALDEN_" + kelvin, "WALDEN_K"), "agree")
        self.add("pack", "group_id-kelvin-sign-on-both", groups("WALDEN_" + kelvin, "WALDEN_" + kelvin), "agree")
        self.add("pack", "group_id-ascii-K-on-both", groups("WALDEN_K", "WALDEN_K"), "agree")
        self.add("pack", "group_id-greek-question-mark", groups("WALDEN;", "WALDEN\u037e"), "agree")
        self.add("pack", "path-kelvin-sign", setter(["files", 0, "path"], "Walden/se-walden-" + kelvin + ".epub"), "documented")
        self.add("pack", "paths-K-and-its-kelvin-twin",
                 lambda d: (d["files"][1].__setitem__("path", "Meditations/K.mp3"),
                            d["files"][2].__setitem__("path", "Meditations/" + kelvin + ".mp3")), "documented")
        # An enum value spelled with a JSON escape is the same code points once unescaped: both sides accept it.
        self.add_raw("pack", "kind-value-written-with-an-escape", ["files", 0, "kind"], '"\\u0065pub"', "agree")
        self.add("handoff", "original_filename-kelvin-sign", setter(["items", 0, "original_filename"], "Meditations-" + kelvin + ".epub"), "agree")
        for kind in KINDS:
            self.add_raw(kind, "unknown-member-names-K-and-its-kelvin-twin", ["x_unknown"], '{"K": 1, "\\u212a": 2}', "agree")
            self.add(kind, "unknown-top-level-members-K-and-its-kelvin-twin",
                     lambda d: (d.__setitem__("x_K", 1), d.__setitem__("x_" + kelvin, 2)), "agree")

    def size_cases(self) -> None:
        """Review R4-02: the readers' manifest size limits, which the schemas' descriptions state, at and one byte over
        each limit (padding in an unknown member, which both sides accept otherwise), and the pack's file limit at its
        largest ordinary paths."""
        for kind in KINDS:
            for over, expect in ((0, "agree"), (1, "documented")):
                document = self.document(kind)
                document["x_padding"] = ""
                length = SIZE_LIMITS[kind] + over - len(dumps(document))
                document["x_padding"] = "a" * length
                raw = dumps(document)
                assert len(raw) == SIZE_LIMITS[kind] + over
                self.add_bytes(kind, f"size-{'at-the-limit' if over == 0 else 'one-byte-over-the-limit'}-{len(raw)}-bytes",
                               raw, expect)
        for count in (9998, 9999):
            self.add_bytes("pack", f"size-{count}-files-with-512-byte-paths-in-20-audiobook-groups",
                           dumps(entry_limit_manifest(self.bases["pack"], count)), "agree")

    def number_cases(self) -> None:
        size = self.bases["pack"]["files"][0]["size"]
        for name, keys, token, expect in [
            ("number-size-with-a-zero-fraction", ["files", 0, "size"], f"{size}.0", "agree"),
            ("number-size-with-an-exponent", ["files", 0, "size"], "9.97147e5", "agree"),
            ("number-schema_version-1.0", ["schema_version"], "1.0", "agree"),
            ("number-schema_version-1e0", ["schema_version"], "1e0", "agree"),
            ("number-order-1.0", ["files", 1, "order"], "1.0", "agree"),
            ("number-size-1.5", ["files", 0, "size"], "1.5", "agree"),
            ("number-size-1e400", ["files", 0, "size"], "1e400", "agree"),
            ("number-size-true", ["files", 0, "size"], "true", "agree"),
            ("number-size-uint64-max", ["files", 0, "size"], str((1 << 64) - 1), "documented"),
            ("number-size-2^64", ["files", 0, "size"], str(1 << 64), "reader-limit"),
            ("number-size-2^64-as-a-float", ["files", 0, "size"], "1.8446744073709552e19", "reader-limit"),
            ("number-total_size-2^64", ["total_size"], str(1 << 64), "reader-limit"),
            ("number-order-2^63", ["files", 1, "order"], str(1 << 63), "reader-limit"),
        ]:
            self.add_raw("pack", name, keys, token, expect)
        for name, keys, token, expect in [
            ("number-byte_count-2^64", ["items", 0, "byte_count"], str(1 << 64), "reader-limit"),
            ("number-total_bytes-2^64", ["total_bytes"], str(1 << 64), "reader-limit"),
            ("number-total_bytes-with-a-zero-fraction", ["total_bytes"], f'{self.bases["handoff"]["total_bytes"]}.0', "agree"),
        ]:
            self.add_raw("handoff", name, keys, token, expect)
        # Spellings Python's json reads as the integer 0 (or -0.0, which JSON Schema counts as an integer >= 0), with the
        # totals adjusted so that only the spelling differs: JSONDecoder reads each as 0 too (measured on macOS 26.6).
        size0 = self.bases["pack"]["files"][0]["size"]
        count0 = self.bases["handoff"]["items"][0]["byte_count"]
        for label, token in (("minus-zero", "-0"), ("minus-zero-fraction", "-0.0"), ("zero-exponent", "0e0"),
                             ("underflow-to-zero", "1e-400"), ("negative-underflow-to-zero", "-1e-400")):
            self.add_raw("pack", f"number-size-{label}", ["files", 0, "size"], token, "agree", repr(token),
                         before=lambda d: d.__setitem__("total_size", d["total_size"] - size0))
            self.add_raw("handoff", f"number-byte_count-{label}", ["items", 0, "byte_count"], token, "agree", repr(token),
                         before=lambda d: d.__setitem__("total_bytes", d["total_bytes"] - count0))
        self.add_raw("pack", "number-order-minus-zero", ["files", 1, "order"], "-0", "agree")
        self.add_raw("pack", "number-size-smallest-subnormal", ["files", 0, "size"], "5e-324", "agree")

    # -- random mutations -----------------------------------------------------------------------------------------

    def fuzz_base(self, kind: str):
        document = copy.deepcopy(self.bases[kind])
        if kind == "pack":
            for entry in document["groups"] + document["files"]:
                if entry.get("group_id") in FUZZ_GROUP_IDS:
                    entry["group_id"] = FUZZ_GROUP_IDS[entry["group_id"]]
        return document

    def fuzz_cases(self) -> dict[str, list[dict]]:
        rng = random.Random(FUZZ_SEED)
        cases = {kind: [] for kind in KINDS}
        for kind in KINDS:
            directory = self.work / "fuzz" / kind
            directory.mkdir(parents=True)
            for index in range(FUZZ_PER_KIND):
                document = self.fuzz_base(kind)
                steps = [mutate(rng, document) for _ in range(rng.randint(1, 3))]
                raw = dumps(document, ascii_only=rng.random() < 0.3, sort_keys=rng.random() < 0.5)
                shadowed: set[str] = set()
                if rng.random() < 0.05:   # a member name given twice at the top level (Python keeps the last)
                    key = rng.choice(sorted(document))
                    value = rng.choice(VALUES)
                    raw = b"{" + json.dumps(key).encode() + b": " + dumps(value) + b", " + raw[1:]
                    steps.append(f"duplicate {key}")
                    # The first value is in the text but not in what Python keeps: what it holds counts too.
                    shadowed = triggers(value, duplicated=True)
                name = f"fuzz-{index:04d}.json"
                (directory / name).write_bytes(raw)
                schema, why, parsed = self.schema_judgement(kind, raw)
                cases[kind].append({"name": name, "schema": schema, "why": why, "steps": steps,
                                    "triggers": triggers(parsed, duplicated=False) | shadowed})
        return cases

    # -- run ------------------------------------------------------------------------------------------------------

    def run(self) -> int:
        for kind in KINDS:
            (self.work / "cases" / kind).mkdir(parents=True)
        self.named_cases()
        failures = 0
        counts: Counter = Counter()
        per_kind = ", ".join(f"{kind} {sum(case['kind'] == kind for case in self.plan)}" for kind in KINDS)
        print(f"named cases: {len(self.plan)} ({per_kind})")
        verdicts = {kind: self.reader_verdicts(kind, self.work / "cases" / kind) for kind in KINDS}
        for case in self.plan:
            verdict, reason = verdicts[case["kind"]][case["name"] + ".json"]
            schema_ok, reader_ok = case["schema"] == "valid", verdict == "accepted"
            if case["expect"] == "agree":
                good = schema_ok == reader_ok
            else:
                good = schema_ok and not reader_ok and reason_class(reason) == case["expect"]
            counts[(case["kind"], case["expect"], good)] += 1
            failures += 0 if good else 1
            note = f" [{case['note']}]" if case["note"] else ""
            schema = case["schema"] + (f" ({case['why']})" if case["why"] else "")
            print(f"  {'ok' if good else 'MISMATCH'}: {case['kind']} {case['name']}{note}: schema={schema} "
                  f"reader={verdict}{(' (' + reason + ')') if reason else ''} expected={case['expect']}")
        for kind in KINDS:
            line = ", ".join(f"{expect} {counts[(kind, expect, True)]}" for expect in ("agree", *CLASSES))
            bad = sum(counts[(kind, expect, False)] for expect in ("agree", *CLASSES))
            print(f"named {kind}: {line}; not as expected {bad}")

        fuzz = self.fuzz_cases()
        print(f"random mutations: seed {FUZZ_SEED}, {FUZZ_PER_KIND} per kind")
        for kind in KINDS:
            reader = self.reader_verdicts(kind, self.work / "fuzz" / kind)
            tally: Counter = Counter()
            for case in fuzz[kind]:
                verdict, reason = reader[case["name"]]
                schema_ok, reader_ok = case["schema"] == "valid", verdict == "accepted"
                if schema_ok == reader_ok:
                    tally["both accept" if schema_ok else "both refuse"] += 1
                    continue
                if reader_ok:
                    outcome = "UNSOUND: the reader accepts what the schema refuses"
                else:
                    cls = reason_class(reason)
                    # A quirk or reader-limit reason counts only if the input holds what causes it (see triggers()),
                    # so a reader bug that happens to give such a reason is not explained away.
                    if cls == "documented" or cls in case["triggers"]:
                        tally[f"schema accepts, reader refuses: {cls}"] += 1
                        continue
                    outcome = ("UNEXPLAINED: the reader refuses a schema-valid input for a reason in no class" if cls is None
                               else f"UNEXPLAINED: a {cls} reason, but the input holds nothing that causes one")
                failures += 1
                tally["failed"] += 1
                print(f"  {outcome}: {kind} {case['name']}: schema={case['schema']} reader={verdict} ({reason}); "
                      f"mutations: {'; '.join(case['steps'])}")
            print(f"random {kind}: " + ", ".join(f"{label} {tally[label]}" for label in sorted(tally)))
            twins = sum(1 for case in fuzz[kind] if any(step.startswith("canonical-twin") for step in case["steps"]))
            print(f"random {kind}: {twins} mutations wrote a canonical twin (U+212A, U+037E or U+1FEF)")

        failures += self.check_instants(verdicts)
        print(f"differential: {len(self.plan)} named cases, {FUZZ_PER_KIND * len(KINDS)} random mutations and the "
              f"instants of {self.instants_compared} date-times, failures={failures}")
        return 1 if failures else 0

    def check_instants(self, verdicts) -> int:
        """Part 3: every created_at both sides accept decodes to Python's proleptic Gregorian instant."""
        failures = 0
        self.instants_compared = 0
        for kind in KINDS:
            # Only strict RFC 3339 texts have an instant to compare: a date-time the validator accepts only through the
            # $ quirk (a final line feed) is judged by part 1, where a reader that accepts it already fails.
            names = sorted(name for (k, name) in self.dates
                           if k == kind and DATE_TIME.fullmatch(self.dates[(k, name)])
                           and verdicts[kind][name + ".json"][0] == "accepted"
                           and next(c for c in self.plan if c["kind"] == kind and c["name"] == name)["schema"] == "valid")
            output = subprocess.run([self.tool, "created-at", kind, *(name + ".json" for name in names)],
                                    cwd=self.work / "cases" / kind, check=True, capture_output=True, text=True).stdout
            swift = dict(line.rsplit(" ", 1) for line in output.splitlines())
            for name in names:
                text = self.dates[(kind, name)]
                expected = python_instant(text)
                value = swift[name + ".json"]
                good = value != "refused" and abs(Decimal(value) - expected) <= Decimal("0.001")
                self.instants_compared += 1
                failures += 0 if good else 1
                print(f"  {'ok' if good else 'INSTANT'}: {kind} {name} [{text!r}]: reader={value} python={expected}")
        print(f"instants: {self.instants_compared} created_at values compared with Python's, failures={failures}")
        return failures


# -- helpers --------------------------------------------------------------------------------------------------------

def dumps(document, ascii_only: bool = False, sort_keys: bool = False) -> bytes:
    try:
        return json.dumps(document, ensure_ascii=ascii_only, sort_keys=sort_keys).encode("utf-8")
    except UnicodeEncodeError:   # an unpaired surrogate cannot be written as UTF-8; write it as an escape
        return json.dumps(document, ensure_ascii=True, sort_keys=sort_keys).encode("utf-8")


def triggers(document, duplicated: bool) -> set[str]:
    """Which divergence classes the input (as Python read it) can explain, judged independently of the reader:
    quirk: a string ending in a line feed (the $ quirk of patterns and date-time), NaN or an infinity, or a UUID field
    that Python's uuid check accepts in a non-canonical form; reader-limit: a member name given twice, an unpaired
    surrogate in any name or string, or a number of magnitude 2^63 or more."""
    found: set[str] = set()
    if duplicated:
        found.add("reader-limit")

    def walk(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if any(0xD800 <= ord(c) <= 0xDFFF for c in key):
                    found.add("reader-limit")
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
        elif isinstance(value, str):
            if value.endswith("\n"):
                found.add("quirk")
            if any(0xD800 <= ord(c) <= 0xDFFF for c in value):
                found.add("reader-limit")
        elif isinstance(value, float) and (value != value or value in (float("inf"), float("-inf"))):
            found.add("quirk")
        elif isinstance(value, (int, float)) and not isinstance(value, bool) and abs(value) >= 2 ** 63:
            found.add("reader-limit")

    walk(document)
    if isinstance(document, dict):
        ids = [document.get("pack_id"), document.get("handoff_id")]
        items = document.get("items")
        if isinstance(items, list):
            ids += [item.get("item_id") for item in items if isinstance(item, dict)]
        for value in ids:
            if isinstance(value, str) and FormatChecker().conforms(value, "uuid") and not CANONICAL_UUID.fullmatch(value):
                found.add("quirk")
    return found


CANONICAL_UUID = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
DATE_TIME = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})")


def python_instant(text: str) -> Decimal:
    """Seconds since 1970-01-01T00:00:00Z of an RFC 3339 date-time the schema accepts, exact: days from Python's
    datetime.date (proleptic Gregorian), then the time, the offset and the fraction."""
    year, month, day, hour, minute, second, fraction, offset = DATE_TIME.fullmatch(text).groups()
    days = (datetime.date(int(year), int(month), int(day)) - datetime.date(1970, 1, 1)).days
    shift = 0 if offset in "Zz" else (1 if offset[0] == "+" else -1) * (int(offset[1:3]) * 3600 + int(offset[4:6]) * 60)
    return (Decimal(days * 86400 + int(hour) * 3600 + int(minute) * 60 + int(second) - shift)
            + (Decimal(fraction) if fraction else Decimal(0)))


def entry_limit_manifest(base, count: int):
    """The pack manifest of PackLimitTests.entryLimitManifest: `count` one-byte audio files whose paths are each 512
    bytes, with 128-character media types, in audiobook groups of 500 members with their metadata at its limits."""
    def group_id(group: int) -> str:
        head = f"audiobook-{group}-"
        return head + "x" * (64 - len(head))
    document = copy.deepcopy(base)
    document["files"] = [{"group_id": group_id(index // 500), "kind": "audio", "media_type": "audio/" + "m" * 122,
                          "order": index % 500 + 1, "path": "a" * 250 + "/" + "b" * 250 + "/" + f"{index:05d}ccccc",
                          "sha256": "ab" * 32, "size": 1} for index in range(count)]
    document["groups"] = [{"creators": ["c" * 512], "group_id": group_id(group),
                           "identifiers": [{"scheme": "s" * 64, "value": "v" * 512}], "kind": "audiobook",
                           "language": "l" * 35, "member_order_basis": "user_confirmed", "title": "t" * 1024}
                          for group in range((count + 499) // 500)]
    document["total_size"] = count
    return document


def setter(keys: list, value):
    def mutate(document):
        target = document
        for key in keys[:-1]:
            target = target[key]
        target[keys[-1]] = value
    return mutate


def audiobook(document, members: int) -> None:
    document["files"] = document["files"][:1] + [
        {"group_id": "meditations-audio", "kind": "audio", "media_type": "audio/mpeg", "order": n,
         "path": f"Meditations (LibriVox)/{n:03d}.mp3", "sha256": "ab" * 32, "size": 1} for n in range(1, members + 1)]
    document["total_size"] = sum(f["size"] for f in document["files"])


def twenty_gib_members(document, count: int) -> None:
    document["files"] = [{"group_id": "meditations-audio", "kind": "audio", "media_type": "audio/x-caf", "order": n,
                          "path": f"Meditations/{n:02d}.caf", "sha256": "cd" * 32, "size": 20 << 30} for n in range(1, count + 1)]
    document["total_size"] = count * (20 << 30)


CANONICAL = "5E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D10"
STRINGS = [
    "", "a", "\u00e9", "\U0001F600", "\n", "\u0000", "a\n", "/", "\\", ":", ".", "..", "a/b", "a//b", "/a", "a/./b", "a/../b",
    "Walden/se-walden.epub", "Walden/se-walden.EPUB", "Walden/se-walde\u0301n.epub", "items/0.epub", "items/1.EPUB", "items/12345",
    "items/0.epub\n", "walden", "meditations-audio", "walden\n", "bad id", "epub", "audio", "cover", "pdf", "text", "markdown",
    "EPUB", "audiobook", "publication", "file_representation", "file_url", "share_extension", "sylviapack",
    "embedded_track", "filename", "user_confirmed", CANONICAL, CANONICAL.lower(), CANONICAL + "\u0000",
    CANONICAL + "\u0000junk", CANONICAL[:24] + "-" + CANONICAL[24:], "{" + CANONICAL + "}", CANONICAL + "\n",
    "2026-10-06T12:00:00Z", "2026-10-06t12:00:00z", "2026-10-06T12:00:00Z\n", "2026-02-30T12:00:00Z", "2026-10-06T12:00:00+1300",
    "ab" * 32, "AB" * 32, "ab" * 32 + "\n", "a" * 63, "\ud800", "x\udc00y",
    "a" * 35, "a" * 36, "a" * 64, "a" * 65, "a" * 128, "a" * 129, "a" * 255, "a" * 256, "a" * 512, "a" * 513,
    "a" * 1024, "a" * 1025, "\u00e9" * 35, "\u00e9" * 36, "\u00e9" * 128, "\u00e9" * 129, "\u00e9" * 256, "\u00e9" * 257,
    "\u00e9" * 127 + "a", "\u00e9" * 128 + "/b", "/".join(["d"] * 15), "/".join(["d"] * 16),
    # Separators inside a Swift Character (report F18): "/" + U+0301, U+0600 + "/".
    "../\u0301x", "/\u0301x", "a//\u0301b", "x\u0600/", "Walden/se-walden.epub/\u0301x", "/\u0301".join(["d"] * 16),
    "a/\u0301b", "x\u0301", "items/0\u0301.epub", "walden\u0301",
    # Canonical twins (review R4-01): the fuzz base's group ids, their U+212A spellings, and the other two twins.
    "WALDEN-K", "WALDEN-\u212a", "Meditations_K_audio", "Meditations_\u212a_audio", "K", "\u212a", "a;b", "a\u037eb",
    "a`b", "a\u1fefb",
]
NUMBERS = [0, 1, -1, 2, 3, 500, 501, 997147, 1.0, 1.5, -0.0, 1e19, 2 ** 53 + 1, 2 ** 63 - 1, 2 ** 63, 2 ** 64 - 1, 2 ** 64,
           10 ** 30, (1 << 30) + 1, 20 << 30, float("inf"), float("nan")]
VALUES = [None, True, False, [], {}, [""], [None], ["a"], [{"scheme": "isbn", "value": "1"}], {"a": 1}, {"name": "x", "version": "1"},
          *STRINGS, *NUMBERS]


def nodes(value, path=()):
    """Every (container, key) pair below the root, depth first."""
    if isinstance(value, dict):
        for key in list(value):
            yield value, key
            yield from nodes(value[key], path + (key,))
    elif isinstance(value, list):
        for index in range(len(value)):
            yield value, index
            yield from nodes(value[index], path + (index,))


def mutate(rng: random.Random, document) -> str:
    """One random edit of `document`; returns a description."""
    places = list(nodes(document))
    operation = rng.choice(["set", "set", "set-string", "set-number", "set-null", "delete", "add-unknown", "repeat-element",
                            "canonical-twin"])
    if operation == "canonical-twin":   # a string that holds K, ; or ` gets one of them in its twin's spelling (R4-01)
        holders = [(c, k) for c, k in places if isinstance(c[k], str) and any(a in c[k] for a in CANONICAL_TWINS)]
        if holders:
            container, key = rng.choice(holders)
            ascii_char = rng.choice([a for a in CANONICAL_TWINS if a in container[key]])
            container[key] = container[key].replace(ascii_char, CANONICAL_TWINS[ascii_char], 1)
            return f"canonical-twin {key!r}"
        operation = "set"
    if operation == "set-null":   # any member, known or not, set to an explicit null (review R3-01)
        members = [(c, k) for c, k in places if isinstance(c, dict)]
        container, key = rng.choice(members)
        container[key] = None
        return f"set-null {key!r}"
    if operation in ("set-string", "set-number"):
        wanted = str if operation == "set-string" else (int, float)
        typed = [(c, k) for c, k in places if isinstance(c[k], wanted) and not isinstance(c[k], bool)]
        if typed:
            container, key = rng.choice(typed)
            old = container[key]
            pool = STRINGS + ([old + "\n", old.upper(), old + "\u00e9", old * 2, old[:-1]] if isinstance(old, str) else [])
            pool = pool if isinstance(old, str) else NUMBERS + [old + 1, old - 1, old * 2, float(old)]
            container[key] = rng.choice(pool)
            return f"{operation} {key!r}"
        operation = "set"
    if operation == "delete":
        members = [(c, k) for c, k in places if isinstance(c, dict)]
        container, key = rng.choice(members)
        del container[key]
        return f"delete {key!r}"
    if operation == "add-unknown":
        objects = [document] + [c[k] for c, k in places if isinstance(c[k], dict)]
        target = rng.choice(objects)
        target[f"x_{rng.randrange(1000)}"] = copy.deepcopy(rng.choice(VALUES))
        return "add unknown member"
    if operation == "repeat-element":
        arrays = [c[k] for c, k in places if isinstance(c[k], list) and c[k]]
        if arrays:
            target = rng.choice(arrays)
            target.append(copy.deepcopy(rng.choice(target)))
            return "repeat an array element"
    container, key = rng.choice(places)
    container[key] = copy.deepcopy(rng.choice(VALUES))
    return f"set {key!r}"


if __name__ == "__main__":
    contracts_dir, work_dir, tool_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
    sys.exit(Check(contracts_dir, work_dir, tool_path).run())
