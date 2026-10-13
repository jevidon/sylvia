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

## Ownership

Each file has one owner so parallel work never edits the same contract. Another workstream that needs a change asks the owner, who makes it under the versioning rule above. `instances.json` is shared: each owner adds only the rows for its own instance files.

At M0 integration (13 October 2026) the Stage 0 contracts moved to the milestone that builds on them (plan Section 21.2). The Stage 0 owner wrote the v1 file; the owner after M0 changes it from now on.

| Contract | Stage 0 owner (wrote v1) | Owner after M0 |
| --- | --- | --- |
| `openapi/source-service.v1.yaml`, `transfer-manifest`, `pairing-payload`, `pair-request`, `pair-response`, `capabilities`, `catalog-page`, `device-inbox-page`, `receipt`, `error` | G0.2 transfer spike | M6 Mac/LAN/cable delivery |
| `import-handoff-manifest`, `sylviapack-manifest` | G0.3 intake spike | M2 direct ingestion (the wired-bundle UX in M6 reads `sylviapack-manifest` and asks M2 for changes) |
| `context-pack`, `provider-config` | G0.5 AI spike | M5 contextual AI |
| `backup-manifest` | G0.5 recovery spike | M1 durable foundation (backup infrastructure starts in M1; its user experience is accepted in M7) |
| `design-tokens` and `design/` | G0.6 design package | The `SylviaDesign` package owner. `design/` stays generated (never edited by hand), and a marker or vocabulary change follows plan Section 4.4.9 |
| `capture-envelope`, `anchor` (EPUB, PDF, text, audio) | Not written in Stage 0 | Contract consolidation after the G0.4 merge, before M3 and M4 start (plan 21.2: they proceed after the domain and anchor contracts stabilize). Inputs: the PDF anchor envelope in ADR-0005 with valid fixtures from `Docs/Stage0/evidence/G01-PDF/anchor-samples.json`, the EPUB locator evidence in ADR-0004 and `G01-EPUB.md`, and G0.4's audio anchor and excerpt record (ADR-0006 decisions 11, 13 and 14 and its Open items: one ordered list of file-local ranges, each bound to its member asset's ID and digest; the actual exported ranges with each range's source format; the excerpt format, AAC-LC 64 kb/s mono 44.1 kHz in .m4a; the timeline revision, for display only) |

After M0 integration the validator covers 15 schemas, 188 fixtures, 1 OpenAPI document and 1 listed instance (`Scripts/ci.sh contracts`).
