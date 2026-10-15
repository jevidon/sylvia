#!/usr/bin/env python3
"""Validate Swift-produced contract instances against Contracts/schemas (G0.5 AI spike).

Usage: validate-exports.py <Contracts dir> <export dir>

Every file in the export dir named "<schema name>.<instance>.json" is validated against
Contracts/schemas/<schema name>.v1.schema.json with the same validator stack as
Scripts/validate-contracts.py (JSON Schema 2020-12, format checking, $id registry).

ContextPack rules that JSON Schema cannot express (see the context-pack.v1 schema description) are then checked
on every exported pack and every committed valid context-pack fixture, independently of the Swift code:
  1. citation IDs are unique within the pack;
  2. pack_sha256 is the SHA-256 of json.dumps(pack with pack_sha256 "", sort_keys=True, separators=(",", ":"),
     ensure_ascii=False) encoded as UTF-8, and each text_sha256 is the SHA-256 of its text;
  3. with the spoiler boundary enabled, no evidence position or included turn lies after max_ordinal, every evidence
     item from the pack's work (its source text, and a saved thought or companion passage whose work_id is the pack's
     work) carries a position, no included turn has an unknown position, and every position and every included turn
     that used evidence (max_evidence_ordinal 0 or more) names the pack's edition (edition_id equal to
     work.edition_id), because ordinals count one edition's extracted paragraphs;
  4. every included turn's destination equals the pack's endpoint in origin, classification and model (an earlier
     answer is resent only to the destination that already received it).
The ProviderConfig rule JSON Schema cannot express (see the provider-config.v1 schema) is checked on every exported
configuration and every committed valid provider-config fixture:
  5. a credential_ref's origin equals the origin of base_url (scheme://host[:port], lowercase, default port omitted),
     so the key is bound to the origin it was entered for (plan 18.1).
A self-test first shows that each rule rejects an instance that breaks it, and that the schema rejects an included
answer that still carries a citation marker.
Exits non-zero if any instance fails or if no instances were found.
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012


def canonical_digest(pack: dict) -> str:
    blank = dict(pack, pack_sha256="")
    text = json.dumps(blank, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def pack_rule_problems(pack: dict) -> list[str]:
    problems = []
    ids = [item["citation_id"] for item in pack.get("evidence", [])]
    if len(ids) != len(set(ids)):
        problems.append(f"citation IDs are not unique: {ids}")
    for item in pack.get("evidence", []):
        if hashlib.sha256(item["text"].encode("utf-8")).hexdigest() != item["text_sha256"]:
            problems.append(f"{item['citation_id']}: text_sha256 does not match its text")
    if canonical_digest(pack) != pack.get("pack_sha256"):
        problems.append("pack_sha256 does not match the canonical serialization")
    boundary = pack.get("spoiler_boundary", {})
    if boundary.get("enabled"):
        limit = boundary.get("max_ordinal")
        if limit is None:
            problems.append("spoiler boundary enabled without max_ordinal")
        else:
            work_id = (pack.get("work") or {}).get("work_id")
            edition_id = (pack.get("work") or {}).get("edition_id")
            for item in pack.get("evidence", []):
                position = item.get("position")
                if position:
                    if item.get("edition_id") is None or item.get("edition_id") != edition_id:
                        problems.append(f"{item['citation_id']} has a position in another edition")
                    elif position["last_ordinal"] > limit:
                        problems.append(f"{item['citation_id']} ends at paragraph {position['last_ordinal']}, after the boundary {limit}")
                elif item["origin"] == "source_text" or (work_id is not None and item.get("work_id") == work_id):
                    problems.append(f"{item['citation_id']} is from this work but has no position")
            for turn in pack.get("history", {}).get("included_turns", []):
                turn_max = turn.get("max_evidence_ordinal")
                if turn_max is None:
                    problems.append(f"included turn {turn['turn_id']} has no known evidence position")
                elif turn_max >= 0 and (turn.get("edition_id") is None or turn.get("edition_id") != edition_id):
                    problems.append(f"included turn {turn['turn_id']} used paragraphs of another edition")
                elif turn_max > limit:
                    problems.append(f"included turn {turn['turn_id']} used paragraph {turn_max}, after the boundary {limit}")
    endpoint = pack.get("endpoint", {})
    for turn in pack.get("history", {}).get("included_turns", []):
        destination = turn.get("destination", {})
        if any(destination.get(key) != endpoint.get(key) for key in ("origin", "classification", "model")):
            problems.append(f"included turn {turn['turn_id']} was sent to {destination.get('origin')} "
                            f"({destination.get('classification')}, {destination.get('model')}), not to this pack's destination")
    return problems


def url_origin(url: str) -> str | None:
    """The origin as Swift's `Origin.description` writes it."""
    parts = urlsplit(url)
    if not parts.scheme or not parts.hostname:
        return None
    scheme, host = parts.scheme.lower(), parts.hostname.lower()
    host_part = f"[{host}]" if ":" in host else host
    port = parts.port
    if port is None or port == {"https": 443, "http": 80}.get(scheme):
        return f"{scheme}://{host_part}"
    return f"{scheme}://{host_part}:{port}"


