#!/usr/bin/env bash
# Regenerates the G0.2 transfer contract fixtures (small JSON files, committed) deterministically:
#
#   Contracts/fixtures/<schema>.v1/{valid,invalid}/*.json         checked against the JSON Schemas
#   Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/Fixtures/manifests/semantic-invalid/*.json
#       manifests that are valid against the JSON Schema but break a rule only the Swift
#       semantic validator can check (part continuity, digest, cover reference, ...)
#
# Manifest digests and part digests are computed here, in Python, from deterministic bytes, so the
# Swift validator is checked against an independent implementation of the digest definition
# (ADR-0009). Running the script twice produces identical files.
#
#   Scripts/fixtures/generate-g02-transfer-contract-fixtures.sh
#   Scripts/fixtures/generate-g02-transfer-contract-fixtures.sh --check   # exit 1 if files would change
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
exec /usr/bin/python3 - "$SYLVIA_ROOT" "${1:-}" <<'PY'
import copy, hashlib, json, sys
from pathlib import Path

root = Path(sys.argv[1])
check = sys.argv[2] == "--check"
contracts = root / "Contracts" / "fixtures"
semantic = root / "Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/Fixtures/manifests/semantic-invalid"
MIB = 1048576
SOURCE = "5a1e0c3e-7d2b-4c1a-9f00-000000000001"
changed = []

def uid(n):
    return f"00000000-0000-4000-8000-{n:012x}"

def content(seed, length):
    # Deterministic bytes: SHA-256 counter stream of the seed.
    out = bytearray()
    counter = 0
    while len(out) < length:
        out += hashlib.sha256(f"{seed}:{counter}".encode()).digest()
        counter += 1
    return bytes(out[:length])

def asset(seed, ordinal, name, media, length, part_size=MIB):
    data = content(seed, length)
    parts = []
    offset = 0
    index = 0
    while offset < length:
        size = min(part_size, length - offset)
        parts.append({"index": index, "offset": offset, "length": size,
                      "sha256": hashlib.sha256(data[offset:offset + size]).hexdigest()})
        offset += size
        index += 1
    digest = hashlib.sha256(data).hexdigest()
    return {"asset_id": uid(0x100 + seed), "ordinal": ordinal, "display_name": name, "media_type": media,
            "length": length, "etag": f'"sha256-{digest}"', "sha256": digest, "part_size": part_size,
            "parts": parts}

def digest_input(m):
    v = m["protocol_version"]
    lines = ["sylvia-transfer-manifest-v1", f"protocol={v['major']}.{v['minor']}", f"source={m['source_id']}",
             f"item={m['item_id']}", f"version={m['item_version_id']}",
             f"cover={m.get('cover_asset_id') or '-'}", f"assets={len(m['assets'])}"]
    for a in m["assets"]:
        lines.append(f"asset={a['ordinal']},{a['asset_id']},{a['media_type']},{a['length']},{a.get('etag', '')},"
                     f"{a['sha256']},{a['part_size']},{len(a['parts'])}")
        for p in a["parts"]:
            lines.append(f"part={p['index']},{p['offset']},{p['length']},{p['sha256']}")
    return "".join(line + "\n" for line in lines)

def seal(m):
    m["manifest_digest"] = hashlib.sha256(digest_input(m).encode()).hexdigest()
    return m

def manifest(item, version, kind, title, assets, creators=None, cover=None):
    m = {"schema_version": 1, "protocol_version": {"major": 1, "minor": 0}, "source_id": SOURCE,
         "item_id": uid(item), "item_version_id": uid(version), "created_at": "2026-10-06T09:00:00Z",
         "manifest_digest": "", "grouping": {"kind": kind, "title": title}}
    if creators:
        m["grouping"]["creators"] = creators
    if cover:
        m["cover_asset_id"] = cover
    m["assets"] = assets
    return seal(m)

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if not path.exists() or path.read_text(encoding="utf-8") != text:
        changed.append(str(path.relative_to(root)))
        if not check:
            path.write_text(text, encoding="utf-8")

