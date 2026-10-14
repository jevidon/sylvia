#!/usr/bin/env python3
"""Weakens the anchor and capture-envelope contracts one constraint at a time and reports any weakening no fixture
notices (ADR-0016, M0-contracts.md; review findings R1-01 and R2-01). Run by Scripts/ci.d/11-capture-anchor-contracts.sh
on every change and by the clean evidence run.

    python3 -I Docs/Stage0/evidence/M0-contracts/commands/mutation-pass.py [--jobs N] [--log <file>]

Each weakening is applied to a copy (the repository is never modified) and the checker's fixture checks are re-run
(Scripts/check-spike-anchors.py: every valid fixture valid and passing the code rules, every invalid fixture failing
with exactly its listed errors, every semantic-invalid fixture schema-valid and breaking only its rule). A weakening
that leaves every outcome unchanged "survives": no fixture protects that constraint.

Part 1, the schemas. For every constraint reachable from the two schemas' roots whose deletion can only accept more:
  * in a positive position: one entry of a `required` or `dependentRequired` list; a whole `const`, `enum`, `pattern`,
    `format`, `type`, `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `minLength`, `maxLength`,
    `minItems`, `maxItems`, `maxProperties`, `propertyNames`, `items`, `additionalProperties`, `not` or `$ref`; one
    member of an `allOf`; one branch of the `anyOf` inside a `not` (an exclusion); one `prefixItems` entry, made `{}`;
  * in a negative position (an `if` condition, whose narrowing applies its `then` less widely, or the inside of a
    `not`, whose narrowing excludes less): one value of an `enum` (R2-01: narrowing the transcript-origin condition to
    `machine_transcript` went unnoticed before).
  Polarity is tracked from where a definition is used, and a `$defs` entry is mutated where a `$ref` reaches it.
  Every deletion is protected (it must change an outcome) except generic bounds, which are reported but not required to
  be: a `type` other than `integer` or `number`, a `minLength` or `maxLength`, a `maxProperties`, a `maxItems` of 100
  or more and a `maximum` of 1,000 or more (size caps). Numeric types are protected: a fraction in a count, position or
  millisecond field, or a string in a coordinate, must be refused (R2-01).

Part 2, the code rules (Scripts/check-spike-anchors.py: surrogate_violations, anchor_violations, minimum_revision,
capture_violations, with their inner helpers). Each of these is applied in turn to a copy of the checker's source:
  * a statement that records a violation (`out.append(...)`, `out += ...`) is removed;
  * one operand of an `or` in an `if` that records a violation is replaced by False (a branch of a compound check);
  * an increment of the revision floor (`floor += ...`, rule C8) is removed;
  * a call of a helper that checks (`scalar_range(...)`, `walk(...)`) is removed, and `surrogate_violations(...)` is
    replaced by an empty list.
  Every one is protected: a code-rule branch that no semantic-invalid fixture alone detects fails the pass.

Protected survivors that are redundant by construction would be listed in EXPECTED_SURVIVORS with the reason; any
other protected survivor, or an expected one that no longer survives, makes the exit status non-zero.
"""
from __future__ import annotations

import argparse
import ast
import concurrent.futures
import copy
import importlib.util
import json
import os
import sys
import time
from pathlib import Path


def repository_root() -> Path:
    """The nearest parent holding Scripts/lib/env.sh, so the script runs unchanged wherever it lives (ADR-0016 asks
    to move it beside the checker)."""
    for parent in Path(__file__).resolve().parents:
        if (parent / "Scripts/lib/env.sh").is_file():
            return parent
    raise SystemExit("mutation-pass.py: not inside the Sylvia repository")


ROOT = repository_root()
CHECKER = ROOT / "Scripts/check-spike-anchors.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("checker", CHECKER)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

from jsonschema import Draft202012Validator  # noqa: E402  (the checker's environment)

