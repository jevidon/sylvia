# G0.5 recovery spike: progress

Branch `m0-g05-recovery`. Read this first if you are resuming.

## History

- `c2795f2` (agent 1, usage limit): first sources. Reviewed and kept with fixes by agent 2.
- `d8bed70`..`0611906` (agent 2): spike package, host tests, contract, CI drop-in, simulator support, ADR-0003 draft.
- `757ca11` (agent 2, usage limit): ADR-0012, device checklist, first evidence logs, first `ci-clean-run.log`.
- `926090f` (agent 2, editor restart): restore-intent and installation-record hardening, crash-drill counting of in-transaction kills. Reviewed by agent 3: correct and complete.
- `08b8f0a`..`bdcba1f` (agent 3): tests for that behaviour, evidence logs, report, round-0 completion.
- `921a925`..`9bac285` and the final commit (review round 1 fixer): restore verifies the snapshot's real schema and opens it defensively (R1-01); class-setting copies and a class-B discriminating protection run (R1-02); excluded media reconciled with the snapshot (R1-03); unreadable directories fail bundle validation (R1-04); on-device-to-unavailable conversion tested (R1-05); canonical cover thumbnails in format v1 (R1-06); CI simulator override and shutdown (R1-07); fixture provenance recorded in `Spikes/G05-Recovery/FIXTURES.md` (R1-08, the shared `Fixtures/LICENSES.md` row is left to its owner); storage full on a real APFS volume (R1-09); the reader enforces the whole manifest contract (R1-10); SIGKILL restore crash drill (T47 gap).
- `6814c8e`..`8a88d0d` (review round 1 fixer, second agent after a usage-limit stop): reviewed the earlier fixer's WIP commits, added the `sqlite_stat*` note to ADR-0012, ran the clean CI run from `6814c8e`, and brought the report, ADR-0003 and ADR-0012 evidence up to that run.
- `fe11120`..final (review round 2 fixer): resumable failed-migration put-back with an intent, a missing-database guard (`libraryMissing`), step, I/O-error and bad-intent tests and a 240-iteration SIGKILL drill (R2-01); `RowCheck` for effective dates and `sqlite_sequence` in restore (R2-02); ADR-0003 and row 15 say the date format is checked in code (R2-03); persistent device probe and a rewritten checklist step 4 (R2-04); the drop-in fails without the class-B evidence line, and the `FileProtection.swift` comment is corrected (R2-05); Markdown includes capture-linked and unassociated conversations, and the drill checks every message (R2-06); `FIXTURES.md` names the public-domain quotations (R2-07; the shared `Fixtures/LICENSES.md` row is still left to its owner).

## Status of evidence (final)

- Clean run: `ci-clean-run.log`, from `9eadf30` (named in its header) with no changes to tracked files, after deleting `Spikes/G05-Recovery/.build` (including `.build/DerivedData`), `.build/g05-recovery`, `.build/ci-logs` and the old logs. The host screen was locked at start and end, so the run used `G05_ALLOW_MISSING_CLASS_B=1`: the class-B protection run and the inheritance probe were skipped (row 10 is pending), and the locked-host observation ran. Every file in `logs/` comes from that run; `logs/contracts-ci.log` is `Scripts/ci.sh contracts`, run by the same script straight after the drop-in and also appended to `ci-clean-run.log`. Commits after `9eadf30` change only the report, ADRs, this file and the logs.
- `simulator-persist-probe-smoke.log` is a separate, filtered simulator run of the T50 persistence probe's three modes from `1c6931b` (test sources unchanged since); it checks the probe's code and is not T50 evidence.
- `Docs/Stage0/G05-Recovery.md`, ADR-0003 and ADR-0012 cite the clean run's numbers.
- Device: all pending (checklist).

## Next

- Run `Scripts/ci.d/71-g05-recovery.sh` once with the Mac's screen unlocked (it now fails without the class-B evidence) and update row 10, ADR-0012's data-protection evidence and this file from that run.
- Remaining work is the device checklist (`Docs/Stage0/device-checklists/G05-Recovery.md`), the human sign-offs listed in the report's open questions, and copying the fixture row from `Spikes/G05-Recovery/FIXTURES.md` into `Fixtures/LICENSES.md`.

## Known problems

- None open in the tested code. Limits are stated as findings in the report.
