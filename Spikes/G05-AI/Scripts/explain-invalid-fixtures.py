#!/usr/bin/env python3
"""Show that each invalid G0.5 contract fixture fails for the one reason it is named for.

Usage: explain-invalid-fixtures.py <Contracts dir>   (run with the tools venv: sylvia_python)

Lists every schema error of each invalid fixture, then checks it against EXPECTED: every error must come from the
rule the fixture is named for (its schema keyword path, with allOf indices ignored, and the property involved).
Exits non-zero if an invalid fixture validates, raises an error from any other rule, or has no expectation here.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

# fixture -> the rule it violates: (schema keyword path with "allOf/N", text that must appear in the error message).
# first-party-over-http breaks the one rule "first-party adapters never use cleartext", which the schema states twice
# (the cleartext clause lists the adapters allowed over http; the first-party clause requires https).
EXPECTED: dict[str, list[tuple[str, str]]] = {
    "context-pack.v1/bad-citation-id.json": [("properties/evidence/items/properties/citation_id/pattern", "source-1")],
    "context-pack.v1/coverage-label-mismatch.json": [("allOf/N/then/properties/coverage_label/const", "Excerpt only")],
    "context-pack.v1/empty-evidence-text.json": [("properties/evidence/items/properties/text/minLength", "non-empty")],
    "context-pack.v1/empty-pack-without-stated-limitation.json": [("allOf/N/then/anyOf", "")],
    "context-pack.v1/heuristic-estimate-not-labelled.json": [("properties/budget/then/properties/estimated/const", "True")],
    "context-pack.v1/history-answer-with-citation-marker.json": [("properties/history/properties/included_turns/items/properties/answer/not", "[c1]")],
    "context-pack.v1/history-excluded-without-reason.json": [("properties/history/then/required", "exclusion_reason")],
    "context-pack.v1/history-turn-without-shared-scopes.json": [("properties/history/properties/included_turns/items/required", "shared_scopes")],
    "context-pack.v1/history-turn-without-edition.json": [("properties/history/properties/included_turns/items/then/required", "edition_id")],
    "context-pack.v1/position-without-edition.json": [("properties/evidence/items/dependentRequired", "edition_id")],
    "context-pack.v1/missing-question.json": [("required", "'question'")],
    "context-pack.v1/no-passages-coverage-with-evidence.json": [("allOf/N/then/properties/evidence/maxItems", "")],
    "context-pack.v1/note-without-capture-id.json": [("properties/evidence/items/allOf/N/then/required", "capture_id")],
    "context-pack.v1/retrieved-evidence-without-score.json": [("properties/evidence/items/allOf/N/then/required", "retrieval")],
    "context-pack.v1/scope-label-whole-book-for-selection.json": [("allOf/N/then/properties/scope_label/const", "Selected passage")],
    "context-pack.v1/secret-field-in-endpoint.json": [("properties/endpoint/propertyNames/not", "api_key")],
    "context-pack.v1/spoiler-enabled-without-max-ordinal.json": [("properties/spoiler_boundary/allOf/N/then/required", "max_ordinal")],
    "context-pack.v1/truncated-without-disclosure.json": [("properties/truncation/then/required", "disclosure")],
    "context-pack.v1/unknown-limitation-code.json": [("properties/limitations/items/properties/code/enum", "model_should_explain")],
    "context-pack.v1/whole-work-with-spoiler-boundary.json": [("allOf/N/then/properties/spoiler_boundary/properties/enabled/const", "False")],
    "context-pack.v1/work-search-claims-excerpt-coverage.json": [("allOf/N/then/properties/coverage/enum", "excerpt_only")],
    "provider-config.v1/api-key-field.json": [("propertyNames/not", "api_key")],
    "provider-config.v1/credential-ref-with-value.json": [("properties/credential_ref/additionalProperties", "value")],
    "provider-config.v1/credential-ref-without-origin.json": [("properties/credential_ref/required", "'origin'")],
    "provider-config.v1/doubled-version-in-base-url.json": [("properties/base_url/not", "/v1/v1")],
    "provider-config.v1/endpoint-path-in-base-url.json": [("properties/base_url/not", "/chat/completions")],
    "provider-config.v1/first-party-over-http.json": [("allOf/N/then/properties/provider_kind/enum", "openai_responses"),
                                                      ("allOf/N/then/properties/base_url/pattern", "^https://")],
    "provider-config.v1/http-local-declared-hosted.json": [("allOf/N/then/properties/privacy_classification/const", "local")],
    "provider-config.v1/http-to-a-public-name.json": [("allOf/N/then/properties/base_url/pattern", "gateway.example.com")],
    "provider-config.v1/http-to-dot-local-name.json": [("allOf/N/then/properties/base_url/pattern", "studio.local")],
    "provider-config.v1/http-without-opt-in.json": [("allOf/N/then/properties/allow_insecure_local_http/const", "True")],
    "provider-config.v1/query-in-base-url.json": [("properties/base_url/pattern", "?key=abc")],
    "provider-config.v1/unknown-provider-kind.json": [("properties/provider_kind/enum", "openai_assistants")],
}


def main(contracts: Path) -> int:
    problems = 0
    seen = set()
    for name in ["context-pack.v1", "provider-config.v1"]:
        schema = json.loads((contracts / "schemas" / f"{name}.schema.json").read_text(encoding="utf-8"))
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        for path in sorted((contracts / "fixtures" / name / "invalid").glob("*.json")):
            key = f"{name}/{path.name}"
            seen.add(key)
            errors = list(validator.iter_errors(json.loads(path.read_text(encoding="utf-8"))))
            print(f"{name}/invalid/{path.name}: {len(errors)} error(s)")
            expected = EXPECTED.get(key)
            if expected is None:
                print("    FAIL: no expected rule recorded for this fixture")
                problems += 1
            if not errors:
                print("    FAIL: the fixture validates")
                problems += 1
            for error in errors:
                rule = re.sub(r"allOf/\d+", "allOf/N", "/".join(map(str, error.absolute_schema_path)))
                print(f"    rule {rule} at /{'/'.join(map(str, error.absolute_path))}: {error.message[:160]}")
                if expected is not None and not any(rule == want and text in error.message for want, text in expected):
                    print("    FAIL: this error is not from the rule the fixture is named for")
                    problems += 1
            if expected is not None:
                for want, text in expected:
                    if not any(re.sub(r"allOf/\d+", "allOf/N", "/".join(map(str, e.absolute_schema_path))) == want for e in errors):
                        print(f"    FAIL: expected an error from {want}")
                        problems += 1
    for missing in sorted(set(EXPECTED) - seen):
        print(f"FAIL: expected fixture {missing} does not exist")
        problems += 1
    print(f"checked {len(seen)} invalid fixtures: {'each fails only for its named rule' if not problems else f'{problems} problem(s)'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
