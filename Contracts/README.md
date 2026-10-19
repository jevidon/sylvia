# Contracts

Portable, versioned descriptions of Sylvia's data and protocols (plan Sections 6.2, 15.3, 22.4 and Appendix A). They are what a future Android client, server or test harness implements, and they are checked on every change by `Scripts/ci.d/10-contracts.sh` (`Scripts/validate-contracts.py`).

## Layout

```text
Contracts/
  schemas/<name>.v<N>.schema.json       # JSON Schema draft 2020-12
  fixtures/<name>.v<N>/valid/*.json     # must validate
  fixtures/<name>.v<N>/invalid/*.json   # must fail, one reason per file, named for the reason
  fixtures/<name>.v<N>/semantic-invalid/*.json  # schema-valid, fail exactly one code-checked rule (anchor, capture-envelope; ADR-0016)
  fixtures/<name>.v<N>/mutations.json   # how each invalid or semantic-invalid fixture is made from a valid one and what it must fail with (anchor, capture-envelope)
  openapi/<service>.v<N>.yaml           # OpenAPI 3.1; may $ref ../schemas/*.schema.json
  design/                               # generated design-token export (plan 4.4.9, A.5)
  instances.json                        # {"<path under Contracts>": "<schema $id>"} for every other JSON file
```

## Rules

- **Identity.** A schema's `$id` is `urn:sylvia:schema:<name>:v<N>`, matching its file name. Schemas reference each other by that `$id`. The `urn:` form avoids implying a hosted domain.
- **Versioning.** Each payload carries `schema_version` (integer). Additive optional fields keep the version; removing a field, changing its meaning or tightening a constraint creates `v<N+1>` beside the old file. Readers tolerate unknown optional fields unless a schema says otherwise (plan 15.3).
- **Units.** Sizes and offsets are 64-bit integers in bytes. Durations and positions are integer milliseconds. Timestamps are RFC 3339 UTC strings (`date-time`). Text offsets state their unit (`unicode_scalar` for Sylvia-extracted text; native UTF-16 only inside adapter-opaque payloads). Digests are lowercase hex SHA-256. IDs are UUID strings generated on device, written in the canonical form: lowercase and hyphenated, 36 characters (plan 7.2, 7.3, 7.5).
- **Exceptions to the units rule, and differences between contracts** (recorded on 19 October 2026 from the M0 final review, contracts R1-02, R1-05 and R1-07; each is its owner's to keep, or to remove in a `v2` or, before a contract is first released, in `v1`):
  - *Seconds:* `error.v1`'s `retry_after_seconds` is whole seconds, as the HTTP `Retry-After` header it mirrors (on 429 `rate_limited` and 503 `preparing`; owner M6).
  - *Timestamps that are not UTC-only:* `import-handoff-manifest.v1` and `sylviapack-manifest.v1` give `created_at` only `format: date-time`, so they accept any RFC 3339 offset (their valid fixtures use `+13:00`) and a lowercase `t` or `z`; their writers emit UTC with `Z` (`HandoffManifest.swift`, `.iso8601`). Owner: M2. The UTC-only contracts also spell UTC three ways: `^...(\.[0-9]+)?Z$` (the G0.2 contracts), `^...(\.[0-9]{1,9})?Z$` (`anchor`, `capture-envelope`) and `date-time` with `Z$` (`backup-manifest`, `context-pack`), so a lowercase `t` passes the last two and fails the first two, and ten fraction digits fail `capture-envelope` alone (`Docs/Stage0/evidence/M0-Integration/final-fix/timestamp-forms.log`). One shared definition is for the owners to agree (M1, M5, M6).
  - *IDs that are not lowercase-only:* `context-pack.v1` and `provider-config.v1` accept upper case (owner M5; ADR-0016 open items), and the G0.3 contracts use `format: uuid`, whose valid fixtures are uppercase; this repository's validator does not hold `format: uuid` to the canonical form (it accepts a trailing brace, for example: integration log row 51, request (b)), while the G0.3 readers refuse anything but the 8-4-4-4-12 form, in either case (the schemas' descriptions; owner M2).
  - *Size bounds:* where a contract bounds a byte size or offset, it is 2^53 - 1 in the G0.2 contracts (a JSON-safe integer) and 2^63 - 1 in `backup-manifest`, `anchor` and `capture-envelope`; the G0.3 schemas give none, and their readers refuse a value above `UInt64`'s maximum (the schemas' descriptions). No ID or size is shared between these groups today.