# ---------------- transfer-manifest ----------------
single = manifest(1, 2, "single", "Walden", [asset(1, 0, "walden.epub", "application/epub+zip", 2 * MIB + MIB // 2)],
                  creators=["Henry David Thoreau"])
exact = manifest(3, 4, "single", "Exact multiple", [asset(2, 0, "exact.pdf", "application/pdf", 2 * MIB)])
group = manifest(5, 6, "group", "Meditations (LibriVox)", [
    asset(3, 0, "01 - Book One.mp3", "audio/mpeg", 3 * MIB + 17),
    asset(4, 1, "02 - Book Two.mp3", "audio/mpeg", MIB + 1),
    asset(5, 2, "cover.jpg", "image/jpeg", 40_000),
], creators=["Marcus Aurelius", "George Long"], cover=uid(0x105))
tolerant = copy.deepcopy(single)
tolerant["future_optional_field"] = {"note": "readers ignore unknown optional fields"}
tolerant["assets"][0]["future_asset_field"] = True

base = contracts / "transfer-manifest.v1"
write(base / "valid/single-epub.json", single)
write(base / "valid/single-exact-part-multiple.json", exact)
write(base / "valid/group-audiobook-with-cover.json", group)
write(base / "valid/unknown-optional-fields-tolerated.json", tolerant)

def variant(src, mutate, reseal=True):
    m = copy.deepcopy(src)
    mutate(m)
    return seal(m) if reseal else m

invalid = {
    # Only the length changes, so the fixture fails the schema's length minimum alone (Contracts/README.md: one reason
    # per file; contracts review R1-03: with its parts emptied too it also failed parts minItems). That its parts no
    # longer add up to the length is a code-checked rule, not a schema one.
    "zero-length-asset": lambda m: m["assets"][0].update(length=0),
    "unsupported-major-version": lambda m: m["protocol_version"].update(major=2),
    "weak-etag": lambda m: m["assets"][0].update(etag="W/" + m["assets"][0]["etag"]),
    "missing-etag": lambda m: m["assets"][0].pop("etag"),
    "part-size-not-whole-mib": lambda m: m["assets"][0].update(part_size=MIB + 1),
    "uppercase-digest": lambda m: m["assets"][0].update(sha256=m["assets"][0]["sha256"].upper()),
    "no-assets": lambda m: m.update(assets=[]),
    "negative-offset": lambda m: m["assets"][0]["parts"][0].update(offset=-1),
    "zero-length-part": lambda m: m["assets"][0]["parts"][1].update(length=0),
    "display-name-is-path": lambda m: m["assets"][0].update(display_name="../../etc/passwd"),
    "control-character-in-title": lambda m: m["grouping"].update(title="Walden\u0007"),
    "length-beyond-json-safe-integer": lambda m: m["assets"][0].update(length=9007199254740992),
    "uppercase-uuid": lambda m: m.update(item_id="ABCDEF00-0000-4000-8000-00000000000A"),
    "missing-manifest-digest": lambda m: m.pop("manifest_digest"),
}
for name, mutate in invalid.items():
    write(base / f"invalid/{name}.json", variant(single, mutate, reseal=name != "missing-manifest-digest"))

def part(m, i):
    return m["assets"][0]["parts"][i]

semantic_cases = {
    # Each stays valid against the JSON Schema (checked in CI) and is re-sealed so only the named rule fails.
    "duplicate-part": lambda m: m["assets"][0]["parts"].insert(2, copy.deepcopy(part(m, 1))),
    "overlapping-parts": lambda m: (part(m, 1).update(offset=MIB - 4096)),
    "gap-between-parts": lambda m: (part(m, 1).update(offset=MIB + 4096)),
    "missing-final-bytes": lambda m: m["assets"][0]["parts"].pop(),
    "inconsistent-total-length": lambda m: m["assets"][0].update(length=m["assets"][0]["length"] + 10),
    "parts-exceed-length": lambda m: m["assets"][0].update(length=m["assets"][0]["length"] - 10),
    "short-non-final-part": lambda m: part(m, 0).update(length=MIB - 1),
    "parts-out-of-order": lambda m: m["assets"][0]["parts"].reverse(),
    "cover-not-in-assets": lambda m: m.update(cover_asset_id=uid(0xdead)),
    "single-with-two-assets": lambda m: m["assets"].append(dict(asset(9, 1, "extra.epub", "application/epub+zip", MIB))),
}
for name, mutate in semantic_cases.items():
    write(semantic / f"{name}.json", variant(single, mutate))
# Digest mismatch: change a part digest without re-sealing.
tampered = copy.deepcopy(single)
part(tampered, 0)["sha256"] = "0" * 64
write(semantic / "manifest-digest-mismatch.json", tampered)
# Group cases.
write(semantic / "duplicate-asset-id.json", variant(group, lambda m: m["assets"][1].update(asset_id=m["assets"][0]["asset_id"])))
write(semantic / "ordinal-not-array-position.json", variant(group, lambda m: m["assets"][1].update(ordinal=5)))
write(semantic / "different-source.json", variant(single, lambda m: m.update(source_id=uid(0xbad))))

# ---------------- pairing-payload ----------------
SPKI = hashlib.sha256(b"fixture spki").hexdigest()
secret = "q7Hc0bJx2mVt9Wd4LkPz8Rn1Ys6Ea3Gu5Fi0Oh2Tj4M"  # 32 bytes as unpadded base64url (fixture only)
payload = {"schema_version": 1, "protocol_version": {"major": 1, "minor": 0}, "source_id": SOURCE,
           "source_name": "Study Mac", "endpoints": [{"host": "192.168.1.20", "port": 48211},
           {"host": "study-mac.tail1234.ts.net", "port": 48211}, {"host": "fd7a:115c:a1e0::1", "port": 48211}],
           "spki_sha256": SPKI, "invitation_id": uid(0x900), "invitation_secret": secret,
           "expires_at": "2026-10-06T09:10:00Z"}
base = contracts / "pairing-payload.v1"
write(base / "valid/lan-tailscale-ipv6.json", payload)
write(base / "valid/single-loopback-endpoint.json", {**payload, "endpoints": [{"host": "127.0.0.1", "port": 50001}]})
pp_invalid = {
    "secret-under-128-bits": {**payload, "invitation_secret": "c2hvcnQtc2VjcmV0"},
    "uppercase-pin": {**payload, "spki_sha256": SPKI.upper()},
    "missing-pin": {k: v for k, v in payload.items() if k != "spki_sha256"},
    "port-zero": {**payload, "endpoints": [{"host": "192.168.1.20", "port": 0}]},
    "no-endpoints": {**payload, "endpoints": []},
    "host-with-path": {**payload, "endpoints": [{"host": "evil.example/pair", "port": 443}]},
    "unsupported-major-version": {**payload, "protocol_version": {"major": 2, "minor": 0}},
    "padded-base64-secret": {**payload, "invitation_secret": secret + "="},
    "local-time-expiry": {**payload, "expires_at": "2026-10-06T09:10:00+13:00"},
}
for name, value in pp_invalid.items():
    write(base / f"invalid/{name}.json", value)

# ---------------- pair-request / pair-response ----------------
request = {"schema_version": 1, "invitation_id": uid(0x900), "invitation_secret": secret, "source_id": SOURCE,
           "device_id": uid(0xd01), "device_name": "Justin's iPhone"}
base = contracts / "pair-request.v1"
write(base / "valid/pair-request.json", request)
write(base / "invalid/missing-secret.json", {k: v for k, v in request.items() if k != "invitation_secret"})
write(base / "invalid/uppercase-device-id.json", {**request, "device_id": uid(0xd01).upper()})
write(base / "invalid/control-character-in-device-name.json", {**request, "device_name": "iPhone\n"})

token = "Zm9yLWZpeHR1cmUtb25seS1ub3QtYS1yZWFsLXRva2Vu"  # fixture only
response = {"schema_version": 1, "source_id": SOURCE, "device_id": uid(0xd01), "token": token, "token_type": "bearer",
            "scopes": ["catalog", "read", "download", "receipt"], "spki_sha256": SPKI, "paired_at": "2026-10-06T09:02:13Z"}
base = contracts / "pair-response.v1"
write(base / "valid/pair-response.json", response)
write(base / "invalid/delete-scope.json", {**response, "scopes": ["catalog", "delete"]})
write(base / "invalid/short-token.json", {**response, "token": "c2hvcnQ"})
write(base / "invalid/basic-token-type.json", {**response, "token_type": "basic"})

# ---------------- capabilities ----------------
caps = {"schema_version": 1, "protocol_version": {"major": 1, "minor": 0}, "supported_major_versions": [1],
        "source_id": SOURCE, "part_size": {"default_bytes": 16 * MIB, "min_bytes": MIB, "max_bytes": 64 * MIB},
        "limits": {"max_parts_per_asset": 16384, "max_parts_per_manifest": 65536, "max_assets_per_item": 4096,
                   "max_page_limit": 200, "max_request_body_bytes": 65536},
        "auth_scheme": "bearer", "scopes": ["catalog", "read", "download", "receipt"], "pin_algorithm": "spki-sha256"}
base = contracts / "capabilities.v1"
write(base / "valid/capabilities.json", caps)
write(base / "invalid/part-size-not-whole-mib.json", {**caps, "part_size": {"default_bytes": 16 * MIB + 1, "min_bytes": MIB, "max_bytes": 64 * MIB}})
write(base / "invalid/basic-auth.json", {**caps, "auth_scheme": "basic"})
write(base / "invalid/missing-supported-majors.json", {k: v for k, v in caps.items() if k != "supported_major_versions"})

# ---------------- catalog-page ----------------
items = [
    {"item_id": uid(1), "kind": "single", "title": "Walden", "asset_count": 1, "total_bytes": 2 * MIB + MIB // 2,
     "modified_at": "2026-10-01T08:00:00Z", "current_version_id": uid(2), "preparation_state": "ready"},
    {"item_id": uid(5), "kind": "group", "title": "Meditations (LibriVox)", "asset_count": 3, "total_bytes": 4 * MIB + 40_018,
     "modified_at": "2026-10-02T08:00:00Z", "current_version_id": None, "preparation_state": "not_prepared"},
]
base = contracts / "catalog-page.v1"
write(base / "valid/first-page.json", {"schema_version": 1, "items": items, "next_cursor": "eyJhZnRlciI6IjEifQ"})
write(base / "valid/last-page.json", {"schema_version": 1, "items": [], "next_cursor": None})
write(base / "invalid/missing-next-cursor.json", {"schema_version": 1, "items": items})
write(base / "invalid/unknown-preparation-state.json",
      {"schema_version": 1, "items": [{**items[0], "preparation_state": "copying"}], "next_cursor": None})

# ---------------- device-inbox-page ----------------
entries = [
    {"queue_entry_id": uid(0xe01), "item_id": uid(1), "item_version_id": uid(2), "title": "Walden",
     "total_bytes": 2 * MIB + MIB // 2, "queued_at": "2026-10-06T08:55:00Z", "state": "observed_by_phone"},
    {"queue_entry_id": uid(0xe02), "item_id": uid(5), "item_version_id": None, "title": "Meditations (LibriVox)",
     "total_bytes": 4 * MIB + 40_018, "queued_at": "2026-10-06T08:56:00Z", "state": "queued_on_mac"},
]
base = contracts / "device-inbox-page.v1"
write(base / "valid/entries.json", {"schema_version": 1, "entries": entries, "next_cursor": None})
write(base / "invalid/deleted-state.json",
      {"schema_version": 1, "entries": [{**entries[0], "state": "deleted"}], "next_cursor": None})
write(base / "invalid/missing-item-version.json",
      {"schema_version": 1, "entries": [{k: v for k, v in entries[0].items() if k != "item_version_id"}], "next_cursor": None})

# ---------------- receipt ----------------
receipt = {"schema_version": 1, "receipt_id": uid(0xa01), "queue_entry_id": uid(0xe01), "item_id": uid(1),
           "item_version_id": uid(2), "state": "downloaded_to_phone", "occurred_at": "2026-10-06T09:05:00Z"}
base = contracts / "receipt.v1"
write(base / "valid/downloaded-to-phone.json", receipt)
write(base / "valid/imported-into-sylvia.json", {**receipt, "receipt_id": uid(0xa02), "state": "imported_into_sylvia"})
write(base / "valid/import-failed.json", {**receipt, "receipt_id": uid(0xa03), "state": "import_failed",
      "failure": {"code": "unsupported_format", "message": "The file could not be opened as an EPUB."}})
write(base / "valid/catalog-download-without-queue-entry.json", {**receipt, "receipt_id": uid(0xa04), "queue_entry_id": None})
write(base / "invalid/queued-on-mac-is-not-a-receipt.json", {**receipt, "state": "queued_on_mac"})
write(base / "invalid/import-failed-without-failure.json", {**receipt, "state": "import_failed"})
write(base / "invalid/failure-on-success.json", {**receipt, "failure": {"code": "x", "message": "unexpected"}})
write(base / "invalid/missing-receipt-id.json", {k: v for k, v in receipt.items() if k != "receipt_id"})

# ---------------- receipt acknowledgement (the 200 body of POST /v1/receipts) ----------------
# Its schema was inline in the OpenAPI document until the M0 final fix (contracts review R1-06).
ack = {"schema_version": 1, "receipt_id": uid(0xa01), "queue_entry_id": uid(0xe01), "entry_state": "downloaded_to_phone",
       "duplicate": False}
base = contracts / "receipt-ack.v1"
write(base / "valid/downloaded-to-phone.json", ack)
write(base / "valid/duplicate-of-a-recorded-receipt.json", {**ack, "duplicate": True})
write(base / "valid/catalog-download-without-queue-entry.json",
      {**ack, "receipt_id": uid(0xa04), "queue_entry_id": None, "entry_state": None})
write(base / "invalid/missing-duplicate.json", {k: v for k, v in ack.items() if k != "duplicate"})
# null is written, never left out (the Swift ReceiptAck encodes both fields explicitly).
write(base / "invalid/entry-state-left-out.json", {k: v for k, v in ack.items() if k != "entry_state"})
write(base / "invalid/deleted-entry-state.json", {**ack, "entry_state": "deleted"})
write(base / "invalid/uppercase-receipt-id.json", {**ack, "receipt_id": uid(0xa01).upper()})
# The two mixed forms the server never writes: a named entry without its state, a state without an entry (M0 final
# review round 2, contracts R2-05).
write(base / "invalid/queue-entry-without-entry-state.json", {**ack, "entry_state": None})
write(base / "invalid/entry-state-without-queue-entry.json",
      {**ack, "receipt_id": uid(0xa04), "queue_entry_id": None, "entry_state": "imported_into_sylvia"})

# ---------------- error ----------------
base = contracts / "error.v1"
write(base / "valid/precondition-failed.json", {"schema_version": 1, "error": {"code": "precondition_failed",
      "message": "The file changed on the Mac. Fetch the manifest again.", "retryable": False}})
write(base / "valid/rate-limited.json", {"schema_version": 1, "error": {"code": "rate_limited",
      "message": "Too many pairing attempts. Try again later.", "retryable": True, "retry_after_seconds": 60}})
write(base / "invalid/uppercase-code.json", {"schema_version": 1, "error": {"code": "PreconditionFailed",
      "message": "x", "retryable": False}})
write(base / "invalid/missing-retryable.json", {"schema_version": 1, "error": {"code": "not_found", "message": "x"}})

if check and changed:
    print("fixtures out of date:\n  " + "\n  ".join(changed))
    sys.exit(1)
print(("checked" if check else "wrote") + f" fixtures; {len(changed)} changed")
PY
