#!/usr/bin/env python3
"""Validate Sylvia's portable contracts.

Rules (Contracts/README.md):
  * Every schema is Contracts/schemas/<name>.v<N>.schema.json, JSON Schema draft 2020-12,
    with "$id" equal to "urn:sylvia:schema:<name>:v<N>". Schemas may $ref each other by $id.
  * Every schema has fixtures in Contracts/fixtures/<name>.v<N>/valid/*.json (must validate)
    and Contracts/fixtures/<name>.v<N>/invalid/*.json (must fail). At least one of each.
  * Every OpenAPI document in Contracts/openapi/*.yaml|*.yml|*.json is a valid OpenAPI 3.1 document.
  * Every other *.json under Contracts/ (for example the design token export) is listed in
    Contracts/instances.json as {"<path relative to Contracts>": "<schema $id>"} and validates.

Exit status is non-zero if anything fails.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate as validate_openapi
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

SCHEMA_DIALECT = "https://json-schema.org/draft/2020-12/schema"
NAME_RE = re.compile(r"^(?P<name>[a-z0-9]+(?:-[a-z0-9]+)*)\.v(?P<version>[1-9][0-9]*)\.schema\.json$")


def main(root: Path) -> int:
    errors: list[str] = []
    schemas_dir = root / "schemas"
    fixtures_dir = root / "fixtures"
    openapi_dir = root / "openapi"

    schemas: dict[str, tuple[Path, dict]] = {}  # stem "<name>.v<N>" -> (path, schema)
    by_id: dict[str, dict] = {}

    for path in sorted(schemas_dir.glob("*.json")):
        match = NAME_RE.match(path.name)
        if not match:
            errors.append(f"{rel(path, root)}: file name must be <name>.v<N>.schema.json")
            continue
        try:
            schema = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{rel(path, root)}: invalid JSON: {exc}")
            continue
        expected_id = f"urn:sylvia:schema:{match['name']}:v{match['version']}"
        if schema.get("$schema") != SCHEMA_DIALECT:
            errors.append(f"{rel(path, root)}: $schema must be {SCHEMA_DIALECT}")
        if schema.get("$id") != expected_id:
            errors.append(f"{rel(path, root)}: $id must be {expected_id}")
        try:
            Draft202012Validator.check_schema(schema)
        except Exception as exc:  # jsonschema.SchemaError
            errors.append(f"{rel(path, root)}: not a valid draft 2020-12 schema: {first_line(exc)}")
            continue
        stem = f"{match['name']}.v{match['version']}"
        schemas[stem] = (path, schema)
        by_id[expected_id] = schema

    registry = Registry().with_resources(
        (schema_id, Resource.from_contents(schema, default_specification=DRAFT202012))
        for schema_id, schema in by_id.items()
    )

    def validator_for(schema: dict) -> Draft202012Validator:
        return Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())

    checked_fixtures = 0
    for stem, (path, schema) in schemas.items():
        fixture_root = fixtures_dir / stem
        valid = sorted((fixture_root / "valid").glob("*.json"))
        invalid = sorted((fixture_root / "invalid").glob("*.json"))
        if not valid:
            errors.append(f"{rel(path, root)}: no fixtures in fixtures/{stem}/valid/")
        if not invalid:
            errors.append(f"{rel(path, root)}: no fixtures in fixtures/{stem}/invalid/")
        validator = validator_for(schema)
        for fixture in valid:
            instance = load_json(fixture, root, errors)
            if instance is None:
                continue
            problems = sorted(validator.iter_errors(instance), key=lambda e: list(e.absolute_path))
            if problems:
                errors.append(f"{rel(fixture, root)}: expected valid, got: {describe(problems[0])}")
            checked_fixtures += 1
        for fixture in invalid:
            instance = load_json(fixture, root, errors)
            if instance is None:
                continue
            if validator.is_valid(instance):
                errors.append(f"{rel(fixture, root)}: expected invalid, but it validates")
            checked_fixtures += 1

    if fixtures_dir.exists():
        for directory in sorted(p for p in fixtures_dir.iterdir() if p.is_dir()):
            if directory.name not in schemas:
                errors.append(f"{rel(directory, root)}: fixture directory has no matching schema")

    checked_openapi = 0
    if openapi_dir.exists():
        for path in sorted(p for p in openapi_dir.iterdir() if p.suffix in {".yaml", ".yml", ".json"}):
            try:
                document = yaml.safe_load(path.read_text(encoding="utf-8"))
                if not str(document.get("openapi", "")).startswith("3.1"):
                    errors.append(f"{rel(path, root)}: must declare openapi 3.1.x")
                validate_openapi(document, base_uri=path.resolve().as_uri())
                checked_openapi += 1
            except Exception as exc:
                errors.append(f"{rel(path, root)}: invalid OpenAPI: {first_line(exc)}")

    instances_path = root / "instances.json"
    listed: dict[str, str] = {}
    if instances_path.exists():
        listed = load_json(instances_path, root, errors) or {}
    skip = {schemas_dir, fixtures_dir, openapi_dir}
    checked_instances = 0
    for path in sorted(root.rglob("*.json")):
        if path == instances_path or any(parent in skip for parent in path.parents):
            continue
        key = path.relative_to(root).as_posix()
        schema_id = listed.get(key)
        if schema_id is None:
            errors.append(f"{key}: not listed in instances.json")
            continue
        schema = by_id.get(schema_id)
        if schema is None:
            errors.append(f"{key}: instances.json names unknown schema {schema_id}")
            continue
        instance = load_json(path, root, errors)
        if instance is None:
            continue
        problems = sorted(validator_for(schema).iter_errors(instance), key=lambda e: list(e.absolute_path))
        if problems:
            errors.append(f"{key}: {describe(problems[0])}")
        checked_instances += 1
    for key in listed:
        if not (root / key).exists():
            errors.append(f"instances.json lists missing file {key}")

    print(
        f"schemas: {len(schemas)}  fixtures: {checked_fixtures}  "
        f"openapi: {checked_openapi}  instances: {checked_instances}"
    )
    for error in errors:
        print(f"error: {error}")
    return 1 if errors else 0


def load_json(path: Path, root: Path, errors: list[str]):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"{rel(path, root)}: invalid JSON: {exc}")
        return None
    except ValueError as exc:
        # Not UTF-8 (UnicodeDecodeError), or an integer longer than Python's conversion limit: an error line, not a
        # traceback (G0.3 report, requests to the validator's owner, item c).
        errors.append(f"{rel(path, root)}: cannot be read as UTF-8 JSON: {first_line(exc)}")
        return None


def describe(error) -> str:
    location = "/".join(str(part) for part in error.absolute_path) or "(root)"
    return f"{location}: {error.message}"


def first_line(exc: Exception) -> str:
    return str(exc).strip().splitlines()[0] if str(exc).strip() else type(exc).__name__


def rel(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


if __name__ == "__main__":
    contracts = Path(sys.argv[1] if len(sys.argv) > 1 else "Contracts").resolve()
    sys.exit(main(contracts))
