#!/usr/bin/env python3
"""Generate the committed G0.5 contract fixtures (context-pack.v1, provider-config.v1).

Usage: make-contract-fixtures.py <export dir> <Contracts dir>

Valid fixtures are copied from instances the Swift code produced (ContractExportTests with
G05_CONTRACT_EXPORT set). The export is deterministic: ContractExportTests replaces every UUID with one derived
from the instance name and recomputes the pack digest, and the build time is fixed, so re-running the export and
this script reproduces the committed files byte for byte (`git diff --exit-code Contracts/fixtures` after a run).
Invalid fixtures are each one named mutation of a valid fixture, chosen so that only the rule the file is named
for rejects it; Spikes/G05-AI/Scripts/explain-invalid-fixtures.py checks that every schema error of each invalid
fixture comes from that rule. Mutated packs keep a valid pack_sha256 so the digest is never a second reason.
Fixture text comes from the Standard Ebooks editions in Fixtures/LICENSES.md (public domain; CC0 contributions).
"""
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import sys
from pathlib import Path


def write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def redigest(pack: dict) -> dict:
    """Recomputes pack_sha256 as the schema description defines it, so a mutated pack fails only for its mutation."""
    blank = dict(pack, pack_sha256="")
    pack["pack_sha256"] = hashlib.sha256(
        json.dumps(blank, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()
    return pack


def main(exports: Path, contracts: Path) -> int:
    pack_dir = contracts / "fixtures" / "context-pack.v1"
    config_dir = contracts / "fixtures" / "provider-config.v1"
    for directory in (pack_dir, config_dir):
        if directory.exists():
            shutil.rmtree(directory)

    packs = {}
    for name in ["selected-passage", "passage-and-nearby", "work-search-restricted", "work-search-truncated", "selected-thoughts",
                 "work-search-no-position", "selected-thoughts-audio-unavailable", "selected-thoughts-restricted"]:
        packs[name] = json.loads((exports / f"context-pack.{name}.json").read_text(encoding="utf-8"))
        write(pack_dir / "valid" / f"{name}.json", packs[name])
    configs = {}
    for name in ["openai-hosted", "anthropic-hosted", "local-generic-http", "gateway-declared-hosted", "transcription-timestamps"]:
        configs[name] = json.loads((exports / f"provider-config.{name}.json").read_text(encoding="utf-8"))
        write(config_dir / "valid" / f"{name}.json", configs[name])

    def pack(base: str, mutate) -> dict:
        data = copy.deepcopy(packs[base])
        mutate(data)
        return redigest(data)

    def config(base: str, mutate) -> dict:
        data = copy.deepcopy(configs[base])
        mutate(data)
        return data

    invalid_packs = {
        "missing-question": pack("selected-passage", lambda d: d.pop("question")),
        "secret-field-in-endpoint": pack("selected-passage", lambda d: d["endpoint"].__setitem__("api_key", "sk-fixture-not-a-real-key")),
        "bad-citation-id": pack("selected-passage", lambda d: d["evidence"][0].__setitem__("citation_id", "source-1")),
        "empty-evidence-text": pack("selected-passage", lambda d: d["evidence"][0].__setitem__("text", "")),
        "scope-label-whole-book-for-selection": pack("selected-passage", lambda d: d.__setitem__("scope_label", "Whole book")),
        "heuristic-estimate-not-labelled": pack("selected-passage", lambda d: d["budget"].__setitem__("estimated", False)),
        "work-search-claims-excerpt-coverage": pack("work-search-restricted", lambda d: d.update(coverage="excerpt_only", coverage_label="Excerpt only")),
        "spoiler-enabled-without-max-ordinal": pack("work-search-restricted", lambda d: d["spoiler_boundary"].pop("max_ordinal")),
        "history-excluded-without-reason": pack("work-search-restricted", lambda d: d["history"].pop("exclusion_reason")),
        "retrieved-evidence-without-score": pack("work-search-restricted", lambda d: d["evidence"][0].pop("retrieval")),
        "truncated-without-disclosure": pack("work-search-truncated", lambda d: d["truncation"].pop("disclosure")),
        "note-without-capture-id": pack("selected-thoughts", lambda d: d["evidence"][1].pop("capture_id")),
        "whole-work-with-spoiler-boundary": pack("selected-passage", lambda d: d.update(
            scope="whole_work", scope_label="Whole book", coverage="whole_work", coverage_label="Whole book included",
            spoiler_boundary={"enabled": True, "max_ordinal": 40, "basis": "user_confirmed_position", "excluded_evidence_count": 0})),
        "empty-pack-without-stated-limitation": pack("work-search-no-position", lambda d: d.__setitem__("limitations", [])),
        "no-passages-coverage-with-evidence": pack("work-search-restricted", lambda d: d.update(coverage="no_passages", coverage_label="No passages sent")),
        "coverage-label-mismatch": pack("selected-passage", lambda d: d.__setitem__("coverage_label", "Relevant passages retrieved")),
        "unknown-limitation-code": pack("selected-thoughts-audio-unavailable", lambda d: d["limitations"][0].__setitem__("code", "model_should_explain")),
        # An earlier answer resent with its own citation marker, which would resolve against this pack's c1 (R2-03).
        "history-answer-with-citation-marker": pack("work-search-restricted", lambda d: d["history"]["included_turns"][0].__setitem__(
            "answer", d["history"]["included_turns"][0]["answer"].replace("[earlier source]", "[c1]"))),
        # An earlier turn that does not say what it shared, so consent could not cover it (R2-02).
        "history-turn-without-shared-scopes": pack("work-search-restricted", lambda d: d["history"]["included_turns"][0].pop("shared_scopes")),
        # A position that does not say which edition's paragraphs it counts (R5-03).
        "position-without-edition": pack("selected-passage", lambda d: d["evidence"][0].pop("edition_id")),
        # An earlier turn that used evidence without saying which edition its position counts in (R5-03).
        "history-turn-without-edition": pack("work-search-restricted", lambda d: d["history"]["included_turns"][0].pop("edition_id")),
    }
    for name, data in invalid_packs.items():
        write(pack_dir / "invalid" / f"{name}.json", data)

    invalid_configs = {
        "api-key-field": config("openai-hosted", lambda d: d.__setitem__("api_key", "sk-fixture-not-a-real-key")),
        "credential-ref-with-value": config("openai-hosted", lambda d: d["credential_ref"].__setitem__("value", "sk-fixture-not-a-real-key")),
        # A key reference that does not say which origin the key was entered for (R4-02, plan 18.1).
        "credential-ref-without-origin": config("openai-hosted", lambda d: d["credential_ref"].pop("origin")),
        "unknown-provider-kind": config("gateway-declared-hosted", lambda d: d.__setitem__("provider_kind", "openai_assistants")),
        "query-in-base-url": config("gateway-declared-hosted", lambda d: d.__setitem__("base_url", "https://gateway.example.com/api/v1?key=abc")),
        "doubled-version-in-base-url": config("gateway-declared-hosted", lambda d: d.__setitem__("base_url", "https://gateway.example.com/api/v1/v1")),
        "endpoint-path-in-base-url": config("gateway-declared-hosted", lambda d: d.__setitem__("base_url", "https://gateway.example.com/api/v1/chat/completions")),
        "http-without-opt-in": config("local-generic-http", lambda d: d.__setitem__("allow_insecure_local_http", False)),
        "http-to-a-public-name": config("local-generic-http", lambda d: d.__setitem__("base_url", "http://gateway.example.com/v1")),
        "http-to-dot-local-name": config("local-generic-http", lambda d: d.__setitem__("base_url", "http://studio.local:1234/v1")),
        "http-local-declared-hosted": config("local-generic-http", lambda d: d.__setitem__("privacy_classification", "hosted")),
        # Everything the cleartext rule allows (opt-in, local class, a local IP literal) except the adapter: only the
        # first-party rules reject it.
        "first-party-over-http": config("local-generic-http", lambda d: d.update(provider_kind="openai_responses", privacy_classification="local")),
    }
    for name, data in invalid_configs.items():
        write(config_dir / "invalid" / f"{name}.json", data)
    print(f"wrote {len(packs)} + {len(invalid_packs)} context-pack and {len(configs)} + {len(invalid_configs)} provider-config fixtures")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