DOCS = {checker.ANCHOR_ID: "anchor", checker.CAPTURE_ID: "capture-envelope"}
DELETABLE = ["const", "enum", "pattern", "format", "type", "minimum", "maximum", "exclusiveMinimum",
             "exclusiveMaximum", "minLength", "maxLength", "minItems", "maxItems", "maxProperties", "propertyNames",
             "items", "additionalProperties", "not", "$ref"]
SKIP = {"description", "title", "$comment", "$id", "$schema", "examples", "default"}
RULE_FUNCTIONS = ("surrogate_violations", "anchor_violations", "minimum_revision", "capture_violations")
CHECK_HELPERS = {"scalar_range", "walk"}

# Weakenings no fixture can notice because another rule already implies the constraint. Each is explained; the pass
# fails if one of them stops surviving (the reason changed) or another protected survivor appears.
EXPECTED_SURVIVORS: dict[str, str] = {}


# ----------------------------------------------------------------------------------------------- part 1: schemas


def is_bound(by_id: dict[str, dict], site: dict) -> bool:
    """A generic bound: reported, not required to be protected (see the module docstring)."""
    if site["kind"] != "schema" or site["op"] != "delete":
        return False
    keyword = site["arg"]
    value = node_at(by_id[site["doc"]], site["pointer"])[keyword]
    if keyword == "type":
        return value not in ("integer", "number")
    return (keyword in {"minLength", "maxLength", "maxProperties"}
            or (keyword == "maxItems" and value >= 100) or (keyword == "maximum" and value >= 1000))


def escape(token) -> str:
    return str(token).replace("~", "~0").replace("/", "~1")


def node_at(document, pointer: str):
    node = document
    for part in checker.pointer_parts(pointer) if pointer else []:
        node = node[int(part)] if isinstance(node, list) else node[part]
    return node


def resolve(doc_id: str, ref: str) -> tuple[str, str]:
    """A $ref of these schemas: `#/$defs/x`, `urn:...`, or `urn:...#/$defs/x`."""
    target, _, fragment = ref.partition("#")
    return (target or doc_id), fragment


def schema_sites(by_id: dict[str, dict]) -> list[dict]:
    """Every weakening of part 1 reachable from the two roots, deduplicated by (document, pointer, operation)."""
    found: dict[tuple, dict] = {}
    visited: set[tuple] = set()

    def note(doc_id: str, pointer: str, op: str, arg=None) -> None:
        key = (doc_id, pointer, op, json.dumps(arg))
        found.setdefault(key, {"kind": "schema", "doc": doc_id, "pointer": pointer, "op": op, "arg": arg})

    def walk(doc_id: str, pointer: str, positive: bool) -> None:
        if (doc_id, pointer, positive) in visited or doc_id not in DOCS:
            return
        visited.add((doc_id, pointer, positive))
        node = node_at(by_id[doc_id], pointer)
        if not isinstance(node, dict):
            return
        if positive:
            for kw in DELETABLE:
                if kw in node:
                    note(doc_id, pointer, "delete", kw)
            for name in node.get("required", []):
                note(doc_id, pointer, "required", name)
            for key, deps in node.get("dependentRequired", {}).items():
                for dep in deps:
                    note(doc_id, pointer, "dependentRequired", [key, dep])
            for i, _ in enumerate(node.get("allOf", [])):
                note(doc_id, pointer, "allOf-member", i)
            for i, _ in enumerate(node.get("prefixItems", [])):
                note(doc_id, pointer, "prefixItems-entry", i)
            branches = node.get("not", {}).get("anyOf") if isinstance(node.get("not"), dict) else None
            for i, _ in enumerate(branches or []):
                note(doc_id, pointer, "not-branch", i)
        else:
            for value in node.get("enum", []):
                note(doc_id, pointer, "enum-value", value)
        for k, v in node.items():
            if k in SKIP or k in {"required", "dependentRequired", "enum", "const", "$defs"}:
                continue
            here = f"{pointer}/{escape(k)}"
            if k in {"not", "if"}:
                walk(doc_id, here, not positive)
            elif k in {"then", "else", "items", "contains", "additionalProperties", "propertyNames"}:
                walk(doc_id, here, positive)
            elif k in {"allOf", "anyOf", "oneOf", "prefixItems"}:
                for i in range(len(v)):
                    walk(doc_id, f"{here}/{i}", positive)
            elif k in {"properties", "patternProperties"}:
                for name in v:
                    walk(doc_id, f"{here}/{escape(name)}", positive)
            elif k == "$ref":
                target, fragment = resolve(doc_id, v)
                walk(target, fragment, positive)

    for doc_id in DOCS:
        walk(doc_id, "", True)
    return list(found.values())