def config_rule_problems(config: dict) -> list[str]:
    ref = config.get("credential_ref")
    if ref is None:
        return []
    expected = url_origin(config.get("base_url", ""))
    if ref.get("origin") != expected:
        return [f"credential_ref.origin {ref.get('origin')!r} is not the origin of base_url ({expected!r})"]
    return []


def config_self_test(sample: dict) -> int:
    """The credential-origin rule accepts the untouched sample and rejects a key bound to another origin."""
    if config_rule_problems(sample):
        print(f"self-test FAIL: the sample configuration breaks a rule: {config_rule_problems(sample)}")
        return 1
    moved = copy.deepcopy(sample)
    moved["base_url"] = "https://gateway.example.com/v1"
    port = copy.deepcopy(sample)
    port["base_url"] = sample["base_url"].replace("://api.openai.com", "://api.openai.com:8443")
    failures = 0
    for label, config in {"base URL moved to another host": moved, "base URL moved to another port": port}.items():
        if config_rule_problems(config):
            print(f"self-test ok: rejects a key bound to another origin ({label})")
        else:
            print(f"self-test FAIL: accepts a key bound to another origin ({label})")
            failures += 1
    return failures


def self_test(sample: dict, validator: Draft202012Validator) -> int:
    """Each code-checked rule must reject a pack that breaks it (and accept the untouched sample); the schema must reject
    an included answer that still carries a citation marker."""
    failures = 0
    if pack_rule_problems(sample):
        print(f"self-test FAIL: the sample pack breaks a rule: {pack_rule_problems(sample)}")
        return 1
    if not sample["history"]["included_turns"]:
        print("self-test FAIL: the sample pack has no included turn")
        return 1
    later = copy.deepcopy(sample)
    later["spoiler_boundary"]["max_ordinal"] = min(i["position"]["last_ordinal"] for i in later["evidence"] if i.get("position")) - 1
    later["pack_sha256"] = canonical_digest(later)
    unknown_turn = copy.deepcopy(sample)
    unknown_turn["history"]["included_turns"].append({"turn_id": "00000000-0000-4000-8000-000000000000", "question": "q", "answer": "a",
                                                      "shared_scopes": ["source_text"], "destination": copy.deepcopy(sample["endpoint"])})
    unknown_turn["pack_sha256"] = canonical_digest(unknown_turn)
    duplicate = copy.deepcopy(sample)
    duplicate["evidence"][1]["citation_id"] = duplicate["evidence"][0]["citation_id"]
    duplicate["pack_sha256"] = canonical_digest(duplicate)
    digest = copy.deepcopy(sample)
    digest["question"] += " (edited after hashing)"
    elsewhere = copy.deepcopy(sample)
    elsewhere["history"]["included_turns"][0]["destination"]["model"] = "another-model"
    elsewhere["pack_sha256"] = canonical_digest(elsewhere)
    # A saved note on this work: after the boundary, or with no position at all (review R4-06).
    limit = sample["spoiler_boundary"]["max_ordinal"]

    def with_thought(position: dict | None) -> dict:
        pack = copy.deepcopy(sample)
        thought = copy.deepcopy(pack["evidence"][0])
        thought.pop("retrieval", None)
        thought.update(citation_id=f"c{len(pack['evidence']) + 1}", role="thought", origin="user_note", source_quality="user_entered",
                       capture_id="00000000-0000-4000-8000-000000000001", work_id=pack["work"]["work_id"])
        if position is None:
            thought.pop("position", None)
        else:
            thought["position"] = position
        pack["evidence"].append(thought)
        pack["pack_sha256"] = canonical_digest(pack)
        return pack

    within_thought = with_thought(dict(sample["evidence"][0]["position"]))
    if pack_rule_problems(within_thought):
        print(f"self-test FAIL: rejects a thought within the boundary: {pack_rule_problems(within_thought)}")
        failures += 1
    else:
        print("self-test ok: accepts a thought on this work within the boundary")
    later_thought = with_thought(dict(sample["evidence"][0]["position"], first_ordinal=limit + 1, last_ordinal=limit + 1))
    unplaced_thought = with_thought(None)
    # A position or an included turn counted in another edition, though its ordinal is within the boundary (review R5-03).
    other_edition = "00000000-0000-4000-8000-0000000000ed"
    foreign_thought = with_thought(dict(sample["evidence"][0]["position"]))
    foreign_thought["evidence"][-1]["edition_id"] = other_edition
    foreign_thought["pack_sha256"] = canonical_digest(foreign_thought)
    foreign_turn = copy.deepcopy(sample)
    placed_turns = [t for t in foreign_turn["history"]["included_turns"] if t.get("max_evidence_ordinal") is not None and t["max_evidence_ordinal"] >= 0]
    if not placed_turns:
        print("self-test FAIL: the sample pack has no included turn that used evidence")
        return failures + 1
    placed_turns[0]["edition_id"] = other_edition
    foreign_turn["pack_sha256"] = canonical_digest(foreign_turn)
    cases = {"evidence after the boundary": later, "turn with unknown position": unknown_turn,
             "duplicate citation ID": duplicate, "stale digest": digest, "turn sent to another destination": elsewhere,
             "thought on this work after the boundary": later_thought, "thought on this work without a position": unplaced_thought,
             "thought positioned in another edition": foreign_thought, "turn that used another edition": foreign_turn}
    for label, pack in cases.items():
        if pack_rule_problems(pack):
            print(f"self-test ok: rejects {label}")
        else:
            print(f"self-test FAIL: accepts {label}")
            failures += 1
    marker = copy.deepcopy(sample)
    marker["history"]["included_turns"][0]["answer"] += " [c1]"
    marker["pack_sha256"] = canonical_digest(marker)
    if any(error.validator == "not" for error in validator.iter_errors(marker)):
        print("self-test ok: the schema rejects an included answer with a citation marker")
    else:
        print("self-test FAIL: the schema accepts an included answer with a citation marker")
        failures += 1
    return failures


