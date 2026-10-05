# Contracts

Portable, versioned descriptions of Sylvia's data and protocols (plan Sections 6.2, 15.3, 22.4 and Appendix A). They are what a future Android client, server or test harness implements, and they are checked on every change by `Scripts/ci.d/10-contracts.sh` (`Scripts/validate-contracts.py`).

## Layout

```text
Contracts/
  schemas/<name>.v<N>.schema.json       # JSON Schema draft 2020-12
  fixtures/<name>.v<N>/valid/*.json     # must validate
  fixtures/<name>.v<N>/invalid/*.json   # must fail, one reason per file, named for the reason
  openapi/<service>.v<N>.yaml           # OpenAPI 3.1; may $ref ../schemas/*.schema.json
  design/                               # generated design-token export (plan 4.4.9, A.5)
  instances.json                        # {"<path under Contracts>": "<schema $id>"} for every other JSON file
```

## Rules

- **Identity.** A schema's `$id` is `urn:sylvia:schema:<name>:v<N>`, matching its file name. Schemas reference each other by that `$id`. The `urn:` form avoids implying a hosted domain.
- **Versioning.** Each payload carries `schema_version` (integer). Additive optional fields keep the version; removing a field, changing its meaning or tightening a constraint creates `v<N+1>` beside the old file. Readers tolerate unknown optional fields unless a schema says otherwise (plan 15.3).
- **Units.** Sizes and offsets are 64-bit integers in bytes. Durations and positions are integer milliseconds. Timestamps are RFC 3339 UTC strings (`date-time`). Text offsets state their unit (`unicode_scalar` for Sylvia-extracted text; native UTF-16 only inside adapter-opaque payloads). Digests are lowercase hex SHA-256. IDs are UUID strings generated on device (plan 7.2, 7.3, 7.5).
- **Secrets.** No schema has a field for a credential, token, invitation secret or key material except the pairing exchange itself, and those fields are documented as never persisted outside Keychain (plan 14.2, 15.2, 17.3).
- **Fixtures.** Every schema has at least one valid and one invalid fixture. Example IDs and digests are fixtures, not real data. Fixture text comes from the public-domain sources in `Fixtures/LICENSES.md`.
- **Generated files.** The design token export is generated from `Packages/Design`, never edited by hand (plan A.5). The generator's output is checked against the committed file in CI.

## Ownership during Stage 0

Each file has one owner so parallel work never edits the same contract.

| Contract | Owner |
| --- | --- |
| `openapi/source-service.v1.yaml`, `transfer-manifest`, `pairing-payload`, transfer receipts and capability payloads | G0.2 transfer spike |
| `sylviapack-manifest`, `import-handoff-manifest` | G0.3 intake spike |
| `context-pack`, `provider-config` | G0.5 AI spike |
| `backup-manifest` | G0.5 recovery spike |
| `design-tokens` and `design/` | G0.6 design package |
| `capture-envelope`, `anchor` (EPUB, PDF, text, audio) | Contract consolidation after G0.1 and G0.4 report their locator evidence |