def apply_schema(by_id: dict[str, dict], site: dict) -> dict[str, dict]:
    mutated = dict(by_id)
    doc = copy.deepcopy(by_id[site["doc"]])
    node = node_at(doc, site["pointer"])
    op, arg = site["op"], site["arg"]
    if op == "delete":
        del node[arg]
    elif op == "required":
        node["required"] = [n for n in node["required"] if n != arg]
        if not node["required"]:
            del node["required"]
    elif op == "dependentRequired":
        key, dep = arg
        node["dependentRequired"][key] = [d for d in node["dependentRequired"][key] if d != dep]
        if not node["dependentRequired"][key]:
            del node["dependentRequired"][key]
        if not node["dependentRequired"]:
            del node["dependentRequired"]
    elif op == "allOf-member":
        del node["allOf"][arg]
        if not node["allOf"]:
            del node["allOf"]
    elif op == "prefixItems-entry":
        node["prefixItems"][arg] = {}
    elif op == "not-branch":
        del node["not"]["anyOf"][arg]
    elif op == "enum-value":
        node["enum"] = [v for v in node["enum"] if v != arg]
    mutated[site["doc"]] = doc
    return mutated


# ----------------------------------------------------------------------------------------------- part 2: code rules


def records_violation(statement: ast.stmt) -> bool:
    """`out.append(...)` or `out += ...`."""
    if isinstance(statement, ast.AugAssign):
        return isinstance(statement.target, ast.Name) and statement.target.id == "out"
    if isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Call):
        f = statement.value.func
        return isinstance(f, ast.Attribute) and f.attr == "append" and isinstance(f.value, ast.Name) and f.value.id == "out"
    return False


def rule_functions(tree: ast.Module):
    return [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in RULE_FUNCTIONS]


def rule_sites(source: str) -> list[dict]:
    """Every weakening of part 2, located by node type, line and column in the checker's source."""
    lines = source.split("\n")  # not splitlines(): the checker's White_Space class holds U+0085, U+2028 and U+2029
    sites = []

    def add(fn, node, op, arg=None, text=None):
        snippet = text if text is not None else lines[node.lineno - 1].strip()
        sites.append({"kind": "rule", "op": op, "arg": arg, "type": type(node).__name__, "line": node.lineno,
                      "col": node.col_offset, "where": f"{fn.name} line {node.lineno}", "text": snippet[:110]})

    for fn in rule_functions(ast.parse(source)):
        for node in ast.walk(fn):
            if isinstance(node, ast.stmt) and records_violation(node):
                add(fn, node, "drop-violation")
            elif isinstance(node, ast.AugAssign) and isinstance(node.target, ast.Name) and node.target.id == "floor":
                add(fn, node, "drop-increment")
            elif (isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
                  and isinstance(node.value.func, ast.Name) and node.value.func.id in CHECK_HELPERS):
                add(fn, node, "drop-helper-call")
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "surrogate_violations":
                add(fn, node, "empty-surrogate-check")
            elif (isinstance(node, ast.If) and isinstance(node.test, ast.BoolOp) and isinstance(node.test.op, ast.Or)
                  and any(records_violation(s) for s in node.body)):
                for k, operand in enumerate(node.test.values):
                    add(fn, node, "drop-or-operand", k, f"operand {k}: {ast.unparse(operand)[:100]}")
    return sites


