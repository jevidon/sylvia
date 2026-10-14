# G0.3 intake: progress log for resuming agents

Branch `m0-int-minors-g03-intake` (from the M0 integration branch at b354dc7): closes the final agent review's round 2
findings for G0.3, then the round 3 and round 4 reviews of those fixes. Simulator for this work:
`Sylvia-M0-minors-g03-intake` (iPhone 17, iOS 26.5), created with `sylvia_sim_udid` and deleted at the end of each task;
other runners pass `G03_SIM_NAME=<their own>` to the CI drop-in. Scratch files go under `.build/scratch/` in the
worktree. In this sandbox, `source` inside compound shell commands, `bash -c '...'`, `for` loops and some arguments
containing "|" are refused; a small script under `.build/scratch/` that sources Scripts/lib/{env,sim,xcodegen}.sh itself
and then does the work helps. The file-writing tools decode a `\uXXXX` written in their input into the character itself
(seen once in round 4): write escapes from a script with `chr(92)`, and check new files for raw non-ASCII characters.

## Status: review round 4 closed on host and simulator (2026-10-13); device and human items pending

- Report: `Docs/Stage0/G03-Intake.md` ("Changes after review round 4" maps R4-01 to R4-06 and the gate gaps to their
  changes and evidence; F16 now says what the checks show instead of claiming the readers accept nothing their schemas
  refuse; F19 is new: the manifest size limits). ADR: `Docs/ADRs/0010-intake-handoff-and-wired-bundles.md` (Proposed).
  Device checklist: `Docs/Stage0/device-checklists/G03-Intake.md` (32 steps, unchanged in round 4).
- Clean CI run: `Spikes/G03-Intake/scripts/clean-ci-run.sh` (deletes every G0.3 build product, then
  `Scripts/ci.sh contracts g03-intake`): `ci-clean-run.log`, commit 34fe383. The step logs in this folder were collected
  from it by `Spikes/G03-Intake/scripts/collect-evidence.sh`, except the one-off logs the report names (the
  `*-before-fix.log` files, `host-round4-before-fix.log`, `generator-overlap*.log`, the `simulator-*` observation and
  experiment logs, `generate-pack.log`, `contract-differential-sensitivity.log`, `contract-fixture-reasons.log`,
  `host-pack-writer-scaling.log`, `host-ci-contracts.log`).
- Commits after 34fe383 change only documentation and evidence.

## Round 4 fixes, in short

- R4-01 (blocker): Swift's String ==, Set, Dictionary, init(rawValue:) and JSONDecoder's member-name and enum matching
  are canonical equivalence, so a file group_id "WALDEN_" + U+212A found the group "WALDEN_K". The reader now checks a
  file's group_id against the pattern before the lookup; every comparison of manifest text is byte for byte
  (`PathBytes.equal`) or on pattern-checked ASCII; enums decode byte for byte (`decodeExactCase`). Tests:
  `PackCanonicalEquivalenceTests`, `CanonicalEquivalenceTests` (only U+037E, U+1FEF, U+212A are canonical twins of ASCII;
  no contract name holds ; ` or K). The audit also fixed `HandoffSession.cleanFilename` (Character-based "/" replace).
- R4-02: pack manifest limit 1 MiB -> 16 MiB (9,998 files at the path limit: 9,356,558 bytes; a 10,000-entry pack is
  accepted; PackWriter reaches it in 5.3 s, `host-pack-writer-scaling.log`); the extension refuses to commit a
  handoff.json over 256 KiB (`HandoffFailure.manifestTooLarge`); both schemas state the limits; `check-manifest`
  applies them via `PackManifest.decode(_:limits:)` and `HandoffManifest.read(contentsOf:)`.
- R4-03: `RFC3339` counts days with `daysFromCivil` (proleptic Gregorian), not Foundation's Calendar.
- R4-04: the stall timeout finishes the gate only with `onlyBeforeWork: true`; test seam `beforeStallTimeoutFires`.
- R4-05: the round 2 check and the round 3 differential are committed under `Spikes/G03-Intake/scripts/sensitivity/`
  (SHA-256 checked); the pre-F18 readers are a PathBytes mutation. Nine defects, all caught.
- R4-06: the drop-in's step 1 no longer runs fetch.sh outside the generator's lock; header reworded; fetch.sh request
  recorded in the report.
- The differential check (`contract_differential.py`) gained canonical-twin and size cases, a canonical-twin mutation,
  and part 3: every accepted created_at instant compared with Python's.
- `check-round4-before-fix.sh` reverts each fix in a private copy and shows its new tests failing
  (`host-round4-before-fix.log`).

## Earlier rounds, in short

- Round 3: strict JSON text check (`StrictJSON.swift`), nulls refused, canonical UUIDs, byte-level path separators
  (F18), the differential rebuilt with per-kind verdicts and seeded mutations, picked-file identity checks.
- Round 2: Cancel in every phase (`CancellationSignal`), raw Finder files and the document picker, string bounds in
  code points, the generator's lock.

## Next (for whoever continues)

- Device runs from the checklist (serialized device session).
- Product-owner, security-review and contract-tooling open items listed at the end of the report, and the shared-file
  requests to M0 integration (LICENSES.md counts and pin, Contracts/README.md total, fetch.sh) and the validator's owner.

## Known problems

- Xcode 27 prints "'<module>' is missing a dependency on '<module>' because dependency scan ... discovered a
  dependency" for IntakeKit's own package targets, although Package.swift declares them; `swift build` does not.
- One earlier UI run (before scan timing was logged) imported a 4 GiB handoff about 5 minutes after the share;
  instrumented runs since import within seconds. Unexplained; finding F11 in the report.
- The Files app's share sheet offers the extension only after the harness has been launched once since installation
  (finding F12); FilesAppUITests launches it first.
