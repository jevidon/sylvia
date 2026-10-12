# G0.3 intake: progress log for resuming agents

Branch `m0-g03-intake`. Simulator: `Sylvia-M0-g03-intake` (iPhone 17, iOS 26.5), created with `sylvia_sim_udid`; other
runners pass `G03_SIM_NAME=<their own>` to the CI drop-in. Scratch files go under `.build/scratch/` in the worktree. In
this sandbox, `source` inside compound shell commands is refused; a small script that sources
Scripts/lib/{env,sim,xcodegen}.sh itself and then does the work helps.

## Status: review round 1 fixed (2026-10-11); device and human items pending

- Report: `Docs/Stage0/G03-Intake.md` (section "Changes after review round 1" maps each finding to its fix).
  ADR: `Docs/ADRs/0010-intake-handoff-and-wired-bundles.md` (Proposed). Device checklist:
  `Docs/Stage0/device-checklists/G03-Intake.md` (27 steps).
- Clean CI run (build products deleted first, `Scripts/ci.sh contracts g03-intake`, every step including the ZIP
  library evaluation): `ci-clean-run.log`. Evidence logs in this folder were collected from that run by
  `Spikes/G03-Intake/scripts/collect-evidence.sh`, except the one-off logs named in the report
  (`host-stall-detector-before-fix.log`, `simulator-open-with-in-place-experiment.log`,
  `simulator-files-app-observation.log`, `simulator-late-import-observation.log`, `simulator-markdown-type-import.log`,
  `generate-pack.log`).

## Round 1 fixes, in short

- Aggregate expansion limit and free-space check before extraction (R1-01); manifest paths 15 components and 512
  bytes, entry names 16 and 520 (R1-02).
- Parallel safety: per-test temporary directories removed after each test, per-run `mktemp` directories in the host
  scripts, `G03_SIM_NAME`, the UI test's SIGKILL limited to this simulator (R1-03).
- Files app share driven on the simulator and required (works once the harness has been launched after install).
  Open With lists no app with `LSSupportsOpeningDocumentsInPlace` = NO and lists the harness with YES (experiment;
  finding F6, product-owner question). Open-in through the system driven with `simctl openurl` (`sim-open-in.sh`,
  CI step 7) (R1-04, R1-07).
- Stall detector watched the wrong Progress field and cut off providers that were still sending; fixed and tested
  (finding F13). EPUB package folders get their own fallback. Checklist gaps closed (R1-05).
- Handoff inbox excluded from backup; imported bundles leave Documents; open-in `.sylviapack` goes to the bundle
  importer; Inbox copies removed whatever the outcome; single-file snapshots are APFS clones; the in-app test records
  the protection class a clone gets (R1-06, R1-07).
- Required-reason APIs recorded in ADR-0010 (R1-08). Kill test: copy time measured in one process (the first attempt
  used two Python processes and measured -0.00 s), only kills that left a partial copy count, at least 8 of 12 required
  (R1-09).
- The dependency probe and the ZIP library evaluation run in the CI drop-in (step 8).

## Next (for whoever continues)

- Device runs from the checklist (serialized device session).
- Product-owner and security-review open items listed at the end of the report.

## Known problems

- Xcode 27 prints "'<module>' is missing a dependency on '<module>' because dependency scan ... discovered a
  dependency" for IntakeKit's own package targets, although Package.swift declares them; `swift build` does not.
- One earlier UI run (before scan timing was logged) imported a 4 GiB handoff about 5 minutes after the share;
  instrumented runs since import within seconds. Unexplained; finding F11 in the report.
- The Files app's share sheet offers the extension only after the harness has been launched once since installation
  (finding F12); FilesAppUITests launches it first.