class RuleMutator(ast.NodeTransformer):
    def __init__(self, site: dict) -> None:
        self.site = site
        self.applied = False

    def matches(self, node: ast.AST) -> bool:
        return (type(node).__name__ == self.site["type"] and getattr(node, "lineno", None) == self.site["line"]
                and getattr(node, "col_offset", None) == self.site["col"])

    def visit(self, node):
        node = self.generic_visit(node)
        if not self.matches(node):
            return node
        op = self.site["op"]
        if op in {"drop-violation", "drop-increment", "drop-helper-call"}:
            self.applied = True
            return ast.copy_location(ast.Pass(), node)
        if op == "empty-surrogate-check":
            self.applied = True
            return ast.copy_location(ast.List(elts=[], ctx=ast.Load()), node)
        if op == "drop-or-operand":
            index = self.site["arg"]
            node.test.values[index] = ast.copy_location(ast.Constant(False), node.test.values[index])
            self.applied = True
        return node


def mutant_checker(source: str, site: dict) -> dict:
    tree = ast.parse(source)
    mutator = RuleMutator(site)
    tree = ast.fix_missing_locations(mutator.visit(tree))
    if not mutator.applied:
        raise RuntimeError(f"mutation not applied: {site}")
    namespace = {"__name__": "checker_mutant", "__file__": str(CHECKER)}
    exec(compile(tree, f"{CHECKER} (mutant)", "exec"), namespace)  # the repository's own checker, changed in memory
    return namespace


# ----------------------------------------------------------------------------------------------- running


def label(site: dict) -> str:
    if site["kind"] == "rule":
        return f"checker {site['where']}: {site['op']}: {site['text']}"
    op, arg = site["op"], site["arg"]
    if op == "dependentRequired":
        what = f"dependentRequired {arg[0]} -{arg[1]}"
    else:
        what = {"delete": f"delete {arg}", "required": f"required -{arg}", "prefixItems-entry": f"prefixItems[{arg}] -> {{}}",
                "allOf-member": f"allOf member {arg}", "not-branch": f"not.anyOf branch {arg}",
                "enum-value": f"enum -{json.dumps(arg)}"}[op]
    return f"{DOCS[site['doc']]}#{site['pointer'] or '/'}: {what}"


KINDS = None
SCHEMAS = None


def outcome(schemas, rules_module: dict, kinds) -> list[str]:
    """The checker's fixture problems under these schemas, code rules and known kinds (empty: nothing noticed). The
    known kinds are read from the schemas under test, as the checker reads them."""
    profiles = {"anchor": lambda d: checker.writer_profile_violations(kinds, None, [d]),
                "capture": lambda d: checker.writer_profile_violations(kinds, d, d["anchors"])}
    problems: list[str] = []
    for stem, key, rules in (("anchor.v1", "anchor", rules_module["anchor_violations"]),
                             ("capture-envelope.v1", "capture", rules_module["capture_violations"])):
        problems += checker.fixture_outcomes(ROOT, stem, key, schemas, rules, profiles[key])[1]
    return problems


def run_site(site: dict) -> tuple[str, str, str]:
    if site["kind"] == "schema":
        mutated = apply_schema(checker.load_schemas(ROOT), site)
        try:
            Draft202012Validator.check_schema(mutated[site["doc"]])
        except Exception as exc:  # jsonschema.SchemaError
            return label(site), "skipped", f"not a valid schema after the deletion: {str(exc).splitlines()[0]}"
        schemas, rules, kinds = checker.Schemas(mutated), vars(checker), checker.Kinds(mutated)
    else:
        schemas, rules, kinds = SCHEMAS, mutant_checker(CHECKER.read_text(encoding="utf-8"), site), KINDS
    try:
        problems = outcome(schemas, rules, kinds)
    except Exception as exc:  # a mutant that crashes on a fixture is noticed, and reported as such
        return label(site), "killed", f"crashed: {type(exc).__name__}: {exc}"
    return label(site), "killed" if problems else "survived", problems[0] if problems else ""