def main(contracts: Path, exports: Path) -> int:
    schemas = {}
    for path in sorted((contracts / "schemas").glob("*.schema.json")):
        schema = json.loads(path.read_text(encoding="utf-8"))
        schemas[schema["$id"]] = schema
    registry = Registry().with_resources(
        (schema_id, Resource.from_contents(schema, default_specification=DRAFT202012)) for schema_id, schema in schemas.items()
    )
    failures = 0
    checked = 0
    packs: list[tuple[str, dict]] = []
    configs: list[tuple[str, dict]] = []
    for instance_path in sorted(exports.glob("*.json")):
        name = instance_path.name.split(".")[0]
        schema_id = f"urn:sylvia:schema:{name}:v1"
        schema = schemas.get(schema_id)
        if schema is None:
            print(f"error: {instance_path.name}: no schema {schema_id}")
            failures += 1
            continue
        validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
        instance = json.loads(instance_path.read_text(encoding="utf-8"))
        problems = sorted(validator.iter_errors(instance), key=lambda e: list(e.absolute_path))
        checked += 1
        if problems:
            failures += 1
            first = problems[0]
            location = "/".join(str(p) for p in first.absolute_path) or "(root)"
            print(f"FAIL {instance_path.name}: {location}: {first.message[:300]}")
        else:
            print(f"ok   {instance_path.name}")
        if name == "context-pack":
            packs.append((f"export {instance_path.name}", instance))
        elif name == "provider-config":
            configs.append((f"export {instance_path.name}", instance))
    print(f"validated {checked} exported instances against the schemas, {failures} failed")
    if checked == 0:
        print("error: no exported instances found")
        return 1

    for path in sorted((contracts / "fixtures" / "context-pack.v1" / "valid").glob("*.json")):
        packs.append((f"fixture {path.name}", json.loads(path.read_text(encoding="utf-8"))))
    sample = next((pack for label, pack in packs if label.endswith("work-search-restricted.json")), None)
    if sample is None:
        print("error: no work-search-restricted pack for the self-test")
        return 1
    pack_validator = Draft202012Validator(schemas["urn:sylvia:schema:context-pack:v1"], registry=registry, format_checker=FormatChecker())
    failures += self_test(sample, pack_validator)
    rule_failures = 0
    for label, pack in packs:
        problems = pack_rule_problems(pack)
        if problems:
            rule_failures += 1
            print(f"FAIL {label}: {'; '.join(problems)[:400]}")
        else:
            print(f"ok   {label}: citation IDs unique, digests match the canonical serialization, spoiler boundary holds, "
                  f"{len(pack.get('history', {}).get('included_turns', []))} included turn(s) from this destination")
    print(f"checked the code-checked ContextPack rules on {len(packs)} packs, {rule_failures} failed")
    failures += rule_failures

    for path in sorted((contracts / "fixtures" / "provider-config.v1" / "valid").glob("*.json")):
        configs.append((f"fixture {path.name}", json.loads(path.read_text(encoding="utf-8"))))
    config_sample = next((config for label, config in configs if label.endswith("openai-hosted.json")), None)
    if config_sample is None:
        print("error: no openai-hosted configuration for the self-test")
        return 1
    failures += config_self_test(config_sample)
    config_failures = 0
    for label, config in configs:
        problems = config_rule_problems(config)
        if problems:
            config_failures += 1
            print(f"FAIL {label}: {'; '.join(problems)}")
        else:
            print(f"ok   {label}: " + (f"key bound to {config['credential_ref']['origin']}, the origin of base_url"
                                       if config.get("credential_ref") else "no key"))
    print(f"checked the code-checked ProviderConfig rule on {len(configs)} configurations, {config_failures} failed")
    failures += config_failures
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