- **Secrets.** No schema has a field for a credential, token, invitation secret or key material except the pairing exchange itself, and those fields are documented as never persisted outside Keychain (plan 14.2, 15.2, 17.3).
- **Patterns.** Every `pattern` is valid ECMA-262, JSON Schema's dialect, which JavaScript validators compile with the `u` flag, and valid in Python's `re`: no inline flag such as `(?i)`; write cases out (`[Kk]`). `Scripts/check-spike-anchors.py` checks every contract on each CI run (ADR-0016 section 1). Two patterns in `context-pack` and `provider-config` are recorded exceptions until their owner (M5) rewrites them (ADR-0016).
- **Fixtures.** Every schema has at least one valid and one invalid fixture. Example IDs and digests are fixtures, not real data. Fixture text comes from the public-domain sources in `Fixtures/LICENSES.md`.
- **Generated files.** The design token export is generated from `Packages/Design`, never edited by hand (plan A.5). The generator's output is checked against the committed file in CI.

## Ownership

Each file has one owner so parallel work never edits the same contract. Another workstream that needs a change asks the owner, who makes it under the versioning rule above. `instances.json` is shared: each owner adds only the rows for its own instance files.

At M0 integration (13 October 2026) the Stage 0 contracts moved to the milestone that builds on them (plan Section 21.2). The Stage 0 owner wrote the v1 file; the owner after M0 changes it from now on.

| Contract | Stage 0 owner (wrote v1) | Owner after M0 |
| --- | --- | --- |
| `openapi/source-service.v1.yaml`, `transfer-manifest`, `pairing-payload`, `pair-request`, `pair-response`, `capabilities`, `catalog-page`, `device-inbox-page`, `receipt`, `receipt-ack` (moved out of the OpenAPI document's inline `ReceiptAck` on 19 October 2026, unchanged), `error` | G0.2 transfer spike | M6 Mac/LAN/cable delivery |
| `import-handoff-manifest`, `sylviapack-manifest` | G0.3 intake spike | M2 direct ingestion (the wired-bundle UX in M6 reads `sylviapack-manifest` and asks M2 for changes) |
| `context-pack`, `provider-config` | G0.5 AI spike | M5 contextual AI |
| `backup-manifest` | G0.5 recovery spike | M1 durable foundation (backup infrastructure starts in M1; its user experience is accepted in M7) |
| `design-tokens` and `design/` | G0.6 design package | The `SylviaDesign` package owner. `design/` stays generated (never edited by hand), and a marker or vocabulary change follows plan Section 4.4.9 |
| `capture-envelope`, `anchor` (EPUB, PDF, text, audio) | M0 contract consolidation (ADR-0016, `Docs/Stage0/M0-contracts.md`) | M1 durable foundation (the domain schema these contracts serialize); M3, M4 and M5 ask M1 for changes. A new capture kind also needs the `SylviaDesign` owner (its kind mapping, checked by `Scripts/ci.d/11-capture-anchor-contracts.sh`) and plan 4.4.9 change control. Fixtures are written by `Scripts/contracts/make-contract-fixtures.py`; a new schema constraint or code rule needs a fixture that breaks it alone, which `Scripts/contracts/mutation-pass.py` checks in CI (ADR-0016 section 10). G0.4's audio anchor and excerpt record (ADR-0006 decisions 11, 13 and 14) is part of `anchor.v1` and `capture-envelope.v1` |

At M0 assembly (14 October 2026), with the contract consolidation (ADR-0016) and the gates' later review rounds merged, the validator covers 17 schemas, 644 fixtures, 1 OpenAPI document and 1 listed instance (`Scripts/ci.sh contracts`); `Scripts/check-spike-anchors.py` also checks the 57 semantic-invalid fixtures of `anchor.v1` and `capture-envelope.v1`, the expected failure of each invalid one, and every contract pattern as ECMA-262.

Since the M0 final fix (19 October 2026; `Docs/Stage0/integration-log.md` section 11): 18 schemas (`receipt-ack.v1` added) and 655 fixtures, 1 OpenAPI document and 1 instance; `anchor.v1` has 15 valid fixtures (three of them composed PDF selections, from the G0.1 PDF spike's `anchor-composed-samples.json`) and 20 semantic-invalid ones, `capture-envelope.v1` 31 valid, so the checker checks 59 semantic-invalid fixtures; its pattern check now also walks member names called `title` or `description`, and reads 101 patterns in 19 contract documents, `receipt-ack.v1`'s included (it had skipped the two under `title` properties of `catalog-page` and `device-inbox-page`).