def init_worker() -> None:
    global KINDS, SCHEMAS
    KINDS = checker.Kinds(checker.load_schemas(ROOT))
    SCHEMAS = checker.Schemas(checker.load_schemas(ROOT))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()
    init_worker()
    by_id = checker.load_schemas(ROOT)
    baseline = outcome(SCHEMAS, vars(checker), KINDS)
    lines = [f"schemas: {', '.join(sorted(DOCS.values()))}; code rules: {', '.join(RULE_FUNCTIONS)}; baseline fixture "
             f"problems: {len(baseline)}"]
    if baseline:
        lines += [f"baseline problem: {p}" for p in baseline]
        print("\n".join(lines))
        return 1
    all_sites = sorted(schema_sites(by_id), key=label) + sorted(
        rule_sites(CHECKER.read_text(encoding="utf-8")), key=lambda s: (s["line"], s["col"], s["op"], str(s["arg"])))
    bounds = {label(s) for s in all_sites if is_bound(by_id, s)}
    started = time.monotonic()
    if args.jobs > 1:
        with concurrent.futures.ProcessPoolExecutor(max_workers=args.jobs, initializer=init_worker) as pool:
            results = list(pool.map(run_site, all_sites, chunksize=4))
    else:
        results = [run_site(s) for s in all_sites]
    elapsed = time.monotonic() - started
    kinds = {label(s): s["kind"] for s in all_sites}
    protected = [r for r in results if r[0] not in bounds]
    generic = [r for r in results if r[0] in bounds]
    survivors = [name for name, verdict, _ in protected if verdict == "survived"]
    unexpected = [s for s in survivors if s not in EXPECTED_SURVIVORS]
    stale = [s for s in EXPECTED_SURVIVORS if s not in survivors]
    for name, verdict, detail in results:
        if verdict == "skipped":
            lines.append(f"skipped: {name}: {detail}")

    def tally(rows) -> str:
        n = {v: sum(1 for _, verdict, _ in rows if verdict == v) for v in ("killed", "survived", "skipped")}
        return f"{len(rows)} ({n['killed']} noticed by a fixture, {n['survived']} survived, {n['skipped']} skipped)"

    schema_protected = [r for r in protected if kinds[r[0]] == "schema"]
    rule_protected = [r for r in protected if kinds[r[0]] == "rule"]
    enum_values = [r for r in schema_protected if ": enum -" in r[0]]
    numeric_types = [r for r in schema_protected if r[0].endswith(": delete type")]
    lines.append(f"part 1, schema constraints, protected: {tally(schema_protected)}; among them single enum values in "
                 f"an if condition or a not: {tally(enum_values)}; numeric types: {tally(numeric_types)}")
    lines.append(f"part 1, generic bounds (non-numeric type, string length, maxProperties, maxItems >= 100, maximum "
                 f">= 1000; reported, not required): {tally(generic)}")
    lines.append(f"part 2, code-rule checks, protected: {tally(rule_protected)}")
    crashed = [name for name, verdict, detail in results if detail.startswith("crashed:")]
    lines.append(f"noticed by crashing on a fixture rather than by an outcome: {len(crashed)}")
    lines.append(f"time: {elapsed:.0f} s with {args.jobs} job(s)")
    for s in survivors:
        reason = EXPECTED_SURVIVORS.get(s)
        lines.append(f"protected, survived{' (expected: ' + reason + ')' if reason else ' (NOT EXPECTED)'}: {s}")
    for s in stale:
        lines.append(f"expected to survive but noticed now (update EXPECTED_SURVIVORS): {s}")
    lines += [f"crashed: {name}" for name in crashed]
    lines += [f"generic bound, survived: {name}" for name, verdict, _ in generic if verdict == "survived"]
    if os.environ.get("MUTATIONS_VERBOSE"):
        lines += [f"{verdict}: {name}: {detail}" for name, verdict, detail in results if verdict == "killed"]
    lines.append(f"result: {'pass' if not unexpected and not stale else 'FAIL'}")
    text = "\n".join(lines)
    print(text)
    if args.log:
        args.log.write_text(text + "\n", encoding="utf-8")
    return 0 if not unexpected and not stale else 1


if __name__ == "__main__":
    sys.exit(main())
